-- plugin/s3_edit.lua
--
-- 直接用 Vim 编辑远端加密文件：
--     nvim s3://hhb-vault/dev.vault.enc
--     nvim s3://hhb-vault/            # 列出远端文件
--     nvim +"S3Ls"                    # 同上，用配置里的 default bucket
--
-- 协议端点是 hhb-vault 这类极简 HTTP 代理（Lambda Function URL）：
--     GET  /files            -> { count, files:[{name,size,lastModified,etag}] }
--     GET  /files/<name>     -> 密文 + ETag / X-Vault-Sha256 / X-Vault-Device
--     PUT  /files/<name>     -> 必须带 If-Match 或 If-None-Match: *（强制条件写）
-- 没有 DELETE，没有 LIST 以外的浏览能力（详见 ~/Sources/AgentHome/vault）。
--
-- 设计要点：
--   * buffer 里永远只有明文；明文不落盘（noswapfile / noundofile），
--     临时文件（密文、明文、curl 配置）都在 finally 里删除
--   * token 通过 0600 的 curl 配置文件传给 curl，不出现在 argv（ps 看不到）
--   * 加解密由本插件调用 openssl 直接作用在临时文件上，密文不经过 buffer
--     的行/换行表示 —— 保证字节精确（见 AGENTS.md 的说明）
--   * 写失败一律保留 modified 状态，让 :e! 成为唯一恢复入口
--
-- 已知限制（Vim 侧无法拦截的部分）：
--   * `:w <别的路径>` 不会触发 BufWriteCmd，会把解密后的明文按默认权限写到本地；
--     需要“另存明文”时请自己注意路径与权限（本插件不提供该功能）
--   * 显式 `:wshada <file>` 会按 Neovim 自身行为写出寄存器内容（与 'shada' 取值无关）；
--     正常退出时 'shada' 已被本插件清空，不会写明文
--
-- 配置：~/.vim/local/s3.lua（local/ 已 gitignore）
--     return {
--       default = 'hhb-vault',
--       buckets = {
--         ['hhb-vault'] = { endpoint = 'https://<id>.lambda-url.<region>.on.aws',
--                           token = '<device token>',
--                           -- 或者 token_file = '~/.vault/mac-studio.token',
--         },
--       },
--     }

if vim.g.loaded_s3_edit == 1 then
  return
end
vim.g.loaded_s3_edit = 1

local api = vim.api
local fmt = string.format

local CONFIG_PATH = (vim.env.VIMHOME or vim.fn.stdpath('config')) .. '/local/s3.lua'

-- 与 pack/my/start/encrypt 保持一致；`-md md5` 是为了兼容既有密文，不要升级
local CIPHER = 'aes-256-cbc'
local CIPHER_OPTS = { '-salt', '-md', 'md5' }

-- 明文/密文双向的安全上限（服务端 body 上限 6MB）
local MAX_BODY = 6 * 1024 * 1024

-- openssl 与 encrypt.vim 用同一个（该插件硬编码 /usr/bin/openssl）
local OPENSSL = '/usr/bin/openssl'
if vim.fn.executable(OPENSSL) ~= 1 then
  OPENSSL = vim.fn.exepath('openssl')
end

--- 当前会话是否已关掉 viminfo / shada（s3 buffer 里是明文，不能进 shada）
local viminfo_saved = nil
local quitting = false

local function notify(msg, level)
  msg = 's3_edit: ' .. msg
  if (level or vim.log.levels.INFO) >= vim.log.levels.ERROR then
    -- nvim_err_writeln：既会红色显示，也会设 v:errmsg，让 :wq / 脚本能感知失败
    api.nvim_err_writeln(msg)
  else
    vim.notify(msg, level)
  end
end

local function err(msg)
  error(msg, 0)
end

-- ---------------------------------------------------------------- 配置

local function get_config()
  local chunk, lerr = loadfile(vim.fn.expand(CONFIG_PATH))
  if not chunk then
    err(fmt('无法加载配置 %s（%s）\n可参考 AGENTS.md 中的模板创建它', CONFIG_PATH, tostring(lerr)))
  end
  local ok, cfg = pcall(chunk)
  if not ok then
    err(fmt('配置 %s 执行出错：%s', CONFIG_PATH, tostring(cfg)))
  end
  if type(cfg) ~= 'table' or type(cfg.buckets) ~= 'table' then
    err(fmt('配置 %s 必须 return { default = "<bucket>", buckets = { ["<bucket>"] = {...} } }', CONFIG_PATH))
  end
  return cfg
end

local function bucket_names()
  local ok, cfg = pcall(get_config)
  if not ok then
    return {}
  end
  local names = vim.tbl_keys(cfg.buckets)
  table.sort(names)
  return names
end

--- 取某个 bucket 的 endpoint + token，配置不全时给出明确报错
local function get_remote(bucket)
  local cfg = get_config()
  local entry = cfg.buckets[bucket]
  if type(entry) ~= 'table' then
    local names = vim.tbl_keys(cfg.buckets)
    table.sort(names)
    err(fmt(
      'bucket %q 未配置（已配置：%s）\n在 %s 的 buckets 里加一条即可',
      bucket,
      #names > 0 and table.concat(names, ', ') or '(无)',
      CONFIG_PATH
    ))
  end
  if type(entry.endpoint) ~= 'string' or entry.endpoint == '' then
    err(fmt('bucket %q 缺少 endpoint', bucket))
  end

  local token = entry.token
  if type(token) ~= 'string' or token == '' then
    if type(entry.token_file) == 'string' and entry.token_file ~= '' then
      local path = vim.fn.expand(entry.token_file)
      local lines = vim.fn.readfile(path)
      token = (lines[1] or ''):gsub('%s+$', '')
    end
  end
  if type(token) ~= 'string' or token == '' then
    err(fmt('bucket %q 缺少 token（或 token_file）', bucket))
  end

  return { bucket = bucket, endpoint = (entry.endpoint:gsub('/+$', '')), token = token }
end

-- ---------------------------------------------------------------- URI / name

--- s3://<bucket>[/<name>]
local function parse_uri(uri)
  local bucket, rest = uri:match('^s3://([^/]+)/?(.*)$')
  if not bucket then
    err(fmt('无法解析 URI：%s（应为 s3://<bucket>/<name.enc>）', uri))
  end
  return bucket, (rest or '')
end

--- 与 Lambda 端点的白名单保持一致（NAME_RE: [A-Za-z0-9][A-Za-z0-9._-]{0,60}\.enc）
--- 注意：端点上限是 1+60+4 = 65，不是 67
local NAME_MAX = 65

local function check_name(name)
  if #name < 5 or #name > NAME_MAX then
    err(fmt('文件名长度必须在 5..%d 之间：%s', NAME_MAX, name))
  end
  if not name:match('^[A-Za-z0-9][A-Za-z0-9._-]*%.enc$') then
    err(fmt('文件名只允许 [A-Za-z0-9._-]、以字母或数字开头、以 .enc 结尾：%s', name))
  end
  if name:find('..', 1, true) then
    err(fmt('文件名不允许包含 ".."：%s', name))
  end
end

-- ---------------------------------------------------------------- 小工具

local function read_whole(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local data = f:read('*a')
  f:close()
  return data
end

local function file_size(path)
  local st = vim.uv.fs_stat(path)
  return st and st.size or nil
end

--- 文件最后一个字节是否是 \n（决定 buffer 的 'eol'，保证写回字节精确）
local function ends_with_newline(path)
  local f = io.open(path, 'rb')
  if not f then
    return false
  end
  local size = f:seek('end')
  if size == 0 then
    f:close()
    return false
  end
  f:seek('set', size - 1)
  local last = f:read(1)
  f:close()
  return last == '\n'
end

local function sha256_file(path)
  -- readblob -> Blob，二进制安全（Lua 字符串里的 NUL 在传给 Vim script 时会被截断）
  return vim.fn.sha256(vim.fn.readblob(path))
end

local function put_confidential(path, lines)
  -- 先以 0600 创建再写，避免“写入瞬间是可读权限”的窗口
  local fd = vim.uv.fs_open(path, 'w', 384) -- 0o600
  if not fd then
    err('无法创建临时文件：' .. path)
  end
  local ok, werr = pcall(vim.uv.fs_write, fd, table.concat(lines or {}, '\n'))
  vim.uv.fs_close(fd)
  vim.fn.setfperm(path, 'rw-------')
  if not ok then
    err('写临时文件失败：' .. tostring(werr))
  end
end

--- 两个文件是否字节相同（<= MAX_BODY，直接读进内存比较）
local function files_equal(a, b)
  if file_size(a) ~= file_size(b) then
    return false
  end
  return read_whole(a) == read_whole(b)
end

--- 临时文件工厂：建出来就是 0600，cleanup() 负责全部删除
local function temp_factory()
  local paths = {}
  local function tmp(suffix)
    local p = vim.fn.tempname() .. (suffix or '')
    put_confidential(p, {})
    paths[#paths + 1] = p
    return p
  end
  local function cleanup()
    for _, p in ipairs(paths) do
      vim.fn.delete(p)
    end
  end
  return tmp, cleanup
end

-- ---------------------------------------------------------------- HTTP

--- 转成 curl 配置文件的字符串字面量
local function curl_quote(s)
  return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
end

local function parse_headers(path)
  local headers = {}
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return headers
  end
  for _, line in ipairs(lines) do
    local k, v = line:match('^([%w%-]+):%s*(.-)%s*$')
    if k then
      headers[k:lower()] = v
    end
  end
  return headers
end

local function error_text(body_path)
  local body = body_path and read_whole(body_path) or ''
  if body == '' then
    return '空响应'
  end
  local ok, json = pcall(vim.json.decode, body)
  if ok and type(json) == 'table' and type(json.error) == 'string' then
    local msg = json.error
    if type(json.message) == 'string' and json.message ~= '' then
      msg = msg .. ': ' .. json.message
    end
    return msg
  end
  return body:sub(1, 200)
end

--- 发一个请求。返回 { status, headers, body=<临时文件路径或 nil>, cleanup() }
--- token 走 curl -K 配置文件（0600），不进 argv
local function http(opts)
  local base = vim.fn.tempname()
  local conf_path = base .. '.curl'
  local head_path = base .. '.head'
  local body_path = base .. '.body'

  local conf = { 'header = ' .. curl_quote('Authorization: Bearer ' .. opts.token) }
  put_confidential(conf_path, conf)
  -- 响应头/响应体也预建为 0600（curl 会保留已有文件的权限）
  put_confidential(head_path, {})
  put_confidential(body_path, {})

  local cmd = {
    'curl',
    '-sS',
    '-K', conf_path,
    '-o', body_path,
    '-D', head_path,
    '-w', '%{http_code}',
    '--connect-timeout', '10',
    '--max-time', tostring(opts.timeout or 30),
    '-X', opts.method,
  }
  if opts.method == 'GET' then
    -- 别让异常端点把整个响应先落盘（chunked 时 curl 仍会下完，但至少挡住带 Content-Length 的）
    vim.list_extend(cmd, { '--max-filesize', tostring(MAX_BODY * 2) })
  end
  for k, v in pairs(opts.headers or {}) do
    vim.list_extend(cmd, { '-H', k .. ': ' .. v })
  end
  if opts.body then
    vim.list_extend(cmd, { '--data-binary', '@' .. opts.body })
  end
  vim.list_extend(cmd, { '--url', opts.url })

  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(((opts.timeout or 30) + 15) * 1000)
  end)
  vim.fn.delete(conf_path)

  -- 响应头文件用完即删；响应体由调用方负责清理（下载内容要留着用）
  local function cleanup()
    vim.fn.delete(head_path)
  end

  if not ok or type(res) ~= 'table' then
    cleanup()
    vim.fn.delete(body_path)
    err('请求失败：' .. tostring(res))
  end
  if (res.signal and res.signal ~= 0) or res.code ~= 0 then
    local detail = (res.stderr or ''):gsub('%s+$', '')
    cleanup()
    vim.fn.delete(body_path)
    if res.signal and res.signal ~= 0 then
      err(fmt('请求超时或被中断（信号 %s）', tostring(res.signal)))
    end
    err(fmt('curl 失败（exit %s）：%s', tostring(res.code), detail ~= '' and detail or '无输出'))
  end

  local status = tonumber(vim.trim(res.stdout or ''))
  if not status then
    local detail = (res.stderr or ''):gsub('%s+$', '')
    cleanup()
    vim.fn.delete(body_path)
    err('无法解析 HTTP 状态码：' .. (detail ~= '' and detail or 'curl 无输出'))
  end

  return {
    status = status,
    headers = parse_headers(head_path),
    body = vim.uv.fs_stat(body_path) and body_path or nil,
    cleanup = cleanup,
  }
end

--- 非 2xx 时统一报错（含服务端 JSON 里的 error/message）
local function expect_ok(res, what)
  if res.status >= 200 and res.status < 300 then
    return
  end
  local detail = error_text(res.body)
  if res.status == 401 then
    err(fmt('%s：token 无效或已被吊销（401）', what))
  elseif res.status == 404 then
    err(fmt('%s：远端不存在（404）', what))
  elseif res.status == 409 then
    local reason = res.headers['x-vault-reason']
    if reason == 'already_exists' then
      err(fmt('%s：远端已存在同名文件，写入被拒绝（409 already_exists）', what))
    end
    err(fmt('%s：远端已被其它设备更新，写入被拒绝（409 %s）', what, reason or 'stale_etag'))
  elseif res.status == 413 then
    err(fmt('%s：文件超过服务端 6MB 上限（413）', what))
  elseif res.status == 428 then
    err(fmt('%s：缺少条件头（428，属插件 bug）', what))
  elseif res.status == 400 then
    err(fmt('%s：服务端拒绝（400）：%s', what, detail))
  else
    err(fmt('%s 失败（HTTP %d）：%s', what, res.status, detail))
  end
end

-- ---------------------------------------------------------------- 加解密

local function get_password(buf)
  local pw = vim.b[buf].s3_password
  if type(pw) ~= 'string' or pw == '' then
    -- 仅供自动化测试/脚本使用；不要在配置里保存密码
    pw = vim.g.s3_password
  end
  if type(pw) ~= 'string' or pw == '' then
    local ok, input = pcall(vim.fn.inputsecret, 'Password: ')
    if not ok then
      err('已取消（未输入密码）')
    end
    pw = input
  end
  if type(pw) ~= 'string' or pw == '' then
    err('密码为空，已取消')
  end
  vim.b[buf].s3_password = pw
  return pw
end

--- 对文件跑 openssl；mode = 'encrypt' | 'decrypt'
local function openssl_file(mode, src, dst, password)
  local base = vim.fn.tempname()
  local pass_path = base .. '.pw'
  put_confidential(pass_path, { password })

  local cmd = { OPENSSL, CIPHER }
  if mode == 'decrypt' then
    table.insert(cmd, '-d')
  end
  vim.list_extend(cmd, CIPHER_OPTS)
  vim.list_extend(cmd, { '-pass', 'file:' .. pass_path, '-in', src, '-out', dst })

  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(60000)
  end)
  vim.fn.delete(pass_path)
  if not ok or type(res) ~= 'table' then
    return false, tostring(res)
  end
  if res.code ~= 0 then
    return false, (res.stderr or ''):gsub('%s+$', '')
  end
  return true
end

-- ---------------------------------------------------------------- viminfo / shada

-- s3 buffer 里是明文，但 BufReadCmd 抑制了 BufReadPre，encrypt.vim 的 viminfo 保护
-- 不会生效（yank 的密码会进 shada）。这里自己管：首个 s3 buffer 清空 &viminfo，
-- 最后一个销毁时还原；退出时不还原（否则退出时写的 shada 会泄明文）。
local function disable_viminfo()
  if viminfo_saved == nil then
    viminfo_saved = vim.o.viminfo
    vim.o.viminfo = ''
  end
end

local function maybe_restore_viminfo(wiping_buf)
  if viminfo_saved == nil or quitting then
    return
  end
  for _, b in ipairs(api.nvim_list_bufs()) do
    if b ~= wiping_buf and api.nvim_buf_is_loaded(b) and api.nvim_buf_get_name(b):match('^s3://') then
      return
    end
  end
  vim.o.viminfo = viminfo_saved
  viminfo_saved = nil
end

-- ---------------------------------------------------------------- buffer 读写

--- 把文件内容按字节精确地放进 buffer
local function load_file_into_buffer(buf, path)
  local eol = ends_with_newline(path)
  api.nvim_buf_call(buf, function()
    vim.bo.bin = true
    vim.cmd('silent keepalt %delete _')
    vim.cmd('silent keepalt 0read ' .. vim.fn.fnameescape(path))
    -- :0read 之后那个空行是 %delete 留下的占位行
    if vim.fn.line('$') > 1 then
      vim.cmd('silent keepalt $delete _')
    end
    vim.bo.eol = eol
    vim.bo.bin = false
    vim.bo.modified = false
  end)
end

--- 把 buffer 内容逐字节写到临时文件
--- `++bin` 很关键：否则 `'fixendofline'` 会给无尾换行的明文补一个 <EOL>（不限制 'fileformat' 转换）
local function write_buffer_to_file(buf, path)
  api.nvim_buf_call(buf, function()
    vim.cmd('silent noautocmd keepalt write! ++bin ' .. vim.fn.fnameescape(path))
  end)
end

--- 去掉 .enc 后推断 filetype：先走内置探测，再回退到「是否存在同名 ftplugin」
local function set_filetype(buf, name)
  local base = name:gsub('%.enc$', '')
  local ok, ft = pcall(vim.filetype.match, { filename = base })
  if not ok then
    ft = nil
  end
  if not ft then
    local ext = base:match('%.([%w_-]+)$')
    if ext then
      local hits = api.nvim_get_runtime_file('ftplugin/' .. ext .. '.vim', false)
      vim.list_extend(hits, api.nvim_get_runtime_file('ftplugin/' .. ext .. '.lua', false))
      if #hits > 0 then
        ft = ext
      end
    end
  end
  if ft and ft ~= '' then
    vim.bo[buf].filetype = ft
  end
end

local function apply_buffer_options(buf)
  vim.bo[buf].swapfile = false
  vim.bo[buf].undofile = false
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].modifiable = true
  vim.bo[buf].readonly = false
end

-- ---------------------------------------------------------------- 列表

local function list_remote(buf, bucket)
  local remote = get_remote(bucket)
  local res = http({ method = 'GET', url = remote.endpoint .. '/files', token = remote.token })
  local ok_call, call_err = pcall(expect_ok, res, '列出远端文件')
  if not ok_call then
    res.cleanup()
    if res.body then
      vim.fn.delete(res.body)
    end
    err(call_err)
  end
  local body = res.body and read_whole(res.body) or ''
  res.cleanup()
  if res.body then
    vim.fn.delete(res.body)
  end

  local parsed_ok, data = pcall(vim.json.decode, body)
  if not parsed_ok or type(data) ~= 'table' or type(data.files) ~= 'table' then
    err('无法解析 /files 响应：' .. body:sub(1, 200))
  end

  -- 只接受符合白名单的 name：列表内容来自服务端，拼进 Ex 命令会被注入
  local files = {}
  for _, f in ipairs(data.files) do
    local name = tostring(f.name or '')
    local ok_name = pcall(check_name, name)
    if ok_name then
      files[#files + 1] = f
    end
  end

  local names = {}
  local lines = {}
  local width = 20
  for _, f in ipairs(files) do
    width = math.max(width, #tostring(f.name))
  end
  width = math.min(width, NAME_MAX)

  vim.list_extend(lines, {
    fmt('%-' .. width .. 's  %9s  %-19s  %s', 'NAME', 'SIZE', 'LAST-MODIFIED', 'ETAG'),
    fmt('%-' .. width .. 's  %9s  %-19s  %s', string.rep('-', width), '-' .. string.rep('-', 8),
      string.rep('-', 19), string.rep('-', 20)),
  })
  for _, f in ipairs(files) do
    local name = tostring(f.name)
    names[#names + 1] = name
    local mtime = tostring(f.lastModified or ''):sub(1, 19):gsub('T', ' ')
    vim.list_extend(lines, {
      fmt('%-' .. width .. 's  %9d  %-19s  %s', name, tonumber(f.size) or 0, mtime, tostring(f.etag or '')),
    })
  end
  if #files == 0 then
    vim.list_extend(lines, { '', '(远端为空)' })
  end

  api.nvim_buf_call(buf, function()
    vim.bo.buftype = 'nofile'
    vim.bo.swapfile = false
    vim.bo.undofile = false
    vim.bo.modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo.modified = false
    vim.bo.modifiable = false
    vim.bo.filetype = 's3list'
    vim.keymap.set('n', '<CR>', function()
      local row = vim.fn.line('.')
      local name = names[row - 2]
      if not name then
        return
      end
      -- 不用 :edit 字符串拼接（name 来自服务端）；nvim_cmd 走参数，不经过 Ex 解析
      api.nvim_cmd({ cmd = 'edit', args = { 's3://' .. bucket .. '/' .. name } }, {})
    end, { buffer = buf, desc = '打开远端文件' })
    vim.keymap.set('n', 'R', function()
      api.nvim_cmd({ cmd = 'edit', args = { 's3://' .. bucket .. '/' }, bang = true }, {})
    end, { buffer = buf, desc = '刷新列表' })
    vim.keymap.set('n', 'q', '<Cmd>close<CR>', { buffer = buf, desc = '关闭列表' })
  end)

  vim.b[buf].s3 = { bucket = bucket, endpoint = remote.endpoint, list = true }
end

-- ---------------------------------------------------------------- 读

local function read_remote(buf, uri)
  local bucket, name = parse_uri(uri)
  apply_buffer_options(buf)
  disable_viminfo()

  if name == '' or name == '/' then
    list_remote(buf, bucket)
    return
  end
  check_name(name)

  local remote = get_remote(bucket)
  local tmp, drop_temps = temp_factory()
  local keep_temps = {}   -- 响应体单独记账（http 返回的 body 也要删）

  local ok, problem = pcall(function()
    local res = http({ method = 'GET', url = remote.endpoint .. '/files/' .. name, token = remote.token })
    local ok_status, status_err = pcall(expect_ok, res, '读取远端文件')
    if res.body then
      keep_temps[#keep_temps + 1] = res.body
    end
    if res.status == 404 and not ok_status then
      -- 远端还没有这个文件：开一个空 buffer，:w 时用 If-None-Match: * 创建
      res.cleanup()
      vim.b[buf].s3 = { bucket = bucket, name = name, endpoint = remote.endpoint, etag = nil, exists = false }
      set_filetype(buf, name)
      vim.bo[buf].modified = false
      notify(fmt('远端还没有 %s，:w 将创建它', name), vim.log.levels.WARN)
      return
    end
    if not ok_status then
      res.cleanup()
      err(status_err)
    end

    local body_path = res.body
    if not body_path then
      res.cleanup()
      err('服务端返回空响应体')
    end
    local size = file_size(body_path) or 0
    if size > MAX_BODY then
      res.cleanup()
      err(fmt('文件过大（%d 字节），超过 6MB 上限', size))
    end

    local want_sha = res.headers['x-vault-sha256']
    local got_sha = sha256_file(body_path)
    if want_sha and want_sha ~= '' and want_sha:lower() ~= got_sha:lower() then
      res.cleanup()
      err(fmt('完整性校验失败：期望 %s，实得 %s', want_sha, got_sha))
    end

    local etag = res.headers['etag']
    if etag == '' then
      etag = nil
    end
    local device = res.headers['x-vault-device']
    res.cleanup()

    local plain_path = tmp('.plain')
    local ok_dec, dec_err = openssl_file('decrypt', body_path, plain_path, get_password(buf))
    if not ok_dec then
      -- 与 encrypt.vim 一致：解不开就锁死 buffer，避免把错误内容写回去；
      -- 同时丢掉密码，让 :e! 重新询问（重试就是打错了）
      vim.b[buf].s3_password = nil
      vim.bo[buf].modifiable = false
      vim.bo[buf].readonly = true
      err(fmt('解密失败（密码错误或文件不是 openssl 密文）：%s\nbuffer 已锁定，请用 :e! 重试', dec_err))
    end

    load_file_into_buffer(buf, plain_path)
    set_filetype(buf, name)
    vim.b[buf].s3 = {
      bucket = bucket,
      name = name,
      endpoint = remote.endpoint,
      etag = etag,
      exists = true,
      sha256 = got_sha,
      device = device,
      size = size,
    }
  end)

  for _, p in ipairs(keep_temps) do
    vim.fn.delete(p)
  end
  drop_temps()
  if not ok then
    err(problem)
  end
end

-- ---------------------------------------------------------------- 写

local function write_remote(buf)
  local st = vim.b[buf].s3
  if type(st) ~= 'table' or st.list then
    err('这个 buffer 不是远端文件（请用 :e s3://<bucket>/<name.enc> 打开）')
  end

  -- 用 buffer 名而不是 b:s3 作为写入目标：:saveas / :file 改名后两者会分叉
  local self_name = api.nvim_buf_get_name(buf)
  local uri_bucket, uri_name = parse_uri(self_name)
  if uri_bucket ~= st.bucket or uri_name ~= st.name then
    err(fmt(
      'buffer 名（%s）与远端状态（s3://%s/%s）不一致，写入被拒绝；请关闭后用 :e 重新打开',
      self_name,
      st.bucket,
      st.name
    ))
  end

  -- exists == false 才表示“远端确实没有这个文件”；其它情况没有 etag 就不能写
  local is_create = (st.exists == false)
  if not is_create and (type(st.etag) ~= 'string' or st.etag == '') then
    err('端点没有返回 ETag，无法安全写入（避免静默覆盖）；请 :e! 重新打开')
  end

  local remote = get_remote(st.bucket)
  local name = st.name
  check_name(name)

  local tmp, drop_temps = temp_factory()
  local was_modified = vim.bo[buf].modified

  local ok, problem = pcall(function()
    local plain_path = tmp('.plain')
    local cipher_path = tmp('.enc')
    write_buffer_to_file(buf, plain_path)

    local pw = get_password(buf)
    if is_create and not vim.g.s3_password and not vim.b[buf].s3_pw_confirmed then
      -- 新建时密码打错会产生一个永远解不开的远端对象，所以要求再输入一次
      local ok_in, again = pcall(vim.fn.inputsecret, 'Password (again): ')
      if not ok_in or type(again) ~= 'string' or again ~= pw then
        err('两次输入的密码不一致，写入被拒绝')
      end
      vim.b[buf].s3_pw_confirmed = true
    end

    local ok_enc, enc_err = openssl_file('encrypt', plain_path, cipher_path, pw)
    if not ok_enc then
      err('加密失败：' .. tostring(enc_err))
    end

    -- 自检：把刚加密的密文解回来，必须与明文逐字节相同（防止加解密管线失配）
    local check_path = tmp('.check')
    local ok_check, check_err = openssl_file('decrypt', cipher_path, check_path, pw)
    if not ok_check then
      err('加密自检失败（无法解回刚加密的内容）：' .. tostring(check_err))
    end
    if not files_equal(plain_path, check_path) then
      err('加密自检失败：解回的内容与明文不一致，写入被拒绝')
    end

    local size = file_size(cipher_path) or 0
    if size == 0 then
      err('加密结果为空，写入被拒绝')
    end
    if size > MAX_BODY then
      err(fmt('加密后 %d 字节，超过服务端 6MB 上限', size))
    end

    local headers = {
      ['Content-Type'] = 'application/octet-stream',
      ['X-Vault-Sha256'] = sha256_file(cipher_path),
    }
    if is_create then
      headers['If-None-Match'] = '*'
    else
      headers['If-Match'] = st.etag
    end

    local res = http({
      method = 'PUT',
      url = remote.endpoint .. '/files/' .. name,
      token = remote.token,
      headers = headers,
      body = cipher_path,
      timeout = 60,
    })
    local ok_status, status_err = pcall(expect_ok, res, '上传 ' .. name)
    local new_etag = res.headers['etag']
    local new_sha = res.headers['x-vault-sha256']
    res.cleanup()
    if res.body then
      vim.fn.delete(res.body)
    end
    if not ok_status then
      err(status_err
        .. '\n本地改动仍在 buffer 里。确认要放弃时用 :e! 重新拉取；'
        .. '需要保留内容请自己复制出去（注意本 buffer 里是明文）')
    end

    if new_etag == nil or new_etag == '' then
      -- 上传成功但端点没给 etag：不假装同步成功，清掉 baseline 逼用户重新打开
      st.etag = nil
      st.exists = true
      vim.b[buf].s3 = st
      vim.bo[buf].modified = false
      notify(fmt('已上传 %s，但响应里没有 ETag；请 :e! 重新打开后再继续编辑', name), vim.log.levels.WARN)
      return
    end

    st.etag = new_etag
    st.exists = true
    st.sha256 = (new_sha and new_sha ~= '') and new_sha or headers['X-Vault-Sha256']
    st.size = size
    vim.b[buf].s3 = st   -- Lua table 的修改必须写回 b: 变量
    vim.bo[buf].modified = false
    notify(fmt('已上传 %s（etag %s）', name, tostring(new_etag):gsub('"', ''):sub(1, 12)))
  end)

  drop_temps()
  if not ok then
    -- 写失败不能把“本来是干净的 buffer”标成 modified（否则 :q 被无理由拒绝）
    vim.bo[buf].modified = was_modified
    err(problem)
  end
end

-- ---------------------------------------------------------------- autocmd / commands

local group = api.nvim_create_augroup('s3_edit', { clear = true })

api.nvim_create_autocmd('BufReadCmd', {
  group = group,
  pattern = 's3://*',
  callback = function(ev)
    local ok, problem = pcall(read_remote, ev.buf, api.nvim_buf_get_name(ev.buf))
    if not ok then
      vim.bo[ev.buf].buftype = 'nofile' -- 读失败时禁止误 :w 覆盖
      notify(tostring(problem), vim.log.levels.ERROR)
    end
  end,
  desc = '通过 HTTP 端点读取 s3:// 对象',
})

api.nvim_create_autocmd('BufWriteCmd', {
  group = group,
  pattern = 's3://*',
  callback = function(ev)
    local ok, problem = pcall(write_remote, ev.buf)
    if not ok then
      notify(tostring(problem), vim.log.levels.ERROR)
    end
  end,
  desc = '通过 HTTP 端点写入 s3:// 对象',
})

-- s3 buffer 消失时恢复 viminfo（退出时不恢复，见 maybe_restore_viminfo）
api.nvim_create_autocmd({ 'BufWipeout', 'BufDelete' }, {
  group = group,
  pattern = 's3://*',
  callback = function(ev)
    maybe_restore_viminfo(ev.buf)
  end,
  desc = '最后一个 s3 buffer 消失时恢复 viminfo',
})

api.nvim_create_autocmd('VimLeavePre', {
  group = group,
  callback = function()
    quitting = true
  end,
  desc = '退出时不再恢复 viminfo，避免 shada 泄明文',
})

api.nvim_create_user_command('S3Ls', function(opts)
  local ok, bucket = pcall(function()
    if opts.args ~= '' then
      return opts.args
    end
    local cfg = get_config()
    if type(cfg.default) ~= 'string' or cfg.default == '' then
      err(fmt('未指定 bucket，且 %s 里没有 default', CONFIG_PATH))
    end
    return cfg.default
  end)
  if not ok then
    notify(tostring(bucket), vim.log.levels.ERROR)
    return
  end
  -- bucket 名同样不拼 Ex 字符串
  if type(bucket) ~= 'string' or not bucket:match('^[A-Za-z0-9][A-Za-z0-9._-]*$') then
    notify(fmt('bucket 名不合法：%s', tostring(bucket)), vim.log.levels.ERROR)
    return
  end
  api.nvim_cmd({ cmd = 'edit', args = { 's3://' .. bucket .. '/' } }, {})
end, {
  nargs = '?',
  complete = function()
    return bucket_names()
  end,
  desc = '列出远端 bucket 里的加密文件',
})

api.nvim_create_user_command('S3Info', function()
  local buf = api.nvim_get_current_buf()
  local st = vim.b[buf].s3
  if type(st) ~= 'table' then
    notify('当前 buffer 不是 s3:// 对象', vim.log.levels.WARN)
    return
  end
  local lines = {
    'bucket:   ' .. tostring(st.bucket),
    'endpoint: ' .. tostring(st.endpoint),
    'etag:     ' .. tostring(st.etag or (st.exists == false and '(无，:w 将创建)' or '(端点未返回)')),
    'sha256:   ' .. tostring(st.sha256 or '-'),
    'device:   ' .. tostring(st.device or '-'),
    'size:     ' .. tostring(st.size or '-'),
  }
  if st.list then
    lines = { 'bucket:   ' .. tostring(st.bucket), 'endpoint: ' .. tostring(st.endpoint),
      'type:     文件列表' }
  else
    table.insert(lines, 1, 'name:     ' .. tostring(st.name))
  end
  api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
end, { desc = '显示当前 s3:// buffer 的远端信息' })

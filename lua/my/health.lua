-- `:checkhealth my` —— 一条命令回答「我这套配置现在是不是真的能用」。
--
-- 收录的都是"出问题时没有报错、只是行为悄悄不对"的东西：
-- 加载失败的配置模块、openssl 兼容性、凭证文件权限、静默降级的依赖、
-- 以及只增不减的 backup 目录。
--
-- 每一节都要自己兜住异常：`vim.health` 只对 `M.check()` 包一层 pcall，
-- 一个抛错会让后面所有小节一起消失（诊断工具恰好在"配置写坏"时失效）。

local M = {}

local h = vim.health

local CONFIG_ROOT = vim.env.VIMHOME or vim.fn.stdpath('config')
local LOCAL_DIR = CONFIG_ROOT .. '/local'

local function exists(path)
  return type(path) == 'string' and path ~= '' and vim.uv.fs_stat(path) ~= nil
end

--- 只认 0600：s3.lua / deepseek.key 里是 token 与密钥
--- @return boolean found
local function check_secret_perm(path)
  if not exists(path) then
    return false
  end
  local p = vim.fn.getfperm(path)
  if p ~= 'rw-------' then
    h.warn(('%s 权限是 %s，应为 rw-------（chmod 600 %s）'):format(path, p, path))
    return true
  end
  h.ok(('%s 权限 rw-------'):format(vim.fn.fnamemodify(path, ':~')))
  return true
end

--- 加解密往返自检：证明 openssl + `-md md5` 这条管线当前可用。
--- 明文/密码/密文都放在 0700 目录里，并且各自 0600 —— 与 s3_edit 同一标准。
local function openssl_roundtrip(openssl)
  local dir = vim.fn.tempname() .. '.d'
  vim.fn.mkdir(dir, 'p', 448) -- 0700
  local pw, src, enc, dec = dir .. '/pw', dir .. '/src', dir .. '/enc', dir .. '/dec'
  local function cleanup()
    vim.fn.delete(dir, 'rf')
  end

  local plain = { 'hello', '世界', '' }
  vim.fn.writefile({ 'conf-test' }, pw, 'b')
  vim.fn.writefile(plain, src, 'b')
  for _, f in ipairs({ pw, src, enc, dec }) do
    vim.fn.setfperm(f, 'rw-------')
  end

  local base = { openssl, 'aes-256-cbc', '-salt', '-md', 'md5', '-pass', 'file:' .. pw }
  vim.fn.system(vim.list_extend(vim.deepcopy(base), { '-in', src, '-out', enc }))
  local err_enc = vim.v.shell_error
  vim.fn.setfperm(enc, 'rw-------')
  vim.fn.system(vim.list_extend(vim.deepcopy(base), { '-d', '-in', enc, '-out', dec }))
  local err_dec = vim.v.shell_error

  local same = err_enc == 0
    and err_dec == 0
    and vim.deep_equal(vim.fn.readfile(dec, 'b'), plain)
  cleanup()
  return same, err_enc, err_dec
end

local function check_crypt()
  h.start('加密（encrypt.vim / s3_edit）')
  local openssl = '/usr/bin/openssl'
  if vim.fn.executable(openssl) ~= 1 then
    openssl = vim.fn.exepath('openssl')
  end
  if openssl == '' then
    h.error('找不到 openssl：encrypt.vim 与 s3_edit 都无法工作')
    return
  end
  h.ok('openssl: ' .. openssl)
  h.info(vim.trim(vim.fn.system({ openssl, 'version' })))
  local ok, err_enc, err_dec = openssl_roundtrip(openssl)
  if ok then
    h.ok('aes-256-cbc -salt -md md5 加解密往返一致（既有密文可读）')
  else
    h.error(
      ('加解密往返失败（encrypt=%d, decrypt=%d）：既有 .enc 文件可能读不出来了'):format(err_enc, err_dec)
    )
  end
end

local function check_s3()
  h.start('s3_edit（vault 远端加密文件）')
  local cfg = LOCAL_DIR .. '/s3.lua'
  if not exists(cfg) then
    h.info('没有 local/s3.lua：s3:// 编辑未配置（按需创建）')
    return
  end
  check_secret_perm(cfg)

  local ok, spec = pcall(dofile, cfg)
  if not ok or type(spec) ~= 'table' then
    h.error('local/s3.lua 无法解析：' .. tostring(spec))
    return
  end
  local buckets = type(spec.buckets) == 'table' and spec.buckets or {}
  local default = spec.default
  if default and not buckets[default] then
    h.error(('default = %s 在 buckets 里不存在'):format(tostring(default)))
  end
  for name, bucket in pairs(buckets) do
    -- 手写的配置，写坏成数字/布尔值很现实；这里归一化，后面的判断只用安全值
    if type(bucket) ~= 'table' then
      h.error(('%s：配置项不是 table（是 %s）'):format(name, type(bucket)))
    else
      if not bucket.endpoint then
        h.error(('%s：缺少 endpoint'):format(name))
      end
      local token_file = type(bucket.token_file) == 'string' and bucket.token_file or nil
      if bucket.token_file ~= nil and token_file == nil then
        h.error(('%s：token_file 应为字符串'):format(name))
      end
      if not (bucket.token or token_file) then
        h.error(('%s：缺少 token 或 token_file'):format(name))
      elseif bucket.endpoint then
        h.ok(('%s：endpoint + 凭证齐备%s'):format(name, default == name and '（default）' or ''))
      end
      if token_file then
        local path = vim.fn.expand(token_file)
        if not check_secret_perm(path) then
          h.error(('%s：token_file 不存在（%s）'):format(name, token_file))
        end
      end
    end
  end
  if type(vim.g.s3_password) == 'string' and vim.g.s3_password ~= '' then
    h.warn('g:s3_password 已设置：仅供自动化测试，记得 unlet')
  end
end

local function check_ai()
  h.start('AI 补全后端')
  local backend = vim.env.VIM_AI or ''
  if backend == '' then
    h.warn('未设置 $VIM_AI：copilot 与 deepseek 都不会加载')
    return
  end
  h.info('$VIM_AI = ' .. backend)
  if backend == 'deepseek' then
    local key = LOCAL_DIR .. '/deepseek.key'
    if not exists(key) then
      h.error('缺少 local/deepseek.key：deepseek-fim 无法请求 API')
      return
    end
    check_secret_perm(key)
    if (vim.uv.fs_stat(key).size or 0) == 0 then
      h.error('local/deepseek.key 是空文件')
    end
    if package.loaded['deepseek'] then
      h.ok('deepseek-fim 已加载')
    else
      h.warn('deepseek-fim 未加载（插件本体在 pack/my/opt/deepseek-fim）')
    end
  elseif backend == 'copilot' then
    if exists(vim.fn.stdpath('data') .. '/lazy/copilot.vim') then
      h.ok('copilot.vim 已安装')
    else
      h.error('copilot.vim 未安装（:Lazy sync）')
    end
  else
    h.warn(('未知的 $VIM_AI = %s（应为 copilot 或 deepseek）'):format(backend))
  end
end

--- 与 `plugin/ghostty_theme.lua` 共用 lua/my/ghostty.lua 的解析器：
--- 这里不做第二套 pattern，避免「运行时不认、checkhealth 认」这类假警告。
local function check_theme()
  h.start('配色（ghostty 主题跟随）')
  if not vim.o.termguicolors then
    h.info("'termguicolors' 关闭（Apple_Terminal？）：ghostty 配色不会生效")
  end
  if vim.g.colors_name ~= 'ghostty' then
    h.info(('当前配色是 %s，不是 ghostty 派生配色（:GhosttyTheme 可强制对齐）')
      :format(tostring(vim.g.colors_name)))
  else
    h.ok("当前配色来自 ghostty：g:colors_name = 'ghostty'")
  end

  local ok, G = pcall(require, 'my.ghostty')
  if not ok then
    h.error('lua/my/ghostty.lua 加载失败：' .. tostring(G))
    return
  end
  local path = G.config_path()
  if not exists(path) then
    h.warn('没有 ghostty 配置：' .. path)
    return
  end

  local config = G.read_config(path)
  local inline = config.background or config.foreground or next(config.palette) ~= nil
  if not (config.theme or inline) then
    h.warn('ghostty 配置（含 config-file include）里既没有 theme= 也没有 palette：不会接管配色')
    return
  end
  if inline then
    h.ok('配置里有内联 background/foreground/palette')
  end

  local name = G.active_name(config.theme)
  if not name then
    return
  end
  h.ok('theme = ' .. name)
  local theme = G.theme_path(name)
  if theme then
    h.ok('主题文件：' .. vim.fn.fnamemodify(theme, ':~'))
  else
    h.warn(('找不到主题文件 %s（ghostty 会静默忽略）'):format(name))
  end
end

local function check_tools()
  h.start('工具链（缺失时静默跳过的部分）')
  local lint_ok, lint = pcall(require, 'lint')
  if lint_ok and lint.linters_by_ft then
    local missing = {}
    for ft, linters in pairs(lint.linters_by_ft) do
      for _, name in ipairs(linters) do
        local ok, linter = pcall(require, 'lint.linters.' .. name)
        local cmd = ok and linter and linter.cmd
        local exe = type(cmd) == 'function' and cmd() or cmd
        if type(exe) == 'string' and vim.fn.executable(exe) ~= 1 then
          missing[#missing + 1] = ('%s（%s）'):format(name, ft)
        end
      end
    end
    if #missing == 0 then
      h.ok('linters_by_ft 声明的 linter 都存在')
    else
      h.warn('声明了但没安装，会被静默跳过：' .. table.concat(missing, '、'))
    end
  else
    h.info('nvim-lint 尚未加载')
  end

  -- LSP 名单直接取 setup/lsp.lua 的 servers 表，不再维护第二份
  local lsp_ok, lsp = pcall(require, 'setup.lsp')
  local servers = (lsp_ok and type(lsp) == 'table' and lsp.servers) or {}
  local binaries = {
    lua_ls = 'lua-language-server',
    basedpyright = 'basedpyright-langserver',
    rust_analyzer = 'rust-analyzer',
  }
  local bin = vim.fn.stdpath('data') .. '/mason/bin'
  local names = vim.tbl_keys(servers)
  table.sort(names)
  if #names == 0 then
    h.info('没有读到 setup/lsp.lua 的 servers 表')
  end
  for _, server in ipairs(names) do
    local exe = binaries[server] or server
    if exists(bin .. '/' .. exe) or vim.fn.executable(exe) == 1 then
      h.ok('LSP: ' .. exe)
    else
      h.warn(('LSP: %s 未安装（相关文件不会有补全/跳转；:MasonInstall %s）'):format(exe, server))
    end
  end

  local parser_dir = vim.fn.stdpath('data') .. '/site/parser'
  local expected = { 'c', 'cpp', 'json', 'lua', 'python', 'rust', 'tsx', 'vim', 'vimdoc' }
  local absent = {}
  for _, lang in ipairs(expected) do
    if not exists(('%s/%s.so'):format(parser_dir, lang)) then
      absent[#absent + 1] = lang
    end
  end
  if #absent == 0 then
    h.ok('treesitter parser 齐全')
  else
    h.warn('treesitter parser 缺失：' .. table.concat(absent, '、') .. '（:TSInstall）')
  end
end

local function check_disk()
  h.start('磁盘（backup 目录只增不减）')
  -- 用真实生效的 'backupdir'（local/ 里可能覆盖过），不是 setup/vim.lua 的常量
  local first = (vim.o.backupdir or ''):gmatch('[^,]+')()
  if not first or first == '' or first == '.' then
    h.info("'backupdir' 是 " .. vim.o.backupdir .. '，不做统计')
    return
  end
  -- 'backupdir' 的项可能是 `~/x//`（写全路径）或 `.`，只统计第一项
  local dir = vim.fn.expand((first:gsub('/+$', '')))
  if dir == '' then
    h.info("'backupdir' 无法展开（" .. first .. '）')
    return
  end
  dir = dir:gsub('/+$', '') .. '/'
  if not exists(dir) then
    h.info('backup 目录不存在（' .. dir .. '）')
    return
  end
  local files, bytes = 0, 0
  for _, name in ipairs(vim.fn.readdir(dir) or {}) do
    local stat = vim.uv.fs_stat(dir .. name)
    if stat and stat.type == 'file' then
      files = files + 1
      bytes = bytes + stat.size
    end
  end
  local msg = ('%d 个备份 / %.1f MB（%s）'):format(files, bytes / 1024 / 1024, vim.fn.fnamemodify(dir, ':~'))
  if files > 200 or bytes > 100 * 1024 * 1024 then
    h.warn(msg .. '：可以清掉旧备份，如 find ' .. dir .. ' -mtime +90 -delete')
  else
    h.ok(msg)
  end
end

function M.check()
  h.start('配置加载')
  local ok, safe = pcall(require, 'my.safe')
  if not ok then
    -- 这正是「整份配置可能都没加载」的场景，绝不能说"加载成功"
    h.error('lua/my/safe.lua 加载失败：' .. tostring(safe))
  elseif safe.broken() then
    for name, err in pairs(safe.errors) do
      h.error(('%s\n%s'):format(name, err))
    end
  else
    h.ok('所有配置模块/文件加载成功')
  end
  if ok and vim.g.my_config_broken then
    h.warn('init.lua 记录过加载失败（见上）')
  end
  if vim.g.my_config_ms then
    h.info(('init.lua 加载耗时 %.1f ms（不含 VimEnter 之后的工作）'):format(vim.g.my_config_ms))
  end
  h.info('$VIMHOME = ' .. CONFIG_ROOT)

  for _, check in ipairs({ check_crypt, check_s3, check_ai, check_theme, check_tools, check_disk }) do
    local ok2, err = pcall(check)
    if not ok2 then
      h.error('这一节自己报错了：' .. tostring(err))
    end
  end
end

return M

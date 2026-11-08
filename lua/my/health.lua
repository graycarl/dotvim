-- `:checkhealth my` —— 一条命令回答「我这套配置现在是不是真的能用」。
--
-- 收录的都是"出问题时没有报错、只是行为悄悄不对"的东西：
-- 加载失败的配置模块、openssl 兼容性、凭证文件权限、静默降级的依赖、
-- 以及只增不减的 backup 目录。

local M = {}

local h = vim.health

local CONFIG_ROOT = vim.env.VIMHOME or vim.fn.stdpath('config')
local LOCAL_DIR = CONFIG_ROOT .. '/local'

local function exists(path)
  return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

--- 只认 0600：s3.lua / deepseek.key 里是 token 与密钥
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

--- 加解密往返自检：证明 openssl + `-md md5` 这条管线当前可用
local function openssl_roundtrip(openssl)
  local pw = vim.fn.tempname()
  local src, enc, dec = vim.fn.tempname(), vim.fn.tempname(), vim.fn.tempname()
  local function cleanup()
    for _, f in ipairs({ pw, src, enc, dec }) do
      vim.fn.delete(f)
    end
  end
  local plain = { 'hello', '世界', '' }
  vim.fn.writefile({ 'conf-test' }, pw, 'b')
  vim.fn.setfperm(pw, 'rw-------')
  vim.fn.writefile(plain, src, 'b')

  local base = { openssl, 'aes-256-cbc', '-salt', '-md', 'md5', '-pass', 'file:' .. pw }
  vim.fn.system(vim.list_extend(vim.deepcopy(base), { '-in', src, '-out', enc }))
  local err_enc = vim.v.shell_error
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
  local version = vim.trim(vim.fn.system({ openssl, 'version' }))
  h.info(version)
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
  local buckets = spec.buckets or {}
  local default = spec.default
  if default and not buckets[default] then
    h.error(('default = %s 在 buckets 里不存在'):format(tostring(default)))
  end
  for name, bucket in pairs(buckets) do
    if type(bucket) ~= 'table' or not bucket.endpoint then
      h.error(('%s：缺少 endpoint'):format(name))
    elseif not (bucket.token or bucket.token_file) then
      h.error(('%s：缺少 token 或 token_file'):format(name))
    else
      h.ok(('%s：endpoint + 凭证齐备%s'):format(name, default == name and '（default）' or ''))
    end
    if bucket.token_file then
      local path = vim.fn.expand(bucket.token_file)
      if not check_secret_perm(path) then
        h.error(('%s：token_file 不存在（%s）'):format(name, bucket.token_file))
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
    local loaded = package.loaded['deepseek'] ~= nil
    if loaded then
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

  local root = vim.g.ghostty_theme_config
    or ((vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/ghostty/config')
  if not exists(root) then
    h.warn('没有 ghostty 配置：' .. root)
    return
  end

  -- `config-file = ?auto/theme.ghostty` 这类 include 很常见（主题选择器就写在这里），
  -- 只看主 config 会误报「没有 theme=」
  local theme, inline, seen = nil, false, {}
  local function scan(path, depth)
    if depth > 3 or seen[path] or not exists(path) then
      return
    end
    seen[path] = true
    local dir = vim.fn.fnamemodify(path, ':h')
    for _, line in ipairs(vim.fn.readfile(path)) do
      local include = line:match('^%s*config%-file%s*=%s*(.-)%s*$')
      if include then
        include = include:gsub('^%?', '')
        if include:sub(1, 1) ~= '/' then
          include = dir .. '/' .. include
        end
        scan(vim.fn.expand(include), depth + 1)
      end
      local value = line:match('^%s*theme%s*=%s*(.-)%s*$')
      if value and value ~= '' then
        theme = value
      end
      if line:match('^%s*(background|foreground|palette)%s*=') then
        inline = true
      end
    end
  end
  scan(vim.fn.expand(root), 0)

  if not (theme or inline) then
    h.warn('ghostty 配置（含 config-file include）里既没有 theme= 也没有 palette：不会接管配色')
    return
  end
  if inline and not theme then
    h.ok('配置里有内联 background/foreground/palette')
  end
  if not theme then
    return
  end
  h.ok('theme = ' .. theme)

  -- 解析 light:X,dark:Y，确认主题文件真的存在（写错名字时 ghostty 只会静默忽略）
  local dirs = {
    (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/ghostty/themes',
    '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
    '/usr/local/share/ghostty/themes',
    '/usr/share/ghostty/themes',
  }
  local function resolve(name)
    name = (name:gsub('^["\']', ''):gsub('["\']$', ''))
    for _, dir in ipairs(dirs) do
      if exists(dir .. '/' .. name) then
        return dir .. '/' .. name
      end
    end
  end
  local names = {}
  for half, name in theme:gmatch('(%a+):([^,]+)') do
    names[#names + 1] = { half, name }
  end
  if #names == 0 then
    names[1] = { 'theme', theme }
  end
  for _, item in ipairs(names) do
    local path = resolve(item[2])
    if path then
      h.ok(('%s：%s'):format(item[1], vim.fn.fnamemodify(path, ':~')))
    else
      h.warn(('%s：找不到主题文件 %s（ghostty 会静默忽略）'):format(item[1], item[2]))
    end
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

  local bin = vim.fn.stdpath('data') .. '/mason/bin'
  for _, server in ipairs({ 'lua-language-server', 'basedpyright-langserver', 'rust-analyzer' }) do
    if exists(bin .. '/' .. server) or vim.fn.executable(server) == 1 then
      h.ok('LSP: ' .. server)
    else
      h.error('LSP: ' .. server .. ' 缺失（:MasonInstall）')
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
  local dir = vim.fn.stdpath('state') .. '/backup/'
  if not exists(dir) then
    h.info('backup 目录不存在（还没有写过文件？）')
    return
  end
  local files = vim.fn.readdir(dir)
  local bytes = 0
  for _, name in ipairs(files) do
    local s = vim.uv.fs_stat(dir .. name)
    bytes = bytes + (s and s.size or 0)
  end
  local msg = ('%d 个备份 / %.1f MB（%s）'):format(#files, bytes / 1024 / 1024, vim.fn.fnamemodify(dir, ':~'))
  if #files > 200 or bytes > 100 * 1024 * 1024 then
    h.warn(msg .. '：可以清掉旧备份，如 find ' .. dir .. ' -mtime +90 -delete')
  else
    h.ok(msg)
  end
end

function M.check()
  local ok, safe = pcall(require, 'my.safe')
  local failed = ok and safe.errors or {}
  h.start('配置加载')
  local count = vim.tbl_count(failed)
  if count == 0 then
    h.ok('所有配置模块/文件加载成功')
  else
    for name, err in pairs(failed) do
      h.error(('%s\n%s'):format(name, err))
    end
  end
  if vim.g.my_config_ms then
    h.info(('init.lua 加载耗时 %.1f ms（不含 VimEnter 之后的工作）'):format(vim.g.my_config_ms))
  end
  h.info('$VIMHOME = ' .. CONFIG_ROOT)

  check_crypt()
  check_s3()
  check_ai()
  check_theme()
  check_tools()
  check_disk()
end

return M

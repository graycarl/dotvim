-- ghostty 配置解析器（被 `plugin/ghostty_theme.lua` 与 `:checkhealth my` 共用）
--
-- 只做「读文件 → 结构」这一层：不碰任何高亮，所以两边不会因为各写一份
-- 解析逻辑而长期漂移（`~/.config/ghostty/config` 的 include、引号、`~`、
-- 行尾注释、`light:X,dark:Y` 这些写法只有这里解释一次）。
--
-- 返回的 config table：
--   { background = '#rrggbb', foreground = '#rrggbb',
--     palette = { [0] = '#rrggbb', ... }, theme = 'light:"A",dark:"B"' }

local M = {}

-- Theme directories, user themes first
M.THEME_DIRS = {
  (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/ghostty/themes',
  '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
  '/usr/local/share/ghostty/themes',
  '/usr/share/ghostty/themes',
}

-- "#rgb" / "#rrggbb" / "#rrggbbaa" -> r, g, b (0..255)
local function rgb(value)
  local r, g, b = value:match('^#?(%x%x)(%x%x)(%x%x)')
  if not r then
    r, g, b = value:match('^#?(%x)(%x)(%x)')
    if not r then
      return nil
    end
    r, g, b = r .. r, g .. g, b .. b
  end
  return tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
end

local function hexstr(r, g, b)
  local function clamp(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return ('#%02x%02x%02x'):format(clamp(r), clamp(g), clamp(b))
end

-- Normalise a colour value to lowercase "#rrggbb" (alpha dropped), or nil
function M.norm(value)
  local found = value and value:match('#%x+')
  if not found then
    return nil
  end
  local r, g, b = rgb(found)
  return r and hexstr(r, g, b) or nil
end

-- Strip a trailing `# comment`, respecting quoted strings
function M.strip_comment(value)
  local out, quote = {}, nil
  for i = 1, #value do
    local ch = value:sub(i, i)
    if quote then
      if ch == quote then
        quote = nil
      end
      out[#out + 1] = ch
    elseif ch == '"' or ch == "'" then
      quote = ch
      out[#out + 1] = ch
    elseif ch == '#' then
      break
    else
      out[#out + 1] = ch
    end
  end
  return (table.concat(out):gsub('%s+$', ''))
end

function M.config_path()
  return (
    vim.g.ghostty_theme_config
    or (vim.env.XDG_CONFIG_HOME and (vim.env.XDG_CONFIG_HOME .. '/ghostty/config'))
    or (vim.env.HOME .. '/.config/ghostty/config')
  )
end

-- Parse a ghostty config or theme file: `background`, `foreground`,
-- `palette = N=#rrggbb`, `theme` and `config-file` includes. Colour values are
-- read with norm(), so a trailing comment on the same line does not confuse
-- them. Includes are followed like ghostty does: relative to the including
-- file, `?` prefix = optional, `~` expanded, later directives win.
function M.read_config(path, data, seen)
  data = data or { palette = {} }
  seen = seen or {}
  if seen[path] then
    return data
  end
  seen[path] = true

  local file = io.open(path, 'r')
  if not file then
    return data
  end
  for line in file:lines() do
    local key, value = line:match('^%s*([%w%-_]+)%s*=%s*(.-)%s*$')
    if key then
      if key == 'background' or key == 'foreground' then
        data[key] = M.norm(value) or data[key]
      elseif key == 'palette' then
        local index, color = value:match('^(%d+)%s*=%s*(.-)$')
        index, color = tonumber(index), M.norm(color)
        if index and color then
          data.palette[index] = color
        end
      elseif key == 'theme' then
        data.theme = M.strip_comment(value)
      elseif key == 'config-file' then
        -- `config-file = ?auto/theme.ghostty` (the theme picker writes here)
        local target = value:gsub('^%?%s*', ''):gsub('^"(.*)"$', '%1')
        target = target:gsub('^~', vim.env.HOME or '~')
        if target:sub(1, 1) ~= '/' then
          target = (path:match('^(.*)/[^/]*$') or '.') .. '/' .. target
        end
        M.read_config(target, data, seen)
      end
    end
  end
  file:close()
  return data
end

-- Path of a theme file by name, from the first directory that has it
function M.theme_path(name)
  for _, dir in ipairs(M.THEME_DIRS) do
    local path = dir .. '/' .. name
    if vim.uv.fs_stat(path) then
      return path
    end
  end
  return nil
end

-- Parsed theme file, or nil when no directory has it
function M.read_theme(name)
  local path = M.theme_path(name)
  return path and M.read_config(path) or nil
end

-- macOS appearance: 'light' | 'dark', which is what ghostty follows for
-- `theme = light:...,dark:...`. Cached, it spawns a process.
local appearance_cache, appearance_at

function M.appearance()
  local now = vim.uv.now()
  if appearance_cache and (now - appearance_at) < 10000 then
    return appearance_cache
  end
  local ok, result = pcall(vim.fn.system, { 'defaults', 'read', '-g', 'AppleInterfaceStyle' })
  if not ok or vim.v.shell_error ~= 0 then
    result = ''
  end
  appearance_cache = (vim.trim(result) == 'Dark') and 'dark' or 'light'
  appearance_at = now
  return appearance_cache
end

-- Pick the theme name of the active light/dark variant
function M.active_name(theme)
  if not theme or theme == '' then
    return nil
  end
  local light, dark = theme:match('^%s*light:%s*"([^"]*)"%s*,%s*dark:%s*"([^"]*)"')
  if light and dark then
    return (M.appearance() == 'light') and light or dark
  end
  dark = theme:match('^%s*dark:%s*"([^"]*)"%s*$')
  if dark then
    return dark
  end
  light = theme:match('^%s*light:%s*"([^"]*)"%s*$')
  if light then
    return light
  end
  return (theme:gsub('^"(.*)"$', '%1'))
end

return M

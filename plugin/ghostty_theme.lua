-- ghostty theme sync: follow the terminal's theme in Neovim
--
-- Keeps the Neovim colorscheme in step with the ghostty theme (and the
-- light/dark variant of `theme = light:...,dark:...`).
--
-- Neovim 0.12 already has a builtin TermResponse handler that parses an OSC 11
-- reply and sets 'background' ("tui_term_has_dark_bg"), but it only knows
-- light/dark -- it cannot tell gruvbox from catppuccin, and inside tmux the
-- reply never arrives at all (tmux swallows the query).
--
-- So this plugin resolves the *theme* from two sources, in this order:
--
--   1. The ghostty config file (`theme = ...`), which is exact and works
--      everywhere, including inside tmux. `theme = light:A,dark:B` is resolved
--      with the macOS appearance (that is what ghostty itself follows).
--   2. An OSC 11 query as a fallback, when the config carries no `theme =`
--      (e.g. inline `background = #rrggbb`): the reply color is looked up in a
--      table of known ghostty backgrounds.
--
-- The colorscheme is then switched to the matching Neovim scheme, with
-- 'background' set first (schemes read it when they load). The builtin table
-- only maps pairs whose background color is identical in Ghostty and in the
-- Neovim colorscheme, so the switch is invisible when both sides agree:
--
--   gruvbox     Gruvbox Light      / Gruvbox Dark        #fbf1c7 / #282828
--   kanagawa    Kanagawa Lotus     / Kanagawa Wave       #f2ecbc / #1f1f28
--   onenord     Onenord Light      / Onenord             #f7f8fa / #2e3440
--   catppuccin  Catppuccin Latte   / Catppuccin Mocha    #eff1f5 / #1e1e2e
--   everforest  Everforest Light … / Everforest Dark …   (approx colours)
--   onedark     Atom One Light     / Atom One Dark       #f9f9f9 / #21252b
--
-- Only *changes* are followed: after a sync, a manual `:colorscheme foo` (or
-- |SwitchColor|) sticks until the ghostty theme actually changes again (or you
-- run `:GhosttyTheme` to force a re-align).
--
-- Settings (all optional):
--
--   vim.g.ghostty_theme_follow = false    " background only, no colorscheme switch
--   vim.g.ghostty_theme_config = '...'    " default: $XDG_CONFIG_HOME/ghostty/config
--   vim.g.ghostty_theme_colors = {        " extra OSC-11 background colour map
--     ['#181616'] = { 'kanagawa', 'dark' },   " Kanagawa Dragon
--   }
--   vim.g.ghostty_theme_schemes = {       " extra theme-name matching rules
--     { pattern = 'nordic', scheme = 'nordic' },
--   }
--
-- Commands: `:GhosttyTheme` re-resolves and reports,
-- `:GhosttyTheme!` also lists the known mappings.

-- Above this relative luminance the terminal counts as light
local LIGHT_THRESHOLD = 0.35

-- Timeout (ms) for the terminal to answer the OSC 11 fallback query
local RESPONSE_TIMEOUT = 800

-- Background colour -> colorscheme. Keys are lowercase `#rrggbb`.
local BUILTIN_COLORS = {
  ['#fbf1c7'] = { 'gruvbox', 'light' }, -- Gruvbox Light
  ['#282828'] = { 'gruvbox', 'dark' }, -- Gruvbox Dark / Gruvbox Material Dark
  ['#f2ecbc'] = { 'kanagawa', 'light' }, -- Kanagawa Lotus
  ['#1f1f28'] = { 'kanagawa', 'dark' }, -- Kanagawa Wave / Kanagawabones
  ['#f7f8fa'] = { 'onenord', 'light' }, -- Onenord Light
  ['#2e3440'] = { 'onenord', 'dark' }, -- Onenord
  ['#eff1f5'] = { 'catppuccin', 'light' }, -- Catppuccin Latte
  ['#1e1e2e'] = { 'catppuccin', 'dark' }, -- Catppuccin Mocha
  ['#fffbef'] = { 'everforest', 'light' }, -- Everforest Light Hard
  ['#272e33'] = { 'everforest', 'dark' }, -- Everforest Dark Hard
  ['#f9f9f9'] = { 'onedark', 'light' }, -- Atom One Light
  ['#21252b'] = { 'onedark', 'dark' }, -- Atom One Dark / One Dark Two
}

-- ghostty theme *name* -> colorscheme (matched as a lowercase substring)
local BUILTIN_SCHEMES = {
  { pattern = 'gruvbox', scheme = 'gruvbox' },
  { pattern = 'kanagawa', scheme = 'kanagawa' },
  { pattern = 'onenord', scheme = 'onenord' },
  { pattern = 'catppuccin', scheme = 'catppuccin' },
  { pattern = 'everforest', scheme = 'everforest' },
  { pattern = 'one dark', scheme = 'onedark' },
  { pattern = 'onedark', scheme = 'onedark' },
}

-- Substrings that mark an explicit background in a theme name
local LIGHT_HINTS = { 'light', 'latte', 'lotus', 'day' }
local DARK_HINTS = { 'dark', 'mocha', 'wave', 'dragon', 'night', 'noir', 'black' }

local pending = false
local applying = false -- guards the OptionSet('background') hook
local last = nil -- last resolved state, see apply() below
local appearance_cache = nil
local appearance_at = 0

-- Whitelisted command execution (no shell): returns trimmed stdout or nil
local function run(cmd)
  local ok, result = pcall(vim.fn.system, cmd)
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end

-- sRGB channel linearization, for WCAG relative luminance
local function linearize(c)
  if c <= 0.04045 then
    return c / 12.92
  end
  return ((c + 0.055) / 1.055) ^ 2.4
end

local function luminance(r, g, b)
  return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
end

local function hex(v)
  return ('%02x'):format(math.floor(v * 255 + 0.5))
end

-- "#rrggbb" for the given 0..1 channels
local function color_key(r, g, b)
  return '#' .. hex(r) .. hex(g) .. hex(b)
end

-- Normalize a mapping key: lowercase, expand 3-digit hex
local function normalize_key(key)
  key = key:lower()
  local r, g, b = key:match('^#(%x)(%x)(%x)$')
  if r then
    return ('#%s%s%s%s%s%s'):format(r, r, g, g, b, b)
  end
  return key
end

-- Parse an OSC 11 reply, e.g. "\27]11;rgb:2020/1111/1b1b\27\\" or with BEL
local function parse_osc11(sequence)
  local r, g, b = sequence:match(']11;rgba?:(%x+)/(%x+)/(%x+)')
  if not r then
    return nil
  end
  local function channel(value)
    if #value == 1 then
      return (tonumber(value, 16) / 15)
    elseif #value == 2 then
      return (tonumber(value, 16) / 255)
    elseif #value == 3 then
      return (tonumber(value, 16) / 4095)
    end
    return (tonumber(value, 16) / 65535)
  end
  return channel(r), channel(g), channel(b)
end

local function color_map()
  local map = {}
  for key, spec in pairs(BUILTIN_COLORS) do
    map[key] = spec
  end
  local user = vim.g.ghostty_theme_colors
  if type(user) == 'table' then
    for key, spec in pairs(user) do
      if type(key) == 'string' then
        if type(spec) == 'string' then
          map[normalize_key(key)] = { spec }
        elseif type(spec) == 'table' then
          map[normalize_key(key)] = { spec[1] or spec.scheme, spec[2] or spec.bg }
        end
      end
    end
  end
  return map
end

local function scheme_rules()
  local rules = {}
  for _, rule in ipairs(BUILTIN_SCHEMES) do
    table.insert(rules, rule)
  end
  local user = vim.g.ghostty_theme_schemes
  if type(user) == 'table' then
    for _, rule in ipairs(user) do
      if type(rule) == 'table' and rule.pattern and rule.scheme then
        table.insert(rules, rule)
      end
    end
  end
  return rules
end

-- Colorschemes come from the runtimepath, so ask the completer instead of
-- relying on a pcall (a failed `:colorscheme` also resets highlights).
local function scheme_available(name)
  if not name or name == '' then
    return false
  end
  return vim.tbl_contains(vim.fn.getcompletion(name, 'color'), name)
end

-- Resolve a ghostty theme name into (colorscheme, 'light'|'dark'|nil)
local function name_spec(name)
  if not name or name == '' then
    return nil, nil
  end
  local lower = name:lower()
  local scheme = nil
  for _, rule in ipairs(scheme_rules()) do
    if lower:find(rule.pattern, 1, true) then
      scheme = rule.scheme
      break
    end
  end
  local bg = nil
  for _, hint in ipairs(LIGHT_HINTS) do
    if lower:find(hint, 1, true) then
      bg = 'light'
      break
    end
  end
  if not bg then
    for _, hint in ipairs(DARK_HINTS) do
      if lower:find(hint, 1, true) then
        bg = 'dark'
        break
      end
    end
  end
  return scheme, bg
end

local function ghostty_config_path()
  return (
    vim.g.ghostty_theme_config
    or (vim.env.XDG_CONFIG_HOME and (vim.env.XDG_CONFIG_HOME .. '/ghostty/config'))
    or (vim.env.HOME .. '/.config/ghostty/config')
  )
end

-- Strip a trailing `# comment`, respecting quoted strings
local function strip_comment(value)
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

-- Parse `key = value` lines (last one wins), skipping comments and blanks
local function read_ghostty_config(path)
  local kv = {}
  local file = io.open(path, 'r')
  if not file then
    return kv
  end
  for line in file:lines() do
    local key, value = line:match('^%s*([%w%-_]+)%s*=%s*(.-)%s*$')
    if key then
      value = strip_comment(value)
      if value ~= '' then
        kv[key] = value
      end
    end
  end
  file:close()
  return kv
end

-- macOS appearance: 'light' | 'dark'. This is what ghostty follows for
-- `theme = light:...,dark:...`. Cached because it spawns a process.
local function appearance()
  local now = vim.uv.now()
  if appearance_cache and (now - appearance_at) < 10000 then
    return appearance_cache
  end
  local result = run({ 'defaults', 'read', '-g', 'AppleInterfaceStyle' })
  appearance_cache = (result == 'Dark') and 'dark' or 'light'
  appearance_at = now
  return appearance_cache
end

-- Resolve the active ghostty theme from the config file.
-- Returns { scheme, bg, id, source } or nil.
local function resolve_from_config()
  local kv = read_ghostty_config(ghostty_config_path())

  local theme = kv.theme
  if not theme then
    return nil
  end

  local light, dark = theme:match('^%s*light:%s*"([^"]*)"%s*,%s*dark:%s*"([^"]*)"')
  local name
  if light and dark then
    name = (appearance() == 'light') and light or dark
  else
    name = theme:gsub('^"(.*)"$', '%1')
  end
  if name == '' then
    return nil
  end

  local scheme, bg = name_spec(name)
  if not scheme and not bg then
    return nil
  end
  return { scheme = scheme, bg = bg, id = 'cfg:' .. name, source = 'config', name = name }
end

-- Apply a resolved spec. Only touches 'background'/colorscheme when the theme
-- identity changed (unless `force`), so manual choices are preserved.
local function apply(spec, force)
  if not spec then
    return
  end
  if last and last.id == spec.id and not force then
    last.skipped = true
    return
  end

  local follow = vim.g.ghostty_theme_follow ~= false
  local scheme = follow and spec.scheme or nil
  local target = spec.bg
  local detected = spec.detected
  local previous = vim.g.colors_name

  if target == nil then
    target = detected or vim.o.background
  end

  applying = true
  local switched = false
  if scheme_available(scheme) and previous ~= scheme then
    -- 'background' must be right *before* loading, schemes read it on load
    vim.o.background = target
    local ok, err = pcall(vim.cmd.colorscheme, scheme)
    if ok then
      switched = true
    else
      vim.notify(('ghostty theme: colorscheme %q failed: %s'):format(scheme, err), vim.log.levels.WARN)
      scheme = nil
      if previous then
        pcall(vim.cmd.colorscheme, previous)
      end
      target = detected or vim.o.background
    end
  end
  if not switched then
    scheme = scheme_available(scheme) and scheme or nil
    if vim.o.background ~= target then
      vim.o.background = target
      -- schemes that embed light/dark variants (kanagawa, everforest, onedark)
      -- only rebuild their highlights when they are (re)loaded
      if vim.g.colors_name then
        vim.cmd.colorscheme(vim.g.colors_name)
      end
    end
  end
  applying = false

  last = {
    id = spec.id,
    source = spec.source,
    bg = vim.o.background,
    scheme = scheme,
    colors = vim.g.colors_name,
    color = spec.color,
    name = spec.name,
    detected = detected,
    skipped = false,
  }
end

local function report()
  if not last then
    return 'ghostty theme: no source resolved (yet)'
  end
  if last.skipped then
    return ('ghostty theme: %s unchanged, kept colorscheme=%s (background=%s)'):format(
      last.id,
      last.colors or 'none',
      last.bg
    )
  end
  return ('ghostty theme: %s via %s%s -> background=%s, colorscheme=%s'):format(
    last.id,
    last.source,
    last.color and (' ' .. last.color) or '',
    last.bg,
    last.colors or 'none'
  )
end

local function report_map()
  local lines = { 'ghostty theme: known mappings' }
  local colors = color_map()
  local keys = vim.tbl_keys(colors)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local spec = colors[key]
    table.insert(lines, ('  OSC 11 %s  %s (%s)'):format(key, spec[1] or '?', spec[2] or 'detected'))
  end
  for _, rule in ipairs(scheme_rules()) do
    table.insert(lines, ('  theme  *%s*  %s'):format(rule.pattern, rule.scheme))
  end
  return table.concat(lines, '\n')
end

-- Ask the terminal for its background colour and apply the OSC 11 mapping.
local function sync_from_osc(verbose)
  if pending or #vim.api.nvim_list_uis() == 0 then
    return
  end
  pending = true

  local id
  local timer
  local function finish(ok)
    if id then
      pcall(vim.api.nvim_del_autocmd, id)
      id = nil
    end
    if timer then
      pcall(function()
        timer:stop()
        timer:close()
      end)
      timer = nil
    end
    pending = false
    if ok and verbose then
      vim.notify(report(), vim.log.levels.INFO)
    end
  end

  id = vim.api.nvim_create_autocmd('TermResponse', {
    callback = function(event)
      local sequence = (event.data and event.data.sequence) or ''
      local r, g, b = parse_osc11(sequence)
      if not r then
        return -- someone else's reply (DA1, OSC 4, ...)
      end
      local key = color_key(r, g, b)
      local spec = color_map()[key]
      local lum = luminance(r, g, b)
      apply({
        scheme = spec and spec[1],
        bg = spec and spec[2],
        detected = lum > LIGHT_THRESHOLD and 'light' or 'dark',
        id = 'osc:' .. key,
        source = 'OSC 11',
        color = key,
      })
      finish(true)
    end,
  })

  timer = vim.uv.new_timer()
  timer:start(
    RESPONSE_TIMEOUT,
    0,
    vim.schedule_wrap(function()
      finish(false)
    end)
  )

  io.stdout:write('\27]11;?\27\\')
  io.stdout:flush()
end

--- Resolve the active ghostty theme and sync 'background'/colorscheme.
--- @param verbose boolean|nil Report the result in |:messages|.
--- @param force boolean|nil Re-align even if the theme did not change.
local function sync(verbose, force)
  local from_config = resolve_from_config()
  if from_config then
    apply(from_config, force)
    if verbose then
      vim.notify(report(), vim.log.levels.INFO)
    end
    return
  end
  -- no `theme =` in the ghostty config: fall back to the OSC 11 reply colour
  sync_from_osc(verbose)
end

vim.api.nvim_create_autocmd({ 'UIEnter', 'VimEnter', 'FocusGained', 'VimResume' }, {
  callback = function()
    sync(false, false)
  end,
})

-- Neovim's own OSC 11 handling (and `:set background=`) changes 'background'
-- without loading a colorscheme; keep the two in sync.
vim.api.nvim_create_autocmd('OptionSet', {
  pattern = 'background',
  callback = function()
    if applying then
      return
    end
    local from_config = resolve_from_config()
    if from_config and from_config.bg and from_config.bg ~= vim.o.background then
      return -- the terminal side wins, the next sync will fix it
    end
    if not vim.g.colors_name then
      return
    end
    applying = true
    -- schemes that embed light/dark variants (kanagawa, everforest, onedark)
    -- only rebuild their highlights when they are (re)loaded
    pcall(vim.cmd.colorscheme, vim.g.colors_name)
    applying = false
  end,
})

vim.api.nvim_create_user_command('GhosttyTheme', function(opts)
  if opts.bang then
    vim.notify(report_map() .. '\n' .. report(), vim.log.levels.INFO)
    return
  end
  if pending then
    return
  end
  sync(true, true)
end, { bang = true, desc = 'Resolve the ghostty theme and sync background/colorscheme' })

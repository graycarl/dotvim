-- ghostty palette sync: paint Neovim with the terminal's own colours
--
-- The active ghostty theme (`theme = ...` in the ghostty config, resolved to
-- its light/dark half with the macOS appearance) provides `background`,
-- `foreground` and `palette 0-15`. Neovim's highlight groups are generated
-- from those colours directly -- no named colorscheme is involved -- so any
-- ghostty theme drives Neovim: builtin themes, user themes, or inline
-- `background =`/`palette =` lines, and the two sides cannot drift apart.
--
--   ghostty theme file    ->  Neovim
--   background            ->  'background' (light/dark from luminance), Normal.bg
--   foreground            ->  Normal.fg
--   palette 1-6 / 9-14    ->  red/green/yellow/blue/magenta/cyan; of each pair
--                             the one with the better contrast against bg wins
--   palette 8             ->  Comment (else a blend of fg towards bg)
--   mix(bg, fg, 6%)       ->  CursorLine, ColorColumn, TabLine
--   mix(bg, fg, 10%)      ->  StatusLine, Pmenu, TabLineSel, Folded
--   mix(bg, fg, 20%)      ->  Visual, QuickFixLine
--   mix(bg, fg, 30%)      ->  WinSeparator
--   mix(bg, fg, 55%)      ->  LineNr, NonText, Whitespace
--
-- The two surface blends are the ones ~/.shell/tools/ghostty-tmux-theme.py
-- feeds tmux (themedark-grey / themelight-grey), so the Neovim statusline and
-- the tmux status bar end up the same colour. `terminal_color_0..15` are set
-- from the palette as well, so :terminal matches the real terminal.
--
-- Only *changes* are followed: after a sync a manual `:colorscheme foo` sticks
-- until the ghostty theme (or its colours) changes again, or you run
-- `:GhosttyTheme` to force a re-align. Colours are GUI-only, so this wants
-- 'termguicolors' (enabled in lua/setup/vim.lua except on Apple Terminal).
--
-- Settings (all optional):
--
--   vim.g.ghostty_theme_config = '...'     " default: $XDG_CONFIG_HOME/ghostty/config
--   vim.g.ghostty_theme_statusline = false " keep lualine's colours after a switch
--
-- Commands: `:GhosttyTheme` re-resolves and reports,
-- `:GhosttyTheme!` also prints the palette in use.

-- Relative luminance above which a background counts as light
local LIGHT_THRESHOLD = 0.35

-- xterm palette, for entries a theme/config leaves unset
local DEFAULT_PALETTE = {
  [0] = '#000000',
  [1] = '#cc0000',
  [2] = '#4e9a06',
  [3] = '#c4a000',
  [4] = '#3465a4',
  [5] = '#75507b',
  [6] = '#06989a',
  [7] = '#d3d7cf',
  [8] = '#555753',
  [9] = '#ef2929',
  [10] = '#8ae234',
  [11] = '#fce94f',
  [12] = '#729fcf',
  [13] = '#ad7fa8',
  [14] = '#34e2e2',
  [15] = '#eeeeec',
}

-- Theme directories, user themes first
local THEME_DIRS = {
  (vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. '/.config')) .. '/ghostty/themes',
  '/Applications/Ghostty.app/Contents/Resources/ghostty/themes',
  '/usr/local/share/ghostty/themes',
  '/usr/share/ghostty/themes',
}

local applying = false -- guards the OptionSet('background') hook
local warned = false -- only nag once about a missing palette
local last = nil -- last applied state, see apply()
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
local function norm(value)
  local found = value and value:match('#%x+')
  if not found then
    return nil
  end
  local r, g, b = rgb(found)
  return r and hexstr(r, g, b) or nil
end

-- sRGB channel linearization, for WCAG relative luminance
local function linearize(v)
  if v <= 0.04045 then
    return v / 12.92
  end
  return ((v + 0.055) / 1.055) ^ 2.4
end

local function luminance(color)
  local r, g, b = rgb(color)
  if not r then
    return 0
  end
  return 0.2126 * linearize(r / 255) + 0.7152 * linearize(g / 255) + 0.0722 * linearize(b / 255)
end

local function contrast(a, b)
  local la, lb = luminance(a), luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

-- Blend colour a towards b by t (0..1)
local function mix(a, b, t)
  local ar, ag, ab = rgb(a)
  local br, bg, bb = rgb(b)
  if not (ar and br) then
    return a
  end
  return hexstr(ar + (br - ar) * t, ag + (bg - ag) * t, ab + (bb - ab) * t)
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

local function config_path()
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
local function read_config(path, data, seen)
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
        data[key] = norm(value) or data[key]
      elseif key == 'palette' then
        local index, color = value:match('^(%d+)%s*=%s*(.-)$')
        index, color = tonumber(index), norm(color)
        if index and color then
          data.palette[index] = color
        end
      elseif key == 'theme' then
        data.theme = strip_comment(value)
      elseif key == 'config-file' then
        -- `config-file = ?auto/theme.ghostty` (the theme picker writes here)
        local target = value:gsub('^%?%s*', ''):gsub('^"(.*)"$', '%1')
        target = target:gsub('^~', vim.env.HOME or '~')
        if target:sub(1, 1) ~= '/' then
          target = (path:match('^(.*)/[^/]*$') or '.') .. '/' .. target
        end
        read_config(target, data, seen)
      end
    end
  end
  file:close()
  return data
end

-- Read a theme file by name, from the first directory that has it
local function read_theme(name)
  for _, dir in ipairs(THEME_DIRS) do
    local path = dir .. '/' .. name
    if vim.uv.fs_stat(path) then
      return read_config(path)
    end
  end
  return nil
end

-- macOS appearance: 'light' | 'dark', which is what ghostty follows for
-- `theme = light:...,dark:...`. Cached, it spawns a process.
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

-- Pick the theme name of the active light/dark variant
local function active_name(theme)
  if not theme or theme == '' then
    return nil
  end
  local light, dark = theme:match('^%s*light:%s*"([^"]*)"%s*,%s*dark:%s*"([^"]*)"')
  if light and dark then
    return (appearance() == 'light') and light or dark
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

-- Resolve the colours in use: { bg, fg, palette, name, source, id } or nil
local function resolve()
  local config = read_config(config_path())
  local name = active_name(config.theme)
  local theme = name and read_theme(name) or nil

  -- ghostty applies config values on top of the theme
  local bg = config.background or (theme and theme.background)
  if not bg then
    return nil
  end
  local fg = config.foreground
    or (theme and theme.foreground)
    or (luminance(bg) > LIGHT_THRESHOLD and '#1a1a1a' or '#e6e6e6')

  local palette = {}
  for i = 0, 15 do
    palette[i] = config.palette[i]
      or (theme and theme.palette[i])
      or DEFAULT_PALETTE[i]
  end

  local keys = { bg, fg }
  for i = 0, 15 do
    keys[#keys + 1] = palette[i]
  end
  return {
    bg = bg,
    fg = fg,
    palette = palette,
    name = (theme and name) or 'config',
    source = theme and 'theme' or 'config',
    id = table.concat(keys, ':'),
  }
end

-- Named colours, derived from the palette
local function roles(spec)
  local bg, fg, palette = spec.bg, spec.fg, spec.palette
  local fg_contrast = contrast(fg, bg)
  -- of two candidates (base and bright), take the readabler one
  local function pick(a, b)
    return (contrast(a, bg) >= contrast(b, bg)) and a or b
  end
  -- ... and nudge it towards the foreground until it is readable on bg, which
  -- saves low-contrast palettes (e.g. Man Page's colours on its yellow bg)
  local function ensure(color, min)
    for i = 0, 10 do
      if contrast(color, bg) >= min then
        break
      end
      color = mix(color, fg, i / 10)
    end
    return color
  end
  local function accent(base, bright)
    return ensure(pick(palette[base], palette[bright]), 3.0)
  end
  -- palette 8 is the conventional comment colour, but some themes set it to
  -- the foreground (or to something invisible): then blend, don't shout
  local comment = palette[8]
  local comment_contrast = contrast(comment, bg)
  if comment_contrast < 1.8 or comment_contrast > 0.62 * fg_contrast then
    comment = mix(bg, fg, 0.45)
  end
  return {
    bg = bg,
    fg = fg,
    shade = mix(bg, fg, 0.06),
    surface = mix(bg, fg, 0.10),
    select = mix(bg, fg, 0.20),
    border = mix(bg, fg, 0.30),
    muted = mix(bg, fg, 0.55),
    comment = comment,
    red = accent(1, 9),
    green = accent(2, 10),
    yellow = accent(3, 11),
    blue = accent(4, 12),
    magenta = accent(5, 13),
    cyan = accent(6, 14),
  }
end

local function highlight_groups(c)
  local groups = {
    Normal = { fg = c.fg, bg = c.bg },
    NormalNC = { fg = c.fg, bg = c.bg },
    NormalFloat = { fg = c.fg, bg = c.surface },
    FloatBorder = { fg = c.border, bg = c.surface },
    FloatTitle = { fg = c.yellow, bg = c.surface, bold = true },

    CursorLine = { bg = c.shade },
    CursorColumn = { bg = c.shade },
    ColorColumn = { bg = c.shade },
    LineNr = { fg = c.muted },
    CursorLineNr = { fg = c.yellow, bold = true },
    SignColumn = { bg = c.bg },
    FoldColumn = { fg = c.muted, bg = c.bg },
    Folded = { fg = c.muted, bg = c.surface },
    NonText = { fg = c.muted },
    EndOfBuffer = { fg = c.bg },
    Whitespace = { fg = c.shade },
    VertSplit = { fg = c.border },
    WinSeparator = { fg = c.border },
    Conceal = { fg = c.muted },

    Visual = { bg = c.select },
    Search = { fg = c.bg, bg = c.yellow },
    IncSearch = { fg = c.bg, bg = c.cyan },
    CurSearch = { fg = c.bg, bg = c.magenta },
    MatchParen = { fg = c.yellow, bg = c.select, bold = true },
    QuickFixLine = { bg = c.select },

    StatusLine = { fg = c.fg, bg = c.surface },
    StatusLineNC = { fg = c.muted, bg = c.shade },
    StatusLineTerm = { fg = c.fg, bg = c.surface },
    StatusLineTermNC = { fg = c.muted, bg = c.shade },
    TabLine = { fg = c.muted, bg = c.shade },
    TabLineSel = { fg = c.fg, bg = c.surface, bold = true },
    TabLineFill = { bg = c.bg },

    Pmenu = { fg = c.fg, bg = c.surface },
    PmenuSel = { fg = c.bg, bg = c.blue },
    PmenuSbar = { bg = c.shade },
    PmenuThumb = { bg = c.muted },
    WildMenu = { fg = c.bg, bg = c.blue },

    Comment = { fg = c.comment, italic = true },
    Constant = { fg = c.cyan },
    String = { fg = c.green },
    Character = { fg = c.green },
    Number = { fg = c.cyan },
    Boolean = { fg = c.cyan },
    Float = { fg = c.cyan },
    Identifier = { fg = c.fg },
    Function = { fg = c.blue },
    Statement = { fg = c.magenta },
    Conditional = { fg = c.magenta },
    Repeat = { fg = c.magenta },
    Label = { fg = c.magenta },
    Operator = { fg = c.cyan },
    Keyword = { fg = c.magenta },
    Exception = { fg = c.red },
    PreProc = { fg = c.magenta },
    Include = { fg = c.magenta },
    Define = { fg = c.magenta },
    Macro = { fg = c.magenta },
    PreCondit = { fg = c.magenta },
    Type = { fg = c.yellow },
    StorageClass = { fg = c.yellow },
    Structure = { fg = c.yellow },
    Typedef = { fg = c.yellow },
    Special = { fg = c.yellow },
    SpecialChar = { fg = c.yellow },
    SpecialComment = { fg = c.yellow, italic = true },
    Delimiter = { fg = c.muted },
    Tag = { fg = c.cyan },
    Debug = { fg = c.red },
    Underlined = { underline = true },
    Ignore = { fg = c.muted },
    Error = { fg = c.red },
    Todo = { fg = c.yellow, bg = c.shade, bold = true },

    ErrorMsg = { fg = c.red },
    WarningMsg = { fg = c.yellow },
    MoreMsg = { fg = c.green },
    ModeMsg = { fg = c.green, bold = true },
    Question = { fg = c.green },
    Title = { fg = c.yellow, bold = true },
    Directory = { fg = c.blue },

    DiffAdd = { fg = c.green, bg = mix(c.bg, c.green, 0.15) },
    DiffChange = { fg = c.yellow, bg = mix(c.bg, c.yellow, 0.15) },
    DiffDelete = { fg = c.red, bg = mix(c.bg, c.red, 0.15) },
    DiffText = { fg = c.yellow, bg = mix(c.bg, c.yellow, 0.35) },
    diffAdded = { fg = c.green },
    diffRemoved = { fg = c.red },
    diffChanged = { fg = c.yellow },
    diffFile = { fg = c.blue },
    diffLine = { fg = c.muted },
    diffNewFile = { fg = c.yellow },
    diffOldFile = { fg = c.red },
  }

  for _, diag in ipairs({
    { 'Error', c.red },
    { 'Warn', c.yellow },
    { 'Info', c.cyan },
    { 'Hint', c.comment },
    { 'Ok', c.green },
  }) do
    local level, color = diag[1], diag[2]
    groups['Diagnostic' .. level] = { fg = color }
    groups['DiagnosticUnderline' .. level] = { sp = color, undercurl = true }
    groups['DiagnosticVirtualText' .. level] = { fg = color, bg = mix(c.bg, color, 0.10) }
  end

  return groups
end

-- Captures Neovim does not link to a classic group by itself (or links to
-- something we do not define), so treesitter output stays consistent
local LINKS = {
  ['@variable'] = 'Identifier',
  ['@variable.parameter'] = 'Identifier',
  ['@variable.member'] = 'Identifier',
  ['@field'] = 'Identifier',
  ['@property'] = 'Identifier',
  ['@function.call'] = 'Function',
  ['@function.method'] = 'Function',
  ['@method'] = 'Function',
  ['@method.call'] = 'Function',
  ['@keyword.function'] = 'Keyword',
  ['@keyword.operator'] = 'Operator',
  ['@conditional'] = 'Conditional',
  ['@repeat'] = 'Repeat',
  ['@namespace'] = 'Include',
  ['@string.special'] = 'SpecialChar',
  ['@punctuation.bracket'] = 'Delimiter',
  ['@punctuation.delimiter'] = 'Delimiter',
}

-- Replace every highlight group with the ones derived from `spec`
local function paint(spec)
  local c = roles(spec)
  vim.cmd('highlight clear')
  if vim.fn.exists('syntax_on') == 1 then
    vim.cmd('syntax reset')
  end
  vim.g.colors_name = 'ghostty'
  for name, group in pairs(highlight_groups(c)) do
    vim.api.nvim_set_hl(0, name, group)
  end
  for name, target in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = target })
  end
  for i = 0, 15 do
    vim.g['terminal_color_' .. i] = spec.palette[i]
  end
  -- plugins rebuild their own groups on ColorScheme; we never load a
  -- colorscheme file, so fire the event ourselves
  vim.api.nvim_exec_autocmds('ColorScheme', { pattern = 'ghostty' })
end

-- Statusline plugins (lualine, ...) build their highlight groups at setup time,
-- and painting above wiped them. Re-run lualine's setup, dropping cached theme
-- modules so a light/dark flip is not served from the previous background.
---@return boolean refreshed true when lualine was re-setup
local function refresh_statusline()
  if vim.g.ghostty_theme_statusline == false then
    return false
  end
  local refreshed = false
  if package.loaded['lualine'] then
    for name in pairs(package.loaded) do
      if type(name) == 'string' and name:match('^lualine%.themes%.') then
        package.loaded[name] = nil
      end
    end
    refreshed = pcall(function()
      require('lualine').setup()
    end)
  end
  pcall(vim.cmd, 'redrawstatus!')
  if vim.o.showtabline ~= 0 and vim.o.tabline ~= '' then
    pcall(vim.cmd, 'redrawtabline')
  end
  return refreshed
end

-- Apply a resolved spec. Only repaints when the colours changed (or `force`),
-- so a manual `:colorscheme` sticks until ghostty actually changes.
local function apply(spec, force)
  if not spec then
    return
  end
  if last and last.id == spec.id and not force then
    last.skipped = true
    return
  end

  local target = luminance(spec.bg) > LIGHT_THRESHOLD and 'light' or 'dark'
  applying = true
  if vim.o.background ~= target then
    vim.o.background = target -- schemes read it, and 'highlight clear' uses it
  end
  paint(spec)
  applying = false
  local statusline = refresh_statusline()

  last = {
    id = spec.id,
    name = spec.name,
    source = spec.source,
    colors = vim.g.colors_name,
    bg = spec.bg,
    fg = spec.fg,
    background = target,
    palette = spec.palette,
    statusline = statusline,
    skipped = false,
  }
end

local function report()
  if not last then
    return ('ghostty theme: no palette found in %s'):format(config_path())
  end
  if last.skipped then
    return ('ghostty theme: %s unchanged, kept colorscheme=%s (background=%s)'):format(
      last.name,
      last.colors or 'none',
      vim.o.background
    )
  end
  return ('ghostty theme: %s (%s) -> background=%s, colorscheme=%s, bg=%s fg=%s%s'):format(
    last.name,
    last.source,
    last.background,
    last.colors or 'none',
    last.bg,
    last.fg,
    last.statusline and ', statusline refreshed' or ''
  )
end

local function report_palette()
  if not last or not last.palette then
    return report()
  end
  local rows = {
    ('ghostty theme: %s (%s)'):format(last.name, last.source),
    ('  background %s   foreground %s'):format(last.bg, last.fg),
  }
  for i = 0, 15, 4 do
    local cells = {}
    for j = i, i + 3 do
      cells[#cells + 1] = ('%2d %s'):format(j, last.palette[j])
    end
    rows[#rows + 1] = '  palette  ' .. table.concat(cells, '  ')
  end
  return table.concat(rows, '\n')
end

--- Re-read the ghostty theme and repaint Neovim.
--- @param verbose boolean|nil Report the result in |:messages|.
--- @param force boolean|nil Repaint even when the colours did not change.
local function sync(verbose, force)
  local spec = resolve()
  if not spec then
    -- only complain once per session: a missing ghostty config is not fatal
    if verbose or not warned then
      warned = true
      vim.notify(
        ('ghostty theme: no `theme =`/`background =` in %s, leaving colours alone'):format(config_path()),
        vim.log.levels.WARN
      )
    end
    return
  end
  warned = false
  apply(spec, force)
  if verbose then
    vim.notify(report(), vim.log.levels.INFO)
  end
end

vim.api.nvim_create_autocmd({ 'UIEnter', 'VimEnter', 'FocusGained', 'VimResume' }, {
  callback = function()
    sync(false, false)
  end,
})

-- Neovim's own OSC 11 handling (and `:set background=`) may set 'background'
-- without touching the highlight groups; the ghostty palette decides here, so
-- put it back rather than half-switching the editor.
vim.api.nvim_create_autocmd('OptionSet', {
  pattern = 'background',
  callback = function()
    if applying then
      return
    end
    local spec = resolve()
    if not spec then
      return
    end
    local target = luminance(spec.bg) > LIGHT_THRESHOLD and 'light' or 'dark'
    if vim.o.background == target then
      return
    end
    applying = true
    vim.o.background = target
    applying = false
  end,
})

vim.api.nvim_create_user_command('GhosttyTheme', function(opts)
  if opts.bang then
    sync(false, true)
    vim.notify(report_palette() .. '\n' .. report(), vim.log.levels.INFO)
    return
  end
  sync(true, true)
end, { bang = true, desc = 'Repaint Neovim from the ghostty theme palette' })

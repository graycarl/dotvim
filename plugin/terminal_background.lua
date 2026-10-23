-- Terminal-driven light/dark background
--
-- Ghostty never pushes its palette to applications; it only answers queries
-- (OSC 4 / 10 / 11). The DEC mode 2031 change notification (CSI ? 997 ; n n)
-- is not parsed by Neovim core and does not surface through |TermResponse|,
-- so we query OSC 11 ourselves and re-query on focus/resume.
--
-- Colorschemes with light/dark variants (e.g. everforest) are reloaded when
-- 'background' changes, which makes them follow ghostty's
-- `theme = light:...,dark:...` setting.
--
-- Debug: `:TerminalBackground` re-queries and reports the detected value.

local pending = false

-- Last reply: { r, g, b, lum, bg } (channels are 0..1)
local last = nil

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

-- Parse an OSC 11 reply, e.g. "\27]11;rgb:2020/1111/1b1b\27\\"
local function parse_osc11(sequence)
  local r, g, b = sequence:match(']11;rgb:(%x+)/(%x+)/(%x+)')
  if not r then
    return nil
  end
  local function channel(hex)
    local value = tonumber(hex, 16)
    if #hex == 2 then
      return value / 255
    end
    return value / 65535
  end
  return channel(r), channel(g), channel(b)
end

-- Above this relative luminance the terminal counts as light
local LIGHT_THRESHOLD = 0.35

local function apply(r, g, b)
  local lum = luminance(r, g, b)
  local target = lum > LIGHT_THRESHOLD and 'light' or 'dark'
  if vim.o.background ~= target then
    vim.o.background = target
    if vim.g.colors_name then
      vim.cmd.colorscheme(vim.g.colors_name)
    end
  end
  last = { r = r, g = g, b = b, lum = lum, bg = target }
end

local function hex(v)
  return ('%02x'):format(math.floor(v * 255 + 0.5))
end

local function report()
  if not last then
    return 'terminal background: no reply (yet)'
  end
  return ('terminal background: #%s%s%s lum=%.3f -> %s (vim.o.background=%s)'):format(
    hex(last.r),
    hex(last.g),
    hex(last.b),
    last.lum,
    last.bg,
    vim.o.background
  )
end

--- Query the terminal background color and sync 'background'.
--- @param verbose boolean|nil Report the result in |:messages|.
local function sync(verbose)
  if pending or #vim.api.nvim_list_uis() == 0 then
    return
  end
  pending = true

  local id
  local function finish(ok)
    if id then
      pcall(vim.api.nvim_del_autocmd, id)
      id = nil
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
        return -- someone else's reply (OSC 4, DA1, ...)
      end
      apply(r, g, b)
      finish(true)
    end,
  })

  -- Give up if the terminal stays silent (not a tty, tmux without relay, ...)
  vim.defer_fn(function()
    finish(false)
  end, 400)

  -- io.stdout is the TUI's tty; there is no public API to write raw sequences
  io.stdout:write('\27]11;?\27\\')
  io.stdout:flush()
end

vim.api.nvim_create_autocmd({ 'UIEnter', 'VimEnter', 'FocusGained', 'VimResume' }, {
  callback = function()
    sync(false)
  end,
})

vim.api.nvim_create_user_command('TerminalBackground', function()
  if pending then
    return
  end
  sync(true)
end, { desc = 'Re-query terminal background color and sync background' })

-- DeepSeek FIM inline completion (ghost text), modelled after copilot.vim.
--
-- Loaded through `plugins.lua` with `cond = vim.env.VIM_AI == "deepseek"`.
-- Configured by `lua/setup/deepseek.lua`.
--
-- Flow: insert-mode autocmds -> debounce/throttle -> context.build() ->
-- api.request() -> api.filter() -> render.show().  While a request is in
-- flight, an already visible suggestion survives as long as the text typed
-- since then keeps matching its prefix ("sticky" suggestion); this hides the
-- ~1s API latency instead of flickering the ghost text away.
local api = require('deepseek.api')
local context = require('deepseek.context')
local cross_file = require('deepseek.cross_file')
local render = require('deepseek.render')

local M = {}

local defaults = {
  end_point = 'https://api.deepseek.com/beta/completions',
  model = 'deepseek-flash',
  key_file = (vim.env.VIMHOME or vim.fn.stdpath('config')) .. '/local/deepseek.key',
  filetypes = {
    python = true,
    dockerfile = true,
    make = true,
    bash = true,
    zsh = true,
    sh = true,
    lua = true,
    javascript = true,
    vim = true,
    gitcommit = true,
    markdown = true,
    toml = true,
    yaml = true,
    rust = true,
    typescript = true,
  },
  debounce = 300,
  throttle = 800,
  timeout = 8000,
  max_tokens = 128,
  temperature = 0,
  max_lines = 10,
  min_prompt_chars = 10,
  context = { total_tokens = 8000, prefix_ratio = 0.70, head_chars = 1000 },
  -- Cross-file context (see `:DeepSeek ctx` / `:DeepSeek eval`): implemented and
  -- measurable, but NOT wired into the prompt path yet.
  cross_file = {
    enabled = true,
    max_files = 6,
    max_lines = 25,
    max_chars = 1200,
    max_scan = 200,
    read_lines = 1000,
    separate = false,
    lua_locals = false,
  },
  keymaps = {
    accept = '<C-J>',
    accept_word = '<M-Right>',
    accept_line = '<M-C-Right>',
    dismiss = '<C-]>',
    refresh = '<M-\\>',
  },
}

local cfg = vim.deepcopy(defaults)

local state = {
  enabled = true,
  suggestion = nil, -- { buf, row, col, text } ; row/col = insert point of the request
  pending = nil, -- { job, target }
  queued = nil, -- text handed to the `<C-R>=` expression register during accept
  timer = nil,
  last_request_at = 0,
  last_error = nil,
  temperature_index = 1, -- rotated by `:DeepSeek`/`<M-\>` to get another candidate
  refresh_tries = 0,
  last_shown_text = nil,
}

---Temperatures used for repeated manual requests; the first entry follows the
---`temperature` option.
local temperatures = { 0, 0.3, 0.7 }

---@return boolean
local function mode_insert()
  return vim.api.nvim_get_mode().mode:sub(1, 1) == 'i'
end

---@return boolean
local function pum_visible()
  return vim.fn.pumvisible() == 1
end

---@param bufnr integer
---@return boolean
local function buffer_allowed(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.bo[bufnr].buftype ~= '' then
    return false
  end
  return cfg.filetypes[vim.bo[bufnr].filetype] == true
end

---Identify "the same place in the same buffer"; used to drop stale responses.
---@param bufnr integer
---@return string
local function target_key(bufnr)
  local pos = vim.api.nvim_win_get_cursor(0)
  return table.concat({ bufnr, vim.api.nvim_buf_get_changedtick(bufnr), pos[1], pos[2] }, ':')
end

local function cancel_pending()
  local pending = state.pending
  state.pending = nil
  if pending and pending.job then
    pcall(pending.job.kill, pending.job, 'sigint')
  end
end

---Text typed since the suggestion was requested, or nil when the suggestion no
---longer applies.  A non-nil result means "still valid, render this remainder".
---@return string|nil
local function sticky_remainder()
  local s = state.suggestion
  if not s then
    return nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  if s.buf ~= bufnr then
    return nil
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  if row ~= s.row or col < s.col then
    return nil
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local typed = line:sub(s.col + 1, col)
  if s.text:sub(1, #typed) ~= typed then
    return nil
  end
  return s.text:sub(#typed + 1)
end

---Drop the current suggestion and any in-flight request.
function M.dismiss()
  if state.timer then
    state.timer:stop()
    state.timer = nil
  end
  if state.suggestion then
    render.clear(state.suggestion.buf)
    state.suggestion = nil
  end
  cancel_pending()
end

---Insert the text prepared by `begin_accept()` (called from the `<C-R>=`
---expression register).
---@return string
function M.queued_text()
  local text = state.queued or ''
  state.queued = nil
  return text
end

---Leading non-keyword characters plus one word.
---@param text string
---@return string
local function take_word_prefix(text)
  local lead = text:match('^([^%w_]*)') or ''
  local word = text:sub(#lead + 1):match('^([%w_]*)') or ''
  return lead .. word
end

---Everything up to the first newline.
---@param text string
---@return string
local function take_line_prefix(text)
  return text:match('^([^\n]*)') or ''
end

---Consume the current suggestion and queue the part of it that should be
---inserted, returning the key sequence for the mapping to execute.
---@param mode 'all'|'word'|'line'
---@return string|nil
local function begin_accept(mode)
  local s = state.suggestion
  if not s then
    return nil
  end
  local remainder = sticky_remainder()
  if not remainder or remainder == '' then
    M.dismiss()
    return nil
  end
  local text = remainder
  if mode ~= 'all' then
    local prefix = mode == 'word' and take_word_prefix(remainder) or take_line_prefix(remainder)
    if prefix ~= '' then
      text = prefix
    end
  end
  state.suggestion = nil
  render.clear(s.buf)
  cancel_pending()
  state.queued = text
  local register = text:find('\n', 1, true) and '<C-R><C-O>=' or '<C-R><C-R>='
  local end_key = mode == 'all' and '<End>' or ''
  return register .. 'v:lua.require("deepseek").queued_text()<CR>' .. end_key
end

local fire

---Signature summaries of the modules this buffer imports, or '' when the
---feature is off / nothing resolves.  Cached per buffer (see cross_file.lua).
---@param bufnr integer
---@return string
local function cross_text(bufnr)
  if cfg.cross_file and cfg.cross_file.enabled == false then
    return ''
  end
  local ok, xf = pcall(cross_file.cached_build, bufnr, cfg)
  if not ok or type(xf) ~= 'table' then
    return ''
  end
  return xf.text or ''
end

---Request a completion (called by the debounce timer, or manually).
---@param manual boolean|nil true when triggered by `<M-\>`/`:DeepSeek refresh`
function fire(manual)
  state.timer = nil
  local bufnr = vim.api.nvim_get_current_buf()
  if not state.enabled or not mode_insert() or pum_visible() or not buffer_allowed(bufnr) then
    return
  end
  local ctx, err = context.build(bufnr, cfg, cross_text(bufnr))
  if not ctx then
    state.last_error = err
    return
  end
  local target = target_key(bufnr)
  if state.pending and state.pending.target == target then
    return
  end
  cancel_pending()

  local handle
  handle = api.request({
    model = cfg.model,
    prompt = ctx.prefix,
    suffix = ctx.suffix,
    max_tokens = cfg.max_tokens,
    temperature = temperatures[state.temperature_index] or 0,
    stream = false,
  }, cfg, function(text, request_err)
    -- Superseded by a newer request (or cancelled): drop silently.
    if not state.pending or state.pending.job ~= handle then
      return
    end
    state.pending = nil
    if request_err then
      state.last_error = request_err
      return
    end
    if not state.enabled or not mode_insert() or pum_visible() then
      return
    end
    if vim.api.nvim_get_current_buf() ~= bufnr or target_key(bufnr) ~= target then
      return
    end
    local clean = api.filter(text or '', ctx, cfg)
    clean = render.prepare(bufnr, clean)
    if clean == '' then
      return
    end
    -- A manual request that returns exactly what is already on screen is
    -- useless; rotate the temperature instead of flickering (max 2 retries).
    if manual and clean == state.last_shown_text and state.refresh_tries < 2 then
      state.refresh_tries = state.refresh_tries + 1
      state.temperature_index = state.temperature_index % #temperatures + 1
      return fire(true)
    end
    state.refresh_tries = 0
    state.last_shown_text = clean
    local pos = vim.api.nvim_win_get_cursor(0)
    state.suggestion = { buf = bufnr, row = pos[1] - 1, col = pos[2], text = clean }
    state.last_error = nil
    render.show(bufnr, clean)
  end)
  state.pending = { job = handle, target = target }
  state.last_request_at = vim.uv.now()
end

---Ask for another candidate (rotates temperature, bypasses the throttle).
function M.refresh()
  if not state.enabled or not mode_insert() then
    return
  end
  state.temperature_index = state.temperature_index % #temperatures + 1
  if state.temperature_index == 1 then
    state.refresh_tries = 0
  end
  M.dismiss()
  state.last_request_at = 0
  fire(true)
end

---Re-evaluate what should be on screen (called from insert-mode autocmds).
function M.schedule()
  local bufnr = vim.api.nvim_get_current_buf()
  if not state.enabled or not mode_insert() or pum_visible() or not buffer_allowed(bufnr) then
    return M.dismiss()
  end

  local remaining = sticky_remainder()
  if remaining then
    if remaining == '' then
      render.clear(bufnr)
    else
      render.show(bufnr, remaining)
    end
    return
  end

  M.dismiss()

  local delay = cfg.debounce
  local since = vim.uv.now() - state.last_request_at
  if state.last_request_at > 0 and since < cfg.throttle then
    delay = math.max(delay, cfg.throttle - since)
  end
  state.timer = vim.defer_fn(fire, delay)
end

---Internal state, for tests and `:DeepSeek`.
---@return table
function M._debug()
  return { enabled = state.enabled, pending = state.pending ~= nil, suggestion = state.suggestion,
           timer = state.timer ~= nil, last_error = state.last_error,
           last_request_at = state.last_request_at }
end

---@return string[]
local function status_lines()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = {
    'DeepSeek: ' .. (state.enabled and 'enabled' or 'disabled'),
    ('  model    : %s'):format(cfg.model),
    ('  key file : %s (%s)'):format(cfg.key_file, api.read_key(cfg) and 'ok' or 'MISSING'),
    ('  filetype : %s (%s)'):format(
      vim.bo[bufnr].filetype,
      buffer_allowed(bufnr) and 'active' or 'skipped'
    ),
    ('  pending  : %s'):format(state.pending and 'yes' or 'no'),
  }
  if cfg.cross_file and cfg.cross_file.enabled == false then
    lines[#lines + 1] = '  cross-file: off'
  else
    local xf = cross_file._cache()
    if xf and xf.bufnr == bufnr and xf.text ~= '' then
      lines[#lines + 1] =
        ('  cross-file: %d file(s), %d bytes (hits %d)'):format(#xf.files, #xf.text, xf.hits or 0)
    else
      lines[#lines + 1] = '  cross-file: on (nothing resolved for this buffer)'
    end
  end
  if state.suggestion then
    lines[#lines + 1] = ('  showing  : %d chars'):format(#state.suggestion.text)
  end
  local last = api.last
  if last then
    if last.canceled then
      lines[#lines + 1] = '  last     : canceled'
    elseif last.error then
      lines[#lines + 1] = ('  last     : %.0f ms, error: %s'):format(last.ms, last.error)
    else
      lines[#lines + 1] = ('  last     : %.0f ms, %d prompt / %d cached / %d completion tok')
        :format(last.ms, last.prompt_tokens or 0, last.cached_tokens or 0, last.completion_tokens or 0)
    end
  end
  if state.last_error then
    lines[#lines + 1] = '  error    : ' .. state.last_error
  end
  return lines
end

---Report lines in a scratch split (used by `:DeepSeek ctx` / `eval`).
---@param name string
---@param lines string[]
local function show_lines(name, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.cmd('botright split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.keymap.set('n', 'q', '<Cmd>close!<CR>', { buffer = buf, nowait = true })
end

---@return string[]
local function stats_lines()
  local s = api.stats
  local cache_rate = s.prompt_tokens > 0 and (100 * s.cached_tokens / s.prompt_tokens) or 0
  return {
    'DeepSeek stats (this session)',
    ('  requests    : %d (%d failed)'):format(s.requests, s.failed),
    ('  prompt tok  : %d'):format(s.prompt_tokens),
    ('  cached tok  : %d (%.1f%% of prompt)'):format(s.cached_tokens, cache_rate),
    ('  completion  : %d'):format(s.completion_tokens),
  }
end

function M._commands()
  vim.api.nvim_create_user_command('DeepSeek', function(args)
    local fargs = args.fargs
    local sub = fargs[1] or 'status'
    if sub == 'toggle' then
      state.enabled = not state.enabled
      if not state.enabled then
        M.dismiss()
      end
      vim.notify('DeepSeek: ' .. (state.enabled and 'enabled' or 'disabled'), vim.log.levels.INFO)
    elseif sub == 'stats' then
      vim.notify(table.concat(stats_lines(), '\n'), vim.log.levels.INFO)
    elseif sub == 'refresh' then
      M.refresh()
    elseif sub == 'cross' then
      cfg.cross_file = cfg.cross_file or {}
      cfg.cross_file.enabled = cfg.cross_file.enabled == false
      vim.notify(
        'DeepSeek: cross-file context ' .. (cfg.cross_file.enabled and 'on' or 'off'),
        vim.log.levels.INFO
      )
      M.refresh()
    elseif sub == 'ctx' then
      -- Which files the cross-file block would pull in, and the block itself.
      local xf = require('deepseek.cross_file').build(vim.api.nvim_get_current_buf(), cfg)
      local lines = {
        ('cross-file block: %d bytes, %d file(s)'):format(#xf.text, #xf.files),
      }
      for _, f in ipairs(xf.files) do
        lines[#lines + 1] = ('  + %s  (from %q)'):format(f.rel, f.spec)
      end
      for _, s in ipairs(xf.skipped) do
        lines[#lines + 1] = ('  - %s: %s'):format(s.spec, s.reason)
      end
      lines[#lines + 1] = ''
      vim.list_extend(lines, vim.split(xf.text, '\n', { plain = true }))
      show_lines('deepseek-ctx', lines)
    elseif sub == 'eval' then
      local file = vim.api.nvim_buf_get_name(0)
      if file == '' then
        vim.notify('DeepSeek: eval needs a file-backed buffer', vim.log.levels.WARN)
        return
      end
      local n = tonumber(fargs[2]) or 4
      local modes = fargs[3] == 'all' and { 'call_site', 'line_end' } or { 'call_site' }
      vim.notify('DeepSeek: evaluating ' .. file, vim.log.levels.INFO)
      require('deepseek.eval').run({
        cfg = cfg,
        files = { file },
        n = n,
        modes = modes,
        quiet = true,
        on_done = function(report) show_lines('deepseek-eval', report.lines) end,
      })
    elseif sub == 'status' then
      vim.notify(table.concat(status_lines(), '\n'), vim.log.levels.INFO)
    else
      vim.notify('DeepSeek: unknown subcommand: ' .. sub, vim.log.levels.WARN)
    end
  end, {
    nargs = '*',
    complete = function()
      return { 'status', 'stats', 'toggle', 'refresh', 'ctx', 'eval', 'cross' }
    end,
  })
end

function M._keymaps()
  local km = cfg.keymaps or {}
  vim.keymap.set('i', km.accept or '<C-J>', function()
    return begin_accept('all') or '<CR>'
  end, { expr = true, silent = true, desc = 'DeepSeek: accept suggestion' })

  -- Accepting one word / one line is a plain prefix of the suggestion; the rest
  -- is dropped (same behaviour as copilot.vim).
  vim.keymap.set('i', km.accept_word or '<M-Right>', function()
    return begin_accept('word') or '<Right>'
  end, { expr = true, silent = true, desc = 'DeepSeek: accept word' })

  vim.keymap.set('i', km.accept_line or '<M-C-Right>', function()
    return begin_accept('line') or '<CR>'
  end, { expr = true, silent = true, desc = 'DeepSeek: accept line' })

  vim.keymap.set('i', km.dismiss or '<C-]>', function()
    M.dismiss()
    return '<C-]>'
  end, { expr = true, silent = true, desc = 'DeepSeek: dismiss suggestion' })

  vim.keymap.set('i', km.refresh or '<M-\\>', function()
    M.refresh()
  end, { silent = true, desc = 'DeepSeek: ask for another suggestion' })
end

---@param opts table|nil
function M.setup(opts)
  cfg = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  state.enabled = true
  temperatures = { cfg.temperature or 0, 0.3, 0.7 }

  if not api.read_key(cfg) then
    vim.schedule(function()
      vim.notify(
        ('DeepSeek: API key not readable at %s (completion disabled until it exists)'):format(
          cfg.key_file
        ),
        vim.log.levels.WARN
      )
    end)
  end

  local group = vim.api.nvim_create_augroup('deepseek_fim', { clear = true })
  -- Deferred by one tick: during InsertEnter `nvim_get_mode()` still reports
  -- normal mode, which would make schedule() bail out immediately.
  vim.api.nvim_create_autocmd(
    { 'InsertEnter', 'CursorMovedI', 'TextChangedI', 'CompleteChanged' },
    { group = group, callback = function() vim.schedule(M.schedule) end }
  )
  -- Summarising the imported files costs a few ms; do it while the user is
  -- still typing instead of inside the request path.
  vim.api.nvim_create_autocmd('InsertEnter', {
    group = group,
    callback = function()
      vim.schedule(function()
        pcall(cross_file.cached_build, vim.api.nvim_get_current_buf(), cfg)
      end)
    end,
  })
  vim.api.nvim_create_autocmd('InsertLeavePre', {
    group = group,
    callback = function() M.dismiss() end,
  })

  M._keymaps()
  M._commands()
  return M
end

return M

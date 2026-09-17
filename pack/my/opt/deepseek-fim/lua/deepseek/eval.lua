-- Offline evaluation harness for the cross-file context proposal.
--
-- It samples real cursor positions from real files, asks the API for a
-- completion with and without the cross-file block, and compares both against
-- the text that actually follows in the file (the ground truth).  Samples are
-- split by whether they *need* knowledge from another file, so "does this help?"
-- becomes a number instead of a feeling.
--
-- The cursor override is only used by this harness, so the A/B is always run
-- through the same `context.build()` layout the runtime produces (cross-file
-- material above the `# Path:` marker).
--
--   require('deepseek.eval').run({ files = { 'a.py' }, n = 3, cfg = cfg })
--   :DeepSeek eval 3
local M = {}

local api = require('deepseek.api')
local context = require('deepseek.context')
local cross_file = require('deepseek.cross_file')

---Definition shapes, used to tell "defined in this file" from "imported".
local DEF_PATTERNS = {
  '^%s*def%s+([%w_]+)',
  '^%s*async%s+def%s+([%w_]+)',
  '^%s*class%s+([%w_]+)',
  '^%s*local%s+function%s+([%w_]+)',
  '^%s*function%s+[%w_%.]-[%.:]([%w_]+)%s*%(',
  '^%s*pub%s+fn%s+([%w_]+)',
  '^%s*fn%s+([%w_]+)',
  '^%s*pub%s+struct%s+([%w_]+)',
  '^%s*pub%s+enum%s+([%w_]+)',
  '^%s*const%s+([%w_]+)',
  '^%s*let%s+([%w_]+)',
  '^%s*export%s+function%s+([%w_]+)',
  '^%s*export%s+const%s+([%w_]+)',
  '^%s*([%w_]+)%s*=%s*function',
  '^%s*local%s+([%w_]+)%s*=',
}

---Not worth sampling: language keywords, common builtins.
local KEYWORDS = {
  ['if'] = true, ['for'] = true, ['while'] = true, ['return'] = true, ['end'] = true,
  ['else'] = true, ['elif'] = true, ['try'] = true, ['except'] = true, ['with'] = true,
  ['lambda'] = true, ['match'] = true, ['case'] = true, ['await'] = true, ['yield'] = true,
  ['print'] = true, ['len'] = true, ['range'] = true, ['str'] = true, ['int'] = true,
  ['dict'] = true, ['list'] = true, ['set'] = true, ['type'] = true, ['super'] = true,
  ['function'] = true, ['local'] = true, ['then'] = true, ['do'] = true, ['nil'] = true,
  ['self'] = true, ['this'] = true, ['new'] = true, ['let'] = true, ['var'] = true,
  ['import'] = true, ['require'] = true, ['from'] = true, ['as'] = true, ['def'] = true,
  ['class'] = true, ['pub'] = true, ['fn'] = true, ['use'] = true, ['mod'] = true,
  ['export'] = true, ['async'] = true, ['assert'] = true, ['not'] = true, ['and'] = true,
  ['or'] = true, ['in'] = true, ['is'] = true, ['pass'] = true, ['raise'] = true,
}

---@param s string
---@return string single line, for tabular output
local function one_line(s)
  return (vim.trim(s or ''):gsub('\n', '⏎'):gsub('\t', ' '))
end

---@param text string
---@return table set of names defined in the file
local function local_defs(text)
  local set = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    for _, pat in ipairs(DEF_PATTERNS) do
      local name = line:match(pat)
      if name then
        set[name] = true
      end
    end
  end
  return set
end

---Identifiers appearing in a block of text.  Used to decide which samples
---actually depend on the material the cross-file block adds: only names that
---show up in the resolved summaries count, so calls into libraries that could
---not be resolved are never mistaken for cross-file samples.
---@param text string
---@return table set
local function tokens_of(text)
  local set = {}
  for word in text:gmatch('[%a_][%w_]*') do
    set[word] = true
  end
  return set
end

---@param name string|nil
---@param tokens table
---@param defs table
---@return string bucket 'cross_file' | 'local' | 'other'
local function classify(name, tokens, defs)
  if not name or KEYWORDS[name] then
    return 'other'
  end
  if defs[name] then
    return 'local'
  end
  if tokens[name] then
    return 'cross_file'
  end
  return 'other'
end

---@param line string
---@return boolean
local function is_comment_or_blank(line)
  local t = vim.trim(line)
  return t == '' or t:match('^[#/%-]+') ~= nil or t:match('^%*') ~= nil
end

---Candidate positions in a file.
---  `line_end`  - cursor at the end of a code line, ground truth = next line
---  `call_site` - cursor right after `(` of a call to an imported name
---@param lines string[]
---@param ft string
---@param tokens table
---@param defs table
---@param mode string
---@return table[]
local function samples(lines, ft, tokens, defs, mode)
  local out = {}
  if mode == 'line_end' then
    for i = 1, #lines - 1 do
      local line = lines[i]
      if not is_comment_or_blank(line) and #vim.trim(line) > 3 then
        local gt
        for j = i + 1, math.min(i + 2, #lines) do
          if not is_comment_or_blank(lines[j]) then
            gt = lines[j]
            break
          end
        end
        if gt and #vim.trim(gt) > 1 then
          local head = vim.trim(gt):match('^([%w_]+)')
          out[#out + 1] = {
            mode = mode,
            row = i,
            col = #line,
            gt = gt,
            bucket = classify(head, tokens, defs),
          }
        end
      end
    end
  else
    for i, line in ipairs(lines) do
      local init = 1
      while true do
        local s, e, callee = line:find('([%a_][%w_%.:]*)(%()', init)
        if not s then
          break
        end
        init = e + 1
        local root = callee:match('^([%w_]+)')
        local tail = callee:match('([%w_]+)$')
        local rest = line:sub(e + 1)
        if s > 1 and line:sub(s - 1, s - 1):match('[%w_%.]') == nil then
          -- skip `def foo(` / keywords
          local is_def = line:sub(1, s - 1):match('^%s*(def|class|function|local|if|for|while|return)%s*$') ~= nil
          local in_tokens = tokens[root] or tokens[tail]
          local known = defs[root] or defs[tail]
          local has_text = vim.trim(rest):match('^[%)%s]*$') == nil
          if not is_def and in_tokens and not known and has_text and not KEYWORDS[root] then
            out[#out + 1] = {
              mode = mode,
              row = i,
              col = e,
              gt = rest,
              bucket = 'cross_file',
              callee = callee,
            }
          end
        end
      end
    end
  end
  return out
end

---@param list table[]
---@param n integer
---@return table[]
local function pick(list, n)
  if #list <= n then
    return list
  end
  local out = {}
  local step = #list / n
  for k = 1, n do
    out[#out + 1] = list[math.floor((k - 1) * step) + 1]
  end
  return out
end

---@param s string
---@return string first line, trimmed
local function first_line(s)
  return vim.trim((s:match('^([^\n]*)') or ''))
end

---Split into word and punctuation tokens, ignoring whitespace, so that
---formatting differences (line breaks, alignment) do not count as errors.
---@param s string
---@return string[]
local function tokens(s)
  local out, i = {}, 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch:match('%s') then
      i = i + 1
    elseif ch:match('[%w_]') then
      local _, e = s:find('^[%w_]+', i)
      out[#out + 1] = s:sub(i, e)
      i = e + 1
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return out
end

---Token-level Levenshtein distance.
---@param a string[]
---@param b string[]
---@return integer
local function levenshtein(a, b)
  local prev = {}
  for j = 0, #b do
    prev[j] = j
  end
  for i = 1, #a do
    local cur = { [0] = i }
    for j = 1, #b do
      local cost = a[i] == b[j] and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[#b]
end

---Multiset token F1: how much of the answer's *content* is present, regardless
---of order (a model that writes the right argument names in a different order
---still scores).
---@param a string[]
---@param b string[]
---@return number 0..1
local function token_f1(a, b)
  if #a == 0 or #b == 0 then
    return 0
  end
  local counts = {}
  for _, tok in ipairs(a) do
    counts[tok] = (counts[tok] or 0) + 1
  end
  local overlap = 0
  for _, tok in ipairs(b) do
    local n = counts[tok]
    if n and n > 0 then
      counts[tok] = n - 1
      overlap = overlap + 1
    end
  end
  return 2 * overlap / (#a + #b)
end

---How many leading tokens agree with the ground truth (0..limit).
---@param a string[]
---@param b string[]
---@param limit integer
---@return integer
local function leading_match(a, b, limit)
  local n = 0
  for i = 1, math.min(limit, #a, #b) do
    if a[i] ~= b[i] then
      break
    end
    n = n + 1
  end
  return n
end

---First `n` non-empty lines, joined -- single-line metrics underrate a
---completion that wraps the right arguments over several lines.
---@param s string
---@param n integer
---@return string
local function first_lines(s, n)
  local out = {}
  for line in (s .. '\n'):gmatch('([^\n]*)\n') do
    if vim.trim(line) ~= '' then
      out[#out + 1] = line
      if #out >= n then
        break
      end
    end
  end
  return table.concat(out, ' ')
end

---Metrics for one completion.
---  first      first identifier matches the ground truth
---  exact      first line identical
---  exact_norm identical ignoring whitespace
---  lead1      at least one leading token matches (graded, see `lead`)
---  lead       number of matching leading tokens, capped at 8
---  f1/sim     multiset F1 and token edit similarity, first line
---  f1m/simm   same, but tolerant of a multi-line completion
---@param comp string
---@param gt string
---@return table
local function compare(comp, gt)
  local c, g = first_line(comp), first_line(gt)
  local ct, gt_tokens = tokens(c), tokens(g)
  local ct_first, gt_first = c:match('^([%w_]+)'), g:match('^([%w_]+)')
  local lead = leading_match(ct, gt_tokens, 8)
  local longer = math.max(#ct, #gt_tokens)
  local cm = tokens(first_lines(comp, 3))
  local longer_m = math.max(#cm, #gt_tokens)
  return {
    first = ct_first ~= nil and gt_first ~= nil and ct_first == gt_first,
    exact = c ~= '' and c == g,
    exact_norm = c ~= '' and (c:gsub('%s+', '')) == (g:gsub('%s+', '')),
    lead = lead,
    lead1 = lead >= 1,
    lead4 = lead >= 4,
    f1 = token_f1(ct, gt_tokens),
    sim = longer > 0 and (1 - levenshtein(ct, gt_tokens) / longer) or 0,
    f1m = token_f1(cm, gt_tokens),
    simm = longer_m > 0 and (1 - levenshtein(cm, gt_tokens) / longer_m) or 0,
  }
end

---@param records table[]
---@return table
local function tally(records)
  local t = {
    n = 0,
    first = 0,
    exact = 0,
    exact_norm = 0,
    lead1 = 0,
    lead4 = 0,
    lead = 0,
    f1 = 0,
    sim = 0,
    f1m = 0,
    simm = 0,
    prompt = 0,
    cached = 0,
    ms = 0,
    errors = 0,
    empty = 0,
  }
  for _, r in ipairs(records) do
    t.n = t.n + 1
    t.errors = t.errors + (r.err and 1 or 0)
    t.empty = t.empty + (r.comp == '' and 1 or 0)
    t.first = t.first + (r.first and 1 or 0)
    t.exact = t.exact + (r.exact and 1 or 0)
    t.exact_norm = t.exact_norm + (r.exact_norm and 1 or 0)
    t.lead1 = t.lead1 + (r.lead1 and 1 or 0)
    t.lead4 = t.lead4 + (r.lead4 and 1 or 0)
    t.lead = t.lead + (r.lead or 0)
    t.f1 = t.f1 + (r.f1 or 0)
    t.sim = t.sim + (r.sim or 0)
    t.f1m = t.f1m + (r.f1m or 0)
    t.simm = t.simm + (r.simm or 0)
    t.prompt = t.prompt + (r.prompt_tokens or 0)
    t.cached = t.cached + (r.cached_tokens or 0)
    t.ms = t.ms + (r.ms or 0)
  end
  return t
end

---Exact two-sided sign test (binomial with p = 0.5): the probability of seeing
---at least this lopsided a split by chance.  Small n makes it forgiving, which
---is the point -- it stops "+2 out of 30" from looking like a result.
---@param wins integer
---@param losses integer
---@return number p
local function sign_test(wins, losses)
  local n = wins + losses
  if n == 0 then
    return 1
  end
  local k = math.min(wins, losses)
  local pmf, sum = 2 ^ -n, 0
  for i = 0, n do
    if i > 0 then
      pmf = pmf * (n - i + 1) / i
    end
    if i <= k then
      sum = sum + pmf
    end
  end
  return math.min(1, 2 * sum)
end

---@param t table
---@param key string
---@return string
local function pct(t, key)
  if t.n == 0 then
    return '-'
  end
  return ('%d/%d'):format(t[key], t.n)
end

-- ------------------------------------------------------------------ run ---

---Run the A/B over `opts.files`.
---@param opts table
---  files         string[] absolute paths (required)
---  cfg           table plugin config (required)
---  n             integer samples per file and mode (default 3)
---  modes         string[] default `{ 'call_site', 'line_end' }`
---  max_requests  integer default 40
---  concurrency   integer default 2
---  quiet         boolean do not print, only return the report
---  dry           boolean only list the sampled positions, no API calls
---  record_raw    boolean keep the raw response and filter trace for every sample
---  on_done       fun(report: table)|nil
---@return table report `{ lines = string[], records = table, totals = table }`
function M.run(opts)
  opts = opts or {}
  local cfg = assert(opts.cfg, 'eval.run requires cfg')
  local n = opts.n or 3
  local modes = opts.modes or { 'call_site', 'line_end' }
  local max_requests = opts.max_requests or 40
  local concurrency = math.max(1, opts.concurrency or 2)

  local report = { lines = {}, records = {}, totals = {} }
  local headless = #vim.api.nvim_list_uis() == 0
  local function say(fmt, ...)
    local line = select('#', ...) > 0 and fmt:format(...) or fmt
    report.lines[#report.lines + 1] = line
    if not opts.quiet then
      if headless then
        -- `print('')` emits nothing at all in headless Neovim (not even a
        -- newline) and consecutive prints get glued into one line, so write
        -- straight to stdout instead.
        io.stdout:write(line, '\n')
      else
        print(line)
      end
    end
  end

  local picked = {}
  local scratch = {}
  local files = 0
  for _, path in ipairs(opts.files or {}) do
    local ok, lines = pcall(vim.fn.readfile, path, '', 5000)
    if not ok or #lines == 0 then
      say('skip %s (unreadable)', path)
    else
      files = files + 1
      local ft = vim.filetype.match({ filename = path }) or 'text'
      local text = table.concat(lines, '\n')
      local defs = local_defs(text)
      local xf = cross_file.build_text(text, path, ft, cfg)
      local tokens = tokens_of(xf.text)
      local buf = vim.fn.bufnr(path)
      if buf == -1 then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        pcall(vim.api.nvim_buf_set_name, buf, path)
        scratch[#scratch + 1] = buf
      end
      vim.bo[buf].filetype = ft
      for _, mode in ipairs(modes) do
        for _, s in ipairs(pick(samples(lines, ft, tokens, defs, mode), n)) do
          s.path = path
          s.ft = ft
          s.buf = buf
          s.xf = xf.text
          s.base = context.build(buf, cfg, nil, { s.row, s.col })
          s.cross = xf.text ~= '' and context.build(buf, cfg, xf.text, { s.row, s.col }) or nil
          if s.base then
            picked[#picked + 1] = s
          end
        end
      end
    end
  end

  -- Cap whole samples, never a single variant: an unpaired record cannot enter
  -- the paired comparison and would skew the per-variant totals.
  if #picked * 2 > max_requests then
    local keep = math.max(1, math.floor(max_requests / 2))
    local trimmed = {}
    for i = 1, math.min(keep, #picked) do
      trimmed[i] = picked[i]
    end
    picked = trimmed
  end
  local jobs = {}
  for _, s in ipairs(picked) do
    jobs[#jobs + 1] = { sample = s, variant = 'base', ctx = s.base }
    if s.cross then
      jobs[#jobs + 1] = { sample = s, variant = 'cross', ctx = s.cross }
    end
  end
  if opts.dry then
    say('deepseek eval (dry run): %d files, %d candidate requests', files, #jobs)
    for _, job in ipairs(jobs) do
      if job.variant == 'base' then
        say('  %-10s %-11s %-16s line %-4d gt=%q', job.sample.mode, job.sample.bucket,
          vim.fn.fnamemodify(job.sample.path, ':t'), job.sample.row,
          vim.trim(job.sample.gt):sub(1, 60))
      end
    end
    for _, buf in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if opts.on_done then
      opts.on_done(report)
    end
    return report
  end
  say('deepseek eval: %d files, %d requests, model %s', files, #jobs, cfg.model)
  if #jobs == 0 then
    say('no samples found')
    for _, buf in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    if opts.on_done then
      opts.on_done(report)
    end
    return report
  end

  local records = report.records
  local inflight, finished = 0, 0
  local function record(item, text, err, usage)
    local trace = {}
    local comp = (not err and text and api.filter(text, item.ctx, cfg, trace)) or ''
    local m = compare(comp, item.sample.gt)
    records[#records + 1] = {
      file = vim.fn.fnamemodify(item.sample.path, ':t'),
      full_path = item.sample.path,
      row = item.sample.row,
      col = item.sample.col,
      mode = item.sample.mode,
      bucket = item.sample.bucket,
      variant = item.variant,
      gt = item.sample.gt,
      suffix = item.ctx.suffix,
      comp = comp,
      -- Kept for empty results (and for everything with `record_raw`) so a
      -- dropped completion can be traced back to the filter stage that ate it.
      raw = (comp == '' or opts.record_raw) and text or nil,
      trace = (comp == '' or opts.record_raw) and trace or nil,
      first = m.first,
      exact = m.exact,
      exact_norm = m.exact_norm,
      lead = m.lead,
      lead1 = m.lead1,
      lead4 = m.lead4,
      f1 = m.f1,
      sim = m.sim,
      f1m = m.f1m,
      simm = m.simm,
      err = err,
      ms = usage and usage.ms or 0,
      prompt_tokens = usage and usage.prompt_tokens or 0,
      cached_tokens = usage and usage.cached_tokens or 0,
      finish_reason = usage and usage.finish_reason or nil,
      choices = usage and usage.choices or 0,
    }
  end

  local pump
  local function finish()
    for _, buf in ipairs(scratch) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    -- A broken report must not swallow the caller's callback (and hang a run
    -- that is already paid for).
    local ok, err = pcall(M.report, report, say)
    if not ok then
      say('report error: %s', tostring(err))
    end
    if opts.on_done then
      opts.on_done(report)
    end
  end

  pump = function()
    while inflight < concurrency and #jobs > 0 do
      local item = table.remove(jobs, 1)
      inflight = inflight + 1
      local job = api.request({
        model = cfg.model,
        prompt = item.ctx.prefix,
        suffix = item.ctx.suffix,
        max_tokens = cfg.max_tokens,
        temperature = 0,
        stream = false,
      }, cfg, function(text, err, usage)
        inflight = inflight - 1
        finished = finished + 1
        record(item, text, err, usage)
        if finished == report.expected then
          finish()
        else
          pump()
        end
      end)
      if not job and inflight > 0 then
        -- `api.request` failed before starting (missing key, ...): the callback
        -- is still scheduled, so do not stall the pool.
        inflight = inflight - 1
      end
    end
  end
  report.expected = #jobs
  pump()
  return report
end

---Format the report (also called once all requests are in).
---@param report table
---@param say fun(fmt: string, ...)
function M.report(report, say)
  local records = report.records
  local function subset(variant, bucket)
    local out = {}
    for _, r in ipairs(records) do
      if r.variant == variant and (bucket == nil or r.bucket == bucket) then
        out[#out + 1] = r
      end
    end
    return out
  end

  -- Pair the two variants of the same sample so they can be read side by side.
  local order, by_key = {}, {}
  for _, r in ipairs(records) do
    local key = ('%s\0%d\0%d\0%s'):format(r.full_path, r.row, r.col, r.mode)
    local entry = by_key[key]
    if not entry then
      entry = { key = key, file = r.file, mode = r.mode, bucket = r.bucket, gt = r.gt }
      by_key[key] = entry
      order[#order + 1] = entry
    end
    entry[r.variant] = r
  end

  local function marks(r)
    if not r then
      return '   -   '
    end
    if r.err then
      return '  ERR  '
    end
    return ('%s%d/%.2f'):format(r.first and 'F' or '.', r.lead or 0, r.sim or 0)
  end

  say('')
  say('#   mode       bucket      file              base     cross    gt')
  for i, s in ipairs(order) do
    say('%-3d %-10s %-11s %-16s %-8s %-8s %s', i, s.mode, s.bucket, s.file, marks(s.base),
      marks(s.cross), one_line(s.gt):sub(1, 36))
    if s.base and s.cross and s.base.comp ~= s.cross.comp then
      say('      base : %s', one_line(s.base.comp):sub(1, 64))
      say('      cross: %s', one_line(s.cross.comp):sub(1, 64))
    end
  end
  say('(base/cross cell = F<leading tokens matched>/<token edit similarity>)')

  say('')
  say('%-8s %-10s %-4s %-7s %-7s %-6s %-6s %-6s %-5s %-8s %-11s %s', 'variant',
    'bucket', 'n', 'first', 'norm', 'lead1', 'sim', 'simm', 'empty', 'prompt', 'cached', 'ms')
  -- `ipairs` stops at the first nil, so the buckets need explicit labels.
  local buckets = { { key = nil, label = 'all' }, { key = 'cross_file', label = 'cross_file' } }
  for _, variant in ipairs({ 'base', 'cross' }) do
    for _, b in ipairs(buckets) do
      local t = tally(subset(variant, b.key))
      if t.n > 0 then
        local n = math.max(1, t.n)
        say(
          '%-8s %-10s %-4d %-7s %-7s %-6s %-6.3f %-6.3f %-5d %-8d %-11s %.0f',
          variant,
          b.label,
          t.n,
          pct(t, 'first'),
          pct(t, 'exact_norm'),
          pct(t, 'lead1'),
          t.sim / n,
          t.simm / n,
          t.empty,
          t.prompt,
          ('%d(%.0f%%)'):format(t.cached, 100 * t.cached / math.max(1, t.prompt)),
          t.ms / n
        )
      end
    end
  end

  -- Paired comparison: both variants answered the *same* cursor position, so
  -- only the differences carry information.  The sign test says whether a
  -- difference could plausibly be coin flips (it usually can, at this n).
  local paired = {}
  for _, s in ipairs(order) do
    if s.base and s.cross then
      paired[#paired + 1] = s
    end
  end
  say('')
  local function compare_paired(field)
    local wins, losses, ties = 0, 0, 0
    for _, s in ipairs(paired) do
      local a, b = s.base[field], s.cross[field]
      if type(a) == 'boolean' then
        a, b = a and 1 or 0, b and 1 or 0
      end
      a, b = a or 0, b or 0
      if math.abs(a - b) < 0.005 then
        ties = ties + 1
      elseif b > a then
        wins = wins + 1
      else
        losses = losses + 1
      end
    end
    return wins, losses, ties
  end
  for _, field in ipairs({ 'simm', 'sim', 'f1m', 'f1', 'lead', 'first', 'exact_norm' }) do
    local wins, losses, ties = compare_paired(field)
    say('paired %-10s cross better %2d, worse %2d, tie %2d  ->  p=%.2f', field, wins, losses, ties,
      sign_test(wins, losses))
  end
  say('paired samples: %d (of %d records)', #paired, #records)

  -- Why completions came back empty: a completion the API returned but the
  -- filter dropped is a *filter* problem, not a context problem, and it would
  -- otherwise be invisible in the scores above.
  local stage_counts, empties = {}, {}
  for _, r in ipairs(records) do
    if r.comp == '' then
      local stage = r.err and ('error: ' .. tostring(r.err)) or 'unknown'
      if not r.err and r.trace then
        for i, s in ipairs(r.trace) do
          if s.text == '' and (i == 1 or r.trace[i - 1].text ~= '') then
            stage = s.name
            break
          end
        end
      end
      stage_counts[stage] = (stage_counts[stage] or 0) + 1
      empties[#empties + 1] = { r = r, stage = stage }
    end
  end
  if #empties > 0 then
    local per_variant = {}
    for _, e in ipairs(empties) do
      per_variant[e.r.variant] = (per_variant[e.r.variant] or 0) + 1
    end
    say('')
    say('--- empty completions: %d of %d records (base %d, cross %d) ---', #empties, #records,
      per_variant.base or 0, per_variant.cross or 0)
    for stage, n in pairs(stage_counts) do
      say('  %-22s %d', stage, n)
    end
    for i = 1, math.min(#empties, 14) do
      local e = empties[i]
      local detail
      local why = ('finish=%s choices=%d'):format(tostring(e.r.finish_reason), e.r.choices or 0)
      if e.r.err then
        why = 'error=' .. tostring(e.r.err)
      end
      if e.r.raw == nil then
        detail = '(raw not captured)'
      elseif e.stage == 'trim_suffix_overlap' then
        detail = ('raw=%q suffix=%q'):format(one_line(e.r.raw):sub(1, 34),
          one_line(e.r.suffix or ''):sub(1, 34))
      else
        detail = ('raw %d bytes: %s'):format(#e.r.raw, one_line(e.r.raw):sub(1, 44))
      end
      say('  %-5s %-16s %-20s %-26s %s', e.r.variant, e.r.file, e.stage, why, detail)
    end
  end

  local function delta(bucket)
    local a = tally(subset('base', bucket))
    local b = tally(subset('cross', bucket))
    if a.n == 0 or b.n == 0 then
      return
    end
    local n = math.max(1, a.n)
    say('delta %-10s first %+d, norm %+d, lead1 %+d, sim %+.3f, simm %+.3f, F1m %+.3f  (n=%d)',
      bucket or 'all', b.first - a.first, b.exact_norm - a.exact_norm, b.lead1 - a.lead1,
      (b.sim - a.sim) / n, (b.simm - a.simm) / n, (b.f1m - a.f1m) / n, a.n)
  end
  delta(nil)
  delta('cross_file')
  report.totals = {
    base = tally(subset('base', nil)),
    cross = tally(subset('cross', nil)),
    base_cross_bucket = tally(subset('base', 'cross_file')),
    cross_bucket = tally(subset('cross', 'cross_file')),
  }
  return report
end

-- Exposed for tests (and for anyone wanting to score completions by hand).
M.compare = compare
M.sign_test = sign_test
M.tokens = tokens

return M

-- Context assembly for DeepSeek FIM.
--
-- The layout mirrors what Copilot's language server builds locally: a document
-- marker (`# Path: ...`) followed by the code before the cursor, with the code
-- after the cursor as the FIM suffix.  Everything is trimmed to a token budget,
-- where tokens are approximated by characters (1 token ~= 3.5 chars) so that no
-- tokenizer dependency is needed.
--
-- Optional cross-file summaries go *above* the marker, so that `# Path:` is a
-- hard boundary: everything below it belongs to the current file.  Without
-- cross-file material the prompt is byte-identical to the plain layout.
--
-- The prefix is kept stable (marker first, then a growing block of code) which
-- is what makes DeepSeek's prompt cache hit: cached prompt tokens are ~50x
-- cheaper than cache misses.
local M = {}

---Line comment leader per filetype, used to build the document marker.
local LINE_COMMENT = {
  python = '#',
  sh = '#',
  bash = '#',
  zsh = '#',
  yaml = '#',
  toml = '#',
  make = '#',
  dockerfile = '#',
  ruby = '#',
  perl = '#',
  r = '#',
  conf = '#',
  gitcommit = '#',
  lua = '--',
  sql = '--',
  haskell = '--',
  vim = '"',
  markdown = '<!--',
}

---@param ft string
---@return string
local function comment_leader(ft)
  return LINE_COMMENT[ft] or '//'
end

M.comment_leader = comment_leader

---Build the `# Path: ...` marker for the buffer.
---@param bufnr integer
---@return string
function M.marker(bufnr)
  local ft = vim.bo[bufnr].filetype
  local leader = comment_leader(ft)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' then
    local rel = vim.fn.fnamemodify(name, ':.')
    if rel:sub(1, 1) == '/' then
      rel = vim.fn.fnamemodify(name, ':t')
    end
    if rel ~= '' then
      return leader .. ' Path: ' .. rel
    end
  end
  return leader .. ' Language: ' .. (ft ~= '' and ft or 'text')
end

---Split the buffer at the cursor into raw prefix/suffix text (byte exact).
---@param bufnr integer
---@param pos integer[]|nil `{row(1-based), col(0-based)}`, defaults to the window cursor
---@return string prefix
---@return string suffix
local function split_at_cursor(bufnr, pos)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  pos = pos or vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  local cur = lines[row + 1] or ''

  local before = {}
  for i = 1, row do
    before[#before + 1] = lines[i]
  end
  local after = {}
  for i = row + 2, #lines do
    after[#after + 1] = lines[i]
  end

  local prefix = table.concat(before, '\n')
  if #before > 0 then
    prefix = prefix .. '\n'
  end
  prefix = prefix .. cur:sub(1, col)
  local suffix = cur:sub(col + 1)
  if #after > 0 then
    suffix = suffix .. '\n' .. table.concat(after, '\n')
  end
  return prefix, suffix
end

---Keep the last `max_chars`, starting at a line boundary.
---@param s string
---@param max_chars integer
---@return string
local function tail_chars(s, max_chars)
  if #s <= max_chars or max_chars <= 0 then
    return s
  end
  local cut = s:sub(#s - max_chars + 1)
  local nl = cut:find('\n', 1, true)
  return nl and cut:sub(nl + 1) or cut
end

---Keep the first `max_chars`, ending at a line boundary.
---@param s string
---@param max_chars integer
---@return string
local function head_chars(s, max_chars)
  if #s <= max_chars or max_chars <= 0 then
    return s
  end
  local cut = s:sub(1, max_chars)
  local last = 0
  for p in cut:gmatch('()\n') do
    last = p
  end
  return last > 1 and cut:sub(1, last - 1) or cut
end

---Assemble the FIM prompt parts for the current cursor position.
---@param bufnr integer
---@param opts table
---@param stable_extra string|nil extra material belonging to the *stable* part
---  of the prompt (cross-file summaries).  It is emitted above the `# Path:`
---  marker; the evaluator uses it to A/B the same layout the integration
---  produces.
---@param pos integer[]|nil cursor position override, for the evaluator
---@return table|nil ctx `{ prefix, suffix, typed_prefix }`
---@return string|nil err
function M.build(bufnr, opts, stable_extra, pos)
  local prefix, suffix = split_at_cursor(bufnr, pos)
  if #prefix < (opts.min_prompt_chars or 10) then
    return nil, 'context too short'
  end

  local c = opts.context or {}
  local chars_per_token = 3.5
  local total_chars = math.floor((c.total_tokens or 8000) * chars_per_token)
  local prefix_chars = math.floor(total_chars * (c.prefix_ratio or 0.70))
  local suffix_chars = total_chars - prefix_chars
  local extra = stable_extra or ''
  if extra ~= '' then
    -- Keep the total budget constant: the extra material is taken out of the
    -- current file's window.
    prefix_chars = math.max(0, prefix_chars - #extra)
  end

  local head_budget = math.max(0, math.min(c.head_chars or 1000, prefix_chars))
  local head, code = '', ''
  if #prefix > prefix_chars and head_budget > 0 then
    -- The file does not fit in the budget: keep the head (imports, module level
    -- definitions) plus the code right before the cursor, so that the model
    -- still sees which APIs exist.  head + code can never overlap because their
    -- budgets sum to at most prefix_chars < #prefix.
    head = head_chars(prefix, head_budget)
    code = tail_chars(prefix, prefix_chars - #head)
  else
    code = tail_chars(prefix, prefix_chars)
  end

  local leader = comment_leader(vim.bo[bufnr].filetype)
  local parts = {}
  -- Other files first: the marker then opens the current file, and nothing has
  -- to separate the summaries from the code.  Keeping them far from the cursor
  -- also matches their value (measured: no reliable gain).
  if extra ~= '' then
    parts[#parts + 1] = extra .. '\n'
  end
  parts[#parts + 1] = M.marker(bufnr) .. '\n'
  if head ~= '' then
    parts[#parts + 1] = head .. '\n'
  end
  -- Only the code right before the cursor is "immediately preceding text", so
  -- whenever the file was actually truncated the model must be told; the marker
  -- no longer doubles as a separator for the cross-file block above `# Path:`.
  if #prefix > prefix_chars then
    parts[#parts + 1] = leader .. ' ... (rest of file omitted)\n'
  end
  parts[#parts + 1] = code

  return {
    prefix = table.concat(parts),
    suffix = head_chars(suffix, suffix_chars),
    typed_prefix = prefix,
  }
end

return M

-- Ghost text rendering for DeepSeek completions.
--
-- The suggestion is always a pure insertion at the cursor (we never delete
-- text), so the preview appends the untouched rest of the current line to the
-- first virtual line.  That way what is displayed is exactly what `<C-J>`
-- inserts.
local M = {}

local NS = vim.api.nvim_create_namespace('deepseek_fim')
local HL = 'CopilotSuggestion'
local MARK_ID = 1

---Prepare a completion for display/acceptance.
---
---A multi-line completion that happens to sit in front of existing text on the
---same line cannot be previewed honestly (the remaining text would have to be
---pushed below the last virtual line), so it is truncated to its first line.
---@param bufnr integer
---@param text string
---@return string
function M.prepare(bufnr, text)
  if text == '' then
    return text
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, pos[1] - 1, pos[1], false)[1] or ''
  if line:sub(pos[2] + 1) == '' then
    return text
  end
  local nl = text:find('\n', 1, true)
  return nl and text:sub(1, nl - 1) or text
end

---Render `text` at the cursor as ghost text.
---@param bufnr integer
---@param text string
function M.show(bufnr, text)
  if text == '' or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local row, col = pos[1] - 1, pos[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local rest = line:sub(col + 1)

  local lines = vim.split(text, '\n', { plain = true })
  local virt_lines = {}
  for i = 2, #lines do
    virt_lines[#virt_lines + 1] = { { lines[i], HL } }
  end

  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  vim.api.nvim_buf_set_extmark(bufnr, NS, row, col, {
    id = MARK_ID,
    virt_text = { { lines[1] .. rest, HL } },
    virt_text_pos = 'overlay',
    virt_lines = virt_lines,
    hl_mode = 'combine',
  })
end

---Remove the ghost text.
---@param bufnr integer|nil
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  end
end

return M

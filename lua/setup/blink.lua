-- blink.cmp configuration.
-- Faithfully reproduces the previous nvim-cmp behaviour (see setup/cmp.lua):
--   <Tab>/<S-Tab> navigate the menu, <CR> confirms without preselecting,
--   <C-l> jumps a snippet backward, <C-d>/<C-f> scroll docs, <C-e> hides.
-- <C-J> is intentionally left unmapped so it stays with copilot/gemini.
return {
  keymap = {
    preset = 'none',
    ['<Tab>']   = { 'select_next', 'fallback' },
    ['<S-Tab>'] = { 'select_prev', 'fallback' },
    ['<CR>']    = { 'accept', 'fallback' },
    ['<C-e>']   = { 'hide', 'fallback' },
    ['<C-d>']   = { 'scroll_documentation_up', 'fallback' },
    ['<C-f>']   = { 'scroll_documentation_down', 'fallback' },
    ['<C-l>']   = { 'snippet_backward', 'fallback' },
  },

  -- Keep using LuaSnip + friendly-snippets.
  snippets = { preset = 'luasnip' },

  -- Built-in signature window replaces cmp-nvim-lsp-signature-help.
  signature = { enabled = true },

  completion = {
    -- Disabled to avoid overlapping with copilot.vim's inline preview.
    ghost_text = { enabled = false },
  },

  sources = {
    default = { 'lsp', 'snippets', 'buffer' },
  },
}

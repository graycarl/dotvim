-- nvim-tree
-- disable netrw at the very start of your init.lua (strongly advised)
require("nvim-tree").setup({
  hijack_netrw = false,
  renderer = {
    icons = {
      symlink_arrow = ' -> ',
      show = { file = false, folder = false, folder_arrow = true, git = false },
      glyphs = {
        bookmark = '>',
        folder = { arrow_closed = '▸', arrow_open = '▾' },
      }
    }
  },
  filters = { custom = { '^\\.git', '__pycache__' } }
})

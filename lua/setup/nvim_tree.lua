-- nvim-tree
-- disable netrw at the very start of your init.lua (strongly advised)
return {
  opts = {
    hijack_netrw = false,
    renderer = vim.env.NERD_FONT and {} or {
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
  }
}

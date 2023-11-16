-- Nvim tree

local function init()
  require("nvim-tree").setup({
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
  })
  -- mappings
  vim.keymap.set('n', 'T', ':NvimTreeFindFileToggle<CR>')
end

return { init = init }

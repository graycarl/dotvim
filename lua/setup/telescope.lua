-- See `:help telescope` and `:help telescope.setup()`
-- Enable telescope fzf native, if installed
local function config()
  pcall(require('telescope').load_extension, 'fzf')
  require('telescope').setup {
      defaults = {
          file_ignore_patterns = {"*.pyc", '__pycache__'},
          wrap_results = true,
          mappings = {
            i = {
              ['<C-u>'] = false,
              ['<C-d>'] = false,
              ['<C-j>'] = 'move_selection_next',
              ['<C-k>'] = 'move_selection_previous'
            },
          },
      }
  }
  -- Mappings
  vim.keymap.set('n', '<C-p>', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader><leader>', require('telescope.builtin').builtin, { desc = '[\\] Start telescope' })
  vim.keymap.set('n', '<leader>?', require('telescope.builtin').oldfiles, { desc = '[?] Find recently opened files' })
  vim.keymap.set('n', '<localleader>/', function()
    -- You can pass additional configuration to telescope to change theme, layout, etc.
    require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
      winblend = 10,
      previewer = false,
    })
  end, { desc = '[/] Fuzzily search in current buffer]' })
  vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader>sh', require('telescope.builtin').help_tags, { desc = '[S]earch [H]elp' })
  vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch current [W]ord' })
  vim.keymap.set('n', '<leader>sg', require('telescope.builtin').live_grep, { desc = '[S]earch by [G]rep' })
  vim.keymap.set('n', '<leader>sd', require('telescope.builtin').diagnostics, { desc = '[S]earch [D]iagnostics' })
  vim.keymap.set('n', '<localleader>sd', function()
    require('telescope.builtin').diagnostics({
      bufnr=0,
      wrap_results=true
    })
  end, { desc = '[S]earch [D]iagnostics current Buffer' })
  vim.keymap.set('n', '<localleader><localleader>', function()
      require('telescope.builtin').oldfiles({cwd_only=true})
  end, { desc = '[S]earch [R]ecents' })
end

return {
  config = config
}

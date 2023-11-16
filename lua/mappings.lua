-- Keymaps for better default experience
-- See `:help vim.keymap.set()`
vim.keymap.set({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true })

-- Remap for dealing with word wrap
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })

-- Don't use Ex mode, use Q for formatting.
vim.keymap.set('n', 'Q', 'gqap')
vim.keymap.set('v', 'Q', 'gq')

-- disable <C-Space> in insert mode
vim.keymap.set('i', '<NUL>', '<Esc>')

-- Enable emacs-like hotkey in command line editing
vim.keymap.set('c', '<C-A>', '<Home>')
vim.keymap.set('c', '<C-B>', '<Left>')
vim.keymap.set('c', '<C-F>', '<Right>')
vim.keymap.set('c', '<C-E>', '<End>')

-- for tab switch
vim.keymap.set('n', '_', 'gT')
vim.keymap.set('n', '+', 'gt')

-- Map insert mode like emacs
vim.keymap.set('i', '<C-B>', '<Left>')
vim.keymap.set('i', '<C-F>', '<Right>')

-- Go to directory
vim.keymap.set('n', '-', ':call my#Goto_parent_dir()<CR>')

-- Shortcut for paste from clipboard
-- from: http://www.drbunsen.org/the-text-triumvirate/
vim.keymap.set('n', '<leader>p', ':set paste<CR>:put  *<CR>:set nopaste<CR>')

-- Copy file path
vim.keymap.set('n', '<Leader>c', ':let @+ = expand("%:p")<CR>')

-- Nvim tree
vim.keymap.set('n', 'T', ':NvimTreeFindFileToggle<CR>')

-- Diagnostic
vim.keymap.set('n', '[d', vim.diagnostic.goto_prev)
vim.keymap.set('n', ']d', vim.diagnostic.goto_next)
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float)
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist)

-- Telescope
vim.keymap.set('n', '<C-p>', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
require('telescope').setup {
  defaults = {
    mappings = {
      i = {
        ['<C-u>'] = false,
        ['<C-d>'] = false,
        ['<C-j>'] = 'move_selection_next',
        ['<C-k>'] = 'move_selection_previous'
      },
    },
  },
}
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

vim.g.mapleader = '\\'
vim.g.maplocalleader = ' '

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

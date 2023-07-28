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
vim.keymap.set('n', '<localleader><localleader>', function()
    require('telescope.builtin').oldfiles({cwd_only=true})
end, { desc = '[S]earch [R]ecents' })

-- Lsp Keymaps
function lsp_keymap_for_buffer(bufnr)
  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<localleader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<localleader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gD', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('gr', require('telescope.builtin').lsp_references, '[G]oto [R]eferences')
  nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
  nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Lesser used LSP functionality
  -- nmap('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
  nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, '[W]orkspace [A]dd Folder')
  nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, '[W]orkspace [R]emove Folder')
  nmap('<leader>wl', function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, '[W]orkspace [L]ist Folders')
end


return {
  lsp_keymap_for_buffer = lsp_keymap_for_buffer
}

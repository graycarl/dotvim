-- vim: foldmethod=marker ts=2 sts=2 sw=2 et

vim.env.VIMHOME = vim.fn.expand('<sfile>:p:h')
vim.env.EDITOR = 'nvim'

local bootstrap = require('plugins')
if bootstrap then
    require('packer').sync()
    return
end
vim.cmd([[
  augroup packer_user_config
    autocmd!
    autocmd BufWritePost $VIMHOME/lua/plugins.lua source <afile> | PackerCompile
  augroup end
]])

require('setup.vim')
require('setup.lualine')
require('setup.comment')
require('setup.gitsigns')
require('setup.nvim_tree')
require('setup.vimnote')
require('setup.telescope')
require('setup.lsp')
require('setup.cmp')

require('mappings')

for _, fn in ipairs({'local.vim', 'local.lua'}) do
  local ffn = vim.env.VIMHOME .. '/' .. fn
  if vim.fn.filereadable(ffn) == 1 then
    vim.cmd.source(ffn)
  end
end

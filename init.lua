-- vim: foldmethod=marker ts=2 sts=2 sw=2 et

-- We need to set font as soon as possible, or we'll facing
-- <https://github.com/neovide/neovide/issues/1636>
vim.opt.guifont = "M+1Code Nerd Font:h16"

vim.env.VIMHOME = vim.fn.expand('<sfile>:p:h')
vim.env.EDITOR = 'nvim'

-- Make sure to set `mapleader` before lazy so your mappings are correct
vim.g.mapleader = '\\'
vim.g.maplocalleader = ' '

-- Setup lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({"git", "clone", "--filter=blob:none", "https://github.com/folke/lazy.nvim.git", lazypath})
end
vim.opt.rtp:prepend(lazypath)
require('lazy').setup('plugins', {
  change_detection = {
    -- Notification is annoying
    notify = false,
  }
})

require('setup.vim')
require('setup.vimnote')
require('setup.lsp')

require('mappings')

for _, fn in ipairs({'local.vim', 'local.lua'}) do
  local ffn = vim.env.VIMHOME .. '/' .. fn
  if vim.fn.filereadable(ffn) == 1 then
    vim.cmd.source(ffn)
  end
end

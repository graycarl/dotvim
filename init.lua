-- vim: foldmethod=marker ts=2 sts=2 sw=2 et

local started = vim.uv.hrtime()

-- 故障隔离：单个配置模块报错不应该让整个编辑器降级。
-- 失败会被记录，`:checkhealth my` 能看到（见 lua/my/safe.lua）。
local safe = require('my.safe')
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
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({"git", "clone", "--filter=blob:none", "--branch=stable",
                 "https://github.com/folke/lazy.nvim.git", lazypath})
end
vim.opt.rtp:prepend(lazypath)
-- plugins.lua 里的模块已经各自做了隔离，这里再兜一层：
-- lazy.setup 抛错会让所有插件都不加载，症状看起来像 "nvim 变回裸机"
safe.call('lazy.setup', function()
  require('lazy').setup('plugins', {
    change_detection = {
      -- Notification is annoying
      notify = false,
    }
  })
end)

safe.require('setup.vim')
safe.require('setup.vimnote')
safe.require('setup.lsp')
safe.require('mappings')

-- Load *.vim and *.lua in local directory
-- (`local/colorswitch.lua` 是自动生成的，写坏了不应该吞掉后面所有配置)
local local_files = vim.fn.glob(vim.env.VIMHOME .. '/local/*.vim', false, true)
vim.list_extend(local_files, vim.fn.glob(vim.env.VIMHOME .. '/local/*.lua', false, true))
for _, file in ipairs(local_files) do
  safe.source(file)
end

vim.g.my_config_ms = (vim.uv.hrtime() - started) / 1e6

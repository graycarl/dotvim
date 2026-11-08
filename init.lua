-- vim: foldmethod=marker ts=2 sts=2 sw=2 et

local started = vim.uv.hrtime()

-- 故障隔离：单个配置模块报错不应该让整个编辑器降级（见 lua/my/safe.lua）。
-- 引导层自己也要能坏：`my.safe` 加载失败时用一个最小 shim 顶上，
-- 否则「隔离方案本身」就成了新的单点故障。
local ok, safe = pcall(require, 'my.safe')
if not ok then
  local boot_err = tostring(safe)
  safe = {
    errors = { ['my.safe'] = boot_err },
    broken = function()
      return true
    end,
    call = function(_, fn, default)
      local ok2, res = pcall(fn)
      return ok2 and res or default
    end,
    fatal = function(name, fn)
      local ok2, res = pcall(fn)
      if ok2 then
        return true
      end
      safe.errors[name] = tostring(res)
      vim.notify(('配置加载失败 %s\n%s'):format(name, res), vim.log.levels.ERROR)
      return false
    end,
    require = function(name)
      local ok2, mod = pcall(require, name)
      if ok2 then
        return mod
      end
    end,
    source = function(path)
      return (pcall(vim.cmd, 'source ' .. vim.fn.fnameescape(path)))
    end,
    run = function()
      return function() end
    end,
    opts = function()
      return {}
    end,
  }
  vim.schedule(function()
    vim.notify('lua/my/safe.lua 加载失败，已降级为无隔离运行：' .. boot_err, vim.log.levels.ERROR)
  end)
  -- plugins.lua 也会 `require('my.safe')`：把 shim 注册进去，
  -- 否则插件清单整份加载失败，隔离方案反而成了单点故障
  package.loaded['my.safe'] = safe
end

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
-- lazy.setup 抛错会让所有插件都不加载，症状看起来像 "nvim 变回裸机"。
-- 这里用 fatal：完整打印堆栈（不走"只报 3 行"的聚合通知），
-- 并在失败后跳过依赖 lazy 的部分，避免级联报错把真因埋掉。
local plugins_ok = safe.fatal('lazy.setup', function()
  require('lazy').setup('plugins', {
    change_detection = {
      -- Notification is annoying
      notify = false,
    }
  })
end)

-- 全局项（选项、LSP 键位、映射）失败不会让 nvim 报错，只会"悄悄不对"，
-- 所以除了 notify 还会在 VimEnter 再提醒一次。
safe.require('setup.vim')
safe.require('setup.vimnote')
safe.require('mappings')
if plugins_ok then
  safe.require('setup.lsp')
end

if plugins_ok then
  -- Load *.vim and *.lua in local directory
  -- (`local/colorswitch.lua` 是自动生成的，写坏了不应该吞掉后面所有配置)
  local local_files = vim.fn.glob(vim.env.VIMHOME .. '/local/*.vim', false, true)
  vim.list_extend(local_files, vim.fn.glob(vim.env.VIMHOME .. '/local/*.lua', false, true))
  for _, file in ipairs(local_files) do
    safe.source(file)
  end
end

vim.g.my_config_ms = (vim.uv.hrtime() - started) / 1e6

if safe.broken() then
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      vim.notify(
        ('%d 项配置加载失败，`:checkhealth my` 查看详情'):format(vim.tbl_count(safe.errors)),
        vim.log.levels.ERROR
      )
    end,
  })
end

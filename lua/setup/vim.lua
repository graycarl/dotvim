-- 这里设置 LANG 环境变量是为了避免 MacVim 自动使用中文语言，导致
-- Git 的输出变成中文而无法使用 fugitive 插件。
vim.env.LANG = 'en_US.UTF-8'

-- Highlight the cursor line
vim.o.cursorline = true
-- 保持一定的留白，不让光标跑到最顶或者最底部
vim.o.scrolloff = 5

-- Load project local
vim.o.exrc = true
vim.o.secure = true

-- backup & swap file
vim.o.backup = true
vim.o.backupdir = vim.fn.stdpath('state') .. '/backup/'
if vim.fn.empty(vim.fn.glob(vim.o.backupdir)) > 0 then
    vim.fn.mkdir(vim.o.backupdir, 'p')
end

-- Editing
vim.o.tabstop = 4
vim.o.shiftwidth = 4
vim.o.expandtab = true
vim.o.wildignore = '*~,*.o,*.obj,*.pyc,__pycache__'

-- netrw
vim.g.netrw_list_hide = '.*\\.swp$,.*\\.pyc'
vim.g.netrw_altv = true

-- Enable mouse mode
vim.o.mouse = 'a'

-- Enable break indent
vim.o.breakindent = true

-- Case insensitive searching UNLESS /C or capital in search
vim.o.ignorecase = true
vim.o.smartcase = true

-- Decrease update time
vim.o.updatetime = 250
vim.wo.signcolumn = 'yes'

-- Set completeopt to have a better completion experience
vim.o.completeopt = 'menuone,noselect'

-- Enable termguicolors if possible, but not on apple terminal
-- See: https://github.com/neovim/neovim/issues/11327
if vim.fn.has('termguicolors') == 1 and vim.env.TERM_PROGRAM ~= 'Apple_Terminal' then
    vim.o.termguicolors = true
end

-- Add http filetype
vim.filetype.add({
  extension = {
    ['http'] = 'http',
  },
})

vim.g.copilot_no_tab_map = true
vim.g.copilot_filetypes = {
  ['*'] = false,
  python = true,
  bash = true,
  lua = true
}
-- 下面这句是从 nvim-cmp 的文档里抄来的，不知道有什么用，但是不加的话copilot 会无法工作
-- 猜测是由于 copilot 会去检查 Accept 函数是否存在 mapping，如果不存在的话就不工作。
-- 而 nvim-cmp 是动态添加 mapping 的，所以 copilot 会检查失败。所以这里手动添加一个
-- dummy mapping。
vim.cmd([[
  imap <expr> <Plug>(vimrc:copilot-dummy-map) copilot#Accept("\<Tab>")
]])

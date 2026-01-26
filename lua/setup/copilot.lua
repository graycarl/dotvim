-- this function should be called before loading the plugin
local function init()
  -- Only enable copilot for these filetypes
  vim.g.copilot_filetypes = {
    ['*'] = false,
    python = true,
    dockerfile = true,
    make = true,
    bash = true,
    zsh = true,
    sh = true,
    lua = true,
    javascript = true,
    vim = true,
    gitcommit = true,
    markdown = true,
    toml = true,
    yaml = true,
    rust = true,
    typescript = true
  }
  -- Use <C-J> to accept the suggestion
  vim.g.copilot_no_tab_map = true
  vim.cmd([[
    imap <silent><script><expr> <C-J> copilot#Accept("\<CR>")
  ]])
  -- Make sure to hide suggestions when leaving insert mode using ctrl-c
  vim.cmd([[
    inoremap <silent><expr> <C-C> copilot#Dismiss() . '<C-C>'
  ]])
end


return {
  init = init,
}

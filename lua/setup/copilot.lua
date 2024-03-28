-- this function should be called before loading the plugin
local function init()
  -- Only enable copilot for these filetypes
  if vim.env.VIM_COPILOT == '0' then
    vim.g.copilot_filetypes = {
      ['*'] = false
    }
  else
    vim.g.copilot_filetypes = {
      ['*'] = false,
      python = true,
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
    }
  end
  -- Use <C-J> to accept the suggestion
  vim.g.copilot_no_tab_map = true
  vim.cmd([[
    imap <silent><script><expr> <C-J> copilot#Accept("\<CR>")
  ]])
end


return {
  init = init,
}

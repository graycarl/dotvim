local function init()
  -- strategy settings: <https://github.com/vim-test/vim-test?tab=readme-ov-file#strategies>
  vim.g["test#strategy"] = "neovim" -- or "toggleterm"
end

return {
  init = init,
}

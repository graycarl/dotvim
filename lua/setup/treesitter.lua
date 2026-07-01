local function config()
  -- Install parsers (handled by neovim-treesitter community fork via :TSInstall)
  require('nvim-treesitter').install({ 'c', 'cpp', 'lua', 'python', 'rust', 'tsx', 'vimdoc', 'vim' })

  -- Highlighting is auto-enabled by Neovim 0.12 built-in for buffers with parsers.
  -- No plugin config needed for highlight.

  -- Treesitter-based indentation
  vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
      vim.bo[args.buf].indentexpr = "v:lua.vim.treesitter.indentexpr()"
    end,
  })

  -- Text objects (via nvim-treesitter-textobjects on 'main' branch)
  local ok, textobjects = pcall(require, 'nvim-treesitter-textobjects')
  if ok then
    textobjects.setup({
      select = {
        enable = true,
        lookahead = true,
        keymaps = {
          ['aa'] = '@parameter.outer',
          ['ia'] = '@parameter.inner',
          ['af'] = '@function.outer',
          ['if'] = '@function.inner',
          ['ac'] = '@class.outer',
          ['ic'] = '@class.inner',
        },
      },
    })
  end
end

return {
  config = config,
}

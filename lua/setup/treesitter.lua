local function config()
  -- jsonl reuses the json parser: tree-sitter-json's `document` is repeat(_value),
  -- so one JSON document per line parses without ERROR nodes.
  vim.treesitter.language.register('json', 'jsonl')

  -- Install parsers (handled by neovim-treesitter community fork via :TSInstall)
  require('nvim-treesitter').install({ 'c', 'cpp', 'json', 'lua', 'python', 'rust', 'tsx', 'vimdoc', 'vim' })

  -- Highlighting: Neovim only starts treesitter by itself for the filetypes that have
  -- a core ftplugin (lua/markdown/help/query). Start it for every other filetype here.
  -- pcall keeps the regex syntax when no parser is installed: `treesitter.start()`
  -- asserts the parser before it clears 'syntax', so failure leaves it untouched.
  vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
      local buf = args.buf
      if vim.bo[buf].buftype ~= '' then
        return -- terminal, nofile, prompt, ...
      end
      if vim.treesitter.highlighter.active[buf] then
        return -- already started by a core ftplugin; a second start would leak a highlighter
      end
      pcall(vim.treesitter.start, buf)
    end,
  })

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

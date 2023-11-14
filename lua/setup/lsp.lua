--  This function gets run when an LSP connects to a particular buffer.
local on_attach = function(_, bufnr)

  require('mappings').lsp_keymap_for_buffer(bufnr)

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- Enable the following language servers
--  Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
--  Add any additional override configuration in the following tables. They will be passed to
--  the `settings` field of the server config. You must look up that documentation yourself.
local servers = {
  lua_ls = {
    settings = {
      Lua = {
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
  pyright = {
    -- SFA Need requirements.py2.txt and requirements.py3.txt
    root_dir = require('lspconfig/util').root_pattern(
      'setup.py', 'pyproject.toml', 'requirements.txt', 'requirements.py2.txt',
      'requirements.py3.txt', '.git'
    ),
  },
}

-- Setup neovim lua configuration
require('neodev').setup()
--
-- nvim-cmp supports additional completion capabilities, so broadcast that to servers
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities)

-- Setup mason so it can manage external tooling
require('mason').setup({PATH="append"})

-- Ensure the servers above are installed
local mason_lspconfig = require 'mason-lspconfig'

mason_lspconfig.setup {
  ensure_installed = vim.tbl_keys(servers),
}

mason_lspconfig.setup_handlers {
  function(server_name)
    local opts = servers[server_name] or {}
    opts.on_attach = on_attach
    opts.capabilities = capabilities
    require('lspconfig')[server_name].setup(opts)
  end,
}

-- Turn on lsp status information
require('fidget').setup()

-- Add linter support
require('lint').linters_by_ft = {
  markdown = {'vale',},
  python = {'mypy', 'ruff'},
}

-- This is why we move to jedi-language-server:
-- Use flake8 instead of pycodestyle
-- See: <https://github.com/python-lsp/python-lsp-server#configuration>
-- But with this code enabled, the Goto definition will not work and I
-- don't know why. So comment in out now.
-- require'lspconfig'.pylsp.setup{
--   settings = {
--     pylsp = {
--       plugins = {
--         pycodestyle = { enabled = false },
--         mccabe = { enabled = false },
--         pyflakes = { enabled = false },
--         flake8 = { enabled = true },
--       },
--       configurationSources = { "flake8" }
--     }
--   }
-- }

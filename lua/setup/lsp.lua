-- This function gets run when an LSP connects to a particular buffer.
local on_attach = function(_, bufnr)

  -- Enable inlay hints
  -- vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

  local nmap = function(keys, func, desc)
    if desc then
      desc = 'LSP: ' .. desc
    end

    vim.keymap.set('n', keys, func, { buffer = bufnr, desc = desc })
  end

  nmap('<localleader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
  nmap('<localleader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction')

  nmap('gD', vim.lsp.buf.definition, '[G]oto [D]efinition')
  nmap('<leader>fr', require('telescope.builtin').lsp_references, '[F]ind [R]eferences')
  -- nmap('gI', vim.lsp.buf.implementation, '[G]oto [I]mplementation')
  -- nmap('<leader>D', vim.lsp.buf.type_definition, 'Type [D]efinition')
  nmap('<leader>ds', require('telescope.builtin').lsp_document_symbols, '[D]ocument [S]ymbols')
  nmap('<leader>ws', require('telescope.builtin').lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')

  -- See `:help K` for why this keymap
  nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
  nmap('<C-k>', vim.lsp.buf.signature_help, 'Signature Documentation')

  -- Create a command `:Format` local to the LSP buffer
  vim.api.nvim_buf_create_user_command(bufnr, 'Format', function(_)
    vim.lsp.buf.format()
  end, { desc = 'Format current buffer with LSP' })
end

-- Enable the following language servers
-- Feel free to add/remove any LSPs that you want here. They will automatically be installed.
--
-- Add any additional override configuration in the following tables. They will be passed to
-- the `settings` field of the server config. You must look up that documentation yourself.
local servers = {
  lua_ls = {
    settings = {
      Lua = {
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
  -- basedpyright instead of pyright
  basedpyright = {
    -- SFA Need requirements.py2.txt and requirements.py3.txt
    root_dir = function(bufnr, on_dir)
      local markers = {
        'setup.py',
        'pyproject.toml',
        'requirements.txt',
        'requirements.py2.txt',
        'requirements.py3.txt',
        '.git',
      }
      local root = vim.fs.root(vim.api.nvim_buf_get_name(bufnr), markers)
      if root then
        on_dir(root)
      end
    end,
  },
  rust_analyzer = {
    settings = {
      ["rust-analyzer"] = {
        imports = {
          granularity = {
            group = "module",
          },
          prefix = "self",
        },
        cargo = {
          buildScripts = {
            enable = true,
          },
        },
        procMacro = {
          enable = true
        },
        -- New rust-analyzer format: checkOnSave is a boolean toggle,
        -- the command moved under `check`.
        checkOnSave = true,
        check = {
          command = "clippy",
        },
      }
    },
  },
}

-- lazydev.nvim handles LuaLS config automatically via opts = {}
-- blink.cmp advertises the extra completion capabilities to servers
-- (get_lsp_capabilities already merges Neovim's built-in defaults).
local capabilities = require('blink.cmp').get_lsp_capabilities()

-- prepend or rust-analyzer in Cargo will be used
require('mason').setup({PATH="prepend"})

local mason_lspconfig = require 'mason-lspconfig'

mason_lspconfig.setup {
  ensure_installed = vim.tbl_keys(servers),
  automatic_enable = false,
}

for server_name, server_opts in pairs(servers) do
  local opts = vim.tbl_deep_extend('force', {
    on_attach = on_attach,
    capabilities = capabilities,
  }, server_opts)

  vim.lsp.config(server_name, opts)
  vim.lsp.enable(server_name)
end

-- Diagnostic appearance. Neovim 0.11+ defaults virtual_text to off, which
-- makes inline diagnostics easy to miss, so enable it explicitly. Text signs
-- follow $NERD_FONT and reuse the same E/W/I/H style as lualine.
vim.diagnostic.config({
  virtual_text = true,
  severity_sort = true,
  float = { border = 'rounded', source = true },
  signs = vim.env.NERD_FONT and true or {
    text = {
      [vim.diagnostic.severity.ERROR] = 'E',
      [vim.diagnostic.severity.WARN]  = 'W',
      [vim.diagnostic.severity.INFO]  = 'I',
      [vim.diagnostic.severity.HINT]  = 'H',
    },
  },
})

-- Turn on lsp status information
require('fidget').setup()

-- Add linter support
require('lint').linters_by_ft = {
  markdown = {'vale',},
  -- It depends on the project
  python = {'mypy', 'ruff', 'flake8'},
}

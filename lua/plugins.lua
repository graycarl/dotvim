return {
  -- surround text objects with quotes, parens, etc
  {
    'tpope/vim-surround',
    config = function()
      -- Remove insert mappings, which are conflicting with copilot
      vim.api.nvim_del_keymap('i', '<C-G>s')
      vim.api.nvim_del_keymap('i', '<C-G>S')
      vim.api.nvim_echo({{'Removed insert mappings for vim-surround', 'Text' }}, true, {})
    end
  },

  -- Git related plugins
  'tpope/vim-fugitive',
  {
    'lewis6991/gitsigns.nvim',
    opts = require('setup.gitsigns').opts
  },

  -- Fancier statusline
  {
    'nvim-lualine/lualine.nvim',
    opts = require('setup.lualine'),
  },
  -- "gc" to comment visual regions/lines
  {
    'numToStr/Comment.nvim', config = true
  },

  -- Color schemes
  "ellisonleao/gruvbox.nvim",
  'sainnhe/everforest',
  'navarasu/onedark.nvim',
  'rmehri01/onenord.nvim',
  "rebelot/kanagawa.nvim",

  {
    'nvim-tree/nvim-tree.lua',
    config = require('setup.nvim_tree').init
  },
  -- Load only when $NERD_FONT exists.
  {'nvim-tree/nvim-web-devicons', lazy = true, cond = function () return vim.env.NERD_FONT end},
  {'godlygeek/tabular', version = '1.0.0'},
  'rhysd/vim-gfm-syntax',

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    version = '*',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = require('setup.telescope').config,
  },

  -- Fuzzy Finder Algorithm which requires local dependencies to be built.
  -- Only load if `make` is available. Make sure you have the system
  -- requirements installed.
  {
    'nvim-telescope/telescope-fzf-native.nvim',
    -- NOTE: If you are having trouble with this installation,
    --       refer to the README for telescope-fzf-native for more instructions.
    build = 'make',
    cond = function()
      return vim.fn.executable 'make' == 1
    end,
  },

  -- NOTE: This is where your plugins related to LSP can be installed.
  --  The configuration is done below. Search for lspconfig to find it below.
  { -- LSP Configuration & Plugins
    'neovim/nvim-lspconfig',
    dependencies = {
      -- Automatically install LSPs to stdpath for neovim
      'williamboman/mason.nvim',
      'williamboman/mason-lspconfig.nvim',

      -- Useful status updates for LSP
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', opts = {} },

      -- Additional lua configuration, makes nvim stuff amazing!
      'folke/neodev.nvim',

      -- Add lint support to lsp
      'mfussenegger/nvim-lint'
    },
  },

  -- Autocompletion
  {
    'hrsh7th/nvim-cmp',
    dependencies = {
      'hrsh7th/cmp-nvim-lsp',
      'hrsh7th/cmp-buffer',
      'hrsh7th/cmp-nvim-lsp-signature-help',
      'L3MON4D3/LuaSnip',
      'saadparwaiz1/cmp_luasnip',
    },
    config = require('setup.cmp').config,
  },
  {
    "L3MON4D3/LuaSnip",
    version = "1.*",
    dependencies = { "rafamadriz/friendly-snippets" }
  },
  {
    'github/copilot.vim',
    init = require('setup.copilot').init,
  },

  -- Treesitter: Highlight, edit, and navigate code
  {
    'nvim-treesitter/nvim-treesitter',
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
    },
    build = ":TSUpdate",
    config = require('setup.treesitter').config,
  },

  -- Use <C-\> to toggle terminal in floating window
  {
    'akinsho/toggleterm.nvim',
    config = require('setup.toggleterm').config,
  },

  {
    "nvim-neorg/neorg",
    build = ":Neorg sync-parsers",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("neorg").setup {
        load = {
          ["core.defaults"] = {},
          ["core.concealer"] = {},
          ["core.dirman"] = {
            config = {
              workspaces = {
                notes = "~/notes",
              },
              default_workspace = "notes",
            },
          },
        },
      }

      vim.wo.foldlevel = 99
      vim.wo.conceallevel = 2
    end,
  },

  -- local plugins
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/encrypt' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/vault' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/vimnotes' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/opt/veeva', lazy=true },
}

-- See: `:help lazy.nvim-🔌-plugin-spec` for more information
-- Or: <https://lazy.folke.io/spec>
return {
  -- Itself
  {
    'folke/lazy.nvim',
    version = '*',
  },
  -- Which key
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    version = "*",
    cond = function()
      -- Only enabled with neovim version > 0.9.4
      return vim.fn.has('nvim-0.9.4') == 1
    end,
    opts = {},
    keys = {
      {
        "<leader>?",
        function()
          require("which-key").show({ global = false })
        end,
        desc = "Buffer Local Keymaps (which-key)",
      },
    },
  },

  -- surround text objects with quotes, parens, etc
  {
    'tpope/vim-surround',
    config = function()
      -- Remove insert mappings, which are conflicting with copilot
      vim.api.nvim_del_keymap('i', '<C-G>s')
      vim.api.nvim_del_keymap('i', '<C-G>S')
    end
  },

  -- Git related plugins
  {'tpope/vim-fugitive', version = '*'},
  {
    'lewis6991/gitsigns.nvim',
    version = '*',
    opts = require('setup.gitsigns').opts
  },

  -- Fancier statusline
  {
    'nvim-lualine/lualine.nvim',
    version = '*',
    opts = require('setup.lualine'),
  },
  -- "gc" to comment visual regions/lines
  {
    'numToStr/Comment.nvim',
    version = 'v0.8',
    config = true
  },

  -- Color schemes
  {"ellisonleao/gruvbox.nvim", version = '2.0'},
  {'sainnhe/everforest', version = 'v0.3'},
  'navarasu/onedark.nvim',
  'rmehri01/onenord.nvim',
  "rebelot/kanagawa.nvim",

  {
    'nvim-tree/nvim-tree.lua',
    version = 'v1.5',
    config = require('setup.nvim_tree').init
  },
  -- Load only when $NERD_FONT exists.
  {'nvim-tree/nvim-web-devicons', lazy = true, cond = function () return vim.env.NERD_FONT end},
  {'godlygeek/tabular', version = '1.0.0'},
  'rhysd/vim-gfm-syntax',

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    version = '0.1.8',
    dependencies = {
      {'nvim-lua/plenary.nvim', version = 'v0.1'}
    },
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
    version = 'v2.*',
    dependencies = {
      -- Automatically install LSPs to stdpath for neovim
      {'mason-org/mason.nvim', version = 'v2.*'},
      {'mason-org/mason-lspconfig.nvim', version = 'v2.*'},

      -- Useful status updates for LSP
      -- NOTE: `opts = {}` is the same as calling `require('fidget').setup({})`
      { 'j-hui/fidget.nvim', version='1.4', opts = {} },

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
    version = 'v1.*',
    cond = function()
      return vim.env.VIM_AI == "copilot"
    end,
    init = require('setup.copilot').init,
  },

  -- Treesitter: Highlight, edit, and navigate code
  {
    'nvim-treesitter/nvim-treesitter',
    version = 'v0.10',
    dependencies = {
      'nvim-treesitter/nvim-treesitter-textobjects',
    },
    build = ":TSUpdate",
    config = require('setup.treesitter').config,
  },

  -- Use <C-\> to toggle terminal in floating window
  {
    'akinsho/toggleterm.nvim',
    version = 'v2.12',
    config = require('setup.toggleterm').config,
  },

  -- Run tests with vim
  {
    'vim-test/vim-test',
    version = 'v2.1',
    init = require('setup.vim-test').init,
  },

  -- Http client
  {
    "mistweaverco/kulala.nvim",
    keys = {
      { "<leader>Rs", desc = "Send request" },
      { "<leader>Ra", desc = "Send all requests" },
      { "<leader>Rb", desc = "Open scratchpad" },
    },
    ft = {"http", "rest"},
    opts = {
      -- your configuration comes here
      global_keymaps = true,
    },
  },

  -- local plugins
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/encrypt' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/vault' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/start/vimnotes' },
  { dir = vim.fn.stdpath('config') .. '/pack/my/opt/veeva', lazy=true },
  { dir = vim.fn.stdpath('config') .. '/pack/ai/opt/gemini.nvim',
    cond = function()
      return vim.env.VIM_AI == "gemini"
    end,
    opts = require('setup.gemini')
  },
}

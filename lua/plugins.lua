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
  -- Commenting ("gc"/"gcc") is provided by Neovim's built-in commenting
  -- (0.10+), so no plugin is needed.

  -- Color schemes
  {"ellisonleao/gruvbox.nvim", version = '*'},
  {'sainnhe/everforest', version = '*'},
  'navarasu/onedark.nvim',
  'rmehri01/onenord.nvim',
  "rebelot/kanagawa.nvim",

  {
    'nvim-tree/nvim-tree.lua',
    version = '*',
    config = require('setup.nvim_tree').init
  },
  -- Load only when $NERD_FONT exists.
  {
    'nvim-tree/nvim-web-devicons',
    lazy = true,
    cond = function ()
      return vim.env.NERD_FONT
    end
  },
  {'godlygeek/tabular', version = '*'},
  'rhysd/vim-gfm-syntax',

  -- Fuzzy Finder (files, lsp, etc)
  {
    'nvim-telescope/telescope.nvim',
    version = '*',
    dependencies = {
      {'nvim-lua/plenary.nvim', version = '*'}
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

      -- Faster LuaLS setup, lazydev instead of deprecated neodev
      { 'folke/lazydev.nvim', version = '*', opts = {} },

      -- Add lint support to lsp
      'mfussenegger/nvim-lint'
    },
  },

  -- Autocompletion
  -- blink.cmp: batteries-included engine (LSP/buffer/snippet/signature +
  -- Rust fuzzy matcher). version tag pulls a prebuilt fuzzy binary.
  {
    'saghen/blink.cmp',
    version = '1.*',
    dependencies = {
      'L3MON4D3/LuaSnip',
      'rafamadriz/friendly-snippets',
    },
    opts = require('setup.blink'),
  },
  {
    "L3MON4D3/LuaSnip",
    version = "*",
    dependencies = { "rafamadriz/friendly-snippets" }
  },
  {
    'github/copilot.vim',
    version = '*',
    cond = function()
      return vim.env.VIM_AI == "copilot"
    end,
    init = require('setup.copilot').init,
  },

  -- Treesitter: community fork that provides :TSInstall (parser management)
  -- and queries. Original nvim-treesitter/nvim-treesitter is archived.
  -- Highlighting, folding, indentation are all Neovim 0.12 built-ins.
  {
    'neovim-treesitter/nvim-treesitter',
    branch = 'main',
    lazy = false,
    dependencies = {
      'neovim-treesitter/treesitter-parser-registry',
      { 'nvim-treesitter/nvim-treesitter-textobjects', branch = 'main' }
    },
    build = ':TSUpdate',
    config = require('setup.treesitter').config,
  },

  -- Use <C-\> to toggle terminal in floating window
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = require('setup.toggleterm').config,
  },

  -- Run tests with vim
  {
    'vim-test/vim-test',
    version = '*',
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

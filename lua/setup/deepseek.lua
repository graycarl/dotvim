-- Configuration for the local DeepSeek FIM completion plugin.
--
-- The plugin lives in `pack/my/opt/deepseek-fim` and is only loaded when
-- `$VIM_AI == "deepseek"` (see `lua/plugins.lua`), so it is mutually exclusive
-- with copilot.vim (`$VIM_AI=copilot`).
--
-- Everything here mirrors the defaults in `deepseek/init.lua`; tweak freely.
return {
  -- `https://api.deepseek.com/beta` is required for FIM.
  end_point = 'https://api.deepseek.com/beta/completions',
  model = 'deepseek-flash', -- or 'deepseek-v4-pro'
  key_file = vim.env.VIMHOME .. '/local/deepseek.key', -- gitignored, chmod 600

  -- Same whitelist as setup/copilot.lua, so switching VIM_AI does not change
  -- which filetypes get completions.
  filetypes = {
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
    typescript = true,
  },

  -- Triggering.  `debounce` waits for a typing pause, `throttle` caps how often
  -- the API is called at all.  Measured latency is ~1.1s regardless of prompt
  -- size, hence the aggressive debounce.
  debounce = 300,
  throttle = 800,
  timeout = 8000,

  -- Completion shape.
  max_tokens = 128,
  temperature = 0,
  max_lines = 10,
  min_prompt_chars = 10,

  -- Context budget.  DeepSeek's prompt cache makes a long, stable prefix cheap
  -- (cached tokens are ~50x cheaper), so this is more generous than Copilot's
  -- 7692 tokens.  When the file does not fit, the head (imports, module level
  -- definitions) is prepended to the code right before the cursor.
  context = {
    total_tokens = 8000,
    prefix_ratio = 0.70, -- prefix : suffix = 70 : 30
    head_chars = 1000,
  },

  keymaps = {
    accept = '<C-J>',
    accept_word = '<M-Right>',
    accept_line = '<M-C-Right>', -- terminals vary: <M-C-Right> is not always reportable
    dismiss = '<C-]>',
    refresh = '<M-\\>', -- ask for another candidate, or `:DeepSeek refresh`
  },
}

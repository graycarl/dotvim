-- See: <https://github.com/kiddos/gemini.nvim>
local opts = {
  model_config = {
    -- model_id = "gemini-2.5-flash",
    model_id = "gemini-pro",
  },
  completion = {
    enabled = true,
    blacklist_filetypes = { 'vault' },
    blacklist_filenames = { '.env', '.enc' },
    completion_delay = 500,
  },
}

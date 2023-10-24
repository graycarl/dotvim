-- See `:help telescope` and `:help telescope.setup()`
-- Enable telescope fzf native, if installed
local function config()
  pcall(require('telescope').load_extension, 'fzf')
  require('telescope').setup {
      defaults = {
          file_ignore_patterns = {"*.pyc", '__pycache__'},
          wrap_results = true
      }
  }
end

return {
  config = config
}

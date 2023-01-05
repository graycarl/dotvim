-- See `:help telescope` and `:help telescope.setup()`
-- Enable telescope fzf native, if installed
pcall(require('telescope').load_extension, 'fzf')
require('telescope').setup {
    defaults = {
        file_ignore_patterns = {"*.pyc", '__pycache__'},
    }
}

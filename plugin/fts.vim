" Some settings for specific file types

" Enable folding for rust (not working)
" let g:rust_fold = 1

" 在 pyenv 环境下，vim 自动寻找可用的 python provider 会比较慢，所以在没有明确需求的情况下，
" 先禁用 python3 provider，未来需要的话，可以按 help 中的方法手动启用。
" See `:help provider-python`
let g:loaded_python_provider = 0

" Python code width
let g:python_code_width_limit = 80

" Enable folding for markdown
let g:markdown_folding = 1

" Disable default mappings for omni-sql
let g:omni_sql_no_default_maps = 1

" Do not use the default folding implementation for markdown.
" Use the treesitter folding implementation (setup in setup/vim.lua).
let g:markdown_folding = 0

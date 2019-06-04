" By Carl.
if exists("b:hhb_ftplugin") | finish | endif
let b:hhb_ftplugin = 1

" About folding
setlocal foldmethod=indent
setlocal foldignore=
setlocal foldnestmax=3
setlocal foldlevelstart=2

" Run buffer
nnoremap <buffer> <F5> :exec '!python' shellescape(@%, 1)<CR>

" We should not let a single line's length more than 80 charaters
if exists('+colorcolumn')
  setlocal colorcolumn=80
else
  au BufWinEnter * let w:m2=matchadd('ErrorMsg', '\%>80v.\+', -1)
endif

" Remove trailing white space
autocmd BufWritePre * %s/\s\+$//e

" ALE Lint
let b:ale_linters = ['pyls']
let b:ale_fixers = ['autopep8']
let b:ale_python_pyls_config = {
            \   'pyls': {
            \     'configurationSources': ['flake8']
            \   },
            \ }
" let b:ale_python_pyls_executable = '/Users/hongbo/.vim/py3env/bin/pyls'
" let b:ale_python_pyls_use_global = 1
setlocal omnifunc=ale#completion#OmniFunc
nmap gD <Plug>(ale_go_to_definition)
" Use supertab to do the completion
let b:SuperTabDefaultCompletionType = "context"

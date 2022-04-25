" About folding
setlocal foldmethod=indent
setlocal foldignore=
setlocal foldnestmax=3
setlocal foldlevelstart=2

" Run buffer
nnoremap <buffer> <F5> :exec '!python' shellescape(@%, 1)<CR>

" We should not let a single line's length more than 80 charaters
if g:python_code_width_limit
    au BufWinEnter <buffer> let w:m2=matchadd('ErrorMsg', '\%>'. g:python_code_width_limit . 'v.\+', -1)
endif

" Remove trailing white space
au BufWritePre <buffer> %s/\s\+$//e

" ALE Lint
let b:ale_linters = ['pyright', 'flake8', 'mypy']
let b:ale_fixers = ['autopep8']

nmap <buffer> gD <Plug>(ale_go_to_definition)


command! -buffer -nargs=1 OpenModule call my#PythonOpenModule('<args>')

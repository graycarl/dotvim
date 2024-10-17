if exists("b:did_my_ftplugin")
  finish
endif
let b:did_my_ftplugin = 1

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

" Lint on save
" about `ignore_errors`, see source code and
" <https://github.com/mfussenegger/nvim-lint/pull/570>
au BufWritePost <buffer> lua require('lint').try_lint(nil, { ignore_errors = true })

" Run pytest for current test case
nnoremap <buffer> <F6> :TestNearest<CR>
nnoremap <buffer> <F7> :TestFile<CR>
" Show local variables on failure
let test#python#pytest#options = '--showlocals'
" pdb mode is not work with test.vim
" let test#python#pytest#options = '--pdb'

if exists("b:did_my_ftplugin")
  finish
endif
let b:did_my_ftplugin = 1

augroup my_ftplugin_python
  autocmd! * <buffer>
augroup END

" About folding
" Use global treesitter folding
" setlocal foldmethod=indent
" setlocal foldignore=
setlocal foldnestmax=2
setlocal foldlevelstart=2


" Run buffer
function! s:run_buffer()
    " check if current dir as uv.lock file
    if filereadable('uv.lock')
        " run uv
        execute '!uv run' shellescape(@%, 1)
    else
        " run python
        execute '!python' shellescape(@%, 1)
    endif
endfunction
command! -buffer -nargs=0 Run call s:run_buffer()
nnoremap <buffer> <F5> :Run<CR>

" Ruff formatter for current file
function! s:run_ruff_fix()
    if executable('ruff')
        execute '!ruff check --fix' shellescape(@%, 1)
    else
        execute '!uv run ruff check --fix' shellescape(@%, 1)
    endif
endfunction
command! -buffer -nargs=0 RuffFix call s:run_ruff_fix()
nnoremap <buffer> <F8> :RuffFix<CR>

" We should not let a single line's length more than 80 charaters
if g:python_code_width_limit
    " delete the previous match first: BufWinEnter fires every time the
    " buffer enters a window, re-adding would pile up duplicate matches
    au my_ftplugin_python BufWinEnter <buffer> silent! call matchdelete(get(w:, 'm2', -1))
          \ | let w:m2=matchadd('ErrorMsg', '\%>'. g:python_code_width_limit . 'v.\+', -1)
endif

" Remove trailing white space without moving the cursor or clobbering
" the search register on every save
function! s:strip_trailing_ws()
    let l:view = winsaveview()
    silent! keepjumps keeppatterns %s/\s\+$//e
    call winrestview(l:view)
endfunction
au my_ftplugin_python BufWritePre <buffer> call <SID>strip_trailing_ws()

" Lint on save
" about `ignore_errors`, see source code and
" <https://github.com/mfussenegger/nvim-lint/pull/570>
au my_ftplugin_python BufWritePost <buffer> lua require('lint').try_lint(nil, { ignore_errors = true })

" Run pytest for current test case
nnoremap <buffer> <F6> :TestNearest<CR>
nnoremap <buffer> <F7> :TestFile<CR>
" Show local variables on failure
let test#python#pytest#options = '--showlocals'
" pdb mode is not work with test.vim
" let test#python#pytest#options = '--pdb'

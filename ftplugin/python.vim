" About folding
set foldmethod=indent
set foldignore=
set foldnestmax=2
set foldlevelstart=2
nnoremap <SPACE> za
vnoremap <SPACE> zf

" Global Search
nnoremap <F10> yiw:call FastGlbSearch("<C-R>0", "py")<CR>
vnoremap <F10> y:call FastGlbSearch("<C-R>0", "py")<CR>

" Run buffer
nnoremap <buffer> <F5> :exec '!python' shellescape(@%, 1)<CR>

" Clever Tab
" inoremap <Tab> <C-R>=CleverTab()<CR>

" We should not let a single line's length more than 80 charaters
if exists('+colorcolumn')
  set colorcolumn=80
else
  au BufWinEnter * let w:m2=matchadd('ErrorMsg', '\%>80v.\+', -1)
endif

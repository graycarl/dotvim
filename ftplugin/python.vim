" By Carl.
if exists("b:hhb_ftplugin") | finish | endif
let b:hhb_ftplugin = 1

" About folding
setlocal foldmethod=indent
setlocal foldignore=
setlocal foldnestmax=2
setlocal foldlevelstart=2
nnoremap <buffer> <SPACE> za
vnoremap <buffer> <SPACE> zf
nnoremap <buffer> <TAB> za
vnoremap <buffer> <TAB> zf

" Global Search
nnoremap <buffer> <F10> yiw:call FastGlbSearch("<C-R>0", "py")<CR>
vnoremap <buffer> <F10> y:call FastGlbSearch("<C-R>0", "py")<CR>

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

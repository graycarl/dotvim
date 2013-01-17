" About folding
set foldmethod=indent
set foldignore=
set foldnestmax=2
set foldlevelstart=2
nnoremap <SPACE> za
vnoremap <SPACE> zf

" Global Search
nnoremap <F10> yiw:call GlbSearch("<C-R>0", "py")<CR>
vnoremap <F10> y:call GlbSearch("<C-R>0", "py")<CR>
command! -nargs=+ Sinpy :call GlbSearch("<args>", "py")

" Clever Tab
inoremap <Tab> <C-R>=CleverTab()<CR>

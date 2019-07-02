" My key bindings

" disable <C-Space> in insert mode
imap <NUL> <Esc>

" for tab switch
nnoremap _ gT
nnoremap + gt

command -nargs=+ Sinpy :call my#FastGlbSearch("<args>", "py")
command -nargs=+ Sinch :call my#GlbSearch("<args>", "[ch]")

nnoremap - :call my#Goto_parent_dir()<CR>

nnoremap ,d :call my#Insert_cur_datetime()<CR>

" Syntax Fix
nnoremap <F9> :syntax sync fromstart <CR>
inoremap <F9> <C-O>:syntax sync fromstart <CR>

" Map other modes
nnoremap <SPACE>b :<C-U>CtrlPBuffer<CR>
nnoremap B :<C-U>CtrlPBuffer<CR>
" Need `brew install ctags`
nnoremap <SPACE>t :<C-U>CtrlPBufTag<CR>

" Shortcut for paste from clipboard
" from: http://www.drbunsen.org/the-text-triumvirate/
noremap <leader>p :set paste<CR>:put  *<CR>:set nopaste<CR>

" Map insert mode like emacs
inoremap <C-B> <Left>
inoremap <C-F> <Right>

" Global Search
nnoremap <F10> yiw:call my#GitSearchInput("<C-R>0")<CR>
vnoremap <F10> y:call my#GitSearchInput("<C-R>0")<CR>
nnoremap <Space><F10> yiw:call my#GitSearch("<C-R>0", 0)<CR>
vnoremap <Space><F10> y:call my#GitSearch("<C-R>0", 0)<CR>

" NeoVim terminal
tnoremap <Esc> <C-\><C-n>

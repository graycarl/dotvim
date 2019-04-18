source ~/.vim/defaults.vim

" Set VIMHOME
let $VIMHOME = expand('<sfile>:p:h')

" disable undofile
set noundofile

" backup
set backup
set backupdir=~/.vim/vimtmp,.

" disable <C-Space> in insert mode
imap <NUL> <Esc>

execute pathogen#infect()

" Base Settings
set softtabstop=4
set shiftwidth=4
set expandtab
set wildignore=*~,*.o,*.obj,*.pyc

" disable auto replace netrw
let NERDTreeHijackNetrw = 0
let NERDTreeIgnore=['\.pyc$', '\~$']

" netrw list style
" let g:netrw_liststyle = 1
let g:netrw_list_hide = '.*\.swp$,.*\.pyc'
let g:netrw_altv = 1  " open file on the right when use `v`

" for tab switch
nnoremap _ gT
nnoremap + gt

" encoding
set encoding=utf-8
set fileformat=unix
set fileformats=unix,dos

" Add file header automatic
autocmd BufNewFile *.py execute "normal i# -*- coding: utf-8 -*-"

" Some common functions, can be used in ftplugins
" Global Search
function! GlbSearch(kw, ext)
    let sexp = '/\<' . a:kw . '\>/j '
    let fexp = '**/*.' . a:ext
    execute 'vimgrep ' . sexp . fexp
    botright cwindow
endfunction
function! FastGlbSearch(kw, ext)
    let sexp = '\\b' . a:kw . '\\b '
    let fexp = '**/*.' . a:ext
    execute 'silent grep! ' . sexp . fexp
    botright cwindow
    " vim has display bugs after grep, so I force redraw it
    redraw!
endfunction
command! -nargs=+ Sinpy :call FastGlbSearch("<args>", "py")
command! -nargs=+ Sinch :call GlbSearch("<args>", "[ch]")

" Open dir of current file
function! HB_goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction
nnoremap - :call HB_goto_parent_dir()<CR>

" Insert Datetime
function! HB_insert_cur_datetime()
    let s = strftime("%Y-%m-%d %T")
    execute "normal a" . s
endfunction 
nnoremap ,d :call HB_insert_cur_datetime()<CR>

" Syntax Fix
nnoremap <F9> :syntax sync fromstart <CR>
inoremap <F9> <C-O>:syntax sync fromstart <CR>

" For CtrlP
let g:ctrlp_custom_ignore = {
    \ 'dir':  '\v[\/](build|dist|node_modules|bower_components|.*\.egg-info)$',
    \ 'file': '\v\.(exe|so|dll|pyc|db)'
    \ }
" Setup ctrl-p Root
" c - the directory of the current file.
" a - like "c", but only applies when the current working directory outside of
"     CtrlP isn't a direct ancestor of the directory of the current file.
let g:ctrlp_working_path_mode = 'a'
" Map other modes
nnoremap <SPACE>b :<C-U>CtrlPBuffer<CR>
nnoremap B :<C-U>CtrlPBuffer<CR>
" Need `brew install ctags`
nnoremap <SPACE>t :<C-U>CtrlPBufTag<CR>


" The vim-less plugin will set sw to 2 and i don't like it.
" So fix this using a autocmd.
autocmd FileType less setlocal shiftwidth=4
autocmd FileType jinja setlocal tabstop=2 softtabstop=2 shiftwidth=2
autocmd FileType yaml setlocal tabstop=2 softtabstop=2 shiftwidth=2
autocmd FileType vimwiki setlocal foldlevel=2

" Shortcut for paste from clipboard
" from: http://www.drbunsen.org/the-text-triumvirate/
noremap <leader>p :set paste<CR>:put  *<CR>:set nopaste<CR>

" For NeoVim
" Set the python program from specified virtualenv
let g:python_host_prog = $HOME . '/.vim/py2env/bin/python'
let g:python3_host_prog = $HOME . '/.vim/py3env/bin/python'

" Map insert mode like emacs
inoremap <C-B> <Left>
inoremap <C-F> <Right>

" Jedi
let g:jedi#auto_vim_configuration = 0
let g:jedi#show_call_signatures = 2
" To disable the preview window when completing
set completeopt=menuone,longest

" Syntastic
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers = ['flake8']

" for lightline
set laststatus=2

" Project local
set exrc
set secure

" Org Mode
let g:org_indent = 1
let g:org_heading_shade_leading_stars = 1

" Load local settings
let localrc = $VIMHOME . '/local.vim'
if filereadable(localrc)
    " source $VIMHOME . '/local.vim'
    execute 'source ' . localrc
endif

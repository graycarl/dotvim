source ~/.vim/defaults.vim
" disable undofile
set noundofile

" disable <C-Space> in insert mode
imap <NUL> <Esc>

execute pathogen#infect()

" color scheme
set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set backupdir=~/.vim/vimtmp,.

" disable auto replace netrw
let NERDTreeHijackNetrw = 0

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

" Remap vim-expand-region
nmap <C-L> <Plug>(expand_region_expand)
vmap <C-L> <Plug>(expand_region_expand)
nmap <C-H> <Plug>(expand_region_shrink)
vmap <C-H> <Plug>(expand_region_shrink)

" Markdown filetype
au BufNewFile,BufRead *.md  setf markdown

" The vim-less plugin will set sw to 2 and i don't like it.
" So fix this using a autocmd.
autocmd FileType less setlocal shiftwidth=4
autocmd FileType jinja setlocal tabstop=2 softtabstop=2 shiftwidth=2
autocmd FileType yaml setlocal tabstop=2 softtabstop=2 shiftwidth=2

" Shortcut for paste from clipboard
" from: http://www.drbunsen.org/the-text-triumvirate/
noremap <leader>p :set paste<CR>:put  *<CR>:set nopaste<CR>

" For NeoVim
" Set the python program from specified virtualenv
let g:python_host_prog = $HOME . '/.vim/py2env/bin/python'
let g:python3_host_prog = $HOME . '/.vim/py3env/bin/python'

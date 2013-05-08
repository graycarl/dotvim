source $VIMRUNTIME/vimrc_example.vim

execute pathogen#infect()

" color scheme
set t_Co=256
colo molokai

set tabstop=4
set softtabstop=4
set shiftwidth=4
set expandtab
set backupdir=~/.vim/vimtmp,.

" for tab switch
nnoremap _ gT
nnoremap + gt

" encoding
set encoding=utf-8
set fileformat=unix
set fileformats=unix,dos

" Auto Close Preview Window
autocmd CursorMovedI * if pumvisible() == 0|pclose|endif
autocmd InsertLeave *  if pumvisible() == 0|pclose|endif

" Add file header automatic
autocmd BufNewFile *.py execute "normal i# -*- coding: utf-8 -*-"

" Some common functions, can be used in ftplugins
" Global Search
function GlbSearch(kw, ext)
    let sexp = '/\<' . a:kw . '\>/j '
    let fexp = '**/*.' . a:ext
    execute 'vimgrep ' . sexp . fexp
    cope
endfunction
command! -nargs=+ Sinpy :call GlbSearch("<args>", "py")
command! -nargs=+ Sinch :call GlbSearch("<args>", "[ch]")

" Clever Tab
function CleverTab()
    if strpart( getline('.'), 0, col('.')-1 ) =~ '^\s*$'
        return "\<tab>"
    else
        return "\<C-N>"
    endif
endfunction


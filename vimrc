source $VIMRUNTIME/vimrc_example.vim

execute pathogen#infect()

" color scheme
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
function! GlbSearch(kw, ext)
    let sexp = '/\<' . a:kw . '\>/j '
    let fexp = '**/*.' . a:ext
    execute 'vimgrep ' . sexp . fexp
    cope
endfunction
command! -nargs=+ Sinpy :call GlbSearch("<args>", "py")
command! -nargs=+ Sinch :call GlbSearch("<args>", "[ch]")

" I have SuperTab now, so ...
" " Clever Tab
" function CleverTab()
"     if strpart( getline('.'), 0, col('.')-1 ) =~ '^\s*$'
"         return "\<tab>"
"     else
"         return "\<C-N>"
"     endif
" endfunction

" Open dir of current file
function! HB_goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction
nnoremap - :call HB_goto_parent_dir()<CR>

function! HB_insert_cur_datetime()
    let s = strftime("%y-%m-%d %T")
    execute "normal i" . s
endfunction 
nnoremap ,d :call HB_insert_cur_datetime()<CR>

" For CtrlP
let g:ctrlp_custom_ignore = {
    \ 'dir':  '\v[\/](build|dist|.*\.egg-info)$',
    \ 'file': '\v\.(exe|so|dll|pyc|db)'
    \ }

" Tagbar
let g:tagbar_type_go = {
    \ 'ctagstype' : 'go',
    \ 'kinds'     : [
        \ 'p:package',
        \ 'i:imports:1',
        \ 'c:constants',
        \ 'v:variables',
        \ 't:types',
        \ 'n:interfaces',
        \ 'w:fields',
        \ 'e:embedded',
        \ 'm:methods',
        \ 'r:constructor',
        \ 'f:functions'
    \ ],
    \ 'sro' : '.',
    \ 'kind2scope' : {
        \ 't' : 'ctype',
        \ 'n' : 'ntype'
    \ },
    \ 'scope2kind' : {
        \ 'ctype' : 't',
        \ 'ntype' : 'n'
    \ },
    \ 'ctagsbin'  : 'gotags',
    \ 'ctagsargs' : '-sort -silent'
    \ }

" Markdown filetype
au BufNewFile,BufRead *.markdown,*.mdown,*.mkd,*.mkdn,*.md  setf markdown

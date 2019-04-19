" Common tools
if exists("g:loaded_my")
  finish
endif
let g:loaded_my = 1

" Global Search
function my#GlbSearch(kw, ext)
    let sexp = '/\<' . a:kw . '\>/j '
    let fexp = '**/*.' . a:ext
    execute 'vimgrep ' . sexp . fexp
    botright cwindow
endfunction
function my#FastGlbSearch(kw, ext)
    let sexp = '\\b' . a:kw . '\\b '
    let fexp = '**/*.' . a:ext
    execute 'silent grep! ' . sexp . fexp
    botright cwindow
    " vim has display bugs after grep, so I force redraw it
    redraw!
endfunction

" Open dir of current file
function! my#Goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction

" Insert Datetime
function! my#Insert_cur_datetime()
    let s = strftime("%Y-%m-%d %T")
    execute "normal a" . s
endfunction 

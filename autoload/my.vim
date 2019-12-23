" Common tools
if exists('did_autoload_my') || &cp || version < 700
    finish
endif
let did_autoload_my = 1

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

function my#GitSearch(kw, whole_word)
    if a:whole_word
        let sexp = '\\b' . a:kw . '\\b '
    else
        let sexp = a:kw
    endif
    execute 'silent Ggrep! ' . sexp
    botright cwindow
    " vim has display bugs after grep, so I force redraw it
    redraw!
endfunction
function my#GitSearchInput(kw)
    call inputsave()
    let kw = input('Search keyword: ', a:kw)
    if strlen(kw) > 0
        let whole_word = confirm('As symbol?', "&Yes\n&No", 'Yes') == 'Yes'
        call inputrestore()
        call my#GitSearch(kw, whole_word)
    endif
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

" Common Search
" args: pattern, use_git=0, file_pattern=0
function my#CommonSearch(use_git, pattern, ...)
    if a:use_git
        let cmd = "silent Ggrep -E '" . a:pattern . "'"
        if a:0 >= 1
            let cmd = cmd . " '" . a:1 . "'"
        endif
    else
        let cmd = "silent grep -rE '" .a:pattern . "'"
        if a:0 >= 2
            let cmd = cmd . " '" . a:1 . "'"
        else
            " TODO: Use global ignore
            let cmd = cmd . " ."
        endif
    endif 
    echo cmd
    execute cmd
    botright cwindow
endfunction

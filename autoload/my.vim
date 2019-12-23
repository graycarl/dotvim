" Common tools
if exists('did_autoload_my') || &cp || version < 700
    finish
endif
let did_autoload_my = 1

" Open dir of current file
function! my#Goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction

" Common Search
" args: pattern, use_git=0, file_pattern=0
function my#CommonSearch(use_git, as_symbol, pattern, ...)
    let pattern = a:pattern
    if a:as_symbol
        let pattern = '\<' . pattern . '\>'
    endif
    if a:use_git
        let cmd = "silent Ggrep -E " . shellescape(pattern)
        if a:0 >= 1
            let cmd = cmd . " " . shellescape(a:1)
        endif
    else
        let cmd = "silent grep -rE " . shellescape(pattern)
        if a:0 >= 2
            let cmd = cmd . " " . shellescape(a:1)
        else
            " TODO: Use global ignore
            let cmd = cmd . " ."
        endif
    endif 
    echo cmd
    execute cmd
    botright cwindow
endfunction

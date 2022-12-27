" Common Search
" args: pattern, file_pattern=0
" TODO: support -i
" TODO: exclude / exclude-dir
function s:CommonSearch(use_git, as_symbol, pattern, ...)
    let pattern = a:pattern
    if a:as_symbol
        let pattern = '\<' . pattern . '\>'
    endif
    if a:use_git
        let cmd = "silent Ggrep! -E " . shellescape(pattern)
        if a:0 >= 1
            let cmd = cmd . " " . a:1
        endif
    else
        let cmd = "silent grep! -rE " . shellescape(pattern)
        if a:0 >= 1
            let cmd = cmd . " " . a:1
        else
            " TODO: Use global ignore
            let cmd = cmd . " ."
        endif
    endif
    echo cmd
    execute cmd
    botright cwindow
    redraw!
endfunction

" Common searching command
" Sample:
" :S[G][!] apple
" :S[G][!] apple\ music
" :S[G][!] apple *.py
command -nargs=+ -bang S :call s:CommonSearch(0, "<bang>" == "!", <f-args>)
command -nargs=+ -bang SG :call s:CommonSearch(1, "<bang>" == "!", <f-args>)

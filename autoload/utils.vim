" Common tools
if exists("g:loaded_utils") || &cp
  finish
endif
let g:loaded_utils = 1

" Global Search
function GlbSearch(kw, ext)
    let sexp = '/\<' . a:kw . '\>/j '
    let fexp = '**/*.' . a:ext
    execute 'vimgrep ' . sexp . fexp
    botright cwindow
endfunction
function FastGlbSearch(kw, ext)
    let sexp = '\\b' . a:kw . '\\b '
    let fexp = '**/*.' . a:ext
    execute 'silent grep! ' . sexp . fexp
    botright cwindow
    " vim has display bugs after grep, so I force redraw it
    redraw!
endfunction

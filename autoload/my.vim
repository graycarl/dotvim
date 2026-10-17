" vim:foldmethod=indent
" Common tools

" Open dir of current file
function! my#Goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction

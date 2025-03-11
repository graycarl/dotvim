" Add fold config for diff
" 
" Fold by file name: `diff --git a/xxx b/xxx`

function MyDiffFold()
    let l:line = getline(v:lnum)
    if l:line =~ '^diff --git'
        return '0'
    else
        return '1'
    endif
endfunction

setlocal foldmethod=expr
setlocal foldexpr=MyDiffFold()
" setlocal foldtext='...'

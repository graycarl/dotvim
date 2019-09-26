" Auto detect vimnotes file
function s:SelectSupportedType()
    let fn = expand("<afile>:p")
    " Check file in notes root dir
    if fn[:strlen(g:VimnotesRootDir)-1] == g:VimnotesRootDir
        set ft=markdown.vimnotes
    endif
endfunction


autocmd BufNewFile,BufRead *.md call s:SelectSupportedType()

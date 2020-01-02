" Auto detect vimnotes file
function s:SelectSupportedType()
    let fn = expand("<afile>:p")
    " Check file in notes root dir
    if fn[:strlen(g:VimnotesRootDir)-1] == g:VimnotesRootDir
        set ft=markdown.vimnotes
    endif
    " When filename is not a absolute path and it's parent dir do not exists,
    " expand will not return a absolute path, see `filename-modifiers` doc.
    " I decide to fix it by hard code currently.
    if fn[:0] != "/" && getcwd() == g:VimnotesRootDir
        set ft=markdown.vimnotes
    endif
endfunction


autocmd BufNewFile,BufRead *.md call s:SelectSupportedType()

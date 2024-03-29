" file is large from 10mb
let g:LargeFile = 1024 * 1024 * 10
augroup LargeFile 
    au!
    autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > g:LargeFile || f == -2 | call s:LargeFile() | endif
augroup END

function! s:LargeFile()
    " no syntax highlighting etc
    set eventignore+=FileType
    " save memory when other file is viewed
    setlocal bufhidden=unload
    " is read-only (write with :w new_filename)
    setlocal buftype=nowrite
    " no undo possible
    setlocal undolevels=-1
    " display message
    autocmd VimEnter *  echo "The file is larger than " . (g:LargeFile / 1024 / 1024) 
        \. " MB, so some options are changed (see plugin/large_files.vim for details)."
endfunction

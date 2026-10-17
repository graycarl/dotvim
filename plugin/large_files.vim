" file is large from 10mb
let g:LargeFile = 1024 * 1024 * 10
augroup LargeFile
    au!
    autocmd BufReadPre * let f=getfsize(expand("<afile>")) | if f > g:LargeFile || f == -2 | call s:LargeFile() | endif
augroup END

function! s:LargeFile()
    " no syntax highlighting etc: suppress the FileType event until the
    " buffer is shown, then restore — eventignore is GLOBAL, leaving it
    " set would disable ftplugin/LSP/lint for every buffer opened later
    " in this session
    set eventignore+=FileType
    autocmd LargeFile BufWinEnter <buffer> ++once set eventignore-=FileType
    " save memory when other file is viewed
    setlocal bufhidden=unload
    " is read-only (write with :w new_filename)
    setlocal buftype=nowrite
    " no undo possible
    setlocal undolevels=-1
    " display message: if VimEnter already fired (file opened after
    " startup) a VimEnter autocmd would never trigger, so echo directly
    if v:vim_did_enter
        echo "The file is larger than " . (g:LargeFile / 1024 / 1024)
            \. " MB, so some options are changed (see plugin/large_files.vim for details)."
    else
        " replace any pending registration to avoid stacking messages
        autocmd! LargeFile VimEnter *
        autocmd LargeFile VimEnter * ++once echo "The file is larger than " . (g:LargeFile / 1024 / 1024)
            \. " MB, so some options are changed (see plugin/large_files.vim for details)."
    endif
endfunction

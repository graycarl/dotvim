setlocal tabstop=2
setlocal shiftwidth=0

" Remove trailing white space (keep cursor position and search register)
function! s:strip_trailing_ws()
    let l:view = winsaveview()
    silent! keepjumps keeppatterns %s/\s\+$//e
    call winrestview(l:view)
endfunction
augroup my_ftplugin_lua
  autocmd! * <buffer>
  autocmd BufWritePre <buffer> call <SID>strip_trailing_ws()
augroup END

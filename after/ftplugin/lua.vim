setlocal tabstop=2
setlocal shiftwidth=0

" Remove trailing white space
au BufWritePre <buffer> %s/\s\+$//e

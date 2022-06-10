setlocal cryptmethod=blowfish2
setlocal noswapfile
setlocal foldmethod=indent foldnestmax=1
set tabstop=2
set shiftwidth=2
set autoindent

" write backup file
autocmd BufWritePost <buffer> call vault#write_backup()

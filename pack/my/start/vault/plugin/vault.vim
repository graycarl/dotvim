" Do not use backup in vault file
set backupskip+=*.vault

" File type detect
autocmd BufNewFile,BufRead *.vault set filetype=vault

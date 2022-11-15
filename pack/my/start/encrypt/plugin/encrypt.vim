" Transparent editing encrypted files.
augroup encrypted
  au!

  " First make sure nothing is written to ~/.viminfo while editing
  " an encrypted file.
  autocmd BufReadPre,FileReadPre *.enc set viminfo=
  " We don't want a various options which write unencrypted data to disk
  autocmd BufReadPre,FileReadPre *.enc set noswapfile noundofile nobackup

  " Switch to binary mode to read the encrypted file
  autocmd BufReadPre,FileReadPre *.enc set bin
  autocmd BufReadPre,FileReadPre *.enc let ch_save = &ch|set ch=2
  " Read password
  autocmd BufReadPre,FileReadPre,BufNewFile *.enc let b:secret = inputsecret("Password: ")
  " (If you use tcsh, you may need to alter this line.)
  autocmd BufReadPost,FileReadPost *.enc execute "1,$!openssl aes-256-cbc -d -md md5 -salt -k '" . b:secret . "'"

  " Switch to normal mode for editing
  autocmd BufReadPost,FileReadPost *.enc set nobin
  autocmd BufReadPost,FileReadPost *.enc let &ch = ch_save|unlet ch_save
  autocmd BufReadPost,FileReadPost *.enc execute ":doautocmd BufReadPost " . expand("%:r")

  " Convert all text to encrypted text before writing
  " (If you use tcsh, you may need to alter this line.)
  autocmd BufWritePre,FileWritePre *.enc set bin
  autocmd BufWritePre,FileWritePre *.enc execute "1,$!openssl aes-256-cbc -md md5 -salt -k '" . b:secret . "'"
  " Undo the encryption so we are back in the normal text, directly
  " after the file has been written.
  autocmd BufWritePost,FileWritePost *.enc set nobin
  autocmd BufWritePost,FileWritePost *.enc u
augroup END

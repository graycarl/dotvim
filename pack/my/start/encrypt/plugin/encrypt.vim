" Transparent editing encrypted files.
" Run openssl with the password passed via a 0600 temp file, so the
" secret never appears in the shell command line (visible in `ps`) and
" passwords containing quotes cannot break the command.
function! s:OpensslFilter(args) abort
  let l:passfile = tempname()
  call writefile([], l:passfile, 'b')
  call setfperm(l:passfile, 'rw-------')
  call writefile([b:secret], l:passfile, 'b')
  try
    execute '1,$!/usr/bin/openssl aes-256-cbc ' . a:args . ' -salt -pass file:' . shellescape(l:passfile)
  finally
    call delete(l:passfile)
  endtry
endfunction

" Decrypt the buffer; on failure (most likely a wrong password) lock it
" so a careless :w cannot encrypt the error output back over the file,
" which would destroy the original ciphertext irreversibly.
function! s:DecryptBuffer() abort
  " Reset any lock from a previous failed attempt so :e! can retry.
  " ('nomodifiable' persists across :e!, so it must be lifted here,
  " before the filter replaces the buffer contents.)
  unlet! b:encrypt_failed
  setlocal modifiable noreadonly
  call s:OpensslFilter('-d -md md5')
  if v:shell_error != 0
    let b:encrypt_failed = 1
    setlocal readonly nomodifiable
    echohl ErrorMsg
    echom 'encrypt.vim: decryption failed (wrong password?). Buffer locked read-only; reopen with :e! and the correct password.'
    echohl None
  endif
endfunction

" Encrypt the buffer before writing. Refuse to write when decryption
" previously failed in this buffer (even for :w!).
function! s:EncryptBuffer() abort
  if get(b:, 'encrypt_failed', 0)
    echoerr 'encrypt.vim: refusing to write: decryption previously failed (wrong password?). Reopen with :e! first.'
    return
  endif
  call s:OpensslFilter('-md md5')
endfunction

" 'viminfo' is a global option: clear it while an encrypted file is open
" (so nothing leaks to ~/.viminfo), and restore the original value when
" the last .enc buffer is wiped out -- otherwise the whole session
" silently stops saving cursor marks, registers and history.
function! s:DisableViminfo() abort
  if !exists('s:viminfo_save')
    let s:viminfo_save = &viminfo
  endif
  set viminfo=
endfunction

function! s:MaybeRestoreViminfo() abort
  if !exists('s:viminfo_save')
    return
  endif
  let l:wiping = str2nr(expand('<abuf>'))
  for l:buf in range(1, bufnr('$'))
    if l:buf != l:wiping && bufexists(l:buf) && bufname(l:buf) =~# '\.enc$'
      return
    endif
  endfor
  let &viminfo = s:viminfo_save
  unlet s:viminfo_save
endfunction

augroup encrypted
  au!

  " First make sure nothing is written to ~/.viminfo while editing
  " an encrypted file.
  autocmd BufReadPre,FileReadPre *.enc call s:DisableViminfo()
  " We don't want a various options which write unencrypted data to disk
  autocmd BufReadPre,FileReadPre *.enc set noswapfile noundofile nobackup

  " Switch to binary mode to read the encrypted file
  autocmd BufReadPre,FileReadPre *.enc set bin
  autocmd BufReadPre,FileReadPre *.enc let ch_save = &ch|set ch=2
  " Read password
  autocmd BufReadPre,FileReadPre,BufNewFile *.enc let b:secret = inputsecret("Password: ")
  autocmd BufReadPost,FileReadPost *.enc call s:DecryptBuffer()

  " Switch to normal mode for editing
  autocmd BufReadPost,FileReadPost *.enc set nobin
  autocmd BufReadPost,FileReadPost *.enc let &ch = ch_save|unlet ch_save
  autocmd BufReadPost,FileReadPost *.enc execute ":doautocmd BufReadPost " . expand("%:r")

  " Restore viminfo when the last encrypted buffer goes away
  autocmd BufWipeout *.enc call s:MaybeRestoreViminfo()
  " Convert all text to encrypted text before writing
  autocmd BufWritePre,FileWritePre *.enc set bin
  autocmd BufWritePre,FileWritePre *.enc call s:EncryptBuffer()
  " Undo the encryption so we are back in the normal text, directly
  " after the file has been written.
  autocmd BufWritePost,FileWritePost *.enc set nobin
  autocmd BufWritePost,FileWritePost *.enc u
augroup END

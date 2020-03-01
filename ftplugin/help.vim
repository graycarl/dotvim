" The standard ftplugin will set keywordprg to :help, so
" we need to reset using autocmd
au BufWinEnter <buffer> setlocal keywordprg=trans\ -no-ansi\ :zh


" By Carl
if exists("b:hhb_ftplugin") | finish | endif
let b:hhb_ftplugin = 1

" The standard ftplugin will set keywordprg to :help, so
" we need to reset it in `after/ftplugin`
setlocal keywordprg=trans\ -no-ansi\ :zh

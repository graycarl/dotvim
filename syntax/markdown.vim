" Fix inner underscore
" Use autocmd to force it executed after standard markdown syntax script
au BufWinEnter <buffer> syn match markdownError "\w\@<=\w\@="

let $VIMHOME = expand('<sfile>:p:h')

" Must be set before loading ale plugin
" let g:ale_completion_enabled = 1

execute pathogen#infect()

" Load local settings
let localrc = $VIMHOME . '/local.vim'
if filereadable(localrc)
    execute 'source ' . localrc
endif

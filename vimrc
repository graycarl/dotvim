let $VIMHOME = expand('<sfile>:p:h')

execute pathogen#infect()

" Load local settings
let localrc = $VIMHOME . '/local.vim'
if filereadable(localrc)
    execute 'source ' . localrc
endif

" Load project local
set exrc
set secure

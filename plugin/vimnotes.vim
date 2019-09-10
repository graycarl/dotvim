" Plugin for note taken

" Settings {{{

if !exists("g:VimnotesRootDir")
    let g:VimnotesRootDir = $HOME . "/Documents/Notes"
endif

" }}}

command! NotesToday call vimnotes#open_today()

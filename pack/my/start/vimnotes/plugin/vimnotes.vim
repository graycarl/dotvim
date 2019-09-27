" vim:foldmethod=marker

" Settings {{{

if !exists("g:VimnotesRootDir")
    let g:VimnotesRootDir = $HOME . "/Documents/Notes"
endif
if !exists("g:VimnotesPreviewCommand")
    let g:VimnotesPreviewCommand = "open -a Marked.app"
endif

" }}}

" Commands {{{

command! NotesToday call vimnotes#open_today()

" }}}

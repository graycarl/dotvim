" vim:foldmethod=marker

" Settings {{{

if !exists("g:VimnotesRootDir")
    let g:VimnotesRootDir = $HOME . "/Documents/Notes"
endif
if !exists("g:VimnotesPreviewCommand")
    let g:VimnotesPreviewCommand = "open -a Marked.app"
endif
if !exists("g:VimnotesJournalTemplate")
    let g:VimnotesJournalTemplate = [
    \"<!-- vim: set foldlevel=2: -->",
    \"# {date}",
    \"",
    \"**Tasks**",
    \"",
    \"{tasks}",
    \"",
    \"**Projects**",
    \"",
    \"{projects}",
    \"",
    \"{notes}",
    \"",
    \]
endif

" }}}

" Commands {{{

command! -bang NotesToday call vimnotes#open_today("<bang>")

" }}}

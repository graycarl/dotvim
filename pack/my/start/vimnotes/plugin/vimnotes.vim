" vim:foldmethod=marker

" Settings {{{

if !exists("g:VimnotesRootDir")
    let g:VimnotesRootDir = $HOME . "/Documents/Notes"
endif
if !exists("g:VimnotesPreviewCommand")
    let g:VimnotesPreviewCommand = "open -a Marked\\ 2.app"
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
    \"## Notes",
    \"",
    \"Take notes here."
    \]
endif

" }}}

" Commands {{{

command! NotesToday call vimnotes#open_today(1)

" }}}

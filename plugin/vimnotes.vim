" vim:foldmethod=marker
" Plugin for note taken

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
command! NotesPreview call vimnotes#preview()

" }}}

" Bindings {{{

nmap <LocalLeader>p :NotesPreview<CR>

" }}}


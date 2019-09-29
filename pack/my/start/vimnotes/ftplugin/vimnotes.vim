" vim:foldmethod=marker

" Commands {{{ "

command -buffer NotesPreview call vimnotes#preview()
command -buffer NotesGoPrevJournal call vimnotes#buffer_go_previous_journal()
command -buffer NotesGoNextJournal call vimnotes#buffer_go_next_journal()

" }}} Commands "


" Bindings {{{ "

nmap <LocalLeader>p :NotesPreview<CR>
nmap ( :NotesGoPrevJournal<CR>
nmap ) :NotesGoNextJournal<CR>

" }}} Bindings "

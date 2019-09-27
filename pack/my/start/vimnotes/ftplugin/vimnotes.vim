" vim:foldmethod=marker

" Commands {{{ "

command! NotesPreview call vimnotes#preview()
command! NotesGoPrevJournal call vimnotes#buffer_go_previous_journal()
command! NotesGoNextJournal call vimnotes#buffer_go_next_journal()

" }}} Commands "


" Bindings {{{ "

nmap <LocalLeader>p :NotesPreview<CR>
nmap ( :NotesGoPrevJournal<CR>
nmap ) :NotesGoNextJournal<CR>

" }}} Bindings "

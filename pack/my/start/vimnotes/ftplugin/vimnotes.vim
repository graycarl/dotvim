" vim:foldmethod=marker

" Init buffer metadata {{{ "

let b:notes_journal_datestr = expand("%:t:r")
let b:notes_journal_date = []
call add(b:notes_journal_date, str2nr(b:notes_journal_datestr[:3]))
call add(b:notes_journal_date, str2nr(b:notes_journal_datestr[5:6]))
call add(b:notes_journal_date, str2nr(b:notes_journal_datestr[8:9]))

" }}} Init buffer metadata "

" Commands {{{ "

command! -buffer NotesPreview call vimnotes#preview()
command! -buffer NotesGoPrevJournal call vimnotes#buffer_go_previous_journal()
command! -buffer NotesGoNextJournal call vimnotes#buffer_go_next_journal()
command! -buffer NotesGoTodayJournal call vimnotes#open_today(0)
command! -buffer NotesInitJournal call vimnotes#buffer_init_journal()

" }}} Commands "


" Bindings {{{ "

nmap <LocalLeader>p :NotesPreview<CR>
nmap <LocalLeader>t :NotesGoTodayJournal<CR>
nmap ( :NotesGoPrevJournal<CR>
nmap ) :NotesGoNextJournal<CR>

" }}} Bindings "

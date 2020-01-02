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

" Auto Commands {{{ "
" Auto create parent directory when save
" from: https://stackoverflow.com/a/4294176
function s:MkNonExDir(file, buf)
    if empty(getbufvar(a:buf, '&buftype')) && a:file!~#'\v^\w+\:\/'
        let dir=fnamemodify(a:file, ':h')
        if !isdirectory(dir)
            call mkdir(dir, 'p')
        endif
    endif
endfunction
autocmd BufWritePre <buffer> :call s:MkNonExDir(expand('<afile>'), +expand('<abuf>'))
" }}} Auto Commands "

" Bindings {{{ "

nmap <LocalLeader>p :NotesPreview<CR>
nmap <LocalLeader>t :NotesGoTodayJournal<CR>
nmap <LocalLeader>i :NotesInitJournal<CR>
nmap ( :NotesGoPrevJournal<CR>
nmap ) :NotesGoNextJournal<CR>

" }}} Bindings "

function! OpenURLUnderCursor()
    let jira = matchstr(expand('<cWORD>'), 'ORI-[0-9]\+')
    if jira != ''
        let url = 'https://jira.veevadev.com/browse/' . jira
    else
        let url = expand('<cfile>')
    endif
    silent exec "!open '" . url . "'"
    redraw!
endfunction
nnoremap gx :call OpenURLUnderCursor()<CR>

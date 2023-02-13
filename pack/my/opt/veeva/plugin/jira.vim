function! OpenURLUnderCursor()
    let jira = matchstr(expand('<cWORD>'), 'ORI-[0-9]\+')
    if jira != ''
        let url = 'https://jira.veevadev.com/browse/' . jira
    else
        let url = expand('<cfile>')
    endif
    " let url = substitute(url, '?', '\\?', '')
    let url = substitute(url, '&', '\\&', '')
    let url = substitute(url, '#', '\\#', '')
    exec "!open " . shellescape(url)
    redraw!
endfunction
nnoremap gx :call OpenURLUnderCursor()<CR>

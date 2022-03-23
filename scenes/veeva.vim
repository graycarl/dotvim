" Open JIRA
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

" Open Gitlab
function! OpenGitlabCommit()
    let commit = matchstr(expand('<cWORD>'), '[a-f0-9]\{6,\}')
    let prj = trim(system("git remote get-url --push origin | grep -Eo 'veevaorion/[^.]*'"))
    if commit != '' && prj != ''
        let url = 'https://gitlab.veevadev.com/' . prj . '/-/commit/' . commit
        echom 'open url: ' . url
        silent exec "!open '" . url . "'"
        redraw!
    else
        echom 'commit=' . commit . '  prj=' . prj
    endif
endfunction
autocmd FileType fugitiveblame nnoremap <buffer> gx :call OpenGitlabCommit()<CR>

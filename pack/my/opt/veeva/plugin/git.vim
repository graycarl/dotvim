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

" Auto insert JIRA number in Git Commit (Need refactory)
au FileType gitcommit nmap <buffer> I :call PreInsertJIRA()<CR>
function PreInsertJIRA()
    g/ORI-[0-9]\+/y
    " normal ggPdthxxf-;DJxA: 
    normal ggPJ
    s/.*\(ORI-[0-9]\+\).*/\1/
    normal A: 
    startinsert!
endfunction

let g:ale_linters = {'rust': ['rls', 'cargo']}
let b:SuperTabDefaultCompletionType = "context"
setlocal omnifunc=ale#completion#OmniFunc
nmap <buffer> gD <Plug>(ale_go_to_definition)

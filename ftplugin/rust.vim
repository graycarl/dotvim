let g:ale_linters = {'rust': ['analyzer']}
setlocal omnifunc=ale#completion#OmniFunc
nmap <buffer> gD <Plug>(ale_go_to_definition)

let b:ale_linters = ['analyzer']

set omnifunc=ale#completion#OmniFunc
nmap <buffer> gD <Plug>(ale_go_to_definition)

nmap <buffer> <F5> :call myrust#Run()<CR>
nmap <buffer> <F6> :Cbuild<CR>
nmap <buffer> <F7> :Ctest<CR>

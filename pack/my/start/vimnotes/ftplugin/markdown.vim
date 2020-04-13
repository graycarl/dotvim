command! -buffer MarkdownPreview call vimnotes#preview()
nmap <buffer> <LocalLeader>p :MarkdownPreview<CR>

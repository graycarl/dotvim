" from: https://github.com/plasticboy/vim-markdown/blob/master/ftplugin/markdown.vim
function! TableFormat()
    if match(getline(v:lnum), '^|') == -1 && match(getline(v:lnum+1), '^|') == -1
        return -1
    endif
    let l:pos = getpos('.')
    normal! {
    " Search instead of `normal! j` because of the table at beginning of file edge case.
    call search('|')
    normal! j
    " Remove everything that is not a pipe, colon or hyphen next to a colon othewise
    " well formated tables would grow because of addition of 2 spaces on the separator
    " line by Tabularize /|.
    let l:flags = (&gdefault ? '' : 'g')
    execute 's/\(:\@<!-:\@!\|[^|:-]\)//e' . l:flags
    execute 's/--/-/e' . l:flags
    Tabularize /|
    " Move colons for alignment to left or right side of the cell.
    execute 's/:\( \+\)|/\1:|/e' . l:flags
    execute 's/|\( \+\):/|:\1/e' . l:flags
    execute 's/ /-/' . l:flags
    call setpos('.', l:pos)
endfunction
" Use gq to format table.
" When it failed(not a table), it will fail back to internal format program.
set formatexpr=TableFormat()

setlocal tabstop=2
setlocal shiftwidth=2
setlocal formatoptions+=mB

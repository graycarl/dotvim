" Do not repeat
if exists("b:did_ftplugin")
  finish
endif
let b:did_ftplugin = 1

setlocal cryptmethod=blowfish2
setlocal noswapfile
setlocal foldmethod=indent foldnestmax=1
set tabstop=2
set shiftwidth=2
set autoindent

" write backup file
autocmd BufWritePost <buffer> call vault#write_backup()

" Commands
command! -buffer CopyItemValue call vault#copy_item_value()

" Binding
nnoremap <buffer> <LocalLeader>c :CopyItemValue<CR>

" Abbreviates
iab <expr> <buffer> item~ <SID>ItemTemplate()
iab <expr> <buffer> now~ <SID>NowString()

function s:ItemTemplate()
    let t = "NAME"
    let t = t . "\n\tURL: XXXX"
    let t = t . "\nUsername: XXXX"
    let t = t . "\nPassword: XXXX"
    let t = t . "\nCreated: " . <SID>NowString()
    let t = t . "\nUpdated: " . <SID>NowString()
    return t
endfunction

function s:NowString()
    return strftime("%Y/%m/%d %H:%M:%S", localtime())
endfunction

" Notes plugin
function vimnotes#open_today()
    vsp
    execute "lcd " . g:VimnotesRootDir
    edit README.md
    CtrlP
endfunction


function s:date_to_fn(date)
endfunction

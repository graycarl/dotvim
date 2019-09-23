" Notes plugin
function vimnotes#open_today()
    vsp
    execute "lcd " . g:VimnotesRootDir
    let now = localtime()
    let yesterday = now - (3600*24)
    let tomorrow = now + (3600*24)
    let fn = strftime("%Y/%m/%Y-%m-%d.md", now)
    execute "edit " . fn
endfunction


function s:date_to_fn(date)
endfunction

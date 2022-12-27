" vim:foldmethod=indent
" Common tools
if exists('did_autoload_my') || &cp || version < 700
    finish
endif
let did_autoload_my = 1

" Open dir of current file
function! my#Goto_parent_dir()
    let bn = bufname("%")
    let fn = matchstr(bn, "[^/]*$")
    Explore
    call search(fn)
endfunction

" View python module file by name
function my#PythonOpenModule(name)
    " echom "OpenModule: " . a:name
    let pycode = 'import pkgutil; l = pkgutil.get_loader("' . a:name . '"); print(l.get_filename())'
    let fn = system('python', pycode)
    if v:shell_error
        return v:false
    else
        execute "view " . fn
        return v:true
    endif
endfunction
function my#PythonOpenModuleOnCursor()
    let line = split(getline("."))
    if line[0] == "from" && line[2] == "import"
        let module = line[1] . "." . line[3]
    elseif line[0] == "import"
        let module = line[1]
    else
        echom "Not a import"
        return
    endif
    if my#PythonOpenModule(module) == v:false
        let module = join(split(module, "\\.")[:-2], ".")
        if my#PythonOpenModule(module) == v:false
            echom "Failed"
        endif
    endif
endfunction


" Show command output to scratch
" Copy from: https://vim.fandom.com/wiki/List_loaded_scripts
function! my#Scratch(command, ...)
    redir => lines
    let saveMore = &more
    set nomore
    execute a:command
    redir END
    let &more = saveMore
    call feedkeys("\<cr>")
    new | setlocal buftype=nofile bufhidden=hide noswapfile
    put=lines
    if a:0 > 0
       execute 'vglobal/'.a:1.'/delete'
    endif
    if a:command == 'scriptnames'
       %substitute#^[[:space:]]*[[:digit:]]\+:[[:space:]]*##e
    endif
    silent %substitute/\%^\_s*\n\|\_s*\%$
    let height = line('$') + 3
    execute 'normal! z'.height."\<cr>"
    0
endfunction


" Simple snippets
function my#SnippetComplete(findstart, base)
    if a:findstart
        let line = getline('.')
        let start = col('.') - 1
        let compl_begin = col('.') - 2
        while start >= 0 && line[start - 1] =~ '\k'
            let start -= 1
        endwhile
        return start
    else
        return ["okok\rsecond", a:base]
    endif
endfunction

" Send command to tmux pane
function my#TmuxSendCommandToPane(cmd)
    execute "silent !tmux send -t1 '" . a:cmd . "' Enter"
    redraw!
endfunction

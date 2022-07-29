if exists('did_autoload_myrust') || &cp || version < 700
    finish
endif
let did_autoload_myrust = 1

function myrust#Run()
    let l:cargo = cargo#nearestCargo(0)
    if len(l:cargo) == 0
        RustRun
    else
        if expand("%:p:h:t") == "examples"
            let l:name = expand("%:t:r")
            let l:cmd = "Cargo run --example " . l:name
        else
            let l:cmd = "Crun"
        endif
        execute l:cmd
    endif
endfunction

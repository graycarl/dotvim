function vault#write_backup()
    if g:VaultBackupDir == ""
        return
    endif
    let vault_bk_dir = expand(g:VaultBackupDir) . "/" . s:hash(expand("%:p:h"), 4)
    echo vault_bk_dir
    if !isdirectory(vault_bk_dir)
        call mkdir(vault_bk_dir, 'p')
    endif
    let vault_bk_file = vault_bk_dir . "/" . expand("%:t:r") . trim(system("date +.%Y%m%d%H%M%S")) . ".vault"
    execute "write " . vault_bk_file
endfunction

function s:hash(str, length)
    return system("md5", a:str)[:a:length-1]
endfunction

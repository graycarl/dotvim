if exists("b:current_syntax")
    finish
endif

" Case sensitive
syntax case match

" Elements
syntax match vaultName /^\S.\+/

" KV items
syntax match vaultKV /^\s\+\S\+:.*$/ contains=vaultKey,vaultValue
syntax match vaultIndent /^\s\+/ nextgroup=vaultKey,vaultKeyPassword
syntax match vaultKey /[^:]\+/ nextgroup=vaultColon contained
syntax match vaultColon /:/ contained nextgroup=vaultValue skipwhite
syntax match vaultValue /.*$/ contained conceal

" Password
" syntax region vaultPassword matchgroup=vaultPasswordK start=/\s\+Password: / end=/$/

syntax match vaultComment /\s*#.*/

" Highline
hi link vaultComment Comment
hi link vaultName Structure
hi link vaultKey Label
hi link vaultValue Character
hi link vaultPassword SpecialChar

if exists("b:current_syntax")
    finish
endif

" Case sensitive
syntax case match

" Default to error
syntax match vaultError /.*/

" Item name
syntax match vaultName /^\S.\+/

" Online KV
syntax match vaultKV /^  \S.\+: \S.\+$/ contains=vaultKey,vaultValue
syntax match vaultKey /^  \S\+: /me=e-2 contained
syntax match vaultValue /: .*$/ms=s+2 contained

" Block KV
syntax region vaultKVBlock start=/^  \S.\+: |.*$/ end=/^ \{0,3\}\S/me=s-1 contains=vaultKey,vaultValueBlockStart,vaultValueBlockContent
syntax match vaultValueBlockStart /: |.*$/ms=s+2 contained
syntax match vaultValueBlockContent /^    .*/ms=s+4 contained

" Comment
syntax match vaultComment /\s*#.*/

" Password
" syntax region vaultPassword matchgroup=vaultPasswordK start=/\s\+Password: / end=/$/

" Highline
hi link vaultComment Comment
hi link vaultName Structure
hi link vaultKey Label
hi link vaultValue Character
hi link vaultValueBlockStart Delimiter
hi link vaultValueBlockContent String
hi link vaultError Error

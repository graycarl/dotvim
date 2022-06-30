if exists("b:current_syntax")
    finish
endif

" Case sensitive
syntax case match

" Default to error
syntax match vaultError /.*/

" Item name
syntax match vaultName /^\S.\+/

" KV
syntax match vaultKey /^  \S.*: /me=e-2 contained
syntax match vaultValue /: .*$/ms=s+2 contained
syntax match vaultPassword /: .*$/ms=s+2 conceal cchar=* contained
" Oneline KV
syntax match vaultKV /^  \S.\+: \S.*$/ contains=vaultKey,vaultValue
" Password KV
syntax match vaultPWKV /^  Password: \S.*$/ contains=vaultKey,vaultPassword

" Block KV
syntax region vaultKVBlock start=/^  \S.\+: |.*$/ end=/^ \{0,3\}\S/me=s-1 contains=vaultKey,vaultValueBlockStart,vaultValueBlockContent
syntax match vaultValueBlockStart /: |.*$/ms=s+2 contained
syntax match vaultValueBlockContent /^    .*/ms=s+4 contained

" Comment
syntax match vaultComment /\s*#.*/

" Highline
hi link vaultComment Comment
hi link vaultName Structure
hi link vaultKey Label
hi link vaultValue Character
hi link vaultPassword Character
hi link vaultValueBlockStart Delimiter
hi link vaultValueBlockContent String
hi link vaultError Error

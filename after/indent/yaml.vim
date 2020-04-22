" Because indentexpr=GetYAMLIndent(v:lnum) Do not work well
" In Block string, I disable it.
" NOTE: on 2020-04-23 00:29:51
" 在 yaml 中使用 `#` 注释文档时经常会被「智能」的调整了缩进，我不需要
setlocal indentexpr=

" JSON Lines: one JSON document per line (treesitter highlighter uses the json parser,
" see setup/treesitter.lua)
setlocal tabstop=2
setlocal shiftwidth=2
setlocal expandtab

" JSON has no comments; avoid `gcc` / `gq` writing /* */ and breaking the one-doc-per-line format
setlocal formatoptions-=t
setlocal comments=
setlocal commentstring=

" Normally cleared by vim.treesitter.start(); kept as a regex fallback for when the
" json parser is missing (e.g. after :TSUninstall json)
setlocal syntax=json
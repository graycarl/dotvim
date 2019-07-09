" We don't need to compat with vi
set nocompatible

" Allow backspacing over everything in insert mode.
set backspace=indent,eol,start

set history=200		" keep 200 lines of command line history
set ruler		" show the cursor position all the time
set showcmd		" display incomplete commands
set wildmenu		" display completion matches in a status line

set ttimeout		" time out for key codes
set ttimeoutlen=100	" wait up to 100ms after Esc for special key

" Show @@@ in the last line if it is truncated.
" set display=truncate
" By Hongbo: some old version do not support `truncate`
set display=lastline

" Show a few lines of context around the cursor.  Note that this makes the
" text scroll if you mouse-click near the start or end of the window.
set scrolloff=5

" Do incremental searching
set incsearch

" Do not recognize octal numbers for Ctrl-A and Ctrl-X, most users find it
" confusing.
set nrformats-=octal

" Don't use Ex mode, use Q for formatting.
nmap Q gqap
vmap Q gq

" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
" Revert with ":iunmap <C-U>".
inoremap <C-U> <C-G>u<C-U>

" In many terminal emulators the mouse works just fine.  By enabling it you
" can position the cursor, Visually select and scroll with the mouse.
if has('mouse')
  set mouse=a
endif

" Switch syntax highlighting on when the terminal has colors or when using the
" GUI (which always has colors).
if &t_Co > 2 || has("gui_running")
  " Revert with ":syntax off".
  syntax on
endif

" Enable file type detection.
" Use the default filetype settings, so that mail gets 'tw' set to 72,
" 'cindent' is on in C files, etc.
" Also load indent files, to automatically do language-dependent indenting.
" Revert with ":filetype off".
filetype plugin indent on

" disable undofile
set noundofile

" backup
set backup
set backupdir=~/.vim/vimtmp,.

" Base Settings
set tabstop=4
set shiftwidth=4
set expandtab
set wildignore+=*~,*.o,*.obj,*.pyc

" disable auto replace netrw
let NERDTreeHijackNetrw = 0
let NERDTreeIgnore=['\.pyc$', '\~$']

" netrw list style
" let g:netrw_liststyle = 1
let g:netrw_list_hide = '.*\.swp$,.*\.pyc'
let g:netrw_altv = 1  " open file on the right when use `v`

" encoding
set encoding=utf-8
set fileformat=unix
set fileformats=unix,dos
" For CtrlP
let g:ctrlp_custom_ignore = {
    \ 'dir':  '\v[\/](build|dist|node_modules|bower_components|.*\.egg-info)$',
    \ 'file': '\v\.(exe|so|dll|pyc|db)'
    \ }
" Setup ctrl-p Root
" c - the directory of the current file.
" a - like "c", but only applies when the current working directory outside of
"     CtrlP isn't a direct ancestor of the directory of the current file.
let g:ctrlp_working_path_mode = 'a'

" For NeoVim
" Set the python program from specified virtualenv
" let g:python_host_prog = $VIMHOME . '/py2env/bin/python'
let g:python3_host_prog = $VIMHOME . '/py3env/bin/python'

" Jedi
let g:jedi#auto_vim_configuration = 0
let g:jedi#show_call_signatures = 2
" To disable the preview window when completing
set completeopt=menuone,longest

" Syntastic
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers = ['flake8']

" ALE
let g:ale_lint_on_text_changed = 0
let g:ale_lint_on_insert_leave = 0
let g:ale_lint_on_enter = 1
let g:ale_lint_on_save = 1
let g:ale_lint_on_filetype_changed = 1

" for lightline
set laststatus=2

" Org Mode
let g:org_indent = 1
let g:org_heading_shade_leading_stars = 1

" Fix editor
if has('nvim')
    let $EDITOR='nvim'
else
    let $EDITOR='vim'
endif

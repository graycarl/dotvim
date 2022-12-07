" vim:foldmethod=marker
" My VIMRC

" Initialize {{{
let $VIMHOME = expand('<sfile>:p:h')
" 这里设置 LANG 环境变量是为了避免 MacVim 自动使用中文语言，导致
" Git 的输出变成中文而无法使用 fugitive 插件。
let $LANG = 'en_US.UTF-8'
" }}}

" Basic Settings {{{

set cursorline

set history=200		" keep 200 lines of command line history

set ttimeout		" time out for key codes
set ttimeoutlen=100	" wait up to 100ms after Esc for special key

" Show a few lines of context around the cursor.  Note that this makes the
" text scroll if you mouse-click near the start or end of the window.
set scrolloff=5

" Do not recognize octal numbers for Ctrl-A and Ctrl-X, most users find it
" confusing.
set nrformats-=octal

" Load project local
set exrc
set secure

" disable undofile
set noundofile

" backup & swap file
set backup
set backupdir=~/.vim/run/backup,.
set directory=~/.vim/run/swap

" Editing
set tabstop=4
set shiftwidth=4
set expandtab
set wildignore+=*~,*.o,*.obj,*.pyc,__pycache__

" encoding
set fileformat=unix
set fileformats=unix,dos

" For NeoVim
" Set the python program from specified virtualenv
" let g:python_host_prog = $VIMHOME . '/py2env/bin/python'
let g:python3_host_prog = $VIMHOME . '/py3env/bin/python'

" for lightline
set noshowmode

" For completion
set completeopt=menu,menuone

" }}}

" Language Settings {{{ "
let g:python_code_width_limit = 80
let g:markdown_folding = 1
" }}} Language Settings "

" GUI Settings {{{ "
if has('gui_running')
    set guioptions-=rL
    set guifont=mplusNerdFontComplete-regular:h14
    set lines=40 columns=200
endif
" }}} GUI Settings "

" Plugin Settings {{{

" disable auto replace netrw
let NERDTreeHijackNetrw = 0
let NERDTreeIgnore=['\.pyc$', '\~$', '__pycache__']

" netrw list style
" let g:netrw_liststyle = 1
let g:netrw_list_hide = '.*\.swp$,.*\.pyc'
let g:netrw_altv = 1  " open file on the right when use `v`

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
" Show recent file belongs to current dir
let g:ctrlp_mruf_relative = 1

" Syntastic
let g:syntastic_always_populate_loc_list = 1
let g:syntastic_auto_loc_list = 2
let g:syntastic_check_on_wq = 0
let g:syntastic_python_checkers = ['flake8']

" ALE
let g:ale_lint_on_text_changed = "never"
let g:ale_lint_on_insert_leave = 0
let g:ale_lint_on_enter = 1
let g:ale_lint_on_save = 1
let g:ale_lint_on_filetype_changed = 1
let g:ale_completion_enabled = 0

" Org Mode
let g:org_indent = 1
let g:org_heading_shade_leading_stars = 1

" Markdown
let g:markdown_fenced_languages = ['sh', 'python', 'json', 'sql', 'yaml']

" Ultisnips
" The search directories
let g:UltiSnipsSnippetDirectories = ["UltiSnips"]
" Where you place personal snippets in.
" You can define some local snippets by name it like `python_local.snippets`,
" git will ignore it by default.
let g:UltiSnipsSnippetDir = $VIMHOME."/UltiSnips"

" SuperTab
let g:SuperTabDefaultCompletionType = "context"

" Emmet
" Do not install global mappings. You can use `:EmmetInstall` to active it in
" current buffer.
let g:user_emmet_install_global = 0

" Notes
let g:VimnotesJournalTemplate = [
\"<!-- vim: set foldlevel=2: -->",
\"# {date}",
\"",
\"Good good study, day day up 💪",
\"",
\"--------------------------------------------------------------------------------",
\"",
\"{tasks}",
\"",
\"--------------------------------------------------------------------------------",
\"",
\"{notes}",
\"",
\]

" }}}

" Bindings {{{

" Define Leaders
let mapleader = "\\"
let maplocalleader = " "

" Don't use Ex mode, use Q for formatting.
nmap Q gqap
vmap Q gq

" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
" Revert with ":iunmap <C-U>".
inoremap <C-U> <C-G>u<C-U>

" disable <C-Space> in insert mode
imap <NUL> <Esc>

" Enable emacs-like hotkey in command line editing
cnoremap <C-A> <Home>
cnoremap <C-B> <Left>
cnoremap <C-F> <Right>
cnoremap <C-E> <End>

" for tab switch
nnoremap _ gT
nnoremap + gt

nnoremap - :call my#Goto_parent_dir()<CR>

" Syntax Fix
nnoremap <F9> :syntax sync fromstart <CR>
inoremap <F9> <C-O>:syntax sync fromstart <CR>

" CtrlP
let g:ctrlp_map = '<c-p>'
let g:ctrlp_cmd = 'CtrlPMixed'
nnoremap <leader>b :<C-U>CtrlPBuffer<CR>
" Need `brew install ctags`
nnoremap <localleader>@ :<C-U>CtrlPBufTag<CR>
nnoremap <leader>@ :<C-U>CtrlPTag<CR>

" Shortcut for paste from clipboard
" from: http://www.drbunsen.org/the-text-triumvirate/
noremap <leader>p :set paste<CR>:put  *<CR>:set nopaste<CR>

" Map insert mode like emacs
inoremap <C-B> <Left>
inoremap <C-F> <Right>

" Global Search
nnoremap <leader>* yiw:SG! <C-R>0<CR>
vnoremap <leader>* y:SG! <C-R>0<CR>
nnoremap <localleader>* yiw:SG! <C-R>0 %<CR>
vnoremap <localleader>* y:SG! <C-R>0 %<CR>

" NeoVim terminal or vim8 terminal
if has('terminal') || has('nvim')
    tnoremap <Esc> <C-\><C-n>
endif

" VimNote
nnoremap <Leader>jj :NotesToday<CR>
nnoremap <Leader>ji :NotesBrowseIndex<CR>
nnoremap <Leader>jp :NotesBrowseProject<CR>

" File management
nnoremap T :NERDTreeFind<CR>
nnoremap <Leader>c :let @+ = expand("%:p")<CR>

" SQL Mode
let g:ftplugin_sql_omni_key = '<C-x><Space>'

" }}}

" Auto Commands {{{

" Put these in an autocmd group, so that you can revert them with:
" ":augroup vimStartup | au! | augroup END"
augroup vimStartup
au!
" When editing a file, always jump to the last known cursor position.
" Don't do it when the position is invalid, when inside an event handler
" (happens when dropping a file on gvim) and for a commit message (it's
" likely a different one than last time).
autocmd BufReadPost *
  \ if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit'
  \ |   exe "normal! g`\""
  \ | endif

augroup END

autocmd FileType markdown setlocal foldlevel=2
autocmd BufNewFile *.py execute "normal i# -*- coding: utf-8 -*-"

" }}}

" Commands {{{

" Convenient command to see the difference between the current buffer and the
" file it was loaded from, thus the changes you made.
" Only define it when not defined already.
if !exists(":DiffOrig")
  command DiffOrig vert new | set bt=nofile | r ++edit # | 0d_ | diffthis
		  \ | wincmd p | diffthis
endif

" Common searching command
" Sample:
" :S[G][!] apple
" :S[G][!] apple\ music
" :S[G][!] apple *.py
command -nargs=+ -bang S :call my#CommonSearch(0, "<bang>" == "!", <f-args>)
command -nargs=+ -bang SG :call my#CommonSearch(1, "<bang>" == "!", <f-args>)

command -nargs=+ Scratch call my#Scratch(<f-args>)

command CloseOtherBuffers %bd|e#

command -nargs=+ T :call my#TmuxSendCommandToPane(<q-args>)

" }}}

" Others {{{

let localrc = $VIMHOME . '/local.vim'
let load_scenes = []
if filereadable(localrc)
    execute 'source ' . localrc
endif
for scene in load_scenes
    execute 'source ' . $VIMHOME . "/scenes/" . scene . ".vim"
endfor

" Fix editor
if has('nvim')
    let $EDITOR='nvim'
else
    let $EDITOR='vim'
endif

" }}}


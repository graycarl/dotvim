" 函数主体由 DeepSeek 生成，做了一些个性化调整
" ========================================================
if exists('g:loaded_start_screen')
  finish
endif
let g:loaded_start_screen = 1

" 配置默认值 =============================================
let g:start_screen_vertical_padding = get(g:, 'start_screen_vertical_padding', 0.25) " 25% 垂直留白

augroup StartScreen
  autocmd!
  " 使用 StdinReadPre 检测是否真正空启动
  autocmd StdinReadPre * let s:std_in=1
  autocmd VimEnter *
        \  if !exists('s:std_in') && argc() == 0 && !exists('b:start_screen_shown') && &filetype == '' |
        \    call s:show() |
        \  endif
augroup END

" 主显示函数 =============================================
function! s:show() abort
  " 创建专用 buffer
  setlocal filetype=start_screen

  " 设置 buffer 属性
  setlocal modifiable
  setlocal buftype=nofile bufhidden=wipe nobuflisted noswapfile
  setlocal nonumber norelativenumber nocursorline nocursorcolumn
  setlocal nospell

  " 生成居中内容
  silent %delete _
  call s:render_centered_content()
  setlocal nomodifiable

  " 设置交互功能
  call s:set_mappings()
  call s:set_syntax()

endfunction

function! s:close() abort
  if &filetype ==# 'start_screen'
    silent! close
  endif
endfunction

" 内容生成 ===============================================
function! s:render_centered_content() abort
  " 获取原始内容
  let l:content = s:header() + s:options() + s:footer()

  " 计算居中参数
  let l:max_width = max(map(copy(l:content), 'strdisplaywidth(v:val)'))
  let l:h_pad = repeat(' ', max([0, (winwidth(0) - l:max_width) / 2]))
  let l:v_pad = repeat([''], float2nr(winheight(0) * g:start_screen_vertical_padding))

  " 生成居中内容
  let l:centered = map(l:content, 'l:h_pad . v:val')
  call setline(1, l:v_pad + l:centered)
  setlocal nomodified
endfunction

function! s:header() abort
  let l:ascii_art = [
        \ '██╗  ██╗ ██████╗ ███╗   ██╗ ██████╗ ██████╗  ██████╗     ██╗   ██╗██╗███╗   ███╗',
        \ '██║  ██║██╔═══██╗████╗  ██║██╔═══██╗██╔══██╗██╔═══██╗    ██║   ██║██║████╗ ████║',
        \ '███████║██║   ██║██╔██╗ ██║██║   ██║███████║██║   ██║    ██║   ██║██║██╔████╔██║',
        \ '██╔══██║██║   ██║██║╚██╗██║██║   ██║██╔══██║██║   ██║    ╚██╗ ██╔╝██║██║╚██╔╝██║',
        \ '██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝██████╔╝╚██████╔╝     ╚████╔╝ ██║██║ ╚═╝ ██║ ',
        \ '╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═════╝  ╚═════╝       ╚═══╝  ╚═╝╚═╝     ╚═╝',
        \]
  return l:ascii_art + [''] " 添加空行分隔
endfunction

function! s:options() abort
  return [
        \ '[1] New File                  ',
        \ '[2] Open Today                ',
        \ '[3] Recent Files              ',
        \ '[4] Configuration             ',
        \ '[q] Quit Vim                  ',
        \ '',
        \ '▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬'
        \]
endfunction

function! s:footer() abort
  return [
        \ '',
        \ 'Vim ' . v:version . '  •  ' . strftime('%Y-%m-%d'),
        \ 'Hongbo''s StartScreen v1.0'
        \]
endfunction

" 交互功能 ===============================================
function! s:set_mappings() abort
  nnoremap <silent><buffer> 1 :enew<CR>
  nnoremap <silent><buffer> 2 :NotesToday<CR>
  nnoremap <silent><buffer> 3 <CR>
  nnoremap <silent><buffer> 4 :edit $MYVIMRC<CR>

  " 进入插入模式时清空缓冲区
  nnoremap <silent><buffer> i :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> I :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> a :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> A :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> o :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> O :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> s :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> S :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> c :call <SID>clear_and_insert()<CR>
  nnoremap <silent><buffer> C :call <SID>clear_and_insert()<CR>
endfunction

" 清空并进入插入模式的辅助函数（仅在第一次时）
function! s:clear_and_insert() abort
  " 检查是否是启动界面状态
  if &filetype ==# 'start_screen' && &buftype ==# 'nofile'
    " 设置缓冲区可修改
    setlocal modifiable
    " 清空所有内容
    silent %delete _
    " 设置为普通的可编辑缓冲区
    setlocal buftype= filetype=
    " 清除启动界面的按键映射，恢复默认行为
    call s:clear_start_screen_mappings()
    " 进入插入模式
    startinsert
  else
    " 如果不是启动界面状态，执行默认的 i 命令
    normal! i
  endif
endfunction

" 清除启动界面的特殊按键映射
function! s:clear_start_screen_mappings() abort
  silent! nunmap <buffer> i
  silent! nunmap <buffer> I
  silent! nunmap <buffer> a
  silent! nunmap <buffer> A
  silent! nunmap <buffer> o
  silent! nunmap <buffer> O
  silent! nunmap <buffer> s
  silent! nunmap <buffer> S
  silent! nunmap <buffer> c
  silent! nunmap <buffer> C
endfunction

function! s:set_syntax() abort
  syntax match StartScreenTitle /║\|╗\|╚\|╔\|╝\|╔\|═\|▬/
  syntax match StartScreenOption /$$.$$\ze/
  syntax match StartScreenKey /<Leader>.\+/
  syntax match StartScreenVersion /Vim \d\+/

  highlight default link StartScreenTitle Title
  highlight default link StartScreenOption Number
  highlight default link StartScreenKey Identifier
  highlight default link StartScreenVersion Comment
endfunction

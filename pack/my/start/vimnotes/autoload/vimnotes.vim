" vim: set foldmethod=marker:

" Public Functions {{{ "

function vimnotes#open_today(bang)
    if a:bang == "!"
        echo "open in current window"
    else
        vsp
    endif
    execute "lcd " . g:VimnotesRootDir
    let date = s:time_to_date(localtime())
    let fn = s:date_to_journal_fn(date)
    execute "edit " . fn
endfunction

function vimnotes#buffer_go_previous_journal()
    let datestr = expand("%:t:r")
    let current = [str2nr(datestr[:3]), str2nr(datestr[5:6]), str2nr(datestr[8:9])]
    let date = s:date_previous(current)
    execute "edit " . s:date_to_journal_fn(date)
endfunction

function vimnotes#buffer_go_next_journal()
    let datestr = expand("%:t:r")
    let current = [str2nr(datestr[:3]), str2nr(datestr[5:6]), str2nr(datestr[8:9])]
    let date = s:date_next(current)
    execute "edit " . s:date_to_journal_fn(date)
endfunction

function vimnotes#preview()
    execute "silent !" . g:VimnotesPreviewCommand . " %"
    redraw!
endfunction

function vimnotes#buffer_init_journal()
    " Remove all the content first
    normal ggdG
    let tasks = join(s:copy_unfinished_tasks_before(b:notes_journal_date), "\n")
    let titles = join(s:copy_repeat_titles_before(b:notes_journal_date), "\n")
    let projects = "- Project 1\n- Project 2"
    for line in g:VimnotesJournalTemplate
        let line = substitute(line, "{date}", b:notes_journal_datestr, "g")
        let line = substitute(line, "{tasks}", escape(tasks, '&'), "g")
        let line = substitute(line, "{projects}", projects, "g")
        let line = substitute(line, "{notes}", titles, "g")
        put =line
    endfor
    normal ggdd
endfunction

function vimnotes#task_toggle_done()
    " Goto the sign position
    let pos = col('.')
    normal ^f[l
    if getline('.')[col('.')-1] == ' '
        normal rx
    else
        execute 'normal r '
    endif
    " Restore cursor position
    call cursor(line('.'), pos)
endfunction

" }}} Public Functions "


" Private Functions {{{ "

function s:time_to_date(time)
    let year = str2nr(strftime("%Y", a:time))
    let month = str2nr(strftime("%m", a:time))
    let day = str2nr(strftime("%d", a:time))
    return [year, month, day]
endfunction

function s:date_to_journal_fn(date)
    return printf("%04d/%02d/%04d-%02d-%02d.md", 
                \ a:date[0], a:date[1], a:date[0], a:date[1], a:date[2])
endfunction

function s:date_previous(date)
    let year = a:date[0]
    let month = a:date[1]
    let day = a:date[2]
    if day > 1
        return [year, month, day-1]
    else
        if month > 1
            return [year, month-1, s:month_day_count(year, month-1)]
        else
            return [year-1, 12, s:month_day_count(year-1, 12)]
        endif
    endif
endfunction

function s:date_next(date)
    let year = a:date[0]
    let month = a:date[1]
    let day = a:date[2]
    let max_day = s:month_day_count(year, month)
    if day < max_day
        return [year, month, day+1]
    else
        if month < 12
            return [year, month+1, 1]
        else
            return [year+1, 1, 1]
        endif
    endif
endfunction

function s:month_day_count(year, month)
    let counts = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if s:is_leap_year(a:year)
        let counts[1] += 1
    endif
    return counts[a:month-1]
endfunction

function s:is_leap_year(year)
    if a:year % 100 == 0
        return a:year % 400 ? 0 : 1
    endif
    return a:year % 4 ? 0 : 1
endfunction

function s:copy_unfinished_tasks_before(date)
    let tasks = []
    let i = 0
    let current = a:date
    while i < 100
        let current = s:date_previous(current)
        let fn = s:date_to_journal_fn(current)
        if getftype(fn) == "file"
            let current_task_unfinished = 0
            let task_context = 0
            for line in readfile(fn)
                " For task title
                if match(line, "\\s*- \\[.\\] ") != -1
                    let task_context = 1
                    if match(line, "\\s*- \\[ \\] ") != -1
                        let current_task_unfinished = 1
                        call add(tasks, line)
                    elseif match(line, "@repeat") != -1
                        let current_task_unfinished = 1
                        let line = substitute(line, "- \\[.\\]", "- [ ]", "")
                        call add(tasks, line)
                    else
                        let current_task_unfinished = 0
                    endif
                " Additional text for previous task
                elseif task_context && (match(line, "\\s") == 0 || strlen(line) == 0)
                    if current_task_unfinished
                        call add(tasks, line)
                    endif
                " Out of task context
                else
                    let task_context = 0
                    let current_task_unfinished = 0
                endif
            endfor
            break
        endif
        echo "Prev journal " . fn . " not found, try next"
        let i += 1
    endwhile
    if len(tasks) == 0
        call add(tasks, "- [ ] To be implemented 1")
        call add(tasks, "- [ ] To be implemented 2")
    endif
    return tasks
endfunction

function s:copy_repeat_titles_before(date)
    let titles = []
    let i = 0
    let current = a:date
    while i < 100
        let current = s:date_previous(current)
        let fn = s:date_to_journal_fn(current)
        if getftype(fn) == "file"
            let title_context = 0
            for line in readfile(fn)
                " For task title
                if match(line, "#.*") != -1
                    if match(line, "@repeat") != -1
                        let title_context = 1
                        call add(titles, line)
                    else
                        let title_context = 0
                    endif
                " Additional text for previous task
                elseif title_context
                    call add(titles, line)
                " Out of task context
                else
                    let title_context = 0
                endif
            endfor
            break
        endif
        echo "Prev journal " . fn . " not found, try next"
        let i += 1
    endwhile
    return titles
endfunction

" }}} Private Functions "

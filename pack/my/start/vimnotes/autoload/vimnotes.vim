" vim: set foldmethod=marker:

" Public Functions {{{ "

function vimnotes#open_today()
    vsp
    execute "lcd " . g:VimnotesRootDir
    let date = s:time_to_date(localtime())
    let fn = s:date_to_journal_fn(date[0], date[1], date[2])
    execute "edit " . fn
endfunction

function vimnotes#buffer_go_previous_journal()
    let datestr = expand("%:t:r")
    let current = [str2nr(datestr[:3]), str2nr(datestr[5:6]), str2nr(datestr[8:9])]
    let date = s:date_previous(current[0], current[1], current[2])
    execute "edit " . s:date_to_journal_fn(date[0], date[1], date[2])
endfunction

function vimnotes#buffer_go_next_journal()
    let datestr = expand("%:t:r")
    let current = [str2nr(datestr[:3]), str2nr(datestr[5:6]), str2nr(datestr[8:9])]
    let date = s:date_next(current[0], current[1], current[2])
    execute "edit " . s:date_to_journal_fn(date[0], date[1], date[2])
endfunction

function vimnotes#preview()
    execute "silent !" . g:VimnotesPreviewCommand . " %"
endfunction

" }}} Public Functions "


" Private Functions {{{ "

function s:time_to_date(time)
    let year = str2nr(strftime("%Y", a:time))
    let month = str2nr(strftime("%m", a:time))
    let day = str2nr(strftime("%d", a:time))
    return [year, month, day]
endfunction

function s:date_to_journal_fn(year, month, day)
    return printf("%04d/%02d/%04d-%02d-%02d.md", 
                \ a:year, a:month, a:year, a:month, a:day)
endfunction

function s:date_previous(year, month, day)
    if a:day > 1
        return [a:year, a:month, a:day-1]
    else
        if a:month > 1
            return [a:year, a:month-1, s:month_day_count(a:year, a:month-1)]
        else
            return [a:year-1, 12, s:month_day_count(a:year-1, 12)]
        endif
    endif
endfunction

function s:date_next(year, month, day)
    let max_day = s:month_day_count(a:year, a:month)
    if a:day < max_day
        return [a:year, a:month, a:day+1]
    else
        if a:month < 12
            return [a:year, a:month+1, 1]
        else
            return [a:year+1, 1, 1]
        endif
    endif
endfunction

function s:month_day_count(year, month)
    let counts = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    if s:is_leap_year(a:year)
        counts[1] += 1
    endif
    return counts[a:month-1]
endfunction

function s:is_leap_year(year)
    if a:year % 100 == 0
        return a:year % 400 ? 0 : 1
    endif
    return a:year % 4 ? 0 : 1
endfunction

" }}} Private Functions "

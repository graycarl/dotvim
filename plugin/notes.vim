" Plugin for note taken

" TODO: Use settings
command! NotesOpen vsp | lcd ~/Documents/Notes | edit README.md | CtrlP

command! NotesToday call notes#open_today()

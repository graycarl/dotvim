" Set the highlight color for copilot suggestions by colorscheme

augroup copilot_color
  autocmd!
  autocmd ColorScheme * highlight CopilotSuggestion guifg=#9933ff
augroup END

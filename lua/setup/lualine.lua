local opts = {
  options = {
    -- 根据 NERD_FONT 环境变量来决定是否启用图标
    icons_enabled = vim.env.NERD_FONT ~= nil,
    section_separators = '',
    component_separators = '|',
  },
  sections = {
    lualine_b = {
      'branch',
      'diff',
      -- 默认的 diagnostic 图标无法显示，所以这里使用自定义的图标
      { 'diagnostics', symbols = {error = 'E', warn = 'W', info = 'I', hint = 'H'} },
    },
    -- 在 lualine 中显示文件图标颜色不太好看，所以这里不显示
    lualine_x = {'encoding', 'fileformat', {'filetype', colored = false}},
  },
}

return opts

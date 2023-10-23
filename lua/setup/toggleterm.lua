local function config()
  local toggleterm = require('toggleterm')
  toggleterm.setup{
    open_mapping = [[<c-\>]],
    direction = 'float',
  }
end

return {
  config = config
}

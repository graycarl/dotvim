-- Switch next/prev colorscheme

-- Fix: https://github.com/neovim/neovim/issues/27683
-- We need to keep track of the current colorscheme
local current

function SwitchColor(direction)
  if current == nil then
    current = vim.g.colors_name
  end
  local colors = vim.fn.getcompletion('', 'color')
  local idx = -1
  for i, color in ipairs(colors) do
    if color == current then
      idx = i
      break
    end
  end
  if idx == -1 then
    return
  end
  local new_idx = idx + direction
  if new_idx < 1 then
    new_idx = #colors
  elseif new_idx > #colors then
    new_idx = 1
  end
  vim.cmd('colorscheme ' .. colors[new_idx])
  current = colors[new_idx]
  -- Print the new colorscheme
  print('Switched to [' .. new_idx .. '] ' .. colors[new_idx])
end

-- Create commands to switch colorscheme
vim.cmd('command! -nargs=0 ColorSwitchNext lua SwitchColor(1)')
vim.cmd('command! -nargs=0 ColorSwitchPrev lua SwitchColor(-1)')

-- Switch next/prev colorscheme

-- Fix: https://github.com/neovim/neovim/issues/27683
-- We need to keep track of the current colorscheme
local current

function SwitchColor(direction)
  if current == nil then
    current = vim.g.colors_name
    if current == nil then
      current = 'default'
    end
  end
  local colors = vim.fn.getcompletion('', 'color')
  -- Remove colors with name contains `-`
  for i = #colors, 1, -1 do
    if string.match(colors[i], '-') then
      table.remove(colors, i)
    end
  end
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
  -- Switch background if current colors name do not contains `-`
  if vim.o.background == 'light' and direction == 1 then
    vim.o.background = 'dark'
    print('Switched to [' .. idx .. '] ' .. current .. ' with dark mode')
  elseif vim.o.background == 'dark' and direction == -1 then
    vim.o.background = 'light'
    print('Switched to [' .. idx .. '] ' .. current .. ' with light mode')
  else
    local new_idx = idx + direction
    if new_idx < 1 then
      new_idx = #colors
    elseif new_idx > #colors then
      new_idx = 1
    end
    vim.cmd('colorscheme ' .. colors[new_idx])
    current = colors[new_idx]
    if direction == -1 then
      vim.o.background = 'dark'
      print('Switched to [' .. new_idx .. '] ' .. colors[new_idx] .. ' with dark mode')
    else
      vim.o.background = 'light'
      print('Switched to [' .. new_idx .. '] ' .. colors[new_idx] .. ' with light mode')
    end
  end
end

-- Save current colorscheme to local/colorswitch.lua
function SaveColor()
  if current == nil then
    current = vim.g.colors_name
  end
  local file = io.open(vim.fn.stdpath('config') .. '/local/colorswitch.lua', 'w')
  if file == nil then
    print('Failed to open file')
    return
  end
  file:write('vim.cmd("colorscheme ' .. current .. '")\n')
  file:write('vim.o.background = "' .. vim.o.background .. '"\n')
  file:close()
end

-- Create commands to switch colorscheme
vim.cmd('command! -nargs=0 ColorSwitchNext lua SwitchColor(1)')
vim.cmd('command! -nargs=0 ColorSwitchPrev lua SwitchColor(-1)')
vim.cmd('command! -nargs=0 ColorSwitchSave lua SaveColor()')

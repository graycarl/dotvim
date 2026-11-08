-- 配置加载的故障隔离。
--
-- 背景：一个写错的配置模块不应该让整个编辑器降级。
--   * `require('lazy').setup()` 抛错 = 所有插件都不加载，症状像"nvim 变裸机"
--   * `init.lua` 里 source `local/*.lua` 抛错 = 后面的 local 配置全部被跳过，
--     而 `local/colorswitch.lua` 是 `ColorSwitchSave` 自动生成的
--
-- 失败不吞掉：记在 `M.errors` 里并 notify 一次（只报前 3 行），
-- `:checkhealth my` 会重新列出完整堆栈。

local M = {}

--- 加载失败的模块/文件：`name -> traceback`
M.errors = {}

local function remember(name, err)
  err = tostring(err)
  M.errors[name] = err
  vim.schedule(function()
    -- 多行 traceback 在命令行里会被截断，只留前 3 行（完整版在 :checkhealth my）
    local brief = vim.split(err, '\n') or {}
    brief = table.concat(vim.list_slice(brief, 1, math.min(#brief, 3)), '\n')
    vim.notify(('配置加载失败 %s\n%s\n（完整堆栈：:checkhealth my）'):format(name, brief),
      vim.log.levels.ERROR)
  end)
end

--- 带 traceback 的 pcall，返回 `ok, result`
local function try(fn)
  return xpcall(fn, debug.traceback)
end

--- 包一层：失败时记录并返回 `default`，不向上抛
--- @param name string 用于错误报告的名字
--- @param fn fun():any
--- @param default any 失败时的返回值
function M.call(name, fn, default)
  local ok, result = try(fn)
  if not ok then
    remember(name, result)
    return default
  end
  return result
end

--- `require` 一个模块；失败返回 nil（不抛错）
function M.require(name)
  return M.call(name, function()
    return require(name)
  end)
end

--- source 一个文件；失败记录并继续。
--- `.lua` 走 `loadfile`：`vim.cmd('source')` 会把错误包成
--- `init.lua..nvim_exec2()…E5113: Lua chunk: file:1: msg`，定位成本很高。
function M.source(path)
  if path:match('%.lua$') then
    return M.call(path, function()
      local chunk, err = loadfile(path)
      if not chunk then
        error(err, 0)
      end
      chunk()
      return true
    end, false)
  end
  return M.call(path, function()
    vim.cmd('source ' .. vim.fn.fnameescape(path))
    return true
  end, false)
end

--- 把 `lua/setup/<name>.lua` 的 `field` 字段包成 lazy 的回调。
--- 延迟到插件真正加载时才 require（顺带省一点启动时间），
--- 且该字段抛错只影响这一个插件。
--- @param name string 模块名，如 `'setup.telescope'`
--- @param field string|nil 字段名，默认 `'config'`
function M.run(name, field)
  field = field or 'config'
  return function(...)
    local mod = M.require(name)
    if type(mod) == 'function' then
      return mod(...)
    end
    if type(mod) == 'table' and type(mod[field]) == 'function' then
      return mod[field](...)
    end
    remember(name, ('模块没有 %s 字段'):format(field))
  end
end

--- 取 `lua/setup/<name>.lua` 的 opts：模块里有 `opts` 字段就用它，
--- 否则模块本身就是 opts；加载失败给一个空 table（插件用默认值）
function M.opts(name)
  local mod = M.require(name)
  if type(mod) == 'table' then
    return mod.opts ~= nil and mod.opts or mod
  end
  return {}
end

return M

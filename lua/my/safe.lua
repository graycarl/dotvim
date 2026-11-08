-- 配置加载的故障隔离。
--
-- 背景：一个写错的配置模块不应该让整个编辑器降级。
--   * `require('lazy').setup()` 抛错 = 所有插件都不加载，症状像"nvim 变裸机"
--   * `init.lua` 里 source `local/*.lua` 抛错 = 后面的 local 配置全部被跳过，
--     而 `local/colorswitch.lua` 是 `ColorSwitchSave` 自动生成的
--
-- 失败不吞掉：记在 `M.errors` 里（完整堆栈，首个错误胜出），并聚合 notify
-- 一次（只报模块名，避免 TUI 里连按回车）；完整内容在 `:checkhealth my`。

local M = {}

--- 加载失败的模块/文件：`name -> traceback`
M.errors = {}

--- 是否发生过加载失败（`init.lua` 会据此加一个 VimEnter 提醒）
function M.broken()
  return next(M.errors) ~= nil
end

-- ---------------------------------------------------------------- 通知

local queue = {}
local flushing = false

local function remember(name, err)
  -- 首个错误胜出：同一模块后续的失败通常是它的后果，覆盖会把真因藏起来
  M.errors[name] = M.errors[name] or tostring(err)
  vim.g.my_config_broken = true
  queue[#queue + 1] = name
  if flushing then
    return
  end
  flushing = true
  vim.schedule(function()
    flushing = false
    local names = table.concat(queue, '、')
    queue = {}
    vim.notify(
      ('配置加载失败：%s\n详情见 :checkhealth my（完整堆栈保留在那里）'):format(names),
      vim.log.levels.ERROR
    )
  end)
end

-- 非 string 的 error（`error({code=...})`）在 LuaJIT 下会被 `debug.traceback`
-- 原样返回，这里先 inspect 再补堆栈，否则只剩 `table: 0x...`
local function msgh(err)
  if type(err) ~= 'string' then
    err = vim.inspect(err)
  end
  return debug.traceback(err, 2)
end

local function try(fn)
  return xpcall(fn, msgh)
end

-- ---------------------------------------------------------------- 对外

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

--- 致命项（`lazy.setup`）：失败时**完整**打印堆栈，并让调用方短路后续加载。
--- 这类错误只截前几行的话，"nvim 变裸机"就没有可读的原因了。
--- @return boolean ok
function M.fatal(name, fn)
  local ok, err = try(fn)
  if not ok then
    M.errors[name] = M.errors[name] or tostring(err)
    vim.g.my_config_broken = true
    vim.notify(('配置加载失败 %s\n%s'):format(name, err), vim.log.levels.ERROR)
  end
  return ok
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
--- 延迟到插件真正加载时才 require，且该字段抛错只影响这一个插件
--- （仍然重新抛出，保留 lazy 自己的 "Failed to run config" 语义）。
--- @param name string 模块名，如 `'setup.telescope'`
--- @param field string|nil 字段名，默认 `'config'`
function M.run(name, field)
  field = field or 'config'
  return function(...)
    -- LuaJIT（Lua 5.1）没有 table.pack，用 select + unpack 保留中间 nil
    local n = select('#', ...)
    local args = { ... }
    local mod = M.require(name)
    if mod == nil then
      return -- require 已经记过真实原因，不要再覆盖
    end
    local fn = type(mod) == 'function' and mod
      or (type(mod) == 'table' and type(mod[field]) == 'function' and mod[field])
    if not fn then
      remember(name, ('模块没有 %s 字段'):format(field))
      return
    end
    -- 现实里最常见的坏法是 config() 本体报错，不只是 require 失败
    local ok, err = try(function()
      return fn(unpack(args, 1, args.n))
    end)
    if not ok then
      remember(name, err)
      error(err, 0)
    end
  end
end

--- 取 `lua/setup/<name>.lua` 的 opts：模块有 `opts` 字段就用它，否则模块
--- 本身就是 opts（两种形态都支持，见 AGENTS.md §2.1）。
--- 加载失败时给空 table：插件用默认配置起来，错误留在 `M.errors` 里。
function M.opts(name)
  local mod = M.require(name)
  if type(mod) ~= 'table' then
    return {} -- 失败已被 record；模块返回函数/nil 也当"没有 opts"
  end
  if mod.opts ~= nil then
    return mod.opts
  end
  return mod
end

return M

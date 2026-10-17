-- DeepSeek FIM transport layer: HTTP request/response, completion
-- post-processing and in-memory usage statistics.
--
-- The API key is handed to curl through a 0600 curl config file (`-K`) instead
-- of the command line, so it never shows up in `ps` output.  The JSON body is
-- piped through stdin (`-d @-`).
local M = {}

M.stats = {
  requests = 0,
  failed = 0,
  prompt_tokens = 0,
  completion_tokens = 0,
  cached_tokens = 0,
}

---Details about the most recent request, for `:DeepSeek`.
---@type table|nil
M.last = nil

---Read the API key from `opts.key_file`.
---@param opts table
---@return string|nil
function M.read_key(opts)
  if not opts.key_file or opts.key_file == '' then
    return nil
  end
  local fd = io.open(opts.key_file, 'r')
  if not fd then
    return nil
  end
  local key = fd:read('*a')
  fd:close()
  key = (key or ''):gsub('%s+', '')
  return key ~= '' and key or nil
end

---@param key string
---@return string|nil path
local function write_curl_config(key)
  local path = vim.fn.tempname()
  local fd = io.open(path, 'w')
  if not fd then
    return nil
  end
  fd:write(('header = "Authorization: Bearer %s"\n'):format((key:gsub('[\\"]', '\\%0'))))
  fd:close()
  vim.fn.setfperm(path, 'rw-------')
  return path
end

---Trim the part of the completion that repeats the text after the cursor.
---FIM models routinely echo the suffix; without this the suggestion would
---duplicate what is already on the line.
---@param text string
---@param suffix string
---@return string
local function trim_suffix_overlap(text, suffix)
  if text == '' or suffix == '' then
    return text
  end
  for n = math.min(#text, #suffix), 1, -1 do
    if text:sub(-n) == suffix:sub(1, n) then
      return text:sub(1, #text - n)
    end
  end
  return text
end

---Strip a leading echo of the text before the cursor (models occasionally
---repeat the last identifier instead of continuing it).
---@param text string
---@param prefix string
---@return string
local function trim_prefix_duplicate(text, prefix)
  if text == '' or prefix == '' then
    return text
  end
  local min_overlap = 12
  for n = math.min(#text, #prefix, 200), min_overlap, -1 do
    if text:sub(1, n) == prefix:sub(-n) then
      return text:sub(n + 1)
    end
  end
  return text
end

---@param text string
---@return boolean
local function has_repeated_line(text)
  local seen = {}
  for line in text:gmatch('[^\n]+') do
    local key = line:gsub('%s+', '')
    if key ~= '' then
      seen[key] = (seen[key] or 0) + 1
      if seen[key] >= 3 then
        return true
      end
    end
  end
  return false
end

---Post-process a raw completion.
---@param text string
---@param ctx table result of `context.build()` (prefix/suffix)
---@param opts table
---@param trace table|nil optional array that receives `{ name, text }` snapshots
---  of every stage, so a dropped completion can be explained afterwards
---@return string
function M.filter(text, ctx, opts, trace)
  local function step(name, value)
    if trace then
      trace[#trace + 1] = { name = name, text = value }
    end
    return value
  end
  if type(text) ~= 'string' or text == '' then
    return step('no-response', '')
  end
  text = text:gsub('\r\n', '\n'):gsub('\r', '\n'):gsub('%z', '')
  step('normalize', text)
  text = step('trim_suffix_overlap', trim_suffix_overlap(text, ctx.suffix))
  text = step('trim_prefix_duplicate', trim_prefix_duplicate(text, ctx.typed_prefix))
  text = step('trim_trailing_ws', (text:gsub('%s+$', '')))
  if text == '' then
    return step('dropped-empty', '')
  end
  if has_repeated_line(text) then
    return step('dropped-repetitive', '')
  end
  local max_lines = opts.max_lines or 10
  local lines = vim.split(text, '\n', { plain = true })
  if #lines > max_lines then
    text = step('truncate-lines', table.concat(vim.list_slice(lines, 1, max_lines), '\n'))
  end
  return step('kept', text)
end

---@param res table
---@param started integer hrtime
---@param cb fun(text: string|nil, err: string|nil, usage: table|nil)
function M._complete(res, started, cb)
  local ms = (vim.uv.hrtime() - started) / 1e6
  local payload, status = (res.stdout or ''):match('^(.*)\n(%d%d%d)$')
  status = tonumber(status)
  if not status then
    -- curl itself failed: cancelled job, timeout, DNS, ...
    local canceled = (res.signal or 0) ~= 0
    if canceled then
      M.last = { ms = ms, canceled = true }
      return cb(nil, nil)
    end
    local stderr = vim.trim(res.stderr)
    local err = stderr ~= '' and stderr or ('curl exit %d'):format(res.code or -1)
    M.stats.failed = M.stats.failed + 1
    M.last = { ms = ms, error = err }
    return cb(nil, err)
  end

  M.stats.requests = M.stats.requests + 1
  local data
  if payload and payload ~= '' then
    local ok, decoded = pcall(vim.json.decode, payload)
    if ok then
      data = decoded
    end
  end
  if status ~= 200 then
    local msg = (data and data.error and data.error.message) or payload or ''
    M.stats.failed = M.stats.failed + 1
    M.last = { ms = ms, status = status, error = ('HTTP %d: %s'):format(status, msg) }
    return cb(nil, M.last.error, M.last)
  end

  local usage = (data and data.usage) or {}
  local cached = usage.prompt_cache_hit_tokens or 0
  M.stats.prompt_tokens = M.stats.prompt_tokens + (usage.prompt_tokens or 0)
  M.stats.completion_tokens = M.stats.completion_tokens + (usage.completion_tokens or 0)
  M.stats.cached_tokens = M.stats.cached_tokens + cached
  local choice = data and data.choices and data.choices[1]
  local record = {
    ms = ms,
    status = status,
    prompt_tokens = usage.prompt_tokens or 0,
    completion_tokens = usage.completion_tokens or 0,
    cached_tokens = cached,
    -- `stop` = the model decided to insert nothing, `length` = ran into
    -- max_tokens; both are worth telling apart when a completion is empty.
    finish_reason = choice and choice.finish_reason or nil,
    choices = data and data.choices and #data.choices or 0,
  }
  M.last = record
  local text = (choice and choice.text) or ''
  cb(text, nil, record)
end

---Fire a FIM completion request.
---@param body table JSON request body
---@param opts table
---@param cb fun(text: string|nil, err: string|nil, usage: table|nil) `usage` is
---  the per-request token/time record, safe to keep when several requests are in
---  flight at once (unlike `api.last`)
---@return table|nil job handle with `:kill()`
function M.request(body, opts, cb)
  local function reply(text, err)
    vim.schedule(function()
      cb(text, err)
    end)
  end
  local key = M.read_key(opts)
  if not key then
    reply(nil, 'API key not readable at ' .. tostring(opts.key_file))
    return nil
  end
  local conf = write_curl_config(key)
  if not conf then
    reply(nil, 'cannot create curl config file')
    return nil
  end
  local ok, payload = pcall(vim.json.encode, body)
  if not ok then
    os.remove(conf)
    reply(nil, 'cannot encode request body')
    return nil
  end

  local args = {
    'curl',
    '-sS',
    '-K',
    conf,
    '-X',
    'POST',
    opts.end_point,
    '-H',
    'Content-Type: application/json',
    '--max-time',
    tostring(math.max(1, math.floor((opts.timeout or 8000) / 1000))),
    '-d',
    '@-',
    '-w',
    '\n%{http_code}',
  }
  local started = vim.uv.hrtime()
  local job
  job = vim.system(args, { text = true, stdin = payload }, function(res)
    os.remove(conf)
    vim.schedule(function()
      M._complete(res, started, cb)
    end)
  end)
  return job
end

return M

-- Cross-file context: signature summaries of the local modules a buffer imports.
--
-- The goal is to tell the model *which APIs exist* without spending the prompt
-- budget on whole files, so only definitions (signatures, never bodies) are
-- emitted.  Everything here is a pure function of (buffer text, referenced file
-- content): it never looks at the cursor, which is what keeps the prompt prefix
-- stable and DeepSeek's prompt cache effective.
--
-- Only direct imports are followed (one hop, no transitive closure), which
-- avoids cycles and bounds the reading cost.  Files outside the project root,
-- dependencies (node_modules, site-packages, ...) and secret-looking files are
-- never read.
local M = {}

---Parsers live in ~/.local/share/nvim/site/parser; `tsx` also parses plain
---.ts/.js sources, which is why javascript/typescript map onto it.
local PARSER_LANG = {
  python = 'python',
  lua = 'lua',
  rust = 'rust',
  typescript = 'tsx',
  javascript = 'tsx',
}

local COMMENT_LEADER = {
  python = '#',
  lua = '--',
  rust = '//',
  typescript = '//',
  javascript = '//',
}

---Extension -> filetype, used to summarise the *imported* files.
local EXT_FT = {
  py = 'python',
  lua = 'lua',
  rs = 'rust',
  ts = 'typescript',
  tsx = 'typescript',
  js = 'javascript',
  jsx = 'javascript',
}

---Import statements per filetype.  Each pattern captures the module specifier
---in `%1`; leading dots (Python relative imports) are part of the capture.
local IMPORT_PATTERNS = {
  python = {
    '^%s*import%s+([%w_%.]+)',
    '^%s*from%s+([%w_%.]+)%s+import%s',
  },
  lua = {
    "require%s*%(?%s*['\"]([%w_%./%-]+)['\"]",
  },
  rust = {
    '^%s*use%s+([%w_:]+)',
    '^%s*mod%s+([%w_]+)%s*;',
  },
  typescript = {
    "^%s*import%s+.-from%s+['\"]([^'\"]+)['\"]",
    "require%s*%(?%s*['\"]([^'\"]+)['\"]",
  },
}
IMPORT_PATTERNS.javascript = IMPORT_PATTERNS.typescript

---Never followed, even inside the project root.
local BLOCKED_DIRS = {
  ['node_modules'] = true,
  ['.venv'] = true,
  venv = true,
  ['.tox'] = true,
  ['site-packages'] = true,
  vendor = true,
  target = true,
  dist = true,
  build = true,
  ['.git'] = true,
  __pycache__ = true,
  ['.mypy_cache'] = true,
}

---Never read: credential-ish file names.
local BLOCKED_FILES = {
  '^%.env',
  '%.min%.js$',
  '%.lock$',
  '%.key$',
  '%.pem$',
  'secret',
  'id_rsa',
  'credential',
}

---tsquery per filetype.  Capture names are normalised: `@fndecl`, `@assign`,
---`@fn`, `@def`.
local QUERIES = {
  python = '(function_definition) @fndecl (class_definition) @def (expression_statement) @member',
  lua = '(function_declaration) @fndecl '
    .. '(assignment_statement (variable_list) (expression_list (function_definition))) @assign',
  rust = '(function_item) @fn (struct_item) @def (enum_item) @def '
    .. '(trait_item) @def (impl_item) @def (type_item) @def',
  typescript = '(function_declaration) @fndecl (class_declaration) @def '
    .. '(interface_declaration) @def (type_alias_declaration) @def '
    .. '(lexical_declaration) @def (method_definition) @fn',
}

---Fallback when no parser is installed: keep signature shaped lines.
local FALLBACK_PATTERNS = {
  python = '^%s*(async%s+def%s|def%s|class%s)',
  lua = '^%s*(function%s|[A-Za-z_][%w_%.]*%s*=%s*function)',
  rust = '^%s*(pub%s+)?(async%s+)?(fn|struct|enum|trait|impl|type|const|static|mod)%s',
  typescript = '^%s*(export%s+)?(declare%s+)?(async%s+)?(function|class|interface|type|enum)%s',
}

---`local function` in Lua is a private helper; without analysing what the
---module returns it would look like public API, so it is skipped by default.
local FALLBACK_LUA_LOCALS = '^%s*local%s+function%s'

local DEFAULTS = {
  max_files = 6,
  max_lines = 25,
  max_chars = 1200,
  max_scan = 200,
  read_lines = 1000,
  separate = false, -- blank line between files (A/B knob)
}

---@param cfg table|nil
---@param name string key of `cfg.cross_file`
---@param default any
local function opt(cfg, name, default)
  local c = (cfg and cfg.cross_file) or {}
  local v = c[name]
  if v == nil then
    return default
  end
  return v
end

M.opt = opt

---@param cfg table|nil
---@param ft string
---@return boolean
function M.enabled(cfg, ft)
  if opt(cfg, 'enabled', true) == false then
    return false
  end
  return IMPORT_PATTERNS[ft] ~= nil
end

---@param ft string
---@return string
local function leader(ft)
  return COMMENT_LEADER[ft] or '//'
end

---@param path string
---@return string|nil ft
local function ft_for_path(path)
  local ext = path:match('%.([%w_]+)$')
  return ext and EXT_FT[ext:lower()] or nil
end

-- ---------------------------------------------------------------- imports ---

---Extract module specifiers from `text`.
---@param text string
---@param ft string
---@param max_lines integer|nil
---@return table[] entries `{ spec, ft, raw }`
function M.parse_imports(text, ft, max_lines)
  local patterns = IMPORT_PATTERNS[ft]
  if not patterns then
    return {}
  end
  local out, seen = {}, {}
  local scanned = 0
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    scanned = scanned + 1
    if max_lines and scanned > max_lines then
      break
    end
    for _, pat in ipairs(patterns) do
      local spec = line:match(pat)
      if spec then
        if not seen[spec] then
          seen[spec] = true
          out[#out + 1] = { spec = spec, ft = ft, raw = vim.trim(line) }
        end
        break
      end
    end
  end
  return out
end

-- --------------------------------------------------------------- resolve ---

---@param path string
---@return boolean
local function is_file(path)
  local st = vim.uv.fs_stat(path)
  return st ~= nil and st.type == 'file'
end

---True when `path` is inside `root` and free of blocked names.
---@param path string
---@param root string
---@return boolean
local function allowed(path, root)
  local rp = vim.uv.fs_realpath(path)
  local rr = vim.uv.fs_realpath(root)
  if not rp or not rr then
    return false
  end
  if rp ~= rr and rp:sub(1, #rr + 1) ~= rr .. '/' then
    return false
  end
  local rel = rp:sub(#rr + 2)
  for segment in rel:gmatch('[^/]+') do
    if BLOCKED_DIRS[segment] then
      return false
    end
  end
  local base = rel:match('([^/]+)$') or rel
  for _, pat in ipairs(BLOCKED_FILES) do
    if base:find(pat) then
      return false
    end
  end
  return true
end

M.allowed = allowed

---@param candidates string[]
---@return string|nil
local function first_existing(candidates)
  for _, c in ipairs(candidates) do
    if is_file(c) then
      return c
    end
  end
  return nil
end

---Directories a Lua module may live under: every ancestor between `dir` and
---`root` contributes itself plus its `lua/` subdirectory (nvim runtimepath
---layout), so both `<pkg>/lua/mod.lua` and `<root>/lua/mod.lua` resolve.
---@param dir string
---@param root string
---@return string[]
function M.lua_roots(dir, root)
  local out, seen = {}, {}
  local function push(path)
    if not seen[path] then
      seen[path] = true
      out[#out + 1] = path
    end
  end
  local cur = dir
  while cur and cur ~= '' do
    push(cur .. '/lua')
    push(cur)
    if cur == root or #cur <= #root then
      break
    end
    local parent = vim.fs.dirname(cur)
    if parent == cur then
      break
    end
    cur = parent
  end
  push(root .. '/lua')
  push(root)
  return out
end

---Resolve one import specifier to a file on disk.
---@param entry table from `parse_imports`
---@param dir string directory of the importing file
---@param root string project root
---@return string|nil path
function M.resolve(entry, dir, root)
  local spec, ft = entry.spec, entry.ft
  local candidates = {}

  if ft == 'python' then
    local dots = #(spec:match('^%.*') or '')
    local rest = (spec:sub(dots + 1)):gsub('%.', '/')
    if dots > 0 then
      local base = dir
      for _ = 2, dots do
        base = vim.fs.dirname(base)
      end
      if rest == '' then
        candidates[#candidates + 1] = base .. '/__init__.py'
      else
        candidates[#candidates + 1] = base .. '/' .. rest .. '.py'
        candidates[#candidates + 1] = base .. '/' .. rest .. '/__init__.py'
      end
    else
      for _, base in ipairs({ root, root .. '/src', dir }) do
        candidates[#candidates + 1] = base .. '/' .. rest .. '.py'
        candidates[#candidates + 1] = base .. '/' .. rest .. '/__init__.py'
      end
    end
  elseif ft == 'lua' then
    local rest = spec:gsub('%.', '/')
    for _, base in ipairs(M.lua_roots(dir, root)) do
      candidates[#candidates + 1] = base .. '/' .. rest .. '.lua'
      candidates[#candidates + 1] = base .. '/' .. rest .. '/init.lua'
    end
  elseif ft == 'rust' then
    local rest, base = spec, dir
    if rest:match('^crate::') then
      rest, base = rest:gsub('^crate::', ''), root .. '/src'
    elseif rest:match('^super::') then
      rest, base = rest:gsub('^super::', ''), vim.fs.dirname(dir)
    else
      rest = rest:gsub('^self::', '')
    end
    rest = rest:gsub('::', '/')
    candidates[#candidates + 1] = base .. '/' .. rest .. '.rs'
    candidates[#candidates + 1] = base .. '/' .. rest .. '/mod.rs'
  else -- typescript / javascript: relative specifiers only
    if spec:sub(1, 1) == '.' then
      local base = vim.fs.normalize(dir .. '/' .. spec)
      for _, ext in ipairs({ '.ts', '.tsx', '.js', '.jsx' }) do
        candidates[#candidates + 1] = base .. ext
      end
      for _, ext in ipairs({ '.ts', '.tsx', '.js', '.jsx' }) do
        candidates[#candidates + 1] = base .. '/index' .. ext
      end
    end
  end

  return first_existing(candidates)
end

-- --------------------------------------------------------------- summary ---

local ROOT_TYPES = { module = true, chunk = true, source_file = true, program = true }
local BODY_TYPES = {
  block = true,
  declaration_list = true,
  class_body = true,
  statement_block = true,
  interface_body = true,
}
local CONTAINER_TYPES = {
  class_definition = true,
  class_declaration = true,
  interface_declaration = true,
  impl_item = true,
  trait_item = true,
}
---Wrappers that do not change where a definition lives.
local WRAPPER_TYPES = { export_statement = true, decorated_definition = true, declare_statement = true }

---Keep top-level definitions plus one level inside a class/impl/trait body
---(that is where the methods are); drop anything deeper (nested helpers,
---`mod tests`, closures).
---@param node TSNode
---@return boolean
local function is_relevant(node)
  local parent = node:parent()
  if parent and WRAPPER_TYPES[parent:type()] then
    parent = parent:parent()
  end
  if not parent then
    return false
  end
  if ROOT_TYPES[parent:type()] then
    return true
  end
  if BODY_TYPES[parent:type()] then
    local gp = parent:parent()
    return gp ~= nil and CONTAINER_TYPES[gp:type()] == true
  end
  return false
end

---@param node TSNode
---@param kind string
---@return TSNode|nil
local function find_child(node, kind)
  for child in node:iter_children() do
    if child:type() == kind then
      return child
    end
    for grandchild in child:iter_children() do
      if grandchild:type() == kind then
        return grandchild
      end
    end
  end
  return nil
end

---Python signatures end at the `:` that opens the body; the body itself is
---dropped.  Multi-line signatures are joined (max 3 extra lines).
---@param lines string[]
---@param node TSNode
---@param is_class boolean
---@return string
local function python_signature(lines, node, is_class)
  local row, col = node:range()
  local text = (lines[row + 1] or ''):sub(col + 1)
  local extra = 0
  while not text:match(':%s*$') and extra < 3 do
    extra = extra + 1
    text = text .. ' ' .. vim.trim(lines[row + 1 + extra] or '')
  end
  text = vim.trim(text)
  text = text:gsub('%s*:%s*$', ':')
  if is_class and not text:match(':$') then
    text = text .. ':'
  end
  return is_class and text or (text .. ' ...')
end

---Brace languages: everything up to the opening brace.  Types that fit on one
---line (`pub enum Kind { A, B }`) are kept verbatim because their members are
---part of the API; function bodies are always elided.
---@param lines string[]
---@param node TSNode
---@param elide_body boolean
---@return string
local function brace_signature(lines, node, elide_body)
  local row, col = node:range()
  local full = vim.trim((lines[row + 1] or ''):sub(col + 1))
  local cut = full:find('{', 1, true)
  if not cut then
    return full
  end
  if not elide_body and #full <= 100 and full:match('}%s*$') then
    return full
  end
  return vim.trim(full:sub(1, cut - 1)) .. ' { ... }'
end

---Lua: `function name(params)` / `name = function(params)`.  The node text
---already includes a leading `local`, if any.
---@param lines string[]
---@param node TSNode function_declaration or function_definition
---@param lhs string|nil assignment target, for the `name = function` form
---@return string
local function lua_signature(lines, node, lhs)
  local row = select(1, node:range())
  local text = vim.trim((lines[row + 1] or '') .. ' ' .. (lines[row + 2] or ''))
  if lhs then
    return lhs .. (text:match('function%s*(%b())') or '')
  end
  return text:match('^(.-%b())') or text
end

---Names a Lua module makes public through its top-level `return`.
---Used to tell `local function` API from private helpers.  Returns nil when the
---returned table cannot be seen statically.
---@param text string
---@return table|nil set
local function lua_exports(text)
  local block
  local literal = text:match('\nreturn%s*(%b{})') or text:match('^return%s*(%b{})')
  local var
  if literal then
    block = literal
  else
    var = text:match('\nreturn%s+([%w_]+)%s*$') or text:match('\nreturn%s+([%w_]+)%s*\n')
    if not var then
      return nil
    end
    block = text:match('\nlocal%s+' .. var .. '%s*=%s*(%b{})')
      or text:match('^local%s+' .. var .. '%s*=%s*(%b{})')
    if not block then
      return nil
    end
  end
  local names = {}
  for key in block:gmatch('([%w_]+)%s*=') do
    names[key] = true
  end
  -- `return M` with `local M = {}` above: whatever gets attached to the table
  -- is public, `M.helper = helper` re-exports a local under a new name.
  if var then
    for exported in text:gmatch('\n' .. var .. '%s*%.[%w_]+%s*=%s*([%w_]+)%s*\n') do
      names[exported] = true
    end
  end
  return names
end

---Signatures of everything worth knowing about in `text`.
---@param text string
---@param ft string
---@param cfg table|nil
---@return string[]|nil nil when no parser/query is available
local function definitions_ts(text, ft, cfg)
  local lang = PARSER_LANG[ft]
  local query_src = QUERIES[ft]
  if not lang or not query_src then
    return nil
  end
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  if not ok_parser then
    return nil
  end
  local ok_query, query = pcall(vim.treesitter.query.parse, lang, query_src)
  if not ok_query then
    return nil
  end
  local root = parser:parse()[1]:root()
  local lines = vim.split(text, '\n', { plain = true })
  local exports = ft == 'lua' and lua_exports(text) or nil
  local keep_locals = opt(cfg, 'lua_locals', false) == true
  local out = {}

  for id, node in query:iter_captures(root, text) do
    local capture = query.captures[id]
    local sr, sc = node:range()
    if capture == 'member' then
      -- Class attributes (`size: Tuple[int, int]`, `step: int = 0`) are the
      -- constructor API of a dataclass, so they are worth showing even though
      -- they are not definitions.  Plain statements are ignored.
      if is_relevant(node) then
        local raw = vim.trim((lines[sr + 1] or ''):sub(sc + 1):gsub('#.*$', ''))
        if raw:match('^[%w_]+%s*:') or raw:match('^[A-Z][A-Z_0-9]*%s*=') then
          out[#out + 1] = (lines[sr + 1] or ''):sub(1, sc) .. raw
        end
      end
    elseif capture == 'assign' then
      local fnval = find_child(node, 'function_definition')
      local lhs_node = node:child(0)
      if fnval and lhs_node and is_relevant(node) then
        local lhs = vim.treesitter.get_node_text(lhs_node, text)
        out[#out + 1] = (lines[sr + 1] or ''):sub(1, sc) .. lua_signature(lines, fnval, lhs)
      end
    elseif is_relevant(node) then
      local indent = (lines[sr + 1] or ''):sub(1, sc)
      local raw = (lines[sr + 1] or ''):sub(sc + 1)
      -- Visibility: private names are not part of the API the model should use.
      local hidden = false
      if ft == 'python' then
        local name = raw:match('^%s*def%s+([%w_]+)')
          or raw:match('^%s*async%s+def%s+([%w_]+)')
          or raw:match('^%s*class%s+([%w_]+)')
        -- `_helper` is private, `__init__`/`__all__` are not.
        hidden = name ~= nil and name:sub(1, 1) == '_' and name:sub(1, 2) ~= '__'
      elseif ft == 'rust' then
        local parent_type = node:parent() and node:parent():type() or ''
        local in_trait = parent_type == 'declaration_list'
          and node:parent():parent()
          and node:parent():parent():type() == 'trait_item'
        hidden = node:type() == 'function_item'
          and not in_trait
          and raw:match('^%s*pub%f[%A]') == nil
      elseif ft == 'typescript' or ft == 'javascript' then
        -- Methods inherit visibility from the class that contains them.
        local ancestor, hops = node:parent(), 0
        local exported = false
        while ancestor and hops < 3 do
          if ancestor:type() == 'export_statement' then
            exported = true
            break
          end
          ancestor = ancestor:parent()
          hops = hops + 1
        end
        hidden = not exported
      end
      -- Decorators annotate the definition they precede.
      local parent = node:parent()
      if not hidden and parent and parent:type() == 'decorated_definition' then
        for child in parent:iter_children() do
          if child:type() == 'decorator' then
            out[#out + 1] = indent .. vim.trim(vim.treesitter.get_node_text(child, text))
          end
        end
      end
      if hidden then
        goto continue
      end
      local sig
      if ft == 'python' then
        sig = python_signature(lines, node, node:type() == 'class_definition')
      elseif ft == 'lua' then
        local is_local = node:type() == 'function_declaration' and raw:match('^local%s') ~= nil
        local name = raw:match('^local%s+function%s+([%w_%.]+)')
        if not (is_local and not keep_locals and exports ~= nil and not (name and exports[name])) then
          sig = lua_signature(lines, node, nil)
        end
      else
        local t = node:type()
        sig = brace_signature(lines, node, t == 'function_item' or t == 'function_declaration'
          or t == 'method_definition')
      end
      if sig then
        out[#out + 1] = indent .. sig
      end
      ::continue::
    end
  end
  return out
end

---Regex-only fallback (no parser installed): keep signature shaped lines.
---@param text string
---@param ft string
---@param cfg table|nil
---@return string[]
local function definitions_regex(text, ft, cfg)
  local pat = FALLBACK_PATTERNS[ft]
  if not pat then
    return {}
  end
  local exports = ft == 'lua' and lua_exports(text) or nil
  local keep_locals = opt(cfg, 'lua_locals', false) == true
  local out = {}
  for line in (text .. '\n'):gmatch('([^\n]*)\n') do
    local name = line:match('^%s*local%s+function%s+([%w_%.]+)')
    local is_local = line:find(FALLBACK_LUA_LOCALS) ~= nil
    local skip = ft == 'lua' and is_local and not keep_locals and exports ~= nil
      and not (name and exports[name])
    if line:find(pat) and not skip then
      local indent = line:match('^(%s*)') or ''
      local body = vim.trim(line:sub(#indent + 1))
      local cut = body:find('{', 1, true)
      if cut then
        body = vim.trim(body:sub(1, cut - 1))
      end
      out[#out + 1] = indent .. (body:gsub('%s*:%s*$', ':'))
    end
  end
  return out
end

---Summarise one source file's public surface.
---@param text string
---@param ft string
---@param cfg table|nil
---@param rel_path string|nil path shown in the `From:` marker
---@return string|nil summary
function M.summary_text(text, ft, cfg, rel_path)
  if not text or text == '' or not ft then
    return nil
  end
  local defs = definitions_ts(text, ft, cfg) or definitions_regex(text, ft, cfg)
  local max_lines = opt(cfg, 'max_lines', DEFAULTS.max_lines)
  local max_chars = opt(cfg, 'max_chars', DEFAULTS.max_chars)
  local kept, chars = {}, 0
  for _, line in ipairs(defs) do
    if #kept >= max_lines or chars + #line > max_chars then
      break
    end
    kept[#kept + 1] = line
    chars = chars + #line + 1
  end
  if #kept == 0 then
    return nil
  end
  return ('%s From: %s\n%s'):format(leader(ft), rel_path or '?', table.concat(kept, '\n'))
end

---@param path string
---@param cfg table|nil
---@param rel_path string|nil
---@return string|nil summary
---@return string|nil err
function M.summary_file(path, cfg, rel_path)
  local ft = ft_for_path(path)
  if not ft then
    return nil, 'unsupported extension'
  end
  local ok, lines = pcall(vim.fn.readfile, path, '', opt(cfg, 'read_lines', DEFAULTS.read_lines))
  if not ok or type(lines) ~= 'table' or #lines == 0 then
    return nil, 'unreadable'
  end
  return M.summary_text(table.concat(lines, '\n'), ft, cfg, rel_path or path)
end

-- ----------------------------------------------------------------- build ---

---Nearest project root above `dir` (no buffer involved, so the eval can use it
---for arbitrary paths without creating buffers).
---@param dir string
---@return string
function M.root_of(dir)
  local markers = { '.git', 'pyproject.toml', 'setup.py', 'package.json', 'Cargo.toml' }
  local found = vim.fs.find(markers, { upward = true, path = dir, limit = 1 })[1]
  return found and vim.fs.dirname(found) or dir
end

---Path shown in the `From:` marker: relative to the project root.
---@param path string
---@param root string
---@return string
function M.rel_path(path, root)
  local rp = vim.uv.fs_realpath(path)
  local rr = vim.uv.fs_realpath(root)
  if rp and rr and rp:sub(1, #rr + 1) == rr .. '/' then
    return rp:sub(#rr + 2)
  end
  return vim.fn.fnamemodify(path, ':~:.')
end

---Summaries for every resolvable local import mentioned in `text`.
---@param text string importing file's text
---@param path string|nil absolute path of the importing file
---@param ft string
---@param cfg table|nil
---@return table `{ text, files, skipped, entries }`
function M.build_text(text, path, ft, cfg)
  local result = { text = '', files = {}, skipped = {}, entries = {} }
  if not M.enabled(cfg, ft) then
    return result
  end
  local dir = (path and path ~= '') and vim.fs.dirname(path) or vim.uv.cwd()
  local root = M.root_of(dir)

  result.entries = M.parse_imports(text, ft, opt(cfg, 'max_scan', DEFAULTS.max_scan))

  local max_files = opt(cfg, 'max_files', DEFAULTS.max_files)
  local seen, blocks = {}, {}
  for _, entry in ipairs(result.entries) do
    local resolved = M.resolve(entry, dir, root)
    local reason
    if not resolved then
      reason = 'not found'
    elseif not allowed(resolved, root) then
      reason = 'blocked'
    else
      local rp = vim.uv.fs_realpath(resolved)
      if seen[rp] then
        reason = 'duplicate'
      elseif #blocks >= max_files then
        reason = 'file limit'
      end
    end
    if reason then
      result.skipped[#result.skipped + 1] = { spec = entry.spec, reason = reason }
    else
      seen[vim.uv.fs_realpath(resolved)] = true
      local rel = M.rel_path(resolved, root)
      local summary = M.summary_file(resolved, cfg, rel)
      if summary then
        blocks[#blocks + 1] = summary
        result.files[#result.files + 1] = { spec = entry.spec, path = resolved, rel = rel }
      else
        result.skipped[#result.skipped + 1] = { spec = entry.spec, reason = 'no definitions' }
      end
    end
  end
  result.text = table.concat(blocks, opt(cfg, 'separate', DEFAULTS.separate) and '\n\n' or '\n')
  return result
end

---Summaries for the imports of `bufnr` (uses the buffer text, not the file).
---@param bufnr integer
---@param cfg table|nil
---@return table `{ text, files, skipped, entries }`
function M.build(bufnr, cfg)
  local ft = vim.bo[bufnr].filetype
  local path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, opt(cfg, 'max_scan', DEFAULTS.max_scan), false)
  return M.build_text(table.concat(lines, '\n'), path, ft, cfg)
end

-- Cache --------------------------------------------------------------------
-- Summarising costs ~4ms per imported file (read + parse), which is too much
-- to redo on every request, so the result is cached per buffer and invalidated
-- by the import block's text and by the mtime/size of the files it read.
local cache = { bufnr = -1, key = '', text = '', files = {}, hits = 0 }

---@param c table
---@return boolean
local function cache_stale(c)
  for _, f in ipairs(c.files) do
    local st = vim.uv.fs_stat(f.path)
    if not st or st.mtime.sec ~= f.mtime or st.size ~= f.size then
      return true
    end
  end
  return false
end

---Cached variant of `M.build`, for the prompt path.
---@param bufnr integer
---@param cfg table|nil
---@return table `{ text, files, skipped, entries, hits }`
function M.cached_build(bufnr, cfg)
  local ft = vim.bo[bufnr].filetype
  if not M.enabled(cfg, ft) then
    return { bufnr = bufnr, key = '', text = '', files = {}, skipped = {}, entries = {}, hits = 0 }
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, opt(cfg, 'max_scan', DEFAULTS.max_scan), false)
  local key = table.concat(lines, '\n')
  if cache.bufnr == bufnr and cache.key == key and not cache_stale(cache) then
    cache.hits = (cache.hits or 0) + 1
    return cache
  end
  local result = M.build_text(key, vim.api.nvim_buf_get_name(bufnr), ft, cfg)
  result.bufnr, result.key, result.hits = bufnr, key, 0
  for _, f in ipairs(result.files) do
    local st = vim.uv.fs_stat(f.path)
    f.mtime = st and st.mtime.sec or 0
    f.size = st and st.size or 0
  end
  cache = result
  return cache
end

---@return table last cached result (for `:DeepSeek status`)
function M._cache()
  return cache
end

return M

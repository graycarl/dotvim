# AGENTS.md — Neovim 配置指南（面向 AI Agent）

本文档旨在帮助 AI Agent 理解本 Neovim 配置的设计原则、目录结构、命名规范和修改规则，确保在协助用户修改配置时保持一致性和正确性。

---

## 一、整体架构

配置目录为 `~/.vim/`，使用 **lazy.nvim** 作为插件管理器，所有第三方插件在 `lua/plugins.lua` 中统一声明。

```
~/.vim/
├── init.lua                 # 入口：设置 leader 键、启动 lazy.nvim、加载各模块
├── lua/
│   ├── plugins.lua          # lazy.nvim 插件清单（唯一入口）
│   ├── mappings.lua         # 全局快捷键映射
│   └── setup/               # 各插件的配置模块，按功能拆分
├── plugin/                  # 本地小插件（不依赖 lazy.nvim 的独立功能）
├── after/ftplugin/          # 文件类型专用设置
├── autoload/                # Vim 自动加载的公共函数
├── ftdetect/                # 自定义文件类型检测
├── pack/                    # Vim 原生包（packpath），通过 lazy.nvim 引用加载
│   ├── my/start/            # 自启动本地插件
│   └── my/opt/              # 按需加载的本地插件（veeva、deepseek-fim）
└── local/                   # 本地私有配置（不提交 git）
```

---

## 二、核心规则

### 2.1 插件管理

- **所有第三方插件**必须在 `lua/plugins.lua` 中声明，使用 lazy.nvim 的规范格式。
- 插件配置尽可能使用 `opts` 字段（自动调用 `setup()`），或 `config` 字段手动调用配置函数。
- `setup/` 目录下的配置文件返回包含 `config` 或 `init` 或 `opts` 的 table，供 `plugins.lua` 引用。
- 永远不要直接修改 `~/.vim/pack/` 下的第三方插件代码（即 submodule 管理的项目）。

### 2.2 配置模块规范（`lua/setup/`）

每个文件对应一个插件的配置，函数通过 `return { config = ..., init = ..., opts = ... }` 导出：

| 导出字段 | 含义 | 调用时机 |
|---------|------|---------|
| `config` | 需要手动调用 `setup()` 的配置 | 在 plug-in spec 的 `config` 字段中调用 |
| `init` | 需要在插件加载前执行的代码 | 在 plug-in spec 的 `init` 字段中调用 |
| `opts` | 自动 `setup()` 的 opts table | 在 plug-in spec 的 `opts` 字段中直接引用 |

### 2.3 本地私有配置（`local/`）

- `local/` 目录在 `.gitignore` 中，**不提交 git**。
- `init.lua` 会自动加载 `local/*.vim` 和 `local/*.lua`。
- 用途：个人工作环境设置（如字体大小、特定项目的插件加载）。
- 示例：`local/colorswitch.lua` — 由 `ColorSwitchSave` 命令自动生成，保存当前配色方案。
- Agent **可以读取** `local/` 的文件以理解用户偏好，但**不应修改**这些文件，除非用户明确要求。

### 2.4 本地小插件（`plugin/`）

- 存放不依赖 lazy.nvim 的独立功能，使用 Vim 原生 `plugin/` 机制自动加载。
- 每个文件实现一个独立功能，文件名需自述其意。
- 使用 Lua 或 VimL 均可，保持文件简洁。

### 2.5 环境变量的角色

本配置使用环境变量实现条件加载和切换：

| 环境变量 | 作用 | 取值 |
|---------|------|------|
| `$NERD_FONT` | 是否启用 Nerd Font 图标（devicons、nvim-tree 图标等） | 设置即启用 |
| `$VIM_AI` | AI 后端选择 | `copilot` 或 `deepseek` |
| `$TERM_PROGRAM` | 判断终端类型（Apple_Terminal 禁用 termguicolors） | 自动 |
| `$VIMHOME` | 在 `init.lua` 中设置为配置目录路径 | 自动 |

**修改规则**：如果要添加新的环境变量条件加载，应在 `plugins.lua` 中使用 `cond` 字段，而非在插件内部判断。

---

## 三、快捷键体系

| 前缀 | 变量 | 值 | 用途 |
|------|------|----|------|
| `<leader>` | `vim.g.mapleader` | `\`（反斜杠） | 全局操作 |
| `<localleader>` | `vim.g.maplocalleader` | `<Space>`（空格） | 缓冲区/语言本地操作 |

**映射添加规则**：
- 全局映射 → `lua/mappings.lua`
- LSP 相关映射 → `lua/setup/lsp.lua` 的 `on_attach` 回调中
- 文件类型专用映射 → `after/ftplugin/<ft>.vim` 中（仅对当前 buffer 生效）
- 插件功能映射 → 插件的配置模块中（如 `telescope.lua`、`nvim_tree.lua`）

---

## 四、各配置模块职责

| 文件 | 职责 | 关键信息 |
|------|------|---------|
| `init.lua` | 启动入口 | 设置 `mapleader`、启动 lazy、加载各模块、加载 local 目录 |
| `plugins.lua` | 插件清单 | 所有第三方与本地插件的声明 |
| `mappings.lua` | 全局快捷键 | 不要在此处添加 LSP 或文件类型相关的映射 |
| `setup/vim.lua` | Neovim 核心选项 | 缩进、搜索、折叠、备份、编码、UI 等基础设置 |
| `setup/lsp.lua` | LSP 完整配置 | mason、lspconfig、fidget、lint；`on_attach` 回调定义 LSP 映射 |
| `setup/blink.lua` | 自动补全 | blink.cmp + LuaSnip，Tab/Shift-Tab 导航；`<C-l>` 向后跳 snippet |
| `setup/treesitter.lua` | 语法高亮/文本对象 | 文本对象映射：`aa`/`ia`(参数)、`af`/`if`(函数)、`ac`/`ic`(类) |
| `setup/telescope.lua` | 模糊搜索 | 定义 `<C-p>`、`<leader>sf`、`<leader>sg` 等搜索命令 |
| `setup/lualine.lua` | 状态栏 | 图标跟随 `$NERD_FONT` |
| `setup/nvim_tree.lua` | 文件树 | `T` 快捷键切换；图标跟随 `$NERD_FONT` |
| `setup/toggleterm.lua` | 浮动终端 | `<C-\>` 切换 |
| `setup/gitsigns.lua` | Git 符号 | 自定义符号样式 |
| `setup/copilot.lua` | Copilot AI | 白名单文件类型；`<C-J>` 接受补全 |
| `setup/deepseek.lua` | DeepSeek FIM 补全配置 | 插件本体在 `pack/my/opt/deepseek-fim`；密钥文件、模型、触发、上下文预算、键位 |
| `setup/vimnote.lua` | 日记模板 | `VimnotesJournalTemplate` 全局变量 |
| `autoload/my.vim` | 公共 VimL 函数 | 目前仅 `my#Goto_parent_dir`（`mappings.lua` 的 `-` 映射） |
| `autoload/myrust.vim` | Rust 智能运行 | `myrust#Run()`：examples 目录下跑 `cargo run --example`，否则 `:Crun`，无 cargo 工程时 `:RustRun`（命令均由 Nvim runtime 提供） |
| `ftdetect/ebnf.vim` | `.ebnf` 文件类型检测 | 顶层 `ftdetect/` 下唯一文件 |

---

## 五、文件类型配置（`after/ftplugin/`）

每个文件对应一种文件类型的本地设置，命名格式为 `<filetype>.vim`。

| 文件 | 主要设置 |
|------|---------|
| `python.vim` | 折叠（2 级）、`<F5>` 运行、`<F8>` ruff fix、自动 lint、`<F6>`/`<F7>` 测试、行宽检查 |
| `rust.vim` | `<F5>` 智能运行（`myrust#Run`）、`<F6>` `:Cbuild`、`<F7>` `:Ctest`（cargo 命令由 Nvim runtime 提供）、折叠 2 级 |
| `markdown.vim` | 表格格式化（`gq`）、tab 2 空格、中文 formatoptions |
| `lua.vim` | tab 2 空格、写文件自动去尾随空格 |
| `javascript.vim` | tab 2 空格 |
| `yaml.vim` | tab 2 空格、indent 折叠、中文 formatoptions |
| `diff.vim` | 按 `diff --git` 行自定义折叠 |

**修改规则**：
- 为已有文件类型添加设置 → 编辑对应 `.vim` 文件
- 为新文件类型添加设置 → 创建 `after/ftplugin/<ft>.vim`
- 使用 `setlocal`（而非 `set`）确保设置仅对当前 buffer 生效
- 使用 `<buffer>` 限定 autocmd 和 mapping 的作用范围

---

## 六、本地插件（`plugin/`）索引

| 文件 | 功能 | 说明 |
|------|------|------|
| `colorswitch.lua` | 配色切换 | `F3`/`F4` 切换，`ColorSwitchSave` 保存到 `local/colorswitch.lua` |
| `fts.vim` | 文件类型全局设置 | 禁用 python provider、markdown 折叠等 |
| `search.vim` | 通用搜索命令 | `:S` / `:SG` 命令（基于 grep / fugitive） |
| `highlight_yank.lua` | 复制高亮 | 复制后短暂高亮 |
| `json_to_yaml.lua` | JSON 转 YAML | `:ToYaml` 预览、`:ToYaml!` 写入同名 `.yaml`（后端复用 `~/.shell/tools/json2yaml.py`） |
| `lastcursor.vim` | 光标记忆 | 重新打开文件时回到上次位置 |
| `large_files.vim` | 大文件保护 | >10MB 的文件禁用语法高亮、撤销、只读打开 |
| `start_screen.vim` | 启动界面 | 显示 ASCII art 和快捷选项（带"hongbo"品牌） |
| `redir_tab.vim` | 命令输出 | `:RedirTab <cmd>` 在新标签中显示命令输出 |
| `copilot_color.vim` | Copilot 颜色 | 设置 Copilot 补全提示色为紫色（`#9933ff`） |
| `pi.vim` | pi 入口 | `:PI` 命令打开 pi 终端 |

### `pack/my/` 本地插件（通过 lazy.nvim 以 `dir` 引用）

| 插件 | 加载 | 功能 |
|------|------|------|
| `start/encrypt` | 自启动 | `.enc` 文件透明加解密（openssl；`-md md5` 是为兼容既有密文，不要升级） |
| `start/vault` | 自启动 | `.vault` 密码本：写时备份、`<buffer>` 命令 `CopyItemValue` |
| `start/vimnotes` | 自启动 | 日记系统：`:NotesToday`、模板填充、任务勾选；ft 为复合型 `markdown.vimnotes` |
| `opt/veeva` | 按需 | 工作工具集（git/jira 等），由 `local/local.lua` 里 `require('lazy').load` 启用 |
| `opt/deepseek-fim` | 条件加载 | DeepSeek FIM 补全（`$VIM_AI=deepseek` 时启用），详见 §8.1 |

---

## 七、LSP 配置说明

LSP 配置使用较新的 Neovim API（`vim.lsp.config()` + `vim.lsp.enable()`）：

```
vim.lsp.config(server_name, opts)   -- 注册服务端配置
vim.lsp.enable(server_name)         -- 启用服务端
```

- mason 管理 LSP 服务端的自动安装
- 当前启用的 LSP 服务端：`lua_ls`、`basedpyright`、`rust_analyzer`（定义在 `setup/lsp.lua` 的 `servers` table 中）
- lint 工具配置也在 `setup/lsp.lua` 中（vale、mypy、ruff、flake8）

**修改规则**：
- 添加新 LSP → 在 `servers` table 中添加条目
- 修改 LSP 设置 → 直接修改 `setup/lsp.lua` 中对应 server 的 `settings`
- 添加新 lint 工具 → 修改 `lint.linters_by_ft` table

---

## 八、AI 后端切换机制

通过 `$VIM_AI` 环境变量切换：

```
# 使用 Copilot
export VIM_AI=copilot

# 使用 DeepSeek FIM（自研本地插件）
export VIM_AI=deepseek
```

- 两个后端在 `plugins.lua` 中用 `cond` 互斥加载：`copilot.vim`、`pack/my/opt/deepseek-fim`
- 二者使用相同的接受快捷键 `<C-J>`

### 8.1 DeepSeek FIM（`pack/my/opt/deepseek-fim`）

用 DeepSeek 的 FIM 接口（`https://api.deepseek.com/beta/completions`，`prompt` + `suffix`）
提供与 copilot 手感一致的紫色 ghost text 补全（纯虚文本，复用 `CopilotSuggestion` 高亮，
颜色由 `plugin/copilot_color.vim` 统一设置）。

**完整文档（架构、键位/命令、配置、跨文件上下文、A/B 数据、未来优化点）在插件目录内：
`pack/my/opt/deepseek-fim/README.md` —— 改动这个插件前先读它。**

| 模块 | 职责 |
|------|------|
| `lua/deepseek/init.lua` | setup、插入模式触发状态机（autocmd / debounce / throttle / 取消）、键位、`:DeepSeek` 命令 |
| `lua/deepseek/context.lua` | prompt/suffix 装配：`# Path:` 标记 + 文件头 + 光标前内容（按 token 预算裁剪） |
| `lua/deepseek/api.lua` | curl 请求（key 走 0600 配置文件，不进 argv）、过滤链、会话统计 |
| `lua/deepseek/render.lua` | extmark 渲染、粘性建议裁剪、清理 |
| `lua/deepseek/cross_file.lua` | 被 import 文件的签名摘要（实验特性）+ buffer 级缓存 |
| `lua/deepseek/eval.lua` | 离线 A/B 评测（`:DeepSeek eval`）、空补全死因诊断 |

仓库级要点（其余看 README）：

- 配置在 `lua/setup/deepseek.lua`；key 在 `local/deepseek.key`（`local/` 已 gitignore，权限保持 600）；
  文件类型白名单与 `setup/copilot.lua` 保持一致，接受键同样是 `<C-J>`。
- **粘性建议**（继续输入时按前缀裁剪已显示的建议）和**稳定 prompt 头部**（前缀缓存命中的前提，
  命中价 $0.006/M vs 未命中 $0.3/M）是两个不要破坏的设计点；FIM 模型会复述光标后内容，
  `api.filter` 必须裁掉。
- **跨文件上下文**（`cross_file.enabled`，默认 `true`）：会把被 import 的本地文件**签名**发到
  DeepSeek API，只读项目根内文件并跳过依赖目录与凭证类文件。实测**无可靠收益**、prompt token
  +21%~31%（两次 A/B 共 94 个配对样本，数据见 README），默认开启只是方便手动体验；
  `:DeepSeek cross` 热切换，`:DeepSeek ctx` 查看注入了什么。
- `:DeepSeek status|stats|toggle|refresh|ctx|eval|cross`；`api.filter` 的第 4 个参数 `trace`
  能逐级回放过滤过程，用于排查"补全为什么是空的"。

## 九、文件修改通用规则

1. **插件配置修改** → 编辑 `lua/plugins.lua` 加上插件声明，然后在 `lua/setup/` 中创建或修改对应的配置模块
2. **核心选项修改** → `lua/setup/vim.lua`
3. **快捷键映射修改** → 按照"映射添加规则"（见第三节）选择合适的位置
4. **文件类型设置修改** → `after/ftplugin/<ft>.vim`
5. **新增本地小功能** → `plugin/<功能名>.lua` 或 `.vim`
6. **本地私有配置** → `local/<文件名>.lua` 或 `.vim`（不提交）
7. **颜色/主题相关** → 配色方案在 `plugins.lua` 中声明，切换逻辑在 `plugin/colorswitch.lua`
8. **配置风格**：保持原有风格——VimL 文件用 `vim` 后缀，Lua 文件用 `lua` 后缀；不要混用语言风格

---

## 十、Git 注意事项

- `.gitignore` 忽略：`local/`、`.pi/`、`.DS_Store`、`.mypy_cache`
- `lazy-lock.json` 随插件更新而变更，正常提交即可

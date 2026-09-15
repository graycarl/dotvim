# deepseek-fim

用 DeepSeek 的 FIM（Fill-In-the-Middle）接口做 **copilot 风格的 inline ghost text 补全**：
纯虚文本、无 popup、`<C-J>` 接受，手感与 `copilot.vim` 对齐。

它是自研的本地插件（不依赖任何第三方 Lua 库），只在 `$VIM_AI` 为 `deepseek` 时加载，
与 `copilot.vim`（`$VIM_AI=copilot`）互斥。配置在 `lua/setup/deepseek.lua`。

```text
lua/deepseek/
  init.lua        触发状态机、键位、接受、命令
  context.lua     prompt/suffix 装配（token 预算、文件头、省略标记）
  api.lua         curl 传输、过滤链、会话统计
  render.lua      extmark 渲染、粘性建议
  cross_file.lua  被 import 文件的签名摘要（实验特性，见下）
  eval.lua        离线 A/B 评测工具
```

## 快速开始

```sh
export VIM_AI=deepseek
echo 'sk-...' > ~/.vim/local/deepseek.key && chmod 600 ~/.vim/local/deepseek.key
```

`local/` 已在 `.gitignore` 里；key 只从这里读，**不进命令行参数**（见"请求"一节）。

## 键位与命令

| 键 | 作用 |
| --- | --- |
| `<C-J>` | 接受整段建议 |
| `<M-Right>` | 只接受一个词 |
| `<M-C-Right>` | 只接受一行 |
| `<M-\>` | 换一个候选（内部轮换 temperature 0 → 0.3 → 0.7，并绕过节流） |
| `<C-]>` | 丢弃当前建议 |

| 命令 | 作用 |
| --- | --- |
| `:DeepSeek` / `:DeepSeek status` | 开关状态、模型、key 是否可读、当前 filetype 是否启用、cross-file 状态、最近一次请求耗时/token |
| `:DeepSeek toggle` | 全局开关补全 |
| `:DeepSeek cross` | 热切换跨文件上下文（切换后立刻重新请求当前行） |
| `:DeepSeek refresh` | 等价于 `<M-\>` |
| `:DeepSeek stats` | 本次会话的请求数、prompt/缓存/补全 token |
| `:DeepSeek ctx` | 打印跨文件块：拉入哪些文件、哪些被跳过及原因、块内容 |
| `:DeepSeek eval [n] [all]` | 离线 A/B 评测（见"评测工具"） |

## 配置

见 `lua/setup/deepseek.lua`（全量注释版）。要点与默认值：

| 键 | 默认 | 说明 |
| --- | --- | --- |
| `end_point` | `https://api.deepseek.com/beta/completions` | FIM 只在 `beta` 路径下 |
| `model` | `deepseek-flash` | 也可用 `deepseek-v4-pro` |
| `key_file` | `~/.vim/local/deepseek.key` | 权限 600 |
| `filetypes` | 与 `setup/copilot.lua` 同一份白名单 | 切换 `VIM_AI` 不改变生效范围 |
| `debounce` / `throttle` | 300 / 800 ms | 打字停顿后触发；节流限制请求频率 |
| `timeout` | 8000 ms | curl `--max-time` |
| `max_tokens` / `temperature` | 128 / 0 | 见"已知问题：temperature 不确定性" |
| `max_lines` / `min_prompt_chars` | 10 / 10 | 补全行数上限；光标前太短就不请求 |
| `context.total_tokens` | 8000 | 1 token ≈ 3.5 字符（不做真分词） |
| `context.prefix_ratio` | 0.70 | prefix : suffix = 70 : 30 |
| `context.head_chars` | 1000 | 文件超预算时保留的文件头 |
| `cross_file.*` | 见下 | 实验特性 |

## 工作原理

### 触发与状态机（`init.lua`）

```text
InsertEnter/CursorMovedI/TextChangedI/CompleteChanged
   └─ schedule() ──守卫(enabled/filetype/buftype/mode/pumvisible) ──> debounce 300ms ──> fire()
                                                                      throttle 800ms
fire(): context.build() → api.request() → api.filter() → render.show()
```

- **粘性建议（sticky）**：已显示的建议在你继续输入时按"已输入前缀"裁剪，而不是立刻消失。
  API 固有延迟约 1.1s（实测与 prompt 大小无关），粘性建议是掩盖延迟、避免闪烁的关键。
  改动触发逻辑时不要破坏它。
- **取消**：新请求发出前 kill 旧 curl；回调里核对 `{bufnr, changedtick, row, col}`，
  过期结果直接丢弃。
- **`nvim_get_mode()` 陷阱**：`InsertEnter` 期间它仍报 `n`，所以所有插入模式回调都包一层
  `vim.schedule()`（否则 `schedule()` 会直接 bail）。
- `pumvisible()` 是硬性互斥：补全菜单弹出时不请求、不显示。

### 上下文装配（`context.lua`）

```text
# Path: <相对项目根的路径>        ← 无文件名时退化为 # Language: python
<文件头 ~1000 字符>               ← 仅当文件超出预算时
[cross-file 块]                   ← 见下，可选
# ... (rest of file omitted)      ← 只要跳过过任何内容就必须有这个标记
<光标前代码（= prompt 结尾）>
```

`suffix` = 光标后代码（占 30% 预算）。关键约束：

- **只有光标前代码是"紧邻上文"**，文件头/cross-file 块必须用省略标记隔开，否则模型会把它们
  当成当前文件的续写；
- 截断按**行边界**，不会切半行；
- CRLF 由 nvim 的 `fileformat` 处理，buffer 内容里不含 `\r`。

### 请求（`api.lua`）

```http
POST https://api.deepseek.com/beta/completions
Authorization: Bearer <key>     ← 通过 0600 的 curl -K 配置文件传入，不出现在 ps
Content-Type: application/json

{"model":"deepseek-flash","prompt":"...","suffix":"...","max_tokens":128,
 "temperature":0,"stream":false}
```

- body 走 stdin（`-d @-`），所以 key 与代码内容都不进 argv；
- `curl -sS -w '\n%{http_code}'`：最后一行是状态码，用来区分"网络失败"与"HTTP 错误"；
- **失败不重试**（成本控制），错误只记录在 `state.last_error`；
- 非流式：实测服务端会把首包缓冲到 ~1.18s，流式只省 <150ms，不值得那 100+ 行 SSE 代码。

### 过滤链（`api.filter`）

| 阶段 | 作用 |
| --- | --- |
| `normalize` | CRLF/`\0` 归一 |
| `trim_suffix_overlap` | **FIM 模型会复述光标后内容，必须裁剪**，否则补全会重复 |
| `trim_prefix_duplicate` | 模型偶尔回显 prompt 尾部（≥12 字符重叠），裁掉 |
| `trim_trailing_ws` | 去尾部空白 |
| `dropped-empty` / `dropped-repetitive` | 空结果；同一行重复 ≥3 次判为退化输出 |
| `truncate-lines` | 超过 `max_lines` 截断 |

第 4 个参数 `trace` 是可选的：传入后每一步都会留下 `{name, text}` 快照，
用来回答"这次补全为什么是空的"（见"空补全分析"）。运行时零开销。

### 渲染（`render.lua`）

- extmark `virt_text` + `virt_text_pos='overlay'`，首行会拼接"本行剩余文本 + 填充空格"，
  保证后面的真实字符被虚文本覆盖（纯插入、不删字符）；
- 多行建议用 `virt_lines`；当光标不在行尾（后面还有内容）时，多行会被截成单行，
  避免虚文本与真实文本错位；
- 高亮复用 `CopilotSuggestion`（颜色由 `plugin/copilot_color.vim` 统一设置，紫色 `#9933ff`）。

### 接受

`<C-J>` 不是简单地"插入文本"，而是让映射返回一个键序列，用**表达式寄存器**插入：

```text
<C-R><C-R>=v:lua.require("deepseek").queued_text()<CR>   ← 单行
<C-R><C-O>=...<CR>                                       ← 多行（<C-O> 避免 autoindent 二次缩进）
```

这样多行建议的缩进原样落盘（不被 `autoindent` 破坏），且整次接受**只占一次 undo**。
按词/按行接受走同一条路径，只是 `begin_accept(mode)` 决定 queue 内容的长度。

### 统计

`api.stats` 累计请求数/失败数/prompt/completion/缓存 token；`:DeepSeek status` 显示最近一次
请求的耗时与 token 分解（含 `prompt_cache_hit_tokens`），`:DeepSeek stats` 显示会话累计。

## 跨文件上下文（`cross_file.lua`）

把当前 buffer **直接 import 的本地文件**摘要成签名列表，附着在 prompt 的稳定区。

```text
# Path: src/report.py
"""..."""
from .config import read_config
# From: src/config.py
class Config:
    timeout: int
    def merge(self, other: Config) -> Config: ...
def read_config(path: str) -> dict: ...
# ... (rest of file omitted)
    def flush(self):
        return read_config(
```

### 路径解析

| 语言 | 规则 |
| --- | --- |
| Python | `from .a import b` 按点数上溯（`rest` 为空时落到 `__init__.py`）；`import a.b` 在 `[项目根, 项目根/src, 当前目录]` 下找 `a/b.py`、`a/b/__init__.py` |
| Lua | `require('a.b')` 在**从当前目录到项目根的每个祖先目录**及其 `lua/` 子目录下找 `a/b.lua`、`a/b/init.lua`（兼容 `<pkg>/lua/` 这种 nvim runtimepath 布局） |
| Rust | `crate::` → `<root>/src`；`super::` → 父目录；`self::` → 同目录；`mod x;` → `x.rs` / `x/mod.rs` |
| TS/JS | 只解析相对路径（`.ts/.tsx/.js/.jsx` 及 `index.*`）；裸 specifier 一律跳过（`node_modules` 无价值且会挤爆预算） |

只做**一跳**（直接 import，不做传递闭包），因此不存在环。

### 摘要内容与可见性

用 `vim.treesitter.get_string_parser()` 解析**字符串**（不创建 buffer，不触发 FileType/LSP attach），
缺失 parser 时退化为正则。只保留"调用别人需要知道"的东西：

- Python：顶层与类内一级的 `def`/`class` 签名（截到 `:`）+ **类级注解**（dataclass 字段，
  那才是构造函数的 API）+ 装饰器（`@property`/`@dataclass`）；单下划线私有名跳过，`__init__` 等 dunder 保留。
- Lua：`function M.x(...)` / `M.x = function(...)`；`local function` 默认只保留**确实出现在
  `return` 表里**的（`cross_file.lua` 会静态分析返回值：`return { init = init }`、`local M = {}` + `M.x = y`）。
- Rust：`pub fn/struct/enum/trait/impl/type`，`impl` 内要求 `pub`（trait 内除外）；`mod tests` 之类
  的嵌套模块不会进来。
- TS/JS：只保留 `export` 的声明（方法沿容器向上找 `export_statement`）。

函数体永远不发送；单行定义（`pub enum Kind { A, B }`）保留原文，因为成员本身就是 API。

### 安全边界

- realpath 必须落在**项目根内**；
- 跳过 `node_modules` / `.venv` / `site-packages` / `vendor` / `target` / `dist` / `build` / `__pycache__` …；
- 跳过 `.env*` / `*.key` / `*.pem` / `*.min.js` / `*secret*` / `id_rsa*` / `*credential*`；
- 每个文件最多读 `read_lines` 行、最多保留 `max_lines` 行 / `max_chars` 字符，最多 `max_files` 个文件；
- **开启时会把被引用文件的签名发给 DeepSeek API**；`cross_file.enabled = false` 关闭。

### 缓存与预取

摘要按 buffer 缓存：键 = **import 段文本**（前 200 行），并用被引用文件的 `mtime`/`size` 判失效。

- 实测：命中 **0.064ms** vs 重算 **7.98ms**（4 个文件）；
- `InsertEnter` 时 `vim.schedule` 预取一次，把 ~8ms 移出请求路径；
- 摘要只依赖 (buffer 文本 × 被引用文件内容)，**不依赖光标** —— 这是让 DeepSeek 前缀缓存
  继续命中的前提（缓存命中价 $0.006/M vs 未命中 $0.3/M，差 50 倍）。

### 实测结果（A/B，真实 API）

两次独立运行（25 个文件 = Gomoku + HBKit + 本仓库；`base` 与 `cross` 在同一光标点配对）：

| 运行 | 请求 | 配对样本 | 目标桶 first | 目标桶 lead1 | 目标桶 sim | 目标桶 simm | 配对 simm (p) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| A | 120 | 54 | 4/26 → 4/26 | 7/26 → 7/26 | 0.246 → 0.169 | 0.254 → 0.190 | 14 好 / 19 差 / 21 平 (0.49) |
| B | 90 | 40 | 0/18 → 2/18 | 3/18 → 5/18 | 0.220 → 0.194 | 0.220 → 0.165 | 10 / 13 / 17 (0.68) |

- 离散指标（first/lead1）两次符号相反 → 噪声；平滑指标（sim/simm）两次都小幅变差但不显著。
- 成本确定为正：prompt token/请求 **+21%~31%**；缓存命中率（82%~84%）与延迟（~1000ms）不变。
- 结论：**无可靠收益**。`enabled = true` 只是为了手动体验，改 `false` 回到实测基线。

### 空补全分析（排除"过滤器误杀"）

90 条记录里 10 条为空，base 4 / cross 6（基本对称）。逐级 trace 显示死因只有两类，都是正确行为：

1. `no-response`（4 次）：`choices=1, finish_reason=stop` 且 text 为空——模型自己选择不插入；
2. `trim_suffix_overlap` / `trim_prefix_duplicate`（6 次）：模型回显了光标后的文本或 prompt 尾部，
   被过滤器整体剪掉（明细里 `raw` 与 `suffix` 逐字符相同）。

所以 sim 的差距只能归因于模型输出本身，与过滤器/传输无关。

## 评测工具（`eval.lua`）

用真实文件、真实光标点做 A/B：以"文件里光标后**真实存在**的文本"作为标准答案。

```vim
:DeepSeek eval 6          " 当前文件，call_site 模式，每文件 6 个样本
:DeepSeek eval 6 all      " 加上 line_end 模式
```

- **采样模式**：`call_site`（光标落在"调用被 import 函数"的 `(` 之后，GT = 本行剩余部分）、
  `line_end`（光标在代码行尾，GT = 下一非空行）。只有名字真的出现在**已解析摘要**里的调用
  才算 cross-file 样本，避免把 `tk.Label(` 这种第三方调用误判成"跨文件"。
- **指标**：`first`（首个标识符命中）、`norm`（去空白整行一致）、`lead1`（首 token 命中）、
  `sim`/`simm`（token 级编辑相似度，单行 / 容忍多行）、`F1`/`F1m`；
- **配对符号检验 p 值**：两个变体回答同一光标点，只看差异；先看 p 再看均值（n<20 时基本不显著）；
- 报告还给出每个空补全的**死因**（含 `finish_reason`、`choices`、raw/suffix 对照）；
- 截断按**整样本**（不会只发 base 或只发 cross），否则配对统计被污染。

`eval.compare` / `eval.sign_test` 已导出，便于写回归测试或手工打分。

## 开发与测试

- 语法/加载：`nvim --headless -n -u NONE -c "lua local ok,e=pcall(loadfile,'<file>'); print(ok,e)" -c q`
- 端到端：用 `nvim --headless --listen <sock>` + `--remote-expr` 驱动真实插入模式
  （`nvim_feedkeys(..., 'm', false)` 才会走映射），`-u NONE` 时记得手动 `vim.bo.filetype`；
- 想离线验证渲染/接受，可以起一个返回固定 JSON 的本地 HTTP 假端点，把 `end_point` 指过去；
- **两个坑**：① headless 下 `print('')` 连换行都不输出、连续 `print` 会被粘成一行（评测器改用
  `io.stdout:write`）；② 无看门狗的长跑脚本一旦中途报错就不会退出，用 `vim.defer_fn(... qa!)` 兜底。

## 未来优化点

### A. 上下文与 prompt

| # | 想法 | 预期收益 | 成本 | 备注 |
| --- | --- | --- | --- | --- |
| A1 | 文件 outline（顶层符号清单）替代"只截 1000 字符的文件头" | 中高（长文件里文件头到后面就没用了） | 低（复用 cross_file 的摘要器） | 与 A2 一起做 |
| A2 | 预算四桶化（对齐 Copilot 的 prefix 35 / suffix 15 / stable 35 / volatile 15） | 中（现在 prefix 独占 70%，8000 token 常常花不完） | 低（改 ratio 计算） | 先测 `prefix_ratio` 敏感度 |
| A3 | 当前作用域感知：光标深嵌时把最外层函数签名重贴回 volatile 区最前 | 中（仅超大函数有用） | 中（treesitter 查询） | 不能紧邻光标 |
| A4 | RecentEdits（Copilot 权重最高的组件 0.99）：最近一次编辑的新内容 | 场景窄但可能明显（重命名/重构扩散） | 中 | 注入形式最脏，需 A/B |
| A5 | 注释/字符串感知的 `max_lines`（注释里不要给 10 行） | 中（减少垃圾多行补全） | 低 | 不进 prompt，只调参数 |
| A6 | 跨文件"按需裁剪"：只放光标附近真正用到的名字的签名 | 未知 | 中 | **会破坏缓存稳定性**，需要迟滞（只在 `BufWritePost` 重排） |
| A7 | 分隔标记 A/B：`# From:` vs DeepSeek-Coder repo-level 风格（`<file_sep>`+路径） | 未知 | 低 | `cross_file.separate` 已是同类的布局开关 |
| A8 | 放置位置 A/B：摘要紧邻光标 vs 现在隔一个省略标记 | 未知 | 低 | `context.build(stable_extra)` 只需换拼装顺序 |

### B. 触发与延迟

| # | 想法 | 预期收益 | 成本 | 备注 |
| --- | --- | --- | --- | --- |
| B1 | **推测性请求**：在 debounce 前用上一次上下文先发一发，命中就省一次往返 | 高（直接砍掉 ~1.1s 中的等待） | 中高（要管理更多在途请求/成本） | Copilot 有 `isSpeculative` |
| B2 | 空闲预取：`InsertEnter` 后停顿即预发一轮 | 中 | 中 | 与 B1 共用基础设施 |
| B3 | 自适应 debounce（按打字速度/接受率） | 中 | 低 | 先加统计再调 |
| B4 | 前缀 LRU：把"行尾"这类高频前缀的结果缓存复用 | 低 | 中 | 只对重复场景有用 |
| B5 | 多候选 `n>1` + 打分选择 | 未知 | 中（成本×n） | 需先确认接口是否支持 `n` |
| B6 | 重新评估流式 | 低（实测 <150ms） | 中 | 服务端行为变了才值得 |

### C. 质量与后处理

| # | 想法 | 预期收益 | 成本 | 备注 |
| --- | --- | --- | --- | --- |
| C1 | **语法校验过滤**：把补全插进影子 buffer，用 treesitter 看 `ERROR` 节点是否增加 | 高（比启发式靠谱） | 中 | 也可用于"缩进与上下文不一致就重排" |
| C2 | 缩进/括号配平修正 | 中 | 中 | 现在完全信任模型给的缩进 |
| C3 | 更强的重复检测（现在只有"同一行 ≥3 次"） | 中 | 低 | 可借鉴 Copilot 的 n-gram `isRepetitive` |
| C4 | 采纳率感知的重排/阈值 | 未知 | 中 | 依赖 D3 |

### D. 工程与可观测性

| # | 想法 | 预期收益 | 成本 | 备注 |
| --- | --- | --- | --- | --- |
| D1 | 请求日志 ring buffer（`:DeepSeek log`：prompt/raw/filtered/耗时） | 高（排查"这次补得怪"） | 低 | trace 目前只对空结果保留 |
| D2 | **回放 fixture**：把评测用过的请求/响应存盘，回归测试不再花钱 | 高 | 低 | 现在每次评测都真调 API |
| D3 | 会话级接受率统计（接受/忽略/按词/按行） | 高（用真实使用判断改动，而非离线指标） | 低 | 最该先做的一个 |
| D4 | 摘要缓存持久化（现在只保留最后一个 buffer 的结果） | 低 | 低 | 大项目/频繁切文件时有用 |
| D5 | `:DeepSeek status` 增加"上一次请求各阶段耗时" | 低 | 低 | 需要 `api` 打点 |

### E. 明确不做（附理由）

- **不做全仓库 embedding / 相似文件检索**：违背"零依赖"，成本与收益都不确定；
- **不做多候选循环**（`<M-]>`/`<M-[>` 这类）：`<M-\>` 换一个 + temperature 轮换已覆盖，
  且 `<M-[>` 在终端里是 CSI 前缀，不可靠；
- **不做 LSP inline completion 封装**：nvim 0.12 的 `vim.lsp.inline_completion` 只管画虚文本，
  触发/预算/过滤/接受都还得自己写，包一层反而更绕；
- **不做流式**（见 B6）；
- **不做成本估算/价格表**：模型价格会变，`:DeepSeek stats` 给 token 数就够。

## 已知问题

- **延迟地板 ~1.1s**：服务端会把首包缓冲到约 1.18s，与 prompt 大小无关（缓存命中也一样）。
  粘性建议是主要缓解手段；若哪天服务端改善，触发策略可以整体放松。
- **`temperature=0` 不保证确定性**：两次相同请求可能返回不同文本，所以"重复结果自动换
  temperature 重试"（`<M-\>`）是必要的。
- **FIM 输出硬上限 4K token**；`max_tokens` 默认 128，够一次函数体。
- **cross-file 实测无收益**（见上），默认开启只是方便手动体验。
- **`<M-C-Right>` 在部分终端不可上报**，不生效时用 `:DeepSeek refresh` 或改键位。

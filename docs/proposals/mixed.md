# Mixed Proposals (临时草稿)

聚集多个未实施的提案 / 想法，方便对话之间持久化。条目稳定后再决定拆成独立 design doc 或并入 ARCHITECTURE.md。

---

## 总览

| # | 标题 | 分类 | 状态 | 优先级 | 触发频率 |
|---|---|---|---|---|---|
| 1 | tmux-bridge message 引号被吃 | A 通信 | 方案 A/B 暂存为 fallback；新主线 Tier 1 (paste-buffer)，见 PLAN | **P0** | 高，反复触发 |
| 2 | PreToolUse hook 给 tmux-bridge 放行 | B 权限 | Tier 1 后预期消失（命令体不再含 $(...)），待 Tier 1 验证后再评估 | P1 | 高 |
| 3 | PreToolUse hook 给只读命令 simple_expansion 放行 | B 权限 | 待决策 | P1 | 中 |
| 4 | tmux copy mode 软折行 / mouse bypass | C 终端 | 调研完成 | P2 | 中 |
| 5 | Zed 终端 link 点击需 shift+cmd | C 终端 | 待决策 | P3 | 低 |

### 分类

- **A 通信**：跨 pane / shell 解析阶段的消息内容传递问题
- **B 权限**：Claude Code permission matcher 对 shell expansion 一刀切降级，hook 兜底放行
- **C 终端**：终端 app / tmux 层交互体验

### 优先级判定

- **P0**：反复触发，软约束失败已验证 → 需硬性兜底
- **P1**：高频体验痛点，方案明确，等落地决策
- **P2**：零成本可加，适配性广
- **P3**：偏个人配置 / 终端层固有限制，文档化即可

---

## 1. tmux-bridge message 引号被吃

**分类**：A 通信。**状态**：方案 A 已落地（skill 文档约束单引号，仅适用单行），方案 B（多行落盘传递）待推进。**优先级 P0**。

### 2026-04-20 重新评估（新主线：Tier 1 paste-buffer）

参考 `docs/research/stably-orca-compare.md` 对 stablyai/orca 的架构对比（第 4 条启发：减少把结构化控制塞入 shell 命令参数），本提案方向重定向：

- **新主线**：tmux `load-buffer + paste-buffer` 通信改造（Tier 1），完全绕开 bash 解析阶段。详见 `PLAN.md` 中「通信层重构（Tier 1：paste-buffer）」章节
- **方案 A（单引号约束）**：保留为 fallback，仅作为单行短消息的轻量路径
- **方案 B（落盘 + 路径传递）**：保留为 debug / 跨 worker 复用场景的 fallback，不再作为多行消息的默认路径
- 原 P0 优先级保留，但实施路径切换到 Tier 1

### 现象

worker 通过 `tmux-bridge message` 给 lead 发评估时，消息体里包含 `` `auth:session:<token>` `` 这种 Markdown 行内代码片段，lead 收到的内容里反引号片段整段缺失，关键 key 名丢失，导致评估信息失真。

**复现记录**：

- 2026-04-18：worker 评估 auth 改造方案时首次发现，含 `` `auth:session:<token>` ``、`xdclaw_session`、`xdclaw.auth` 等多个 key 名缺失
- 2026-04-19：worker 发文档大纲预案时再次触发，主体内容到达但「有几处被吃掉」，worker 自己已意识到并主动澄清
- 2026-04-20：worker 长汇报场景再次触发，第一条带反引号被吃；worker 立即用单引号重发，结果消息体里写的 `\n` 在单引号下成了**字面 2 字符**，lead 收到的是断行被破坏的一长段。**单引号方案的副作用首次暴露**

**结论**：方案 A（软约束）经过 3 次实战验证，不可靠。worker 在 markdown 习惯下仍会写反引号；即使按规则用单引号，多行汇报场景下又踩 `\n` 字面量陷阱。

### 根因

`tmux-bridge` 自身没问题——`/Users/fmfsaisai/.smux/bin/tmux-bridge:250` 用 `tmx send-keys -t "$target" -l -- "${header} $2"`，`-l --` 是字面量模式。

问题在 **调用侧的 bash 解析阶段**：worker 按习惯写

```bash
tmux-bridge message "$ORCA_PEER" "...`auth:session:<token>`..."
```

整条 message 体被双引号包裹，bash 在调用 tmux-bridge **之前** 就把反引号里的内容当命令替换执行，结果替换为空。tmux-bridge 拿到的 `$2` 已经是缺字版本。

最小复现：

```bash
bash -lc 'printf "<%s>\n" "left `auth:session:<token>` right"'
# command substitution syntax error → 输出 "<left  right>"
```

风险字符范围：

- 必规避：`` ` ``、`$(...)`、`$var` —— 双引号内一律解释
- 反斜杠 `\` 参与转义，需注意
- `!`：仅在开启 histexpand 的 **交互 shell** 风险，当前 worker（codex / claude code 的非交互 bash 路径）不触发

### 方案

#### 方案 A（已落地）：skill 提示词约束 message 体用单引号

`skills/orca/SKILL.md` 通信规则：消息体用单引号 `'...'`，target 部分仍可用 `"$ORCA_PEER"`。

```bash
tmux-bridge message "$ORCA_PEER" '消息体可以放 `反引号` 和 $变量'
```

**已暴露副作用**：
1. 消息体含单引号字符需手动 `'\''` 转义，写起来很丑
2. **`\n` 不展开成换行**，是字面 2 字符 → 多行汇报破相（2026-04-20 实测）
3. 软约束不可靠，依赖 worker 习惯

#### 方案 B（推荐落地）：消息体多行 → 落盘传递（复用 PR #8 handoff 模式）

PR #8 已验证 dispatch 方向的 handoff：lead 写 plan 到 `/tmp/orca-handoff-<slug>-<ts>.md`，message 体只放路径。本方案对称扩展到 worker → lead 的汇报方向：

```bash
msg_path="/tmp/orca-msg-<slug>-$(date +%s).md"
cat > "$msg_path" <<'EOF'
长汇报内容，可含 `反引号`、$VAR、'单引号'、真换行
EOF
tmux-bridge message "$ORCA_PEER" "Read $msg_path"
```

新规则：
- **单行短消息** → 单引号 `'...'`，沿用方案 A
- **多行 / 含 markdown 代码片段 / 含 shell 元字符** → 落盘 + 路径

收益（相比原 heredoc 方案）：
- 不改 tmux-bridge
- 多 worker 广播天然复用同一文件路径
- `&&` 链兼容（落盘是独立命令，message 仍单行）
- 不需要嵌套 heredoc 分隔符约定
- 复用 PR #8 已验证的 CC matcher 行为，无未知风险
- skill 文档改动最小：扩展现有 handoff 规则到汇报方向

代价：worker / lead 多一步 `cat > ... <<EOF`，临时文件复用 PR #8 sweep 机制（`/tmp` 自动清理）。

### 待办（P0）

1. `skills/orca/SKILL.md` 通信规则补「多行汇报必须落盘 + 路径传递」，规则与 PR #8 dispatch handoff 对称
2. 复用 PR #8 的 `/tmp` 清理机制，sweep pattern 加 `orca-msg-*`
3. 给 worker 一次广播：新规则生效

### 决策点

1. 文件路径前缀：`orca-msg-` （汇报方向）vs PR #8 的 `orca-handoff-` （dispatch 方向）。倾向**区分**——便于排查方向，sweep 模式都覆盖
2. 单行 vs 多行的判定：留给 worker 自觉，还是设字符数阈值（如 >300 字符）？倾向**自觉**——含反引号 / `$` / 多行就落盘，规则简单

### 关联

- 与 PR #8 handoff 模式同源，文档可交叉引用（dispatch 方向 + 汇报方向 = 完整对称）
- 与 #2 / #3 互补：本条解决"消息内容传递"，#2 / #3 解决"hook 放行"
- 方案 A 仍适用于单行短消息，B 是多行场景的必选项

---

## 2. PreToolUse hook 给 tmux-bridge 自动放行

**分类**：B 权限。**状态**：待决策（倾向落地）。**优先级 P1**。

### Tier 1 影响（待 Tier 1 验证后再评估）

Tier 1 (paste-buffer) 完成后，`tmux-bridge` 命令体不再包含 `$(...)` 命令替换（内容通过 buffer 而非命令参数传递）。预期效果：

- Claude Code permission matcher 不再因 `$(...)` 触发降级 → 本提案的 ask-prompt 现象大概率自动消失
- 若验证后确实消失，本提案可降级为 P3 或并入 #3（共同根因仍是 matcher 对 shell expansion 的保守降级）
- 若 Tier 1 后仍有残留场景，再评估是否单独落地 PreToolUse hook

### 现象

Claude Code 里把 `Bash(tmux-bridge *)` 加进 settings.json allow 列表后，下面这种命令仍然每次弹权限询问：

```bash
tmux-bridge read $ORCA_PEER 5 && tmux-bridge message $ORCA_PEER "$(cat <<'EOF'
多行内容
EOF
)"
```

### 根因

**Claude Code 的 permission matcher 对含 `$(...)` 的整条命令保守降级到询问** —— 子 shell 输出动态、无法静态判断会运行什么，所以无论外层 `tmux-bridge *` 是否在 allow 列表都会问。`&&` 链和 `$ORCA_PEER` 变量本身不影响匹配，只有命令替换 `$(...)` 是触发器。

### 排除的方案

| 方案 | 排除理由 |
|---|---|
| 改 Claude Code permission matcher 不对 `$(...)` 降级 | 不在我们控制范围 |
| tmux-bridge 加 `--stdin` (proposal #1B) | 仍要 AI 主动选这种调用形式，没解决"约束 AI"的根本问题 |
| 包装脚本 / 重命名 | matcher 按整条命令文本看，加包装不影响 `$(...)` 判定 |
| 改 skill 提示词约束 AI 用单引号 (proposal #1A) | 软约束、概率性，AI 写命令的姿势难以保证 |

### 方案

`~/.claude/settings.json` PreToolUse hook，命令以 `tmux-bridge` 开头就直接放行：

```json
"PreToolUse": [
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "jq -r '.tool_input.command' | grep -qE '^[[:space:]]*tmux-bridge[[:space:]]' && echo '{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}' || exit 0"
      }
    ]
  }
]
```

逻辑：命令以 `tmux-bridge` 开头 → harness 层强制 allow；否则不干预走原本 allow/deny。`deny` 列表（如 `rm -rf *`）优先级高于 hook approve，安全红线不破。

### 决策点

1. **是否纳入 orca install.sh 自动注册？**
   - 倾向是。orca 已经在 `install.sh:108-157` 管理 SessionStart hook，`install_or_update_hook` 在 PR #8 follow-up 里会通用化（P0-3 deferred），届时复用即可
   - 边界：CC 专属（用 `permissionDecision` 格式），但 orca 现有 hook 也都是 CC 专属——"model-agnostic"在 orca 语境里指**编排逻辑**，不含 harness 集成层
2. **装载作用域：全局 `~/.claude/settings.json`**（已定）
   - 项目级方案被否：worker 启动时 cwd 是 worktree 或别的项目，CC 按 cwd 向上查找 settings，跨项目派 worker 时 orca 项目级 settings 找不到
   - over-reach 风险用 install.sh 显式确认提示兜底（"将修改 ~/.claude/settings.json，确认？"）
3. **匹配范围**：只放 `tmux-bridge` 还是把 `orca`、`orca-worktree` 也加进去？倾向只放 `tmux-bridge` —— 其他命令副作用面更大，少弹一次询问换不来风险

### 待办

1. P0-3 通用化 `install_or_update_hook` 后接入 PreToolUse hook 注册
2. `install.sh` 安装 `hooks/allow-tmux-bridge.sh` 脚本（jq + grep 那段）
3. **前置验证**（落地前必做）：
   - `command -v jq >/dev/null` 检测 jq 依赖，缺失则报错并提示安装方式
   - 用 `rm -rf /tmp/orca-deny-test` 实测 CC `deny` 列表与 hook approve 的优先级，确认 deny 优先（文档说法，未实测）

### 关联

- 与 #1 互补：#1 减少触发概率（消息内容侧），#2 兜底覆盖 AI 没遵守约束或 heredoc 必须场景
- 与 #3 同类：根因同（matcher 对 shell expansion 降级）、方案同（PreToolUse force allow），脚本可合并参数化

---

## 3. PreToolUse hook 给只读命令的 simple_expansion 放行

**分类**：B 权限。**状态**：待决策。**优先级 P1**。

### 现象

带 `$VAR` 变量展开的纯只读命令仍每次弹询问，即使命令本身已在 allow 列表：

```bash
echo "ROLE=$ORCA_ROLE PEER=$ORCA_PEER WORKERS=$ORCA_WORKERS"
```

`~/.claude/settings.json` 已加 `Bash(echo:*)`，弹窗仍出现，提示信息：`Contains simple_expansion`。

### 根因

Claude Code permission matcher 对含 shell expansion 的命令统一降级到 ask，触发器包括：

- `$VAR` / `${VAR}` 变量展开（本条主因）
- `$(...)` 命令替换（proposal #2 主因）
- 反引号 `` `...` ``

设计意图是防 `echo $(rm -rf /)` 之类绕过 allowlist 的注入。代价是纯只读命令也被一刀切。

### 方案

复用 proposal #2 的 PreToolUse hook 路子，把匹配集合从单一 `tmux-bridge` 扩成可配前缀列表：

```bash
^[[:space:]]*(echo|env|printf)[[:space:]]
```

只覆盖明确无副作用的命令。**不放** `cat` / `ls` —— 路径含 `$HOME` 等仍可能触达敏感目录，保留人类确认有意义。

### 决策点

1. 放行集合范围：`echo` / `env` / `printf` 三个够不够？要不要加 `pwd`、`date`？倾向先三个，按需扩
2. 与 #2 共用脚本还是独立？倾向共用，参数化前缀列表
3. 装载作用域：跟随 #2，**全局 `~/.claude/settings.json`** + install.sh 显式确认
4. 是否纳入 install.sh 自动注册（同 #2）？依赖 #2 决策

### 待办

1. 手动在 `~/.claude/settings.json` 试装 hook 验证有效
2. 确认有效后合并 #2 的 hook 脚本基础设施（共用 jq 依赖检测 + deny 优先级实测）

### 关联

- 与 #2 同类：根因 + 方案 + 脚本基础设施可共享。#2 聚焦 `tmux-bridge` + `$(...)` 命令替换；#3 聚焦只读命令 + `$VAR` 变量展开

---

## 4. tmux copy mode 软折行 / mouse bypass

**分类**：C 终端。**状态**：调研完成，待决策落地兜底方案。**优先级 P2**。

### 现象

orca 内 tmux copy mode 复制出来的文本被预期外的换行切断，无法获得"原生终端复制"的效果。

### 根因

tmux pane 内部按"终端宽度"存储字符网格，程序输出超过宽度时 tmux 自己折行，把一段长文本拆成多行存进 buffer。copy mode 选择 buffer 内容，**软折行**（terminal wrap）和**硬换行**（程序输出 `\n`）出来都是 `\n`，无法区分。

### tmux mouse 模式的硬限制

之前讨论中曾设想"mouse 改成只能滚动，不触发 copy mode" —— 这条路走不通。

tmux mouse 模式在协议层是**二元的**：`set -g mouse on` 就让终端订阅所有 mouse event 给 tmux。unbind 某个 binding（如 `unbind -n MouseDrag1Pane`）只是让 tmux 收到事件后 no-op，**事件仍被 tmux 吃掉，不会穿透到终端原生选择**。所以"部分 mouse 能力"在 tmux 配置层无法实现。

### 终端层 bypass 调研

不同终端 bypass key 不同：

| 终端 | Bypass key | 备注 |
|---|---|---|
| iTerm2 | ⌥ Option | 默认 |
| **Ghostty** | **Shift** | `mouse-shift-capture = false`（默认） |
| **Zed terminal** | Cmd（实测）/ Shift（理论） | 基于 `alacritty_terminal` |
| WezTerm | Shift | |
| macOS Terminal.app | Fn | |
| Kitty | Shift | `terminal_select_modifiers shift` |

### 各终端实际表现（用户实测）

- **Ghostty + Shift+drag**：bypass 生效，**但跨 pane 选中** —— 终端不知道 pane 存在，把整个窗口当一块字符网格。架构必然，无解
- **Zed + Shift**：无反应。**Cmd 有反应但仍带换行** —— Zed 用的 `alacritty_terminal` 不追踪 wrap 状态，bypass 也救不了软折行问题
- iTerm2 / macOS Terminal / Ghostty 都追踪 wrap 状态，原生选择是干净一行；alacritty 系不追踪

### 可行兜底

**方案 A：Ghostty + zoom + Shift+drag**

要复制时 `prefix+z` zoom 当前 pane 全屏 → Shift+drag → `prefix+z` 取消 zoom。zoom 状态下 window 只剩一个 pane，跨不了。两步操作但比 copy mode 换行问题省心。

**方案 B（推荐落地到 orca）：`prefix+P` 一键 capture-pane 到剪贴板**

在 `start.sh` 里追加 binding：

```bash
$TMUX_CMD set-option -t "$SESSION" -g \
  bind-key P run-shell "tmux capture-pane -J -p -S -3000 | pbcopy && tmux display 'pane copied'"
```

`-J` 让 tmux 把 wrapped lines join 回去 —— 这是 tmux 自己的"知道 wrap"接口，比 copy mode 的"二进制 buffer dump"高级。失去交互式选区，但作为"AI 给的长输出我要整段"的 fallback 很顺手。Ghostty / Zed / 任何终端都能用。

**Zed 用户专属现实**：Zed 的内置终端因为 alacritty_terminal 不追踪 wrap，**没法做到完美原生复制**。重要复制操作建议搬到 Ghostty 或 iTerm2 做；Zed 终端用来跑 dev server / 看日志够了。

### 决策点

1. **是否把方案 B（`bind P`）加到 `start.sh`？** 倾向加 —— 零成本，普适，不影响现有交互
2. **是否文档化"Zed 终端不适合 orca host"？** 倾向加一句到 README 或 docs，避免用户重复踩坑

### 待办

1. `start.sh` 追加 `bind-key P` capture-pane 配置
2. （可选）docs 加"推荐终端"段，标注 Ghostty / iTerm2 ✅，Zed 终端 ⚠️ 软折行无解
3. （可选）`pbcopy` 是 macOS 专属，跨平台版本用 `command -v pbcopy >/dev/null && pbcopy || (command -v wl-copy >/dev/null && wl-copy || xclip -selection clipboard)` 之类

### 关联

- 与 #5 同类（C 终端）：都是 Zed 终端的特殊行为，可在「推荐终端」文档段统一说明

---

## 5. Zed 终端 link 点击需 shift+cmd

**分类**：C 终端。**状态**：待决策（仅文档化）。**优先级 P3**。

### 现象

Zed 内置终端里，AI 输出的 URL / 文件路径链接需要 **shift+cmd+click** 才能打开。

### 方案

**仅文档化**，不改 Zed 配置：

- 在 docs「推荐终端」段（与 #4 决策 2 合并）注明：Zed 终端 link 点击为 **shift+cmd+click**
- 不建议为单一终端调 keymap —— 用户偏好差异大，文档说明即可

### 决策点

1. 是否同时给出 Zed keymap 自定义示例？倾向**不给** —— 容易过度配置且与 Zed 升级冲突
2. 与 #4 的「推荐终端」段合并写还是分开？倾向合并，统一一节列各终端注意点

### 待办

1. （与 #4 决策 2 一起）docs「推荐终端」段加 Zed link 点击说明

### 关联

- 与 #4 同类（C 终端）：Zed 终端使用注意事项可统一说明

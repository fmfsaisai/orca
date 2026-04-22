# Orca UX 问题清单 —— Nick 反馈拆解

> 来源：2026-04-21 与 Nick 的微信对话
> 整理时间：2026-04-22

## 摘要

Nick 是 Orca 的早期用户。他在 2026-04-21 给出了一组连续反馈，最终情绪曲线：
"想试试" → "感觉不好上手" → "突然就不想用了" → "打破幻想了"。

**这是 Orca 当前最严重的产品级 churn 信号**。本文档拆解他的具体反馈，对应到 Orca 的设计问题。

---

## 1. 反馈原文 → 设计问题映射

### 痛点 1：入口反了

> Nick: "感觉不是很好上手，不知道第一步该怎么用"
> Nick: "当我启动 Claude Code 的时候，orca 不会自动 hooks 上吗？还需要我手动执行下 orca?"

**用户期望**：先打开 Agent → Agent 里调用 orca

**Orca 当前**：先 `orca` 命令 → 创建 tmux session → 把 cc/codex 装进 pane

**关键证据**：OMC/OMX 都是后者范式，Nick 明确说"使用姿势我倾向于类似 OMC OMX"。

**对应文件**：
- `start.sh`（创建 tmux session 的入口）
- `install.sh`（安装 hook、skill）
- `skills/orca/SKILL.md`（lead/worker 协议）

---

### 痛点 2：强制 tmux 入侵

> Nick: "但这个入侵就有点严重了吧，能不能实现另说，如果我就是单纯只想启动 cc, 不想装在 tmux 里呢，然后还要解决 tmux 内启动 cc, hook 在再次触发 orca 的嵌套问题"

**用户诉求**：tmux 应该是"任务需要并发时才出现"的能力，不是入口前提

**Orca 当前**：tmux 是必须的，不开 tmux 就用不了 orca

**衍生问题**：嵌套触发——用户在 tmux 里启动 cc，cc 的 hook 又触发 orca 创建新 tmux，套娃

**对应文件**：
- `start.sh`（无条件创建 tmux）
- 任何 `SessionStart` hook 注册的入口

---

### 痛点 3：默认多 pane 太重

> 我（赛赛）："启动 orca app，然后它会自动拉起 1 个 claude 和 2 个 codex?"
> Nick: "nonono，这个太丑了"
> Nick: "我突然就不想用了"
> Nick: "打破幻想了"

**用户诉求**：默认应只有 1 个 pane，开几个 pane 由任务并发决定

> Nick: "默认肯定只能有一个，然后开多少个 tmux pane 得根据任务的并发量去评估"

**Orca 当前**：`start.sh` 起手就建好 lead + N worker pane

**对应文件**：
- `start.sh:??`（pane 创建逻辑，需 worker 确认行号）

---

### 痛点 4：hook 介入要"按需生效"

> Nick: "我觉得是要 hooks 上，但是否生效取决于我是否要让它干过"
> 我："是否要让他干活，可以参考下 OMX OMC 的做法"

**用户诉求**：hook 可以挂上，但默认不激活；只有用户调用 `/orca` skill 才介入

**OMC/OMX 现状**：
- OMC 注册了完整 hook 栈（UserPromptSubmit / SessionStart / PreToolUse / PostToolUse / Stop / SessionEnd 等 11 个事件），但 worker spawn 是按需的（用户显式调用 `/team` 才起 tmux pane）
- OMX 也注册了 5 个 hook 事件（SessionStart / UserPromptSubmit / PreToolUse / PostToolUse / Stop），但任务编排靠 skill 显式调用（`$ultrawork` / `$tdd` / `$plan`）
- 两家本质都是「**全量 hook 注册 + 功能按需激活**」，hook 自身不是"按需"的

**Orca 当前**：hook 一旦装上就持续生效（PreToolUse 等）

**对应文件**：
- `install.sh`（hook 注册）
- `~/.claude/settings.json`（用户侧 hook 配置）

---

### 痛点 5：介入路径

> Nick: "得让工头来介入啊，流水线工人那边不能随便介入的"
> Nick: "偶尔我 codex 窗口出现 rm -rf 还是要等我授权确认的"
> Nick: "大部分时候是托管"
> Nick: "然后，流水线工人有时候我看他明显走偏了，我会直接打断介入，找工头还是延迟有点高"

**用户诉求**：
1. **大部分时候是托管**——Agent 自己跑，用户不干预
2. **危险操作（rm -rf）保留 worker 自身的授权机制**——Codex 内置的确认弹窗不要被绕过
3. **走偏纠正**——理论上应该回 lead pane 让 lead 转发，但**延迟太高**，所以用户实际会跳进 worker pane 直接打字
4. 期望"工头介入"是一等公民路径，但要把延迟做下来

**Orca 当前**：bridge 通信确实有延迟（read 5s + 心跳），用户跳 worker pane 是 workaround

**对应文件**：
- `skills/orca/SKILL.md`（lead/worker 协议、read 周期）
- `tmux-bridge`（通信延迟优化）

---

### 痛点 6：`orca ps` 在 cc 内用不上

> Nick: "Ps 都是在外面用的情况，但里面基本用不上，这也是我想用 Claude 来调用 orca 来做"

**用户诉求**：`orca ps`（多实例多忘关）在 shell 外用得上，但 Agent 内基本用不上

**用户期望**：让 Claude 在 cc 内自己调用 `orca ps` / `orca clean` 自动管理实例

**对应文件**：
- `orca` 主命令（ps、clean 子命令）
- skill 暴露给 cc 调用

---

## 2. 优先级建议

| 痛点 | 严重性 | 修复成本 | 优先级 |
|---|---|---|---|
| 1. 入口反了 | 极高（churn 直接原因） | 高（要重构入口范式） | **P0** |
| 2. 强制 tmux 入侵 | 高（与 1 同源） | 高（同 1） | **P0** |
| 3. 默认多 pane 太重 | 极高（"打破幻想"） | 中（改 start.sh 默认行为） | **P0** |
| 4. hook 按需生效 | 中（解决了 1+2 自然好转） | 中 | **P1** |
| 5. 介入路径 | 中（用户已有 workaround） | 中（bridge 通信优化） | **P1** |
| 6. ps 在 cc 内用 | 低（已有 workaround） | 低（暴露 skill） | **P2** |

---

## 3. 对比 OMC/OMX 的范式落地

| Nick 诉求 | OMC 怎么做 | OMX 怎么做 | Orca 应该怎么改 |
|---|---|---|---|
| Agent 内入口 | `/autopilot "..."` | `$ultrawork "..."` | `/orca dispatch "..."` skill |
| 默认无 tmux | 默认在当前 shell 跑 cc | 默认在当前 shell 跑 codex | 默认不创建 tmux session |
| 按需多 pane | `/team` 或 `omc team N:agent` | `omx team spawn` | `/orca team N` 显式调用才 spawn |
| 工头介入 | OMC 主导（cc 是工头） | codex 是工头 | lead pane 收 worker 报告并可重新 dispatch |
| 危险操作授权 | cc 自身机制 | codex 自身机制 | **不要拦截 worker 的原生确认** |
| 多实例管理 | OMC 自动清理 | session 持久化 | `orca ps`/`clean` 暴露给 cc 调用 |

---

## 4. 落地路径草案

### Phase 0：紧急修复入口范式（P0）

1. 新增 `orca dispatch` skill，可在 cc/codex 内直接调用
2. `start.sh` 加 `--no-tmux` 默认开关，单 pane 模式直接退化为"在当前 shell 起 cc"
3. `start.sh` 默认只起 1 个 pane（lead），worker pane 按需 spawn
4. install.sh 注册 hook 但默认 dormant（不主动 push 通知），用户调用 `/orca` 才激活通信流（OMC/OMX 是「全量注册 + 功能按需」，Orca 应学这个范式）

### Phase 1：通信优化（P1）

5. 缩短 `read` 默认延迟（5s → 1-2s 或事件驱动）
6. 加 `orca worker spawn <agent>` 命令支持运行时增加 worker
7. 加 `orca worker status` 让 lead 不用 read pane 也能查状态

### Phase 2：自管理（P2）

8. `orca ps` / `orca clean` 暴露给 cc 调用
9. hook 自动检测僵尸 pane 并提示

---

## 5. 风险

- **不破坏现有用户**：`orca` 命令仍能创建多 pane，只是默认变了；老用户用 `--legacy` 或显式参数能恢复
- **嵌套问题**：tmux 内启动 cc，cc 的 hook 不要再触发 orca tmux 创建（需要环境变量探测，类似 `$TMUX` 检查）
- **OMC 的强项是 19 unified agents 自动选**：Orca 不应该走"specialist 库"路线（差异化在异构 agent + 弱研发流程），所以入口范式抄 OMC，但 agent 设计仍走 lead/worker

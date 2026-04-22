# Orca 演进方向建议

> 基于：[comparison-matrix.md](./comparison-matrix.md) + [ux-issues.md](./ux-issues.md) + [ctx-deep-dive.md](./ctx-deep-dive.md)
> 时间：2026-04-22

## 1. 三个独立但相关的议题

| 议题 | 来源 | 严重性 | 优先级 |
|---|---|---|---|
| **A. 入口范式重构** | Nick 反馈 + OMC/OMX 对照 | P0（用户 churn） | 立即 |
| **B. 通信连续性** | Nick 反馈 + OMX 队列模型 | P1（影响日常顺畅） | A 后 |
| **C. 上下文持续性** | ctx 借鉴 | P2（增量价值，非阻塞） | A、B 后 |

## 2. 议题 A：入口范式重构（P0）

### 2.1 现状

- 入口在 shell 外（`orca` 命令）
- 启动即创建 tmux session + 多 pane
- 用户必须懂 tmux/worktree/bridge 才能用
- "我突然就不想用了"

### 2.2 目标

让 Orca 同时支持两种用法：

**模式 A（OMC 风格，新默认）**：
- 用户开 cc/codex
- 在 Agent 内 `/orca dispatch "任务"`
- Orca 在后台按需创建 worker（默认还是当前 shell，需要并发才 spawn 新 pane）
- 用户全程在原 Agent 会话内，看不到 tmux

**模式 B（当前行为，保留为高级用法）**：
- 用户在 shell 跑 `orca`
- 创建多 pane 布局
- lead/worker 显式分离

### 2.3 改造范围（粗）

| 文件 | 改造内容 |
|---|---|
| `start.sh` | 加 `--no-tmux` / `--single-pane` 默认模式；旧行为通过 `--legacy` 或显式参数保留 |
| `install.sh` | hook 全量注册（参考 OMC 11 个事件、OMX 5 个事件的覆盖面）但默认 dormant 不主动 push；`/orca` 调用才激活通信流 |
| `skills/orca/SKILL.md` | 新增 `dispatch` 入口（cc/codex 内调用）；区分"在 Agent 内"和"在 shell 外"两种调用上下文 |
| 新增 `bin/orca-dispatch` | 给 Agent skill 调用的 shell 入口，封装 tmux 按需创建逻辑 |
| `tmux-bridge` | 加嵌套检测（已在 tmux 内时不再创建新 session） |

### 2.4 验收

- [ ] 在 cc 里 `/orca dispatch "..."` 能开工，不见 tmux
- [ ] 任务完成 worker 自动清理，不留僵尸 pane
- [ ] 老用户的 `orca` 命令仍能创建多 pane
- [ ] 嵌套场景（tmux 内启 cc）不再触发二次 tmux 创建

## 3. 议题 B：通信连续性（P1）

### 3.1 现状

- lead 用 `tmux-bridge read $WORKER 5` 同步等
- PreToolUse hook 给 idle 通知，但不能告知"结果就绪"
- 用户跳进 worker pane 直接打字纠偏（延迟太高）

### 3.2 目标

事件驱动的 lead/worker 通信。

### 3.3 改造范围（粗）

| 文件 | 改造内容 |
|---|---|
| `tmux-bridge` | 加 `wait-event` 模式：worker 完成时主动 signal lead |
| `skills/orca/SKILL.md` | read 周期从 5s → 事件驱动 |
| 新增 `orca worker status` | lead 不用 read pane 也能查 worker 状态（基于 SQLite 或 fifo） |
| 借鉴 OMX 队列模型 | 引入 `orca task queue` / `orca task claim`，worker 自取任务 |

### 3.4 验收

- [ ] worker 完成任务 lead 1s 内得知
- [ ] lead 可以同时跟踪 N 个 worker 而不阻塞
- [ ] 用户介入 worker 不再需要跳 pane

## 4. 议题 C：上下文持续性（P2）

### 4.1 现状

- pane scrollback 即丢
- worker session 死后无法续
- lead 难以回溯历史决策

### 4.2 目标

借鉴 ctx 的 workstream 模型，自研轻量上下文存储。

### 4.3 改造范围（粗）

详见 [ctx-deep-dive.md 第 5 节](./ctx-deep-dive.md)，摘要：

**Phase 1**：CLI + SQLite 最小闭环
- 新增 `scripts/orca-context.sh`
- 新增 SQLite 表：`workstream/session/entry/source_link/meta`
- 默认 DB：`.orca/context.db`
- 首批命令：`orca ctx start/bind/pull/resume/branch/search`

**Phase 2**：质量与隔离
- `pin` / `exclude` load control
- repo/worktree guard
- per-pane current slot

**Phase 3**：UI（如有需要）
- TUI 或 local web

### 4.4 验收

- [ ] worker pane 死后能从 DB 恢复对话上下文
- [ ] lead 可以 `orca ctx search "..."` 查跨 session 决策
- [ ] worktree 间分支不污染（快照分支）

## 5. 总体路线图

```
P0 (1-2 周): 入口范式重构
   ├─ start.sh --no-tmux 默认
   ├─ /orca dispatch skill
   ├─ install.sh hook dormant
   └─ 嵌套检测

P1 (2-4 周): 通信连续性
   ├─ tmux-bridge wait-event
   ├─ orca worker status
   └─ orca task queue (借鉴 OMX)

P2 (4-8 周): 上下文持续性
   ├─ orca-context.sh + sqlite schema
   ├─ orca ctx start/bind/pull
   ├─ orca ctx resume/branch/search
   └─ pin/exclude
```

## 6. 不做的事

- ❌ 不做 OMC 的 19 unified agents 库（差异化在异构 agent，不在 specialist 数量）
- ❌ 不引入 Python 作为核心依赖（保持 shell-only 哲学）
- ❌ 不做强结构化 workflow（Orca 是"弱研发流程"，OMX 那套不适合）
- ❌ 不做 Web UI（Phase 3 再说，且优先 TUI）
- ❌ 不直接依赖 ctx 运行时（产品边界不同）

## 7. 风险与开放问题

### 风险

| 风险 | 缓解 |
|---|---|
| 入口范式改变破坏老用户 | `--legacy` 参数 + 文档明确兼容性 |
| Hook dormant 后部分功能默认不可见 | `/orca status` 命令显式查询 |
| 队列模型增加复杂度 | Phase 2 才引入，不影响 P0 |
| SQLite 引入数据迁移成本 | Phase 3 再说，且向前兼容 |

### 开放问题（待你拍板）

1. **入口范式重构是另起新分支还是增量改？**
   - 我倾向新分支并行做，避免破坏当前用户
   - 拍板后再细分任务

2. **`/orca dispatch` 暴露给 cc 还是 codex 优先？**
   - 我倾向先 cc（用户基数大）
   - codex 同步跟进

3. **`orca task queue` 是 P1 还是 P2？**
   - 我倾向 P1，因为它解决"通信连续性"的根本
   - 但实现成本不低（需要持久化）

4. **上下文存储是 sqlite 还是 jsonl？**
   - 倾向 sqlite（搜索、join、原子性）
   - jsonl 更"shell 友好"，但搜索能力差

5. **是否要做 `orca doctor`？**
   - 借鉴 OMX 的 doctor 命令，提升首次安装可靠性
   - 成本低，建议加入 P0

## 8. 下一步

如果方向认可，建议：

1. 让 worker 把 OMC/OMX 的实测细节补完（[omc-deep-dive.md 第 4 节](./omc-deep-dive.md)、[omx-deep-dive.md 第 5 节](./omx-deep-dive.md)）
2. 起一个新 worktree 做 P0（`orca-entry-refactor`）
3. P0 期间不做 P1/P2，避免范围蔓延

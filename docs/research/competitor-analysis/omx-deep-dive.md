# OMX 深度分析（oh-my-codex）

> 仓库：[staticpayload/oh-my-codex](https://github.com/staticpayload/oh-my-codex)
> 备用名：scalarian/oh-my-codex
> 状态：🟢 已补充源码/文档实测细节（少数运行时行为仍未二进制级验证）

## 1. 定位

OpenAI Codex CLI 的编排层，"like oh-my-zsh but for Codex"。

特点：
- 多 agent team（执行/审查等角色）
- 持久 memory + state
- git worktree 集成
- 结构化 workflow（autopilot / TDD / code review / planning）
- README/About 仍提 Async Claude Code delegation，但 v2 源码与 FAQ 明确说明已不再是 Claude bridge

## 2. 安装 / 入口

### 2.1 安装

把 GitHub repo URL 粘贴给你的 agent，触发自动依赖安装、构建、CLI 链接。

或：标准 npm install（需 worker 确认包名）。

### 2.2 首次配置

```
omx setup       # 项目初始化
omx doctor      # 环境自检
omx hud         # 仪表盘验证
```

### 2.3 主入口

```
$ultrawork "ship the feature end to end"
```

也支持：
```
$tdd "write tests for auth"
$plan "design the migration"
```

## 3. Team / Worker 模型

```
omx team spawn executor          # 显式起 worker
omx team queue [task]            # 任务入队
omx team inbox                   # 看队列状态
```

worker 自取任务（claim 模型），不是 lead 直接 push。

## 4. 其他子命令

```
omx session                  # 持久工作上下文
omx explore index            # codebase 索引
omx hooks status             # hook 检查
omx plugins doctor           # 插件检查
```

## 5. 实测补充

- [x] **完整 CLI 命令列表**
  - `omx --help` 对应源码常量：
    - `omx setup`
    - `omx doctor`
    - `omx hud`
    - `omx team`
    - `omx explore`
    - `omx session`
    - `omx autoresearch`
    - `omx agents`
    - `omx plugins`
    - `omx hooks`
    - `omx version`
  - 证据：`/tmp/omx-research/packages/cli/src/help.ts:1-20`
  - `omx team` 子命令：
    - `init|status|spawn|queue|claim|heartbeat|complete|review|message|await|inbox|logs|resume|shutdown`
    - 证据：`/tmp/omx-research/packages/cli/src/commands/team.ts:19-167`

- [x] **`omx hud` 仪表盘真实样子**
  - 当前 HUD 是纯文本，不是 curses/TUI。
  - 固定输出字段：
    - `Branch`
    - `Session`
    - `Tasks`
    - `Modes`
    - `Team`
    - `Inbox`
    - `Priority note`
    - `Memory`
    - `Autoresearch`
  - 证据：`/tmp/omx-research/packages/core/src/hud.ts:68-93`
  - 未实机执行时，可按源码推得样式：
    ```text
    OMX HUD
    =======
    Branch: main
    Session: session_xxx (active)
    Tasks: 3 queued, 1 active, 0 in review
    Modes: ultrawork, plan
    Team: omx-team (1/3 busy, 0 stale, backend tmux)
    Inbox: 2 open, Reviews: 1 pending
    Priority note: none
    Memory: empty
    Autoresearch: idle
    ```

- [x] **队列模型实现**
  - `team.json` 里直接有 `taskQueue: string[]`。`/tmp/omx-research/packages/core/src/team.ts:37-53`
  - `queueTeamTask()` 把 taskId 放进 `taskQueue` 并把任务状态改为 `queued`。`packages/core/src/team.ts:253-260`
  - `claimTeamTask()`：
    - worker 置 `busy`
    - 写 `leaseExpiresAt`
    - 从 `taskQueue` 移除
    - task 状态变 `in_progress`
    - 证据：`packages/core/src/team.ts:262-289`
  - 结论：
    - **不是 socket**
    - **不是文件锁**
    - **是 repo-local JSON 队列 + lease 字段**

- [x] **持久 state 存储位置**
  - 产品真相是 repo 下的 `.omx/`。`/tmp/omx-research/docs/ARCHITECTURE.md:53-78`
  - 目录契约：
    - `.omx/state`
    - `.omx/sessions`
    - `.omx/plans`
    - `.omx/research`
    - `.omx/team`
    - `.omx/logs`
    - `.omx/memory`
    - `.omx/hud-config.json`
  - 证据：`/tmp/omx-research/packages/core/src/contract.ts:5-112`
  - 关键文件：
    - `state/tasks.json`
    - `state/reviews.json`
    - `state/inbox.json`
    - `state/hooks.json`
    - `team/team.json`
    - `logs/ledger.json`
  - 结论：
    - **不是 SQLite**
    - **是 repo-local JSON 文件族**

- [x] **memory 机制**
  - `memory/<namespace>.json`，默认 namespace=`project`。`/tmp/omx-research/packages/core/src/memory.ts:21-48`
  - 结构：
    - `namespace`
    - `summary`
    - `facts[]`
    - `updatedAt`
  - 保留的是项目摘要和事实，不是 transcript 回放。

- [x] **Async Claude Code delegation 怎么实现**
  - 结论：**当前 v2 没有实现。**
  - 证据链：
    - README/About 仍保留“Async Claude Code delegation (no timeouts)”的旧文案。
    - FAQ 明确写：`Is this still a Claude bridge? No.` `docs/FAQ.md:3-5`
    - Architecture 写：`durable orchestration primitives instead of a Claude bridge`。`docs/ARCHITECTURE.md:29-35`
    - README 也写：`There is no Claude bridge in this release.` `/tmp/omx-research/README.md`
  - 所以这是**文案滞后**，不应当算当前能力。

- [x] **TDD/plan workflow 完整流程**
  - `$tdd`
    - 红-绿-重构三段式
    - 明确 `No production code without a failing test first`
    - 输出要包含 behavior / failing signal / minimal implementation / final verification command
    - 证据：`/tmp/omx-research/skills/tdd/SKILL.md`
  - `$plan`
    - 先读 `.omx/plans/*-requirements.md`、`brownfield-map.md`、`.omx/research/summary.md`
    - 每个 slice 写清 files / verify / done / deps
    - 交付物是 `<phase>.md` 和 `<phase>-verification.md`
    - 证据：`/tmp/omx-research/skills/plan/SKILL.md`
  - `$ultrawork`
    - 默认路径是 interview -> plan -> execute -> verify
    - 模糊需求走 `$deep-interview`，并行耐久工作走 `$team`
    - 证据：`/tmp/omx-research/skills/ultrawork/SKILL.md`

- [x] **git worktree 集成**
  - 本轮没有验证到 team runtime 默认自动创建 worker worktree。
  - 当前核心实现聚焦于 tmux session/window + `.omx/` durable state。`/tmp/omx-research/packages/core/src/team.ts:137-250`
  - 所以最保守的写法应是：
    - **未验证到自动创建**
    - **骨架中“git worktree 集成”更像能力方向，不是默认命令流的显式行为**

- [x] **hook 机制**
  - 事件集：
    - `SessionStart`
    - `PreToolUse`
    - `PostToolUse`
    - `UserPromptSubmit`
    - `Stop`
    - 证据：`/tmp/omx-research/packages/core/src/hooks.ts:7-21`
  - 预设：
    - `workspace-context`
    - `memory`
    - `safety`
    - `review`
    - `telemetry`
    - 证据：`packages/core/src/hooks.ts:41-123`, `docs/HOOKS.md:5-11`
  - 安装位置：
    - repo-local：`<repo>/.codex/hooks.json`
    - handlers：`<repo>/.codex/hooks/omx/*.mjs`
    - personal 也支持 `~/.codex/hooks.json`
    - 证据：`packages/core/src/hooks.ts:138-215`, `docs/HOOKS.md:13-25`
  - 限制：
    - Codex hooks 仍是 experimental
    - `PreToolUse` / `PostToolUse` 主要面向 Bash
    - Windows 不在支持范围
    - 证据：`docs/HOOKS.md:34-38`

- [x] **License**
  - MIT。`/tmp/omx-research/LICENSE`

- [x] **维护活跃度**
  - 当前可见提交集中在两个时间点：
    - 2026-02-08 初始发布
    - 2026-04-01 一波 v2 product 化冲刺
  - 本地 `git log` 已拿到：
    - `2026-04-01` 多次 merge/feat/fix
    - `2026-02-08` initial release
  - 结论：
    - **不是持续高频日更**
    - **而是阶段性集中提交**

- [x] **失败恢复**
  - worker 有 `leaseExpiresAt`；超时后 `reconcileWorker()` 会把 `busy` worker 标成 `stale`。`/tmp/omx-research/packages/core/src/team.ts:127-134`
  - 但任务一旦被 claim，会从 `taskQueue` 中移除。`packages/core/src/team.ts:262-289`
  - 这意味着 worker 死亡后：
    - **不会自动重新入队**
    - 需要 operator 手动 `status` / `claim` / `queue` / `spawn` 修复

## 6. 对 Orca 的启示

| OMX 特性 | Orca 应该学吗 | 怎么学 |
|---|---|---|
| `$ultrawork` skill 入口 | **学** | 与 OMC 的 `/autopilot` 一致，做 `/orca dispatch` |
| 三步 onboarding（install/setup/doctor） | **可选学** | 加 `orca doctor` 自检命令 |
| **任务队列模型** | **重点学** | Phase 2 引入队列，避免 lead 直接硬指派；worker claim 模型 |
| **`omx hud` 仪表盘** | **学** | Orca 缺乏全局观测，可加 `orca hud` |
| persistent state | **学** | 与 ctx 借鉴方向重合，自研 sqlite 实现 |
| TDD/plan/review workflow | **可选学** | Orca 哲学是"弱研发流程"，但可作为可选 skill |
| Async delegation 文案 | **不直接学** | 当前 README 文案与 v2 实现不一致，先学 durable queue/event，再避免写超前营销文案 |

## 7. OMX vs OMC 关键差异

| 维度 | OMC | OMX |
|---|---|---|
| 宿主 | Claude Code | Codex CLI |
| 入口 | `/autopilot` | `$ultrawork` |
| 任务分发 | 智能路由（自动选 specialist） | 队列 + claim |
| 自动化程度 | 极高 | 中（保留用户控制） |
| 多 agent 架构 | 19 unified agents + 兼容 alias | architect / executor / reviewer 等少数固定角色 |
| tmux 关系 | 可选（Issue #716 已 Closed，文档口径采纳默认 tmux 包装） | tmux-aware（worker spawn 用） |

**对 Orca 的启示**：OMC 是"自动化优先"，OMX 是"显式控制优先"。Orca 应该走 OMX 路线，因为 Orca 的差异化是"弱研发流程 + 异构 agent 编排"，需要保留人工编排的控制点。

## 8. 参考材料

- [GitHub: staticpayload/oh-my-codex](https://github.com/staticpayload/oh-my-codex)
- [Verdent Guides: What Is OMX](https://www.verdent.ai/guides/what-is-oh-my-codex-omx)
- [FindSkill.ai: oh-my-codex explained](https://findskill.ai/blog/oh-my-codex-explained/)

# 四方对比矩阵

> 对比对象：Orca（当前）/ OMC / OMX / ctx
> 时间：2026-04-22

## 1. 产品定位

| 维度 | Orca（当前） | OMC | OMX | ctx |
|---|---|---|---|---|
| 一句话定位 | tmux 多 agent 编排器 | Claude Code 多 agent plugin | Codex CLI 编排层 | 本地上下文持续化 |
| 核心解决问题 | Lead 调度 Worker 并行 | Claude Code 内编排 native Team + 19 个主 agent | Codex 内 TDD/plan/review workflow | 跨会话上下文恢复、防漂移 |
| 设计哲学 | shell-only orchestrator | "Don't learn CC, just use OMC" | "oh-my-zsh for Codex" | local-first, no API key |
| 主语 | "工头-工人" 流水线 | Agent 团队 | 结构化 workflow | workstream（工作流） |
| 差异化 | 异构 agent + 弱研发流程 + 多 worktree | 19 个 unified agents + Team/native+tmux 双 runtime | 队列 + 持久 state | 上下文绑定 + 增量拉取 |

---

## 2. 入口与启动方式（Nick 最关心）

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 入口位置 | **shell 外**（`orca` 命令） | **Agent 内**（`/autopilot`） | **Agent 内**（`$ultrawork`） | **Agent 内**（`/ctx`） |
| 启动顺序 | 先 orca → 再装 cc/codex | 先开 cc → 再 `/autopilot` | 先开 codex → 再 `$ultrawork` | 先开 cc/codex → 再 `/ctx` |
| 默认是否拉 tmux | **是**（强制） | `/team` 否，`omc team` 是；`omc` 主 CLI 的默认 tmux 包装方向在 Issue #716 关闭后进入文档口径，但源码侧本轮未完全验证 | 否（team worker 才用 tmux） | 否（与 tmux 无关） |
| 默认布局 | 多 pane（lead + N worker） | 单 cc 会话 | 单 codex 会话 | 单会话 |
| 安装方式 | `install.sh` 写 hook + skill | `/plugin install` 原生 plugin | npm + `omx setup` | `setup.sh` 或 `curl \| bash` |
| 安装步骤数 | 1（脚本一键）+ 多步骤副作用 | 2（marketplace add + plugin install） | 3（npm + setup + doctor） | 1-3（视方式） |

---

## 3. 使用者视角 —— 上手难度

> 单位：从「装好工具」到「完成第一次有价值任务」需要的步数和心智负担

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| **首次价值前置步骤** | 1. `orca` 起 tmux<br>2. 理解 lead/worker pane<br>3. 主 pane 输入任务<br>4. lead 自行调度 worker | 1. `/autopilot "任务"`<br>（一句话开工） | 1. `omx setup`<br>2. `omx doctor`<br>3. `$ultrawork "任务"` | 1. `/ctx start <name>`<br>2. 正常对话<br>3. `/ctx pull` 抓 transcript |
| **必备前置概念** | tmux pane / worktree / bridge / lead-worker 协议 | （几乎无） | session / queue / worker 类型 | workstream / session / entry / source binding |
| **主观上手难度** | 高 | 极低 | 中 | 中 |
| **首次成功体验时长**（估算） | 5-15 min | < 1 min | 3-5 min | 2-3 min |
| **是否需要看文档** | 必须 | 不需要 | 推荐 | 推荐 |
| **失败时的错误反馈** | tmux/bash 报错（用户要懂 tmux） | Agent 内自然语言 | `omx doctor` 自检 | shell 错 + Agent 重提示 |

**解读**：OMC 是降维打击。它把"零学习"做到了极致：进 cc 直接 `/autopilot`。Orca 的入口前置成本是其他三家的好几倍。

---

## 4. 使用者视角 —— 日常使用顺畅性

> 单位：高频操作（每天可能 10-50 次）的摩擦点

| 操作 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 启动新任务 | 切到 lead pane → 输入 | 在 cc 内 `/autopilot` | 在 codex 内 `$ultrawork` | 在 cc/codex 内 `/ctx start` |
| 查看 worker 进度 | `tmux switch` 或主 pane 看 PreToolUse 通知 | cc 内自动汇报 | 队列状态查询命令 | 不涉及 |
| 中断 worker | 切到 worker pane → Ctrl+C 或回到 lead message | 自然语言中断 | `omx team kill` | 不涉及 |
| 切换 agent 类型 | 重启 worker pane | OMC 自动选 | `omx team spawn <type>` | 不涉及 |
| 多任务并行 | 必须开多 pane | 显式 `/team N:agent` | `omx team queue` | 不涉及 |
| 单 pane 简单提问 | **做不到**（要么用 orca 要么不用） | 直接对话即可 | 直接对话即可 | 不影响 |
| 退出/收尾 | `stop.sh` 杀 session | 关 cc 即可 | 关 codex 即可 | 关 Agent 即可 |
| 重启电脑后恢复 | 全部失去 | 部分（cc 自身能力） | 部分 | **完整恢复**（DB） |

**解读**：Nick 的"突然不想用了"主要源于这一栏：**"单 pane 简单提问"在 Orca 里做不到**。OMC/OMX 是"日常用 cc/codex，需要时调用编排"，Orca 是"用 orca 就被锁死在 tmux 里"。

---

## 5. 使用者视角 —— 可观测性

> 用户能看到 Agent 在做什么、任务进展如何

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 实时输出 | tmux pane 直接显示（多 pane 要切） | cc 内嵌显示 | codex 内嵌显示 + tmux pane | 不涉及实时 |
| 进度通知 | PreToolUse hook 在 lead 显示 | cc 原生 | `omx hud` 仪表盘 | 不涉及 |
| 全局视图 | `orca ps` 列实例 | `omc team status <team-name>`；in-session `/team status` 未直接验证 | `omx hud` / `omx team status` / `omx team inbox` | Web UI 时间线 |
| 历史追溯 | scrollback（pane 死即丢） | cc 自身历史 | session 持久化 | **SQLite 全文搜索** |
| 跨 worker 视图 | 必须切 pane | OMC 内聚合 | 队列 inbox | 不涉及 |
| 错误定位 | scrollback grep | cc 内 | `omx doctor` | 不涉及 |
| 第三方查看 | `tmux attach` | 难 | `omx hud` | Web UI（loopback） |

**解读**：Orca 在"实时"上有 tmux 优势（每个 pane 就是直播），但**"持续追溯"完全空白**——这是 ctx 最大的补位点。OMX 的 `omx hud` 是个有意思的中间态：仪表盘聚合状态。

---

## 6. 使用者视角 —— 可介入性

> 任务跑偏、需要纠偏或临时修改时的路径

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 介入入口 | 切 worker pane 直接打字 / 回 lead pane 让 lead 转发 | cc 内自然语言 | codex 内自然语言 / `omx team` 命令 | 不涉及 |
| 工头介入 vs 用户直接介入 | 都行（用户偏好"工头介入"，见 Nick 反馈） | 自然由 Claude 主导 | codex 主导 | 不涉及 |
| 危险操作授权 | **worker pane 自己处理**（Codex `rm -rf` 弹确认） | cc 自身机制 | codex 自身机制 | 不涉及 |
| 暂停 / 续跑 | 杀 pane / 重起 pane（丢上下文） | cc 原生支持 | session 持久化 | 不涉及 |
| 改主意（任务变了） | 重新 message lead | 自然语言重述 | 自然语言重述 | 不涉及 |
| 局部回滚 | 无 | 无 | 未验证到内建 session 回滚；当前更像靠持久 state + operator 手动修复 | branch 快照可回 |

**解读**：Nick 说"得让工头来介入啊，流水线工人那边不能随便介入的"——这是**协作流程偏好**，不是技术限制。Orca 实际两条路都通，但默认范式应明确"工头优先介入"，避免用户养成"跳进 worker pane 抢键盘"的反模式。

---

## 7. 使用者视角 —— 自动互相沟通的连续性

> 多 Agent 协作时，沟通是否流畅、是否需要人工拼接

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 通信通道 | tmux-bridge（pane 间发消息） | OMC 内部协议 | 队列 + state | 无（单 agent）|
| 通信触发 | 显式调用 bridge 命令 | 自动路由 | 队列 claim | - |
| 通信延迟 | 1-3 秒（PreToolUse hook 心跳） | 即时 | 队列轮询 | - |
| 上下文传递方式 | 文本消息体 / 文件路径 | 内部对象 | session state | - |
| 大消息处理 | 写文件 + 路径传递 | 内部 | 内部 | - |
| 跨 Agent 一致性 | 无（lead 自己维护） | OMC 维护 | OMX 维护 | - |
| 通信日志 | tmux scrollback | OMC 历史 | session 持久 | - |
| 通信失败重试 | 无（要 lead 看 read 结果） | 自动 | 队列重试 | - |
| 异步任务 | 不支持（lead 等 worker） | 部分支持：native Team API + tmux CLI runtime | **核心能力**（队列/claim） | - |
| 中断恢复 | 不支持（pane 死即丢） | 部分：dead worker 检测 + restart 设计，但 CLI team 可直接 fail fast | 部分：stale lease 可见，但无自动 requeue | - |

**解读**：Orca 的 tmux-bridge 是**显式同步通信**，OMX 的队列模型是**异步任务编排**。两者哲学不同：
- Orca：lead 是"项目经理"，直接和 worker 对话
- OMX：lead 是"任务发布者"，把任务扔进队列，worker 自取

Orca 的痛点：lead 必须 `read` worker pane 才知道结果，间歇性轮询，**没有事件驱动**。`PreToolUse` hook 是个心跳但只能告知"idle"，不能告知"结果就绪"。

---

## 8. 多 Agent / 多 Worker 模式

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| Worker spawn 时机 | 起手即建 | **按需**（`/team` 显式） | **按需**（`omx team spawn/queue`） | 不涉及 |
| Worker 类型 | 同质（lead + worker） | 19 个主 agent + 兼容 alias；native Team 与 tmux worker 并存 | architect / executor / reviewer 等固定角色 | 不涉及 |
| 任务分发 | lead 直接 message | `/team` 智能路由 | 队列 claim 模型 | 不涉及 |
| 跨 Agent | Claude + Codex pane 平等 | Claude 主，可 delegate Codex/Gemini | Codex 主 | Claude + Codex 都支持 |
| Worker 死亡 | 用户手动 stop | 任务完成自动死 | 任务完成自动死 | 不涉及 |
| 资源占用 | 起手就占满 | 按需 | 按需 | - |

---

## 9. 上下文与持续性（worker 报告核心）

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 上下文存储 | **无**（pane scrollback 即丢） | 内存 + 部分持久化 | 持久 state + memory | **SQLite 三层模型** |
| 数据模型 | 无 | `.omc/` 状态文件 + Team config/event/heartbeat/runtime snapshot | `.omx/` JSON 文件族（tasks/reviews/inbox/team/memory/ledger） | `workstream/session/entry` |
| 跨会话恢复 | 不支持 | 部分 | 支持 | **核心能力** |
| Transcript 绑定 | 无 | 无 | 无 | **`session_source_link`** |
| 增量拉取 | 无 | 无 | 无 | **`message_count` delta** |
| 分支语义 | git worktree 物理隔离 | 无 | 无 | **快照分支不共享未来绑定** |
| 搜索 | 无 | 会话/Team API 与 HUD 辅助，可观测性强于检索 | `omx explore index` | **SQLite FTS5** |
| 负载控制（pin/exclude） | 无 | 无 | 无 | **支持** |

---

## 10. 集成机制

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| Hooks | `PreToolUse` 通知 lead | `UserPromptSubmit` / `SessionStart` / `PreToolUse` / `PostToolUse` / `Stop` 等完整钩子栈 | `SessionStart` / `UserPromptSubmit` / `PreToolUse` / `PostToolUse` / `Stop` 预设包 | 几乎不用 hooks |
| Skill | shared `orca` skill | 19 主 agent + 36 skill（另有兼容 alias） | TDD/plan/review skill | `/ctx`、`ctx-resume`、`branch` |
| Slash command | `/orca` | `/setup` `/autopilot` `/team` | `$ultrawork` 等 | `/ctx` `/ctx resume` `/ctx branch` |
| 通信通道 | tmux-bridge（pane 间） | Claude Code 内部 | Codex 内部 + tmux | shell + SQLite |
| Codex 集成 | tmux pane | `omc team N:codex` 启真实 Codex CLI pane（不是一次性 `--no-interactive`） | 原生 | skill alias |

---

## 11. 技术栈与依赖

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 主语言 | Bash | TypeScript / Node | TypeScript / Node + 少量 Rust helper | **Python**（86%） |
| 运行时依赖 | tmux + bash | Node + Claude Code | Node + Codex CLI | Python 3.9+ + SQLite FTS5 |
| 第三方包 | 无 | npm | npm | 标准库 only |
| 数据库 | 无 | 无中心数据库，repo/worktree 状态文件 + 可选集中 `OMC_STATE_DIR` | 无数据库，repo-local `.omx/` JSON | SQLite (`~/.contextfun/context.db`) |
| 安装复杂度 | 中（install.sh 多步） | 低（plugin 一键） | 中（npm + setup + doctor） | 中 |
| 隐私边界 | 全本地 | 走 Claude Code | 走 Codex | 全本地，loopback only |

---

## 12. License & 维护

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| License | MIT | MIT | MIT | MIT |
| Bus factor | 你 + Claude | Yeachan-Heo 主导 | scalarian 主导 | 单作者（dchu917） |
| 活跃度 | - | 高（2026-04 仍在高频更新） | 中（2026-02 初发，2026-04-01 集中冲刺 v2） | 高（68 commits, 2026-04 密集） |
| API 稳定性 | - | 中 | 中 | 中（项目年轻） |

---

## 13. 综合评分（主观，1-5 分）

| 维度 | Orca | OMC | OMX | ctx |
|---|---|---|---|---|
| 上手难度（5=最易） | 2 | 5 | 3 | 4 |
| 日常顺畅性 | 2 | 5 | 4 | - |
| 可观测性 | 3 | 4 | 4 | 5 |
| 可介入性 | 4 | 4 | 4 | - |
| 通信连续性 | 2 | 4 | 5 | - |
| 上下文持续性 | 1 | 3 | 4 | 5 |
| 多 Agent 编排 | 4 | 5 | 4 | - |
| 安装/维护 | 3 | 4 | 3 | 3 |
| 总分（满分 40） | 21 | 34 | 27 | - |

> 说明：ctx 不在多 agent 维度参与评分。Orca 的"多 agent 编排" 4 分是因为它确实把 lead/worker 跑通了，但被入口范式拖累。

---

## 14. 一句话差异化

| 项目 | 一句话 |
|---|---|
| **Orca** | "我能让 Claude 和 Codex 在 tmux 里同时开工，但你得先学会 tmux" |
| **OMC** | "你在 cc 里说一句 `/autopilot`，剩下的不用管" |
| **OMX** | "Codex CLI 的 oh-my-zsh，TDD/plan/review 一条命令搞定" |
| **ctx** | "你的 cc 和 codex 对话不会再丢了，还能搜、能分支、能恢复" |

---

## 待 worker 补充的细节

以下维度已由 worker 通过源码/文档补齐：

- [x] OMC `omc team status <team-name>` 实际存在；in-session `/team status` 仍未直接验证
- [x] OMX `omx hud` 文本格式已由 `renderHud()` 源码确认
- [x] OMC 当前主 catalog 已确认不是 32，而是 19 个 unified agents（另有兼容 alias）
- [x] OMX 队列模型 API：`spawn/queue/claim/heartbeat/complete/review/inbox/logs/await`
- [x] OMC/OMX 的 hook 注册位置已确认
- [x] OMC setup 需要 `/setup` 或 `omc setup`，不是“完全零配置无 setup”
- [x] OMC/OMX 的 License 已确认均为 MIT
- [ ] OMC/OMX 中断恢复未做二进制级实机跑通，只完成源码核实

## 修正记录

- 把 OMC 的“32 specialists”修正为“当前 runtime 主 catalog 为 19 个 unified agents”；32 更像旧 tiered/内部文档口径，不是现行事实。
- 把 OMC 的“`/team status`（推测）”修正为：`omc team status <team-name>` 已确认存在，in-session `/team status` 仍未直接验证。
- 把 OMX 的“Async Claude Code delegation”从现有能力中移除：README/About 文案仍保留旧表述，但 FAQ 与架构文档明确说明 v2 已不再是 Claude bridge。
- 把 OMX 的状态存储从“session-based/未明”修正为“repo-local `.omx/` JSON 文件族”。
- 把 OMX 的“session 回滚（推测）”修正为“未验证到内建回滚，当前更像持久 state + operator 手动修复”。
- 把 Orca 的 License 从“MIT（推测）”修正为仓库 `LICENSE` 已确认的 MIT。

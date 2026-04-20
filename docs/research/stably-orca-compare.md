# stablyai/orca — 架构对比研究

## Provenance

- Source repository: https://github.com/stablyai/orca
- Reviewed commit: c47b651f2d7e79c5ca22737334495a953a9c2c11 (tag 1.3.6, 2026-04-19)
- Upstream license: MIT (Copyright © 2026 Lovecast Inc.)
- Reviewed: 2026-04-20
- Method: 仅静态阅读源码，无代码执行
- Scope: 编排 runtime、IPC、agent 通信、worktree 处理、状态检测。UI / build / i18n 不在范围
- Attribution form: 仅以「文件路径 + 行号」形式引用（如 `src/main/runtime/orca-runtime.ts:138-198`），未复制任何源码

---

## 1. 编排机制

`stablyai/orca` 的核心实现不是 lead/worker 式的文本协作器，而是 Electron main process 内的长期存活 runtime control plane。

- 主入口位于 `src/main/index.ts:140-226`。`app.whenReady()` 中初始化 `OrcaRuntimeService`、`registerCoreHandlers()`、`OrcaRuntimeRpcServer`，随后打开主窗口。由此可见，编排核心位于 main process，而不是 renderer 或 shell wrapper。
- 运行时核心位于 `src/main/runtime/orca-runtime.ts:138-198`。`OrcaRuntimeService` 内部维护 `tabs`、`leaves`、`handles`、`waiters`，将每个 terminal pane/leaf 视为可寻址对象，而不是将 agent 建模为互发消息的角色。
- 多 agent 组织方式体现为“单个 workspace 下的多个 tab/group/leaf”：
  - 持久化 schema 位于 `src/shared/workspace-session-schema.ts:177-191`，包含 `tabsByWorktree`、`terminalLayoutsByTabId`、`unifiedTabs`、`tabGroups`、`tabGroupLayouts`。
  - live graph 同步位于 `src/main/runtime/orca-runtime.ts:198-230`，renderer 将 graph 同步给 main，随后由 main 维护 authoritative terminal state。
- 进程形态如下：
  - 本地 terminal 通过 `node-pty` 驱动，见 `src/main/providers/local-pty-provider.ts:7,112-176,318-325`。
  - 远程 terminal 通过 SSH provider 抽象驱动，见 `src/main/providers/types.ts:53-67`、`src/main/providers/ssh-pty-provider.ts:66-88,133`。
  - 另有可选的 daemon-backed persistent terminal provider，并未观察到 Docker/container 编排路径，启动分支位于 `src/main/index.ts:185-209,191-201`。

从结构上看，`stablyai/orca` 的多 agent 编排更接近“桌面端多终端/多工作区控制平面”，而不是基于 tmux pane 的显式角色调度。

## 2. Agent 通信

### 2.1 main ⇄ renderer / CLI 通信

- renderer 与 main 之间通过 Electron IPC 通信，核心注册入口位于 `src/main/ipc/register-core-handlers.ts:37-83`。
- terminal 数据不是以文件或 message 文本形式传递，而是 PTY 数据流直通：
  - `src/main/ipc/pty.ts:196-240` 维护 `pendingData`，按 8ms flush，并通过 `mainWindow.webContents.send('pty:data', ...)` 推送给 renderer；进程退出时发送 `pty:exit`。
- CLI 对运行时的控制不是 stdin/stdout 转发，而是本地 RPC：
  - `src/main/runtime/runtime-rpc.ts:50-156` 启动本地 socket server，并生成随机 `authToken`。
  - bootstrap 元数据写入 `orca-runtime.json`，字段包含 `transport` 和 `authToken`，见 `src/shared/runtime-bootstrap.ts:13-24`、`src/main/runtime/runtime-metadata.ts:16-46`。
  - RPC 方法采用资源式接口，而不是 peer message，包括 `status.get`、`terminal.list/show/read/send/wait`、`worktree.ps/list/create`，见 `src/main/runtime/runtime-rpc.ts:218-385,524-573`。

### 2.2 agent ⇄ agent 关系

在本次聚焦的 core 文件范围内，未观察到与 `lead -> worker` 对应的显式角色关系层。以下结论属于基于源码结构的推断：

- runtime API 面向 terminal/worktree handle，而不是 peer label 或 role，见 `src/main/runtime/runtime-rpc.ts:229-342` 与 `src/main/runtime/orca-runtime.ts:290-375`。
- `OrcaRuntimeService` 维护的是 terminal handle、leaf、waiter，并未维护“谁向谁派发任务”的关系，见 `src/main/runtime/orca-runtime.ts:145-181`。

基于上述结构，`stablyai/orca` 的协作模型更接近“多个平铺 agent terminal 由 UI 与 runtime 统一观察和控制”，而不是显式的 lead/worker 层级调度。

### 2.3 长消息 / 多行内容

本次阅读范围内未发现与 `/tmp/orca-handoff-*.md` 或 `/tmp/orca-msg-*.md` 对应的 handoff 文件机制。原因可从接口形态解释：

- 控制接口采用结构化 RPC 与 PTY 字节流，不需要将长消息拼装为 shell 命令参数。
- 用户观察对话主要通过 UI 中的 terminal 内容与持久化 session：
  - terminal 流由 `pty:data` 推送，见 `src/main/ipc/pty.ts:206-240`
  - workspace session 持久化由 `session:get/set/set-sync` 完成，并包含 scrollback buffer，见 `src/main/ipc/session.ts:6-18`

这一实现路径绕开了 shell quoting、反引号替换与多行参数传递等问题。

## 3. Worktree / 仓库隔离

- `stablyai/orca` 直接内建 git worktree 能力，而不是通过额外 shell script 封装：
  - git worktree 基础操作位于 `src/main/git/worktree.ts:30-81,94-191`
  - IPC 暴露位于 `src/main/ipc/worktrees.ts:35-140`
  - 路径、branch 计算与安全校验位于 `src/main/ipc/worktree-logic.ts:8-40,47-94,96-121`
- 关键特征如下：
  - 支持本地 repo、folder-mode、SSH remote repo 三种路径，见 `src/main/ipc/worktrees.ts:49-107,120-135`
  - worktree path 会进行 workspace 目录约束，用于防止 path traversal，见 `src/main/ipc/worktree-logic.ts:32-44`
  - 支持 Windows/WSL 路径归一化与跨平台比较，见 `src/main/git/worktree.ts:9-27`、`src/main/ipc/worktree-logic.ts:68-94,96-112`
  - 删除 worktree 后会执行 prune，并尝试删除本地 branch，见 `src/main/git/worktree.ts:165-210`

与此对照，`fmfsaisai/orca` 当前的 worktree 管理主要由 `orca-worktree.sh:8-39,51-57` 完成，直接执行 `git worktree add/remove` 并将目录落在 `.orca/worktree/<id>/`。

## 4. Idle / 状态检测

`stablyai/orca` 的状态检测主要依赖直接监听 PTY 输出与 terminal title，而不是通过 hook 文件观察工具调用。

- 状态识别规则位于 `src/shared/agent-detection.ts:10-19,31,120-150,271-320`
  - 可识别 `claude`、`codex`、`gemini`、`opencode`、`aider`
  - 可从 OSC title 提取 `working | permission | idle`
- main process 中的 `AgentDetector` 位于 `src/main/stats/agent-detector.ts:60-140`
  - 每次 `onData()` 直接扫描 raw PTY data
  - 通过 `extractLastOscTitle()` 与 `detectAgentStatusFromTitle()` 判断状态
  - 区分 “meaningful output” 与纯 ANSI 噪音，以减少 idle prompt 被误判为 working 的情况
- `StatsCollector` 位于 `src/main/stats/collector.ts:53-149`，负责统计 agent start/stop 与累计时长
- 整体链路可概括为 `PTY output -> AgentDetector -> StatsCollector`，而不是 `tool hook -> heartbeat file`

与此对照，`fmfsaisai/orca` 当前的 idle 检测来自 hook 文件：

- worker 侧 PostToolUse 写 heartbeat，见 `hooks/post-tool-use.sh:2-8`
- lead 侧 PreToolUse 读取 heartbeat，并在 30s 阈值上输出 `[orca] Idle: ...`，见 `hooks/check-heartbeat.sh:2-29`
- 设计说明位于 `docs/design/heartbeat.md:21-26,52-60`

两种方案的观察对象不同：前者更接近 terminal/agent runtime 状态，后者更接近工具调用活跃度。

## 5. 关键文件清单

- 主入口 / 编排装配：
  - `src/main/index.ts:86-226`
  - `src/main/ipc/register-core-handlers.ts:37-83`
- runtime 控制平面：
  - `src/main/runtime/orca-runtime.ts:138-198,290-375`
  - `src/main/runtime/runtime-rpc.ts:50-156,218-385,524-573`
  - `src/shared/runtime-bootstrap.ts:13-24`
  - `src/main/runtime/runtime-metadata.ts:16-46`
- PTY / 子进程管理：
  - `src/main/ipc/pty.ts:19-25,125-182,196-240,300-359`
  - `src/main/providers/types.ts:10-67`
  - `src/main/providers/local-pty-provider.ts:7,112-176,318-325,415`
- worktree：
  - `src/main/git/worktree.ts:30-81,94-191`
  - `src/main/ipc/worktrees.ts:35-140`
  - `src/main/ipc/worktree-logic.ts:8-44,47-121`
- 状态检测：
  - `src/shared/agent-detection.ts:31,120-150,271-320`
  - `src/main/stats/agent-detector.ts:60-140`
  - `src/main/stats/collector.ts:53-149`

## 对 fmfsaisai/orca 的启发（项目方解读）

### stablyai/orca 在相关方面的覆盖

- 通信层避免了 shell quoting 问题，控制命令通过 RPC 发出，内容展示通过 PTY 流完成。
- runtime 由 main process 持有 authoritative state，terminal handle 稳定，因此能够提供 `list/show/read/send/wait` 这类统一编排接口。
- worktree 是一等公民能力，而不是附属脚本；本地、SSH、WSL、Windows 路径差异均在同一套抽象内处理。
- 状态检测直接观察 terminal/agent 生命周期，而不是通过工具调用频率间接推断。

### fmfsaisai/orca 在相关方面的特点

- 架构较为精简，部署路径集中于 shell、tmux 与 skill 协作。
- lead/worker 分工明确，适合通过主代理拆分任务给多个子代理的工作流。
- 临时 worktree、handoff 文件与 tmux pane 均可由维护者直接人工介入，排障路径较短。

### 可借鉴方向

1. 将“编排接口”从 `tmux-bridge message + pane label` 逐步提升为稳定句柄与结构化命令接口。
   `stablyai/orca` 中 `terminal.list/show/read/send/wait` 这类 runtime API 形态，为接口演化提供了一个可参考样本。
2. 将“终端状态”与“调度状态”分离。
   `fmfsaisai/orca` 当前 heartbeat 主要反映工具活跃度；若引入 terminal-title 或 stdout pattern 检测层，可形成另一条独立观察面。
3. 将 worktree 逻辑从 shell script 提升到库级模块。
   `stablyai/orca` 中的路径规范化、删除后 prune 与 branch cleanup、错误分类处理，展示了更完整的 worktree 生命周期治理方式。
4. 减少“将结构化控制内容塞入 shell 命令参数”的场景。
   `stablyai/orca` 采用 RPC 与 PTY 流后，长消息、特殊字符与多行内容不再依赖 shell 参数传递。

### 不直接适用的部分

- Electron main/renderer/runtime-rpc 的整套控制平面较重，与 `fmfsaisai/orca` 当前的 shell + skills 产品形态并不等价。
- `stablyai/orca` 的平铺 terminal 模型，并不直接对应 `fmfsaisai/orca` 的 lead/worker 编排模型；二者面向的协作体验不同。

## 总结

`stablyai/orca` 主要解决的是“桌面应用如何统一托管与观察多个 agent terminal”；`fmfsaisai/orca` 当前主要解决的是“在 shell/tmux 环境中由 lead 协调多个 worker”。前者在 runtime、通信与 worktree 抽象上的覆盖范围更广，后者在角色编排、轻量部署与人工介入路径上具有不同特点。两者差异的核心不在界面形态，而在编排控制面的建模方式。

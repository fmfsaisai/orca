# OMC 深度分析（oh-my-claudecode）

> 仓库：[Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)
> 状态：🟢 已补充源码/文档实测细节（少数运行时行为仍未二进制级验证）

## 1. 定位

Claude Code 的多 agent 编排 plugin，"Don't learn Claude Code. Just use OMC."

- 当前主 catalog 为 19 个 unified agents（另有兼容 alias）+ 36 skills
- 零配置，自动检测最佳模式和 agent
- 声称 "ship features 3-5× faster, save 30-50% tokens"

## 2. 安装 / 入口

### 2.1 Plugin 路径（推荐）

在 Claude Code 会话里：
```
/plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode
/plugin install oh-my-claudecode
```

### 2.2 npm 路径

```
npm i -g oh-my-claude-sisyphus@latest
```

### 2.3 首次使用

```
/setup                      # 首次配置（cc 内）
/autopilot "build a REST API"  # 自然语言开工
autopilot: build a REST API     # 等价的自然语言形式
```

## 3. Team 命令（多 worker）

```
omc team 1:claude "implement payment flow"
omc team 2:codex "review auth module"
omc team 2:gemini "redesign UI accessibility"
```

或在 cc 内：
```
/team
```

## 4. 实测补充

- [x] **完整 32 specialists 清单**
  - 结论：**当前公开运行时不是 32 specialists，而是 19 个 unified agents。**
  - 证据链：
    - README 写的是 `19 specialized agents`。`/tmp/omc-research/README.md:250`
    - 官网 changelog 写的是 v4.3.x 收敛成 `19 unified agents`。来源：`https://yeachan-heo.github.io/oh-my-claudecode-website/docs.html`
    - 运行时 registry 在 `getAgentDefinitions()`，主 agent 共 19 个。`/tmp/omc-research/src/agents/definitions.ts:212-250`
    - 仓库里仍有旧注释说 `32 specialized AI agent definitions`，但那是过期内部文档。`/tmp/omc-research/src/AGENTS.md`
  - 当前主 catalog 与能力边界：
    - `explore`：内部 codebase 搜索/结构理解；外部资料不归它。`src/agents/explore.ts:39-40`
    - `analyst`：需求澄清、隐含约束、风险识别。`src/agents/analyst.ts:38`
    - `planner`：创建工作计划，明确 NEVER implements。`src/agents/planner.ts:37`
    - `architect`：高难调试与架构设计，read-only consultation。`src/agents/architect.ts:43`
    - `debugger`：根因分析、回归定位、编译/构建错误。`src/agents/definitions.ts:55-60`
    - `executor`：直接实现；明确 NEVER delegate/spawn。`src/agents/executor.ts:38`
    - `verifier`：完成证据、claim 校验、测试充分性。`src/agents/definitions.ts:66-71`
    - `tracer`：因果追踪、竞争性假设、下一步 probe。`src/agents/tracer.ts:38`
    - `security-reviewer`：安全审计、OWASP、边界与漏洞检测。`src/agents/definitions.ts:101-106`
    - `code-reviewer`：全面代码审查、质量/兼容性/逻辑缺陷。`src/agents/definitions.ts:112-117`
    - `test-engineer`：测试策略、覆盖率、flaky hardening。`src/agents/definitions.ts:86-91`
    - `designer`：纯视觉/UI/UX 变更；纯逻辑前端改动不建议走它。`src/agents/designer.ts:42`
    - `writer`：README / API docs / 架构文档 / 用户指南。`src/agents/writer.ts:38`
    - `qa-tester`：交互式 CLI / 服务验证，依赖 tmux。`src/agents/qa-tester.ts:43`
    - `scientist`：数据分析、统计、Python EDA。`src/agents/scientist.ts:51`
    - `git-master`：atomic commit / rebase / history management。`src/agents/definitions.ts:124-129`
    - `document-specialist`：外部文档、SDK/API/reference lookup。`agents/document-specialist.md:2-3`
    - `code-simplifier`：代码简化、可维护性提升。`src/agents/definitions.ts:135-140`
    - `critic`：计划/方案/分析评审，补 “What's Missing”。`src/agents/critic.ts:37`
  - 额外说明：`docs/REFERENCE.md` 仍写 `Agents (29 Total)`，更像“主 agent + 兼容 alias/旧名”的总盘子，不等于当前主 catalog 数。`/tmp/omc-research/docs/REFERENCE.md:14`

- [x] **/setup 实际做什么**
  - `/setup` 与 `/omc-setup` 都是 setup 入口。`/tmp/omc-research/README.md:75-82`, `107-109`
  - setup 主要落盘到：
    - `~/.claude/agents/`
    - `~/.claude/skills/`
    - `~/.claude/hooks/`
    - `~/.claude/hud/`
    - `~/.claude/settings.json`
    - `~/.claude/CLAUDE.md`
    - `~/.claude/.omc-version.json`
    - `~/.claude/.omc-config.json`
    - 路径常量定义：`/tmp/omc-research/src/installer/index.ts:31-38`
  - 关键动作：
    - 写 agent files。`src/installer/index.ts:1671-1683`
    - 同步 bundled skills。`src/installer/index.ts:1751-1761`
    - 合并/备份 `CLAUDE.md`。`src/installer/index.ts:1779-1810`
    - 生成 `hud/omc-hud.mjs`。`src/installer/index.ts:1813-1843`
    - 更新 `settings.json` 的 hooks/statusLine。`src/installer/index.ts:1849-1911`
    - 保存 `.omc-version.json`。`src/installer/index.ts:1917-1925`
    - 保存 `.omc-config.json` 中的 node 路径。`src/installer/index.ts:1875-1889`
  - hook 注册位置：
    - `~/.claude/settings.json` 里合并 hooks 配置。`src/installer/index.ts:450-495`, `1849-1911`
    - standalone hook 脚本落到 `~/.claude/hooks/*.mjs`。`src/installer/index.ts:588-639`

- [x] **`/team` 与 `omc team` 的差异**
  - 这不是别名，而是两个不同 runtime。
  - `/team`
    - Claude Code 会话内 native team workflow。`/tmp/omc-research/README.md:123-147`
    - staged pipeline：`team-plan → team-prd → team-exec → team-verify → team-fix`。`README.md:133-145`
    - 需要 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`。`README.md:137-145`
  - `omc team`
    - shell/terminal 里的 CLI runtime，起 tmux CLI workers。`README.md:149-176`
    - 支持 `status` / `shutdown` / `api`。`/tmp/omc-research/docs/REFERENCE.md:353-367`
  - 选择建议：
    - Claude 内同质 Team 协作：`/team`
    - 真实 Codex/Gemini/Claude CLI panes：`omc team`

- [x] **Hook 机制**
  - 覆盖事件：
    - `UserPromptSubmit`
    - `SessionStart`
    - `PreToolUse`
    - `PermissionRequest`
    - `PostToolUse`
    - `PostToolUseFailure`
    - `SubagentStart`
    - `SubagentStop`
    - `PreCompact`
    - `Stop`
    - `SessionEnd`
  - 汇总表：`/tmp/omc-research/docs/REFERENCE.md:620-636`
  - 关键语义：
    - `autopilot` / `ralph` / `ultrawork` 是 skills，不是 hooks。
    - 真正阻止早停的是 `persistent-mode` Stop hook。`/tmp/omc-research/docs/HOOKS.md:230-237`

- [x] **按需 spawn 实现**
  - 外层先起 **detached Node runtime process**。`/tmp/omc-research/src/cli/team.ts:331-370`
  - runtime 再创建/管理 tmux panes。`/tmp/omc-research/src/team/runtime-v2.ts:1-14`
  - pane 内 worker 通过 `spawnWorkerInPane()` 注入启动命令。`/tmp/omc-research/src/team/tmux-session.ts:250-339`
  - 所以准确说法是：
    - control plane = detached Node runtime
    - worker execution = tmux pane + CLI process

- [x] **跨 agent delegate**
  - `omc team N:codex|gemini|claude` 用 provider contract 选 CLI binary。`/tmp/omc-research/src/team/model-contract.ts:160-245`
  - Codex worker 用的是真实 `codex` CLI，带 `--dangerously-bypass-approvals-and-sandbox`，并支持 prompt mode。`src/team/model-contract.ts:181-210`
  - 启动方式是 tmux pane 内执行 shell + binary，不是一次性 `--no-interactive` 子进程。`/tmp/omc-research/src/team/tmux-session.ts:269-311`

- [x] **`/team status` 是否存在**
  - shell 侧 `omc team status <team-name>` 已确认存在。`/tmp/omc-research/src/cli/commands/team.ts:26-45`, `683-732`, `855-860`
  - in-session `/team status` 本轮未直接验证，只能确认 Team API/Task API 存在。来源：`https://yeachan-heo.github.io/oh-my-claudecode-website/docs.html`

- [x] **License**
  - MIT。`/tmp/omc-research/LICENSE`

- [x] **Issue #716 进展**
  - Issue 页面状态是 **Closed**，但无关联 PR/branch/milestone。来源：`https://github.com/Yeachan-Heo/oh-my-claudecode/issues/716`
  - 提案内容是让 `omc` 默认像 OMX 一样把 Claude 包进 tmux session，并支持 `--no-tmux`。同页 issue body 可见。
  - 官网 CLI 文档已经出现 `Just run omc. It launches Claude Code inside a tmux session automatically.` 的口径，但本轮未完整追到主 launcher 源码实现，所以只能写成：
    - **Issue 已关闭**
    - **文档口径显示该方向已采纳**
    - **源码侧未完全验证到最终落地路径**

- [x] **失败/中断恢复**
  - runtime snapshot 会跟踪 `deadWorkers` / `nonReportingWorkers`。`/tmp/omc-research/src/team/runtime-v2.ts:108-143`, `1388-1544`
  - `all workers dead && outstanding work` 时 runtime-cli 直接 fail fast。`/tmp/omc-research/src/team/runtime-cli.ts:502-505`
  - 另有 worker auto-restart 模块，带 sidecar JSON + exponential backoff + `maxRestarts=3`。`/tmp/omc-research/src/team/worker-restart.ts:1-120`
  - 但 CLI workers 不写 `shutdown-ack.json`，更多依赖 tmux kill 和运行时检测。`/tmp/omc-research/src/team/runtime.ts:922-948`

- [x] **Token 节省 30-50% 的来源**
  - README 归因到 `Smart model routing` / `Cost optimization`。`/tmp/omc-research/README.md` “Why oh-my-claudecode?” 段
  - 本轮没有找到公开 benchmark methodology 或可复现实验。
  - 因此只能写：
    - **作者声称主要来源是 model routing**
    - **未验证到独立实验数据**

## 5. 对 Orca 的启示

| OMC 特性 | Orca 应该学吗 | 怎么学 |
|---|---|---|
| Plugin 形式安装 | **学** | 把 `install.sh` 退化为可选，主入口做成 cc plugin |
| `/autopilot` 入口 | **学** | 抄 `/orca dispatch "..."` |
| 按需 spawn worker | **学** | `start.sh` 默认单 pane，worker 显式调用才建 |
| 19 unified agents | **不学** | Orca 差异化在异构 agent，不在 specialist 库 |
| 自动选最佳 agent | **可选学** | Phase 2 可考虑 lead 自动选 worker 类型 |
| 零配置 | **学** | 砍掉 install.sh 的多步骤副作用 |

## 6. 参考材料

- [仓库主页](https://github.com/Yeachan-Heo/oh-my-claudecode)
- [官网](https://yeachan-heo.github.io/oh-my-claudecode-website/)
- [REFERENCE.md](https://github.com/Yeachan-Heo/oh-my-claudecode/blob/main/docs/REFERENCE.md)
- [Issue #716 - tmux 默认行为](https://github.com/Yeachan-Heo/oh-my-claudecode/issues/716)
- [agentskills.so 的 omc-setup](https://agentskills.so/skills/yeachan-heo-oh-my-claudecode-omc-setup)
- [npm: oh-my-claude-sisyphus](https://www.npmjs.com/package/oh-my-claude-sisyphus)
- 第三方介绍：[OpenClaw API blog](https://openclawapi.org/en/blog/2026-03-31-oh-my-claudecode-32-agents)、[emelia.io](https://emelia.io/hub/oh-my-claudecode-multi-agent)

---
name: orchestra
description: 多 agent 协同环境。当 $ORCH_ROLE 环境变量存在时激活。Lead 调度 Coder 编码，Coder 自查后 Lead 做独立优化。适用于涉及 coder、派活、协同等场景。
---

# Agent Orchestra Skill

你在一个多 agent 协同环境中工作。你的角色通过以下方式确定：
- 环境变量 `$ORCH_ROLE`（Claude Code 可读取）
- 或启动时收到的角色通知消息（如"你的角色是 coder"）

**如果以上两者都没有，忽略本 skill 的所有内容。**

## 角色

pane label 固定为 `lead` 和 `coder`。

启动时 orch 脚本会自动告知你的角色（通过 `echo $ORCH_ROLE` 或直接消息）。**禁止执行任何环境验证命令**，环境由 orch 脚本保证就绪，确认角色后直接等待指令。

| ORCH_ROLE | 角色 | agent | 职责 |
|-----------|------|-------|------|
| lead | 主调度器 | Claude Code | 接收用户任务、派活给 coder、等待结果、/simplify 独立优化、向用户汇报 |
| coder | 编码执行者 | Codex CLI | 接收任务、编码实现、/review 自查修复、汇报 lead |

## 通信命令

使用 `tmux-bridge` CLI 通信。**务必将整个流程写在一条 Bash 命令中**：

```bash
tmux-bridge read <target> 5 && tmux-bridge message <target> "消息内容" && tmux-bridge read <target> 5 && tmux-bridge keys <target> Enter
```

**Read Guard 机制**：每次 `type`/`keys` 前必须先 `read`，否则报错。每次操作后 read mark 清除，需重新 read。

读取对方输出：

```bash
tmux-bridge read <target> 200
```

---

## Lead 工作流（ORCH_ROLE=lead）

### 1. 接收任务

用户给你描述任务后，先与用户确认任务拆解方案。**在用户确认前，不要派活。**

### 2. 派活给 coder

```bash
tmux-bridge read coder 5 && tmux-bridge message coder "任务描述..." && tmux-bridge read coder 5 && tmux-bridge keys coder Enter
```

消息应包含：明确的实现目标、涉及的文件/模块范围、技术约束或偏好、验收标准。

**复杂任务先要方案**：涉及多文件或架构决策时，先让 coder 给方案，确认后再执行。

派活消息末尾附带：`完成编码后请执行 /review 自查，发现问题自行修复，然后汇报给我。`

### 3. 等待 coder 完成

**不要轮询。** 派活后直接告诉用户"已派活给 coder，等待汇报"，然后**结束你的回合**。

coder 完成后会通过 tmux-bridge 向你发送汇报消息，这条消息会出现在你的输入提示符中，你会自动收到。

**严格禁止**：不要执行 orch-idle、不要执行 tmux-bridge read 检查进度、不要轮询任何东西。

### 4. 收到汇报后独立优化

收到 coder 的汇报消息后，对 coder 修改的文件执行 `/simplify` 进行独立优化：
- 检查代码复用机会
- 检查代码质量问题
- 检查效率改进空间
- 直接修复发现的问题

### 5. 报告结果

向用户汇报：
- coder 实现了什么
- /simplify 优化了什么
- 修改的文件列表
- 需要用户关注的点

### Lead 规则

1. **先沟通再派活**：收到任务后先跟用户确认拆解方案
2. **不替代 coder**：编码交给 coder，自己负责调度和优化
3. **透明汇报**：派活时、收到结果时向用户简要汇报
4. **区分完成与异常**：不要假设 idle = 成功，read 后检查是否有报错
5. **复杂任务先要方案**：涉及多文件或架构决策时，先让 coder 给方案

---

## Coder 工作流（ORCH_ROLE=coder）

### 1. 接收并执行任务

收到 lead 的任务后，按要求编码实现。

### 2. 自查修复

编码完成后，执行 `/review` 对自己的代码进行审查。如果发现问题，自行修复后再次 `/review`，直到没有重大问题。

### 3. 验证（按需）

仅在任务明确要求或自行判断有必要时，才执行测试、lint 等验证。验证应在 /review 修复之后进行。

### 4. 汇报给 lead

给 lead 发送**简短摘要**（一两句话），不要发详细内容。Lead 会自己读文件了解细节。

```bash
tmux-bridge read lead 5 && tmux-bridge message lead "任务完成，修改了 X 个文件：file1, file2。已通过 /review。" && tmux-bridge read lead 5 && tmux-bridge keys lead Enter
```

**禁止在消息中包含代码片段、diff、完整日志等长内容。**

### 5. 主动发起协作

coder 也可以主动给 lead 发消息请求协助、确认方案或分配任务：

```bash
tmux-bridge read lead 5 && tmux-bridge message lead "请求：[需要 lead 做什么]" && tmux-bridge read lead 5 && tmux-bridge keys lead Enter
```

---

## 通用规则（所有角色）

1. **Read Guard**：每次 `type`/`keys` 前必须先 read（tmux-bridge 强制要求）
2. **一条命令完成通信**：read → message → read → keys 写在一条 `&&` 链中
3. **不要轮询**：等待对方时不要循环 read

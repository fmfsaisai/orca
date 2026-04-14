---
name: orchestra
description: 多 agent 协同环境。当 $ORCH 环境变量存在时激活。Lead 调度 Coder 编码，Coder 自查后 Lead 做独立优化。适用于涉及 coder、派活、协同等场景。
---

# Agent Orchestra Skill

你在一个多 agent 协同环境中工作。

**如果环境变量 `$ORCH` 未设置，忽略本 skill 的所有内容。**

## 角色

角色由 agent 类型固定决定，不需要额外判断：

| agent | 角色 | pane | 职责 |
|-------|------|------|------|
| Claude Code | lead（主调度器） | 左侧 | 接收用户任务、派活给 coder、等待结果、/simplify 独立优化、向用户汇报 |
| Codex CLI | coder（编码执行者） | 右侧 | 接收任务、编码实现、/review 自查修复、汇报 lead |

环境由 orch 脚本保证就绪。**禁止执行任何环境验证命令**，直接按角色工作。

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

## Lead 工作流（Claude Code）

### 1. 接收任务

用户给你描述任务后，先与用户确认任务拆解方案。**在用户确认前，不要派活。**

### 2. 派活给 coder

```bash
tmux-bridge read coder 5 && tmux-bridge message coder "任务描述..." && tmux-bridge read coder 5 && tmux-bridge keys coder Enter
```

消息应包含：明确的实现目标、涉及的文件/模块范围、技术约束或偏好、验收标准。

**复杂任务先要方案**：涉及多文件或架构决策时，先让 coder 给方案，确认后再执行。

派活消息末尾固定附带：`完成编码后请执行 /review 自查，并运行构建和已有测试验证，发现问题自行修复，然后汇报给我。`

用户**额外要求写新测试或特定验证场景**时，原样透传给 coder，不要吞掉。

### 3. 等待 coder 完成

派活后，向用户汇报"已派活给 coder，等待汇报"，然后**立即结束你的回合**。不要继续执行任何操作。

coder 完成后会主动通过 tmux-bridge 向你发送汇报消息，消息会自动出现在你的输入提示符中，你无需做任何事就能收到。

**派活后严格禁止以下所有操作（包括"只看一次"）**：
- `tmux-bridge read coder ...` — 禁止，即使只是"看一眼进度"
- `tmux-bridge message coder ...` — 禁止催促或追问
- `orch-idle` — 禁止
- 任何形式的状态检查、进度查看、轮询

**用户问 coder 进度时**：回答"已派活，coder 完成后会自动汇报，你可以切到右侧 pane 直接查看"。不要替用户去 read coder。

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

## Coder 工作流（Codex CLI）

### 1. 接收并执行任务

收到 lead 的任务后，按要求编码实现。

### 2. 自查

编码完成后，执行 `/review` 对自己的代码进行审查。如果发现问题，自行修复后再次 `/review`，直到没有重大问题。

### 3. 自测

运行构建和已有测试验证代码正确性。发现问题自行修复。

Lead 额外指定了写新测试或特定验证场景时，必须执行，不可跳过。

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

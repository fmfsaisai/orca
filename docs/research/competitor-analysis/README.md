# 竞品/参考项目对比分析

本目录归档 Orca 与同类项目的对比分析，用于回答：

- Orca 的入口范式是否合理？
- Orca 的上下文持续性应该怎么补？
- Orca 的差异化定位在哪里？

## 文档清单

| 文件 | 内容 | 状态 |
|---|---|---|
| [comparison-matrix.md](./comparison-matrix.md) | 四方对比矩阵（含 UX 维度） | ✅ 主框架完成，部分待 worker 实测 |
| [ux-issues.md](./ux-issues.md) | Nick 反馈拆解 + UX 问题清单 | ✅ |
| [omc-deep-dive.md](./omc-deep-dive.md) | OMC（oh-my-claudecode）深度分析 | 🟡 骨架，待 worker 填充 |
| [omx-deep-dive.md](./omx-deep-dive.md) | OMX（oh-my-codex）深度分析 | 🟡 骨架，待 worker 填充 |
| [ctx-deep-dive.md](./ctx-deep-dive.md) | ctx（dchu917/ctx）深度分析 | ✅ worker 报告整理 |
| [orca-evolution-proposal.md](./orca-evolution-proposal.md) | Orca 改造方向建议 | ✅ |

## 对比对象

| 项目 | 仓库 | 定位 |
|---|---|---|
| **Orca** | 本仓库 | tmux 多 agent 编排器 |
| **OMC** | [Yeachan-Heo/oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) | Claude Code 多 agent plugin |
| **OMX** | [staticpayload/oh-my-codex](https://github.com/staticpayload/oh-my-codex) | Codex CLI 编排层 |
| **ctx** | [dchu917/ctx](https://github.com/dchu917/ctx) | 本地上下文持续化 |

> 注：另有 [stablyai/orca](https://github.com/stablyai/orca) 的对比已在 [`../stably-orca-compare.md`](../stably-orca-compare.md)，定位是 Electron 桌面端，与本目录的 CLI/Agent-plugin 维度不同，单独存档。

## 一句话结论

| 项目 | 学什么 | 怎么学 |
|---|---|---|
| **OMC** | Agent 内入口、按需 spawn pane、低门槛安装 | 把 `orca` 主入口下沉到 cc/codex 内的 skill；tmux 按需而非起手 |
| **OMX** | 任务队列、worker claim 模型、`doctor` 自检命令 | Phase 2 引入队列模型，避免 lead 直接硬指派 |
| **ctx** | workstream 数据模型、绑定表、增量拉取、快照分支、pin/exclude | shell + sqlite3 CLI 自研（不依赖 Python） |
| **不学** | OMC 的 19 unified agents 库；ctx 的 Web UI；OMX 的强 Codex 耦合 | 保持 Orca 异构 agent 编排的差异化定位 |

详见 [orca-evolution-proposal.md](./orca-evolution-proposal.md)。

## 调研方法说明

- WebFetch / WebSearch 公开材料
- 部分项目源码 git clone 到 `/tmp/` 静态阅读
- 不在范围：UI 截图、企业版功能、商业模型
- Attribution：仅以「文件路径 + 行号」形式引用，不复制源码
- 时间戳：2026-04-22

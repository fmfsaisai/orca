# Git Worktree Build Practices — 社区共识归档

## Provenance

- Reviewed: 2026-04-21
- Method: 公开文档与社区文章静态阅读
- Scope: 多 worktree 场景下的 dependency 安装、build / dev server / test 执行
- Attribution: 仅以「源 URL + 关键句直引」形式引用

---

## 1. 共识结论

社区在多个独立来源上形成稳定共识：

1. **Per-worktree install**：每个 worktree 必须独立安装依赖，不跨 worktree 共享 `node_modules` / `.venv` / `vendor/` / `Pods/` 等工程产物
2. **包管理器底层 cache 自然共享**：`~/.pnpm-store`、`~/.cache/pip`、`$GOPATH/pkg/mod`、`~/.m2/repository` 等全局 cache 由包管理器自身维护，多 worktree 自动共用，无需用户介入
3. **build / test / dev server 均在 worktree 内运行**：使用 worktree 自身的 deps，不引用主仓产物

不要：
- 跨 worktree 共享 `node_modules` 等工程目录（含 symlink 或 cp -al 等手段）
- 在 worktree 中引用主仓的 build 产物作为运行时输入
- 在主仓中跑 build / test 来「服务」worktree

---

## 2. 第一手来源

### 2.1 pnpm 官方文档（最强背书）

源：https://pnpm.io/next/git-worktrees

> "The first `pnpm install` downloads packages into the global store. Subsequent installs in other worktrees are nearly instant because they only create symlinks to the same store."

> "each worktree's `node_modules` contains only symlinks into a single content-addressable store on disk. This means adding a new agent is fast and costs almost no extra disk space."

意义：pnpm 把「git worktrees + multi-agent」列为官方支持场景，并明确推荐 per-worktree install。

### 2.2 Python 社区共识

源：https://huonw.github.io/blog/2020/04/worktrees-and-pyenv/

源：https://www.andreagrandi.it/posts/how-to-use-git-worktree-effectively-with-python-projects/

共识写法：
- 每个 worktree 用独立 venv（推荐 `pyenv local` 自动绑定）
- 共享 `~/.cache/pip` 由 pip 自动处理

### 2.3 通用 best practice

源：
- https://blog.flotes.app/posts/git-worktrees
- https://www.gitworktree.org/faq
- https://oneuptime.com/blog/post/2026-01-24-git-worktrees/view

> "Node modules and other dependencies are not shared, lock production worktrees..."

> "git pull origin main && yarn install before checking out a new branch"

### 2.4 工程化工具

源：https://github.com/rohansx/workz

`workz` 把上述 pattern 工程化为「zero-config dep sync for Node, Rust, Python, Go, and Java」。证据点：社区已成熟到值得专门工具实现。

### 2.5 git 官方文档

源：https://git-scm.com/docs/git-worktree

git-worktree(1) 不涉及 build / deps 话题。所有 deps 相关 best practice 来自工具生态层，不是 git 层。

---

## 3. 各生态实现差异（速查）

| 生态 | 全局 cache（自动共享） | 工程产物（per-worktree） |
|---|---|---|
| pnpm | `~/.pnpm-store`（CAS hardlink） | `node_modules` |
| npm / yarn classic | `~/.npm` / `~/.yarn/cache`（仅下载） | `node_modules` |
| Python (pip / uv / poetry) | `~/.cache/pip`、`~/.cache/uv` | `.venv` |
| Go | `$GOPATH/pkg/mod` | binary、`vendor/` |
| Java (Maven / Gradle) | `~/.m2/repository`、`~/.gradle/caches` | `target/`、`build/` |
| Rust | `~/.cargo/registry` | `target/` |
| CocoaPods | `~/.cocoapods` | `Pods/` |

共性：所有现代包管理器都已分离「下载/存储缓存」与「工程产物」。前者本就跨 worktree 共享；后者必须 per-tree。

---

## 4. 对 orca 的应用

`skills/orca/SKILL.md` 的 Worktree Filesystem Access 段据此规定：

- **Read 主仓 tracked 资源 / 只读引用数据** → `$ORCA_ROOT/<path>`
- **Install / build / test / run worktree 代码** → per-worktree install，包管理器自动复用全局 cache
- **Write task 代码** → 当前 worktree
- **Write 跨 task 共享资源** → `$ORCA_ROOT/<path>`，需任务显式授权

明确**排除**「从 `$ORCA_ROOT/node_modules` 等 deps 目录读」这条歧义路径。

---

## 5. 不在本归档范围

- IDE 集成（VSCode / IntelliJ 的 worktree workspace 配置）
- monorepo 工具（Turborepo / Nx）的 worktree 适配
- CI 中 worktree 用法（多数 CI 直接 fresh clone，不用 worktree）

如未来需要可独立扩充。

# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

[English](README.md) | 中文 | [博客文章](https://fists.cc/posts/ai/ruyi-as-you-wish/)

## Status

本项目正在积极开发中。`.ruyi-tasks` 格式和公开 API 可能会在版本间发生变化。

**心想事成。**

任何任务最难的部分不是做，而是定义清楚"做好"到底长什么样。如意通过与 [Claude Code](https://claude.ai/code) 的交互对话，帮你定义你真正想要的，包括怎样才算达标。然后剩下的交给如意：自主的实现-审查循环，直到达到你定义的标准。

灵感来自 [Karpathy 的 autoresearch](https://github.com/karpathy/autoresearch) 和软件开发的实现-审查-交付模式——泛化到**一切任务**。

## 能做什么

```bash
ruyi do "添加 CLI 支持"
ruyi do "写一篇产品发布的博客"
ruyi do "把 README 翻译成日语"
ruyi do "调研竞品定价并写摘要"
```

一条命令，任何任务。如意和你一起规划，然后运行自主循环：**Agent A 执行 → Agent B 审查 → 修改或交付**。每一轮从审查反馈中改进。只有高质量的产出才能通过。

## 怎么用

```bash
ruyi do "目标"                    # 描述你想做的
ruyi do @requirements.md         # 从文件读取目标
ruyi do #123                     # 做一个 GitHub issue
ruyi do                          # 重跑最近的任务
ruyi pdo "X" // "Y" // "Z"      # 并行做多件事
```

## 在 Claude Code 中使用

如果你用 [Claude Code](https://claude.ai/code)，如意提供了 `/ruyi` 斜杠命令，把你的对话变成任务定义工作流：

```
你：     /ruyi 添加暗色模式
Claude:  [阅读你的代码库，提出 goal + judgement]
你：     judgement 更严格一点——也检查对比度
Claude:  [更新 task.rkt，后台运行 ruyi do]
你：     侧边栏组件也处理一下        ← 继续聊
Claude:  [编辑 task.rkt — 下次迭代生效]
```

工作流：
1. **讨论** — Claude 通过对话帮你定义 goal 和 judgement
2. **写入** — Claude 写 `task.rkt`，后台运行 `ruyi do`
3. **调整** — 继续聊天。让 Claude 修改 goal 或 judgement；它实时编辑 `task.rkt`。运行中的如意每轮迭代重新读取。

你留在对话里。如意在后台干活。

## 安装

你需要 [Claude Code](https://claude.ai/code)。把下面这句话粘贴进去：

> 帮我安装 ruyi: https://github.com/ZhenchongLi/ruyi/blob/main/INSTALL-PROMPT.md

Claude Code 会自动检测环境、安装依赖、完成配置。支持 macOS、Linux，不依赖 brew，大陆网络也能用。

<details>
<summary>Shell 脚本安装（备选）</summary>

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

</details>

---

## 工作原理

```
  ruyi do "目标"
       │
       ├─ Claude Code 交互式规划
       │  → 生成 .ruyi-tasks/<日期>-<摘要>/task.rkt
       │
       ├─ 实现-审查循环：
       │    Agent A (Claude Code) 实现  ← 完整能力：读文件、写代码、跑测试
       │    Agent B (独立) 审查         ← 对抗性，找问题
       │    分数 < 阈值？→ 反馈给 Agent A，修订
       │    如意裁决：提交 / 修改 / 回滚
       │
       └─ 推送 + PR（或本地合并）
```

两个独立 AI agent——一个实现，一个审查。它们看不到彼此的推理过程。如意是裁判。

## Claude Code + 如意

它们互相调用：

```
用户 → Claude Code → ruyi do "目标"    CC 把复杂任务委托给如意
                        │
                        ├─ 如意 → Claude Code（规划）   交互对话
                        ├─ 如意 → Claude Code（实现）   完整 agent 模式
                        └─ 如意 → Claude Code（审查）   独立审查
```

**Claude Code** 是大脑——读代码、写代码、和你对话。**如意** 是流程——worktree 隔离、提交/回滚、双 Agent 审查、质量循环。

一起用：在项目的 `CLAUDE.md` 中加入：

```markdown
遇到复杂的多步任务，使用 `ruyi do "目标"` 而不是直接实现。
如意会处理 worktree 隔离、迭代审查和安全的提交/回滚。
```

## 安全契约

- **原子性提交或回滚** ——任务要么通过审查并提交，要么完整回滚
- **双 Agent 审查** ——实现者和审查者独立、对抗
- **Worktree 隔离** ——每个任务在独立的 git worktree 中运行，不碰你的工作目录
- **所有参数由你掌控** ——分数阈值、diff 限制、修改轮数，全部通过自然语言控制

## 全部命令

```bash
ruyi do "目标"                    # 主命令
ruyi do @file.md                 # 从文件读取目标
ruyi do #123                     # 做一个 GitHub issue
ruyi do #123 "补充说明"           # issue + 额外指示
ruyi do                          # 重跑最近的任务
ruyi tasks                       # 列出所有任务
ruyi pdo "X" // "Y" // "Z"      # 并行执行
ruyi modes                       # 列出保存的 mode
ruyi import mode.txt             # 导入 mode
ruyi clean                       # 清理如意生成的文件
ruyi update                      # 更新如意
ruyi version                     # 显示版本
```

## 任务文件

每次 `ruyi do` 会生成 `.ruyi-tasks/` 文件夹：

```
.ruyi-tasks/2026-03-27-improve-docs/
  task.rkt     ← 任务定义（可读、可编辑、git 跟踪）
```

```racket
(ruyi-task
  (goal "提高文档质量")
  (judgement "关注清晰度，面向 HN 读者")
  (max-revisions 3)                       ;; 审查-修订轮数
  (min-score 8))                          ;; 审查者通过阈值
```

编辑 `task.rkt`，`ruyi do` 重跑。修改下次迭代生效。可以分享给团队。

<details>
<summary>为什么选择 Racket？</summary>

安全不变量（原子性提交或回滚、diff 限制、双 Agent 审查）太重要了，不能交给 LLM。引擎约 2,000 行 Racket——10 分钟可读完。你不需要写 Racket——它只是运行时。

</details>

## 致谢

- [Karpathy 的 autoresearch](https://github.com/karpathy/autoresearch)——核心洞察：AI agent 可以在自主循环中做真正的迭代工作，而非一次性生成。如意将其泛化：软件开发的实现-审查-交付模式，适用于任何任务。
- [Claude Code](https://claude.ai/code) by Anthropic——驱动实现和审查的 AI agent。

## 许可证

MIT

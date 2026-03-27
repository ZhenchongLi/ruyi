# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

[English](README.md) | 中文

**如你所愿。** 用自主的实现-审查循环，替代传统的 dev-review 工作流。

灵感来自 [Karpathy 的 autoresearch](https://github.com/karpathy/autoresearch)——AI agent 可以在循环中做真正的工作，而不只是一次性生成。如意将这个理念应用于软件工程：两个独立的 AI agent 对每个变更反复博弈，直到质量收敛。

## 能做什么

```bash
ruyi do "添加 CLI 支持"
```

一条命令。如意和你一起规划，然后运行自主循环：**Agent A 实现 → Agent B 审查 → 修改或提交**。每一轮，实现者从审查者的反馈中改进。只有通过审查的变更才会被提交。最终你得到一个干净的 PR。

## 怎么用

```bash
ruyi do "目标"                    # 描述你想做的
ruyi do @requirements.md         # 从文件读取目标
ruyi do #123                     # 做一个 GitHub issue
ruyi do                          # 重跑最近的任务
ruyi pdo "X" // "Y" // "Z"      # 并行做多件事
```

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
       ├─ 每个子任务：
       │    Agent A (Claude Code) 实现  ← 完整能力：读文件、写代码、跑测试
       │    Agent B (独立) 审查         ← 对抗性，找问题
       │    如意裁决：提交 / 修改 / 回滚
       │
       └─ 推送 + PR（或本地合并）
```

两个独立 AI agent——一个实现，一个审查。它们看不到彼此的推理过程。如意是裁判。

## 安全契约

- **原子性提交或回滚** ——每个子任务要么通过并提交，要么完整回滚
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

每次 `ruyi do` 会生成 `.ruyi-tasks/` 文件夹，包含任务文件——可读、可编辑、git 跟踪：

```racket
(ruyi-task
  (goal "提高文档质量")
  (validate #f)
  (max-revisions 2)
  (min-score 8)
  (judgement "关注清晰度，面向 HN 读者")
  (subtasks
    ("编写中英双语 README")
    ("添加架构图和说明")))
```

编辑后 `ruyi do` 重跑。可以分享给团队。

<details>
<summary>为什么选择 Racket？</summary>

安全不变量（原子性提交或回滚、diff 限制、双 Agent 审查）太重要了，不能交给 LLM。引擎约 2,000 行 Racket——10 分钟可读完。你不需要写 Racket——它只是运行时。

</details>

## 致谢

- [Karpathy 的 autoresearch](https://github.com/karpathy/autoresearch)——核心洞察：AI agent 可以在自主循环中做真正的迭代工作，而非一次性生成。如意将这一模式引入软件工程，加入双 Agent 审查。
- [Claude Code](https://claude.ai/code) by Anthropic——执行实现和审查的 AI agent。

## 许可证

MIT

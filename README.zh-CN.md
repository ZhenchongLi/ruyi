# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

[English](README.md) | 中文

**告诉 Claude 你想要什么，Ruyi 确保只有干净的变更被提交。**

每一次 AI 变更要么干净地提交，要么完整地回滚——你只需审查一个 PR，而不是一个改了一半的烂摊子。安全契约由代码保证，而非提示词。

## 20 秒上手

```bash
cd your-project
ruyi do "add CLI support"
```

就这么简单。Ruyi 自动检测你的项目，将目标拆分为子任务，逐一实现，运行你的测试，通过的提交，失败的回滚。最终你会得到一个干净的 PR。

想同时做两件事？打开另一个终端：

```bash
ruyi do "fix auth bug"          # 并行执行，在独立的 worktree 中
```

或者一次启动多个任务：

```bash
ruyi pdo "add tests" // "translate README" // "fix auth bug"
```

## 工作原理

```
     ┌─────────────────┐
     │  ruyi do "goal"  │  描述你的目标
     └────────┬────────┘
              ▼
     ┌──────────────────┐
     │  拆分为子任务      │
     │  (Claude)         │
     └────────┬─────────┘
              ▼
     ┌──────────────────┐
     │  实现下一个        │◄──────────────────┐
     │  子任务 (Claude)   │                   │
     └────────┬─────────┘                   │
              ▼                             │
     ┌──────────────────┐                   │
     │  运行测试/构建     │                   │
     └───┬──────────┬───┘                   │
   通过  ▼          ▼ 失败                  │
   ┌──────────┐ ┌───────────┐              │
   │  提交    │ │  回滚      │              │
   │ (原子性) │ │ (完整回滚) │              │
   └────┬─────┘ └─────┬─────┘              │
        └──────────────┴────────────────────┘
              ▼
     ┌──────────────────┐
     │ 一个干净的 PR      │
     └──────────────────┘
```

Racket 引擎控制每一个步骤。Claude 不会决定是提交还是回滚——循环会根据你的测试套件来决定。

## 安装

前置条件：[Claude Code](https://claude.ai/code) 和 Git。

**一行安装**（类似 oh-my-zsh）：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

或手动：

```bash
git clone https://github.com/ZhenchongLi/ruyi.git ~/.ruyi && ~/.ruyi/install.sh
```

Ruyi 会自动检查更新。运行 `ruyi update` 获取最新版本。

<details>
<summary>安装脚本做了什么</summary>

1. 安装 `racket`（如果没有，通过 brew/apt）
2. 安装 `gh`（可选，用于 GitHub issue 支持）
3. Clone 到 `~/.ruyi`
4. 编译 `raco make`
5. 链接 `~/.ruyi/ruyi` 到 `~/.local/bin/ruyi`
6. 如需要，将 `~/.local/bin` 加入 PATH

</details>

## 命令

```bash
ruyi do "goal"                   # 执行目标——主命令
ruyi pdo "X" // "Y" // "Z"      # 并行执行多个目标
ruyi run my-mode                 # 重新运行已保存的 mode
ruyi modes                       # 列出已保存的 mode
ruyi import mode.txt             # 从文件导入 mode
ruyi init                        # 手动初始化（通常自动完成）
ruyi update                      # 更新 ruyi
ruyi version                     # 显示版本
```

## Mode（模式）

成功执行 `ruyi do` 后，系统会提示你将目标保存为**可复用的 mode**。Mode 是存放在 `.ruyi-modes/` 中的纯文本文件：

```
$ ruyi do "add comprehensive test coverage"
...
Done: evolve/freestyle/0326 (kept 5)
PR: https://github.com/...

Save as reusable mode? Name (Enter to skip): test-coverage
Saved: .ruyi-modes/test-coverage.txt
Re-run anytime: ruyi run test-coverage
```

与团队共享 mode——只需提交 `.ruyi-modes/` 目录，或使用 `ruyi import`。

## 安全契约

- **原子性提交或回滚** ——每个子任务要么通过测试并提交，要么完整回滚。不会出现中间状态。
- **Worktree 隔离** ——每个 `ruyi do` 在独立的 git worktree 中运行，不会触碰你的工作目录。可以随意并行运行多个任务。
- **Diff 大小限制**（默认 500 行）——防止变更失控。
- **禁止文件** ——不会触碰你保护的文件。
- **一个干净的 PR** ——最终你只需审查一个 diff。

所有规则由 [Racket 引擎](engine.rkt) 强制执行，而非提示词。

## 支持的语言

TypeScript、JavaScript、Python、C#/.NET、Rust、Go、Racket——任何包含 `package.json`、`pyproject.toml`、`Cargo.toml`、`go.mod` 或类似配置文件的项目。Ruyi 自动检测编程语言、构建工具和测试框架。

<details>
<summary>为什么选择 Racket？</summary>

安全不变量（原子性提交或回滚、diff 大小限制、禁止文件强制执行）太重要了，不能交给 LLM 来保证。整个引擎约 2,000 行 Racket 代码——你可以在大约 10 分钟内读完核心循环（[`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)）。你不需要编写或阅读 Racket——它只是运行时。

</details>

## 许可证

MIT

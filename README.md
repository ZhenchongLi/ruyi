# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

[中文文档](README.zh-CN.md)

**As you wish.** Tell Claude what you want — Ruyi makes it happen, safely.

## What it does

```bash
ruyi do "add CLI support"
```

One command. Ruyi plans with you, implements each step with Claude Code, reviews with an independent AI reviewer, commits what passes, reverts what fails. You get one clean PR.

## How to use

```bash
ruyi do "goal"                   # describe what you want
ruyi do @requirements.md         # read goal from file
ruyi do #123                     # do a GitHub issue
ruyi do                          # re-run latest task
ruyi pdo "X" // "Y" // "Z"      # do multiple things in parallel
```

## Install

You need [Claude Code](https://claude.ai/code). Paste this into it:

> Install ruyi for me: https://github.com/ZhenchongLi/ruyi/blob/main/INSTALL-PROMPT.md

That's it. Claude Code detects your environment and handles everything.

<details>
<summary>Shell script (alternative)</summary>

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

</details>

---

## How it works

```
  ruyi do "goal"
       │
       ├─ Claude Code plans with you interactively
       │  → generates .ruyi-tasks/<date>-<slug>/task.rkt
       │
       ├─ For each subtask:
       │    Agent A (Claude Code) implements  ← full agent: reads, writes, tests
       │    Agent B (independent) reviews     ← adversarial, finds issues
       │    Ruyi decides: commit / revise / revert
       │
       └─ Push + PR (or local merge)
```

Two independent AI agents — one implements, one reviews. They never see each other's reasoning. Ruyi is the referee.

## The safety contract

- **Atomic commit-or-revert** — every subtask either passes and commits, or reverts completely
- **Dual-agent review** — implementer and reviewer are independent, adversarial
- **Worktree isolation** — each task runs in its own git worktree, never touches your working directory
- **All parameters in your hands** — score thresholds, diff limits, revision rounds, all controllable through natural language

## All commands

```bash
ruyi do "goal"                   # the main command
ruyi do @file.md                 # read goal from file
ruyi do #123                     # do a GitHub issue
ruyi do #123 "extra context"     # issue + instructions
ruyi do                          # re-run latest task
ruyi tasks                       # list all tasks
ruyi pdo "X" // "Y" // "Z"      # parallel execution
ruyi modes                       # list saved modes
ruyi import mode.txt             # import a mode
ruyi clean                       # remove ruyi-generated files
ruyi update                      # update ruyi
ruyi version                     # show version
```

## Task file

Every `ruyi do` generates a `.ruyi-tasks/` folder with a task file — human-readable, editable, git-tracked:

```racket
(ruyi-task
  (goal "improve documentation")
  (validate #f)
  (max-revisions 2)
  (min-score 8)
  (judgement "focus on clarity for HN readers")
  (subtasks
    ("Write bilingual README")
    ("Add architecture diagram")))
```

Edit it, re-run with `ruyi do`. Share with your team.

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff limits, dual-agent review) are too important to leave to an LLM. The engine is ~2,000 lines of Racket — readable in 10 minutes. You never write Racket — it's just the runtime.

</details>

## License

MIT

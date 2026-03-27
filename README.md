# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

[中文文档](README.zh-CN.md)

**Tell Claude what you want. Ruyi makes sure only clean changes ship.**

Every AI change either commits clean or reverts completely — you review one PR, not a half-applied disaster. The safety contract is code, not prompts.

## 20 seconds

```bash
cd your-project
ruyi do "add CLI support"
```

That's it. Ruyi auto-detects your project, breaks the goal into subtasks, implements each one, runs your tests, commits what passes, reverts what fails. You get one clean PR at the end.

Want to do two things at once? Open another terminal:

```bash
ruyi do "fix auth bug"          # parallel, in its own worktree
```

Or launch multiple in one shot:

```bash
ruyi pdo "add tests" // "translate README" // "fix auth bug"
```

## How it works

```
     ┌─────────────────┐
     │  ruyi do "goal"  │  Describe what you want
     └────────┬────────┘
              ▼
     ┌──────────────────┐
     │  Break into       │
     │  subtasks (Claude) │
     └────────┬─────────┘
              ▼
     ┌──────────────────┐
     │  Implement next   │◄──────────────────┐
     │  subtask (Claude)  │                   │
     └────────┬─────────┘                   │
              ▼                             │
     ┌──────────────────┐                   │
     │  Run tests/build  │                   │
     └───┬──────────┬───┘                   │
    pass ▼          ▼ fail                  │
   ┌──────────┐ ┌───────────┐              │
   │  commit  │ │  revert   │              │
   │ (atomic) │ │ (full)    │              │
   └────┬─────┘ └─────┬─────┘              │
        └──────────────┴────────────────────┘
              ▼
     ┌──────────────────┐
     │ One clean PR      │
     └──────────────────┘
```

The Racket engine controls every step. Claude never decides whether to commit or revert — the loop does, based on your test suite.

## Install

You need [Claude Code](https://claude.ai/code). Paste this into it:

> Install ruyi for me: https://github.com/ZhenchongLi/ruyi/blob/main/INSTALL-PROMPT.md

Claude Code will detect your environment, install dependencies, and set up everything. Works on macOS, Linux, with or without brew, in mainland China or anywhere else.

Run `ruyi update` anytime to pull latest.

<details>
<summary>Shell script (alternative)</summary>

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

</details>

## Commands

```bash
ruyi do "goal"                   # do something — the main command
ruyi do @file.md                 # read goal from file
ruyi do #123                     # do a GitHub issue
ruyi do #123 "extra context"     # issue + additional instructions
ruyi do                          # re-run latest task
ruyi tasks                       # list all tasks
ruyi pdo "X" // "Y" // "Z"      # do multiple things in parallel
ruyi modes                       # list saved modes
ruyi import mode.txt             # import a mode from file
ruyi clean                       # remove ruyi-generated files
ruyi init [path]                 # manually init project (usually auto)
ruyi update                      # update ruyi
ruyi version                     # show version
```

## Modes

After a successful `ruyi do`, you're prompted to save the goal as a **reusable mode**. Modes are plain text files in `.ruyi-modes/`:

```
$ ruyi do "add comprehensive test coverage"
...
Done: evolve/freestyle/0326 (kept 5)
PR: https://github.com/...

Save as reusable mode? Name (Enter to skip): test-coverage
Saved: .ruyi-modes/test-coverage.txt
Re-run anytime: ruyi run test-coverage
```

Share modes with your team — just commit `.ruyi-modes/` or use `ruyi import`.

## The safety contract

- **Atomic commit-or-revert** — every subtask either passes and commits, or reverts completely. No broken intermediate state.
- **Worktree isolation** — each `ruyi do` runs in its own git worktree. Your working directory is never touched. Run as many in parallel as you want.
- **Diff size limits** (default 500 lines) — no runaway changes.
- **Forbidden files** — won't touch what you protect.
- **One clean PR** — you review a single diff at the end.

All enforced by the [Racket engine](engine.rkt), not by prompts.

## Supported languages

TypeScript, JavaScript, Python, C#/.NET, Rust, Go, Racket — anything with a `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, or equivalent. Ruyi auto-detects language, build tool, and test framework.

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff size limits, forbidden file enforcement) are too important to leave to an LLM. The entire engine is ~2,000 lines of Racket — you can read the core loop ([`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)) in about 10 minutes. You never write or see Racket — it's just the runtime.

</details>

## License

MIT

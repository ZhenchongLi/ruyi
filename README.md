# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

**Every AI change either commits clean or reverts completely.** No half-applied changes, no broken intermediate state, ever. You review one PR, not a disaster.

Ruyi runs Claude Code in a loop — each iteration is atomic. Pass tests? Committed. Fail? Gone, as if it never happened.

> "Improve test coverage." Ruyi writes 14 tests across 6 files. Keeps the 11 that pass, reverts the 3 that don't. You review one clean diff.
>
> "Fix GitHub issues." Ruyi picks up open issues one by one, implements a fix, runs your test suite. Passing fix gets committed with the issue linked. Failing fix gets reverted. You wake up to closed issues and a single PR.

## Quick Start

**Option A — clone and alias** (3 commands, nothing hidden):

```bash
brew install minimal-racket
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi
echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> ~/.zshrc && source ~/.zshrc
```

**Option B — install script** ([read it first](https://github.com/ZhenchongLi/ruyi/blob/main/install.sh) — it just does the three steps above):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

Then:

```bash
cd your-project          # any language, any framework
ruyi init                # auto-detects everything, asks what you want
ruyi                     # start evolving
```

## Battle-tested

Every claim is verifiable — click the commits:

- **This README** — written by Ruyi's `evolve-doc` mode. 24 iterations: 7 kept, 17 discarded. Every kept commit is a real diff on GitHub:
  - [`5044d5d`](https://github.com/ZhenchongLi/ruyi/commit/5044d5d) — first kept draft (score: 7.6)
  - [`eff19ab`](https://github.com/ZhenchongLi/ruyi/commit/eff19ab) — biggest single jump (score: 8.7)
  - [`7af276c`](https://github.com/ZhenchongLi/ruyi/commit/7af276c) — latest iteration (score: 8.7)
- **Ruyi's own engine** — `coverage` mode writing tests for the core Racket modules ([iteration log](evolution-log.tsv))
- **Private TypeScript/React apps** — 20-iteration `coverage` sessions across stores, database repos, hooks, and lib modules. The same atomic guarantee held across pnpm build + test validation.

| Metric | Value |
|--------|-------|
| Total iterations logged | 24 |
| Kept / Discarded | 7 / 17 |
| Score range | 7.4 → 8.7 |
| Broken main branches | 0 |

Most AI output isn't good enough. Ruyi's job is to keep only what passes.

## What does `init` look like?

```
$ cd my-react-app
$ ruyi init

=== Ruyi Init ===

Detected: TypeScript (react), build: pnpm
Path:     /Users/you/my-react-app

What would you like ruyi to do?
Examples:
  - Improve test coverage
  - Fix GitHub issues
  - Refactor large files
  - Translate docs to English
  - Any goal you have in mind

> Improve test coverage

Plan: Write tests for untested source files, prioritizing core logic
Mode: coverage

Created: .ruyi.rkt

Ready! Run:
  ruyi
```

Zero config files to write. Ruyi detects your language, build tool, and test framework automatically. Works with TypeScript, Python, C#/.NET, Rust, Go, and Racket — if it has a `package.json`, `pyproject.toml`, `Cargo.toml`, or equivalent, Ruyi picks it up.

## What a run looks like

A real `coverage` run on a TypeScript project. Each iteration is independent — a failure in iteration 2 doesn't affect the code committed in iteration 1:

<p align="center">
  <img src="demo.svg" alt="Ruyi coverage run — iterations commit or revert atomically" width="680">
</p>

**Your git log at the end** — only passing iterations survive:

```
$ git log --oneline ruyi/coverage-session

e82b4f0 test(billing): add 8 tests for src/api/billing.ts
a3f9c21 test(session): add 14 tests for src/auth/session.ts
  ↑ failed attempts leave no trace
```

## How it works

Ruyi is a deterministic control loop that delegates creative work to Claude Code. Each iteration: pick a task, let Claude write code, run your tests. Pass? `git commit`. Fail? `git revert`. Next iteration.

**Safety guarantees** — this is what separates Ruyi from "just run Claude in a loop":
- **Atomic commit-or-revert** — every iteration either passes tests and commits, or reverts completely. No broken intermediate state, ever.
- Always works on a branch — never touches main
- Enforces diff size limits (default 500 lines) — no runaway changes
- Respects forbidden files — won't touch what you protect
- You review one clean PR at the end

## Modes

Describe your goal in plain English during `ruyi init` — Ruyi selects the right mode automatically.

| Mode | You say | What happens |
|------|---------|-------------|
| `coverage` | "Improve test coverage" | Writes tests file-by-file, commits each passing test suite |
| `issue` | "Fix GitHub issues" | Picks up open issues, implements + tests a fix per iteration |
| `freestyle` | "Translate docs to Spanish" | Any goal — validated by your test suite each iteration |

<details>
<summary>More modes: refactor, filesize, evolve-doc</summary>

| Mode | You say | What happens |
|------|---------|-------------|
| `refactor` | "Refactor large files" | Simplifies complex code one file at a time, build must pass |
| `filesize` | "Break up large files" | Splits oversized files into modules + updates imports |
| `evolve-doc` | "Improve the README" | Iterates docs via LLM-as-Judge scoring (this README was written this way) |

</details>

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff size limits, forbidden file enforcement) are too important to leave to an LLM. The entire engine is ~2,000 lines of Racket — you can read the core loop ([`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)) in about 10 minutes. The install script adds a `ruyi` alias — you never need to type `racket` directly.

</details>

## Requirements

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Git
- [Racket](https://racket-lang.org/) 9.0+ (installed automatically by `install.sh`, or `brew install minimal-racket`)

## License

MIT

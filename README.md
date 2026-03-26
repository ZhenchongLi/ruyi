# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

**Claude broke main again? Not with Ruyi.** Every AI change either commits clean or reverts completely — you review one PR, not a half-applied disaster.

The control loop is deterministic Racket, not an LLM — safety guarantees are code, not prompts. ~2,000 lines you can [read yourself](engine.rkt).

## How it works

```
                  ┌─────────────────┐
                  │   ruyi init     │  You describe a goal in plain English
                  └────────┬────────┘
                           ▼
              ┌────────────────────────┐
              │  Pick next target      │  file, issue, or doc
              │  (deterministic loop)  │◄─────────────────────┐
              └────────────┬───────────┘                      │
                           ▼                                  │
              ┌────────────────────────┐                      │
              │  Claude Code writes    │                      │
              │  code / tests / docs   │                      │
              └────────────┬───────────┘                      │
                           ▼                                  │
              ┌────────────────────────┐                      │
              │  Run tests / build     │                      │
              └──────┬─────────┬───────┘                      │
                     │         │                              │
                pass ▼         ▼ fail                         │
          ┌──────────────┐ ┌──────────────┐                   │
          │ git commit   │ │ git revert   │  branch unchanged │
          │ (atomic)     │ │ (full reset) │                   │
          └──────┬───────┘ └──────┬───────┘                   │
                 │                │                           │
                 └────────────────┴───────────────────────────┘
                           ▼
              ┌────────────────────────┐
              │  One clean PR to review│
              └────────────────────────┘
```

The Racket engine controls every step. Claude never decides whether to commit or revert — the loop does, based on your test suite. That's the safety guarantee.

## Modes

Describe your goal in plain English during `ruyi init` — Ruyi selects the right mode automatically.

| Mode | You say | What happens |
|------|---------|-------------|
| `coverage` | "Improve test coverage" | Writes tests file-by-file, commits each passing test suite |
| `issue` | "Fix GitHub issues" | Picks up open issues, implements + tests a fix per iteration |
| `refactor` | "Refactor large files" | Simplifies one file at a time, build must pass |
| `filesize` | "Break up large files" | Splits oversized files into modules + updates imports |
| `freestyle` | "Translate docs to Spanish" | Any goal — validated by your test suite each iteration |
| `evolve-doc` | "Improve the README" | Iterates docs via LLM-as-Judge scoring |

## What a run looks like

A real `coverage` run on a TypeScript project. Each iteration is independent — a failure doesn't affect previously committed code:

```
 ╭─────────────────────────────────────────────────╮
 │  Ruyi — coverage session                        │
 │  Project: my-app (TypeScript, pnpm)             │
 │  Branch:  ruyi/coverage-session                 │
 ╰─────────────────────────────────────────────────╯

 Iteration 1 ─────────────────────────────────────
   Target: src/auth/session.ts (0% coverage)
   Claude: writing tests...
   Run:    pnpm test -- session.test.ts
   Result: ✅ 14 tests pass
   Commit: a3f9c21 test(session): add 14 tests

 Iteration 2 ─────────────────────────────────────
   Target: src/api/billing.ts (12% coverage)
   Claude: writing tests...
   Run:    pnpm test -- billing.test.ts
   Result: ❌ 3 tests fail (mock DB mismatch)
   Revert: changes discarded, branch unchanged

 Iteration 3 ─────────────────────────────────────
   Target: src/api/billing.ts (12% coverage)
   Claude: writing tests (fresh attempt)...
   Run:    pnpm test -- billing.test.ts
   Result: ✅ 8 tests pass
   Commit: e82b4f0 test(billing): add 8 tests

 ── Session complete: 2 committed, 1 reverted ──
```

**Your git log at the end** — only passing iterations survive:

```
$ git log --oneline ruyi/coverage-session

e82b4f0 test(billing): add 8 tests for src/api/billing.ts
a3f9c21 test(session): add 14 tests for src/auth/session.ts
  ↑ failed attempts leave no trace
```

> "Improve test coverage." Ruyi writes 14 tests across 6 files. Keeps the 11 that pass, reverts the 3 that don't. You review one clean diff.
>
> "Fix GitHub issues." Ruyi picks up open issues one by one, implements a fix, runs your test suite. Passing fix gets committed with the issue linked. Failing fix gets reverted. You wake up to closed issues and a single PR.

## Quick Start

**Install Racket + clone Ruyi (3 commands):**

macOS:
```bash
brew install minimal-racket
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi
echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> ~/.zshrc && source ~/.zshrc
```

<details>
<summary>Linux (Ubuntu/Debian / Fedora)</summary>

**Ubuntu/Debian:**
```bash
sudo apt-get install racket
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi
echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> ~/.bashrc && source ~/.bashrc
```

**Fedora:**
```bash
sudo dnf install racket
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi
echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> ~/.bashrc && source ~/.bashrc
```

</details>

<details>
<summary>Prefer a one-liner? Install script</summary>

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"
```

[Read the script first](https://github.com/ZhenchongLi/ruyi/blob/main/install.sh) — it does exactly the 3 steps above: installs Racket if missing, clones the repo, adds the alias. After running, `source` your shell rc or open a new terminal.

</details>

**Then — start evolving:**

```bash
cd your-project          # any language, any framework
ruyi init                # auto-detects everything, asks what you want
ruyi                     # start evolving
```

Each passing iteration commits, each failure reverts. You review one PR when it's done.

## The safety contract

This is what separates Ruyi from "just run Claude in a loop":

- **Atomic commit-or-revert** — every iteration either passes and commits, or reverts completely. No broken intermediate state, ever.
- **Branch isolation** — never touches main. You merge when you're ready.
- **Diff size limits** (default 500 lines) — no runaway changes.
- **Forbidden files** — won't touch what you protect.
- **One clean PR** — you review a single diff at the end.

All enforced by the [Racket engine](engine.rkt), not by prompts.

## Proof it works

**28 iterations, 18 kept, 10 discarded, 0 broken mains.** [See every commit →](https://github.com/ZhenchongLi/ruyi/commits/main/?search=evolve)

This README was evolved by Ruyi running in `evolve-doc` mode on itself. The [evolution log](evolution-log.tsv) is checked into the repo — every iteration is timestamped with its score and keep/discard decision. Here's a sample:

```
timestamp                 status   description
2026-03-26T17:27:26       discard  Score 7.4 < 8.0 threshold
2026-03-26T17:29:55       keep     Score 8.2 — committed fe74537
2026-03-26T17:32:30       discard  Score 7.4 < 8.0 threshold
2026-03-26T17:36:15       keep     Score 8.3 — committed 29a2513
```

Each `evolve(doc)` commit in the [git history](https://github.com/ZhenchongLi/ruyi/commits/main/) was made by Ruyi's loop. Each discarded iteration left no trace on the branch. The proof isn't a claim — it's `git log`.

**On the engine:** Ruyi's own test suite was bootstrapped by running `ruyi` in `coverage` mode on this repo. Same loop, same safety guarantees.

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

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff size limits, forbidden file enforcement) are too important to leave to an LLM. The entire engine is ~2,000 lines of Racket — you can read the core loop ([`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)) in about 10 minutes. The install script adds a `ruyi` alias — you never need to type `racket` directly.

</details>

## Requirements

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Git
- [Racket](https://racket-lang.org/) 9.0+ (installed automatically by `install.sh`)

## License

MIT

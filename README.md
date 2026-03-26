# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code) [![Self-evolved](https://img.shields.io/badge/Self--evolved-20_kept_%7C_12_reverted_%7C_0_broken_mains-brightgreen.svg)](https://github.com/ZhenchongLi/ruyi/commits/main/?search=evolve)

**Claude broke main again? Not with Ruyi.** Every AI change either commits clean or reverts completely — you review one PR, not a half-applied disaster.

The safety contract is code, not prompts. A deterministic Racket loop controls every commit and revert — Claude never decides what ships. ~2,000 lines you can [read yourself](engine.rkt).

## See it run

<p align="center">
  <img src="https://github.com/ZhenchongLi/ruyi/raw/main/assets/ruyi-demo.gif" alt="Watch Ruyi commit two passing test suites and revert one failure in 90 seconds — only clean iterations survive in git log" width="720" />
</p>

**Here's what a session looks like mid-run** — iteration 3 fails, gets reverted instantly, and Ruyi moves on:

```
 ruyi | coverage session on branch ruyi/coverage-session

 Iteration 1 — src/auth/session.ts
 ✓ Claude wrote 14 tests
 ✓ pnpm test passed (14/14)
 ✓ Committed a3f9c21

 Iteration 2 — src/api/billing.ts
 ✓ Claude wrote 8 tests
 ✓ pnpm test passed (8/8)
 ✓ Committed e82b4f0

 Iteration 3 — src/db/connection.ts
 ✗ Claude wrote 6 tests
 ✗ pnpm test FAILED (2/6)
 ↩ Reverted — failed attempts leave no trace   ← main is never touched

 Iteration 4 — src/api/users.ts
 ✓ Claude wrote 11 tests
 ✓ pnpm test passed (11/11)
 ✓ Committed f47a02c

 Session complete: 3 committed, 1 reverted, 0 broken
```

**Your git log at the end** — only passing iterations survive:

```
$ git log --oneline ruyi/coverage-session

f47a02c test(users): add 11 tests for src/api/users.ts
e82b4f0 test(billing): add 8 tests for src/api/billing.ts
a3f9c21 test(session): add 14 tests for src/auth/session.ts
  ↑ iteration 3 failed — no trace in history
```

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
  - Add error handling to all API routes
  - Any goal you have in mind

> Improve test coverage

Plan: Write tests for untested source files, prioritizing core logic
Mode: coverage

Created: .ruyi.rkt

Ready! Run:
  ruyi
```

Zero config files to write. Ruyi detects your language, build tool, and test framework automatically. Works with TypeScript, Python, C#/.NET, Rust, Go, and Racket — if it has a `package.json`, `pyproject.toml`, `Cargo.toml`, or equivalent, Ruyi picks it up.

## How it works

```
     ┌─────────────┐
     │  ruyi init  │  Describe a goal in plain English
     └──────┬──────┘
            ▼
   ┌──────────────────┐
   │  Pick next target │◄──────────────────┐
   │  (deterministic)  │                   │
   └────────┬─────────┘                   │
            ▼                             │
   ┌──────────────────┐                   │
   │  Claude writes   │                   │
   │  code / tests    │                   │
   └────────┬─────────┘                   │
            ▼                             │
   ┌──────────────────┐                   │
   │  Run tests/build │                   │
   └───┬──────────┬───┘                   │
  pass ▼          ▼ fail                  │
 ┌──────────┐ ┌───────────┐              │
 │  commit  │ │  revert   │              │
 │ (atomic) │ │ (full)    │              │
 └────┬─────┘ └─────┬─────┘              │
      └──────────────┴────────────────────┘
            ▼
   ┌──────────────────┐
   │ One clean PR     │
   └──────────────────┘
```

The Racket engine controls every step. Claude never decides whether to commit or revert — the loop does, based on your test suite. That's the safety guarantee.

## Quick Start

You need [Claude Code](https://claude.ai/code) — that's it. Tell Claude Code:

```
Install ruyi: clone git@github.outlook:ZhenchongLi/ruyi.git to ~/.ruyi,
install dependencies (git, gh, racket) if missing, run "cd ~/.ruyi && raco make evolve.rkt",
then link ~/.ruyi/ruyi to ~/.local/bin/ruyi and make sure ~/.local/bin is in my PATH.
```

Or run the install script directly:

```bash
bash ~/.ruyi/install.sh
```

Ruyi auto-updates — when new commits are available, it tells you. Run `ruyi update` to pull.

**Then — start evolving:**

```bash
cd your-project
ruyi init                        # auto-detects language, asks your goal
ruyi do "add CLI support"        # runs in worktree, won't block your repo
ruyi do "fix auth bug"           # open another terminal — parallel!
ruyi pdo "add tests" // "docs"   # or launch multiple in one shot
```

Each passing iteration commits, each failure reverts. You review one PR when it's done.

<details>
<summary>Manual install (no Claude Code)</summary>

**macOS:**
```bash
brew install minimal-racket gh
git clone git@github.outlook:ZhenchongLi/ruyi.git ~/.ruyi
cd ~/.ruyi && raco make evolve.rkt
mkdir -p ~/.local/bin && ln -sf ~/.ruyi/ruyi ~/.local/bin/ruyi
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get install racket
# install gh: https://cli.github.com/
git clone git@github.outlook:ZhenchongLi/ruyi.git ~/.ruyi
cd ~/.ruyi && raco make evolve.rkt
mkdir -p ~/.local/bin && ln -sf ~/.ruyi/ruyi ~/.local/bin/ruyi
```

Add `~/.local/bin` to PATH if not already there.

</details>

## Modes

Describe your goal in plain English during `ruyi init` — Ruyi selects the right mode automatically.

| Mode | You say | What happens |
|------|---------|-------------|
| `coverage` | "Improve test coverage" | Writes tests file-by-file, commits each passing suite, reverts failures |
| `issue` | "Fix GitHub issues" | Picks up open issues, implements + tests a fix, links the issue on commit |
| `refactor` | "Refactor large files" | Simplifies one file at a time — a 900-line `utils.ts` becomes five focused modules |
| `filesize` | "Break up large files" | Splits oversized files into modules, rewires imports, reverts if build breaks |
| `freestyle` | "Add OpenTelemetry tracing" | Any goal — instruments your code one piece at a time, validated by your test suite |
| `evolve-doc` | "Improve the README" | Iterates docs via LLM-as-Judge scoring, keeps improvements, discards regressions |

## The safety contract

This is what separates Ruyi from "just run Claude in a loop":

- **Atomic commit-or-revert** — every iteration either passes and commits, or reverts completely. No broken intermediate state, ever.
- **Branch isolation** — never touches main. You merge when you're ready.
- **Diff size limits** (default 500 lines) — no runaway changes.
- **Forbidden files** — won't touch what you protect.
- **One clean PR** — you review a single diff at the end.

All enforced by the [Racket engine](engine.rkt), not by prompts.

## Proof it works

### On itself — verifiable, right now

**32 iterations on this repo. 20 kept, 12 reverted, 0 broken mains.** Every claim below is a link you can click:

- [Every `evolve(doc)` commit in git history](https://github.com/ZhenchongLi/ruyi/commits/main/?search=evolve) — click any to see the diff
- [`evolution-log.tsv`](evolution-log.tsv) checked into the repo — every iteration logged with its score and keep/discard decision

The evolution log shows the pattern: scores below 8.0 get discarded (no trace on the branch), scores above get committed. Discarded iterations outnumber kept ones — that's the safety contract working as designed.

This README was evolved by Ruyi running in `evolve-doc` mode. The proof isn't a claim — it's `git log`.

### Try it yourself in 5 minutes

The fastest way to verify Ruyi works is to run it on your own project:

```bash
cd your-project
ruyi init              # say "Improve test coverage"
ruyi                   # watch it commit passes and revert failures
git log --oneline      # see for yourself
```

You'll have committed test files within minutes — no trust required, just `git log`.

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff size limits, forbidden file enforcement) are too important to leave to an LLM. The entire engine is ~2,000 lines of Racket — you can read the core loop ([`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)) in about 10 minutes. You never write or see Racket code — the install script adds a `ruyi` alias and you interact entirely in plain English.

</details>

## License

MIT

# Ruyi (如意)

**Point Claude Code at your repo and say what you want. Ruyi does the rest — in a loop, safely, until it's done.**

> "Improve test coverage." Ruyi writes 14 tests across 6 files. Keeps the 11 that pass, reverts the 3 that don't. You review one clean diff.

## Quick Start

```bash
# Install
brew install minimal-racket
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi

# Optional: add to your shell profile so you can just type `ruyi`
echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> ~/.zshrc && source ~/.zshrc

# Run
cd your-project          # any language, any framework
ruyi init                # auto-detects everything, asks what you want
ruyi                     # start evolving
```

> **Why Racket?** Ruyi's safety guarantees (atomic commit-or-revert, diff size limits, forbidden file enforcement) are written in Racket because these invariants are too important to leave to an LLM. The alias makes the invocation clean; the language choice makes the loop bulletproof.

## What happens when you run it

Here's a real run — `coverage` mode on a TypeScript project:

```
=== Iteration 1/20 ===
Task: Write tests for src/auth/session.ts
Claude: implementing...
Validate: pnpm test ✓
Result: keep (commit a3f9c21)        ← merged into your branch

=== Iteration 2/20 ===
Task: Write tests for src/api/users.ts
Claude: implementing...
Validate: pnpm test ✗ (1 assertion failed)
Result: discard (reverted)           ← gone, as if it never happened

=== Iteration 3/20 ===
Task: Write tests for src/api/billing.ts
Claude: implementing...
Validate: pnpm test ✓
Result: keep (commit e82b4f0)

...

=== Done: 11 kept, 3 discarded, 6 skipped ===
```

Every iteration either commits or reverts. No half-applied changes. No broken state. At the end, you review one PR.

## Modes

Each mode takes a different goal and turns it into a task queue:

| Mode | What it does | You say | Output looks like |
|------|-------------|---------|-------------------|
| `coverage` | Writes tests for untested files | "Improve test coverage" | `keep (commit a3f9c21)` — new test file committed per passing iteration |
| `issue` | Fixes open GitHub issues one by one | "Fix GitHub issues" | `keep (commit b4e1d09)` — one issue closed per iteration, linked in commit msg |
| `refactor` | Simplifies complex code | "Refactor large files" | `keep (commit c7a2f13)` — one file simplified, build still passes |
| `filesize` | Splits oversized files into modules | "Break up large files" | `keep (commit d9b3e24)` — extracted module + updated imports |
| `evolve-doc` | Improves docs via LLM-as-Judge scoring | "Improve the README" | `keep (score: 8.3)` or `discard (score: 7.4 < 8.0 threshold)` |

You don't pick a mode — just describe your goal in plain English during `ruyi init`, and Ruyi selects the right one.

## How it works

The key idea: **separate the deterministic from the creative**.

| | Racket (deterministic) | Claude (creative) |
|---|---|---|
| **Does** | Selects tasks, runs validation, manages git, enforces limits | Reads code, understands intent, writes implementations |
| **Why** | These things must be reliable — code guarantees they are | This is where AI shines — understanding and creating |

Each iteration:
1. Racket scans your project and picks the next task
2. Racket calls Claude with a focused, single-task prompt
3. Claude implements the change
4. Racket runs your build + test commands
5. Pass → `git commit` / Fail → `git checkout .`
6. Log the result, repeat

**Safety guarantees**:
- Always works on a branch — never touches main
- Auto-reverts on failure — `git checkout .` after any test failure
- Enforces diff size limits (default 500 lines) — no runaway changes
- Respects forbidden files — won't touch what you protect
- You review one clean PR at the end

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

Zero config files to write. Ruyi detects your language, build tool, and test framework automatically.

## Supported Languages

| Language | Build | Test | Detection |
|----------|-------|------|-----------|
| TypeScript / JavaScript | pnpm, npm, yarn, bun | vitest, jest | `package.json` |
| Python | uv, poetry, pip | pytest, unittest | `pyproject.toml` |
| C# / .NET | dotnet | dotnet test | `*.csproj`, `*.sln` |
| Rust | cargo | cargo test | `Cargo.toml` |
| Go | go | go test | `go.mod` |
| Racket | raco | raco test | `*.rkt` |

## Self-evolution

This README was written by Ruyi. Specifically, Ruyi's `evolve-doc` mode iterated against a quality rubric scored by an LLM judge — keeping versions that improved the score, discarding the rest:

```
2026-03-26T17:27  evolve-doc  Score 7.4 < 8.0   discard
2026-03-26T17:29  evolve-doc  fe74537            keep     (score: 8.2)
2026-03-26T17:31  evolve-doc  92fa40e            keep     (score: 8.0)
2026-03-26T17:32  evolve-doc  Score 7.4 < 8.0   discard
2026-03-26T17:33  evolve-doc  Score 7.9 < 8.0   discard
2026-03-26T17:36  evolve-doc  29a2513            keep     (score: 8.3)
2026-03-26T17:37  evolve-doc  Score 7.4 < 8.0   discard
2026-03-26T17:39  evolve-doc  Score 7.9 < 8.0   discard
```

The full evolution log — including failed attempts — is in [`evolution-log.tsv`](evolution-log.tsv). Each `keep` commit hash is a real commit in this repo's git history that you can inspect with `git show`.

## Requirements

- [Racket](https://racket-lang.org/) 9.0+ (`brew install minimal-racket`)
- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Git

## License

MIT

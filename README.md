# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code)

**Every change either commits clean or reverts completely. You review one PR, not a disaster recovery incident.**

Ruyi runs Claude Code in a loop with an atomic guarantee: each iteration passes your tests and commits, or gets reverted as if it never happened. No half-applied changes. No broken intermediate state. Ever.

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

## What a run looks like

A real `coverage` run on a TypeScript project. Each iteration is independent — a failure in iteration 2 doesn't affect the code committed in iteration 1:

```
$ ruyi

=== Iteration 1/20 ===
Task: Write tests for src/auth/session.ts
Claude: implementing...
Validate: pnpm test ✓ (14 tests, 14 passed)
Result: keep (commit a3f9c21)        ← merged into your branch

=== Iteration 2/20 ===
Task: Write tests for src/api/users.ts
Claude: implementing...
Validate: pnpm test ✗ (1 assertion failed)
Result: discard (reverted)           ← gone, as if it never happened

=== Iteration 3/20 ===
Task: Write tests for src/api/billing.ts
Claude: implementing...
Validate: pnpm test ✓ (8 tests, 8 passed)
Result: keep (commit e82b4f0)

...

=== Done: 11 kept, 3 discarded, 6 skipped ===
```

**Before and after** — your git log at the end of a run:

```
$ git log --oneline ruyi/coverage-session

e82b4f0 test(billing): add 8 tests for src/api/billing.ts
a3f9c21 test(session): add 14 tests for src/auth/session.ts
  ↑ only passing iterations survive — failed attempts leave no trace
```

## How it works

```
  "Improve test coverage"
         │
         ▼
  ┌─────────────┐      ┌──────────────┐      ┌────────────┐
  │  Pick task   │ ───► │  Claude Code  │ ───► │  Run tests  │
  │  (Racket)    │      │  writes code  │      │  (your CI)  │
  └─────────────┘      └──────────────┘      └──────┬─────┘
         ▲                                      ┌────┴────┐
         │                                   pass?      fail?
         │                                     │          │
         │                                git commit  git revert
         │                                     │          │
         └──────── next iteration ◄────────────┴──────────┘
```

The core idea: **deterministic orchestration in a compiled language, creative work delegated to the LLM**. The control loop, git operations, and safety invariants are Racket — pattern matching and immutable data structures make them easy to audit. Claude handles what AI is good at: reading code, understanding intent, writing implementations.

**Safety guarantees** — this is what separates Ruyi from "just run Claude in a loop":
- **Atomic commit-or-revert** — every iteration either passes tests and commits, or reverts completely. No broken intermediate state, ever.
- Always works on a branch — never touches main
- Enforces diff size limits (default 500 lines) — no runaway changes
- Respects forbidden files — won't touch what you protect
- You review one clean PR at the end

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

## Dogfooding: this README was written by Ruyi

The `evolve-doc` mode wrote this README. It iterated 20 times against a quality rubric scored by an LLM judge — keeping versions that beat the previous score, reverting the rest. The exact same commit-or-revert loop that writes your tests also wrote these words:

| What happened | Score | Commit |
|--------------|-------|--------|
| First accepted version | **8.3** | [`f293c4d`](https://github.com/ZhenchongLi/ruyi/commit/f293c4d) |
| Current version | **8.7** | [`eff19ab`](https://github.com/ZhenchongLi/ruyi/commit/eff19ab) |

20 iterations total, 13 discarded. Every commit hash in [`evolution-log.tsv`](evolution-log.tsv) links to the real diff on GitHub. Ruyi has also been used on its own codebase in `coverage` mode, writing tests for the core engine modules.

<details>
<summary>Why Racket?</summary>

Ruyi's safety guarantees (atomic commit-or-revert, diff size limits, forbidden file enforcement) are written in Racket because these invariants are too important to leave to an LLM. Pattern matching and immutable data structures make the control loop easy to audit. The install script adds a `ruyi` alias — you never need to type `racket` directly.

</details>

## Requirements

- [Claude Code](https://claude.ai/code) CLI installed and authenticated
- Git
- [Racket](https://racket-lang.org/) 9.0+ (installed automatically by `install.sh`, or `brew install minimal-racket`)

## License

MIT

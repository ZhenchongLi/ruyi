# Ruyi (如意)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Language: Racket](https://img.shields.io/badge/Language-Racket-9F1D20.svg)](https://racket-lang.org/) [![Claude Code](https://img.shields.io/badge/Powered_by-Claude_Code-orange.svg)](https://claude.ai/code) [![Self-evolved](https://img.shields.io/badge/Self--evolved-20_kept_%7C_12_reverted_%7C_0_broken_mains-brightgreen.svg)](https://github.com/ZhenchongLi/ruyi/commits/main/?search=evolve)

**Claude broke main again? Not with Ruyi.** Every AI change either commits clean or reverts completely — you review one PR, not a half-applied disaster.

The safety contract is code, not prompts. A deterministic Racket loop controls every commit and revert — Claude never decides what ships. ~2,000 lines you can [read yourself](engine.rkt).

## See it run

<p align="center">
  <img src="https://github.com/ZhenchongLi/ruyi/raw/main/assets/ruyi-demo.gif" alt="Watch Ruyi commit two passing test suites and revert one failure in 90 seconds — only clean iterations survive in git log" width="720" />
</p>

**Your git log at the end** — only passing iterations survive:

```
$ git log --oneline ruyi/coverage-session

e82b4f0 test(billing): add 8 tests for src/api/billing.ts
a3f9c21 test(session): add 14 tests for src/auth/session.ts
  ↑ failed attempts leave no trace
```

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

> **Prerequisites:** [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/overview) (installed and authenticated — `claude --version` to check), Git, and Racket (or Docker). That's it.

**You never write Racket — it's just the runtime.** The install takes ~2 minutes and adds a `ruyi` alias. You interact with Ruyi in plain English.

**macOS (3 commands):**
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
<summary>Don't want to install Racket? Use Docker</summary>

```bash
git clone https://github.com/ZhenchongLi/ruyi.git ~/ruyi
alias ruyi="docker run --rm -v \$(pwd):/work -v ~/.claude:/root/.claude -w /work ghcr.io/zhenchongli/ruyi"
```

Same behavior, zero runtime install. Requires Docker and Claude Code CLI on the host.

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

## Modes

Describe your goal in plain English during `ruyi init` — Ruyi selects the right mode automatically.

| Mode | You say | What happens |
|------|---------|-------------|
| `coverage` | "Improve test coverage" | Writes tests file-by-file, commits each passing test suite |
| `issue` | "Fix GitHub issues" | Picks up open issues, implements + tests a fix per iteration |
| `refactor` | "Refactor large files" | Simplifies one file at a time, build must pass |
| `filesize` | "Break up large files" | Splits oversized files into modules + updates imports |
| `freestyle` | "Add OpenTelemetry tracing to every endpoint" | Any goal — validated by your test suite each iteration |
| `evolve-doc` | "Improve the README" | Iterates docs via LLM-as-Judge scoring |

> **"Improve test coverage."** Ruyi writes tests across your codebase. Keeps the ones that pass, reverts the ones that don't. You review one clean diff.
>
> **"Fix GitHub issues."** Ruyi picks up open issues one by one, implements a fix, runs your test suite. Passing fix gets committed with the issue linked. Failing fix gets reverted. You wake up to closed issues and a single PR.
>
> **"Refactor large files."** A 900-line `utils.ts` becomes five focused modules — each extraction commits only if the build still passes.
>
> **"Break up large files."** A 2,000-line controller gets split into route-specific files with all imports rewired. Build breaks? Reverted instantly.
>
> **"Add OpenTelemetry tracing to every endpoint."** Freestyle mode — Ruyi instruments your API endpoints one at a time, committing each change only if your test suite still passes. You get incremental, safe progress toward any goal.

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
- [`evolution-log.tsv`](evolution-log.tsv) checked into the repo — every iteration timestamped with its score and keep/discard decision:

```
timestamp                 status   description
2026-03-26T17:27:26       discard  Score 7.4 < 8.0 threshold
2026-03-26T17:29:55       keep     Score 8.2 — committed fe74537
2026-03-26T17:32:30       discard  Score 7.4 < 8.0 threshold
2026-03-26T17:50:14       keep     Score 8.7 — committed eff19ab
```

This README was evolved by Ruyi running in `evolve-doc` mode. Each discarded iteration left no trace on the branch. The proof isn't a claim — it's `git log`.

### Try it yourself in 5 minutes

The fastest way to verify Ruyi works is to run it on your own project:

```bash
cd your-project
ruyi init              # say "Improve test coverage"
ruyi                   # watch it commit passes and revert failures
git log --oneline      # see for yourself
```

You'll have committed test files within minutes — no trust required, just `git log`.

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

<details>
<summary>Why Racket?</summary>

The safety invariants (atomic commit-or-revert, diff size limits, forbidden file enforcement) are too important to leave to an LLM. The entire engine is ~2,000 lines of Racket — you can read the core loop ([`engine.rkt`](engine.rkt) + [`evolve.rkt`](evolve.rkt) + [`git.rkt`](git.rkt)) in about 10 minutes. You never write or see Racket code — the install script adds a `ruyi` alias and you interact entirely in plain English.

</details>

## License

MIT

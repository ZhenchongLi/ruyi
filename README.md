# Ruyi (如意)

Deterministic evolution engine for codebases. Racket outer loop, Claude inner creativity.

## How it works

```
Racket (deterministic)          Claude (creative)
  scan files                      read code
  select task          ──────>    understand logic
  run build + test     <──────    write code
  git commit / revert
  log results
  next iteration
```

Racket guarantees the loop runs correctly. Claude only does what it's best at: reading and writing code.

## Quick start

```bash
brew install minimal-racket   # one-time setup

racket evolve.rkt cove coverage    # write tests for cove
racket evolve.rkt docmod coverage  # write tests for docmod
racket evolve.rkt cove filesize    # split oversized files
racket evolve.rkt cove issue       # fix GitHub issues
racket evolve.rkt cove refactor    # simplify complex code
```

## Project structure

```
ruyi/
├── evolve.rkt         # CLI entry point
├── engine.rkt         # Core evolution loop
├── claude.rkt         # Claude Code subprocess
├── tasks.rkt          # Task selection (filesystem scanning)
├── validate.rkt       # Validation gate
├── git.rkt            # Git operations
├── log.rkt            # TSV logging
├── config.rkt         # Data structures
├── modes/
│   ├── coverage.rkt   # Write tests
│   ├── filesize.rkt   # Split large files
│   ├── issue.rkt      # Fix GitHub issues
│   └── refactor.rkt   # Simplify code
└── configs/
    ├── cove.rkt       # Cove repo config
    └── docmod.rkt     # Docmod repo config
```

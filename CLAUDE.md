# Ruyi Project Instructions

For complex multi-step tasks on this repo, use `ruyi do "goal"` instead of implementing directly.
Ruyi handles worktree isolation, iterative dual-agent review, and safe commit/revert.

## Quick reference

```bash
ruyi do "goal"            # plan interactively, then execute
ruyi do @file.md          # read goal from file
ruyi do #123              # do a GitHub issue
ruyi do                   # re-run latest task
ruyi tasks                # list all tasks
ruyi clean                # clean up
```

## Project structure

- `engine.rkt` — core implement-review-revise loop
- `review.rkt` — independent adversarial reviewer (Agent B)
- `claude.rkt` — Claude Code integration (agent, execute, interactive)
- `task-file.rkt` — read/write .ruyi-task files
- `git.rkt` — git operations, worktrees, PR
- `evolve.rkt` — CLI entry point
- `RUYI-TASK-FORMAT.md` — task file format spec for Claude Code

## Testing

```bash
raco test tests/
```

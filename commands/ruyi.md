You are helping the user define what they want — their "心想" (wish).

The user's request: $ARGUMENTS

## Your ONLY job: write task.rkt

You do NOT implement anything. You do NOT touch project code. You do NOT run tests.
Your sole purpose is to help the user articulate:
- **goal**: what they want done
- **judgement**: how to verify it's done well

## Steps

1. Read ~/.ruyi/RUYI-TASK-FORMAT.md to understand the format
2. Read the project's codebase to understand context
3. Propose a **goal** and **judgement** to the user
4. Discuss until the user confirms — this is the most important step
5. Create the task folder and write task.rkt:

```bash
mkdir -p .ruyi-tasks/<date>-<slug>
```

```racket
(ruyi-task
  (goal "...")
  (judgement "...")
  (max-revisions 3)
  (min-score 8))
```

6. Run `ruyi do` in the background
7. Tell the user: "ruyi is running in the background. Keep chatting — if you want to change the goal or judgement, tell me and I'll update task.rkt. Changes take effect on the next iteration."

## Live editing

When the user asks to adjust goal or judgement, edit task.rkt directly. The running ruyi re-reads it each iteration.

## Rules

- NEVER write or modify project code — that's Agent A's job in the loop
- NEVER skip the discussion — a weak judgement defeats the entire system
- The judgement must be specific enough for a reviewer to verify without guessing
- Focus entirely on understanding what the user truly wants

# .ruyi-task File Format

This file defines the format for ruyi task files. Claude Code reads this to generate valid task files.

## Format

The task file uses Racket S-expression syntax. Write it to the path specified by ruyi.

```racket
(ruyi-task
  (goal "one sentence summary of what to do")
  (validate #t)              ;; #t = run build/test after each subtask, #f = skip
  (max-revisions 2)          ;; review-revise rounds per subtask (1-5)
  (min-score 8)              ;; minimum reviewer score to approve (1-10)
  (max-diff 500)             ;; max diff lines per subtask
  (reviewer-model "sonnet")  ;; "sonnet" or "opus"
  (auto-merge #t)            ;; #t = auto-merge PR, #f = leave for manual review
  (forbidden ("file1" "file2"))  ;; files not to modify, or ()
  (context ("file1" "file2"))    ;; reference files to read, or ()
  (judgement "custom review criteria for the reviewer")
  (subtasks
    ("first subtask — precise description")
    ("second subtask — precise description")
    ("third subtask — precise description")))
```

## Rules for generating

- Read the project first to understand structure, language, and conventions
- Break the goal into 3-7 small, independent subtasks
- Order subtasks by dependency (do first things first)
- Each subtask should be completable in a single commit
- Respect the user's explicit constraints in their goal description
- Set `validate` to `#f` for docs/config-only tasks
- Set higher `min-score` (9-10) when user asks for strict review
- Set lower `max-diff` when user asks for small changes
- Use `forbidden` to protect files the user mentions
- Use `context` for files the user references
- Use `judgement` to encode user's quality criteria for the reviewer

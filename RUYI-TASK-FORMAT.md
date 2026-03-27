# .ruyi-task File Format

The task file is the contract between Agent A (implementer) and Agent B (reviewer).

## Format

```racket
(ruyi-task
  (goal "what to do — clear, specific, complete")
  (judgement "how the reviewer should verify the work is done well")
  (max-revisions 3)
  (min-score 8))
```

## Fields

- **goal** — What Agent A should implement. Be precise and complete.
- **judgement** — How Agent B should verify and score. This is the most important field. Include:
  - What success looks like
  - What must compile / pass / not break
  - Specific quality criteria
  - Edge cases to check
- **max-revisions** — How many review-revise rounds (1-5, default 3)
- **min-score** — Minimum reviewer score to approve (1-10, default 8)

## Rules for generating

- Read the project first to understand structure, language, and conventions
- Focus on writing a clear goal and a thorough judgement
- The judgement MUST include project-specific verification criteria:
  - Build/compile must pass (detect from project: raco make, tsc, cargo build, go build, etc.)
  - Existing tests must not break (detect from project: raco test, pytest, jest, cargo test, etc.)
  - Linting or CI checks if present
- The judgement should be specific enough that a reviewer can verify without guessing
- A weak judgement (empty or vague) means the reviewer can't catch real issues

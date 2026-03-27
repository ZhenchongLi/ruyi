# Ruyi Tests Itself / 如意自测记

> Ruyi ran `ruyi do` on its own codebase to add tests — and the dual-agent review loop caught 4 real bugs in the process.
>
> 如意用 `ruyi do` 给自己加测试，双代理审查循环在过程中发现了 4 个真实 bug。

## Process Overview / 流程概览

### The Goal / 目标

We pointed ruyi at itself: `ruyi do "Add tests for task-file.rkt covering read, write round-trip, slugify, and done.txt"`. The tool that orchestrates code changes was now the codebase being changed.

我们让如意指向自己：用 `ruyi do` 给 `task-file.rkt` 添加测试，覆盖读取、写入往返、slugify 和 done.txt。编排代码变更的工具，此刻成了被变更的代码。

### How the Dual-Agent Loop Works / 双代理循环如何运作

Ruyi splits every task into subtasks, then runs each through an **implement → review → decide** loop:

如意将每个任务拆分为子任务，然后逐个通过 **实现 → 审查 → 决策** 循环：

```
┌─────────────────────────────────────────────┐
│  ruyi engine (engine.rkt)                   │
│                                             │
│  for each subtask:                          │
│    1. Agent A (Claude Code, full agent)     │
│       implements the change                 │
│                                             │
│    2. git add -A  (stage for diff)          │
│                                             │
│    3. Safety checks:                        │
│       - forbidden files untouched?          │
│       - diff size within limit?             │
│                                             │
│    4. Build & test commands run             │
│                                             │
│    5. Agent B (independent Claude instance) │
│       reviews the diff adversarially        │
│       — sees ONLY diff + task description   │
│       — never sees Agent A's reasoning      │
│                                             │
│    6. ruyi decides:                         │
│       score >= min  → commit                │
│       score < min   → revert + revise       │
│       max attempts  → reject or best-effort │
└─────────────────────────────────────────────┘
```

**Agent A** (the implementer) runs as a full Claude Code agent — it can read files, write code, and execute commands. But it is forbidden from running git commands; ruyi controls the commit lifecycle.

**Agent A**（实现者）以完整的 Claude Code 代理模式运行——可以读文件、写代码、执行命令。但禁止运行 git 命令；如意控制提交生命周期。

**Agent B** (the reviewer) is adversarial by design. It receives only the git diff and the task description — never the implementer's plan, reasoning, or conversation history. Its prompt demands at least 2 issues per review and penalizes leniency. This information barrier is critical: without it, the reviewer would inherit the implementer's blind spots.

**Agent B**（审查者）天然是对抗性的。它只接收 git diff 和任务描述——从不看到实现者的计划、推理或对话历史。它的提示要求每次审查至少找出 2 个问题，并惩罚宽松评分。这道信息屏障至关重要：没有它，审查者会继承实现者的盲点。

**Ruyi** (the engine) is the decision-maker. It never generates code. It reads the reviewer's score, decides to commit, revise, or reject, and reformulates feedback in its own voice before passing it back to Agent A. The implementer never sees the reviewer's raw output — this prevents gaming.

**如意**（引擎）是决策者。它从不生成代码。它读取审查者的评分，决定提交、修订还是拒绝，并用自己的声音重新表述反馈后再传回 Agent A。实现者永远看不到审查者的原始输出——这防止了博弈。

### What Happened When Ruyi Tested Itself / 自测时发生了什么

When Agent A wrote the first round of tests for `task-file.rkt`, several tests failed immediately — not because the tests were wrong, but because they exposed real bugs that had gone unnoticed:

当 Agent A 为 `task-file.rkt` 编写第一轮测试时，好几个测试立即失败——不是因为测试写错了，而是因为它们暴露了之前未被发现的真实 bug：

1. **Subtask list parsing** — Claude Code generated task files with `(subtasks ("a") ("b") ("c"))`, but the parser's `get-list` only read the first element via `cadr`, silently dropping the rest. Every multi-step task was losing subtasks.

   **子任务列表解析** — Claude Code 生成的任务文件格式为 `(subtasks ("a") ("b") ("c"))`，但解析器的 `get-list` 通过 `cadr` 只读取第一个元素，静默丢弃其余部分。每个多步骤任务都在丢失子任务。

   ```racket
   ;; Before (task-file.rkt, get-list): took only the first element
   (define (get-list key)
     (define pair (assq key fields))
     (if pair
         (let ([val (cadr pair)])        ; ← only first element
           (if (list? val) val (list val)))
         '()))

   ;; After: handles (key ("a") ("b") ("c")) by mapping over all elements
   (define (get-list key)
     (define pair (assq key fields))
     (if pair
         (let ([rest (cdr pair)])
           (cond
             [(and (pair? (car rest))
                   (> (length rest) 1))
              (map (lambda (item)         ; ← collects all elements
                     (if (pair? item) (car item) item))
                   rest)]
             [(pair? (car rest)) (car rest)]
             [else (list (car rest))]))
         '()))
   ```

2. **Boolean `#f` handling** — `(auto-merge #f)` was treated as missing because the parser used `#f` as both the "not found" sentinel and a legitimate value. Explicit opt-outs were silently converted to defaults (`#t`).

   **布尔 `#f` 处理** — `(auto-merge #f)` 被当作缺失处理，因为解析器同时用 `#f` 作为"未找到"哨兵值和合法值。显式的关闭选项被静默转换为默认值（`#t`）。

   ```racket
   ;; Before: #f meant both "not found" and "explicitly false"
   (define (get key [default #f])
     (define pair (assq key fields))
     (if pair (cadr pair) default))
   ;; So (auto-merge #f) returned #f, then:
   (let ([v (get 'auto-merge)]) (if (eq? v #f) #t v))  ; ← #f → #t !

   ;; After: gensym sentinel distinguishes missing from explicit #f
   (define MISSING (gensym 'missing))
   (define (get key [default MISSING])
     (define pair (assq key fields))
     (if pair (cadr pair) default))
   (define (get-bool key default)
     (define v (get key))
     (if (eq? v MISSING) default v))     ; ← only defaults when truly missing
   ```

3. **Engine failed to stage new files before diffing** — When Agent A created new test files, they remained untracked. Ruyi's `git diff HEAD` saw nothing, so the reviewer received an empty diff and rejected the work — even though the implementation was correct. The fix added `git add -A` in `engine.rkt` after implementation, before safety checks and review.

   **引擎在 diff 前未暂存新文件** — 当 Agent A 创建新的测试文件时，这些文件处于未跟踪状态。如意的 `git diff HEAD` 什么也看不到，因此审查者收到空 diff 并拒绝了工作——尽管实现本身是正确的。修复方法是在 `engine.rkt` 中，实现完成后、安全检查和审查之前，添加 `git add -A`。

   ```racket
   ;; Added to engine.rkt after Agent A implements, before review:
   ;; 2b. Stage all changes (so untracked new files show in diff)
   (with-handlers ([exn:fail? (lambda (_) (void))])
     (shell! repo "git" "add" "-A"))
   ```

4. **Agent A running git commands independently** — A separate but related problem: Agent A sometimes ran `git add` or `git commit` on its own during implementation, also causing ruyi's `git diff HEAD` to return empty. While bug #3 was ruyi's own staging omission, this was an agent discipline issue. The fix added an explicit "no git commands" rule to all 6 mode prompt files.

   **Agent A 擅自执行 git 命令** — 一个独立但相关的问题：Agent A 在实现过程中有时自行执行 `git add` 或 `git commit`，同样导致如意的 `git diff HEAD` 返回空内容。虽然 bug #3 是如意自身的暂存遗漏，这个则是代理纪律问题。修复方法是在全部 6 个模式提示文件中添加明确的"禁止 git 命令"规则。

The reviewer (Agent B) played a key role: it flagged the empty-diff anomaly (which led to discovering bugs #3 and #4) and questioned missing test coverage for edge cases, which led to discovering bugs #1 and #2. The dual-agent structure meant the reviewer had no stake in the implementation being "correct" — its only job was to find problems, and it did.

审查者（Agent B）发挥了关键作用：它标记了空 diff 异常（导致发现 bug #3 和 #4），并质疑边缘情况缺少测试覆盖，这导致发现了 bug #1 和 #2。双代理结构意味着审查者对实现是否"正确"没有利害关系——它唯一的工作就是找问题，而它确实找到了。

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

1. **Subtask list parsing** — Claude Code generated task files with `(subtasks ("a") ("b") ("c"))`, but the parser's `get-list` only read the first element via `cadr`, silently dropping the rest. Any task file generated interactively by Claude Code was losing subtasks.

   **子任务列表解析** — Claude Code 生成的任务文件格式为 `(subtasks ("a") ("b") ("c"))`，但解析器的 `get-list` 通过 `cadr` 只读取第一个元素，静默丢弃其余部分。所有 Claude Code 交互式生成的任务文件都在丢失子任务。

   ```racket
   ;; Before (task-file.rkt, get-list): took only the first element
   (define (get-list key)
     (define pair (assq key fields))
     (if pair
         (let ([val (cadr pair)])        ; ← only first element
           (if (list? val) val (list val)))
         '()))

   ;; After (commit b44ee41): handles four cases via (cdr pair)
   (define (get-list key)
     (define pair (assq key fields))
     (if pair
         (let ([rest (cdr pair)])
           (cond
             [(and (not (null? rest))    ; ← collects all elements
                   (pair? (car rest))
                   (> (length rest) 1))
              (map (lambda (item)
                     (if (pair? item) (car item) item))
                   rest)]
             [(and (not (null? rest))
                   (pair? (car rest)))
              (car rest)]
             [(not (null? rest))
              (list (car rest))]
             [else '()]))
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

---

## Bug #1: Subtask Parsing Only Returned the First Subtask / Bug #1：子任务解析只返回第一个子任务

### Discovery / 发现

When Agent A wrote tests for `task-file.rkt`, it created a task file with three subtasks in the format Claude Code naturally generates:

当 Agent A 为 `task-file.rkt` 编写测试时，它按 Claude Code 自然生成的格式创建了一个包含三个子任务的任务文件：

```scheme
(ruyi-task
  (goal "Add widget support")
  (subtasks ("step 1") ("step 2") ("step 3")))
```

The test asserted that all three subtasks would be parsed:

测试断言所有三个子任务都应被解析：

```racket
(check-equal? (ruyi-task-subtasks task) '("step 1" "step 2" "step 3"))
```

It failed. The parser returned `'("step 1")` — only the first subtask. Steps 2 and 3 were silently dropped. Any task file where Claude Code had generated subtasks in this form would lose all but the first.

测试失败了。解析器返回 `'("step 1")` ——只有第一个子任务。步骤 2 和 3 被静默丢弃。所有 Claude Code 以这种形式生成子任务的任务文件都会丢失除第一个之外的全部子任务。

### Root Cause / 根本原因

The `get-list` helper inside `parse-ruyi-task-expr` used `cadr` to extract the value from a field pair. In Racket, `(assq 'subtasks fields)` returns the entire association — `(subtasks ("step 1") ("step 2") ("step 3"))` — and `cadr` takes only the second element of that list: `("step 1")`.

`parse-ruyi-task-expr` 内部的 `get-list` 辅助函数使用 `cadr` 从字段对中提取值。在 Racket 中，`(assq 'subtasks fields)` 返回整个关联列表 `(subtasks ("step 1") ("step 2") ("step 3"))`，而 `cadr` 只取该列表的第二个元素：`("step 1")`。

The problem is that S-expression task files can represent lists in two valid forms:

问题在于 S 表达式任务文件可以用两种有效形式表示列表：

```scheme
;; Form A: single flat list (written by write-ruyi-task)
(subtasks ("step 1" "step 2" "step 3"))

;; Form B: multiple wrapped elements (written by Claude Code)
(subtasks ("step 1") ("step 2") ("step 3"))
```

`write-ruyi-task` produces Form A, but Claude Code (when generating task files interactively) produces Form B. The parser only handled Form A. Tasks that ruyi wrote and re-read itself (Form A) were fine, but any task file generated interactively by Claude Code during the planning step used Form B — and was silently truncated.

`write-ruyi-task` 生成形式 A，但 Claude Code（交互式生成任务文件时）生成形式 B。解析器只处理了形式 A。如意自身写入再读取的任务（形式 A）没有问题，但 Claude Code 在规划步骤中交互式生成的任务文件都使用形式 B——然后被静默截断。

### The Fix / 修复

The fix replaced the single `cadr` call with a `cond` that distinguishes four S-expression cases. The key insight: instead of extracting one element, take `(cdr pair)` to get *all* values after the key, then dispatch based on their structure.

修复方案将单一的 `cadr` 调用替换为一个 `cond`，区分四种 S 表达式情况。关键洞察：不是提取一个元素，而是用 `(cdr pair)` 获取键之后的*所有*值，然后根据结构分发处理。

**Before** (`task-file.rkt`, `get-list`):

```racket
(define (get-list key)
  (define pair (assq key fields))
  (if pair
      (let ([val (cadr pair)])        ; ← only second element of the assoc
        (if (list? val) val (list val)))
      '()))
```

**After** (commit b44ee41):

```racket
(define (get-list key)
  "Get a list field. Handles both (key (a b c)) and (key (a) (b) (c)) forms."
  (define pair (assq key fields))
  (if pair
      (let ([rest (cdr pair)])       ; ← all elements after the key
        (cond
          ;; (key ("a") ("b") ("c")) — multiple sub-elements
          [(and (not (null? rest))
                (pair? (car rest))
                (> (length rest) 1))
           (map (lambda (item)
                  (if (pair? item) (car item) item))
                rest)]
          ;; (key ("a" "b" "c")) — single list
          [(and (not (null? rest))
                (pair? (car rest)))
           (car rest)]
          ;; (key "a") — single value
          [(not (null? rest))
           (list (car rest))]
          [else '()]))
      '()))
```

Each of the three explicit branches guards with `(not (null? rest))`, and the `[else '()]` fallthrough handles the empty case. The four cases:

三个显式分支各用 `(not (null? rest))` 守卫，`[else '()]` 兜底处理空情况。四种情况：

| Form | Example | Handling |
|------|---------|----------|
| Multiple wrapped elements | `(subtasks ("a") ("b") ("c"))` | `map car` over all elements |
| Single flat list | `(subtasks ("a" "b" "c"))` | Return the list directly |
| Single value | `(subtasks "only-one")` | Wrap in a list |
| Empty | `(subtasks)` | Return `'()` via `[else '()]` |

| 形式 | 示例 | 处理方式 |
|------|------|----------|
| 多个包装元素 | `(subtasks ("a") ("b") ("c"))` | 对所有元素执行 `map car` |
| 单一扁平列表 | `(subtasks ("a" "b" "c"))` | 直接返回列表 |
| 单一值 | `(subtasks "only-one")` | 包装为列表 |
| 空 | `(subtasks)` | 通过 `[else '()]` 返回 `'()` |

This same fix applies to all list fields — `build`, `test`, `forbidden`, and `context` — since they all use `get-list`.

同一修复适用于所有列表字段——`build`、`test`、`forbidden` 和 `context`——因为它们都使用 `get-list`。

### Why It Matters / 为什么重要

This bug was invisible in normal operation. Ruyi would parse a 5-subtask plan, execute only subtask 1, report "complete", and move on. No error, no warning. The only signal was that tasks seemed to finish suspiciously fast — which is easy to dismiss as "Claude is efficient."

这个 bug 在正常操作中是不可见的。如意会解析一个 5 子任务的计划，只执行子任务 1，报告"完成"，然后继续。没有错误，没有警告。唯一的信号是任务似乎完成得异常快——这很容易被当作"Claude 很高效"而忽略。

The test caught it instantly because it asserted on the *full* parsed result, not just that parsing succeeded. This is the value of testing the round-trip: `write → read → compare` reveals mismatches that usage-based testing misses.

测试立即捕获了它，因为它断言的是*完整的*解析结果，而不仅仅是解析成功。这就是往返测试的价值：`写入 → 读取 → 比较` 能揭示基于用法的测试所遗漏的不匹配。

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

---

## Bug #2: Git Diff Showed 0 Lines for New Files / Bug #2：Git Diff 对新文件显示 0 行

### Discovery / 发现

When Agent A implemented a subtask that required creating a new test file (`tests/test-task-file.rkt`), ruyi's engine reported `Diff: 1 lines` — effectively empty. The reviewer (Agent B) received a blank diff and rejected the work with a low score, citing "no meaningful changes." But Agent A *had* created the file — it was sitting right there in the working directory. The implementation was correct; the review infrastructure couldn't see it.

当 Agent A 实现一个需要创建新测试文件（`tests/test-task-file.rkt`）的子任务时，如意引擎报告 `Diff: 1 lines`——实际上是空的。审查者（Agent B）收到了空白 diff，以"没有有意义的变更"为由给出低分并拒绝了工作。但 Agent A *确实*创建了文件——它就在工作目录里。实现是正确的；审查基础设施看不到它。

The reviewer's exact complaint was the clue: an adversarial reviewer that sees an empty diff for a task asking to "create tests" will always flag the contradiction. This is precisely the kind of structural anomaly that a separate reviewer catches — an implementer working alone might assume the commit just didn't go through and retry.

审查者的投诉本身就是线索：一个看到空 diff 的对抗性审查者，面对"创建测试"的任务，必然会标记这个矛盾。这恰恰是独立审查者能捕获的结构性异常——独自工作的实现者可能只会以为提交没有成功然后重试。

### Root Cause / 根本原因

The engine used `git diff HEAD` to measure the diff size and to capture the diff text sent to the reviewer. But `git diff HEAD` only compares the working tree against the last commit for *tracked* files. Newly created files are **untracked** — they don't exist in git's index, so `git diff HEAD` simply ignores them. The diff was legitimately empty from git's perspective: no tracked file had changed.

引擎使用 `git diff HEAD` 来测量 diff 大小以及获取发送给审查者的 diff 文本。但 `git diff HEAD` 只将工作目录与最后一次提交的*已跟踪*文件进行比较。新创建的文件是**未跟踪的**——它们不存在于 git 的索引中，所以 `git diff HEAD` 直接忽略它们。从 git 的角度来看，diff 确实是空的：没有已跟踪的文件发生了变化。

The relevant code path in `engine.rkt` went: implement → check forbidden files → measure diff → run build/test → get diff for review → decide. At no point between Agent A creating files and the engine reading the diff were new files staged into git's index.

`engine.rkt` 中的相关代码路径是：实现 → 检查禁止文件 → 测量 diff → 运行构建/测试 → 获取 diff 供审查 → 决策。在 Agent A 创建文件和引擎读取 diff 之间，没有任何步骤将新文件暂存到 git 索引中。

```
Agent A creates tests/test-task-file.rkt     (untracked)
         ↓
git diff HEAD                                 (sees nothing — file not in index)
         ↓
Reviewer gets empty diff                      (rejects: "no changes")
         ↓
Ruyi reverts                                  (correct code deleted)
```

### The Fix / 修复

The fix was a single addition: run `git add -A` immediately after Agent A finishes implementing, before any safety checks or review. This stages all changes — including newly created files — into the index, making them visible to `git diff HEAD`.

修复方案是一处添加：在 Agent A 完成实现后、任何安全检查或审查之前，立即运行 `git add -A`。这会将所有变更——包括新创建的文件——暂存到索引中，使它们对 `git diff HEAD` 可见。

**Before** (engine.rkt, `execute-one-iteration`):

```racket
;; 2. Agent A implements
(define ok? (claude-implement repo mode-obj tsk*))
(unless ok?
  (git-revert! repo)
  (raise ...))

;; 3. Safety checks (git diff HEAD sees nothing for new files!)
(define forbidden (git-check-forbidden-files repo))
```

**After** (commit 8178048):

```racket
;; 2. Agent A implements
(define ok? (claude-implement repo mode-obj tsk*))
(unless ok?
  (git-revert! repo)
  (raise ...))

;; 2b. Stage all changes (so untracked new files show in diff)
(with-handlers ([exn:fail? (lambda (_) (void))])
  (shell! repo "git" "add" "-A"))

;; 3. Safety checks (now sees everything)
(define forbidden (git-check-forbidden-files repo))
```

The `with-handlers` wrapper ensures that if `git add -A` fails for any reason (e.g., corrupt index), the engine doesn't crash — it falls through and the review proceeds with whatever diff is available. This is a deliberate choice: a partially visible diff is better than a crash that loses the implementation.

`with-handlers` 包装确保如果 `git add -A` 因任何原因失败（例如索引损坏），引擎不会崩溃——它会继续执行，审查将使用当前可用的 diff。这是一个刻意的选择：部分可见的 diff 好过崩溃丢失实现。

### Why It Matters / 为什么重要

This bug made ruyi structurally incapable of handling tasks that create new files — which is a large proportion of real work. Adding a test file, creating a new module, scaffolding a feature: all of these produce untracked files that `git diff HEAD` can't see.

这个 bug 使如意在结构上无法处理创建新文件的任务——而这在真实工作中占很大比例。添加测试文件、创建新模块、搭建功能骨架：所有这些都会产生 `git diff HEAD` 看不到的未跟踪文件。

The failure mode was especially insidious: the engine didn't error out. It reported a small diff, the reviewer scored low, the engine reverted the (correct) work, and moved on to the next attempt — which would fail the same way. From the outside, it looked like the reviewer was being too strict or Agent A was producing bad implementations. The real problem was that the review infrastructure was blind.

失败模式特别阴险：引擎不会报错。它报告一个很小的 diff，审查者给出低分，引擎回滚（正确的）工作，然后进入下一次尝试——同样会失败。从外部看，像是审查者过于严格或 Agent A 产出了糟糕的实现。真正的问题是审查基础设施是盲的。

The fix is two lines of code, but it required the reviewer to surface the symptom. An implementer-only workflow would have seen "reviewer rejected my work" and tried harder — never questioning whether the reviewer could actually see the work.

---

## Bug #3: Explicit `#f` for Auto-Merge Was Treated as `#t` / Bug #3：显式 `#f` 自动合并被当作 `#t`

### Discovery / 发现

When Agent A wrote round-trip tests for boolean fields, it created a task file with explicit opt-outs:

当 Agent A 为布尔字段编写往返测试时，它创建了一个带有显式关闭选项的任务文件：

```scheme
(ruyi-task
  (goal "test")
  (auto-merge #f)
  (track #f))
```

The test asserted that both fields should parse as `#f`:

测试断言这两个字段应解析为 `#f`：

```racket
(check-equal? (ruyi-task-auto-merge? task) #f)
(check-equal? (ruyi-task-track? task) #f)
```

Both failed. The parser returned `#t` for both — the default value, as if the fields had never been set. A user who explicitly wrote `(auto-merge #f)` to prevent automatic PR merging would have their preference silently overridden.

两个都失败了。解析器对两个字段都返回 `#t`——默认值，就好像这些字段从未被设置过。一个显式写了 `(auto-merge #f)` 来阻止自动 PR 合并的用户，其偏好会被静默覆盖。

### Root Cause / 根本原因

The parser's `get` helper used `#f` as the default return value when a key was not found:

解析器的 `get` 辅助函数在键未找到时使用 `#f` 作为默认返回值：

```racket
(define (get key [default #f])
  (define pair (assq key fields))
  (if pair (cadr pair) default))
```

When the task file contained `(auto-merge #f)`, `get` correctly extracted `#f` from the S-expression. But the calling code couldn't distinguish this from a missing field:

当任务文件包含 `(auto-merge #f)` 时，`get` 正确地从 S 表达式中提取出 `#f`。但调用代码无法区分这个值和缺失字段：

```racket
;; In parse-ruyi-task-expr:
(let ([v (get 'auto-merge)]) (if (eq? v #f) #t v))
```

The logic was: "if `v` is `#f`, use the default `#t`; otherwise use `v`." But `#f` had two meanings:

1. The key was not present in the file → should default to `#t`
2. The key was present with value `#f` → should remain `#f`

Since both cases produced the same value (`#f`) from `get`, the `if` branch always treated them identically — defaulting to `#t`.

逻辑是："如果 `v` 是 `#f`，使用默认值 `#t`；否则使用 `v`。"但 `#f` 有两层含义：

1. 键不存在于文件中 → 应使用默认值 `#t`
2. 键存在且值为 `#f` → 应保持 `#f`

由于两种情况从 `get` 产生相同的值（`#f`），`if` 分支总是将它们一视同仁——默认为 `#t`。

This is a classic sentinel-value collision: using a value from the domain (`#f` is a valid boolean) as a signal for "absent." It's the same class of bug as using `null` to mean "not found" in a system where `null` is a valid data value.

这是经典的哨兵值冲突：将一个属于值域的值（`#f` 是有效的布尔值）用作"缺失"信号。与在 `null` 是有效数据值的系统中用 `null` 表示"未找到"属于同一类 bug。

### The Fix / 修复

The fix introduced a `gensym` sentinel — a unique symbol guaranteed to never appear in any S-expression — to represent "missing," and added a dedicated `get-bool` helper that uses it.

修复方案引入了 `gensym` 哨兵——一个保证永远不会出现在任何 S 表达式中的唯一符号——来表示"缺失"，并添加了使用它的专用 `get-bool` 辅助函数。

**Before** (`task-file.rkt`, `parse-ruyi-task-expr`):

```racket
(define (get key [default #f])
  (define pair (assq key fields))
  (if pair (cadr pair) default))

;; Boolean fields: #f means both "missing" and "explicitly false"
(let ([v (get 'auto-merge)]) (if (eq? v #f) #t v))   ; ← #f → #t!
(let ([v (get 'track)])      (if (eq? v #f) #t v))    ; ← #f → #t!
```

**After** (commit 7273980):

```racket
(define MISSING (gensym 'missing))

(define (get key [default MISSING])
  (define pair (assq key fields))
  (if pair (cadr pair) default))

(define (get-bool key default)
  "Get a boolean field. Distinguishes missing from explicit #f."
  (define v (get key))
  (if (eq? v MISSING) default v))    ; ← only defaults when truly missing

;; Boolean fields now use get-bool:
(get-bool 'auto-merge #t)           ; missing → #t, explicit #f → #f ✓
(get-bool 'track #t)                ; missing → #t, explicit #f → #f ✓
```

`gensym` creates a symbol that is `eq?` only to itself — it cannot collide with any value read from an S-expression. This cleanly separates the "not found" signal from the data domain. The same `MISSING` sentinel is also used for non-boolean fields (`goal`, `max-revisions`, etc.), replacing all the ad-hoc `(if (eq? v #f) default v)` patterns with a consistent approach.

`gensym` 创建一个只与自身 `eq?` 的符号——它不可能与从 S 表达式读取的任何值冲突。这干净地将"未找到"信号与数据域分离。同一个 `MISSING` 哨兵也用于非布尔字段（`goal`、`max-revisions` 等），将所有临时的 `(if (eq? v #f) default v)` 模式替换为一致的方法。

### Why It Matters / 为什么重要

In production, this bug would silently override a safety control. A user who set `(auto-merge #f)` — perhaps because they wanted to review the PR manually before merging — would find that ruyi merged it automatically anyway. The setting existed in the file, the UI showed it, but the parser ignored it.

在生产环境中，这个 bug 会静默覆盖安全控制。一个设置了 `(auto-merge #f)` 的用户——也许因为想在合并前手动审查 PR——会发现如意还是自动合并了。设置存在于文件中，界面也显示了它，但解析器忽略了它。

The same bug affected `track`, which controls whether the task file is committed to git. Setting `(track #f)` for a sensitive task would be ignored — the task file would be committed anyway, potentially exposing internal planning details to the repository history.

同一 bug 也影响了 `track`，它控制任务文件是否提交到 git。为敏感任务设置 `(track #f)` 会被忽略——任务文件仍然会被提交，可能将内部规划细节暴露到仓库历史中。

The test that caught this was straightforward — just parse a file with `#f` values and check they come back as `#f`. But writing it required the insight that `#f` plays double duty in Racket as both a boolean and a common default. Agent B's review of the initial test suite flagged the missing edge case: "no test covers explicit `#f` for boolean fields." That observation led directly to the test, the failure, and the fix.

捕获这个 bug 的测试很简单——只需解析一个包含 `#f` 值的文件并检查它们是否作为 `#f` 返回。但编写它需要理解 `#f` 在 Racket 中同时充当布尔值和常见默认值的双重角色。Agent B 在审查初始测试套件时标记了缺失的边缘情况："没有测试覆盖布尔字段的显式 `#f`。"这个观察直接导致了测试、失败和修复。

---

## Conclusion: The Value of Dual-Agent Review / 结论：双代理审查的价值

### Adversarial Review Catches Real Bugs / 对抗性审查捕获真实 Bug

The three bugs documented above share a pattern: Agent A (the implementer) either introduced them or had no reason to look for them. A single-agent workflow — implement, test what you think matters, commit — would have missed all three.

以上记录的三个 bug 有一个共同模式：Agent A（实现者）要么引入了它们，要么没有理由去寻找它们。单代理工作流——实现、测试你认为重要的、提交——会遗漏所有三个。

**Bug #1** (subtask truncation): Agent A wrote tests that matched the format `write-ruyi-task` produces. It had no reason to test a format it didn't generate. Agent B flagged incomplete edge-case coverage, which led to testing the format Claude Code *actually* generates — and exposed the parser's blind spot.

**Bug #1**（子任务截断）：Agent A 编写的测试匹配 `write-ruyi-task` 产生的格式。它没有理由去测试自己不生成的格式。Agent B 标记了不完整的边缘情况覆盖，这导致了对 Claude Code *实际*生成格式的测试——暴露了解析器的盲点。

**Bug #2** (empty diff for new files): Agent A created the test file correctly. From its perspective, the job was done. It was Agent B who saw the contradiction — a task that asked "create tests" paired with a diff showing zero changes — and rejected it. That rejection forced investigation into *why* the diff was empty, revealing the missing `git add -A` step.

**Bug #2**（新文件空 diff）：Agent A 正确地创建了测试文件。从它的角度来看，工作已完成。是 Agent B 看到了矛盾——一个要求"创建测试"的任务配上一个显示零变更的 diff——并拒绝了它。这个拒绝迫使调查 diff *为什么*是空的，揭示了缺失的 `git add -A` 步骤。

**Bug #3** (boolean `#f` as `#t`): Agent A's initial tests checked that fields parsed correctly when present with truthy values. Agent B's review noted: "no test covers explicit `#f` for boolean fields." That single observation produced the test that broke the parser.

**Bug #3**（布尔 `#f` 变 `#t`）：Agent A 最初的测试检查了字段在以真值存在时是否正确解析。Agent B 的审查指出："没有测试覆盖布尔字段的显式 `#f`。"这一个观察产生了打破解析器的测试。

The information barrier is what makes this work. Agent B never sees Agent A's reasoning, plan, or conversation history. It sees only the diff and the task description. This means it cannot inherit the implementer's assumptions about what "should" work. When Agent A assumes `cadr` is sufficient because it tested with one format, Agent B doesn't share that assumption — it evaluates the diff on its own terms and asks "what about other formats?"

信息屏障是这一切生效的关键。Agent B 从不看到 Agent A 的推理、计划或对话历史。它只看到 diff 和任务描述。这意味着它无法继承实现者关于什么"应该"有效的假设。当 Agent A 假设 `cadr` 足够因为它用一种格式测试过，Agent B 不共享这个假设——它用自己的标准评估 diff 并问"其他格式呢？"

### Not Ceremony — Structural Necessity / 不是仪式——结构性必需

It's tempting to view code review as overhead — a checkbox before merging. The self-testing experiment shows it is structurally load-bearing. Remove the reviewer, and all three bugs ship:

人们很容易将代码审查视为开销——合并前的一个勾选框。自测实验表明它在结构上是承重的。移除审查者，三个 bug 全部发布：

- Tasks silently execute only their first subtask
- New files are created but invisible to the review pipeline, leading to false rejections and wasted retries
- Users' explicit `#f` opt-outs are silently overridden to `#t`

- 任务静默只执行第一个子任务
- 新文件被创建但对审查流水线不可见，导致误拒和浪费的重试
- 用户显式的 `#f` 关闭选项被静默覆盖为 `#t`

The dual-agent design costs one additional Claude call per subtask (the review). In exchange, it provides an independent check that shares no state with the implementer. The cost is linear; the value is in catching bugs that a single agent systematically cannot find in its own work.

双代理设计每个子任务多花一次 Claude 调用（审查）。作为交换，它提供了一个与实现者不共享任何状态的独立检查。成本是线性的；价值在于捕获单一代理在自己的工作中系统性无法发现的 bug。

### A Note on Self-Referential Testing / 关于自指测试的思考

There is something recursive about a tool finding bugs in itself. Ruyi's implement-review-revise loop was the mechanism that discovered that the same loop had a staging bug (Bug #2), that its task parser silently truncated data (Bug #1), and that its boolean handling was fundamentally broken (Bug #3). The tool was both the surgeon and the patient.

一个工具在自身中发现 bug，这件事有某种递归的意味。如意的实现-审查-修订循环是发现同一循环有暂存 bug（Bug #2）、任务解析器静默截断数据（Bug #1）、布尔处理根本性错误（Bug #3）的机制。这个工具既是外科医生又是病人。

This works precisely because the dual-agent architecture creates genuine independence. Agent B reviewing Agent A's work on ruyi is no different from Agent B reviewing Agent A's work on any other codebase — it sees a diff, it finds problems. The self-referential nature doesn't weaken the process; if anything, it stress-tests it. If the review loop can find bugs in *its own implementation*, it can likely find bugs anywhere.

这之所以行得通，恰恰是因为双代理架构创造了真正的独立性。Agent B 审查 Agent A 在如意上的工作，与 Agent B 审查 Agent A 在任何其他代码库上的工作没有区别——它看到 diff，它找到问题。自指性质不会削弱这个过程；如果有什么区别的话，它反而是一种压力测试。如果审查循环能在*自身的实现*中找到 bug，它很可能在任何地方都能找到 bug。

The practical takeaway: if you build a system that orchestrates AI agents, point it at itself early. The bugs it finds will be real, and the act of self-testing validates the architecture in a way that testing on external codebases alone cannot.

实用的启示：如果你构建了一个编排 AI 代理的系统，尽早让它指向自己。它发现的 bug 将是真实的，而自测行为以一种仅在外部代码库上测试无法实现的方式验证了架构。

#lang racket/base
(require racket/format racket/list racket/string racket/file racket/port racket/match)
(require "config.rkt" "claude.rkt" "git.rkt" "validate.rkt" "log.rkt" "judge.rkt" "review.rkt"
         "task-file.rkt")
(provide evolution-loop evolution-loop/worktree run-parallel-evolutions
         evolution-loop/worktree-task run-parallel-task-evolutions)

;; ============================================================
;; Helper: clone repo-config with a different path
;; ============================================================

(define (repo-config-with-path repo new-path)
  (repo-config (repo-config-name repo)
               (if (string? new-path) (string->path new-path) new-path)
               (repo-config-base-branch repo)
               (repo-config-source-dirs repo)
               (repo-config-source-exts repo)
               (repo-config-excluded-dirs repo)
               (repo-config-test-pattern repo)
               (repo-config-test-alt-dir repo)
               (repo-config-forbidden-files repo)
               (repo-config-validate-commands repo)
               (repo-config-priority-dirs repo)
               (repo-config-context-files repo)
               (repo-config-log-path repo)
               (repo-config-max-iterations repo)
               (repo-config-max-consecutive-fails repo)
               (repo-config-max-diff-lines repo)))

;; ============================================================
;; Core evolution loop — deterministic backbone
;;
;; Prepare: user confirms goal (interactive)
;; Loop: fully autonomous, auto-continues (Ctrl-C to stop)
;; Finish: show summary, merge to main, cleanup
;; ============================================================

(define (evolution-loop repo mode-obj)

  ;; Setup
  (printf "\n=== Ruyi Evolution Engine ===\n")
  (printf "Repo:  ~a (~a)\n" (repo-config-name repo) (repo-config-path repo))
  (printf "Mode:  ~a\n" (mode-name mode-obj))
  (printf "============================\n\n")

  ;; Ensure clean state
  (git-ensure-clean! repo)

  ;; Create branch
  (define branch (git-create-branch! repo mode-obj))
  (printf "Branch: ~a\n" branch)

  ;; Validate baseline
  (printf "\nBaseline validation:\n")
  (define baseline (run-validation-gate repo))
  (unless (validation-result-passed? baseline)
    (error 'evolution-loop
           "Repo is not green! Fix before running.\nFailed: ~a"
           (validation-result-failed-step baseline)))
  (printf "Baseline: PASSED\n")

  ;; Init log + journal
  (log-init! repo)
  (journal-init! repo (mode-name mode-obj))

  ;; Track results for summary
  (define kept-tasks '())    ; list of task structs
  (define discarded-count 0)

  ;; Main loop (auto-continues, Ctrl-C to stop)
  (let loop ([i 1]
             [consecutive-fails 0]
             [done '()])

    (cond
      ;; Termination: iteration limit
      [(> i (repo-config-max-iterations repo))
       (printf "\nReached iteration limit (~a).\n"
               (repo-config-max-iterations repo))
       (finish-evolution repo mode-obj branch kept-tasks discarded-count)]

      ;; Termination: consecutive failures
      [(>= consecutive-fails (repo-config-max-consecutive-fails repo))
       (printf "\n~a consecutive failures. Stopping.\n" consecutive-fails)
       (finish-evolution repo mode-obj branch kept-tasks discarded-count)]

      ;; Normal execution
      [else
       (define tsk ((mode-select-task mode-obj) repo done))

       (cond
         [(not tsk)
          (printf "\nNo more tasks found.\n")
          (finish-evolution repo mode-obj branch kept-tasks discarded-count)]

         [else
          (printf "\n[~a/~a] ~a\n" i (repo-config-max-iterations repo)
                  (task-description tsk))

          ;; Execute one iteration
          (define result (execute-one-iteration repo mode-obj tsk))

          ;; Log
          (log-iteration! repo (mode-name mode-obj) tsk result)

          ;; Print result
          (printf "  ~a ~a\n"
                  (if (eq? (iteration-result-status result) 'keep) "+" "-")
                  (iteration-result-detail result))

          ;; Track for summary
          (when (eq? (iteration-result-status result) 'keep)
            (set! kept-tasks (cons tsk kept-tasks)))
          (when (eq? (iteration-result-status result) 'discard)
            (set! discarded-count (add1 discarded-count)))

          ;; Auto-continue
          (loop (add1 i)
                (if (eq? (iteration-result-status result) 'discard)
                    (add1 consecutive-fails)
                    0)
                (if (eq? (iteration-result-status result) 'keep)
                    (cons tsk done)
                    done))])])))

;; ============================================================
;; Finish: summary + merge + cleanup
;; ============================================================

(define (finish-evolution repo mode-obj branch kept-tasks discarded-count)
  (define kept-count (length kept-tasks))

  ;; Show summary
  (printf "\n=== Evolution Complete ===\n")
  (printf "Kept:      ~a\n" kept-count)
  (printf "Discarded: ~a\n" discarded-count)
  (when (> kept-count 0)
    (printf "\nChanges made:\n")
    (for ([tsk (in-list (reverse kept-tasks))])
      (printf "  + ~a\n" (task-description tsk))))
  (printf "=========================\n")

  ;; If nothing was kept, just go back to main
  (when (= kept-count 0)
    (printf "\nNo changes to apply.\n")
    (shell! repo "git" "checkout" (repo-config-base-branch repo))
    (return-void))

  ;; Ask to merge via PR
  (define answer (read-line-interactive "Merge to main? (y/n) "))

  (cond
    [(string=? answer "y")
     (with-handlers
       ([exn:fail?
         (lambda (e)
           (printf "PR merge failed: ~a\n" (exn-message e)))])
       (git-push-branch! repo)
       (define pr-url (gh-create-and-merge-pr! repo mode-obj (reverse kept-tasks)))
       (printf "~a\n" pr-url)
       (printf "Done.\n"))]
    [else
     (printf "Changes kept on branch: ~a\n" branch)
     (shell! repo "git" "checkout" (repo-config-base-branch repo))]))

(define (return-void) (void))

;; ============================================================
;; Single iteration execution
;; ============================================================

(define DEFAULT-MAX-REVISIONS 2)

(define (inject-feedback tsk feedback)
  "Add reviewer feedback to task's extra hash."
  (if (string=? feedback "")
      tsk
      (task (task-source-file tsk)
            (task-description tsk)
            (task-priority tsk)
            (if (task-extra tsk)
                (hash-set (task-extra tsk) 'reviewer-feedback feedback)
                (make-immutable-hash
                 (list (cons 'reviewer-feedback feedback)))))))

(define (task-param tsk key default)
  "Get a parameter from task extra, or return default."
  (if (and (task-extra tsk) (hash-has-key? (task-extra tsk) key))
      (hash-ref (task-extra tsk) key)
      default))

(define (execute-one-iteration repo mode-obj tsk)
  "Implement → Review → Decide. All parameters from task spec."
  (define max-revs     (task-param tsk 'max-revisions 2))
  (define min-score    (task-param tsk 'min-score 8))
  (define max-diff     (task-param tsk 'max-diff 500))
  (define rev-model    (task-param tsk 'reviewer-model "sonnet"))
  (define skip-valid?  (task-param tsk 'skip-validation #f))

  (with-handlers
    ([exn:fail?
      (lambda (e)
        (printf "  Error: ~a\n" (exn-message e))
        (with-handlers ([exn:fail? (lambda (_) (void))])
          (git-revert! repo))
        (iteration-result 'discard (exn-message e)))])

    (let revise-loop ([attempt 1] [feedback ""])

      ;; 1. Inject reviewer feedback into task
      (define tsk* (inject-feedback tsk feedback))
      (when (> attempt 1)
        (printf "  Revision ~a/~a with feedback...\n" attempt max-revs))

      ;; 2. Agent A implements (full Claude Code agent mode)
      (define ok? (claude-implement repo mode-obj tsk*))
      (unless ok?
        (git-revert! repo)
        (raise (make-exn:fail "Claude failed" (current-continuation-marks))))

      ;; 3. Safety checks
      (define forbidden (git-check-forbidden-files repo))
      (unless (null? forbidden)
        (git-revert! repo)
        (raise (make-exn:fail
                (format "Touched forbidden: ~a" (string-join forbidden ", "))
                (current-continuation-marks))))

      (define diff-lines (git-diff-line-count repo))
      (printf "  Diff: ~a lines\n" diff-lines)
      (when (> diff-lines max-diff)
        (git-revert! repo)
        (raise (make-exn:fail
                (format "Diff too large: ~a > ~a" diff-lines max-diff)
                (current-continuation-marks))))

      ;; 4. Optional build/test validation
      (unless skip-valid?
        (define validation (run-validation-gate repo))
        (unless (validation-result-passed? validation)
          (git-revert! repo)
          (raise (make-exn:fail
                  (format "Validation failed: ~a"
                          (validation-result-failed-step validation))
                  (current-continuation-marks)))))

      ;; 5. Agent B reviews (independent, sees only diff + task)
      (define diff-text
        (with-handlers ([exn:fail? (lambda (_) "")])
          (shell! repo "git" "diff" "HEAD")))
      (define judgement (task-param tsk 'judgement ""))
      (define-values (score issues suggestions)
        (review-changes (repo-config-path repo)
                        (task-description tsk)
                        diff-text
                        #:model rev-model
                        #:judgement judgement))

      ;; 6. Ruyi decides (thresholds from task spec)
      (define revise-threshold (max 1 (- min-score 2)))  ; e.g. min-score 8 → revise at 6+

      (cond
        ;; Approved
        [(>= score min-score)
         (define hash (git-commit! repo mode-obj tsk))
         (iteration-result 'keep (format "~a (score: ~a)" hash score))]

        ;; Needs revision
        [(and (>= score revise-threshold) (< attempt max-revs))
         (printf "  Score ~a < ~a — revising...\n" score min-score)
         (git-revert! repo)
         (define reformulated (format-feedback-for-implementer issues suggestions))
         (revise-loop (add1 attempt) reformulated)]

        ;; Max attempts, decent score: best effort
        [(and (>= score revise-threshold) (>= attempt max-revs))
         (printf "  Score ~a — max revisions, committing best effort\n" score)
         (define hash (git-commit! repo mode-obj tsk))
         (iteration-result 'keep (format "~a (score: ~a, best-effort)" hash score))]

        ;; Rejected
        [else
         (printf "  Score ~a — rejected\n" score)
         (git-revert! repo)
         (iteration-result 'discard (format "Rejected (score: ~a)" score))]))))

;; ============================================================
;; Worktree-based evolution (for parallel execution)
;; ============================================================

;; Mutex for branch creation + worktree setup (shared git index)
(define worktree-setup-lock (make-semaphore 1))

(define (evolution-loop/worktree repo mode-obj
                                  #:auto-merge? [auto-merge? #t]
)
  "Run evolution in an isolated git worktree. Creates branch in main repo,
   sets up worktree, runs the loop there, pushes + creates PR, cleans up.
   Returns (values branch kept-count pr-url-or-#f)."
  (define origin-repo repo)
  (define origin-path (repo-config-path repo))

  ;; Serialize branch creation + worktree add (touches shared git index)
  (define-values (branch wt-path)
    (call-with-semaphore worktree-setup-lock
      (lambda ()
        (git-ensure-clean! origin-repo)
        (define b (git-create-branch! origin-repo mode-obj))
        (shell! origin-repo "git" "checkout" (repo-config-base-branch origin-repo))
        (define wt (git-worktree-add! origin-repo b))
        (values b wt))))
  (printf "[worktree] ~a → ~a\n" branch wt-path)

  ;; Build a repo-config pointing to the worktree
  (define wt-repo (repo-config-with-path origin-repo wt-path))

  (define kept-tasks '())
  (define discarded-count 0)
  (define pr-url #f)

  (with-handlers
    ([exn:fail?
      (lambda (e)
        (printf "[worktree] Error in ~a: ~a\n" branch (exn-message e)))])

    ;; Validate baseline in worktree (skip if no validate-commands)
    (cond
      [(null? (repo-config-validate-commands wt-repo))
       (printf "[~a] Baseline: skipped (no validate commands)\n" branch)]
      [else
       (printf "[~a] Baseline validation:\n" branch)
       (define baseline (run-validation-gate wt-repo))
       (unless (validation-result-passed? baseline)
         (error 'evolution-loop/worktree
                "Repo is not green! Failed: ~a"
                (validation-result-failed-step baseline)))
       (printf "[~a] Baseline: PASSED\n" branch)])

    ;; Init log + journal
    (log-init! wt-repo)
    (journal-init! wt-repo (mode-name mode-obj))

    ;; Main loop (same logic as evolution-loop, but non-interactive)
    (let loop ([i 1]
               [consecutive-fails 0]
               [done '()])
      (cond
        [(> i (repo-config-max-iterations wt-repo))
         (printf "[~a] Reached iteration limit.\n" branch)]
        [(>= consecutive-fails (repo-config-max-consecutive-fails wt-repo))
         (printf "[~a] ~a consecutive failures. Stopping.\n" branch consecutive-fails)]
        [else
         (define tsk ((mode-select-task mode-obj) wt-repo done))
         (cond
           [(not tsk)
            (printf "[~a] No more tasks.\n" branch)]
           [else
            (printf "[~a][~a/~a] ~a\n" branch i (repo-config-max-iterations wt-repo)
                    (task-description tsk))
            (define result (execute-one-iteration wt-repo mode-obj tsk))
            (log-iteration! wt-repo (mode-name mode-obj) tsk result)
            (printf "[~a]   ~a ~a\n" branch
                    (if (eq? (iteration-result-status result) 'keep) "+" "-")
                    (iteration-result-detail result))
            (when (eq? (iteration-result-status result) 'keep)
              (set! kept-tasks (cons tsk kept-tasks)))
            (when (eq? (iteration-result-status result) 'discard)
              (set! discarded-count (add1 discarded-count)))

            (loop (add1 i)
                  (if (eq? (iteration-result-status result) 'discard)
                      (add1 consecutive-fails)
                      0)
                  (if (eq? (iteration-result-status result) 'keep)
                      (cons tsk done)
                      done))])]))

    ;; Push + PR if we have changes
    (define kept-count (length kept-tasks))
    (printf "\n[~a] Complete — kept: ~a, discarded: ~a\n" branch kept-count discarded-count)

    (when (and auto-merge? (> kept-count 0))
      (define has-remote?
        (with-handlers ([exn:fail? (lambda (_) #f)])
          (define out (shell!/dir wt-path "git" "remote"))
          (not (string=? (string-trim out) ""))))
      (cond
        [has-remote?
         (printf "[~a] Pushing and creating PR...\n" branch)
         (shell!/dir wt-path "git" "push" "-u" "origin" branch)
         (set! pr-url
           (gh-create-and-merge-pr! wt-repo mode-obj (reverse kept-tasks)))
         (printf "[~a] PR: ~a\n" branch pr-url)]
        [else
         (printf "[~a] No remote — merging locally...\n" branch)
         (define base (repo-config-base-branch origin-repo))
         (shell!/dir (path->string (repo-config-path origin-repo))
                     "git" "merge" branch "--no-ff"
                     "-m" (format "Merge ~a (~a changes)" branch kept-count))
         (printf "[~a] Merged to ~a\n" branch base)])))

  ;; Cleanup worktree
  (printf "[worktree] Cleaning up ~a\n" wt-path)
  (git-worktree-remove! origin-repo wt-path)

  (values branch (length kept-tasks) pr-url))

;; ============================================================
;; Parallel evolution: run multiple mode+goal pairs concurrently
;; ============================================================

(define (run-parallel-evolutions repo mode-goals
                                  #:auto-merge? [auto-merge? #t])
  "Run multiple evolutions in parallel, each in its own worktree.
   mode-goals is a list of mode objects.
   Returns a list of (list branch kept-count pr-url-or-#f)."
  (printf "\n=== Ruyi Parallel Evolution ===\n")
  (printf "Repo:    ~a (~a)\n" (repo-config-name repo) (repo-config-path repo))
  (printf "Streams: ~a\n" (length mode-goals))
  (printf "===============================\n\n")

  ;; Launch each evolution in a thread
  (define threads+channels
    (for/list ([mode-obj (in-list mode-goals)]
               [idx (in-naturals 1)])
      (define ch (make-channel))
      (printf "  [~a] ~a\n" idx (mode-name mode-obj))
      (define t
        (thread
         (lambda ()
           (with-handlers
             ([exn:fail?
               (lambda (e)
                 (channel-put ch (list (format "stream-~a" idx) 0 #f (exn-message e))))])
             (define-values (branch kept pr-url)
               (evolution-loop/worktree repo mode-obj #:auto-merge? auto-merge?))
             (channel-put ch (list branch kept pr-url #f))))))
      (cons t ch)))

  (printf "\nAll streams launched. Waiting for completion...\n\n")

  ;; Collect results
  (define results
    (for/list ([tc (in-list threads+channels)])
      (define result (channel-get (cdr tc)))
      result))

  ;; Summary
  (printf "\n=== Parallel Evolution Summary ===\n")
  (for ([r (in-list results)]
        [idx (in-naturals 1)])
    (match-define (list branch kept pr-url err) r)
    (cond
      [err (printf "  [~a] ~a — FAILED: ~a\n" idx branch err)]
      [(> kept 0)
       (printf "  [~a] ~a — ~a changes" idx branch kept)
       (when pr-url (printf " — ~a" pr-url))
       (printf "\n")]
      [else
       (printf "  [~a] ~a — no changes\n" idx branch)]))
  (printf "==================================\n")

  results)

;; ============================================================
;; Task-file based evolution (new architecture)
;; ============================================================

(define (make-task-mode rtask)
  "Create a mode object from a ruyi-task struct."
  (define subtask-list (ruyi-task-subtasks rtask))
  (define remaining (box subtask-list))

  (define (select-task repo done)
    (define rem (unbox remaining))
    (if (null? rem)
        #f
        (let ([next (car rem)])
          (set-box! remaining (cdr rem))
          (task ""
                (if (> (string-length next) 70)
                    (string-append (substring next 0 70) "...")
                    next)
                1
                (make-immutable-hash
                 (list (cons 'goal next)
                       (cons 'overview (ruyi-task-goal rtask))
                       (cons 'skip-validation (not (ruyi-task-validate? rtask)))
                       (cons 'max-revisions (ruyi-task-max-revisions rtask))
                       (cons 'min-score (ruyi-task-min-score rtask))
                       (cons 'max-diff (ruyi-task-max-diff rtask))
                       (cons 'reviewer-model (ruyi-task-reviewer-model rtask))
                       (cons 'auto-merge (ruyi-task-auto-merge? rtask))
                       (cons 'forbidden (ruyi-task-forbidden rtask))
                       (cons 'context (ruyi-task-context rtask))
                       (cons 'judgement (ruyi-task-judgement rtask))))))))

  (define (build-prompt repo tsk)
    (define subtask-goal (hash-ref (task-extra tsk) 'goal))
    (define overview (hash-ref (task-extra tsk) 'overview))
    (define reviewer-fb
      (if (hash-has-key? (task-extra tsk) 'reviewer-feedback)
          (hash-ref (task-extra tsk) 'reviewer-feedback) ""))
    (define judgement (hash-ref (task-extra tsk) 'judgement ""))
    (define ctx-files (hash-ref (task-extra tsk) 'context '()))
    (define forbidden (hash-ref (task-extra tsk) 'forbidden '()))

    (define context-content
      (for/fold ([ctx ""])
                ([cf (in-list ctx-files)])
        (define full-path (build-path (repo-config-path repo) cf))
        (if (file-exists? full-path)
            (string-append ctx "\n\n## " cf "\n\n" (file->string full-path))
            ctx)))

    (string-append
     "You are implementing one step of a larger goal.\n\n"
     "## Overall goal\n\n" overview "\n\n"
     "## This step\n\n" subtask-goal "\n\n"
     (if (string=? reviewer-fb "")
         ""
         (string-append "## Issues found in your previous attempt\n\n"
                        reviewer-fb "\n\nFix these issues.\n\n"))
     "## Rules\n\n"
     "- Read relevant source files before making changes.\n"
     "- Write or update tests for code changes.\n"
     "- Keep changes focused — ONLY do this one step.\n"
     (if (null? forbidden) ""
         (string-append "- Do NOT modify: "
                        (string-join forbidden ", ") "\n"))
     "- Follow the project's existing patterns.\n\n"
     (if (string=? context-content "") ""
         (string-append "## Reference files\n" context-content "\n"))))

  (mode 'ruyi select-task build-prompt "ruyi" "ruyi"))

(define (evolution-loop/worktree-task repo rtask)
  "Run evolution from a ruyi-task struct. Returns (values branch kept pr-url)."
  (define mode-obj (make-task-mode rtask))
  (evolution-loop/worktree repo mode-obj
                            #:auto-merge? (ruyi-task-auto-merge? rtask)))

(define (run-parallel-task-evolutions repo tasks)
  "Run multiple ruyi-tasks in parallel."
  (define modes (map make-task-mode tasks))
  (run-parallel-evolutions repo modes))

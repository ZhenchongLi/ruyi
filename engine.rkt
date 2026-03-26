#lang racket/base
(require racket/format racket/list racket/string racket/file racket/port racket/match)
(require "config.rkt" "claude.rkt" "git.rkt" "validate.rkt" "log.rkt" "judge.rkt")
(provide evolution-loop evolution-loop/worktree run-parallel-evolutions)

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

(define (execute-one-iteration repo mode-obj tsk)
  (with-handlers
    ([exn:fail?
      (lambda (e)
        (printf "  Error: ~a\n" (exn-message e))
        (with-handlers ([exn:fail? (lambda (_) (void))])
          (git-revert! repo))
        (iteration-result 'discard (exn-message e)))])

    ;; 1. Call Claude to implement
    (define ok? (claude-implement repo mode-obj tsk))
    (unless ok?
      (git-revert! repo)
      (raise (make-exn:fail "Claude failed" (current-continuation-marks))))

    ;; 2. Check forbidden files
    (define forbidden (git-check-forbidden-files repo))
    (unless (null? forbidden)
      (git-revert! repo)
      (raise (make-exn:fail
              (format "Touched forbidden: ~a" (string-join forbidden ", "))
              (current-continuation-marks))))

    ;; 3. Check diff size
    (define diff-lines (git-diff-line-count repo))
    (printf "  Diff: ~a lines\n" diff-lines)
    (when (> diff-lines (repo-config-max-diff-lines repo))
      (git-revert! repo)
      (raise (make-exn:fail
              (format "Diff too large: ~a > ~a"
                      diff-lines (repo-config-max-diff-lines repo))
              (current-continuation-marks))))

    ;; 4. Validate — either Judge or build+test
    (define has-rubric?
      (and (task-extra tsk) (hash-has-key? (task-extra tsk) 'rubric)))

    (cond
      ;; Judge mode: score with LLM
      [has-rubric?
       (define rubric (hash-ref (task-extra tsk) 'rubric))
       (define min-score (hash-ref (task-extra tsk) 'min-score 7.0))
       (define set-feedback!
         (hash-ref (task-extra tsk) 'set-feedback! (lambda (s w f) (void))))
       (define file-path (task-source-file tsk))
       (define content
         (if (file-exists? file-path) (file->string file-path) ""))
       (define-values (score weaknesses feedback)
         (judge-evaluate (repo-config-path repo) rubric content))
       (set-feedback! score weaknesses feedback)
       (journal-iteration! repo
                           (format "~a" (hash-ref (task-extra tsk) 'min-score 0))
                           (if (>= score min-score) "keep" "discard")
                           (task-description tsk)
                           #:score score
                           #:weaknesses weaknesses
                           #:feedback feedback)
       (cond
         [(>= score min-score)
          (define hash (git-commit! repo mode-obj tsk))
          (iteration-result 'keep (format "~a (score: ~a)" hash score))]
         [else
          (printf "  Score ~a < ~a\n" score min-score)
          (git-revert! repo)
          (iteration-result 'discard (format "Score ~a < ~a" score min-score))])]

      ;; Standard mode: build + test
      [else
       (define validation (run-validation-gate repo))
       (cond
         [(validation-result-passed? validation)
          (define hash (git-commit! repo mode-obj tsk))
          (iteration-result 'keep hash)]
         [else
          (git-revert! repo)
          (iteration-result 'discard
                            (format "Validation failed: ~a"
                                    (validation-result-failed-step validation)))])])))

;; ============================================================
;; Worktree-based evolution (for parallel execution)
;; ============================================================

;; Mutex for branch creation + worktree setup (shared git index)
(define worktree-setup-lock (make-semaphore 1))

(define (evolution-loop/worktree repo mode-obj
                                  #:auto-merge? [auto-merge? #t])
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

    ;; Validate baseline in worktree
    (printf "[~a] Baseline validation:\n" branch)
    (define baseline (run-validation-gate wt-repo))
    (unless (validation-result-passed? baseline)
      (error 'evolution-loop/worktree
             "Repo is not green! Failed: ~a"
             (validation-result-failed-step baseline)))
    (printf "[~a] Baseline: PASSED\n" branch)

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
      (printf "[~a] Pushing and creating PR...\n" branch)
      ;; Push from worktree
      (shell!/dir wt-path "git" "push" "-u" "origin" branch)
      (set! pr-url
        (gh-create-and-merge-pr! wt-repo mode-obj (reverse kept-tasks)))
      (printf "[~a] PR: ~a\n" branch pr-url)))

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

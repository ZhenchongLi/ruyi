#lang racket/base
(require racket/format racket/list racket/string)
(require "config.rkt" "claude.rkt" "git.rkt" "validate.rkt" "log.rkt")
(provide evolution-loop)

;; ============================================================
;; Core evolution loop — deterministic backbone
;; ============================================================

(define (evolution-loop repo mode-obj)
  "Run the evolution loop: select → implement → validate → keep/discard."

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

  ;; Init log
  (log-init! repo)

  ;; Main loop
  (let loop ([i 1]
             [consecutive-fails 0]
             [done '()])

    (cond
      ;; Termination: iteration limit
      [(> i (repo-config-max-iterations repo))
       (printf "\nReached iteration limit (~a).\n"
               (repo-config-max-iterations repo))
       (print-summary done)]

      ;; Termination: consecutive failures
      [(>= consecutive-fails (repo-config-max-consecutive-fails repo))
       (printf "\n~a consecutive failures. Stopping.\n" consecutive-fails)
       (print-summary done)]

      ;; Normal execution
      [else
       ;; Step 1: Select task
       (define tsk ((mode-select-task mode-obj) repo done))

       (cond
         [(not tsk)
          (printf "\nNo more tasks found.\n")
          (print-summary done)]

         [else
          (printf "\n[~a/~a] ~a\n" i (repo-config-max-iterations repo)
                  (task-description tsk))

          ;; Step 2-4: Execute one iteration
          (define result (execute-one-iteration repo mode-obj tsk))

          ;; Step 5: Log
          (log-iteration! repo (mode-name mode-obj) tsk result)

          ;; Print result
          (printf "  ~a ~a\n"
                  (if (eq? (iteration-result-status result) 'keep) "+" "-")
                  (iteration-result-detail result))

          ;; Continue
          (loop (add1 i)
                (if (eq? (iteration-result-status result) 'discard)
                    (add1 consecutive-fails)
                    0)
                (cons tsk done))])])))

;; ============================================================
;; Single iteration execution
;; ============================================================

(define (execute-one-iteration repo mode-obj tsk)
  "Execute one iteration with full safety wrapping."
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

    ;; 4. Run validation gate
    (define validation (run-validation-gate repo))
    (cond
      [(validation-result-passed? validation)
       ;; All passed — commit
       (define hash (git-commit! repo mode-obj tsk))
       (iteration-result 'keep hash)]
      [else
       ;; Failed — revert
       (git-revert! repo)
       (iteration-result 'discard
                         (format "Validation failed: ~a"
                                 (validation-result-failed-step validation)))])))

;; ============================================================
;; Summary
;; ============================================================

(define (print-summary done-tasks)
  (define total (length done-tasks))
  (printf "\n=== Summary ===\n")
  (printf "Total iterations: ~a\n" total)
  (printf "================\n"))

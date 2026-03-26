#lang racket/base
(require racket/format racket/list racket/string racket/file racket/port)
(require "config.rkt" "claude.rkt" "git.rkt" "validate.rkt" "log.rkt" "judge.rkt")
;; read-line-interactive is provided by claude.rkt via (all-defined-out)
(provide evolution-loop human-feedback)

;; Global parameter: human feedback from last interactive prompt
(define human-feedback (make-parameter ""))

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

  ;; Init log + journal
  (log-init! repo)
  (journal-init! repo (mode-name mode-obj))

  ;; Main loop
  (let loop ([i 1]
             [consecutive-fails 0]
             [done '()]
             [user-feedback ""])

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

          ;; Pass human feedback to mode (if supported)
          (when (and (task-extra tsk)
                     (hash-has-key? (task-extra tsk) 'set-human-input!))
            ((hash-ref (task-extra tsk) 'set-human-input!) user-feedback))

          ;; Step 2-4: Execute one iteration
          (define result (execute-one-iteration repo mode-obj tsk))

          ;; Step 5: Log
          (log-iteration! repo (mode-name mode-obj) tsk result)

          ;; Print result
          (printf "  ~a ~a\n"
                  (if (eq? (iteration-result-status result) 'keep) "+" "-")
                  (iteration-result-detail result))

          ;; Ask user for feedback (interactive)
          (define input (read-line-interactive "\n  > "))
          (define new-feedback
            (cond
              [(string=? input "stop")
               (printf "\nStopped by user.\n")
               (print-summary done)
               (exit 0)]
              [else input]))

          ;; Continue — only add to done if kept (so discarded docs can retry)
          (loop (add1 i)
                (if (eq? (iteration-result-status result) 'discard)
                    (add1 consecutive-fails)
                    0)
                (if (eq? (iteration-result-status result) 'keep)
                    (cons tsk done)
                    done)
                new-feedback)])])))

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
       ;; Always pass feedback to next round (whether keep or discard)
       (set-feedback! score weaknesses feedback)
       ;; Journal detailed entry
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
          (printf "  Weaknesses: ~a\n" (string-join weaknesses "; "))
          (iteration-result 'keep (format "~a (score: ~a)" hash score))]
         [else
          (printf "  Score ~a < ~a (min). Weaknesses: ~a\n"
                  score min-score (string-join weaknesses "; "))
          (git-revert! repo)
          (iteration-result 'discard
                            (format "Score ~a < ~a" score min-score))])]

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
;; Summary
;; ============================================================

(define (print-summary done-tasks)
  (define total (length done-tasks))
  (printf "\n=== Summary ===\n")
  (printf "Total iterations: ~a\n" total)
  (printf "================\n"))

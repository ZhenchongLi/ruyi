#lang racket/base
(require racket/format racket/list racket/string racket/file racket/port)
(require "config.rkt" "claude.rkt" "git.rkt" "validate.rkt" "log.rkt" "judge.rkt")
(provide evolution-loop)

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

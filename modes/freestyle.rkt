#lang racket/base
(require racket/string racket/format racket/file racket/path racket/list)
(require "../config.rkt" "../tasks.rkt" "../claude.rkt")
(provide freestyle-mode make-freestyle-mode)

;; ============================================================
;; Freestyle mode: user says what they want, Claude implements
;;
;; Two-step process:
;;   1. Claude asks clarifying questions (interactive)
;;   2. Claude implements the precise spec (deterministic loop)
;; ============================================================

(define (make-freestyle-mode initial-goal #:clarify? [clarify? #t] #:repo-path [repo-path #f])
  "Create a freestyle mode. If clarify? is #t, runs interactive Q&A first."
  (define refined-goal
    (if (and clarify? repo-path (not (string=? initial-goal "")))
        (claude-clarify repo-path initial-goal)
        initial-goal))

  (define iteration-count 0)

  (define (freestyle-select-task repo done-tasks)
    (set! iteration-count (add1 iteration-count))
    (if (> iteration-count 1)
        #f  ;; one shot per goal
        (task ""
              (format "Freestyle: ~a"
                      (if (> (string-length refined-goal) 60)
                          (string-append (substring refined-goal 0 60) "...")
                          refined-goal))
              1
              (make-immutable-hash
               (list (cons 'goal refined-goal))))))

  (define (freestyle-build-prompt repo tsk)
    (define user-goal (hash-ref (task-extra tsk) 'goal))
    (define context-content
      (for/fold ([ctx ""])
                ([cf (in-list (repo-config-context-files repo))])
        (define full-path (build-path (repo-config-path repo) cf))
        (if (file-exists? full-path)
            (string-append ctx "\n\n## " cf "\n\n" (file->string full-path))
            ctx)))

    (string-append
     "You are implementing a feature/change for this project.\n\n"
     "## Precise task specification\n\n"
     user-goal "\n\n"
     "## Rules\n\n"
     "- Read the relevant source files before making changes.\n"
     "- Write or update tests for any code you change.\n"
     "- Keep changes focused and minimal.\n"
     "- Do NOT modify: "
     (string-join (repo-config-forbidden-files repo) ", ") "\n"
     "- Follow the project's existing patterns and conventions.\n\n"
     "## Project context\n" context-content))

  (mode 'freestyle
        freestyle-select-task
        freestyle-build-prompt
        "evolve/freestyle"
        "evolve(freestyle)"))

;; Default instance (goal set at runtime)
(define freestyle-mode (make-freestyle-mode "" #:clarify? #f))

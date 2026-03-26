#lang racket/base
(require racket/string racket/format racket/file racket/path racket/list)
(require "../config.rkt" "../tasks.rkt" "../claude.rkt")
(provide freestyle-mode make-freestyle-mode)

;; ============================================================
;; Freestyle mode: user says what they want, Claude implements
;;
;; Two-step process:
;;   1. Prepare: clarify → break into subtasks → confirm
;;   2. Loop: execute each subtask → validate → keep/discard
;; ============================================================

(define (parse-subtasks spec)
  "Extract SUBTASK lines from the spec string."
  (define lines (string-split spec "\n"))
  (filter (lambda (s) (not (string=? s "")))
          (map (lambda (line)
                 (define trimmed (string-trim line))
                 (cond
                   [(regexp-match #rx"^SUBTASK [0-9]+[.:] *(.*)" trimmed)
                    => (lambda (m) (second m))]
                   [else #f]))
               lines)))

(define (parse-overview spec)
  "Extract OVERVIEW line from the spec string."
  (define lines (string-split spec "\n"))
  (for/or ([line (in-list lines)])
    (define trimmed (string-trim line))
    (define m (regexp-match #rx"^OVERVIEW[.:] *(.*)" trimmed))
    (and m (second m))))

(define (make-freestyle-mode initial-goal #:clarify? [clarify? #t] #:repo-path [repo-path #f])
  "Create a freestyle mode. If clarify? is #t, runs interactive Q&A first."
  (define refined-spec
    (if (and clarify? repo-path (not (string=? initial-goal "")))
        (claude-clarify repo-path initial-goal)
        (string-append "OVERVIEW: " initial-goal "\nSUBTASK 1: " initial-goal)))

  (define subtasks (parse-subtasks refined-spec))
  (define overview (or (parse-overview refined-spec) initial-goal))
  (define remaining-tasks (box subtasks))

  (printf "\nGoal: ~a\n" overview)
  (printf "Subtasks: ~a\n\n" (length subtasks))
  (for ([st (in-list subtasks)] [i (in-naturals 1)])
    (printf "  ~a. ~a\n" i st))
  (printf "\n")

  (define (freestyle-select-task repo done-tasks)
    (define remaining (unbox remaining-tasks))
    (if (empty? remaining)
        #f
        (let ([next-task (first remaining)])
          (set-box! remaining-tasks (rest remaining))
          (task ""
                (format "~a" (if (> (string-length next-task) 70)
                                 (string-append (substring next-task 0 70) "...")
                                 next-task))
                1
                (make-immutable-hash
                 (list (cons 'goal next-task)
                       (cons 'overview overview)))))))

  (define (freestyle-build-prompt repo tsk)
    (define subtask-goal (hash-ref (task-extra tsk) 'goal))
    (define full-overview (hash-ref (task-extra tsk) 'overview))
    (define context-content
      (for/fold ([ctx ""])
                ([cf (in-list (repo-config-context-files repo))])
        (define full-path (build-path (repo-config-path repo) cf))
        (if (file-exists? full-path)
            (string-append ctx "\n\n## " cf "\n\n" (file->string full-path))
            ctx)))

    (string-append
     "You are implementing one step of a larger goal.\n\n"
     "## Overall goal\n\n" full-overview "\n\n"
     "## This step\n\n" subtask-goal "\n\n"
     "## Rules\n\n"
     "- Read the relevant source files before making changes.\n"
     "- Write or update tests for any code you change.\n"
     "- Keep changes focused — ONLY do this one step, nothing more.\n"
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

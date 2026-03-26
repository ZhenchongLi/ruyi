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
  (filter-map (lambda (line)
                (define trimmed (string-trim line))
                (define m (regexp-match #rx"^SUBTASK [0-9]+[.:] *(.*)" trimmed))
                (and m (not (string=? (second m) "")) (second m)))
              lines))

(define (parse-overview spec)
  "Extract OVERVIEW line from the spec string."
  (define lines (string-split spec "\n"))
  (for/or ([line (in-list lines)])
    (define trimmed (string-trim line))
    (define m (regexp-match #rx"^OVERVIEW[.:] *(.*)" trimmed))
    (and m (second m))))

(define (parse-validate spec)
  "Extract VALIDATE line. Returns #t if yes or missing, #f if no."
  (define m (regexp-match #rx"(?i:VALIDATE[.:]\\s*(yes|no))" spec))
  (if m
      (string=? (string-downcase (second m)) "yes")
      #t))  ; default: validate

(define (parse-max-revisions spec)
  "Extract MAX_REVISIONS. Returns integer 1-5, default 2."
  (define m (regexp-match #rx"(?i:MAX_REVISIONS[.:]\\s*([0-9]+))" spec))
  (if m (min 5 (max 1 (or (string->number (second m)) 2))) 2))

(define (parse-min-score spec)
  "Extract MIN_SCORE. Returns integer 1-10, default 8."
  (define m (regexp-match #rx"(?i:MIN_SCORE[.:]\\s*([0-9]+))" spec))
  (if m (min 10 (max 1 (or (string->number (second m)) 8))) 8))

(define (parse-max-diff spec)
  "Extract MAX_DIFF. Returns integer, default 500."
  (define m (regexp-match #rx"(?i:MAX_DIFF[.:]\\s*([0-9]+))" spec))
  (if m (max 50 (or (string->number (second m)) 500)) 500))

(define (parse-reviewer-model spec)
  "Extract REVIEWER_MODEL. Returns string, default 'sonnet'."
  (define m (regexp-match #rx"(?i:REVIEWER_MODEL[.:]\\s*(sonnet|opus|haiku))" spec))
  (if m (string-downcase (second m)) "sonnet"))

(define (parse-auto-merge spec)
  "Extract AUTO_MERGE. Returns #t if yes or missing, #f if no."
  (define m (regexp-match #rx"(?i:AUTO_MERGE[.:]\\s*(yes|no))" spec))
  (if m (string=? (string-downcase (second m)) "yes") #t))

(define (parse-list-field spec field-name)
  "Extract a comma-separated list field. Returns list of strings."
  (define pattern (regexp (string-append "(?i:" field-name "[.:]\\s*(.+))")))
  (define m (regexp-match pattern spec))
  (if (and m (not (regexp-match? #rx"(?i:none)" (second m))))
      (map string-trim (string-split (second m) ","))
      '()))

(define (make-freestyle-mode initial-goal #:clarify? [clarify? #t] #:repo-path [repo-path #f])
  "Create a freestyle mode. If clarify? is #t, runs interactive Q&A first."
  (define refined-spec
    (if (and clarify? repo-path (not (string=? initial-goal "")))
        (claude-clarify repo-path initial-goal)
        (string-append "OVERVIEW: " initial-goal "\nSUBTASK 1: " initial-goal)))

  ;; Parse all parameters from spec
  (define subtasks (parse-subtasks refined-spec))
  (define overview (or (parse-overview refined-spec) initial-goal))
  (define needs-validation? (parse-validate refined-spec))
  (define max-revisions (parse-max-revisions refined-spec))
  (define min-score (parse-min-score refined-spec))
  (define max-diff (parse-max-diff refined-spec))
  (define reviewer-model (parse-reviewer-model refined-spec))
  (define auto-merge? (parse-auto-merge refined-spec))
  (define forbidden (parse-list-field refined-spec "FORBIDDEN"))
  (define context-files (parse-list-field refined-spec "CONTEXT"))
  (define remaining-tasks (box subtasks))

  ;; Show config
  (printf "\nGoal: ~a\n" overview)
  (printf "Validate: ~a | Revisions: ~a | Min score: ~a | Max diff: ~a\n"
          (if needs-validation? "yes" "no") max-revisions min-score max-diff)
  (printf "Reviewer: ~a | Auto-merge: ~a\n" reviewer-model (if auto-merge? "yes" "no"))
  (when (not (null? forbidden))
    (printf "Forbidden: ~a\n" (string-join forbidden ", ")))
  (when (not (null? context-files))
    (printf "Context: ~a\n" (string-join context-files ", ")))
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
                       (cons 'overview overview)
                       (cons 'skip-validation (not needs-validation?))
                       (cons 'max-revisions max-revisions)
                       (cons 'min-score min-score)
                       (cons 'max-diff max-diff)
                       (cons 'reviewer-model reviewer-model)
                       (cons 'auto-merge auto-merge?)
                       (cons 'forbidden forbidden)
                       (cons 'context-files context-files)))))))

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

    (define user-ctx
      (if (hash-has-key? (task-extra tsk) 'user-context)
          (hash-ref (task-extra tsk) 'user-context)
          ""))

    (define reviewer-fb
      (if (hash-has-key? (task-extra tsk) 'reviewer-feedback)
          (hash-ref (task-extra tsk) 'reviewer-feedback)
          ""))

    (string-append
     "You are implementing one step of a larger goal.\n\n"
     "## Overall goal\n\n" full-overview "\n\n"
     "## This step\n\n" subtask-goal "\n\n"
     (if (string=? reviewer-fb "")
         ""
         (string-append "## Issues found in your previous attempt\n\n"
                        reviewer-fb "\n\n"
                        "Fix these issues in this attempt.\n\n"))
     (if (string=? user-ctx "")
         ""
         (string-append "## User feedback from previous iterations\n\n"
                        user-ctx "\n\n"))
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

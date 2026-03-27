#lang racket/base
(require racket/string racket/format racket/file racket/path racket/list)
(require "../config.rkt" "../tasks.rkt" "../claude.rkt")
(provide make-freestyle-mode)

;; ============================================================
;; Freestyle mode: user says what they want, Claude implements
;; ============================================================

(define (parse-goal spec)
  "Extract GOAL line from the spec string."
  (define m (regexp-match #rx"(?i:GOAL[.:] *(.+))" spec))
  (if m (second m) ""))

(define (parse-judgement spec)
  "Extract JUDGEMENT line from the spec string."
  (define m (regexp-match #rx"(?i:JUDGEMENT[.:] *(.+))" spec))
  (if m (second m) ""))

(define (parse-max-revisions spec)
  "Extract MAX_REVISIONS. Returns integer 1-5, default 3."
  (define m (regexp-match #rx"(?i:MAX_REVISIONS[.:]\\s*([0-9]+))" spec))
  (if m (min 5 (max 1 (or (string->number (second m)) 3))) 3))

(define (parse-min-score spec)
  "Extract MIN_SCORE. Returns integer 1-10, default 8."
  (define m (regexp-match #rx"(?i:MIN_SCORE[.:]\\s*([0-9]+))" spec))
  (if m (min 10 (max 1 (or (string->number (second m)) 8))) 8))

(define (make-freestyle-mode initial-goal #:clarify? [clarify? #t] #:repo-path [repo-path #f])
  "Create a freestyle mode. If clarify? is #t, runs interactive Q&A first."
  (define refined-spec
    (if (and clarify? repo-path (not (string=? initial-goal "")))
        (claude-clarify repo-path initial-goal)
        (string-append "GOAL: " initial-goal)))

  ;; Parse spec
  (define goal (let ([g (parse-goal refined-spec)]) (if (string=? g "") initial-goal g)))
  (define judgement (parse-judgement refined-spec))
  (define max-revisions (parse-max-revisions refined-spec))
  (define min-score (parse-min-score refined-spec))
  (define done? (box #f))

  ;; Show config
  (printf "\nGoal: ~a\n" goal)
  (printf "Judgement: ~a\n" judgement)
  (printf "Revisions: ~a | Min score: ~a\n" max-revisions min-score)
  (printf "\n")

  (define (freestyle-select-task repo done-tasks)
    (if (unbox done?)
        #f
        (begin
          (set-box! done? #t)
          (task ""
                (if (> (string-length goal) 70)
                    (string-append (substring goal 0 70) "...")
                    goal)
                1
                (make-immutable-hash
                 (list (cons 'goal goal)
                       (cons 'overview goal)
                       (cons 'max-revisions max-revisions)
                       (cons 'min-score min-score)
                       (cons 'judgement judgement)))))))

  (define (freestyle-build-prompt repo tsk)
    (define task-goal (hash-ref (task-extra tsk) 'goal))
    (define context-content
      (for/fold ([ctx ""])
                ([cf (in-list (repo-config-context-files repo))])
        (define full-path (build-path (repo-config-path repo) cf))
        (if (file-exists? full-path)
            (string-append ctx "\n\n## " cf "\n\n" (file->string full-path))
            ctx)))

    (define reviewer-fb
      (if (hash-has-key? (task-extra tsk) 'reviewer-feedback)
          (hash-ref (task-extra tsk) 'reviewer-feedback)
          ""))

    (string-append
     "## Goal\n\n" task-goal "\n\n"
     (if (string=? reviewer-fb "")
         ""
         (string-append "## Issues found in your previous attempt\n\n"
                        reviewer-fb "\n\n"
                        "Fix these issues in this attempt.\n\n"))
     "## Rules\n\n"
     "- Read the relevant source files before making changes.\n"
     "- Write or update tests for any code you change.\n"
     "- Keep changes focused on the goal.\n"
     "- Do NOT modify: "
     (string-join (repo-config-forbidden-files repo) ", ") "\n"
     "- Follow the project's existing patterns and conventions.\n"
     "- Do NOT run git add, git commit, or any git commands. Just write files — the harness handles git.\n\n"
     (if (string=? context-content "") ""
         (string-append "## Project context\n" context-content))))

  (mode 'freestyle
        freestyle-select-task
        freestyle-build-prompt
        "evolve/freestyle"
        "evolve(freestyle)"))

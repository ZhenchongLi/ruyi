#lang racket/base
(require racket/string racket/port racket/system racket/format racket/file)
(require "config.rkt")
(provide (all-defined-out))

;; ============================================================
;; Claude Code subprocess integration
;; ============================================================

(define CLAUDE-PATH
  (or (find-executable-path "claude")
      "/Users/lizc/.local/bin/claude"))

(define DEFAULT-MODEL "opus")
(define CLAUDE-TIMEOUT 300) ; seconds

(define (claude-execute repo-path prompt
                        #:model [model DEFAULT-MODEL]
                        #:timeout [timeout CLAUDE-TIMEOUT])
  "Call claude -p with prompt via temp files, return (values success? output)."

  ;; Write prompt to temp file (avoids shell arg length limits)
  (define tmp-prompt (make-temporary-file "ruyi-prompt-~a.txt"))
  (define tmp-output (make-temporary-file "ruyi-output-~a.txt"))
  (define tmp-err (make-temporary-file "ruyi-err-~a.txt"))
  (call-with-output-file tmp-prompt
    (lambda (out) (display prompt out))
    #:exists 'replace)

  ;; Forward proxy env vars from parent process
  (define proxy-env
    (string-join
     (filter (lambda (s) (not (string=? s "")))
             (map (lambda (v)
                    (define val (getenv v))
                    (if val (format "export ~a='~a';" v val) ""))
                  '("https_proxy" "http_proxy" "all_proxy"
                    "HTTPS_PROXY" "HTTP_PROXY" "ALL_PROXY")))
     " "))

  (define cmd
    (format "~a cd ~a && ~a -p --dangerously-skip-permissions --model ~a < ~a > ~a 2> ~a"
            proxy-env
            (path->string repo-path)
            (path->string CLAUDE-PATH)
            model
            (path->string tmp-prompt)
            (path->string tmp-output)
            (path->string tmp-err)))

  ;; Run with timeout
  (define done-channel (make-channel))
  (define worker
    (thread
     (lambda ()
       (define exit-code
         (parameterize ([current-directory repo-path])
           (system/exit-code (format "/bin/bash -c ~a" (shell-quote cmd)))))
       (channel-put done-channel exit-code))))

  (define result (sync/timeout timeout done-channel))

  ;; Read output
  (define output
    (if (file-exists? tmp-output) (file->string tmp-output) ""))

  ;; Cleanup
  (for ([f (list tmp-prompt tmp-output tmp-err)])
    (with-handlers ([exn:fail? (lambda (_) (void))])
      (delete-file f)))

  (cond
    [result (values (zero? result) output)]
    [else
     (kill-thread worker)
     (values #f "TIMEOUT")]))

(define (claude-implement repo mode-obj tsk)
  "Plan first, confirm, then implement."
  (define prompt ((mode-build-prompt mode-obj) repo tsk))
  (define repo-path (repo-config-path repo))

  ;; Step 1: Ask Claude to output a plan (lightweight, no full context)
  (printf "  Planning... ")
  (flush-output)
  (define task-desc (task-description tsk))
  (define goal-text
    (if (and (task-extra tsk) (hash-has-key? (task-extra tsk) 'goal))
        (hash-ref (task-extra tsk) 'goal)
        task-desc))
  (define plan-prompt
    (string-append
     "You are planning a code change. Do NOT write code yet.\n\n"
     "Task: " goal-text "\n\n"
     "Output a brief plan:\n"
     "- What files to create or modify\n"
     "- What changes to make (1-2 lines each)\n"
     "- What tests to add\n\n"
     "Start with 'Plan:' and keep it concise."))

  (define-values (plan-ok? plan)
    (claude-execute repo-path plan-prompt #:model "sonnet" #:timeout 60))

  ;; Show plan, then auto-execute
  (cond
    [(not plan-ok?)
     (printf "skipped\n  Implementing... ")
     (flush-output)]
    [else
     (printf "done\n\n")
     (displayln (string-trim plan))
     (printf "\n  Implementing... ")
     (flush-output)])

  (define-values (ok? output)
    (claude-execute repo-path prompt))
  (if ok?
      (begin (printf "done\n") #t)
      (begin (printf "failed\n") #f)))

;; ============================================================
;; Interactive Claude: clarify requirements before execution
;; ============================================================

(define (claude-clarify repo-path initial-goal)
  "Use Claude interactively to clarify a vague goal into a precise spec.
   Returns a detailed task description string."
  (printf "\nClarifying your goal with Claude...\n\n")

  ;; Step 1: Ask Claude to generate clarifying questions
  (define question-prompt
    (string-append
     "A user wants to make a change to their project. Their goal is:\n\n"
     "\"" initial-goal "\"\n\n"
     "Ask 2-3 short clarifying questions to understand exactly what they need.\n"
     "Format: one question per line, numbered.\n"
     "Only output the questions, nothing else."))

  (define-values (q-ok? questions)
    (claude-execute repo-path question-prompt #:model "sonnet" #:timeout 30))

  (unless q-ok?
    (printf "Could not generate questions. Using goal as-is.\n")
    (printf "~a\n\n" initial-goal))

  (when q-ok?
    (displayln questions)
    (printf "\n"))

  ;; Step 2: Collect user answers
  (printf "Your answers (type each answer, press Enter; empty line when done):\n")
  (define answers
    (let loop ([acc '()])
      (define line (read-line-interactive "  > "))
      (cond
        [(string=? line "") (reverse acc)]
        [else (loop (cons line acc))])))

  ;; Step 3: Ask Claude to synthesize into precise subtasks
  (printf "Synthesizing task spec...\n")
  (define spec-prompt
    (string-append
     "A user wants to modify their project.\n\n"
     "Original goal: \"" initial-goal "\"\n\n"
     (if q-ok?
         (string-append "Clarifying questions:\n" questions "\n\n")
         "")
     "User's answers:\n"
     (string-join (map (lambda (a) (string-append "- " a)) answers) "\n")
     "\n\n"
     "Break this into small, independent subtasks that can be implemented one at a time.\n"
     "Each subtask should be completable in a single commit.\n\n"
     "Format:\n"
     "OVERVIEW: one sentence summary of the full goal\n\n"
     "SUBTASK 1: <precise description of what to do>\n"
     "SUBTASK 2: <precise description of what to do>\n"
     "SUBTASK 3: ...\n\n"
     "Keep subtasks small. 3-7 subtasks is ideal. Order them by dependency (do first things first).\n"
     "Output only the overview and subtasks, nothing else."))

  (define-values (s-ok? spec)
    (claude-execute repo-path spec-prompt #:model "opus" #:timeout 120))

  (unless s-ok?
    (printf "Warning: synthesis failed, using goal directly.\n"))

  (define final-spec
    (if (and s-ok? (> (string-length (string-trim spec)) 0))
        (string-trim spec)
        ;; Fallback: combine goal + answers as single task
        (string-append "OVERVIEW: " initial-goal "\n\n"
                       "SUBTASK 1: " initial-goal "\n"
                       "User clarifications:\n"
                       (string-join (map (lambda (a) (string-append "- " a)) answers) "\n"))))

  (printf "\n--- Task spec ---\n~a\n-----------------\n\n" final-spec)
  (define confirm (read-line-interactive "Proceed? (Enter = yes, or type changes) > "))

  (cond
    [(string=? confirm "")
     final-spec]
    [(string=? confirm "no")
     (printf "Cancelled.\n")
     (exit 0)]
    [else
     ;; User wants changes — append their input
     (string-append final-spec "\n\nAdditional requirements: " confirm)]))

;; ============================================================
;; Interactive input helper (supports CJK and line editing)
;; ============================================================

(define (read-line-interactive prompt-str)
  "Read a line using bash's read for proper CJK and line editing support."
  (define tmp-out (make-temporary-file "ruyi-input-~a.txt"))
  (define cmd
    (format "/bin/bash -c 'read -e -p \"~a\" line && echo \"$line\" > ~a'"
            (string-replace prompt-str "'" "'\\''")
            (path->string tmp-out)))
  (define exit-code (system/exit-code cmd))
  (define result
    (cond
      [(and (zero? exit-code) (file-exists? tmp-out))
       (define content (string-trim (file->string tmp-out)))
       content]
      [else ""]))
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (delete-file tmp-out))
  result)

;; ============================================================
;; Shell quoting helper
;; ============================================================

(define (shell-quote s)
  "Quote a string for shell use."
  (string-append "'"
                 (string-replace s "'" "'\\''")
                 "'"))

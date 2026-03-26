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

(define (claude-execute repo-path-raw prompt
                        #:model [model DEFAULT-MODEL]
                        #:timeout [timeout CLAUDE-TIMEOUT])
  "Call claude -p (print mode, no tools) for lightweight queries.
   Returns (values success? output)."
  (define repo-path
    (if (string? repo-path-raw) (string->path repo-path-raw) repo-path-raw))

  (define tmp-prompt (make-temporary-file "ruyi-prompt-~a.txt"))
  (define tmp-output (make-temporary-file "ruyi-output-~a.txt"))
  (define tmp-err (make-temporary-file "ruyi-err-~a.txt"))
  (call-with-output-file tmp-prompt
    (lambda (out) (display prompt out))
    #:exists 'replace)

  (define proxy-env (build-proxy-env))

  (define cmd
    (format "~a cd ~a && ~a -p --dangerously-skip-permissions --model ~a < ~a > ~a 2> ~a"
            proxy-env
            (path->string repo-path)
            (path->string CLAUDE-PATH)
            model
            (path->string tmp-prompt)
            (path->string tmp-output)
            (path->string tmp-err)))

  (define-values (exit-code _timeout?)
    (run-with-timeout cmd repo-path timeout))

  (define output
    (if (file-exists? tmp-output) (file->string tmp-output) ""))

  (for ([f (list tmp-prompt tmp-output tmp-err)])
    (with-handlers ([exn:fail? (lambda (_) (void))])
      (delete-file f)))

  (if exit-code
      (values (zero? exit-code) output)
      (values #f "TIMEOUT")))

(define (claude-agent repo-path-raw prompt
                       #:model [model DEFAULT-MODEL]
                       #:timeout [timeout (* CLAUDE-TIMEOUT 2)])
  "Call claude in full agent mode (reads files, runs commands, iterates).
   Returns (values success? output)."
  (define repo-path
    (if (string? repo-path-raw) (string->path repo-path-raw) repo-path-raw))

  (define tmp-prompt (make-temporary-file "ruyi-prompt-~a.txt"))
  (define tmp-output (make-temporary-file "ruyi-output-~a.txt"))
  (define tmp-err (make-temporary-file "ruyi-err-~a.txt"))
  (call-with-output-file tmp-prompt
    (lambda (out) (display prompt out))
    #:exists 'replace)

  (define proxy-env (build-proxy-env))

  ;; Full agent mode: no -p, Claude Code uses all tools
  (define cmd
    (format "~a cd ~a && ~a --dangerously-skip-permissions --model ~a -p < ~a > ~a 2> ~a"
            proxy-env
            (path->string repo-path)
            (path->string CLAUDE-PATH)
            model
            (path->string tmp-prompt)
            (path->string tmp-output)
            (path->string tmp-err)))

  (define-values (exit-code _timeout?)
    (run-with-timeout cmd repo-path timeout))

  (define output
    (if (file-exists? tmp-output) (file->string tmp-output) ""))

  (for ([f (list tmp-prompt tmp-output tmp-err)])
    (with-handlers ([exn:fail? (lambda (_) (void))])
      (delete-file f)))

  (if exit-code
      (values (zero? exit-code) output)
      (values #f "TIMEOUT")))

;; ============================================================
;; Shared helpers
;; ============================================================

(define (build-proxy-env)
  (string-join
   (filter (lambda (s) (not (string=? s "")))
           (map (lambda (v)
                  (define val (getenv v))
                  (if val (format "export ~a='~a';" v val) ""))
                '("https_proxy" "http_proxy" "all_proxy"
                  "HTTPS_PROXY" "HTTP_PROXY" "ALL_PROXY")))
   " "))

(define (run-with-timeout cmd repo-path timeout)
  "Run cmd with timeout. Returns (values exit-code-or-#f timed-out?)."
  (define done-channel (make-channel))
  (define worker
    (thread
     (lambda ()
       (define exit-code
         (parameterize ([current-directory repo-path])
           (system/exit-code (format "/bin/bash -c ~a" (shell-quote cmd)))))
       (channel-put done-channel exit-code))))
  (define result (sync/timeout timeout done-channel))
  (cond
    [result (values result #f)]
    [else
     (kill-thread worker)
     (values #f #t)]))

(define (plan-says-skip? plan-text)
  "Check if the agent decided to skip planning for a simple task."
  (regexp-match? #rx"(?i:SKIP_PLAN)" (string-trim plan-text)))

(define (claude-implement repo mode-obj tsk)
  "Use Claude Code in full agent mode to implement a task.
   Claude reads files, writes code, runs tests, and iterates on its own."
  (define prompt ((mode-build-prompt mode-obj) repo tsk))
  (define repo-path (repo-config-path repo))

  (printf "  Implementing (agent mode)... ")
  (flush-output)

  (define-values (ok? output)
    (claude-agent repo-path prompt))
  (if ok?
      (begin (printf "done\n") #t)
      (begin (printf "failed\n") #f)))

;; ============================================================
;; Interactive Claude: clarify requirements before execution
;; ============================================================

(define (claude-clarify repo-path initial-goal)
  "Use Claude interactively to clarify a vague goal into a precise spec.
   Multi-round: Claude decides when it has enough info to proceed."
  (printf "\nClarifying your goal with Claude...\n\n")

  ;; Multi-round conversation loop
  (define conversation-history
    (list (string-append "User's goal: \"" initial-goal "\"")))

  (let round-loop ([round 1])
    ;; Ask Claude: more questions or ready to plan?
    (define round-prompt
      (string-append
       "You are helping a user plan a code change.\n\n"
       "Conversation so far:\n"
       (string-join conversation-history "\n") "\n\n"
       "Based on the conversation, decide:\n"
       "- If you need more info, output QUESTIONS: followed by 2-3 numbered questions.\n"
       "- If you have enough info, output READY\n\n"
       "Only output QUESTIONS: or READY, nothing else."))

    (define-values (ok? response)
      (claude-execute repo-path round-prompt #:model "sonnet" #:timeout 30))

    (cond
      ;; Claude wants more info
      [(and ok? (string-contains? response "QUESTIONS:"))
       (define questions
         (let ([m (regexp-match-positions #rx"QUESTIONS:" response)])
           (if m
               (string-trim (substring response (cdr (car m))))
               (string-trim response))))
       ;; Show questions to user (strip the "QUESTIONS:" prefix if regex missed)
       (displayln questions)
       (printf "\n")

       ;; Collect answers
       (printf "Your answers (Enter on empty line when done):\n")
       (define answers
         (let loop ([acc '()])
           (define line (read-line-interactive "  > "))
           (cond
             [(string=? line "") (reverse acc)]
             [else (loop (cons line acc))])))

       ;; Add to conversation
       (set! conversation-history
         (append conversation-history
                 (list (string-append "Agent questions (round " (number->string round) "):\n"
                                      questions))
                 (list (string-append "User answers (round " (number->string round) "):\n"
                                      (string-join
                                       (map (lambda (a) (string-append "- " a)) answers) "\n")))))

       ;; Continue (max 5 rounds to avoid infinite loop)
       (if (< round 5)
           (round-loop (add1 round))
           (void))]

      ;; Claude is ready or failed — proceed to synthesis
      [else (void)]))

  ;; Synthesize into subtasks
  (printf "\nSynthesizing task spec...\n")
  (define spec-prompt
    (string-append
     "A user wants to modify their project.\n\n"
     (string-join conversation-history "\n") "\n\n"
     "Break this into small, independent subtasks that can be implemented one at a time.\n"
     "Each subtask should be completable in a single commit.\n\n"
     "Format (output each on its own line, then subtasks):\n\n"
     "VALIDATE: yes or no (build/test after each subtask? yes for code, no for docs)\n"
     "MAX_REVISIONS: <1-5> (review-revise rounds per subtask, default 2)\n"
     "MIN_SCORE: <1-10> (minimum reviewer score to approve, default 8)\n"
     "MAX_DIFF: <number> (max diff lines per subtask, default 500)\n"
     "REVIEWER_MODEL: sonnet or opus (which model reviews, default sonnet)\n"
     "AUTO_MERGE: yes or no (auto-merge PR when done, default yes)\n"
     "FORBIDDEN: file1, file2, ... (files not to touch, or 'none')\n"
     "CONTEXT: file1, file2, ... (reference files to read, or 'none')\n\n"
     "OVERVIEW: one sentence summary of the full goal\n\n"
     "SUBTASK 1: <precise description of what to do>\n"
     "SUBTASK 2: <precise description of what to do>\n"
     "SUBTASK 3: ...\n\n"
     "Keep subtasks small. 3-7 subtasks is ideal. Order them by dependency.\n"
     "Only output the parameters, OVERVIEW, and SUBTASKs. "
     "Respect the user's explicit preferences when they specify constraints."))

  (define-values (s-ok? spec)
    (claude-execute repo-path spec-prompt #:model "opus" #:timeout 120))

  (unless s-ok?
    (printf "Warning: synthesis failed, using goal directly.\n"))

  (define final-spec
    (if (and s-ok? (> (string-length (string-trim spec)) 0))
        (string-trim spec)
        (string-append "OVERVIEW: " initial-goal "\n\n"
                       "SUBTASK 1: " initial-goal)))

  (printf "\n--- Task spec ---\n~a\n-----------------\n\n" final-spec)
  (define confirm (read-line-interactive "Proceed? (Enter = yes, or type changes) > "))

  (cond
    [(string=? confirm "")
     final-spec]
    [(string=? confirm "no")
     (printf "Cancelled.\n")
     (exit 0)]
    [else
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

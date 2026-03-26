#lang racket/base
(require racket/string racket/port racket/system racket/format)
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
  "Call claude -p with a prompt, return (values success? output)."
  (define cmd
    (format "cd ~a && ~a -p --dangerously-skip-permissions --model ~a ~a"
            (path->string repo-path)
            (path->string CLAUDE-PATH)
            model
            (shell-quote prompt)))

  ;; Use process/ports for timeout control
  (define-values (proc stdout-in stdin-out stderr-in)
    (subprocess #f #f #f
                "/bin/bash" "-c" cmd))

  ;; Read output with timeout
  (define output-channel (make-channel))
  (define reader-thread
    (thread
     (lambda ()
       (define out (port->string stdout-in))
       (define err (port->string stderr-in))
       (close-input-port stdout-in)
       (close-input-port stderr-in)
       (channel-put output-channel (cons out err)))))

  ;; Wait with timeout
  (define result
    (sync/timeout timeout
                  (handle-evt (thread-dead-evt reader-thread)
                              (lambda (_)
                                (channel-get output-channel)))))

  (cond
    [result
     (subprocess-wait proc)
     (define exit-code (subprocess-status proc))
     (values (zero? exit-code) (car result))]
    [else
     ;; Timeout
     (subprocess-kill proc #t)
     (kill-thread reader-thread)
     (values #f "TIMEOUT")]))

(define (claude-implement repo mode-obj tsk)
  "Call Claude to implement a task. Returns #t if Claude completed."
  (define prompt ((mode-build-prompt mode-obj) repo tsk))
  (printf "  Calling Claude... ")
  (flush-output)
  (define-values (ok? output)
    (claude-execute (repo-config-path repo) prompt))
  (if ok?
      (begin (printf "done\n") #t)
      (begin (printf "failed\n") #f)))

;; ============================================================
;; Shell quoting helper
;; ============================================================

(define (shell-quote s)
  "Quote a string for shell use."
  (string-append "'"
                 (string-replace s "'" "'\\''")
                 "'"))

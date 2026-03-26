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

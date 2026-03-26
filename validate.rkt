#lang racket/base
(require racket/string racket/format)
(require "config.rkt" "git.rkt")
(provide (all-defined-out))

;; ============================================================
;; Validation gate
;; ============================================================

(struct validation-result
  (passed?       ; boolean
   failed-step   ; string or #f
   details)      ; string: stdout/stderr of failed step
  #:transparent)

(define (run-validation-gate repo)
  "Run all validation commands in order. Stop on first failure."
  (define commands (repo-config-validate-commands repo))
  (for/fold ([result (validation-result #t #f "")])
            ([cmd (in-list commands)]
             #:break (not (validation-result-passed? result)))
    (define cmd-str (string-join cmd " "))
    (printf "  Validate: ~a... " cmd-str)
    (flush-output)
    (define-values (code stdout stderr)
      (apply shell-in-dir (repo-config-path repo) cmd))
    (cond
      [(zero? code)
       (printf "OK\n")
       result]
      [else
       (printf "FAILED\n")
       (validation-result #f cmd-str (string-append stdout "\n" stderr))])))

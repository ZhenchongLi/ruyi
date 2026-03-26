#lang racket/base
(require rackunit racket/string racket/port racket/system racket/file)
(require (only-in "../config.rkt"
                  repo-config repo-config-validate-commands))
(require (only-in "../validate.rkt"
                  validation-result validation-result?
                  validation-result-passed? validation-result-failed-step
                  validation-result-details
                  run-validation-gate))

;; ============================================================
;; validation-result construction and field access
;; ============================================================

(test-case "validation-result passing"
  (define r (validation-result #t #f ""))
  (check-true (validation-result? r))
  (check-true (validation-result-passed? r))
  (check-false (validation-result-failed-step r))
  (check-equal? (validation-result-details r) ""))

(test-case "validation-result failing"
  (define r (validation-result #f "raco test ." "error: test failed"))
  (check-true (validation-result? r))
  (check-false (validation-result-passed? r))
  (check-equal? (validation-result-failed-step r) "raco test .")
  (check-equal? (validation-result-details r) "error: test failed"))

(test-case "validation-result transparency and equality"
  (define r1 (validation-result #t #f ""))
  (define r2 (validation-result #t #f ""))
  (check-equal? r1 r2)
  (define r3 (validation-result #f "cmd" "err"))
  (define r4 (validation-result #f "cmd" "err"))
  (check-equal? r3 r4)
  ;; different results are not equal
  (check-not-equal? r1 r3))

;; ============================================================
;; run-validation-gate with real commands
;; ============================================================

;; Use /tmp as the working directory since it always exists
(define tmp-dir
  (let ([d (make-temporary-file "ruyi-test-~a" 'directory)])
    (path->string d)))

(define (make-repo-with-commands cmds)
  (repo-config "test" tmp-dir "main" '() '() '() 'sibling #f '() cmds '() '()
               "log.tsv" 10 3 500))

(test-case "run-validation-gate with all passing commands"
  (define repo (make-repo-with-commands '(("true") ("true"))))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-true (validation-result-passed? r))
  (check-false (validation-result-failed-step r)))

(test-case "run-validation-gate with first command failing"
  (define repo (make-repo-with-commands '(("false") ("true"))))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-false (validation-result-passed? r))
  (check-equal? (validation-result-failed-step r) "false"))

(test-case "run-validation-gate with second command failing"
  (define repo (make-repo-with-commands '(("true") ("false"))))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-false (validation-result-passed? r))
  (check-equal? (validation-result-failed-step r) "false"))

(test-case "run-validation-gate stops at first failure (short-circuit)"
  ;; If the first command fails, the second should not run.
  ;; We test this by having the second command be something that would
  ;; create a file — if it runs, the file would exist.
  (define marker (build-path tmp-dir "should-not-exist"))
  (when (file-exists? (string->path (if (path? marker) (path->string marker) marker)))
    (delete-file marker))
  (define repo (make-repo-with-commands
                (list '("false")
                      (list "touch" (path->string marker)))))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-false (validation-result-passed? r))
  (check-false (file-exists? (if (string? marker) (string->path marker) marker))))

(test-case "run-validation-gate with empty command list passes"
  (define repo (make-repo-with-commands '()))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-true (validation-result-passed? r)))

(test-case "run-validation-gate captures output in details on failure"
  ;; Use echo to produce output, then exit with failure
  (define repo (make-repo-with-commands
                (list (list "sh" "-c" "echo 'validation error' && exit 1"))))
  (define r
    (let ([res #f])
      (with-output-to-string
        (lambda () (set! res (run-validation-gate repo))))
      res))
  (check-false (validation-result-passed? r))
  ;; The details should contain the output from the failed command
  (check-not-false (string-contains? (validation-result-details r) "validation error")))

(test-case "run-validation-gate prints progress"
  (define repo (make-repo-with-commands '(("true"))))
  (define output
    (with-output-to-string
      (lambda () (run-validation-gate repo))))
  (check-not-false (string-contains? output "Validate: true"))
  (check-not-false (string-contains? output "OK")))

(test-case "run-validation-gate prints FAILED on failure"
  (define repo (make-repo-with-commands '(("false"))))
  (define output
    (with-output-to-string
      (lambda () (run-validation-gate repo))))
  (check-not-false (string-contains? output "FAILED")))

;; Cleanup temp directory
(delete-directory tmp-dir)

(printf "All validate tests passed.\n")

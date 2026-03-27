#lang racket/base
(require rackunit racket/file)
(require "../task-file.rkt")

;; ============================================================
;; Tests for read-ruyi-task parsing
;; ============================================================

(test-case "read-ruyi-task parses all fields correctly"
  (define tmp (make-temporary-file "ruyi-task-~a.rkt"))
  (call-with-output-file tmp
    (lambda (out)
      (display
       (string-append
        "(ruyi-task\n"
        "  (goal \"Add widget support\")\n"
        "  (judgement \"must compile, tests pass, no regressions\")\n"
        "  (max-revisions 3)\n"
        "  (min-score 7))\n")
       out))
    #:exists 'replace)
  (define task (read-ruyi-task tmp))
  (check-equal? (ruyi-task-goal task) "Add widget support")
  (check-equal? (ruyi-task-judgement task) "must compile, tests pass, no regressions")
  (check-equal? (ruyi-task-max-revisions task) 3)
  (check-equal? (ruyi-task-min-score task) 7)
  (delete-file tmp))

(test-case "read-ruyi-task uses defaults for missing fields"
  (define tmp (make-temporary-file "ruyi-task-~a.rkt"))
  (call-with-output-file tmp
    (lambda (out)
      (display "(ruyi-task\n  (goal \"minimal task\"))\n" out))
    #:exists 'replace)
  (define task (read-ruyi-task tmp))
  (check-equal? (ruyi-task-goal task) "minimal task")
  (check-equal? (ruyi-task-judgement task) "")
  (check-equal? (ruyi-task-max-revisions task) 3)
  (check-equal? (ruyi-task-min-score task) 8)
  (delete-file tmp))

(test-case "read-ruyi-task defaults for completely empty body"
  (define tmp (make-temporary-file "ruyi-task-~a.rkt"))
  (call-with-output-file tmp
    (lambda (out) (display "(ruyi-task)\n" out))
    #:exists 'replace)
  (define task (read-ruyi-task tmp))
  (check-equal? (ruyi-task-goal task) "")
  (check-equal? (ruyi-task-judgement task) "")
  (check-equal? (ruyi-task-max-revisions task) 3)
  (check-equal? (ruyi-task-min-score task) 8)
  (delete-file tmp))

;; ============================================================
;; Tests for write-ruyi-task → read-ruyi-task round-trip
;; ============================================================

(test-case "write then read round-trip preserves all fields"
  (define tmp (make-temporary-file "ruyi-task-~a.rkt"))
  (define original
    (ruyi-task "Implement feature X"
               "ensure backward compatibility, all tests pass"
               4 9))
  (write-ruyi-task tmp original)
  (define loaded (read-ruyi-task tmp))
  (check-equal? (ruyi-task-goal loaded) "Implement feature X")
  (check-equal? (ruyi-task-judgement loaded) "ensure backward compatibility, all tests pass")
  (check-equal? (ruyi-task-max-revisions loaded) 4)
  (check-equal? (ruyi-task-min-score loaded) 9)
  (delete-file tmp))

(test-case "write then read round-trip with defaults"
  (define tmp (make-temporary-file "ruyi-task-~a.rkt"))
  (write-ruyi-task tmp DEFAULT-TASK)
  (define loaded (read-ruyi-task tmp))
  (check-equal? (ruyi-task-goal loaded) "")
  (check-equal? (ruyi-task-judgement loaded) "")
  (check-equal? (ruyi-task-max-revisions loaded) 3)
  (check-equal? (ruyi-task-min-score loaded) 8)
  (delete-file tmp))

;; ============================================================
;; Tests for slugify
;; ============================================================

(test-case "slugify: basic spaces to hyphens"
  (check-equal? (slugify "add widget support") "add-widget-support"))

(test-case "slugify: unicode (CJK) preserved"
  (check-equal? (slugify "修复登录问题") "修复登录问题"))

(test-case "slugify: mixed ascii and unicode"
  (check-equal? (slugify "fix 登录 bug") "fix-登录-bug"))

(test-case "slugify: leading and trailing punctuation stripped"
  (check-equal? (slugify "---hello world---") "hello-world"))

(test-case "slugify: special characters collapsed"
  (check-equal? (slugify "foo@bar#baz!qux") "foo-bar-baz-qux"))

(test-case "slugify: empty string"
  (check-equal? (slugify "") ""))

(test-case "slugify: truncates to 40 chars"
  (define long-goal "this is a very long goal description that exceeds the forty character limit")
  (define slug (slugify long-goal))
  (check-true (<= (string-length slug) 40)))

(test-case "slugify: all punctuation yields empty"
  (check-equal? (slugify "!!!@@@###") ""))

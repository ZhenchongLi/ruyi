#lang racket/base
(require rackunit racket/string)
(require (only-in "../config.rkt"
                  repo-config repo-config? repo-config-name repo-config-path
                  repo-config-base-branch repo-config-source-dirs
                  repo-config-source-exts repo-config-excluded-dirs
                  repo-config-test-pattern repo-config-test-alt-dir
                  repo-config-forbidden-files repo-config-validate-commands
                  repo-config-priority-dirs repo-config-context-files
                  repo-config-log-path repo-config-max-iterations
                  repo-config-max-consecutive-fails repo-config-max-diff-lines
                  mode mode? mode-name mode-select-task mode-build-prompt
                  mode-branch-prefix mode-commit-prefix
                  task task? task-source-file task-description task-priority task-extra
                  iteration-result iteration-result? iteration-result-status
                  iteration-result-detail
                  repo-full-path priority-for-file))

;; ============================================================
;; repo-config construction and field access
;; ============================================================

(define test-repo
  (repo-config "myrepo"
               "/home/user/myrepo"
               "main"
               '("src" "lib")
               '(".rkt" ".scrbl")
               '("node_modules" ".git")
               'mirror
               "__tests__"
               '("README.md")
               '(("raco" "test" ".") ("raco" "setup"))
               '(("src/core" . 1) ("src/utils" . 5))
               '("CLAUDE.md")
               "evolution-log.tsv"
               20
               5
               300))

(test-case "repo-config struct predicate"
  (check-true (repo-config? test-repo))
  (check-false (repo-config? "not a repo")))

(test-case "repo-config field accessors return correct values"
  (check-equal? (repo-config-name test-repo) "myrepo")
  (check-equal? (repo-config-path test-repo) "/home/user/myrepo")
  (check-equal? (repo-config-base-branch test-repo) "main")
  (check-equal? (repo-config-source-dirs test-repo) '("src" "lib"))
  (check-equal? (repo-config-source-exts test-repo) '(".rkt" ".scrbl"))
  (check-equal? (repo-config-excluded-dirs test-repo) '("node_modules" ".git"))
  (check-equal? (repo-config-test-pattern test-repo) 'mirror)
  (check-equal? (repo-config-test-alt-dir test-repo) "__tests__")
  (check-equal? (repo-config-forbidden-files test-repo) '("README.md"))
  (check-equal? (repo-config-validate-commands test-repo)
                '(("raco" "test" ".") ("raco" "setup")))
  (check-equal? (repo-config-priority-dirs test-repo)
                '(("src/core" . 1) ("src/utils" . 5)))
  (check-equal? (repo-config-context-files test-repo) '("CLAUDE.md"))
  (check-equal? (repo-config-log-path test-repo) "evolution-log.tsv")
  (check-equal? (repo-config-max-iterations test-repo) 20)
  (check-equal? (repo-config-max-consecutive-fails test-repo) 5)
  (check-equal? (repo-config-max-diff-lines test-repo) 300))

(test-case "repo-config with sibling test-pattern and no test-alt-dir"
  (define sibling-repo
    (repo-config "sibling" "/tmp/s" "develop" '("src") '(".rkt") '()
                 'sibling #f '() '() '() '() "log.tsv" 10 3 500))
  (check-equal? (repo-config-test-pattern sibling-repo) 'sibling)
  (check-false (repo-config-test-alt-dir sibling-repo)))

;; ============================================================
;; mode construction and field access
;; ============================================================

(define test-mode
  (mode 'coverage
        (lambda (repo done) #f)
        (lambda (repo tsk) "prompt text")
        "evolve/coverage"
        "evolve(coverage)"))

(test-case "mode struct predicate"
  (check-true (mode? test-mode))
  (check-false (mode? 42)))

(test-case "mode field accessors"
  (check-equal? (mode-name test-mode) 'coverage)
  (check-equal? (mode-branch-prefix test-mode) "evolve/coverage")
  (check-equal? (mode-commit-prefix test-mode) "evolve(coverage)"))

(test-case "mode functions are callable"
  (check-false ((mode-select-task test-mode) test-repo '()))
  (define t (task "a.rkt" "desc" 1 #f))
  (check-equal? ((mode-build-prompt test-mode) test-repo t) "prompt text"))

;; ============================================================
;; task construction and field access
;; ============================================================

(test-case "task struct predicate and fields"
  (define t (task "src/foo.rkt" "Add feature X" 2 (hash 'issue 42)))
  (check-true (task? t))
  (check-equal? (task-source-file t) "src/foo.rkt")
  (check-equal? (task-description t) "Add feature X")
  (check-equal? (task-priority t) 2)
  (check-equal? (task-extra t) (hash 'issue 42)))

(test-case "task with #f extra"
  (define t (task "src/bar.rkt" "Fix bug" 1 #f))
  (check-false (task-extra t)))

;; ============================================================
;; iteration-result construction and field access
;; ============================================================

(test-case "iteration-result keep"
  (define r (iteration-result 'keep "abc123"))
  (check-true (iteration-result? r))
  (check-equal? (iteration-result-status r) 'keep)
  (check-equal? (iteration-result-detail r) "abc123"))

(test-case "iteration-result discard"
  (define r (iteration-result 'discard "validation failed"))
  (check-equal? (iteration-result-status r) 'discard)
  (check-equal? (iteration-result-detail r) "validation failed"))

;; ============================================================
;; repo-full-path helper
;; ============================================================

(test-case "repo-full-path builds correct path"
  (define p (repo-full-path test-repo "src/foo.rkt"))
  (check-true (path? p))
  (check-not-false (string-contains? (path->string p) "myrepo"))
  (check-not-false (string-contains? (path->string p) "src/foo.rkt")))

(test-case "repo-full-path with nested relative path"
  (define p (repo-full-path test-repo "lib/sub/bar.rkt"))
  (check-not-false (string-contains? (path->string p) "lib/sub/bar.rkt")))

;; ============================================================
;; priority-for-file helper
;; ============================================================

(test-case "priority-for-file returns matching priority"
  (check-equal? (priority-for-file test-repo "src/core/engine.rkt") 1)
  (check-equal? (priority-for-file test-repo "src/utils/helpers.rkt") 5))

(test-case "priority-for-file returns 999 for unmatched path"
  (check-equal? (priority-for-file test-repo "docs/readme.md") 999))

(test-case "priority-for-file returns first matching directory"
  ;; "src/core" matches before "src/utils" because it comes first in the list
  (check-equal? (priority-for-file test-repo "src/core/utils/shared.rkt") 1))

(test-case "priority-for-file with empty priority-dirs"
  (define empty-repo
    (repo-config "e" "/tmp/e" "main" '() '() '() 'sibling #f '() '() '() '()
                 "log.tsv" 10 3 500))
  (check-equal? (priority-for-file empty-repo "anything.rkt") 999))

;; ============================================================
;; struct transparency (can be printed/compared)
;; ============================================================

(test-case "transparent structs support equal?"
  (define t1 (task "a.rkt" "desc" 1 #f))
  (define t2 (task "a.rkt" "desc" 1 #f))
  (check-equal? t1 t2)
  (define r1 (iteration-result 'keep "abc"))
  (define r2 (iteration-result 'keep "abc"))
  (check-equal? r1 r2))

(printf "All config tests passed.\n")

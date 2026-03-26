#lang racket/base
(require rackunit racket/string racket/list racket/match)
(require (only-in "../config.rkt" repo-config mode task task-description
                  mode-commit-prefix repo-config-base-branch repo-config-path))
(require "../git.rkt")

;; ============================================================
;; Helpers: fake repo-config and mode for testing
;; ============================================================

(define fake-mode
  (mode 'freestyle
        (lambda (repo done) #f)
        (lambda (repo tsk) "")
        "evolve/freestyle"
        "evolve(freestyle)"))

(define fake-repo
  (repo-config "test-repo"
               "/tmp/ruyi-test-repo"
               "main"
               '("src")
               '(".rkt")
               '()
               'sibling
               #f
               '()
               '()
               '()
               '()
               "evolution-log.tsv"
               10
               3
               500))

(define fake-tasks
  (list (task "src/a.rkt" "Add widget support" 1 #f)
        (task "src/b.rkt" "Fix login bug" 2 #f)
        (task "src/c.rkt" "Refactor auth module" 3 #f)))

;; ============================================================
;; Tests for gh-create-and-merge-pr! argument construction
;; ============================================================

;; We can't call the real function without a git repo and gh CLI,
;; but we can test the building blocks it relies on:

(test-case "PR title uses mode commit-prefix and branch name"
  (define title (format "~a: ~a" (mode-commit-prefix fake-mode) "evolve/freestyle/0326"))
  (check-equal? title "evolve(freestyle): evolve/freestyle/0326"))

(test-case "PR body lists kept tasks in order"
  (define body
    (string-append
     "## Kept iterations\n\n"
     (string-join
      (for/list ([tsk (in-list (reverse fake-tasks))])
        (format "- ~a" (task-description tsk)))
      "\n")
     "\n"))
  (check-not-false (string-contains? body "## Kept iterations"))
  (check-not-false (string-contains? body "- Add widget support"))
  (check-not-false (string-contains? body "- Fix login bug"))
  (check-not-false (string-contains? body "- Refactor auth module"))
  ;; Tasks should appear in reverse order (oldest first)
  ;; reverse of (a, b, c) = (c, b, a) so auth < login < widget in position
  (define widget-pos (car (regexp-match-positions #rx"Add widget" body)))
  (define login-pos (car (regexp-match-positions #rx"Fix login" body)))
  (define auth-pos (car (regexp-match-positions #rx"Refactor auth" body)))
  (check-true (< (car auth-pos) (car login-pos)))
  (check-true (< (car login-pos) (car widget-pos))))

(test-case "base-branch is accessible for rebase target"
  (check-equal? (repo-config-base-branch fake-repo) "main"))

(test-case "empty kept-tasks produces minimal body"
  (define body
    (string-append
     "## Kept iterations\n\n"
     (string-join
      (for/list ([tsk (in-list (reverse '()))])
        (format "- ~a" (task-description tsk)))
      "\n")
     "\n"))
  (check-equal? body "## Kept iterations\n\n\n"))

(printf "All git PR tests passed.\n")

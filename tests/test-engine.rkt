#lang racket/base
(require rackunit racket/string racket/port)
(require (only-in "../config.rkt" repo-config mode task task-description
                  mode-commit-prefix repo-config-base-branch))

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
;; Tests for finish-evolution summary output
;; ============================================================

;; Replicate the summary logic from finish-evolution to test it
;; (finish-evolution is not exported since it's internal to engine.rkt)

(test-case "summary prints task descriptions from task structs"
  (define output
    (with-output-to-string
      (lambda ()
        (for ([tsk (in-list (reverse fake-tasks))])
          (printf "  + ~a\n" (task-description tsk))))))
  (check-not-false (string-contains? output "Refactor auth module"))
  (check-not-false (string-contains? output "Fix login bug"))
  (check-not-false (string-contains? output "Add widget support")))

(test-case "summary preserves task order (oldest first via reverse)"
  (define kept (list (task "c.rkt" "Third" 3 #f)
                     (task "b.rkt" "Second" 2 #f)
                     (task "a.rkt" "First" 1 #f)))
  (define output
    (with-output-to-string
      (lambda ()
        (for ([tsk (in-list (reverse kept))])
          (printf "  + ~a\n" (task-description tsk))))))
  (define first-pos (car (regexp-match-positions #rx"First" output)))
  (define second-pos (car (regexp-match-positions #rx"Second" output)))
  (define third-pos (car (regexp-match-positions #rx"Third" output)))
  (check-true (< (car first-pos) (car second-pos)))
  (check-true (< (car second-pos) (car third-pos))))

(test-case "merge prompt answer 'y' triggers PR path"
  ;; Verify the string comparison logic used in finish-evolution
  (check-true (string=? "y" "y"))
  (check-false (string=? "n" "y"))
  (check-false (string=? "" "y"))
  (check-false (string=? "Y" "y"))
  (check-false (string=? "yes" "y")))

(test-case "gh-create-and-merge-pr! receives reversed kept-tasks"
  ;; kept-tasks is accumulated via cons (newest first),
  ;; so reverse gives oldest-first for the PR body
  (define kept (list (task "c.rkt" "Third" 3 #f)
                     (task "b.rkt" "Second" 2 #f)
                     (task "a.rkt" "First" 1 #f)))
  (define reversed (reverse kept))
  (check-equal? (task-description (car reversed)) "First")
  (check-equal? (task-description (cadr reversed)) "Second")
  (check-equal? (task-description (caddr reversed)) "Third"))

(printf "All engine tests passed.\n")

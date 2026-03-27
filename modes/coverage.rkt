#lang racket/base
(require racket/list racket/string racket/format racket/file racket/path)
(require "../config.rkt" "../tasks.rkt")
(provide coverage-mode)

;; ============================================================
;; Coverage mode: write tests for untested source files
;; ============================================================

(define (coverage-select-task repo done-tasks)
  "Find the next untested source file."
  (define done-files (map task-source-file done-tasks))
  (define all-sources (find-source-files repo))

  ;; Filter: no test file, not already done, not .d.ts
  (define candidates
    (filter (lambda (f)
              (and (not (test-file-exists? repo f))
                   (not (member f done-files))
                   (not (string-contains? f ".test."))
                   (not (string-suffix? f ".d.ts"))))
            all-sources))

  ;; Sort by priority
  (define sorted
    (sort candidates <
          #:key (lambda (f) (priority-for-file repo f))))

  (if (empty? sorted)
      #f
      (let ([file (first sorted)])
        (task file
              (format "Write tests for ~a" (path->relative file repo))
              (priority-for-file repo file)
              #f))))

(define (coverage-build-prompt repo tsk)
  "Build a focused prompt for Claude to write a test file."
  (define source-file (task-source-file tsk))
  (define test-path (derive-test-path repo source-file))
  (define rel-source (path->relative source-file repo))
  (define rel-test (path->relative (path->string test-path) repo))

  ;; Read context files
  (define context
    (for/fold ([ctx ""])
              ([cf (in-list (repo-config-context-files repo))])
      (define full-path (build-path (repo-config-path repo) cf))
      (if (file-exists? full-path)
          (string-append ctx "\n\n## " cf "\n\n" (file->string full-path))
          ctx)))

  ;; Find nearby test files for reference
  (define nearby (find-nearby-test-files repo source-file 3))
  (define nearby-str
    (if (empty? nearby)
        "No nearby test files found. Follow the project conventions."
        (string-join
         (map (lambda (f) (format "  - ~a" (path->relative f repo)))
              nearby)
         "\n")))

  (string-append
   "You are writing a test file. This is your ONLY task.\n\n"
   "Source file to test:\n  " rel-source "\n\n"
   "Write the test file at:\n  " rel-test "\n\n"
   "Reference these existing test files for patterns:\n" nearby-str "\n\n"
   "Rules:\n"
   "- ONLY create the test file. Do NOT modify any source files.\n"
   "- Cover: normal path, edge cases, error handling.\n"
   "- Use the same testing library and assertions as the reference tests.\n"
   "- Read the source file first to understand what it does.\n"
   "- Keep your total diff under ~"
   (number->string (if (task-extra tsk) (hash-ref (task-extra tsk) 'max-diff 500) 500))
   " lines.\n"
   "- Do NOT run git add, git commit, or any git commands. Just write files — the harness handles git.\n\n"
   "Project context:" context))

(define coverage-mode
  (mode 'coverage
        coverage-select-task
        coverage-build-prompt
        "evolve/coverage"
        "evolve(coverage)"))

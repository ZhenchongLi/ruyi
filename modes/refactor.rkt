#lang racket/base
(require racket/list racket/string racket/format)
(require "../config.rkt" "../tasks.rkt")
(provide refactor-mode)

;; ============================================================
;; Refactor mode: simplify complex code
;; ============================================================

(define COMPLEXITY-THRESHOLD 200)

(define (refactor-select-task repo done-tasks)
  "Find files with high complexity (long files as proxy)."
  (define done-files (map task-source-file done-tasks))
  (define all-sources (find-source-files repo))

  (define candidates
    (filter (lambda (f)
              (and (> (count-lines f) COMPLEXITY-THRESHOLD)
                   (not (member f done-files))
                   (not (string-contains? f ".test."))))
            all-sources))

  (define sorted (sort candidates > #:key count-lines))

  (if (empty? sorted)
      #f
      (let* ([file (first sorted)]
             [lines (count-lines file)])
        (task file
              (format "Refactor ~a (~a lines)" (path->relative file repo) lines)
              (- lines)
              #f))))

(define (refactor-build-prompt repo tsk)
  "Build prompt for Claude to refactor a file."
  (define source-file (task-source-file tsk))
  (define rel (path->relative source-file repo))

  (string-append
   "Refactor this file to improve code quality without changing behavior.\n\n"
   "File: " rel "\n\n"
   "Look for:\n"
   "- Long methods that can be split\n"
   "- Duplicated code that can be extracted\n"
   "- Complex nested logic that can be flattened\n"
   "- Unused code that can be removed\n\n"
   "Rules:\n"
   "- Do NOT change any external behavior.\n"
   "- Do NOT modify test files or config files.\n"
   "- Keep changes focused — one refactoring per iteration.\n"
   "- If there's nothing meaningful to refactor, create no changes.\n"
   "- Keep your total diff under ~"
   (number->string (if (task-extra tsk) (hash-ref (task-extra tsk) 'max-diff 500) 500))
   " lines.\n"
   "- Do NOT run git add, git commit, or any git commands. Just write files — the harness handles git.\n"))

(define refactor-mode
  (mode 'refactor
        refactor-select-task
        refactor-build-prompt
        "evolve/refactor"
        "evolve(refactor)"))

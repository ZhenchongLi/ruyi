#lang racket/base
(require racket/list racket/string racket/format)
(require "../config.rkt" "../tasks.rkt")
(provide filesize-mode)

;; ============================================================
;; Filesize mode: split oversized files
;; ============================================================

(define FILE-SIZE-LIMIT 400)

(define (filesize-select-task repo done-tasks)
  "Find the largest oversized source file."
  (define done-files (map task-source-file done-tasks))
  (define all-sources (find-source-files repo))

  (define candidates
    (filter (lambda (f)
              (and (> (count-lines f) FILE-SIZE-LIMIT)
                   (not (member f done-files))
                   (not (string-contains? f ".test."))))
            all-sources))

  ;; Sort by line count descending (negate for sort <)
  (define sorted
    (sort candidates > #:key count-lines))

  (if (empty? sorted)
      #f
      (let* ([file (first sorted)]
             [lines (count-lines file)])
        (task file
              (format "Split ~a (~a lines)" (path->relative file repo) lines)
              (- lines) ; negative so largest first
              #f))))

(define (filesize-build-prompt repo tsk)
  "Build prompt for Claude to split an oversized file."
  (define source-file (task-source-file tsk))
  (define rel (path->relative source-file repo))

  (string-append
   "You need to split an oversized file into smaller, focused files.\n\n"
   "File to split:\n  " rel "\n\n"
   "Rules:\n"
   "- Read the file and identify natural domain boundaries.\n"
   "- Extract logically independent pieces into new files in the same directory.\n"
   "- Update all imports that reference the original file.\n"
   "- Each resulting file should be under 400 lines.\n"
   "- Do NOT change any behavior — this is a pure refactor.\n"
   "- Do NOT modify test files, config files, or package.json.\n"))

(define filesize-mode
  (mode 'filesize
        filesize-select-task
        filesize-build-prompt
        "evolve/filesize"
        "evolve(filesize)"))

#lang racket/base
(require racket/list racket/string racket/format racket/port racket/system)
(require json)
(require "../config.rkt" "../tasks.rkt" "../git.rkt")
(provide issue-mode)

;; ============================================================
;; Issue mode: implement GitHub issues
;; ============================================================

(define (issue-select-task repo done-tasks)
  "Fetch open issues from GitHub and pick the next one."
  (define done-numbers
    (filter-map (lambda (t)
                  (and (task-extra t)
                       (hash-ref (task-extra t) 'number #f)))
                done-tasks))

  (define json-str
    (with-handlers ([exn:fail? (lambda (_) "[]")])
      (shell! repo "gh" "issue" "list"
              "--limit" "10"
              "--state" "open"
              "--json" "number,title,body,labels")))

  (define issues
    (with-handlers ([exn:fail? (lambda (_) '())])
      (string->jsexpr json-str)))

  (define candidates
    (filter (lambda (issue)
              (not (member (hash-ref issue 'number) done-numbers)))
            (if (list? issues) issues '())))

  (if (empty? candidates)
      #f
      (let ([issue (first candidates)])
        (task ""
              (format "Fix #~a: ~a"
                      (hash-ref issue 'number)
                      (hash-ref issue 'title))
              (hash-ref issue 'number)
              (make-immutable-hash
               (list (cons 'number (hash-ref issue 'number))
                     (cons 'title (hash-ref issue 'title))
                     (cons 'body (hash-ref issue 'body ""))))))))

(define (issue-build-prompt repo tsk)
  "Build prompt for Claude to implement a GitHub issue."
  (define extra (task-extra tsk))
  (define number (hash-ref extra 'number))
  (define title (hash-ref extra 'title))
  (define body (hash-ref extra 'body ""))
  (define forbidden
    (string-join (repo-config-forbidden-files repo) ", "))

  (string-append
   "Fix this GitHub issue.\n\n"
   "Issue #" (number->string number) ": " title "\n\n"
   "Description:\n" body "\n\n"
   "Rules:\n"
   "- Keep changes focused and minimal.\n"
   "- Write or update tests for changed code.\n"
   "- Do NOT modify: " forbidden "\n"
   "- Read the relevant source files before making changes.\n"
   "- Do NOT run git add, git commit, or any git commands. Just write files — the harness handles git.\n"))

(define issue-mode
  (mode 'issue
        issue-select-task
        issue-build-prompt
        "evolve/issue"
        "evolve(issue)"))

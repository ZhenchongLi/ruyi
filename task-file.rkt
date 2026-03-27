#lang racket/base
(require racket/file racket/string racket/format racket/port racket/list racket/date racket/path)
(provide (all-defined-out))

;; ============================================================
;; .ruyi-task: the contract between Agent A and Agent B
;;
;; goal      — what Agent A should implement
;; judgement — how Agent B should verify and score
;; ============================================================

(struct ruyi-task
  (goal           ; string: what to do
   judgement      ; string: how to verify it's done well
   max-revisions  ; integer: review-revise rounds
   min-score)     ; integer: reviewer threshold
  #:transparent)

(define DEFAULT-TASK (ruyi-task "" "" 3 8))

;; ============================================================
;; Read .ruyi-task (S-expression format)
;; ============================================================

(define (read-ruyi-task path)
  "Read a .ruyi-task file. Returns a ruyi-task struct."
  (define content (file->string path))
  (define expr (with-input-from-string content read))
  (parse-ruyi-task-expr expr))

(define (parse-ruyi-task-expr expr)
  "Parse (ruyi-task (field value) ...) into struct."
  (unless (and (pair? expr) (eq? (car expr) 'ruyi-task))
    (error 'parse-ruyi-task "Expected (ruyi-task ...), got: ~a" expr))
  (define fields (cdr expr))
  (define MISSING (gensym 'missing))
  (define (get key)
    (define pair (assq key fields))
    (if pair (cadr pair) MISSING))

  (ruyi-task
   (let ([v (get 'goal)]) (if (eq? v MISSING) "" v))
   (let ([v (get 'judgement)]) (if (eq? v MISSING) "" v))
   (let ([v (get 'max-revisions)]) (if (eq? v MISSING) 3 v))
   (let ([v (get 'min-score)]) (if (eq? v MISSING) 8 v))))

;; ============================================================
;; Write .ruyi-task
;; ============================================================

(define (write-ruyi-task path task)
  "Write a ruyi-task struct to file as S-expression."
  (call-with-output-file path
    (lambda (out)
      (fprintf out ";; .ruyi-task — the contract between Agent A and Agent B\n")
      (fprintf out ";; goal: what to do | judgement: how to verify\n\n")
      (fprintf out "(ruyi-task\n")
      (fprintf out "  (goal ~s)\n" (ruyi-task-goal task))
      (fprintf out "  (judgement ~s)\n" (ruyi-task-judgement task))
      (fprintf out "  (max-revisions ~a)\n" (ruyi-task-max-revisions task))
      (fprintf out "  (min-score ~a))\n" (ruyi-task-min-score task)))
    #:exists 'replace))

;; ============================================================
;; Display .ruyi-task summary
;; ============================================================

(define (print-ruyi-task task)
  "Print a human-readable summary of the task."
  (printf "\nGoal: ~a\n" (ruyi-task-goal task))
  (printf "Judgement: ~a\n" (ruyi-task-judgement task))
  (printf "Revisions: ~a | Min score: ~a\n"
          (ruyi-task-max-revisions task)
          (ruyi-task-min-score task))
  (printf "\n"))

;; ============================================================
;; Task folder management
;;
;; .ruyi-tasks/
;;   2026-03-27-improve-docs/
;;     task.rkt          ← task definition
;;     log.tsv           ← execution log
;;     journal.md        ← detailed history
;; ============================================================

(define TASKS-DIR ".ruyi-tasks")
(define TASK-FILENAME "task.rkt")

(define (tasks-dir dir)
  (build-path dir TASKS-DIR))

(define (slugify s)
  "Turn a goal string into a short filesystem-safe slug."
  (define clean
    (regexp-replace* #rx"[^a-zA-Z0-9\u4e00-\u9fff]+" (string-downcase s) "-"))
  (define trimmed
    (if (> (string-length clean) 40)
        (substring clean 0 40)
        clean))
  (string-trim trimmed "-"))

(define (create-task-dir dir goal)
  "Create a new task folder under .ruyi-tasks/. Returns the folder path."
  (define date-str
    (parameterize ([date-display-format 'iso-8601])
      (define d (current-date))
      (format "~a-~a-~a"
              (date-year d)
              (~r (date-month d) #:min-width 2 #:pad-string "0")
              (~r (date-day d) #:min-width 2 #:pad-string "0"))))
  (define slug (slugify goal))
  (define folder-name (format "~a-~a" date-str slug))
  (define folder-path (build-path (tasks-dir dir) folder-name))
  (make-directory* folder-path)
  folder-path)

(define (task-file-in-folder folder)
  (build-path folder TASK-FILENAME))

(define (list-task-dirs dir)
  "List all task folders, newest first."
  (define tdir (tasks-dir dir))
  (if (directory-exists? tdir)
      (sort
       (for/list ([d (directory-list tdir #:build? #t)]
                  #:when (directory-exists? d)
                  #:when (file-exists? (task-file-in-folder d)))
         d)
       string>?
       #:key path->string)
      '()))

(define (latest-task-dir dir)
  "Get the most recent task folder, or #f."
  (define dirs (list-task-dirs dir))
  (if (null? dirs) #f (car dirs)))

(define (print-task-list dir)
  "Print all task folders with their goals."
  (define dirs (list-task-dirs dir))
  (cond
    [(null? dirs)
     (printf "No tasks found.\n")]
    [else
     (printf "Tasks:\n")
     (for ([d (in-list dirs)] [i (in-naturals 1)])
       (define task (read-ruyi-task (task-file-in-folder d)))
       (define name (path->string (file-name-from-path d)))
       (printf "  ~a. ~a — ~a\n" i name (ruyi-task-goal task)))]))

;; ============================================================
;; Prompt for Claude Code to generate .ruyi-task
;; ============================================================

(define (task-generation-prompt goal task-folder-path ruyi-home)
  "Build prompt for Claude Code to generate task.rkt."
  (define format-file (build-path ruyi-home "RUYI-TASK-FORMAT.md"))
  (string-append
   "The user wants: " goal "\n\n"
   "Read the format spec at: " (path->string format-file) "\n"
   "Then read this project's codebase.\n"
   "Generate the task file at: " (path->string (task-file-in-folder task-folder-path)) "\n"))

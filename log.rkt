#lang racket/base
(require racket/string racket/format racket/date racket/path racket/file racket/list)
(require "config.rkt")
(provide (all-defined-out))

;; ============================================================
;; Logging: TSV summary + detailed Markdown journal
;; ============================================================

(define TSV-HEADER "timestamp\tmode\tcommit\tstatus\tdescription")

(define (current-timestamp)
  (define d (current-date))
  (format "~a-~a-~aT~a:~a:~a"
          (date-year d)
          (~r (date-month d) #:min-width 2 #:pad-string "0")
          (~r (date-day d) #:min-width 2 #:pad-string "0")
          (~r (date-hour d) #:min-width 2 #:pad-string "0")
          (~r (date-minute d) #:min-width 2 #:pad-string "0")
          (~r (date-second d) #:min-width 2 #:pad-string "0")))

(define (log-init! repo)
  "Create log files if they don't exist."
  (define log-file (build-path (repo-config-path repo) (repo-config-log-path repo)))
  (define log-dir (path-only log-file))
  (when log-dir (make-directory* log-dir))
  (unless (file-exists? log-file)
    (call-with-output-file log-file
      (lambda (out) (displayln TSV-HEADER out)))))

(define (log-iteration! repo mode-sym tsk result)
  "Append to TSV log."
  (define log-file (build-path (repo-config-path repo) (repo-config-log-path repo)))
  (define line
    (string-join
     (list (current-timestamp)
           (symbol->string mode-sym)
           (iteration-result-detail result)
           (symbol->string (iteration-result-status result))
           (task-description tsk))
     "\t"))
  (call-with-output-file log-file
    (lambda (out) (displayln line out))
    #:exists 'append))

;; ============================================================
;; Detailed journal: Markdown file with full iteration history
;; ============================================================

(define (journal-path repo)
  (build-path (repo-config-path repo) "evolution-journal.md"))

(define (journal-init! repo mode-sym)
  "Create or append a new session header to the journal."
  (define jp (journal-path repo))
  (call-with-output-file jp
    (lambda (out)
      (fprintf out "\n---\n\n# Evolution Session: ~a\n\n" (current-timestamp))
      (fprintf out "Mode: ~a\n\n" mode-sym))
    #:exists 'append))

(define (journal-iteration! repo round status description
                            #:score [score #f]
                            #:weaknesses [weaknesses '()]
                            #:feedback [feedback ""]
                            #:human-input [human-input ""])
  "Append detailed iteration entry to journal."
  (define jp (journal-path repo))
  (call-with-output-file jp
    (lambda (out)
      (fprintf out "## Round ~a — ~a\n\n" round status)
      (fprintf out "~a\n\n" description)
      (when score
        (fprintf out "**Score:** ~a/10\n\n" score))
      (unless (empty? weaknesses)
        (fprintf out "**Weaknesses:**\n")
        (for ([w (in-list weaknesses)])
          (fprintf out "- ~a\n" w))
        (fprintf out "\n"))
      (unless (string=? feedback "")
        (fprintf out "**Judge feedback:**\n~a\n\n" feedback))
      (unless (string=? human-input "")
        (fprintf out "**Human input:** ~a\n\n" human-input)))
    #:exists 'append))

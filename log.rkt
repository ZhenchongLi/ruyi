#lang racket/base
(require racket/string racket/format racket/date racket/path racket/file)
(require "config.rkt")
(provide (all-defined-out))

;; ============================================================
;; TSV logging
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
  "Create the log file with header if it doesn't exist."
  (define log-file (build-path (repo-config-path repo) (repo-config-log-path repo)))
  (define log-dir (path-only log-file))
  (when log-dir (make-directory* log-dir))
  (unless (file-exists? log-file)
    (call-with-output-file log-file
      (lambda (out) (displayln TSV-HEADER out)))))

(define (log-iteration! repo mode-sym tsk result)
  "Append one line to the evolution log."
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

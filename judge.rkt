#lang racket/base
(require racket/string racket/format racket/port racket/list)
(require "claude.rkt")
(provide judge-evaluate parse-score)

;; ============================================================
;; Judge: LLM-as-Judge for quality evaluation
;; ============================================================

(define (judge-evaluate repo-path rubric content
                        #:model [model "sonnet"]
                        #:timeout [timeout 60])
  "Ask Claude to evaluate content against a rubric. Returns (values score feedback)."
  (define prompt
    (string-append
     "You are a strict quality judge. Score the following content against the rubric.\n\n"
     "## Rubric\n\n" rubric "\n\n"
     "## Content to evaluate\n\n" content "\n\n"
     "## Instructions\n\n"
     "1. Score each dimension from 1-10\n"
     "2. Give a weighted total score (1-10)\n"
     "3. List the top 3 weaknesses, most critical first\n"
     "4. Be strict — a 7 is 'good', 9 is 'excellent', 10 is near-perfect\n\n"
     "Output format (EXACTLY this, no markdown fences):\n"
     "SCORE: <number>\n"
     "WEAKNESSES:\n"
     "- <weakness 1>\n"
     "- <weakness 2>\n"
     "- <weakness 3>\n"
     "FEEDBACK:\n"
     "<one paragraph of specific improvement suggestions>\n"))

  (printf "  Judging... ")
  (flush-output)
  (define-values (ok? output)
    (claude-execute repo-path prompt #:model model #:timeout timeout))

  (cond
    [ok?
     (define score (parse-score output))
     (define weaknesses (parse-weaknesses output))
     (define feedback (parse-feedback output))
     (printf "score: ~a/10\n" score)
     (values score weaknesses feedback)]
    [else
     (printf "failed\n")
     (values 0 '("Judge failed to respond") "")]))

;; ============================================================
;; Output parsing
;; ============================================================

(define (parse-score text)
  "Extract SCORE: <number> from judge output."
  (define lines (string-split text "\n"))
  (for/or ([line (in-list lines)])
    (define trimmed (string-trim line))
    (and (string-prefix? (string-upcase trimmed) "SCORE:")
         (let ([num-str (string-trim (substring trimmed 6))])
           (string->number (car (string-split num-str " ")))))))

(define (parse-weaknesses text)
  "Extract weakness list from judge output."
  (define lines (string-split text "\n"))
  (define in-weaknesses? #f)
  (define result '())
  (for ([line (in-list lines)])
    (define trimmed (string-trim line))
    (cond
      [(string-prefix? (string-upcase trimmed) "WEAKNESSES:")
       (set! in-weaknesses? #t)]
      [(string-prefix? (string-upcase trimmed) "FEEDBACK:")
       (set! in-weaknesses? #f)]
      [(and in-weaknesses? (string-prefix? trimmed "-"))
       (set! result (cons (string-trim (substring trimmed 1)) result))]))
  (reverse result))

(define (parse-feedback text)
  "Extract feedback paragraph from judge output."
  (define lines (string-split text "\n"))
  (define in-feedback? #f)
  (define result '())
  (for ([line (in-list lines)])
    (define trimmed (string-trim line))
    (cond
      [(string-prefix? (string-upcase trimmed) "FEEDBACK:")
       (set! in-feedback? #t)]
      [in-feedback?
       (set! result (cons trimmed result))]))
  (string-join (reverse result) "\n"))

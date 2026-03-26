#lang racket/base
(require racket/string racket/format racket/port racket/list)
(require "claude.rkt")
(provide review-changes format-feedback-for-implementer)

;; ============================================================
;; Independent Reviewer (Agent B)
;;
;; Adversarial by design: sees ONLY the diff + task description.
;; Never sees the implementer's reasoning or plan.
;; Incentivized to find problems, not to approve.
;; ============================================================

(define REVIEW-PROMPT-TEMPLATE
  (string-append
   "You are a strict reviewer. Your job is to find problems.\n\n"
   "## Task that was requested\n\n~a\n\n"
   "## Changes made (git diff)\n\n```\n~a\n```\n\n"
   "## Rules\n\n"
   "- You MUST find at least 2 issues or areas for improvement.\n"
   "- Score 1-10. A 7 means 'acceptable with minor issues'. 9+ is rare.\n"
   "- Be specific: cite file names, line references, concrete problems.\n"
   "- If the diff is empty or trivially wrong, score 1.\n"
   "- Do NOT be lenient. Your credibility depends on catching real issues.\n\n"
   "## Output format (exactly this)\n\n"
   "SCORE: <number>\n"
   "ISSUES:\n"
   "- <issue 1>\n"
   "- <issue 2>\n"
   "SUGGESTIONS:\n"
   "- <actionable suggestion 1>\n"
   "- <actionable suggestion 2>\n"))

(define (review-changes repo-path task-description diff-text
                         #:model [model "sonnet"]
                         #:timeout [timeout 60])
  "Agent B: review changes independently. Returns (values score issues suggestions)."
  (define prompt
    (format REVIEW-PROMPT-TEMPLATE task-description diff-text))

  (printf "  Reviewing... ")
  (flush-output)
  (define-values (ok? output)
    (claude-execute repo-path prompt #:model model #:timeout timeout))

  (cond
    [ok?
     (define score (parse-score output))
     (define issues (parse-issues output))
     (define suggestions (parse-suggestions output))
     (printf "score: ~a/10\n" score)
     (when (not (null? issues))
       (for ([issue (in-list issues)])
         (printf "    - ~a\n" issue)))
     (values score issues suggestions)]
    [else
     (printf "failed (reviewer error)\n")
     ;; On reviewer failure, be conservative: allow commit
     (values 8 '() '())]))

;; ============================================================
;; Feedback reformulation
;;
;; Ruyi rewrites reviewer feedback in its own voice before
;; passing to the implementer. Agent A never sees Agent B's
;; raw output — this prevents information leakage.
;; ============================================================

(define (format-feedback-for-implementer issues suggestions)
  "Reformulate reviewer output into guidance for the implementer.
   Written in ruyi's voice, not the reviewer's."
  (string-append
   (if (null? issues)
       ""
       (string-append
        "The following issues were found in your changes:\n"
        (string-join (map (lambda (i) (string-append "- " i)) issues) "\n")
        "\n\n"))
   (if (null? suggestions)
       ""
       (string-append
        "Please address these in your next attempt:\n"
        (string-join (map (lambda (s) (string-append "- " s)) suggestions) "\n")
        "\n"))))

;; ============================================================
;; Parsers (adapted from judge.rkt)
;; ============================================================

(define (parse-score text)
  "Extract SCORE: <number> from output."
  (define m (regexp-match #rx"(?i:SCORE:\\s*([0-9]+\\.?[0-9]*))" text))
  (if m
      (or (string->number (second m)) 5)
      5))  ; default middle score on parse failure

(define (parse-issues text)
  "Extract ISSUES list from output."
  (parse-section text "ISSUES" "SUGGESTIONS"))

(define (parse-suggestions text)
  "Extract SUGGESTIONS list from output."
  (parse-section text "SUGGESTIONS" #f))

(define (parse-section text start-marker end-marker)
  "Extract bullet list between two markers."
  (define lines (string-split text "\n"))
  (define in-section? #f)
  (define result '())
  (for ([line (in-list lines)])
    (define trimmed (string-trim line))
    (cond
      [(string-prefix? (string-upcase trimmed) (string-upcase (string-append start-marker ":")))
       (set! in-section? #t)]
      [(and end-marker
            (string-prefix? (string-upcase trimmed) (string-upcase (string-append end-marker ":"))))
       (set! in-section? #f)]
      [(and in-section? (string-prefix? trimmed "-"))
       (set! result (cons (string-trim (substring trimmed 1)) result))]))
  (reverse result))

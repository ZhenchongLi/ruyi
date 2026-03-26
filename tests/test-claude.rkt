#lang racket/base
(require rackunit racket/string)
(require (only-in "../claude.rkt" plan-says-skip?))

;; ============================================================
;; Tests for plan-says-skip? (agent decides to skip planning)
;; ============================================================

(test-case "SKIP_PLAN is detected"
  (check-true (plan-says-skip? "SKIP_PLAN"))
  (check-true (plan-says-skip? "SKIP_PLAN\n"))
  (check-true (plan-says-skip? "  SKIP_PLAN  ")))

(test-case "SKIP_PLAN is case-insensitive"
  (check-true (plan-says-skip? "skip_plan"))
  (check-true (plan-says-skip? "Skip_Plan")))

(test-case "normal plan output is not skipped"
  (check-false (plan-says-skip? "Plan:\n- Modify src/foo.rkt\n- Add tests"))
  (check-false (plan-says-skip? "Here is the plan:\n1. Edit file\n2. Test"))
  (check-false (plan-says-skip? "")))

(test-case "SKIP_PLAN embedded in other text is detected"
  (check-true (plan-says-skip? "This is simple. SKIP_PLAN")))

(printf "All claude tests passed.\n")

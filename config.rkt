#lang racket/base
(require racket/contract racket/string racket/list)
(provide (all-defined-out))

;; ============================================================
;; repo-config: all configuration for a target repository
;; ============================================================

(struct repo-config
  (name              ; string: "cove" | "docmod"
   path              ; string: absolute path to repo
   base-branch       ; string: "main"
   source-dirs       ; (listof string): directories to scan
   source-exts       ; (listof string): file extensions
   excluded-dirs     ; (listof string): directories to skip
   test-pattern      ; symbol: 'sibling | 'mirror
   test-alt-dir      ; string or #f: "__tests__" or test dir for mirror
   forbidden-files   ; (listof string): files that must not be modified
   validate-commands ; (listof (listof string)): shell commands for validation
   priority-dirs     ; (listof (cons string integer)): directory -> priority
   context-files     ; (listof string): files to inject into Claude prompt
   log-path          ; string: path to evolution-log.tsv
   max-iterations    ; integer
   max-consecutive-fails ; integer
   max-diff-lines)   ; integer
  #:transparent)

;; ============================================================
;; mode: defines an evolution mode
;; ============================================================

(struct mode
  (name            ; symbol: 'coverage | 'filesize | 'issue | 'refactor
   select-task     ; (repo-config (listof task) -> task or #f)
   build-prompt    ; (repo-config task -> string)
   branch-prefix   ; string: "evolve/coverage"
   commit-prefix)  ; string: "evolve(coverage)"
  #:transparent)

;; ============================================================
;; task: a single unit of work
;; ============================================================

(struct task
  (source-file   ; string: path relative to repo
   description   ; string: human-readable
   priority      ; integer: lower = higher priority
   extra)        ; hash or #f: additional data (issue number, etc.)
  #:transparent)

;; ============================================================
;; result: outcome of one iteration
;; ============================================================

(struct iteration-result
  (status   ; symbol: 'keep | 'discard
   detail   ; string: commit hash or failure reason
   )
  #:transparent)

;; ============================================================
;; helpers
;; ============================================================

(define (repo-full-path repo rel-path)
  (build-path (repo-config-path repo) rel-path))

(define (priority-for-file repo file-path)
  (define dirs (repo-config-priority-dirs repo))
  (or (for/or ([pair (in-list dirs)])
        (and (string-contains? file-path (car pair))
             (cdr pair)))
      999))

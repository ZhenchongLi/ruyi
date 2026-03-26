#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list)
  (require "config.rkt" "engine.rkt" "init.rkt"
           "modes/coverage.rkt" "modes/filesize.rkt"
           "modes/issue.rkt" "modes/refactor.rkt")

  ;; ============================================================
  ;; Ruyi — as you wish
  ;; ============================================================

  (define all-modes
    (make-immutable-hash
     (list (cons "coverage" coverage-mode)
           (cons "filesize" filesize-mode)
           (cons "issue" issue-mode)
           (cons "refactor" refactor-mode))))

  ;; ---- Function definitions (before dispatch) ----

  (define (print-usage)
    (displayln "
Ruyi — deterministic evolution engine

Usage:
  racket evolve.rkt init [path]     Set up ruyi for a project
  racket evolve.rkt                 Run evolution (reads .ruyi.rkt)
  racket evolve.rkt <mode>          Run with specific mode
  racket evolve.rkt <repo> <mode>   Legacy: use configs/<repo>.rkt

Modes:  coverage, filesize, issue, refactor

Quick start:
  cd your-project
  racket ~/ruyi/evolve.rkt init     # detect project, set your goal
  racket ~/ruyi/evolve.rkt          # start evolving"))

  (define (run-from-local-config dir [mode-override #f])
    (define config-file (build-path dir ".ruyi.rkt"))
    (unless (file-exists? config-file)
      (printf "No .ruyi.rkt found in ~a\n\n" (path->string dir))
      (printf "Run 'ruyi init' first:\n")
      (printf "  cd ~a\n" (path->string dir))
      (displayln "  racket ~/ruyi/evolve.rkt init")
      (exit 1))
    (define config-module `(file ,(path->string config-file)))
    (define local-config (dynamic-require config-module 'local-config))
    (define config-mode-name (dynamic-require config-module 'local-mode-name))
    (define mode-name (or mode-override config-mode-name))
    (unless (hash-has-key? all-modes mode-name)
      (eprintf "Unknown mode: ~a\nAvailable: ~a\n"
               mode-name (string-join (hash-keys all-modes) ", "))
      (exit 1))
    (evolution-loop local-config (hash-ref all-modes mode-name)))

  (define (run-legacy repo-name mode-name)
    (define config-file
      (build-path (find-system-path 'orig-dir)
                  "configs" (string-append repo-name ".rkt")))
    (unless (file-exists? config-file)
      (eprintf "No config found: configs/~a.rkt\n" repo-name)
      (exit 1))
    (unless (hash-has-key? all-modes mode-name)
      (eprintf "Unknown mode: ~a\n" mode-name)
      (exit 1))
    (define config-sym (string->symbol (string-append repo-name "-config")))
    (define config-module `(file ,(path->string config-file)))
    (define repo-config (dynamic-require config-module config-sym))
    (evolution-loop repo-config (hash-ref all-modes mode-name)))

  ;; ---- Dispatch ----

  (define args (vector->list (current-command-line-arguments)))

  (cond
    ;; No args: run from .ruyi.rkt
    [(empty? args)
     (run-from-local-config (current-directory))]

    ;; "init" command
    [(string=? (first args) "init")
     (ruyi-init! (if (> (length args) 1)
                     (path->complete-path (string->path (second args)))
                     (current-directory)))]

    ;; Help
    [(or (string=? (first args) "--help") (string=? (first args) "-h"))
     (print-usage)]

    ;; Single arg: mode name
    [(and (= (length args) 1) (hash-has-key? all-modes (first args)))
     (run-from-local-config (current-directory) (first args))]

    ;; Two args: legacy <repo> <mode>
    [(= (length args) 2)
     (run-legacy (first args) (second args))]

    ;; Unknown
    [else
     (eprintf "Unknown command: ~a\n" (string-join args " "))
     (print-usage)
     (exit 1)]))

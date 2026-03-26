#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list)
  (require "config.rkt" "engine.rkt" "init.rkt"
           "modes/coverage.rkt" "modes/filesize.rkt"
           "modes/issue.rkt" "modes/refactor.rkt"
           "modes/evolve-doc.rkt" "modes/freestyle.rkt")

  ;; ============================================================
  ;; Ruyi — as you wish
  ;; ============================================================

  (define all-modes
    (make-immutable-hash
     (list (cons "coverage" coverage-mode)
           (cons "filesize" filesize-mode)
           (cons "issue" issue-mode)
           (cons "refactor" refactor-mode)
           (cons "evolve-doc" evolve-doc-mode))))

  ;; ---- Function definitions ----

  (define (print-usage)
    (displayln "
Ruyi — as you wish

Usage:
  racket evolve.rkt init [path]           Set up ruyi for a project
  racket evolve.rkt                       Run evolution (reads .ruyi.rkt)
  racket evolve.rkt <mode>                Run with specific mode
  racket evolve.rkt <repo> <mode>         Legacy: use configs/<repo>.rkt
  racket evolve.rkt <repo> do <goal>      Freestyle: tell ruyi what you want

Modes:  coverage, filesize, issue, refactor, evolve-doc

Examples:
  racket evolve.rkt cove coverage
  racket evolve.rkt cove do \"add CLI support\"
  racket evolve.rkt docmod do \"translate README to English\""))

  (define (run-from-local-config dir [mode-override #f])
    (define config-file (build-path dir ".ruyi.rkt"))
    (unless (file-exists? config-file)
      (printf "No .ruyi.rkt found in ~a\n\n" (path->string dir))
      (displayln "Run 'ruyi init' first:")
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

  (define (run-freestyle repo-name goal)
    (define config-file
      (build-path (find-system-path 'orig-dir)
                  "configs" (string-append repo-name ".rkt")))
    (unless (file-exists? config-file)
      (eprintf "No config found: configs/~a.rkt\n" repo-name)
      (exit 1))
    (define config-sym (string->symbol (string-append repo-name "-config")))
    (define config-module `(file ,(path->string config-file)))
    (define repo-config (dynamic-require config-module config-sym))
    (define fm (make-freestyle-mode goal
                 #:repo-path (repo-config-path repo-config)))
    (evolution-loop repo-config fm))

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

    ;; Freestyle: <repo> do <goal...>
    [(and (>= (length args) 3) (string=? (second args) "do"))
     (define repo-name (first args))
     (define goal (string-join (cddr args) " "))
     (run-freestyle repo-name goal)]

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

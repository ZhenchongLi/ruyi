#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list
           racket/runtime-path)
  (require "config.rkt" "engine.rkt" "init.rkt" "git.rkt" "claude.rkt"
           "modes/coverage.rkt" "modes/filesize.rkt"
           "modes/issue.rkt" "modes/refactor.rkt"
           "modes/evolve-doc.rkt" "modes/freestyle.rkt")

  (define-runtime-path ruyi-dir ".")

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

Usage (run from your project directory):
  ruyi do <goal>                          Do something (auto-inits if needed)
  ruyi pdo <g1> // <g2> // ...            Do multiple things in parallel
  ruyi init [path]                        Manually init (usually not needed)
  ruyi wrun <mode>                        Run a predefined mode in worktree
  ruyi update                             Update ruyi to latest version
  ruyi version                            Show version

Examples:
  cd ~/my-project
  ruyi do \"add CLI support\"
  ruyi do \"fix auth bug\"                  # another terminal, parallel!
  ruyi pdo \"add tests\" // \"translate README\""))

  (define (load-local-config dir)
    "Load repo-config from .ruyi.rkt in dir. Auto-inits if missing."
    (ruyi-ensure-init! dir)
    (define config-file (build-path dir ".ruyi.rkt"))
    (define config-module `(file ,(path->string config-file)))
    (dynamic-require config-module 'local-config))

  (define (run-from-local-config dir [mode-override #f])
    (define config-file (build-path dir ".ruyi.rkt"))
    (define local-config (load-local-config dir))
    (define config-module `(file ,(path->string config-file)))
    (define config-mode-name (dynamic-require config-module 'local-mode-name))
    (define mode-name (or mode-override config-mode-name))
    (unless (hash-has-key? all-modes mode-name)
      (eprintf "Unknown mode: ~a\nAvailable: ~a\n"
               mode-name (string-join (hash-keys all-modes) ", "))
      (exit 1))
    (evolution-loop local-config (hash-ref all-modes mode-name)))

  (define (suggest-next-mode dir kept)
    "After a freestyle do, suggest running a predefined mode."
    (when (> kept 0)
      (printf "\nContinue with a mode?\n")
      (printf "  coverage  — improve test coverage\n")
      (printf "  refactor  — simplify large files\n")
      (printf "  issue     — fix GitHub issues\n")
      (printf "  filesize  — break up big files\n")
      (define answer (read-line-interactive "\nMode (Enter to skip): "))
      (when (and (not (string=? answer ""))
                 (hash-has-key? all-modes answer))
        (run-local-wrun dir answer))))

  (define (run-local-do dir goal)
    "Run freestyle evolution in worktree, using .ruyi.rkt from cwd."
    (define repo (load-local-config dir))
    (define fm (make-freestyle-mode goal
                 #:repo-path (repo-config-path repo)
                 #:clarify? #f))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree repo fm))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url))
    (suggest-next-mode dir kept))

  (define (run-local-pdo dir goals)
    "Run multiple freestyle goals in parallel, using .ruyi.rkt from cwd."
    (define repo (load-local-config dir))
    (define modes
      (for/list ([goal (in-list goals)])
        (make-freestyle-mode goal
          #:repo-path (repo-config-path repo)
          #:clarify? #f)))
    (run-parallel-evolutions repo modes))

  (define (run-local-wrun dir mode-name)
    "Run a predefined mode in worktree, using .ruyi.rkt from cwd."
    (define repo (load-local-config dir))
    (unless (hash-has-key? all-modes mode-name)
      (eprintf "Unknown mode: ~a\n" mode-name)
      (exit 1))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree repo (hash-ref all-modes mode-name)))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url)))

  (define (run-legacy repo-name mode-name)
    (define config-file
      (build-path ruyi-dir
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
      (build-path ruyi-dir
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

  (define (load-repo-config repo-name)
    (define config-file
      (build-path ruyi-dir
                  "configs" (string-append repo-name ".rkt")))
    (unless (file-exists? config-file)
      (eprintf "No config found: configs/~a.rkt\n" repo-name)
      (exit 1))
    (define config-sym (string->symbol (string-append repo-name "-config")))
    (define config-module `(file ,(path->string config-file)))
    (dynamic-require config-module config-sym))

  (define (run-parallel-modes repo-name mode-names)
    "Run multiple predefined modes in parallel on the same repo."
    (define repo (load-repo-config repo-name))
    (define modes
      (for/list ([mn (in-list mode-names)])
        (unless (hash-has-key? all-modes mn)
          (eprintf "Unknown mode: ~a\n" mn)
          (exit 1))
        (hash-ref all-modes mn)))
    (run-parallel-evolutions repo modes))

  (define (run-parallel-freestyle repo-name goals)
    "Run multiple freestyle goals in parallel on the same repo."
    (define repo (load-repo-config repo-name))
    (define modes
      (for/list ([goal (in-list goals)])
        (make-freestyle-mode goal
          #:repo-path (repo-config-path repo)
          #:clarify? #f)))
    (run-parallel-evolutions repo modes))

  (define (run-worktree-freestyle repo-name goal)
    "Run a single freestyle evolution in its own worktree."
    (define repo (load-repo-config repo-name))
    (define fm (make-freestyle-mode goal
                 #:repo-path (repo-config-path repo)
                 #:clarify? #f))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree repo fm))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url)))

  (define (run-worktree-mode repo-name mode-name)
    "Run a single predefined mode in its own worktree."
    (define repo (load-repo-config repo-name))
    (unless (hash-has-key? all-modes mode-name)
      (eprintf "Unknown mode: ~a\n" mode-name)
      (exit 1))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree repo (hash-ref all-modes mode-name)))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url)))

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

    ;; ---- Local commands (run from cwd with .ruyi.rkt) ----

    ;; ruyi do <goal...>
    [(and (>= (length args) 2) (string=? (first args) "do"))
     (run-local-do (current-directory) (string-join (cdr args) " "))]

    ;; ruyi pdo <goal1> // <goal2> // ...
    [(and (>= (length args) 2) (string=? (first args) "pdo"))
     (define goal-str (string-join (cdr args) " "))
     (define goals (map string-trim (string-split goal-str "//")))
     (run-local-pdo (current-directory) goals)]

    ;; ruyi wrun <mode>
    [(and (= (length args) 2) (string=? (first args) "wrun"))
     (run-local-wrun (current-directory) (second args))]

    ;; ---- Legacy commands (<repo> prefix, uses configs/<repo>.rkt) ----

    ;; <repo> do <goal...>
    [(and (>= (length args) 3) (string=? (second args) "do"))
     (define repo-name (first args))
     (define goal (string-join (cddr args) " "))
     (run-worktree-freestyle repo-name goal)]

    ;; <repo> wrun <mode>
    [(and (= (length args) 3) (string=? (second args) "wrun"))
     (run-worktree-mode (first args) (third args))]

    ;; <repo> parallel <mode1> <mode2> ...
    [(and (>= (length args) 3) (string=? (second args) "parallel"))
     (define repo-name (first args))
     (define mode-names (cddr args))
     (run-parallel-modes repo-name mode-names)]

    ;; <repo> pdo <goal1> // <goal2> // ...
    [(and (>= (length args) 3) (string=? (second args) "pdo"))
     (define repo-name (first args))
     (define goal-str (string-join (cddr args) " "))
     (define goals
       (map string-trim (string-split goal-str "//")))
     (run-parallel-freestyle repo-name goals)]

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

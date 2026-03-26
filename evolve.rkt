#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list
           racket/runtime-path)
  (require racket/file)
  (require "config.rkt" "engine.rkt" "init.rkt" "git.rkt" "claude.rkt"
           "modes/freestyle.rkt")

  (define-runtime-path ruyi-dir ".")

  ;; ============================================================
  ;; Ruyi — as you wish
  ;; ============================================================

  (define (print-usage)
    (displayln "
Ruyi — as you wish

Usage (run from your project directory):
  ruyi do <goal>                          Do something (freestyle)
  ruyi do <mode> [prompt]                 Run a saved mode, with optional prompt
  ruyi pdo <g1> // <g2> // ...            Do multiple things in parallel
  ruyi modes                              List saved modes
  ruyi import <file>                      Import a mode file
  ruyi clean                              Remove stale worktrees
  ruyi init [path]                        Manually init (usually not needed)
  ruyi update                             Update ruyi to latest version
  ruyi version                            Show version

Examples:
  ruyi do \"add CLI support\"
  ruyi do \"fix auth bug\"                  # another terminal, parallel!
  ruyi do test-coverage                   # run saved mode
  ruyi do test-coverage \"focus on auth\"   # saved mode + extra prompt
  ruyi pdo \"add tests\" // \"translate README\""))

  (define (load-local-config dir)
    "Load repo-config from .ruyi.rkt in dir. Auto-inits if missing."
    (ruyi-ensure-init! dir)
    (define config-file (build-path dir ".ruyi.rkt"))
    (define config-module `(file ,(path->string config-file)))
    (dynamic-require config-module 'local-config))

  ;; ============================================================
  ;; Mode management: save & load reusable goals
  ;; ============================================================

  (define (modes-dir dir)
    (build-path dir ".ruyi-modes"))

  (define (save-mode! dir goal kept)
    "After a successful freestyle run, offer to save the goal as a reusable mode."
    (when (> kept 0)
      (define answer (read-line-interactive "\nSave as reusable mode? Name (Enter to skip): "))
      (when (and (not (string=? answer ""))
                 (regexp-match? #rx"^[a-zA-Z0-9_-]+$" answer))
        (define mdir (modes-dir dir))
        (make-directory* mdir)
        (define mode-file (build-path mdir (string-append answer ".txt")))
        (call-with-output-file mode-file
          (lambda (out) (displayln goal out))
          #:exists 'replace)
        (printf "Saved: .ruyi-modes/~a.txt\n" answer)
        (printf "Re-run anytime: ruyi run ~a\n" answer))))

  (define (load-mode dir name)
    "Load a saved mode by name. Returns the goal string or #f."
    (define mode-file (build-path (modes-dir dir) (string-append name ".txt")))
    (and (file-exists? mode-file)
         (string-trim (file->string mode-file))))

  (define (list-modes dir)
    "List available saved modes."
    (define mdir (modes-dir dir))
    (if (directory-exists? mdir)
        (for/list ([f (directory-list mdir)]
                   #:when (string-suffix? (path->string f) ".txt"))
          (define name (path->string f))
          (substring name 0 (- (string-length name) 4)))
        '()))

  ;; ============================================================
  ;; Run commands
  ;; ============================================================

  (define (run-local-do dir goal)
    "Run freestyle evolution in worktree, using .ruyi.rkt from cwd."
    (define repo (load-local-config dir))
    (define fm (make-freestyle-mode goal
                 #:repo-path (repo-config-path repo)
                 #:clarify? #t))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree repo fm))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url))
    (save-mode! dir goal kept))

  (define (run-local-pdo dir goals)
    "Run multiple freestyle goals in parallel, using .ruyi.rkt from cwd."
    (define repo (load-local-config dir))
    (define modes
      (for/list ([goal (in-list goals)])
        (make-freestyle-mode goal
          #:repo-path (repo-config-path repo)
          #:clarify? #f)))
    (run-parallel-evolutions repo modes))

  ;; ---- Dispatch ----

  (define args (vector->list (current-command-line-arguments)))

  (cond
    ;; No args: show help
    [(empty? args)
     (print-usage)]

    ;; "init" command
    [(string=? (first args) "init")
     (ruyi-init! (if (> (length args) 1)
                     (path->complete-path (string->path (second args)))
                     (current-directory)))]

    ;; Help
    [(or (string=? (first args) "--help") (string=? (first args) "-h"))
     (print-usage)]

    ;; ruyi do [mode] <goal...>
    ;; If first arg after "do" is a saved mode name, use it + rest as prompt
    ;; Otherwise, treat everything as freestyle goal
    [(and (>= (length args) 2) (string=? (first args) "do"))
     (define dir (current-directory))
     (define rest (cdr args))
     (define maybe-mode (first rest))
     (define saved-goal (load-mode dir maybe-mode))
     (define goal
       (cond
         [saved-goal
          ;; First arg is a mode name
          (define extra (if (> (length rest) 1)
                            (string-join (cdr rest) " ")
                            ""))
          (if (string=? extra "")
              saved-goal
              (string-append saved-goal "\n\nAdditional: " extra))]
         [else
          ;; All args are the goal
          (string-join rest " ")]))
     ;; Support @file: read goal from file
     (define final-goal
       (if (string-prefix? goal "@")
           (let ([fpath (substring goal 1)])
             (unless (file-exists? fpath)
               (eprintf "File not found: ~a\n" fpath)
               (exit 1))
             (printf "Reading goal from: ~a\n" fpath)
             (file->string fpath))
           goal))
     (run-local-do dir final-goal)]

    ;; ruyi pdo <goal1> // <goal2> // ...
    [(and (>= (length args) 2) (string=? (first args) "pdo"))
     (define goal-str (string-join (cdr args) " "))
     (define goals (map string-trim (string-split goal-str "//")))
     (run-local-pdo (current-directory) goals)]

    ;; ruyi modes
    [(and (= (length args) 1) (string=? (first args) "modes"))
     (define available (list-modes (current-directory)))
     (cond
       [(null? available)
        (displayln "No saved modes. Run `ruyi do \"goal\"` and save one after.")]
       [else
        (printf "Saved modes:\n")
        (for ([m (in-list available)])
          (define goal (load-mode (current-directory) m))
          (printf "  ~a — ~a\n" m (if goal goal "?")))])]

    ;; ruyi import <file>
    [(and (= (length args) 2) (string=? (first args) "import"))
     (define source (second args))
     (define dir (current-directory))
     (define mdir (modes-dir dir))
     (make-directory* mdir)
     (define source-path (string->path source))
     (unless (file-exists? source-path)
       (eprintf "File not found: ~a\n" source)
       (exit 1))
     (define name (path->string (file-name-from-path source-path)))
     (define dest (build-path mdir name))
     (copy-file source-path dest #t)
     (printf "Imported: .ruyi-modes/~a\n" name)]

    ;; ruyi clean
    [(and (= (length args) 1) (string=? (first args) "clean"))
     (define dir (current-directory))
     (ruyi-ensure-init! dir)
     (define repo (load-local-config dir))
     (define tmp (path->string (find-system-path 'temp-dir)))
     (define stale
       (for/list ([d (directory-list (string->path tmp))]
                  #:when (string-prefix? (path->string d) "ruyi-wt-"))
         (build-path tmp (path->string d))))
     (cond
       [(null? stale)
        (printf "No stale worktrees found.\n")]
       [else
        (printf "Cleaning ~a stale worktree(s):\n" (length stale))
        (for ([wt (in-list stale)])
          (printf "  ~a\n" (path->string wt))
          (git-worktree-remove! repo (path->string wt)))
        (printf "Done.\n")])]

    ;; Unknown
    [else
     (eprintf "Unknown command: ~a\n" (string-join args " "))
     (print-usage)
     (exit 1)]))

#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list
           racket/runtime-path)
  (require "config.rkt" "engine.rkt" "init.rkt" "git.rkt" "claude.rkt"
           "task-file.rkt")

  (define-runtime-path ruyi-dir ".")

  (define TASK-FILE ".ruyi-task")

  ;; ============================================================
  ;; Ruyi — as you wish
  ;; ============================================================

  (define (print-usage)
    (displayln "
Ruyi — as you wish

Usage (run from your project directory):
  ruyi do <goal>                          Do something (auto-plans with Claude Code)
  ruyi do @file.md                        Read goal from file
  ruyi do                                 Re-run existing .ruyi-task
  ruyi pdo <g1> // <g2> // ...            Do multiple things in parallel
  ruyi modes                              List saved modes
  ruyi import <file>                      Import a mode file
  ruyi clean                              Remove ruyi-generated files
  ruyi init [path]                        Manually init project
  ruyi update                             Update ruyi
  ruyi version                            Show version

Examples:
  ruyi do \"add CLI support\"
  ruyi do @requirements.md
  ruyi do                                 # re-run .ruyi-task
  ruyi pdo \"add tests\" // \"translate docs\""))

  ;; ============================================================
  ;; Core: generate task file → execute
  ;; ============================================================

  (define (ensure-project dir)
    "Ensure .ruyi.rkt exists (project config). Auto-init if needed."
    (ruyi-ensure-init! dir)
    (define config-file (build-path dir ".ruyi.rkt"))
    (define config-module `(file ,(path->string config-file)))
    (dynamic-require config-module 'local-config))

  (define (generate-task-file dir goal)
    "Use Claude Code (full agent mode) to generate .ruyi-task."
    (printf "Planning with Claude Code...\n")
    (define repo (ensure-project dir))
    (define prompt (task-generation-prompt goal))
    (define-values (ok? output)
      (claude-agent (repo-config-path repo) prompt))
    (unless ok?
      (eprintf "Planning failed. Try again or create .ruyi-task manually.\n")
      (exit 1))
    ;; Claude Code should have written .ruyi-task directly
    (define task-path (build-path dir TASK-FILE))
    (unless (file-exists? task-path)
      (eprintf "Claude Code did not create .ruyi-task. Try again.\n")
      (exit 1))
    (read-ruyi-task task-path))

  (define (run-do dir goal)
    "Main do flow: plan → confirm → execute."
    (define task-path (build-path dir TASK-FILE))
    (define task
      (cond
        ;; No goal given but .ruyi-task exists → re-run
        [(and (not goal) (file-exists? task-path))
         (printf "Using existing .ruyi-task\n")
         (read-ruyi-task task-path)]
        ;; Goal given → generate new task file
        [goal
         (generate-task-file dir goal)]
        ;; No goal, no task file
        [else
         (eprintf "No goal and no .ruyi-task found.\n")
         (print-usage)
         (exit 1)]))

    ;; Show plan
    (print-ruyi-task task)

    ;; Execute
    (define repo (ensure-project dir))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree-task repo task))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url)))

  (define (run-pdo dir goals)
    "Parallel do: generate task files and run in parallel."
    (define repo (ensure-project dir))
    (define tasks
      (for/list ([goal (in-list goals)])
        (generate-task-file dir goal)))
    (run-parallel-task-evolutions repo tasks))

  ;; ============================================================
  ;; Mode management (kept for saved goals)
  ;; ============================================================

  (define (modes-dir dir) (build-path dir ".ruyi-modes"))

  (define (load-mode dir name)
    (define mode-file (build-path (modes-dir dir) (string-append name ".txt")))
    (and (file-exists? mode-file)
         (string-trim (file->string mode-file))))

  (define (list-modes dir)
    (define mdir (modes-dir dir))
    (if (directory-exists? mdir)
        (for/list ([f (directory-list mdir)]
                   #:when (string-suffix? (path->string f) ".txt"))
          (define name (path->string f))
          (substring name 0 (- (string-length name) 4)))
        '()))

  ;; ============================================================
  ;; Dispatch
  ;; ============================================================

  (define args (vector->list (current-command-line-arguments)))

  (cond
    ;; No args: re-run .ruyi-task or show help
    [(empty? args)
     (if (file-exists? (build-path (current-directory) TASK-FILE))
         (run-do (current-directory) #f)
         (print-usage))]

    ;; init
    [(string=? (first args) "init")
     (ruyi-init! (if (> (length args) 1)
                     (path->complete-path (string->path (second args)))
                     (current-directory)))]

    ;; help
    [(or (string=? (first args) "--help") (string=? (first args) "-h"))
     (print-usage)]

    ;; ruyi do [mode|@file|goal...]
    [(and (>= (length args) 1) (string=? (first args) "do"))
     (define dir (current-directory))
     (cond
       ;; ruyi do (no args) → re-run .ruyi-task
       [(= (length args) 1)
        (run-do dir #f)]
       [else
        (define rest (cdr args))
        (define first-arg (first rest))
        ;; Check if it's a saved mode
        (define saved-goal (load-mode dir first-arg))
        (define raw-goal
          (cond
            [saved-goal
             (define extra (if (> (length rest) 1)
                               (string-join (cdr rest) " ") ""))
             (if (string=? extra "")
                 saved-goal
                 (string-append saved-goal "\n\nAdditional: " extra))]
            [else (string-join rest " ")]))
        ;; Support @file
        (define goal
          (if (string-prefix? raw-goal "@")
              (let ([fpath (substring raw-goal 1)])
                (unless (file-exists? fpath)
                  (eprintf "File not found: ~a\n" fpath) (exit 1))
                (printf "Reading goal from: ~a\n" fpath)
                (file->string fpath))
              raw-goal))
        (run-do dir goal)])]

    ;; ruyi pdo
    [(and (>= (length args) 2) (string=? (first args) "pdo"))
     (define goal-str (string-join (cdr args) " "))
     (define goals (map string-trim (string-split goal-str "//")))
     (run-pdo (current-directory) goals)]

    ;; ruyi modes
    [(and (= (length args) 1) (string=? (first args) "modes"))
     (define available (list-modes (current-directory)))
     (cond
       [(null? available)
        (displayln "No saved modes.")]
       [else
        (printf "Saved modes:\n")
        (for ([m (in-list available)])
          (define goal (load-mode (current-directory) m))
          (printf "  ~a — ~a\n" m (if goal goal "?")))])]

    ;; ruyi import
    [(and (= (length args) 2) (string=? (first args) "import"))
     (define source (second args))
     (define dir (current-directory))
     (define mdir (modes-dir dir))
     (make-directory* mdir)
     (define source-path (string->path source))
     (unless (file-exists? source-path)
       (eprintf "File not found: ~a\n" source) (exit 1))
     (define name (path->string (file-name-from-path source-path)))
     (copy-file source-path (build-path mdir name) #t)
     (printf "Imported: .ruyi-modes/~a\n" name)]

    ;; ruyi clean
    [(and (= (length args) 1) (string=? (first args) "clean"))
     (define dir (current-directory))
     (define ruyi-files
       (list ".ruyi.rkt" ".ruyi-task" "evolution-log.tsv" "evolution-journal.md"))
     (define ruyi-dirs (list ".ruyi-modes"))
     (define cleaned 0)
     (for ([f (in-list ruyi-files)])
       (define p (build-path dir f))
       (when (file-exists? p)
         (delete-file p)
         (printf "  Removed ~a\n" f)
         (set! cleaned (add1 cleaned))))
     (for ([d (in-list ruyi-dirs)])
       (define p (build-path dir d))
       (when (directory-exists? p)
         (delete-directory/files p)
         (printf "  Removed ~a/\n" d)
         (set! cleaned (add1 cleaned))))
     (define tmp (path->string (find-system-path 'temp-dir)))
     (define stale
       (for/list ([d (directory-list (string->path tmp))]
                  #:when (string-prefix? (path->string d) "ruyi-wt-"))
         (build-path tmp (path->string d))))
     (when (not (null? stale))
       (for ([wt (in-list stale)])
         (when (directory-exists? wt) (delete-directory/files wt)))
       (set! cleaned (+ cleaned (length stale))))
     (if (= cleaned 0)
         (printf "Nothing to clean.\n")
         (printf "Cleaned ~a item(s).\n" cleaned))]

    ;; Unknown
    [else
     (eprintf "Unknown command: ~a\n" (string-join args " "))
     (print-usage)
     (exit 1)]))

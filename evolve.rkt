#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format racket/path racket/file racket/list
           racket/runtime-path)
  (require "config.rkt" "engine.rkt" "init.rkt" "git.rkt" "claude.rkt"
           "task-file.rkt")

  (define-runtime-path ruyi-dir ".")


  ;; ============================================================
  ;; Ruyi — as you wish
  ;; ============================================================

  (define (print-usage)
    (displayln "
Ruyi — as you wish

Usage (run from your project directory):
  ruyi do <goal>                          Do something (auto-plans with Claude Code)
  ruyi do @file.md                        Read goal from file
  ruyi do #123                            Do a GitHub issue
  ruyi do #123 \"extra context\"            Issue + additional instructions
  ruyi do                                 Re-run latest task
  ruyi tasks                              List all tasks
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
    "Launch Claude Code interactively to plan and generate task.rkt in a task folder."
    (define repo (ensure-project dir))
    (define folder (create-task-dir dir goal))
    (printf "Task folder: ~a\n" (path->string folder))
    (define ruyi-home (path->string (simplify-path (expand-user-path "~/.ruyi"))))
    (define prompt (task-generation-prompt goal folder ruyi-home))
    (define exit-code (claude-interactive (repo-config-path repo) prompt))
    (define tf (task-file-in-folder folder))
    (unless (file-exists? tf)
      (eprintf "No task file created at ~a\n" (path->string tf))
      (exit 1))
    (values folder (read-ruyi-task tf)))

  (define (run-do dir goal)
    "Main do flow: plan → execute."
    (define-values (folder task)
      (cond
        ;; No goal → re-run latest task
        [(not goal)
         (define latest (latest-task-dir dir))
         (unless latest
           (eprintf "No goal and no existing tasks.\n")
           (print-usage)
           (exit 1))
         (printf "Re-running: ~a\n" (path->string (file-name-from-path latest)))
         (values latest (read-ruyi-task (task-file-in-folder latest)))]
        ;; Goal given → generate new task
        [else
         (generate-task-file dir goal)]))

    ;; Show plan
    (print-ruyi-task task)

    ;; Execute
    (define repo (ensure-project dir))
    (define-values (branch kept pr-url)
      (evolution-loop/worktree-task repo task))
    (printf "\nDone: ~a (kept ~a)\n" branch kept)
    (when pr-url (printf "PR: ~a\n" pr-url))
    (printf "Task: ~a\n" (path->string folder)))

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
    ;; No args: re-run latest task or show help
    [(empty? args)
     (if (latest-task-dir (current-directory))
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
        ;; Support @file and #issue
        (define goal
          (cond
            ;; @file — read from file
            [(string-prefix? raw-goal "@")
             (let ([fpath (substring raw-goal 1)])
               (unless (file-exists? fpath)
                 (eprintf "File not found: ~a\n" fpath) (exit 1))
               (printf "Reading goal from: ~a\n" fpath)
               (file->string fpath))]
            ;; #123 or #issue — fetch GitHub issue
            [(regexp-match #rx"^#([0-9]+)" raw-goal)
             => (lambda (m)
                  (define issue-num (second m))
                  ;; Check if gh is available
                  (unless (find-executable-path "gh")
                    (eprintf "GitHub CLI (gh) is required for #issue support.\n")
                    (eprintf "Install: https://cli.github.com/\n")
                    (exit 1))
                  (printf "Fetching issue #~a...\n" issue-num)
                  (define issue-text
                    (with-handlers ([exn:fail?
                                     (lambda (e)
                                       (eprintf "Failed to fetch issue: ~a\n" (exn-message e))
                                       (exit 1))])
                      (shell!/dir (path->string dir)
                                  "gh" "issue" "view" issue-num
                                  "--json" "title,body"
                                  "--jq" "\"Issue #\" + (.number|tostring) + \": \" + .title + \"\\n\\n\" + .body")))
                  ;; Append any extra text after #123
                  (define extra (regexp-replace #rx"^#[0-9]+" raw-goal ""))
                  (define trimmed-extra (string-trim extra))
                  (if (string=? trimmed-extra "")
                      (string-trim issue-text)
                      (string-append (string-trim issue-text)
                                     "\n\nAdditional: " trimmed-extra)))]
            [else raw-goal]))
        (run-do dir goal)])]

    ;; ruyi pdo
    [(and (>= (length args) 2) (string=? (first args) "pdo"))
     (define goal-str (string-join (cdr args) " "))
     (define goals (map string-trim (string-split goal-str "//")))
     (run-pdo (current-directory) goals)]

    ;; ruyi tasks
    [(and (= (length args) 1) (string=? (first args) "tasks"))
     (print-task-list (current-directory))]

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
       (list ".ruyi.rkt" "evolution-log.tsv" "evolution-journal.md"))
     (define ruyi-dirs (list ".ruyi-modes" ".ruyi-tasks"))
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
     ;; Clean stale worktrees
     (define tmp (path->string (find-system-path 'temp-dir)))
     (define stale
       (for/list ([d (directory-list (string->path tmp))]
                  #:when (string-prefix? (path->string d) "ruyi-wt-"))
         (build-path tmp (path->string d))))
     (when (not (null? stale))
       (printf "  Removing ~a stale worktree(s)\n" (length stale))
       (for ([wt (in-list stale)])
         (when (directory-exists? wt) (delete-directory/files wt)))
       (set! cleaned (+ cleaned (length stale))))
     ;; Clean ruyi branches (evolve/*)
     (when (directory-exists? (build-path dir ".git"))
       (define branch-output
         (with-handlers ([exn:fail? (lambda (_) "")])
           (shell!/dir (path->string dir) "git" "branch")))
       (define ruyi-branches
         (filter (lambda (b)
                   (or (string-contains? b "ruyi/")
                       (string-contains? b "evolve/")))  ; legacy
                 (map string-trim (string-split branch-output "\n"))))
       (for ([b (in-list ruyi-branches)])
         ;; Skip if it's the current branch
         (unless (string-prefix? b "*")
           (with-handlers ([exn:fail? (lambda (_) (void))])
             (shell!/dir (path->string dir) "git" "branch" "-D" b)
             (printf "  Deleted branch: ~a\n" b)
             (set! cleaned (add1 cleaned))))))
     (if (= cleaned 0)
         (printf "Nothing to clean.\n")
         (printf "Cleaned ~a item(s).\n" cleaned))]

    ;; Unknown
    [else
     (eprintf "Unknown command: ~a\n" (string-join args " "))
     (print-usage)
     (exit 1)]))

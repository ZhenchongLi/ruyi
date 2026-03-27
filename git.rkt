#lang racket/base
(require racket/system racket/string racket/port racket/format racket/list)
(require "config.rkt")
(provide (all-defined-out))

;; ============================================================
;; Shell execution helper
;; ============================================================

(define (shell-in-dir dir . args)
  "Run a command in the given directory, return (values exit-code stdout stderr)."
  (define out (open-output-string))
  (define err (open-output-string))
  (parameterize ([current-directory dir]
                 [current-output-port out]
                 [current-error-port err])
    (define exit-code
      (apply system*/exit-code
             (find-executable-path (car args))
             (cdr args)))
    (values exit-code
            (get-output-string out)
            (get-output-string err))))

(define (shell!/dir dir . args)
  "Run a command, raise on failure, return stdout."
  (define-values (code stdout stderr) (apply shell-in-dir dir args))
  (unless (zero? code)
    (error 'shell! "Command failed (~a): ~a\n~a"
           code (string-join args " ") stderr))
  stdout)

(define (shell! repo . args)
  "Run a command in the repo directory."
  (apply shell!/dir (repo-config-path repo) args))

(define (shell-ok? repo . args)
  "Run a command, return #t if exit code is 0."
  (define-values (code _ _2) (apply shell-in-dir (repo-config-path repo) args))
  (zero? code))

;; ============================================================
;; Git operations
;; ============================================================

(define (git-current-branch repo)
  (string-trim (shell! repo "git" "rev-parse" "--abbrev-ref" "HEAD")))

(define (git-create-branch! repo mode)
  "Create and checkout a new evolution branch."
  (define date-str
    (string-trim
     (with-output-to-string
       (lambda () (system "date +%m%d")))))
  (define branch-name
    (format "~a/~a" (mode-branch-prefix mode) date-str))
  ;; If branch exists, add a suffix
  (define final-branch
    (if (apply shell-ok? repo (list "git" "rev-parse" "--verify" branch-name))
        (format "~a-~a" branch-name
                (string-trim
                 (with-output-to-string
                   (lambda () (system "date +%H%M%S")))))
        branch-name))
  (shell! repo "git" "checkout" "-b" final-branch)
  final-branch)

(define (git-commit! repo mode tsk)
  "Stage and commit changes, return short hash."
  (shell! repo "git" "add" "-A")
  (define msg (format "~a: ~a" (mode-commit-prefix mode) (task-description tsk)))
  (shell! repo "git" "commit" "-m" msg)
  (string-trim (shell! repo "git" "rev-parse" "--short" "HEAD")))

(define (git-revert! repo)
  "Discard all working tree changes and remove untracked files."
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (shell! repo "git" "checkout" "."))
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (shell! repo "git" "clean" "-fd")))

(define (git-diff-line-count repo)
  "Count lines of diff (staged + unstaged)."
  (define diff-output
    (with-handlers ([exn:fail? (lambda (_) "")])
      (shell! repo "git" "diff" "HEAD")))
  (length (string-split diff-output "\n")))

(define (git-changed-files repo)
  "List files changed relative to HEAD."
  (define output (shell! repo "git" "diff" "--name-only" "HEAD"))
  (define unstaged (shell! repo "git" "diff" "--name-only"))
  (define untracked
    (with-handlers ([exn:fail? (lambda (_) "")])
      (shell! repo "git" "ls-files" "--others" "--exclude-standard")))
  (remove-duplicates
   (filter (lambda (s) (not (string=? s "")))
           (append (string-split output "\n")
                   (string-split unstaged "\n")
                   (string-split untracked "\n")))))

(define (git-check-forbidden-files repo)
  "Return list of forbidden files that were modified."
  (define changed (git-changed-files repo))
  (define forbidden (repo-config-forbidden-files repo))
  (filter (lambda (f)
            (for/or ([pat (in-list forbidden)])
              (or (string=? f pat)
                  (string-suffix? f pat)
                  ;; glob-like: "*.csproj"
                  (and (string-prefix? pat "*")
                       (string-suffix? f (substring pat 1))))))
          changed))

(define (git-ensure-clean! repo)
  "Ensure working tree is clean."
  (define-values (code stdout _)
    (shell-in-dir (repo-config-path repo) "git" "status" "--porcelain"))
  (unless (string=? (string-trim stdout) "")
    (git-revert! repo)))

(define (git-push-branch! repo)
  "Push the current branch to origin with upstream tracking."
  (define branch (git-current-branch repo))
  (shell! repo "git" "push" "-u" "origin" branch))

;; ============================================================
;; Git worktree operations (for parallel evolution)
;; ============================================================

(define (git-worktree-add! repo branch-name)
  "Create a worktree for branch-name under a temp directory.
   Returns the worktree path (string)."
  (define wt-dir
    (path->string
     (build-path (find-system-path 'temp-dir)
                 (format "ruyi-wt-~a" (string-replace branch-name "/" "-")))))
  ;; Remove stale worktree if it exists
  (when (directory-exists? (string->path wt-dir))
    (with-handlers ([exn:fail? (lambda (_) (void))])
      (shell! repo "git" "worktree" "remove" "--force" wt-dir)))
  (shell! repo "git" "worktree" "add" wt-dir branch-name)
  wt-dir)

(define (git-worktree-remove! repo wt-dir)
  "Remove a worktree and prune."
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (shell! repo "git" "worktree" "remove" "--force" wt-dir))
  (with-handlers ([exn:fail? (lambda (_) (void))])
    (shell! repo "git" "worktree" "prune")))

;; ============================================================
;; GitHub PR operations
;; ============================================================

(define (gh-create-and-merge-pr! repo mode-obj kept-tasks)
  "Create a PR via gh and auto-merge it. kept-tasks is a list of task structs."
  (define branch (git-current-branch repo))
  (define title (format "~a: ~a" (mode-commit-prefix mode-obj) branch))
  (define body
    (string-append
     "## Kept iterations\n\n"
     (string-join
      (for/list ([tsk (in-list (reverse kept-tasks))])
        (format "- ~a" (task-description tsk)))
      "\n")
     "\n"))

  ;; Create the PR
  (define pr-url
    (string-trim
     (shell! repo "gh" "pr" "create"
             "--title" title
             "--body" body
             "--head" branch
             "--base" (repo-config-base-branch repo))))

  (printf "PR created: ~a\n" pr-url)

  ;; Attempt merge; on failure, rebase onto main and retry
  (define (try-merge!)
    (shell! repo "gh" "pr" "merge" "--merge" "--auto" "--delete-branch" pr-url))

  (with-handlers
    ([exn:fail?
      (lambda (e)
        (printf "Merge failed, attempting rebase onto ~a...\n"
                (repo-config-base-branch repo))
        (shell! repo "git" "fetch" "origin" (repo-config-base-branch repo))
        (shell! repo "git" "rebase"
                (format "origin/~a" (repo-config-base-branch repo)))
        (shell! repo "git" "push" "--force-with-lease" "origin" branch)
        (try-merge!))])
    (try-merge!))

  (printf "PR merge initiated: ~a\n" pr-url)
  pr-url)

#lang racket/base
(require racket/string racket/format racket/path racket/file racket/port racket/system)
(require "config.rkt" "detect.rkt" "claude.rkt")
(provide ruyi-init!)

;; ============================================================
;; init: detect project + collect intent + generate .ruyi.rkt
;; ============================================================

(define RUYI-CONFIG-FILE ".ruyi.rkt")

(define (ruyi-init! path)
  "Interactive init: detect project, ask intent, generate config."

  (printf "\n=== Ruyi Init ===\n\n")

  ;; Step 1: Detect project
  (define info (detect-project path))
  (printf "Detected: ~a\n" (describe-project info))
  (printf "Path:     ~a\n\n" (path->string path))

  (when (string=? (project-info-language info) "unknown")
    (printf "Could not detect project type.\n")
    (printf "Please make sure you're in a project directory.\n")
    (exit 1))

  ;; Step 2: Ensure git
  (unless (directory-exists? (build-path path ".git"))
    (printf "No git repo found. Initializing...\n")
    (parameterize ([current-directory path])
      (system "git init")
      (system "git add -A")
      (system "git commit -m 'initial commit'")))

  ;; Step 3: Detect base branch
  (define base-branch
    (string-trim
     (with-output-to-string
       (lambda ()
         (parameterize ([current-directory path])
           (system "git rev-parse --abbrev-ref HEAD"))))))

  ;; Step 4: Collect intent
  (printf "What would you like ruyi to do?\n")
  (printf "Examples:\n")
  (printf "  - Improve test coverage\n")
  (printf "  - Fix GitHub issues\n")
  (printf "  - Refactor large files\n")
  (printf "  - Translate docs to English\n")
  (printf "  - Any goal you have in mind\n")
  (define intent (read-line-interactive "\n> "))

  (when (or (eof-object? intent) (string=? (string-trim intent) ""))
    (printf "No intent provided. Using default: improve test coverage\n")
    (set! intent "improve test coverage"))

  ;; Step 5: Use Claude to interpret intent and suggest mode
  (printf "\nAnalyzing your intent...\n")
  (define-values (ok? claude-response)
    (claude-execute path
     (string-append
      "I'm setting up an evolution engine for a "
      (describe-project info) " project.\n\n"
      "The user wants: " intent "\n\n"
      "Based on this intent, respond with EXACTLY one JSON object (no markdown, no explanation):\n"
      "{\n"
      "  \"mode\": \"coverage|filesize|issue|refactor|custom\",\n"
      "  \"description\": \"one sentence describing what ruyi will do\",\n"
      "  \"priority_dirs\": [\"most important dir first\", \"second\"],\n"
      "  \"extra_excluded\": [\"dirs to skip if any\"]\n"
      "}\n\n"
      "Choose the mode that best fits. If none of the standard modes fit, use \"custom\".\n"
      "priority_dirs should be subdirectories within the source tree that matter most for this intent.\n"
      "Only output the JSON, nothing else.")
     #:model "sonnet"
     #:timeout 30))

  ;; Step 6: Parse Claude's suggestion (or use defaults)
  (define suggested-mode "coverage")
  (define description "Improve test coverage by writing tests for untested files")
  (define extra-priority '())
  (define extra-excluded '())

  (when ok?
    ;; Simple JSON extraction via regex
    (define response (string-trim claude-response))
    (define (extract-field field str)
      (define m (regexp-match
                 (regexp (string-append "\"" field "\"\\s*:\\s*\"([^\"]+)\""))
                 str))
      (and m (cadr m)))

    (when (string-contains? response "\"mode\"")
      (define mode-val (extract-field "mode" response))
      (when mode-val (set! suggested-mode mode-val))
      (define desc-val (extract-field "description" response))
      (when desc-val (set! description desc-val))))

  (printf "\nPlan: ~a\n" description)
  (printf "Mode: ~a\n\n" suggested-mode)

  ;; Step 7: Generate .ruyi.rkt
  (define config-content
    (generate-config path info base-branch suggested-mode intent))

  (define config-path (build-path path RUYI-CONFIG-FILE))
  (call-with-output-file config-path
    (lambda (out) (display config-content out))
    #:exists 'replace)

  (printf "Created: ~a\n\n" RUYI-CONFIG-FILE)
  (printf "Ready! Run:\n")
  (printf "  cd ~a\n" (path->string path))
  (printf "  ruyi do \"your goal\"\n\n"))

;; ============================================================
;; Config file generator
;; ============================================================

(define (generate-config path info base-branch mode-name intent)
  (define lang (project-info-language info))
  (define source-dirs (project-info-source-dirs info))
  (define source-exts (project-info-source-exts info))
  (define excluded (project-info-excluded-dirs info))
  (define test-pat (project-info-test-pattern info))
  (define test-dir (project-info-test-dir info))
  (define forbidden (project-info-forbidden-files info))
  (define build-cmds (project-info-build-commands info))
  (define test-cmds (project-info-test-commands info))

  (string-append
   "#lang racket/base\n"
   ";; Generated by: ruyi init\n"
   ";; Intent: " intent "\n"
   ";; Language: " lang "\n"
   ";; Mode: " mode-name "\n"
   "(require (file \""
   (path->string (build-path (find-system-path 'orig-dir) "config.rkt"))
   "\"))\n"
   "(provide local-config local-mode-name)\n\n"
   "(define local-mode-name \"" mode-name "\")\n\n"
   "(define local-config\n"
   "  (repo-config\n"
   "   \"" (let-values ([(base name must-be-dir?) (split-path path)])
             (path->string name)) "\"  ; name\n"
   "   \"" (path->string path) "\"  ; path\n"
   "   \"" base-branch "\"  ; base-branch\n"
   "   '" (format "~s" source-dirs) "  ; source-dirs\n"
   "   '" (format "~s" source-exts) "  ; source-exts\n"
   "   '" (format "~s" excluded) "  ; excluded-dirs\n"
   "   '" (symbol->string test-pat) "  ; test-pattern\n"
   "   " (if test-dir (format "\"~a\"" test-dir) "#f") "  ; test-dir\n"
   "   '" (format "~s" forbidden) "  ; forbidden-files\n"
   "   '" (format "~s" build-cmds) "  ; validate-commands (build)\n"
   ;; Append test commands to validate
   "   '" (format "~s" (append build-cmds test-cmds)) "  ; validate-commands\n"
   "   '()  ; priority-dirs\n"
   "   '()  ; context-files\n"
   "   \"evolution-log.tsv\"  ; log-path\n"
   "   20  ; max-iterations\n"
   "   3   ; max-consecutive-fails\n"
   "   500))  ; max-diff-lines\n"))

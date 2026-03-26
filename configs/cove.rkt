#lang racket/base
(require "../config.rkt")
(provide cove-config)

(define cove-config
  (repo-config
   "cove"                                         ; name
   (build-path (find-system-path 'home-dir) "code" "cove") ; path
   "main"                                         ; base-branch
   '("src/")                                      ; source-dirs
   '(".ts" ".tsx")                                 ; source-exts
   '("src/components/ui/"                          ; excluded-dirs
     "src/types/"
     "src/i18n/"
     "src/test-utils/"
     "src/styles/")
   'sibling                                        ; test-pattern
   "__tests__"                                     ; test-alt-dir
   '("vitest.config.ts"                            ; forbidden-files
     "vite.config.ts"
     "tsconfig.json"
     "tailwind.config.ts"
     "package.json"
     "pnpm-lock.yaml"
     "CLAUDE.md"
     "AGENTS.md")
   '(("pnpm" "run" "build")                       ; validate-commands
     ("pnpm" "test"))
   '(("stores/" . 1)                              ; priority-dirs
     ("db/repos/" . 2)
     ("hooks/" . 3)
     ("lib/" . 4)
     ("components/" . 5))
   '("CLAUDE.md"                                   ; context-files
     ".agent/workflows/test-quality.md")
   ".agent/evolution/evolution-log.tsv"            ; log-path
   20                                              ; max-iterations
   3                                               ; max-consecutive-fails
   500))                                           ; max-diff-lines

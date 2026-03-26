#lang racket/base
(require "../config.rkt")
(provide docmod-config)

(define docmod-config
  (repo-config
   "docmod"                                        ; name
   (build-path (find-system-path 'home-dir) "code" "docmod") ; path
   "main"                                          ; base-branch
   '("src/Docmod.Core/")                           ; source-dirs
   '(".cs")                                        ; source-exts
   '()                                             ; excluded-dirs
   'mirror                                         ; test-pattern
   "tests/Docmod.Tests/"                           ; test-alt-dir
   '("*.csproj"                                    ; forbidden-files
     "Directory.Build.props"
     "Directory.Packages.props"
     "CLAUDE.md")
   '(("dotnet" "build" "--no-restore")             ; validate-commands
     ("dotnet" "test" "--no-build"))
   '(("Patch/" . 1)                                ; priority-dirs
     ("Html/" . 2)
     ("Api/" . 3)
     ("Reader/" . 4)
     ("Writer/" . 5)
     ("Commands/" . 6)
     ("Models/" . 7))
   '("CLAUDE.md")                                  ; context-files
   ".agent/evolution/evolution-log.tsv"            ; log-path
   20                                              ; max-iterations
   3                                               ; max-consecutive-fails
   500))                                           ; max-diff-lines

#lang racket/base
(require "../config.rkt")
(provide ruyi-config)

(define ruyi-config
  (repo-config
   "ruyi"                                          ; name
   (build-path (find-system-path 'home-dir) "code" "ruyi") ; path
   "main"                                          ; base-branch
   '(".")                                          ; source-dirs
   '(".rkt")                                       ; source-exts
   '("compiled/")                                  ; excluded-dirs
   'sibling                                        ; test-pattern
   #f                                              ; test-alt-dir
   '("evolve.rkt")                                 ; forbidden-files (entry point)
   '(("racket" "-e" "(require \"evolve.rkt\")")    ; validate: compile check
     ("raco" "test" "."))                           ; validate: run tests
   '(("engine" . 1)                                ; priority-dirs
     ("claude" . 2)
     ("git" . 3)
     ("validate" . 4)
     ("tasks" . 5)
     ("log" . 6)
     ("config" . 7)
     ("modes/" . 8)
     ("configs/" . 9))
   '()                                             ; context-files
   "evolution-log.tsv"                             ; log-path
   20                                              ; max-iterations
   10                                              ; max-consecutive-fails
   500))                                           ; max-diff-lines

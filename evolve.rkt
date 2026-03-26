#!/usr/bin/env racket
#lang racket/base
(module+ main
  (require racket/cmdline racket/string racket/format)
  (require "config.rkt" "engine.rkt"
           "configs/cove.rkt" "configs/docmod.rkt" "configs/ruyi.rkt"
           "modes/coverage.rkt" "modes/filesize.rkt"
           "modes/issue.rkt" "modes/refactor.rkt")

  ;; ============================================================
  ;; CLI entry point for Ruyi Evolution Engine
  ;; ============================================================

  ;; Registry
  (define repos
    (make-immutable-hash
     (list (cons "cove" cove-config)
           (cons "docmod" docmod-config)
           (cons "ruyi" ruyi-config))))

  (define modes
    (make-immutable-hash
     (list (cons "coverage" coverage-mode)
           (cons "filesize" filesize-mode)
           (cons "issue" issue-mode)
           (cons "refactor" refactor-mode))))

  ;; Parse args
  (define repo-name (make-parameter #f))
  (define mode-name-param (make-parameter #f))

  (command-line
   #:program "ruyi"
   #:usage-help
   "Ruyi Evolution Engine — deterministic outer loop, creative inner step"
   ""
   "Usage: racket evolve.rkt <repo> <mode>"
   ""
   "Repos:  cove, docmod, ruyi"
   "Modes:  coverage, filesize, issue, refactor"
   ""
   "Examples:"
   "  racket evolve.rkt cove coverage"
   "  racket evolve.rkt docmod coverage"
   "  racket evolve.rkt cove filesize"
   "  racket evolve.rkt ruyi coverage"
   #:args (repo mode)
   (repo-name repo)
   (mode-name-param mode))

  ;; Validate
  (unless (hash-has-key? repos (repo-name))
    (eprintf "Unknown repo: ~a\nAvailable: ~a\n"
             (repo-name) (string-join (hash-keys repos) ", "))
    (exit 1))

  (unless (hash-has-key? modes (mode-name-param))
    (eprintf "Unknown mode: ~a\nAvailable: ~a\n"
             (mode-name-param) (string-join (hash-keys modes) ", "))
    (exit 1))

  ;; Run
  (define repo (hash-ref repos (repo-name)))
  (define mode-obj (hash-ref modes (mode-name-param)))

  (evolution-loop repo mode-obj))

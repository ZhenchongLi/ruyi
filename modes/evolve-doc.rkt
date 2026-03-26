#lang racket/base
(require racket/string racket/format racket/file racket/path racket/list)
(require "../config.rkt" "../tasks.rkt" "../judge.rkt")
(provide evolve-doc-mode README-RUBRIC)

;; ============================================================
;; Evolve-doc mode: iteratively improve documents using Judge
;;
;; Unlike other modes (which validate with build+test),
;; this mode validates with LLM-as-Judge scoring.
;; ============================================================

(define README-RUBRIC
  "Score this README for an open-source developer tool on GitHub.

Dimensions (weight):

1. HOOK (25%) — First 2 lines. Would a scrolling developer stop?
   10: Instantly clear value prop, makes you want to try it
   5: Generic description, could be any tool
   1: No hook, just a title

2. CLARITY (20%) — Can someone understand what this does in 10 seconds?
   10: Crystal clear with concrete example
   5: Understandable after reading 2 paragraphs
   1: Confusing, jargon-heavy

3. QUICK START (25%) — How fast can someone go from zero to running?
   10: 3 commands or less, copy-paste ready
   5: Needs setup but instructions are clear
   1: Long setup, unclear steps

4. VISUAL (15%) — Does it have a diagram/screenshot showing how it works?
   10: Clear diagram that explains the core concept
   5: Some visual but not very helpful
   1: Wall of text, no visuals

5. CREDIBILITY (15%) — Does it feel real and trustworthy?
   10: Shows real output, has concrete examples, battle-tested feel
   5: Reasonable but generic examples
   1: Feels like vaporware

The target audience is developers who use AI coding tools (Claude Code, Cursor, Copilot).
They are technical, skeptical, and time-poor.")

(define (evolve-doc-select-task repo done-tasks)
  "Select the next document to evolve."
  (define repo-path (repo-config-path repo))
  ;; Priority: README first, then other docs
  (define candidates
    (filter (lambda (f) (not (member f (map task-source-file done-tasks))))
            (filter file-exists?
                    (list (build-path repo-path "README.md")))))

  (if (empty? candidates)
      #f
      (task (path->string (first candidates))
            "Evolve README.md"
            1
            (make-immutable-hash
             (list (cons 'rubric README-RUBRIC)
                   (cons 'min-score 8.0))))))

(define (evolve-doc-build-prompt repo tsk)
  "Build prompt for Claude to improve a document."
  (define file-path (task-source-file tsk))
  (define current-content
    (if (file-exists? file-path) (file->string file-path) ""))
  (define rubric (hash-ref (task-extra tsk) 'rubric))

  (string-append
   "You are improving a README.md for an open-source project.\n\n"
   "## Current README\n\n" current-content "\n\n"
   "## Quality rubric (what the judge will score you on)\n\n" rubric "\n\n"
   "## Project context\n\n"
   "Ruyi is a Racket-based evolution engine that uses a deterministic outer loop\n"
   "(select task, validate, git commit/revert) with Claude Code as the creative\n"
   "inner step. It can improve any codebase autonomously.\n\n"
   "Key selling points:\n"
   "- Works on ANY project (auto-detects language, build tool, test framework)\n"
   "- Zero config: 'ruyi init' asks what you want, generates everything\n"
   "- Deterministic safety: Racket code guarantees revert on failure\n"
   "- Self-evolving: ruyi evolved its own test suite and this README\n\n"
   "## Your task\n\n"
   "Rewrite the README to score higher on the rubric. Focus on:\n"
   "1. A compelling hook in the first 2 lines\n"
   "2. 3-command quick start that anyone can copy-paste\n"
   "3. A mermaid diagram showing the loop\n"
   "4. Real output example (what it looks like when running)\n\n"
   "Output the complete new README.md content. Nothing else.\n"))

(define evolve-doc-mode
  (mode 'evolve-doc
        evolve-doc-select-task
        evolve-doc-build-prompt
        "evolve/doc"
        "evolve(doc)"))

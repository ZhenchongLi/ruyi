#lang racket/base
(require racket/string racket/format racket/file racket/path racket/list)
(require "../config.rkt" "../tasks.rkt" "../judge.rkt")
(provide evolve-doc-mode README-RUBRIC)

;; ============================================================
;; Evolve-doc mode: iteratively improve documents using Judge
;;
;; Key design: each iteration receives the previous round's
;; Judge feedback, so Claude can fix specific weaknesses.
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

;; Mutable state: last round's feedback (shared across iterations)
(define last-weaknesses (make-parameter '()))
(define last-feedback (make-parameter ""))
(define last-score (make-parameter 0))
(define human-input (make-parameter ""))

(define (evolve-doc-set-feedback! score weaknesses feedback)
  "Called by engine after Judge evaluation to pass feedback to next round."
  (last-score score)
  (last-weaknesses weaknesses)
  (last-feedback feedback))

(define (evolve-doc-set-human-input! input)
  "Called by engine to pass user's interactive feedback."
  (human-input input))

(define (evolve-doc-select-task repo done-tasks)
  "Always return README as the task (we keep improving the same file)."
  (define repo-path (repo-config-path repo))
  (define readme (build-path repo-path "README.md"))
  (if (file-exists? readme)
      (task (path->string readme)
            (format "Evolve README.md (prev score: ~a)" (last-score))
            1
            (make-immutable-hash
             (list (cons 'rubric README-RUBRIC)
                   (cons 'min-score 7.5)
                   (cons 'set-feedback! evolve-doc-set-feedback!)
                   (cons 'set-human-input! evolve-doc-set-human-input!))))
      #f))

(define (evolve-doc-build-prompt repo tsk)
  "Build prompt with previous round's feedback included."
  (define file-path (task-source-file tsk))
  (define current-content
    (if (file-exists? file-path) (file->string file-path) ""))
  (define rubric (hash-ref (task-extra tsk) 'rubric))

  ;; Build feedback section from previous round
  (define prev-feedback
    (if (empty? (last-weaknesses))
        ""
        (string-append
         "## CRITICAL: Previous round's Judge feedback\n\n"
         "Last score: " (number->string (last-score)) "/10\n\n"
         "Weaknesses the Judge identified (FIX THESE):\n"
         (string-join (map (lambda (w) (string-append "- " w)) (last-weaknesses)) "\n")
         "\n\n"
         "Judge's improvement suggestions:\n"
         (last-feedback)
         "\n\n"
         "You MUST address these specific weaknesses. Do not ignore them.\n\n")))

  ;; Build human input section
  (define human-section
    (if (string=? (human-input) "")
        ""
        (string-append
         "## HIGHEST PRIORITY: Human feedback\n\n"
         "The human just said: \"" (human-input) "\"\n"
         "Address this FIRST before anything else.\n\n")))

  (string-append
   "You are improving a README.md for an open-source project.\n\n"
   human-section
   prev-feedback
   "## Current README\n\n" current-content "\n\n"
   "## Quality rubric (what the judge will score you on)\n\n" rubric "\n\n"
   "## Project context\n\n"
   "Ruyi is an evolution engine that improves codebases autonomously.\n"
   "It uses a deterministic loop (Racket) for safety, and Claude Code for creativity.\n\n"
   "Key facts:\n"
   "- Works on ANY project — auto-detects language (TypeScript, Python, C#, Rust, Go)\n"
   "- Zero config: 'ruyi init' asks what you want, generates everything\n"
   "- Safe: always works on a branch, auto-reverts on failure\n"
   "- Self-evolving: ruyi evolved its own README using LLM-as-Judge\n"
   "- Requires: Racket + Claude Code CLI\n"
   "- GitHub: https://github.com/ZhenchongLi/ruyi\n\n"
   "## Your task\n\n"
   "Rewrite the README to maximize the rubric score.\n"
   (if (not (empty? (last-weaknesses)))
       "PRIORITY: Fix the weaknesses from the previous round's feedback above.\n"
       "")
   "\nOutput the complete new README.md content. Nothing else — no explanation, no markdown fences around it.\n"
   "Keep your total diff under ~"
   (number->string (if (task-extra tsk) (hash-ref (task-extra tsk) 'max-diff 500) 500))
   " lines.\n"
   "Do NOT run git add, git commit, or any git commands. Just write the file — the harness handles git.\n"))

(define evolve-doc-mode
  (mode 'evolve-doc
        evolve-doc-select-task
        evolve-doc-build-prompt
        "evolve/doc"
        "evolve(doc)"))

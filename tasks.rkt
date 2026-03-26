#lang racket/base
(require racket/list racket/string racket/path racket/file)
(require "config.rkt")
(provide (all-defined-out))

;; ============================================================
;; Filesystem scanning for task selection
;; ============================================================

(define (find-all-files dir exts)
  "Recursively find all files with given extensions under dir."
  (if (not (directory-exists? dir))
      '()
      (for/fold ([result '()])
                ([p (in-directory dir)])
        (if (and (file-exists? p)
                 (for/or ([ext (in-list exts)])
                   (string-suffix? (path->string p) ext)))
            (cons (path->string p) result)
            result))))

(define (excluded? file-path excluded-dirs)
  "Check if a file path falls within any excluded directory."
  (for/or ([dir (in-list excluded-dirs)])
    (string-contains? file-path dir)))

(define (find-source-files repo)
  "Find all source files in the repo, excluding excluded dirs."
  (define base (repo-config-path repo))
  (define all-files
    (for/fold ([result '()])
              ([src-dir (in-list (repo-config-source-dirs repo))])
      (append result
              (find-all-files (build-path base src-dir)
                              (repo-config-source-exts repo)))))
  (filter (lambda (f)
            (not (excluded? f (repo-config-excluded-dirs repo))))
          all-files))

(define (path->relative file-path repo)
  "Convert absolute path to relative path from repo root."
  (define base (path->string (repo-config-path repo)))
  (if (string-prefix? file-path base)
      (let ([rel (substring file-path (string-length base))])
        (if (string-prefix? rel "/")
            (substring rel 1)
            rel))
      file-path))

;; ============================================================
;; Test file detection
;; ============================================================

(define (derive-test-path repo source-file)
  "Given a source file, return the expected test file path."
  (define ext
    (let ([parts (string-split (path->string (file-name-from-path source-file)) ".")])
      (string-append "." (last parts))))
  (define base-name
    (string-replace (path->string (file-name-from-path source-file))
                    ext ""))
  (define dir (path-only source-file))
  (case (repo-config-test-pattern repo)
    [(sibling)
     (build-path dir (string-append base-name ".test" ext))]
    [(mirror)
     (define test-dir
       (build-path (repo-config-path repo)
                   (repo-config-test-alt-dir repo)))
     (build-path test-dir (string-append base-name "Tests" ext))]
    [else
     (build-path dir (string-append base-name ".test" ext))]))

(define (test-file-exists? repo source-file)
  "Check if a test file exists for the given source file."
  (define test-path (derive-test-path repo source-file))
  (or (file-exists? test-path)
      ;; Also check __tests__ subdirectory for sibling pattern
      (and (eq? (repo-config-test-pattern repo) 'sibling)
           (let* ([dir (path-only source-file)]
                  [fname (file-name-from-path source-file)]
                  [ext (let ([parts (string-split (path->string fname) ".")])
                         (string-append "." (last parts)))]
                  [base (string-replace (path->string fname) ext "")]
                  [alt-path (build-path dir "__tests__"
                                        (string-append base ".test" ext))])
             (file-exists? alt-path)))))

;; ============================================================
;; File metrics
;; ============================================================

(define (count-lines file-path)
  "Count the number of lines in a file."
  (if (file-exists? file-path)
      (call-with-input-file file-path
        (lambda (in)
          (for/sum ([_ (in-lines in)]) 1)))
      0))

(define (find-nearby-test-files repo source-file [n 3])
  "Find up to n test files near the source file for reference."
  (define dir (path-only source-file))
  (define ext (last (string-split (path->string (file-name-from-path source-file)) ".")))
  (define test-ext (string-append ".test." ext))
  (define all
    (if (directory-exists? dir)
        (for/list ([p (directory-list dir #:build? #t)]
                   #:when (string-contains? (path->string p) test-ext))
          (path->string p))
        '()))
  (take all (min n (length all))))

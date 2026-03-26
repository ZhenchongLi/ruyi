#lang racket/base
(require racket/list racket/string racket/format racket/path racket/file)
(provide (all-defined-out))

;; ============================================================
;; Auto-detect project type from filesystem signals
;; ============================================================

(struct project-info
  (language         ; string: "typescript" | "python" | "csharp" | "rust" | "go" | "racket" | "unknown"
   framework        ; string or #f: "react" | "nextjs" | "django" | "flask" | etc.
   build-tool       ; string or #f: "pnpm" | "npm" | "yarn" | "cargo" | "dotnet" | "go" | "make"
   source-dirs      ; (listof string)
   source-exts      ; (listof string)
   excluded-dirs    ; (listof string)
   test-pattern     ; symbol: 'sibling | 'mirror
   test-dir         ; string or #f
   build-commands   ; (listof (listof string))
   test-commands    ; (listof (listof string))
   forbidden-files) ; (listof string)
  #:transparent)

(define (detect-project path)
  "Detect project type by examining files in the directory."
  (define (has? file) (file-exists? (build-path path file)))
  (define (has-dir? dir) (directory-exists? (build-path path dir)))

  (cond
    ;; TypeScript / JavaScript (package.json)
    [(has? "package.json")
     (define pkg-content (file->string (build-path path "package.json")))
     (define has-ts? (or (has? "tsconfig.json") (string-contains? pkg-content "typescript")))
     (define is-react? (string-contains? pkg-content "react"))
     (define build-tool
       (cond [(has? "pnpm-lock.yaml") "pnpm"]
             [(has? "yarn.lock") "yarn"]
             [(has? "bun.lockb") "bun"]
             [else "npm"]))
     (define has-vitest? (string-contains? pkg-content "vitest"))
     (define has-jest? (string-contains? pkg-content "jest"))
     (project-info
      (if has-ts? "typescript" "javascript")
      (cond [is-react? "react"]
            [(string-contains? pkg-content "next") "nextjs"]
            [(string-contains? pkg-content "vue") "vue"]
            [(string-contains? pkg-content "svelte") "svelte"]
            [(string-contains? pkg-content "express") "express"]
            [else #f])
      build-tool
      '("src/")                                        ; source-dirs
      (if has-ts? '(".ts" ".tsx") '(".js" ".jsx"))     ; source-exts
      '("node_modules/" "dist/" ".next/" "build/")     ; excluded-dirs
      'sibling                                         ; test-pattern
      #f                                               ; test-dir
      (list (list build-tool "run" "build"))            ; build-commands
      (list (if has-vitest?
                (list build-tool "test")
                (if has-jest?
                    (list build-tool "test")
                    (list build-tool "test"))))         ; test-commands
      (list "package.json" (string-append build-tool "-lock.yaml")
            "tsconfig.json" "vite.config.ts"))]        ; forbidden-files

    ;; Python (pyproject.toml or setup.py or requirements.txt)
    [(or (has? "pyproject.toml") (has? "setup.py") (has? "requirements.txt"))
     (define has-pytest? (or (has? "pytest.ini")
                             (has? "conftest.py")
                             (and (has? "pyproject.toml")
                                  (string-contains?
                                   (file->string (build-path path "pyproject.toml"))
                                   "pytest"))))
     (define build-tool
       (cond [(has? "pyproject.toml")
              (define content (file->string (build-path path "pyproject.toml")))
              (cond [(string-contains? content "uv") "uv"]
                    [(string-contains? content "poetry") "poetry"]
                    [else "pip"])]
             [else "pip"]))
     (project-info
      "python"
      (cond [(has-dir? "django") "django"]
            [(and (has? "pyproject.toml")
                  (string-contains? (file->string (build-path path "pyproject.toml")) "flask"))
             "flask"]
            [(and (has? "pyproject.toml")
                  (string-contains? (file->string (build-path path "pyproject.toml")) "fastapi"))
             "fastapi"]
            [else #f])
      build-tool
      '("src/" ".")                                    ; source-dirs
      '(".py")                                         ; source-exts
      '("__pycache__/" ".venv/" "venv/" ".tox/" "dist/" "build/") ; excluded
      'sibling                                         ; test-pattern: foo.py -> test_foo.py
      "tests/"                                         ; test-dir
      (list (list build-tool "run" "python" "-m" "py_compile")) ; build (placeholder)
      (list (if has-pytest?
                (list (if (string=? build-tool "uv") "uv" build-tool)
                      "run" "pytest")
                (list "python" "-m" "unittest")))      ; test-commands
      '("pyproject.toml" "setup.py" "requirements.txt"))]

    ;; C# / .NET (*.csproj or *.sln)
    [(or (has? "Directory.Build.props")
         (for/or ([f (directory-list path)])
           (string-suffix? (path->string f) ".sln"))
         (for/or ([f (directory-list path)])
           (string-suffix? (path->string f) ".csproj")))
     (project-info
      "csharp"
      ".NET"
      "dotnet"
      '("src/")                                        ; source-dirs
      '(".cs")                                         ; source-exts
      '("bin/" "obj/")                                 ; excluded
      'mirror                                          ; test-pattern
      "tests/"                                         ; test-dir
      '(("dotnet" "build"))                            ; build-commands
      '(("dotnet" "test"))                             ; test-commands
      '("*.csproj" "*.sln" "Directory.Build.props"))]  ; forbidden

    ;; Rust (Cargo.toml)
    [(has? "Cargo.toml")
     (project-info
      "rust"
      #f
      "cargo"
      '("src/")
      '(".rs")
      '("target/")
      'sibling
      #f
      '(("cargo" "build"))
      '(("cargo" "test"))
      '("Cargo.toml" "Cargo.lock"))]

    ;; Go (go.mod)
    [(has? "go.mod")
     (project-info
      "go"
      #f
      "go"
      '(".")
      '(".go")
      '("vendor/")
      'sibling
      #f
      '(("go" "build" "./..."))
      '(("go" "test" "./..."))
      '("go.mod" "go.sum"))]

    ;; Racket
    [(for/or ([f (directory-list path)])
       (string-suffix? (path->string f) ".rkt"))
     (project-info
      "racket"
      #f
      "raco"
      '(".")
      '(".rkt")
      '("compiled/")
      'sibling
      #f
      '(("raco" "make" "."))
      '(("raco" "test" "."))
      '())]

    ;; Unknown
    [else
     (project-info
      "unknown" #f #f
      '(".") '() '()
      'sibling #f
      '() '() '())]))

;; ============================================================
;; Pretty print detection results
;; ============================================================

(define (describe-project info)
  "Return a human-readable description of the detected project."
  (define lang (project-info-language info))
  (define fw (project-info-framework info))
  (define tool (project-info-build-tool info))
  (string-append
   (string-titlecase lang)
   (if fw (format " (~a)" fw) "")
   (if tool (format ", build: ~a" tool) "")))

# Install Ruyi

Copy the text below and paste it into Claude Code:

---

Install ruyi (如意) for me. Source: https://github.com/ZhenchongLi/ruyi

Steps:
1. Check my OS, shell, and existing tools (git, racket, gh)
2. Install missing dependencies:
   - git: use the best method for my OS (apt, dnf, xcode-select, etc.)
   - racket: prefer direct download from https://download.racket-lang.org/ if brew is not available. For mainland China users, consider mirror sources.
   - gh (GitHub CLI): optional, install if easy, skip if not
3. Clone https://github.com/ZhenchongLi/ruyi.git to ~/.ruyi (or update if exists)
4. Compile: cd ~/.ruyi && raco make evolve.rkt
5. Link: mkdir -p ~/.local/bin && ln -sf ~/.ruyi/ruyi ~/.local/bin/ruyi
6. Ensure ~/.local/bin is in my PATH (update .zshrc/.bashrc if needed)
7. Verify: run ruyi version

Handle any errors you encounter. If a download is slow, try alternative sources.

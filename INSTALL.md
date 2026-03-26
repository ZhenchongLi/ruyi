# Install Ruyi

Open Claude Code and paste:

```
Install ruyi for me. Run this command:

bash -c "$(curl -fsSL https://raw.githubusercontent.com/ZhenchongLi/ruyi/main/install.sh)"

If the script isn't available yet, do it manually:
1. Make sure git, gh, and racket are installed (brew install minimal-racket gh if needed)
2. git clone git@github.outlook:ZhenchongLi/ruyi.git ~/.ruyi
3. cd ~/.ruyi && raco make evolve.rkt
4. mkdir -p ~/.local/bin && ln -sf ~/.ruyi/ruyi ~/.local/bin/ruyi
5. Add ~/.local/bin to PATH if not already there

Then set up my current project:
6. cd back to my project directory
7. Run: ruyi init
```

That's it. Then use:

```bash
ruyi do "add CLI support"
```

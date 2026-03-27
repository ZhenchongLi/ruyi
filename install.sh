#!/usr/bin/env bash
set -euo pipefail

# Ruyi installer — designed to be run by Claude Code
# Usage: paste the prompt from INSTALL.md into Claude Code

RUYI_HOME="${RUYI_HOME:-$HOME/.ruyi}"
RUYI_REPO="https://github.com/ZhenchongLi/ruyi.git"
BIN_DIR="$HOME/.local/bin"

echo "=== Ruyi Installer ==="

# 1. Dependencies
missing=()
for cmd in git gh racket; do
  command -v "$cmd" &>/dev/null || missing+=("$cmd")
done

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing: ${missing[*]}"
  for cmd in "${missing[@]}"; do
    case "$cmd" in
      racket)
        if command -v brew &>/dev/null; then
          echo "Installing racket..."
          brew install minimal-racket
        elif command -v apt-get &>/dev/null; then
          echo "Installing racket..."
          sudo apt-get update && sudo apt-get install -y racket
        else
          echo "Error: Install racket manually — https://racket-lang.org/"
          exit 1
        fi
        ;;
      gh)
        if command -v brew &>/dev/null; then
          echo "Installing gh..."
          brew install gh
        elif command -v apt-get &>/dev/null; then
          echo "Installing gh..."
          (type -p wget >/dev/null || sudo apt-get install wget -y) \
            && sudo mkdir -p -m 755 /etc/apt/keyrings \
            && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
              | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
              | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
            && sudo apt-get update && sudo apt-get install gh -y
        else
          echo "Error: Install gh manually — https://cli.github.com/"
          exit 1
        fi
        ;;
      git)
        echo "Error: git is required. Install it first."
        exit 1
        ;;
    esac
  done
fi

echo "git:    $(git --version)"
echo "gh:     $(gh --version | head -1)"
echo "racket: $(racket --version 2>&1 | head -1)"

# 2. Clone or update
if [ -d "$RUYI_HOME/.git" ]; then
  echo "Updating existing installation..."
  git -C "$RUYI_HOME" pull --ff-only origin main
else
  [ -d "$RUYI_HOME" ] && { echo "Error: $RUYI_HOME exists but is not a git repo."; exit 1; }
  echo "Cloning ruyi to $RUYI_HOME..."
  git clone "$RUYI_REPO" "$RUYI_HOME"
fi

# 3. Compile
echo "Compiling..."
(cd "$RUYI_HOME" && raco make evolve.rkt 2>&1)

# 4. Install /ruyi command for Claude Code
CLAUDE_CMD_DIR="$HOME/.claude/commands"
mkdir -p "$CLAUDE_CMD_DIR"
cp "$RUYI_HOME/commands/ruyi.md" "$CLAUDE_CMD_DIR/ruyi.md"
echo "Installed /ruyi command for Claude Code"

# 5. Link to PATH
mkdir -p "$BIN_DIR"
chmod +x "$RUYI_HOME/ruyi"
ln -sf "$RUYI_HOME/ruyi" "$BIN_DIR/ruyi"

# 5. Ensure BIN_DIR in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  SHELL_RC=""
  case "$(basename "${SHELL:-/bin/bash}")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    bash) SHELL_RC="$HOME/.bashrc" ;;
  esac
  if [ -n "$SHELL_RC" ]; then
    sed -i'' -e '/alias ruyi=/d' "$SHELL_RC" 2>/dev/null || true
    grep -q 'local/bin' "$SHELL_RC" 2>/dev/null || \
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
    echo "Added ~/.local/bin to PATH in $SHELL_RC"
  fi
fi

echo ""
echo "=== Ruyi installed ==="
echo "Version: $(git -C "$RUYI_HOME" log -1 --format='%h %s')"
echo ""
echo "Usage:"
echo "  cd <your-project>"
echo "  ruyi init"
echo "  ruyi do \"your goal\""

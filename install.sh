#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Ruyi ==="

# Check for Racket, install if missing
if ! command -v racket &> /dev/null; then
  echo "Installing Racket..."
  if command -v brew &> /dev/null; then
    brew install minimal-racket
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y racket
  elif command -v dnf &> /dev/null; then
    sudo dnf install -y racket
  else
    echo "Error: Racket is required. Install it from https://racket-lang.org/"
    echo "  macOS:  brew install minimal-racket"
    echo "  Ubuntu: sudo apt-get install racket"
    echo "  Fedora: sudo dnf install racket"
    exit 1
  fi
else
  echo "Racket: found $(racket --version)"
fi

# Check for Claude Code
if ! command -v claude &> /dev/null; then
  echo "Warning: Claude Code CLI not found. Install it from https://claude.ai/code"
fi

# Clone or update
INSTALL_DIR="$HOME/ruyi"
if [ -d "$INSTALL_DIR" ]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "Cloning ruyi..."
  git clone https://github.com/ZhenchongLi/ruyi.git "$INSTALL_DIR"
fi

# Add alias to shell profile
SHELL_RC="$HOME/.zshrc"
if [ -n "${BASH_VERSION:-}" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

if ! grep -q 'alias ruyi=' "$SHELL_RC" 2>/dev/null; then
  echo 'alias ruyi="racket ~/ruyi/evolve.rkt"' >> "$SHELL_RC"
  echo "Added 'ruyi' alias to $SHELL_RC"
fi

echo ""
echo "=== Ruyi installed ==="
echo "Run: source $SHELL_RC && cd your-project && ruyi init"

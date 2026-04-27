#!/usr/bin/env bash
# install.sh — symlink remote-launcher into ~/.local/bin and ~/.claude/skills/

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
SKILLS_DIR="$HOME/.claude/skills/remote-launcher"

mkdir -p "$LOCAL_BIN"

ln -sf "$PROJECT_DIR/bin/remote-launcher"        "$LOCAL_BIN/remote-launcher"
ln -sf "$PROJECT_DIR/bin/remote-launcher-doctor" "$LOCAL_BIN/remote-launcher-doctor"

mkdir -p "$SKILLS_DIR"
ln -sf "$PROJECT_DIR/skill/SKILL.md" "$SKILLS_DIR/SKILL.md"

echo "[install] symlinks created:"
echo "    $LOCAL_BIN/remote-launcher"
echo "    $LOCAL_BIN/remote-launcher-doctor"
echo "    $SKILLS_DIR/SKILL.md"

case ":$PATH:" in
  *":$LOCAL_BIN:"*) echo "[install] $LOCAL_BIN already in PATH" ;;
  *) echo "[install] WARN: add this to ~/.zshrc:"
     echo '    export PATH="$HOME/.local/bin:$PATH"' ;;
esac

echo "[install] done. Run: remote-launcher-doctor"

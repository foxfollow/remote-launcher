#!/usr/bin/env bash
# uninstall.sh — remove symlinks installed by install.sh
set -euo pipefail

LOCAL_BIN="$HOME/.local/bin"
SKILLS_DIR="$HOME/.claude/skills/remote-launcher"

rm -f "$LOCAL_BIN/remote-launcher" "$LOCAL_BIN/remote-launcher-doctor"
rm -rf "$SKILLS_DIR"

echo "[uninstall] removed symlinks. Project files at $(cd "$(dirname "$0")" && pwd) untouched."

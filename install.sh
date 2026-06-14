#!/usr/bin/env bash
# Install the worktree-orchestrate workflow on this machine.
#
#   ./install.sh
#
# Symlinks the repo's pieces into the locations Claude Code + the helper expect:
#   bin/setup-worktree.sh      -> ~/.worktrees/setup-worktree.sh
#   config/*.sh                -> ~/.worktrees/config/*.sh
#   skills/orchestrate/        -> ~/.claude/skills/orchestrate/
#
# Symlinks (not copies) mean `git pull` in this repo updates your live tools.
# Pass --copy to copy instead (edit the originals in the repo, re-run to sync).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_HOME="${WORKTREE_HOME:-$HOME/.worktrees}"
SKILLS_HOME="${SKILLS_HOME:-$HOME/.claude/skills}"
MODE="symlink"
[ "${1:-}" = "--copy" ] && MODE="copy"

link() { # link <src> <dest>
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ "$MODE" = "copy" ]; then
    cp -R "$src" "$dest"
  else
    ln -sfn "$src" "$dest"
  fi
  echo "  $dest -> $src"
}

echo "Installing worktree-orchestrate ($MODE) from $REPO"

# 1. Helper script
link "$REPO/bin/setup-worktree.sh" "$WORKTREE_HOME/setup-worktree.sh"
chmod +x "$REPO/bin/setup-worktree.sh"

# 2. Per-project configs (one symlink per file so you can add your own later)
mkdir -p "$WORKTREE_HOME/config"
for cfg in "$REPO"/config/*.sh; do
  [ -e "$cfg" ] || continue
  link "$cfg" "$WORKTREE_HOME/config/$(basename "$cfg")"
done

# 3. The orchestrate skill
link "$REPO/skills/orchestrate" "$SKILLS_HOME/orchestrate"

echo
echo "Done. Sanity check:"
echo "  ls -la $WORKTREE_HOME/setup-worktree.sh"
echo "  ls -la $SKILLS_HOME/orchestrate"
echo
echo "Next: open Claude Code in your repo and try  /orchestrate  — see README.md."

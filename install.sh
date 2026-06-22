#!/usr/bin/env bash
# Install the worktree-orchestrate workflow on this machine.
#
#   ./install.sh
#
# Symlinks the repo's pieces into the locations Claude Code + the helper expect:
#   bin/setup-worktree.sh      -> ~/.worktrees/setup-worktree.sh
#   config/*.sh                -> ~/.worktrees/config/*.sh
#   skills/orchestrate/        -> ~/.claude/skills/orchestrate/  AND  ~/.agents/skills/orchestrate/
#
# Symlinks (not copies) mean `git pull` in this repo updates your live tools.
# Pass --copy to copy instead (edit the originals in the repo, re-run to sync).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_HOME="${WORKTREE_HOME:-$HOME/.worktrees}"
# Install the skill into every agent skills home: Claude Code and the generic
# ~/.agents convention. Add more here and they all stay in sync.
SKILL_HOMES=(
  "${CLAUDE_SKILLS_HOME:-$HOME/.claude/skills}"
  "${AGENTS_SKILLS_HOME:-$HOME/.agents/skills}"
)
MODE="symlink"
[ "${1:-}" = "--copy" ] && MODE="copy"

link() { # link <src> <dest>
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  # Clear whatever's already at dest first. A real file/dir left by a prior
  # `--copy` install (or a hand setup) would otherwise make `ln -sfn` nest the
  # new symlink *inside* the existing directory instead of replacing it — a
  # silent broken install. (Plain `if` so `set -e` doesn't trip on a no-op.)
  if [ -e "$dest" ] || [ -L "$dest" ]; then rm -rf "$dest"; fi
  if [ "$MODE" = "copy" ]; then
    cp -R "$src" "$dest"
  else
    ln -sfn "$src" "$dest"
  fi
  echo "  $dest -> $src"
}

echo "Installing worktree-orchestrate ($MODE) from $REPO"

# 1. Helper scripts
link "$REPO/bin/setup-worktree.sh" "$WORKTREE_HOME/setup-worktree.sh"
chmod +x "$REPO/bin/setup-worktree.sh"
link "$REPO/bin/remove-worktree.sh" "$WORKTREE_HOME/remove-worktree.sh"
chmod +x "$REPO/bin/remove-worktree.sh"

# 2. Per-project configs (one symlink per file so you can add your own later)
mkdir -p "$WORKTREE_HOME/config"
for cfg in "$REPO"/config/*.sh; do
  [ -e "$cfg" ] || continue
  link "$cfg" "$WORKTREE_HOME/config/$(basename "$cfg")"
done

# 3. The orchestrate skill — into every skill home
for home in "${SKILL_HOMES[@]}"; do
  link "$REPO/skills/orchestrate" "$home/orchestrate"
done

echo
echo "Done. Sanity check:"
echo "  ls -la $WORKTREE_HOME/setup-worktree.sh"
for home in "${SKILL_HOMES[@]}"; do
  echo "  ls -la $home/orchestrate"
done
echo
echo "Next: open Claude Code in your repo and try  /orchestrate  — see README.md."

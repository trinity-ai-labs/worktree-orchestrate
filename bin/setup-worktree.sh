#!/usr/bin/env bash
# Create an isolated git worktree for a task, in a central per-project home.
#
#   setup-worktree.sh <branch> <base>
#
# Run it from ANYWHERE inside the target repo — the repo root, a subdirectory, a
# monorepo subpackage, or even a linked worktree. It walks up to the repo's
# common gitdir, so it always resolves the right project. If cwd isn't inside a
# git repo, pass REPO=/path/to/repo.
#
# What it does, driven by per-project config at $WORKTREE_HOME/config/<project>.sh
# (WORKTREE_HOME defaults to ~/.worktrees):
#   - creates the worktree at  $WORKTREE_HOME/<project>/<branch-leaf>
#   - symlinks the project's gitignored env files (ENV_FILES)
#   - runs the project's install command (INSTALL_CMD) inside the worktree
#
# <branch>  full name of the new branch, e.g. feat/toasts-top-right (any prefix:
#           feat/ fix/ refactor/ chore/ docs/ …). The worktree dir is named after
#           the segment past the last slash.
# <base>    branch to fork from. REQUIRED, no default — integration branches roll
#           over often, so a hardcoded default just goes stale.
#
# A branch matching DOCS_BRANCH_PREFIX (from config) takes a fast path: env
# symlinks + install are skipped so the worktree comes up instantly.
#
# Per-project config is sourced as bash and may set: ENV_FILES (array),
# INSTALL_CMD, GATE_CMD, DOCS_BRANCH_PREFIX, DOCS_NOTE, BRIEF_CONVENTIONS.
# (GATE_CMD / BRIEF_CONVENTIONS aren't used here — they're read by the
# orchestrator.) No config → a bare worktree (no env symlinks, no install).
set -euo pipefail

WORKTREE_HOME="${WORKTREE_HOME:-$HOME/.worktrees}"
CONFIG_DIR="$WORKTREE_HOME/config"

if [ $# -lt 2 ]; then
  echo "usage: setup-worktree.sh <branch> <base>" >&2
  echo "  e.g. setup-worktree.sh feat/toasts-top-right release/0.3.4" >&2
  echo "  run from inside the target repo, or set REPO=/path/to/repo" >&2
  exit 1
fi

BRANCH="$1"
BASE="$2"
REPO="${REPO:-$PWD}"

# Resolve the MAIN working tree. The common gitdir's parent is the repo root,
# whether cwd is the root, a subdir, a monorepo package, or a linked worktree.
if ! COMMON=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  echo "not inside a git repo: $REPO" >&2
  echo "  run from inside the target repo, or set REPO=/path/to/repo" >&2
  exit 1
fi
MAIN=$(dirname "$COMMON")
PROJECT=$(basename "$MAIN")
SLUG="${BRANCH##*/}"
WT="$WORKTREE_HOME/$PROJECT/$SLUG"

# Per-project config (optional). Defaults first so `set -u` is safe if it's absent.
ENV_FILES=()
INSTALL_CMD=""
DOCS_BRANCH_PREFIX=""
DOCS_NOTE=""
CONFIG="$CONFIG_DIR/$PROJECT.sh"
if [ -f "$CONFIG" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG"
else
  echo "note: no config at $CONFIG — creating a bare worktree (no env symlinks, no install)." >&2
  echo "  add $CONFIG to declare ENV_FILES / INSTALL_CMD for '$PROJECT'." >&2
fi

# Docs fast path: a branch under DOCS_BRANCH_PREFIX skips env symlinks + install.
DOCS_MODE=0
if [ -n "$DOCS_BRANCH_PREFIX" ]; then
  case "$BRANCH" in "$DOCS_BRANCH_PREFIX"*) DOCS_MODE=1 ;; esac
fi

# Fail early with a fetch hint if base isn't a known local ref (a freshly-cut
# integration branch won't exist locally until you fetch it).
if ! git -C "$MAIN" rev-parse --verify --quiet "$BASE" >/dev/null; then
  echo "base branch not found locally: $BASE" >&2
  echo "  try: git -C \"$MAIN\" fetch origin   (or pass origin/$BASE)" >&2
  exit 1
fi

mkdir -p "$WORKTREE_HOME/$PROJECT"

if git -C "$MAIN" worktree list | grep -qF "$WT"; then
  echo "worktree already exists: $WT"
else
  git -C "$MAIN" worktree add -b "$BRANCH" "$WT" "$BASE"
fi

# Docs mode: skip env symlinks + the heavy install. Markdown checks (docs:check)
# are node:fs-only and need nothing, but formatting markdown still needs the
# formatter (prettier lives in node_modules). Symlinking the main checkout's
# node_modules is instant (no copy, no install) and lets the worktree resolve
# `node_modules/.bin/prettier` without a full install. Docs work only READS these
# deps, so sharing them is safe; never run `pnpm install` against this symlink.
if [ "$DOCS_MODE" -eq 1 ]; then
  LINKED_NM=0
  if [ -e "$MAIN/node_modules" ] && [ ! -e "$WT/node_modules" ]; then
    ln -sfn "$MAIN/node_modules" "$WT/node_modules"
    LINKED_NM=1
  fi
  echo "READY: $WT (branch $BRANCH off $BASE)"
  if [ "$LINKED_NM" -eq 1 ]; then
    echo "  docs mode: skipped env symlinks + install; symlinked node_modules so formatters run."
  else
    echo "  docs mode: skipped env symlinks + install."
  fi
  [ -n "$DOCS_NOTE" ] && echo "  $DOCS_NOTE"
  exit 0
fi

# Symlink the project's gitignored env files (tests/build read these). Guarded
# for bash 3.2, where expanding an empty array under `set -u` errors.
if [ "${#ENV_FILES[@]}" -gt 0 ]; then
  for rel in "${ENV_FILES[@]}"; do
    if [ -e "$MAIN/$rel" ]; then
      mkdir -p "$WT/$(dirname "$rel")"
      ln -sf "$MAIN/$rel" "$WT/$rel"
    fi
  done
fi

# Materialize node_modules / deps (worktrees don't share them; the gate needs them).
if [ -n "$INSTALL_CMD" ]; then
  # corepack-shimmed package managers (e.g. pnpm) provision the pinned version on
  # first use and, by default, block on a [Y/n] download prompt — which has nowhere
  # to go in this non-interactive install and hangs/fails the cold-cache run. Auto-
  # accept so the first worktree setup warms the cache instead of stalling. Harmless
  # when INSTALL_CMD doesn't go through corepack.
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  ( cd "$WT" && eval "$INSTALL_CMD" )
fi

echo "READY: $WT (branch $BRANCH off $BASE)"

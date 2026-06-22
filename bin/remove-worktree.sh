#!/usr/bin/env bash
# Safely tear down a git worktree — the deterministic inverse of setup-worktree.sh.
#
#   remove-worktree.sh <branch-leaf-or-path>
#
# Run it from ANYWHERE inside the target repo (or set REPO=). Given the branch
# leaf (the segment past the last slash, e.g. "1322-compose-env") or the full
# absolute worktree path, it:
#
#   1. Kills every process whose cwd or open files are rooted in the worktree
#      path — BEFORE removing the directory. This is the critical step: a plain
#      `git worktree remove` evicts the directory but does NOT signal any running
#      processes, so a wrap-up `pnpm gate` (the machine-wide-lock holder) that
#      was detached or backgrounded by the implementer agent survives as an
#      orphan, keeping the lock long after the branch is gone and starving the
#      next agent waiting in the queue. Killing first releases the lock cleanly.
#
#   2. Runs `git worktree remove <path> --force` + `git worktree prune` to
#      unregister the worktree from git.
#
# Safety invariants:
#   - Only kills processes rooted at the EXACT absolute worktree path (trailing
#     slash anchored), so a leaf named "1322-foo" cannot match "1322-foo-retry".
#   - Prints every candidate PID + command before killing; you can see exactly
#     what will be terminated.
#   - Escalates SIGTERM → SIGKILL with a brief pause so in-flight cleanup runs
#     where possible (node's process.on('exit') release path).
#   - Idempotent: if the path doesn't exist or no processes match, no-ops cleanly.
#   - Exits non-zero with a descriptive message on real failure.
#
# Caveats:
#   - Uses lsof to enumerate processes with open fds/cwd under the worktree.
#     lsof is available by default on macOS. On Linux, /proc/<pid>/fd + /proc/<pid>/cwd
#     could substitute; this script is macOS-first (matching the project's platform).
#   - Process detection is best-effort: a process that closed all fds pointing
#     into the worktree before removal would not be detected by lsof alone.
#     The lsof + argv scan (pkill) combination covers the common cases.
set -euo pipefail

WORKTREE_HOME="${WORKTREE_HOME:-$HOME/.worktrees}"
CONFIG_DIR="$WORKTREE_HOME/config"

die() { echo "remove-worktree: error: $*" >&2; exit 1; }

if [ $# -lt 1 ]; then
  echo "usage: remove-worktree.sh <branch-leaf-or-absolute-path>" >&2
  echo "  e.g. remove-worktree.sh 1322-compose-env" >&2
  echo "  e.g. remove-worktree.sh /Users/you/.worktrees/my-project/1322-compose-env" >&2
  echo "  run from inside the target repo, or set REPO=/path/to/repo" >&2
  exit 1
fi

INPUT="$1"
REPO="${REPO:-$PWD}"

# --- Resolve the worktree path -------------------------------------------------
# If the input looks like an absolute path, trust it directly; otherwise treat
# it as a branch leaf and resolve it via the repo the caller is standing in.
if [[ "$INPUT" == /* ]]; then
  WT="$INPUT"
else
  # Resolve the MAIN working tree — same logic as setup-worktree.sh.
  if ! COMMON=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    die "not inside a git repo: $REPO\n  run from inside the target repo, or set REPO=/path/to/repo"
  fi
  MAIN=$(dirname "$COMMON")
  PROJECT=$(basename "$MAIN")
  # setup-worktree.sh names the dir after the segment past the LAST slash
  # (e.g. `feat/1319-foo` → `1319-foo`), so derive the leaf the same way —
  # otherwise a full branch name resolves to a non-existent nested path.
  LEAF="${INPUT##*/}"
  WT="$WORKTREE_HOME/$PROJECT/$LEAF"
fi

# Normalise to absolute (strip trailing slashes etc.)
WT="${WT%/}"

echo "remove-worktree: target path: $WT"

# --- Idempotent path-exists check ----------------------------------------------
if [ ! -d "$WT" ]; then
  echo "remove-worktree: path does not exist or already removed: $WT"
  echo "  running git worktree prune to clean stale refs..."
  # Still need to know which repo to prune. If we resolved from REPO above,
  # COMMON/MAIN are already set; otherwise derive from the nearest repo.
  if [[ "$INPUT" == /* ]]; then
    if COMMON=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      MAIN=$(dirname "$COMMON")
    else
      echo "remove-worktree: cannot find repo for $WT — skipping prune" >&2
      exit 0
    fi
  fi
  git -C "$MAIN" worktree prune
  echo "remove-worktree: done (path was already absent)."
  exit 0
fi

# --- Derive MAIN if we took the absolute-path branch ---------------------------
# We need MAIN for git worktree remove. The worktree itself is a git repo
# (its .git is a gitfile pointing back), so we can find COMMON from it.
if [[ "$INPUT" == /* ]]; then
  if ! COMMON=$(git -C "$WT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
    # Worktree exists but git can't see it (already unregistered?). Force-rm and exit.
    echo "remove-worktree: worktree dir exists but is not a git repo; removing directory only."
    rm -rf "$WT"
    exit 0
  fi
  MAIN=$(dirname "$COMMON")
fi

# --- Kill processes rooted in the worktree FIRST --------------------------------
# Anchor on the exact path + a trailing slash so:
#   /path/to/1322-compose-env/   matches everything inside
#   /path/to/1322-compose-env    matches exactly the dir itself (lsof cwd)
#   /path/to/1322-compose-env-2/ does NOT match (different leaf)
WT_PREFIX="${WT}/"  # trailing slash anchor for substring matches

echo "remove-worktree: scanning for processes using $WT ..."

# Collect PIDs via two complementary methods:
#   A) lsof: processes with open file descriptors or cwd pointing into the tree.
#   B) pgrep on the argv: catches processes that cd'd in and closed their fds
#      (e.g. a shell that eval'd a command and closed the script fd).
# Both methods are filtered to PIDs whose path starts with the exact WT_PREFIX
# (or equals WT for cwd). We deduplicate the union.

PIDS=()

# Method A: lsof (macOS). -w suppresses warnings, +D recurses the directory.
# Filter to paths that start with WT (exact dir) or WT_PREFIX (inside the dir).
if command -v lsof >/dev/null 2>&1; then
  # +D is expensive on large node_modules trees; we pipe through awk to filter
  # for safety, matching the exact WT path or anything under it.
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && PIDS+=("$pid")
  done < <(
    lsof -w +D "$WT" 2>/dev/null \
      | awk -v wt="$WT" -v pfx="${WT_PREFIX}" '
          NR>1 {
            # Column 2 is the PID; column 9 is the NAME (path).
            pid=$2; path=$NF
            if (path == wt || index(path, pfx) == 1) print pid
          }
        ' \
      | sort -u
  )
fi

# Method B: pgrep on the exact path string in the command line.
# Anchor to the WT_PREFIX so "1322-foo" cannot match "1322-foo-retry".
# pgrep -f matches the full argv string.
if command -v pgrep >/dev/null 2>&1; then
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && PIDS+=("$pid")
  done < <(
    pgrep -f "${WT_PREFIX}" 2>/dev/null || true
  )
fi

# Deduplicate and exclude self (this script's own PID)
SELF=$$
UNIQUE_PIDS=()
# macOS ships bash 3.2, which has no associative arrays — dedup the PID list by
# piping through `sort -un` and dropping our own PID, instead of a SEEN map.
# (Also guard the empty case: "${PIDS[@]}" under `set -u` is an error on 3.2.)
if [ "${#PIDS[@]}" -gt 0 ]; then
  while IFS= read -r pid; do
    [ -n "$pid" ] && UNIQUE_PIDS+=("$pid")
  done < <(printf '%s\n' "${PIDS[@]}" | grep -vx "$SELF" | sort -un)
fi

if [ "${#UNIQUE_PIDS[@]}" -eq 0 ]; then
  echo "remove-worktree: no running processes found in $WT"
else
  echo "remove-worktree: found ${#UNIQUE_PIDS[@]} process(es) to terminate:"
  for pid in "${UNIQUE_PIDS[@]}"; do
    # Print PID + command for transparency
    cmd=$(ps -p "$pid" -o pid=,args= 2>/dev/null || echo "$pid  <already exited>")
    echo "  $cmd"
  done

  # SIGTERM first — gives node's process.on('exit') release() a chance to run,
  # which removes the lock directory cleanly rather than leaving a stale lockfile.
  echo "remove-worktree: sending SIGTERM ..."
  for pid in "${UNIQUE_PIDS[@]}"; do
    kill -TERM "$pid" 2>/dev/null || true
  done

  # Brief pause — enough for a clean SIGTERM handler to run and the lock dir to
  # be removed, but short enough to not stall the orchestrator.
  sleep 2

  # SIGKILL any survivors. A SIGKILL'd node lock-holder will leave the lockdir
  # behind, but with-test-lock.mjs's dead-holder detection (holderIsDead) will
  # detect the stale PID on the next poll and steal the lock automatically —
  # so no manual lock cleanup is required even in the SIGKILL path.
  SURVIVORS=()
  for pid in "${UNIQUE_PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null && SURVIVORS+=("$pid") || true
  done

  if [ "${#SURVIVORS[@]}" -gt 0 ]; then
    echo "remove-worktree: ${#SURVIVORS[@]} process(es) survived SIGTERM; sending SIGKILL ..."
    for pid in "${SURVIVORS[@]}"; do
      kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 1
  else
    echo "remove-worktree: all processes exited cleanly after SIGTERM."
  fi
fi

# --- Remove the worktree -------------------------------------------------------
echo "remove-worktree: removing worktree $WT ..."
git -C "$MAIN" worktree remove "$WT" --force
git -C "$MAIN" worktree prune
echo "remove-worktree: done — $WT removed."

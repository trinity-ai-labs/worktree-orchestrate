#!/usr/bin/env bash
# Merge a reviewed PR and clean up — the atomic close-out of the worktree flow.
#
#   merge-pr.sh <pr-number>
#
# Run it from ANYWHERE inside the target repo (or set REPO=). It performs the
# whole "Merge & cleanup" sequence as ONE command, in the one correct order, so
# no load-bearing step can be dropped:
#
#   1. Resolve the MAIN checkout + the PR's base (integration) and head branch.
#   2. Remove the head branch's worktree FIRST — git refuses to delete a branch
#      that's still checked out in a worktree, so `gh pr merge --delete-branch`
#      would error on the local-branch step if the worktree still existed. Done
#      via remove-worktree.sh, which kills processes rooted in the tree first.
#   3. `gh pr merge --merge --delete-branch` — a real merge commit (never squash),
#      deleting both the local and remote branch.
#   4. Sync the MAIN checkout's local integration branch to the just-merged tip.
#
# Step 4 is the whole reason this helper exists. `gh pr merge` advances the branch
# on the REMOTE; the local integration branch in the main checkout does NOT move.
# Syncing it is a manual step with NO forcing feedback — every visible signal
# (`✓ Merged`, branch deleted, PR closed) says "done", so it's the step that gets
# silently skipped, and the miss only surfaces later when the NEXT worktree is cut
# from a stale HEAD. Worse, hand-run as `git checkout <integration> && git pull`
# from inside a worktree, the checkout fails ("already used by worktree at …") and
# `&&` swallows the pull — so the sync silently never happens. This helper anchors
# every git call to the MAIN checkout with `git -C "$MAIN"`, independent of cwd,
# and fast-forwards only (the main checkout never carries direct commits, so a
# non-ff means something is wrong and should surface loudly, not merge-commit past).
#
# Idempotent: if the PR is already merged, it skips the merge and still runs the
# worktree teardown + local sync, so a re-run finishes a half-done close-out.
set -euo pipefail

WORKTREE_HOME="${WORKTREE_HOME:-$HOME/.worktrees}"

die() { echo "merge-pr: error: $*" >&2; exit 1; }

if [ $# -lt 1 ]; then
  echo "usage: merge-pr.sh <pr-number>" >&2
  echo "  e.g. merge-pr.sh 2094" >&2
  echo "  run from inside the target repo, or set REPO=/path/to/repo" >&2
  exit 1
fi

PR="$1"
REPO="${REPO:-$PWD}"

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) not found on PATH"

# Resolve the MAIN working tree — same logic as setup-worktree.sh / remove-worktree.sh.
if ! COMMON=$(git -C "$REPO" rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  die "not inside a git repo: $REPO\n  run from inside the target repo, or set REPO=/path/to/repo"
fi
MAIN=$(dirname "$COMMON")

# gh resolves the repo from cwd, so run every gh call from the MAIN checkout.
pr_field() { ( cd "$MAIN" && gh pr view "$PR" --json "$1" -q ".$1" ); }

STATE=$(pr_field state) || die "could not read PR #$PR (is the number right? is gh authed?)"
INTEGRATION=$(pr_field baseRefName)
HEAD_BRANCH=$(pr_field headRefName)
[ -n "$INTEGRATION" ] || die "PR #$PR has no base branch"

echo "merge-pr: PR #$PR  state=$STATE  base=$INTEGRATION  head=$HEAD_BRANCH  main=$MAIN"

# --- 0. Wrong-repo guard ---------------------------------------------------------
# The repo is resolved from cwd/REPO, so a shell sitting in a DIFFERENT repo's
# checkout makes every step below operate on that repo — same-numbered PRs exist
# everywhere, so the gh calls above still "succeed" and nothing else would catch
# it. Verify PR #$PR actually belongs to this working set before touching anything.
LEAF="${HEAD_BRANCH##*/}"
PROJECT=$(basename "$MAIN")
if [ "$STATE" = "MERGED" ]; then
  # Idempotent-rerun case: finishing a half-done close-out implies SOME local
  # residue — the worktree or the local head branch. Neither existing means
  # there is nothing to close out here: almost certainly the wrong repo.
  if [ ! -d "$WORKTREE_HOME/$PROJECT/$LEAF" ] \
     && ! git -C "$MAIN" show-ref --verify --quiet "refs/heads/$HEAD_BRANCH" \
     && [ "${MERGE_PR_FORCE:-}" != "1" ]; then
    die "PR #$PR is already MERGED and neither a worktree ($WORKTREE_HOME/$PROJECT/$LEAF) nor a local branch '$HEAD_BRANCH' exists in $MAIN — nothing to close out here. WRONG REPO? cd into the intended repo and re-run (or MERGE_PR_FORCE=1 to run teardown+sync here anyway)."
  fi
else
  git -C "$MAIN" show-ref --verify --quiet "refs/heads/$HEAD_BRANCH" \
    || git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/$HEAD_BRANCH" \
    || { git -C "$MAIN" fetch --prune origin >/dev/null 2>&1 && git -C "$MAIN" show-ref --verify --quiet "refs/remotes/origin/$HEAD_BRANCH"; } \
    || die "PR #$PR's head branch '$HEAD_BRANCH' is unknown in $MAIN (not local, not on origin) — WRONG REPO? The repo is resolved from cwd/REPO; cd into the intended repo and re-run."
fi

# --- 1. Remove the head branch's worktree FIRST --------------------------------
# So `--delete-branch` can remove the local branch. remove-worktree.sh is
# idempotent (no-ops if the worktree is already gone) and derives the worktree
# path from the branch leaf against this same repo.
if [ -n "$HEAD_BRANCH" ]; then
  echo "merge-pr: tearing down worktree for $HEAD_BRANCH ..."
  REPO="$MAIN" "$WORKTREE_HOME/remove-worktree.sh" "$HEAD_BRANCH"
fi

# --- 2. Merge (unless already merged) ------------------------------------------
if [ "$STATE" = "MERGED" ]; then
  echo "merge-pr: PR #$PR already merged — skipping merge, finishing the local sync."
else
  echo "merge-pr: merging PR #$PR (real merge commit, deleting branch) ..."
  ( cd "$MAIN" && gh pr merge "$PR" --merge --delete-branch )
fi

# --- 3. Sync the local integration branch in the MAIN checkout ------------------
# Anchored to MAIN so it works regardless of the caller's cwd. Fast-forward only:
# the main checkout never carries direct commits (all work lands via PR merge on
# the remote), so a non-ff pull means an anomaly that should stop us loudly.
CUR=$(git -C "$MAIN" rev-parse --abbrev-ref HEAD)
if [ "$CUR" != "$INTEGRATION" ]; then
  echo "merge-pr: main checkout is on '$CUR'; switching to '$INTEGRATION' ..."
  git -C "$MAIN" checkout "$INTEGRATION"
fi

# `gh pr merge` returns before GitHub is guaranteed to serve the new tip, so a pull
# fired immediately can fast-forward to nothing ("Already up to date") and silently
# leave the branch on the PRE-merge commit — while a `rev-parse HEAD` in the done-
# message still prints a sha and reads as "synced." That is the "said synced, wasn't"
# bug. So: poll-fetch until the remote actually carries the merge commit, fast-forward
# each round, and VERIFY the local branch truly reached the merged tip. The message is
# never proof; the ref-equality check below is — and on failure we die loudly, never lie.
MERGE_OID=$( cd "$MAIN" && gh pr view "$PR" --json mergeCommit -q '.mergeCommit.oid' 2>/dev/null || true )
echo "merge-pr: syncing local '$INTEGRATION' to the merged tip ..."
synced=""
for attempt in 1 2 3 4 5 6; do
  git -C "$MAIN" fetch --prune origin >/dev/null 2>&1 || true
  git -C "$MAIN" merge --ff-only "origin/$INTEGRATION" >/dev/null 2>&1 || true
  LOCAL=$(git -C "$MAIN" rev-parse "$INTEGRATION")
  REMOTE=$(git -C "$MAIN" rev-parse "origin/$INTEGRATION")
  if [ "$LOCAL" = "$REMOTE" ] && { [ -z "$MERGE_OID" ] || \
       git -C "$MAIN" merge-base --is-ancestor "$MERGE_OID" "$INTEGRATION" 2>/dev/null; }; then
    synced=1
    break
  fi
  echo "merge-pr: remote not serving the merge yet (attempt $attempt/6) — waiting ..."
  sleep 2
done
[ -n "$synced" ] || die "local '$INTEGRATION' did NOT reach the merged tip (merge commit ${MERGE_OID:-unknown} still absent after retries) — SYNC FAILED; do NOT cut new worktrees off '$INTEGRATION' until this is resolved."

echo "merge-pr: done — PR #$PR merged, worktree removed, local '$INTEGRATION' synced to $(git -C "$MAIN" rev-parse --short "$INTEGRATION")."

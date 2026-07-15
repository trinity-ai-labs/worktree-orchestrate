# Per-project worktree config — TEMPLATE.
#
# Copy this to  ~/.worktrees/config/<project>.sh  where <project> is the repo's
# DIRECTORY NAME (e.g. a repo cloned at ~/Code/foo-bar needs foo-bar.sh).
# The helper (setup-worktree.sh) auto-detects the project from cwd and sources
# the matching file. The /orchestrate skill reads GATE_CMD + BRIEF_CONVENTIONS
# from it too. A repo with no config still works — it just gets a bare worktree
# (no env symlinks, no install).
#
# Every key is OPTIONAL. Delete what you don't need.

# Gitignored env files to symlink from the main checkout into each worktree
# (paths relative to the repo root). Only ones that exist are linked. Worktrees
# don't inherit gitignored files, so tests/builds that read .env need these.
ENV_FILES=(
  "apps/web/.env.local"
  ".env"
)

# Install command, run inside each new worktree. Worktrees don't share
# node_modules / vendor dirs, so deps must be materialized per worktree.
INSTALL_CMD="pnpm install --frozen-lockfile"   # or: npm ci / yarn / bun install / cargo build / ...

# Optional: a monorepo shared build cache (turbo / nx / bazel). Export a machine-local cache
# dir so a fresh worktree's gate replays what another checkout already built instead of running
# cold. The config is sourced bash, so this export reaches the install step.
# ⚠️ CRITICAL: also put the SAME export in ~/.zshenv (NOT ~/.zshrc). The gate runner, the drain,
# and dispatched implementer agents run in NON-interactive shells — those read ~/.zshenv only.
# A cache var set solely in ~/.zshrc reaches your interactive terminal but NOT the fleet, so the
# shared cache silently never applies to gated PRs (every drain runs cold). Delete if unused.
# export TURBO_CACHE_DIR="${TURBO_CACHE_DIR:-$HOME/.cache/<project>-turbo}"

# The green gate an implementer runs before opening a PR (typecheck + tests +
# lint, whatever "ready to review" means here). The orchestrator re-runs it only
# as a backstop, not on every PR.
GATE_CMD="pnpm check && pnpm test"

# Conventions baked into every dispatched implementer brief (read by the
# orchestrator). Put framework rules, compat policy, comment style, and the
# simplify-then-gate ritual here so every sub-agent follows house style.
BRIEF_CONVENTIONS="Match surrounding style. As the last step before committing, run /simplify over the changes, then run the gate to green. Never rebase, never self-merge."

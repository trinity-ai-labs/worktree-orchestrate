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

# The green gate an implementer runs before opening a PR (typecheck + tests +
# lint, whatever "ready to review" means here). The orchestrator re-runs it only
# as a backstop, not on every PR.
GATE_CMD="pnpm check && pnpm test"

# Branches under this prefix take a FAST PATH: env symlinks + install are
# skipped, so deps-free work (markdown, config) comes up instantly. Optional.
DOCS_BRANCH_PREFIX="docs/"
DOCS_NOTE="run install by hand if a docs branch happens to touch code."

# Conventions baked into every dispatched implementer brief (read by the
# orchestrator). Put framework rules, compat policy, comment style, and the
# simplify-then-gate ritual here so every sub-agent follows house style.
BRIEF_CONVENTIONS="Match surrounding style. As the last step before committing, run /simplify over the changes, then run the gate to green. Never rebase, never self-merge."

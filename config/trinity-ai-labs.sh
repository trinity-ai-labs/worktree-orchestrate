# Per-project worktree config for trinity-ai-labs.
# Sourced as bash by ~/.worktrees/setup-worktree.sh, and read by the orchestrator
# (the /orchestrate skill) for GATE_CMD + BRIEF_CONVENTIONS to bake into briefs.

# Gitignored env files to symlink from the main checkout into each worktree
# (paths relative to the repo root). Only ones that exist are linked.
ENV_FILES=(
  "trinity/.env.local"
  "trinityailabs.com/.env.local"
  "trinityailabs.com/.env.dev"
  "trinityailabs.com/.env.prod"
  "cf/.dev.vars"
)

# Install command, run inside the new worktree (worktrees don't share node_modules).
INSTALL_CMD="pnpm install --frozen-lockfile"

# The gate an implementer runs to green before opening a PR (orchestrator's backstop).
GATE_CMD="pnpm check && pnpm test"

# Branches under this prefix skip env symlinks + install: markdown + `pnpm docs:check`
# are node:fs only, so the worktree comes up instantly.
DOCS_BRANCH_PREFIX="docs/"
DOCS_NOTE="run 'pnpm install' by hand if the docs change touches TypeScript (e.g. registering a chapter in trinityailabs.com/lib/content/docs-structure.ts)."

# Conventions to bake into every dispatched implementer brief (read by the orchestrator).
BRIEF_CONVENTIONS="Use the 'effect' skill for any Effect-TS code (idiomatic services/layers/error-handling). Pre-launch, no backwards-compat: no users yet and the DB gets nuked, so build forward-only — never add migration/backfill/compat shims. Code comments explain the mechanism — no issue/PR/version/plan refs. As the last step before committing, run the /simplify skill over the changes, then run the gate (pnpm check && pnpm test) to green."

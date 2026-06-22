# Per-project worktree config for trinity-ai-labs.
# Sourced as bash by ~/.worktrees/setup-worktree.sh, and read by the orchestrator
# (the /orchestrate skill) for GATE_CMD + BRIEF_CONVENTIONS to bake into briefs.

# Gitignored env files to symlink from the main checkout into each worktree
# (paths relative to the repo root). Only ones that exist are linked.
ENV_FILES=(
  "trinity/.env.local"
  "trinityailabs.com/.env.local"
  "cf/.dev.vars"
)

# Install command, run inside the new worktree (worktrees don't share node_modules).
INSTALL_CMD="pnpm install --frozen-lockfile"

# HEAVY gate — typecheck + build + lint + FULL test suite, behind a machine-wide lock.
# The lock exists because running this concurrently saturates the box (parallel vite builds
# + vitest forks). This is the implementer's single wrap-up signal before opening a PR.
# The orchestrator must NOT pile extra GATE_CMD runs on top of a running fleet — that's the
# exact saturation the lock is there to prevent. Backstop re-gates (agent died / branches
# not tested together) must wait until the fleet is QUIET (≤1 agent active), and even then
# prefer running only the affected test files rather than the full suite.
#
# TRANSIENT-RED EPICS (e.g. schema-first / all-or-nothing migrations): when the full gate
# is unattainably red mid-epic by design, implementers verify with:
#   pnpm check   (typecheck + build + lint) — must be GREEN
#   + the task's OWN new/affected test files — must be GREEN
#   + no new failures vs. the captured baseline set (file + test names, not just a count)
# The full pnpm gate is reserved for quiet-branch checkpoints and epic-completion sign-off.
GATE_CMD="pnpm gate"

# Branches under this prefix skip env symlinks + install: markdown + `pnpm docs:check`
# are node:fs only, so the worktree comes up instantly.
DOCS_BRANCH_PREFIX="docs/"
DOCS_NOTE="run 'pnpm install' by hand if the docs change touches TypeScript (e.g. registering a chapter in trinityailabs.com/lib/content/docs-structure.ts)."

# Conventions to bake into every dispatched implementer brief (read by the orchestrator).
BRIEF_CONVENTIONS="Use the 'effect' skill for any Effect-TS code (idiomatic services/layers/error-handling). Pre-launch, no backwards-compat: no users yet and the DB gets nuked, so build forward-only — never add migration/backfill/compat shims. Code comments explain the mechanism — no issue/PR/version/plan refs. As the last step before committing, run the /simplify skill over the changes, then run the gate. The gate (pnpm gate) is HEAVY — the full typecheck/build/lint/test suite behind a machine-wide lock — so run it ONCE as your wrap-up signal, not repeatedly. If the orchestrator has told you this is a transient-red epic (foundational change landed first, full-green gate unattainable mid-epic by design), verify instead with: pnpm check GREEN + your own/affected test files GREEN + no new failures vs. the baseline set (file+test names, not just a count). The full gate is reserved for quiet-branch checkpoints and epic-completion sign-off."

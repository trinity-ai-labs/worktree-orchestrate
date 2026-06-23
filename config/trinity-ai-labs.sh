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

# GATE_CMD is the LOCKED gate: `pnpm gate` wraps `format && check && test` in a machine-wide
# lock (scripts/with-test-lock.mjs). `check` here is lint + typecheck (tsc --noEmit) — NOT an
# app build; `build` (turbo build → .next) is a SEPARATE task neither check nor gate invokes,
# so agents never build the app. The lock exists because heavy concurrent runs (monorepo tsc +
# vitest forks) saturate the box.
# CRUCIAL: a bare `pnpm check` / `typecheck` / `build` runs OUTSIDE the lock — only `gate` and
# `test` take it — so launching those standalone in parallel across worktrees is the exact
# saturation the lock prevents. A bare `check` is heavy (monorepo tsc) AND unlocked; it is NOT
# the "light" option it looks like. The implementer's single wrap-up signal is the LOCKED
# `pnpm gate`, never a bare check.
# The orchestrator must NOT pile extra GATE_CMD runs on top of a running fleet (same saturation).
# Backstop re-gates (agent died / branches not tested together) wait until the fleet is QUIET
# (≤1 agent); only when quiet may you run a targeted subset.
#
# TRANSIENT-RED EPICS (schema-first / all-or-nothing migrations): the full gate is unattainably
# red mid-epic BY DESIGN. Implementers STILL run the locked `pnpm gate` — what changes is how you
# READ it: compile half (typecheck + lint) GREEN + own/affected tests GREEN + no failures beyond
# the fork-point baseline SET (file + test names, not a count; the absolute count drifts per fork
# and as consumers migrate). A fully GREEN gate is reserved for quiet-branch checkpoints and the
# epic-completion sign-off.
GATE_CMD="pnpm gate"

# Branches under this prefix skip env symlinks + install: markdown + `pnpm docs:check`
# are node:fs only, so the worktree comes up instantly.
DOCS_BRANCH_PREFIX="docs/"
DOCS_NOTE="run 'pnpm install' by hand if the docs change touches TypeScript (e.g. registering a chapter in trinityailabs.com/lib/content/docs-structure.ts)."

# Conventions to bake into every dispatched implementer brief (read by the orchestrator).
BRIEF_CONVENTIONS="Use the 'effect' skill for any Effect-TS code (idiomatic services/layers/error-handling). Pre-launch, no backwards-compat: no users yet and the DB gets nuked, so build forward-only — never add migration/backfill/compat shims. Code comments explain the mechanism — no issue/PR/version/plan refs. As the last step before committing, run the /simplify skill over the changes, then run the LOCKED gate 'pnpm gate' ONCE as your wrap-up signal — in the FOREGROUND; wait for it to exit. Don't background/detach it: an orphaned gate keeps holding the machine-wide lock and starves the next agent. Don't loop or poll-retry it. If it sits there producing no output it is almost certainly QUEUED behind another worktree's gate waiting for the lock, NOT hung — let it wait its turn; don't kill it and don't launch a second one. NEVER substitute a bare 'pnpm check'/'typecheck'/'build': those run OUTSIDE the machine-wide lock (only 'gate' and 'test' take it), so a bare check is heavy monorepo tsc AND unlocked — running it standalone saturates the box. If the orchestrator has told you this is a transient-red epic (foundational change landed first, full-green gate unattainable mid-epic by design), STILL run 'pnpm gate' — just read its output as: compile half (typecheck+lint) GREEN + your own/affected tests GREEN + no failures beyond the fork-point baseline set (file+test names, not a count); don't chase a green exit, don't loop. A fully green gate is reserved for quiet-branch checkpoints and epic-completion sign-off."

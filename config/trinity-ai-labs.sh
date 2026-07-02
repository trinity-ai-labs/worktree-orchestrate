# Per-project worktree config for trinity-ai-labs.
# Sourced as bash by ~/.worktrees/setup-worktree.sh, and read by the orchestrator
# (the /orchestrate skill) for the gate/check/queue commands + BRIEF_CONVENTIONS.

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

# Shared turbo cache — machine-local, so a fresh worktree's gate REPLAYS tasks another
# checkout already built (near-instant on unchanged packages) instead of recomputing cold.
# This export (config is sourced bash) covers the INSTALL step. ⚠️ The GATE runner + drain +
# dispatched agents run in NON-interactive shells, which read ~/.zshenv, NOT ~/.zshrc — so the
# SAME line must also live in ~/.zshenv or the shared cache silently never reaches gated PRs.
export TURBO_CACHE_DIR="${TURBO_CACHE_DIR:-$HOME/.cache/trinity-turbo}"

# GATE_CMD is the HEAVY full gate: `pnpm gate` = `format && check && test`, serialized behind a
# slim machine-wide slot (scripts/gate-slot.mjs) so only one gate runs at a time on the box. This
# is what the RUNNER runs against a queued PR's worktree when it drains the queue — implementers do
# NOT run it (they enqueue it; see BRIEF_CONVENTIONS). `check` is format:check + lint + typecheck;
# `build` (turbo build → .next) is a SEPARATE task the gate never invokes, so gating never builds
# the app. The slot exists because concurrent full runs (monorepo tsc + vitest/workerd forks)
# saturate the box; the runner gates one-at-a-time, and multiple orchestrators may drain safely.
GATE_CMD="pnpm gate"

# SCOPED_CHECK_CMD is the cheap, unlocked bar an implementer's commits are held to: `pnpm check` =
# format:check + lint + typecheck (oxlint is fast; typecheck is turbo-cached) — NO build, NO test
# suite, NO slot. The agentic pre-commit hook (.agents/hooks/pre-commit.mjs) already enforces it on
# every agent `git commit`, so a commit that fails it is denied. This is the ENTIRE quality bar an
# implementer personally clears; the full build+test gate runs later in the runner.
SCOPED_CHECK_CMD="pnpm check"

# How an implementer enqueues its PR for gating, and how the orchestrator drains the queue. Both
# live at the monorepo ROOT (like `pnpm gate`). ENQUEUE_CMD drops a durable on-disk ticket after the
# implementer opens its draft PR; DRAIN_CMD is a one-shot pass the orchestrator runs each tick to
# gate queued PRs one-at-a-time and flip them ready (green) / comment the failure (red).
ENQUEUE_CMD="pnpm gate:enqueue"   # --branch <b> --worktree <absPath> --pr-number <n> --pr-url <url>
DRAIN_CMD="pnpm gate:drain"       # [--max <n>]

# Branches under this prefix skip env symlinks + install: markdown + `pnpm docs:check`
# are node:fs only, so the worktree comes up instantly.
DOCS_BRANCH_PREFIX="docs/"
DOCS_NOTE="run 'pnpm install' by hand if the docs change touches TypeScript (e.g. registering a chapter in trinityailabs.com/lib/content/docs-structure.ts)."

# Conventions to bake into every dispatched implementer brief (read by the orchestrator).
BRIEF_CONVENTIONS="Trinity splits in two — app = Solid, sidecar = Effect. Invoke the 'effect' skill (as Step 0) for any Effect-TS code on the SIDECAR (idiomatic services/layers/error-handling), and invoke the 'solid' skill (as Step 0) for any SolidJS UI code on the APP (solid-js components/signals/stores, @solidjs/router, @tanstack/solid-query for server data, Kobalte — this is Trinity's frontend); a full-stack slice that spans both invokes both. Pre-launch, no backwards-compat: no users yet and the DB gets nuked, so build forward-only — never add migration/backfill/compat shims. Code comments explain the mechanism — no issue/PR/version/plan refs. YOU DO NOT RUN THE FULL GATE. The heavy build+test 'pnpm gate' runs later in a runner, drained from the queue by the orchestrator — not by you. Your wrap-up is: write the whole change uncommitted, run /simplify over the full diff, THEN commit in logical blocks, push, open a DRAFT PR, and enqueue the gate — then hand back without waiting. Your commits are held only to the cheap SCOPED check 'pnpm check' (format:check + lint + typecheck — no build, no test suite), which the agentic pre-commit hook enforces on every commit; run 'pnpm format' before committing so the format:check passes (a commit that fails the scoped check is denied — fix and re-commit). To enqueue after opening your draft PR: 'pnpm gate:enqueue --branch <yourBranch> --worktree <yourWorktreeAbsPath> --pr-number <n> --pr-url <url>' (get the number/url from the 'gh pr create --draft' output). Do NOT run 'pnpm gate', do NOT wait for a gate, do NOT mark your own PR ready — the runner gates it and flips it ready (green) or comments the failure and leaves it draft (red). 'pnpm check' and 'pnpm gate:enqueue' live at the monorepo ROOT: from a subpackage (trinity/, cf/, trinityailabs.com/, shared/) they report 'no such script' — that means WRONG DIRECTORY, cd up to the worktree root; it is never licence to improvise. RUN TESTS THROUGH TURBO so the shared local + R2 remote cache applies: for a whole package use 'pnpm exec turbo run test --filter=<pkg>' from the repo root (NOT 'pnpm --filter <pkg> test' — that package 'test' script is a bare 'vitest run' and bypasses turbo, so it always runs cold and never populates the cache); same for typecheck/lint via 'pnpm check' (already turbo). A SINGLE file is fine run direct and uncached: 'pnpm --filter <pkg> exec vitest run path/to/x.test.ts'. Never reach for bare 'vitest'/'tsc'/'eslint' or 'pnpm --filter <pkg> test' for a whole-package run. OVERRIDE MODE ONLY: if the orchestrator's brief explicitly says to run the full gate yourself (a foundational/cross-cutting slice, or no orchestrator is draining), then after committing+pushing run 'pnpm gate' ONCE in the FOREGROUND from the worktree root with the FULL 10-minute (600000ms) Bash timeout, flip your own PR ready on green, and do NOT enqueue. 'pnpm gate' auto-formats first (prettier --write); if it leaves formatting changes, commit them as part of your change — pure prettier writes can't break a check/test that already passed, so don't re-run it just to re-verify formatting. If told this is a transient-red epic (foundational change landed first, full-green gate unattainable mid-epic by design), read the gate as: compile half (typecheck+lint) GREEN + your own/affected tests GREEN + no failures beyond the fork-point baseline set (file+test names, not a count); don't chase a green exit, don't loop."

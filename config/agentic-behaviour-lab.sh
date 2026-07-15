# Per-project worktree config for agentic-behaviour-lab.
# Sourced as bash by ~/.worktrees/setup-worktree.sh, and read by the orchestrator
# (the /orchestrate skill) for the gate/check/queue commands + BRIEF_CONVENTIONS.

# No gitignored env files yet — the lab is a local-first OSS app; trials run
# against a locally-authenticated `claude` binary, not API keys in env files.
ENV_FILES=()

# Install command, run inside the new worktree (worktrees don't share node_modules).
# We also build once: the workspace packages import each other's BUILT types
# (@abl/engine, @abl/server, …), so a fresh install-only worktree fails
# `pnpm check` (and the pre-commit hook, which runs it) with cascading
# "@abl/engine not found" errors in files the change never touched, until the
# depended-on packages are built. Building at setup makes the scoped check work
# out of the box (the gate also builds first, so nothing here is gate-specific).
INSTALL_CMD="pnpm install && pnpm build"

# GATE_CMD is the HEAVY full gate (build + check + test across the workspace),
# serialized behind the slim machine-wide slot (scripts/gate-slot.mjs, shared
# tmpdir name abl-gate-slot). The RUNNER runs it against a queued PR's worktree
# when draining; implementers do NOT run it (they enqueue).
GATE_CMD="pnpm gate"

# SCOPED_CHECK_CMD is the cheap, unlocked bar an implementer's commits are held
# to: `pnpm -r check` = per-package typecheck/lint (plus web's token-purity +
# theme-matrix scripts); no build, no test suite, and no formatter (see below).
# It's enforced by a Claude Code AGENTIC hook, NOT a native git hook: there is no
# .git/hooks/pre-commit — instead .claude/settings.json wires a PreToolUse hook
# on `git commit` to `node .agents/hooks/pre-commit.mjs` (which runs `pnpm check`).
# So it fires for agents committing under the harness; a plain `git commit` run
# outside the harness does NOT trigger it. Because it runs `pnpm -r check`, it
# needs the workspace already built — which INSTALL_CMD now handles at setup.
SCOPED_CHECK_CMD="pnpm check"

# Durable gate queue (ported from Trinity; tmpdir root abl-gate-queue).
ENQUEUE_CMD="pnpm gate:enqueue"   # --branch <b> --worktree <absPath> --pr-number <n> --pr-url <url>
DRAIN_CMD="pnpm gate:drain"       # [--max <n>]

# Conventions baked into every dispatched implementer brief (read by the orchestrator).
BRIEF_CONVENTIONS="The lab is an OSS monorepo: backend packages (packages/engine, packages/mcp, packages/server) are Effect-TS — invoke the 'effect' skill as Step 0 for any of them; the dashboard (packages/web) is SolidJS — invoke the 'solid' skill as Step 0 there; full-stack slices invoke both. THE DATA CONTRACT IS packages/engine/src/schema.ts: build against it; if it needs changing, say so in your PR description rather than silently rewriting it. Flat files are the source of truth (trial.json + artifacts under the store); SQLite and all UI state are derived indexes, rebuildable from disk — never make the DB authoritative. Every trial record carries its full environment fingerprint (model, harness, OS, scenario+grader versions). This repo is PUBLIC: never commit secrets, tokens, or private internals from other projects (including roadmap/phase refs in ported code comments); MIT license. SOLO LOCAL-FIRST TOOL: no accounts, auth, or team/collab/multiplayer features ever — sharing is committed artifacts; servers bind 127.0.0.1. Adapting OSS code (with license compliance and attribution) is fine; porting proprietary infra from private projects (multi-user chat, host controller, session sync) is not. Keep the product GENERIC: primitives users compose, not baked-in opinions. Code comments explain the mechanism — no issue/PR/version/plan refs. Pre-launch, forward-only: no migration/backfill/compat shims. No Claude/AI attribution on commits or PRs — git user only. YOU DO NOT RUN THE FULL GATE: 'pnpm gate' runs later in a runner drained from the queue. There is NO code formatter in this repo (no prettier, no 'pnpm format' script) — do not run or expect a formatter in write mode; match the house style by hand: no semicolons, double quotes, trailing commas, 2-space indent. Your wrap-up: write the whole change uncommitted, run /simplify over the full diff when the slice is substantial, THEN commit in logical blocks (a Claude Code agentic pre-commit hook — wired in .claude/settings.json, not a native git hook — holds each commit to 'pnpm check'), push, open a DRAFT PR, and enqueue with 'pnpm gate:enqueue --branch <b> --worktree <absPath> --pr-number <n> --pr-url <url>' — then hand back without waiting. Do not wait on gates, do not mark your own PR ready, never rebase, never self-merge. An in-flight sub-agent you spawned is YOUR wait, not a stopping point — end your turn only after the enqueue+report handoff is complete."

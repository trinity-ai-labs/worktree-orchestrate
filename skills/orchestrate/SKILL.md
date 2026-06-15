---
name: orchestrate
description: >-
  Release-branch worktree workflow (per-project) — the playbook for coordinating and shipping work off
  an integration branch using isolated git worktrees. Use whenever you're asked to ORCHESTRATE or
  coordinate work, complete or work a GitHub issue, execute a plan, or handle a batch of tasks (you
  decompose, make worktrees, dispatch implementer sub-agents, review their PRs, and merge); AND whenever
  you're told to build, implement, or fix a specific thing in a repo that uses this flow (you're the
  IMPLEMENTER: code in a worktree, run /simplify, get the gate green, open a PR, hand back). Covers the
  generic worktree helper (~/.worktrees/setup-worktree.sh + per-project config), default parallelization,
  the PR review loop, gate-as-backstop, merge-not-squash / never-rebase, stop-and-report, and cleanup.
argument-hint: "[issue # or task batch to coordinate — omit if you're implementing directly]"
---

# Orchestrate — release-branch worktree workflow

Our main dev workflow: we work off an integration branch (for Trinity, `release/x.x.x` — discover the active one with `git branch --list 'release/*'` / the current branch; never hardcode a version). For each task we cut a git worktree, do the work there, commit, push, and open a PR back into the integration branch. After a PR merges we **sync the local integration branch first**, then clean up the merged branch and its worktree.

This is project-agnostic. The per-project specifics — which env files to symlink, the install command, the gate command, the docs fast-path, and the conventions to bake into briefs — live in a config the tooling reads (see *Per-project config* below), not in this playbook.

**Default to planning for parallelization.** Given a batch of work, the first move is to decompose it into independent tasks that can run concurrently in their own worktrees — don't default to doing everything sequentially yourself. Spin up as many worktrees/branches as the work needs.

## First: which role are you?

Before acting, decide whether you are the **orchestrator** or an **implementer** — they behave very differently.

- **ORCHESTRATOR** when the user asks you to *orchestrate / coordinate* work, to *complete or work a GitHub issue*, to *execute a plan*, or hands you a batch of tasks. You are the coordinator. **Do NOT write the implementation yourself.** You decompose the work, create + verify worktrees, dispatch an implementer sub-agent into each (in parallel when independent), then run the review loop and merge. You hold the plan, the reviews, and the merges — not the file edits.

- **IMPLEMENTER** when you are a dispatched sub-agent, or the user *directly tells you to implement / build / fix* a specific thing. You do the actual code in your assigned worktree, get it green, open a PR, and hand back. **You do not merge your own PR** — the orchestrator reviews and merges.

---

## Per-project config

The worktree tooling is generic; each project declares its specifics in a bash file at `~/.worktrees/config/<project>.sh`, where `<project>` is the repo's directory name. The helper sources it; the orchestrator reads it too (e.g. `cat ~/.worktrees/config/<project>.sh`) to learn the gate and the brief conventions. Keys:

- `ENV_FILES` — gitignored env files to symlink from the main checkout into each worktree.
- `INSTALL_CMD` — install command run inside a new worktree (worktrees don't share `node_modules`).
- `GATE_CMD` — the green gate an implementer runs before opening a PR (the orchestrator's backstop).
- `DOCS_BRANCH_PREFIX` / `DOCS_NOTE` — branches under this prefix skip env + install (a fast path for deps-free work like markdown).
- `BRIEF_CONVENTIONS` — project conventions to bake into every dispatched implementer brief (framework skills, compat policy, comment style, simplify-then-gate, etc.).

A repo with no config still works — the helper makes a bare worktree (no env, no install). To onboard a new project, drop a `~/.worktrees/config/<project>.sh` declaring the keys above.

---

## Worktree creation (both roles depend on this being done right)

**⛔ HARD BAN — the Agent tool's `isolation: "worktree"` parameter (and ANY harness / auto worktree provisioner) is FORBIDDEN. Never use it.** It (a) creates the worktree under `.claude/worktrees/agent-*` (violates invariant 1 below) and (b) repeatedly seeds it at a STALE base — far behind the integration tip (observed ~1000+ commits behind, a previous-minor-version commit) — which has burned us over and over (agents waste cycles re-basing, or stale code silently leaks in). There is exactly ONE way to make a worktree: the helper script below, then **verify HEAD yourself**, THEN dispatch a plain agent (no `isolation`) pointed at that worktree path.

**Helper script — `~/.worktrees/setup-worktree.sh`** (a personal tool, NOT repo-tracked — edit it directly, no worktree/PR needed; don't search the repo for it). It auto-detects the project and reads its config, so it works the same for any repo.

Usage: `setup-worktree.sh <branch> <base>` — both **required**. Run it from **anywhere inside the target repo** (the root, a subdirectory, a monorepo subpackage, or even a linked worktree — it walks up to the repo's common gitdir). If cwd isn't inside the repo, prefix `REPO=/path/to/repo`.
- `<branch>` = full name of the branch to create (any prefix: `feat/…`, `fix/…`, `refactor/…`, `docs/…`); the worktree dir is named after the segment past the last slash (`feat/toasts-top-right` → `toasts-top-right`).
- `<base>` = the branch to fork from, with **no default** (integration branches roll over often, so a hardcoded default just goes stale); it errors early with a `git fetch` hint if `<base>` isn't a local ref yet.

It creates the worktree at `~/.worktrees/<project>/<branch-leaf>`, symlinks the config's `ENV_FILES`, and runs `INSTALL_CMD` — automating invariants 1, 3, 4 below. A branch under `DOCS_BRANCH_PREFIX` takes the fast path (env + install skipped).

**The four invariants** (the helper covers 1, 3, 4 — step 2 is always on you):
1. The worktree lives under `~/.worktrees/<project>/`, **never** under `.claude/worktrees`.
2. **Verify its HEAD == the base tip BEFORE dispatching any agent** — run `git -C <worktree> rev-parse HEAD` and confirm it equals `git rev-parse origin/<base>` (e.g. `origin/release/x.x.x`). The helper does **not** verify this for you — sync the base first, then check. A mismatch means STOP and fix the base; do not dispatch.
3. Env files are symlinked into the worktree (they aren't carried over automatically).
4. Deps are installed (worktrees don't share `node_modules`, and the gate can't run without them).

---

## Orchestrator

### Dispatch
Decompose the batch into independent tasks. For each: create + **verify** a worktree (above), then **dispatch a plain implementer sub-agent** (no `isolation`) pointed at that worktree path — in parallel whenever the tasks are independent. Spin up as many worktrees/branches as the work needs.

Bake the **implementer rules** (next section) into every dispatched brief — including, every time:
- Work only in the assigned worktree (absolute paths); match surrounding style.
- **The project's `BRIEF_CONVENTIONS`** from its config (`~/.worktrees/config/<project>.sh`) plus anything in the repo's `AGENTS.md` — framework skills, compat policy, comment style, etc. (For Trinity: use the `effect` skill for Effect-TS code; pre-launch forward-only with no backwards-compat shims; comments explain the mechanism.)
- **Commit in logical blocks as you go** — not one monolithic end-of-task commit. Each self-contained step (a type + its plumbing, a behavior + its tests, one cohesive refactor) is its own commit with a mechanism-explaining message; we never squash, so these are the reviewable history.
- Before the **final** commit, **run the `/simplify` skill** over the full set of changes, fold the fixes in, then **run the project's `GATE_CMD`** to green.
- Push all commits, open a PR targeting the integration branch; report PR URL, files changed, gate result, tests touched, and anything ambiguous. **Never rebase. Never self-merge.**
- **The stop-and-report rule** (verbatim in the brief): if you get stuck, blocked, or hit an ambiguity you can't resolve, STOP and hand back a reviewable artifact — a draft PR, or a complete report of your worktree state + the exact blocker + the decision you need. Never spin or die silently.

### Dispatch in the background, then monitor for divergence
**Default to dispatching implementers in the background** (the Agent tool's `run_in_background: true`) rather than blocking on each one. This keeps you — the orchestrator — responsive: you get an automatic notification when an agent completes or opens its PR, AND you can poll the live worktrees mid-flight to catch a wandering agent *before* it burns a whole run going the wrong way. (Background dispatch is the Agent tool's own flag — this is NOT the banned `isolation: "worktree"`; you still make the worktree yourself via the helper and point a plain agent at it.)

**Poll every ~3 minutes for divergence** while agents run. Use `ScheduleWakeup` to self-pace the checks (≈180s keeps the prompt cache warm and is frequent enough to course-correct early). Don't poll *only* for completion — that arrives as a notification for free; the point of polling is **early divergence detection**. Each tick, snapshot what files each agent is actually touching and compare against its assigned scope:

- **Snapshot against the worktree's OWN HEAD (its fork point), not the integration tip:** `git -C <wt> --no-pager diff --stat HEAD` (+ `git -C <wt> ls-files --others --exclude-standard` for untracked, + `git -C <wt> log --oneline HEAD` to see if it has committed). Diffing against `origin/<integration>` after another PR merged renders that merged work as **phantom deletions/additions** in this worktree and triggers a false alarm — same trap as the PR-review diff (below). Diff the fork point.
- **What counts as divergence:** editing another task's / another phase's **core source files** (e.g. a "types only" task editing the resolver, or a backend task building UI). **What does NOT count:** compile-driven ripples from the task's own change — exhaustive `switch`/enum/interface/config entries a new member forces, a one-line badge to keep an exhaustive UI match compiling, and `+1`-line fixture edits across many `*.test.ts` files (even ones in another area) from adding a field to a shared type. Spell out this divergence/not-divergence line in the wakeup prompt so the check is mechanical, not a re-judgement each time.
- **If an agent diverged:** `TaskStop` it immediately, then **dispatch a fresh plain agent into the SAME worktree path** with a tighter brief — explicit *do-not-touch* boundaries naming the files/areas it strayed into, and an instruction to revert the out-of-scope edits. Don't try to course-correct a still-running agent mid-stream; stop-and-replace is cleaner.
- **If an agent opened its PR or completed:** stop rescheduling for that one and move into the PR review loop + merge below.

Carry forward a one-line note of each agent's last-known on-scope file set in the next wakeup prompt, so a sudden jump in surface area is obvious tick-over-tick.

### The PR review loop
Each implementer opens **its own PR** back to the integration branch. You then **review each PR — and actually read the code involved**, not just the agent's summary or the green gate. Read the diff: verify correctness, that it does what the issue/plan intended, that the scope is right, and scrutinize anything the agent flagged or where it went wider than the planned files. A green gate and a confident agent report are necessary but **not sufficient** — the merge decision is yours and must be grounded in the actual changed code.

**Diff against the merge-base, not the integration tip.** The integration branch advances *while a worktree is open* (other agents' PRs merging in parallel), so `git diff <integration-branch>..HEAD` shows the OTHER work's additions as phantom **deletions** in this PR — a clean change then looks like it ripped out unrelated code, and you'll raise a false alarm. Always diff the fork point: `git -C <wt> diff $(git merge-base HEAD origin/<integration>)..HEAD` (re-`fetch` first — the tip moves). Confirm by test-merging the current base in: if the "deleted" files come back as *additions*, the PR never touched them. This bit us once — burned a review cycle chasing a "destructive deletion" that was just the base having moved.

If it needs changes, **dispatch a fix agent into that same worktree**; iterate until the PR is good. Only when satisfied do you **merge and clean up** — and the *order* matters because of worktrees (see next section): the implementer has already pushed everything, so you **remove the worktree first**, then merge with `gh pr merge --merge --delete-branch`.

### On the gate — re-gate as a backstop, not a blanket
**The IMPLEMENTER runs the project's `GATE_CMD` to green at wrap-up — that IS the gate.** An agentic pre-commit hook may be wired (PreToolUse → gate, denies on failure), but it did NOT intercept the commits observed in orchestration sessions — a broken-test commit slipped through, and a sub-agent reported it never fired. Likely because implementers run as Agent-tool sub-agents and the interactive `PreToolUse` hook doesn't apply to their Bash calls (it gates a normal interactive session as designed — don't assume it's broken there). And release-branch PRs typically get no CI. So: **don't assume a commit was gated by the hook — especially a sub-agent's**; the implementer's own gate run is what stands in for CI.

Don't blanket re-run the full suite yourself on every PR — it's redundant when the agent credibly reported all-green with real pass-counts. Re-run the gate as a **backstop** only when there's reason to: an agent died/stopped early or gave no credible pass-count (gate may never have run), or a **merge integrates branches that weren't tested together** (run one integration gate on the merged result). Your always-on job is reading the **diff**; re-gating is conditional.

(Observed: agents can die mid-run on API/socket errors or stop early — the ones that had already opened a PR were reviewable/mergeable; one that stopped with no PR left only a dirty worktree, forcing manual cleanup. That's why the stop-and-report rule is mandatory in every brief.)

### Merge & cleanup — order matters because of worktrees
The branch lives in a linked worktree, and **git refuses to delete a branch that's checked out in a worktree** (`cannot delete branch 'X' used by worktree …`). So `gh pr merge --delete-branch` would error on the local-branch step if the worktree still exists. The fix is ordering, not dropping the flag: the implementer has already pushed everything and the PR is up, so **tear the worktree down before you merge**, and then `--delete-branch` cleanly removes both branches. Sequence, every time:
1. **Remove the worktree first:** `git worktree remove <path>`. Nothing is lost — it's all pushed — and this frees the branch so it can be deleted.
2. **Merge with branch deletion:** `gh pr merge --merge --delete-branch` — real merge commit (never squash), and with the worktree gone `--delete-branch` cleanly removes BOTH the local and remote branch. Skipping `--delete-branch` is what let merged `origin/*` branches pile up indefinitely (they did: dozens accumulated). Verify it's fully merged first; STOP on git's "not yet merged to HEAD" warning.
3. **Sync the local integration branch:** `git checkout <integration> && git pull --prune` so it fast-forwards to the merge commit and stale remote-tracking refs are pruned. Skipping the sync leaves it behind the remote, so the next worktree gets cut from a stale HEAD.
4. **Close the issue yourself if the work resolved one — GitHub will NOT auto-close it.** Auto-close only fires when a PR with a `Closes #N` keyword merges into the **default branch** (`main`). Our PRs merge into the **integration branch**, so a linked issue stays open regardless of keywords — and in practice the PRs only cross-reference (`#N`) rather than use a closing keyword anyway, so no close link even exists. After merging, `gh issue close <N> --comment "Fixed in #<pr> (merged into <integration>)."` for each issue the merged work resolved. (Don't wait for the eventual integration→`main` merge to sweep them — close them now so the issue tracker reflects reality.)

---

## Implementer

Work only in the assigned worktree (absolute paths), match surrounding style, and follow the project's conventions — its `BRIEF_CONVENTIONS` (from `~/.worktrees/config/<project>.sh`) and its `AGENTS.md`. (For Trinity: use the `effect` skill for any Effect-TS code; build forward-only — pre-launch, no backwards-compat shims; comments explain the mechanism, no issue/PR/version/plan refs.)

**Commit as you go, in logical blocks.** Don't accumulate the whole task into one end-of-run commit — commit each self-contained step (a type + its plumbing, a behavior + its tests, one cohesive refactor) as you finish it, with a message that explains the mechanism. We never squash, so these commits survive into history and let the orchestrator review the PR block-by-block. The gate needn't be green at every intermediate commit, but it MUST be green at the final one.

**Before the final commit, run the `/simplify` skill** over the full set of worktree changes (reuse / simplification / efficiency / altitude cleanups — quality only, not bug-hunting), fold the fixes in, then **run the project's `GATE_CMD`** and make it pass — so the PR is already simplified and green when the orchestrator reviews it. Then push all your commits, open a PR targeting the integration branch, and report back: PR URL, files changed, gate result, tests touched, and anything ambiguous. **Never rebase. Never merge your own PR.**

**If you get stuck, hand back a reviewable artifact — never spin or die silently.** A blocker, an ambiguity you can't resolve, a gate you can't get green, or running low on room all mean the same thing: STOP and give the orchestrator something it can act on. Commit-push and open a **draft PR** with what you have; if you can't even do that, hand back a complete report of your worktree state — what's done, what's broken, the exact error/blocker, and the decision you need. Partial-but-clean beats stuck-and-silent (e.g. land the solid part and flag the rest). **Never leave a dirty worktree with no PR and no report.**

---

## Hard rules (both roles)

- **⛔ Never use the Agent tool's `isolation: "worktree"` param or any auto worktree provisioner.** Make worktrees only via `~/.worktrees/setup-worktree.sh`, verify HEAD, then dispatch a plain agent. (See worktree section.)
- **Never squash-merge.** Merge PRs with a real merge commit (`gh pr merge --merge --delete-branch`), never `--squash` — squashing flattens the individual commits we keep. Always pass `--delete-branch` so the remote branch is removed on merge instead of accumulating — but **remove the worktree first** (see Merge & cleanup), or `--delete-branch` errors trying to delete a branch still checked out in a worktree.
- **Do NOT rebase.** Rebasing rewrites history. Default to plain merge commits everywhere: integrating parallel worktree branches, a branch falling behind the integration branch, resolving overlap between two PRs — MERGE, never rebase. If two parallel branches touch the same file, resolve it at MERGE time (merge one, then merge the other and fix conflicts in the merge), not by rebasing one onto the other. Never instruct a sub-agent to rebase. Only rebase when there's a specific, unavoidable reason AND it's worth rewriting history — rare; when in doubt, merge.
- **Branch from the active integration branch, not `main`.** PRs target the integration branch.
- **Never delete a branch past git's "not merged" warning** — verify fully merged into the target first.

**Why this shape:** integration branch as the merge point, isolated worktrees per task, clean up after merge. Worktrees start without env files and can drift from the integration HEAD, which breaks the work if not handled up front. We preserve real merge history rather than flattening it via squash or rebase. Skipping the post-merge local sync leaves the local integration branch behind the remote, so the next worktree gets cut from a stale HEAD.

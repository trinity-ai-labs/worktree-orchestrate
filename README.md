# worktree-orchestrate

A Claude Code workflow for shipping work off an **integration branch** using isolated **git worktrees** and **orchestrator / implementer** sub-agents. One task → one worktree → one PR → merge → clean up. Parallel tasks run in parallel worktrees without stepping on each other.

This repo packages three things that work together:

| Piece | Lives at (after install) | What it does |
|---|---|---|
| `bin/setup-worktree.sh` | `~/.worktrees/setup-worktree.sh` | Generic helper that creates a worktree, symlinks env files, installs deps |
| `bin/merge-pr.sh` | `~/.worktrees/merge-pr.sh` | Atomic close-out: tear down the worktree, real merge commit, fast-forward the local integration branch (so the post-merge sync can't be dropped) |
| `bin/remove-worktree.sh` | `~/.worktrees/remove-worktree.sh` | Safely tear down a worktree, killing processes rooted in it first |
| `config/<project>.sh` | `~/.worktrees/config/<project>.sh` | Per-project settings the helper + skill read (gate, env files, conventions) |
| `skills/orchestrate/` | `~/.claude/skills/orchestrate/` + `~/.agents/skills/orchestrate/` | The `/orchestrate` skill — the playbook Claude follows |

---

## The mental model

You **never code directly in the main checkout**. The main checkout holds the **integration branch** (for Trinity that's `release/x.x.x` — the current release line). Every task gets its own git worktree under `~/.worktrees/<project>/<branch-leaf>`, branched off the integration branch. Work → commit → push → PR back into the integration branch → review → **merge with a real merge commit** → sync the local integration branch → delete branch + worktree.

When you invoke `/orchestrate`, Claude first decides **which role it's in**:

- **Orchestrator** — you asked it to *coordinate* work, *work a GitHub issue*, or *execute a plan/batch*. It does **not** write code. It decomposes the work, makes + verifies a worktree per task, dispatches implementer sub-agents (in parallel when independent), reviews each PR by reading the diff, and merges.
- **Implementer** — you told it to *build / fix / implement* a specific thing (or it was dispatched as a sub-agent). It codes in its worktree, runs `/simplify`, greens the gate, opens a PR, and **hands back — it never merges its own PR**.

### Why this shape
- **Isolated worktrees** → parallel tasks never collide; each has its own `node_modules` and branch.
- **Integration branch as merge point** → PRs target the release line, not `main`.
- **Real merge commits, never squash/rebase** → individual commit history is preserved; conflicts between parallel branches are resolved at merge time.
- **Gate as a backstop** → the implementer greens the gate before the PR; the orchestrator re-runs it only when there's reason to (an agent died, or a merge combined branches never tested together).

---

## Prerequisites

> **macOS or Linux** — `install.sh` is portable `bash` (re-runnable; cleanly converts a prior `--copy` install to symlinks). On Windows, run it under WSL.

- **git** (worktrees are built in; nothing extra to install)
- **[GitHub CLI](https://cli.github.com/)** (`gh`) authenticated: `gh auth login` — used to open/merge PRs
- **[Claude Code](https://claude.com/claude-code)** — this is where `/orchestrate` runs
- Whatever your project needs to install + test (for Trinity: **pnpm**)

---

## Install

```bash
git clone git@github.com:trinity-ai-labs/worktree-orchestrate.git
cd worktree-orchestrate
./install.sh
```

`install.sh` **symlinks** the pieces into place (`~/.worktrees/` and both skill homes — `~/.claude/skills/` and `~/.agents/skills/`), so a later `git pull` in this repo updates your live tools automatically. Use `./install.sh --copy` if you'd rather have independent copies.

Verify:

```bash
ls -la ~/.worktrees/setup-worktree.sh        # -> .../worktree-orchestrate/bin/setup-worktree.sh
ls -la ~/.claude/skills/orchestrate          # -> .../worktree-orchestrate/skills/orchestrate
ls -la ~/.agents/skills/orchestrate          # -> .../worktree-orchestrate/skills/orchestrate
```

Then in Claude Code, `/orchestrate` should appear in the skills list.

---

## Setting up with Trinity

The Trinity config (`config/trinity.sh`) ships in this repo, so `install.sh` already wired it up. It assumes your Trinity clone's directory is named `trinity` (the helper keys off the directory name). What it declares:

- **ENV_FILES** — symlinks `trinity/.env.local`, the `trinityailabs.com/.env.*` files, and `cf/.dev.vars` into each worktree (you must already have these in your main checkout — get them from the team vault, they're gitignored).
- **INSTALL_CMD** — `pnpm install --frozen-lockfile`
- **GATE_CMD** — `pnpm check && pnpm test` (this is the green bar before any PR)
- **DOCS_BRANCH_PREFIX** — `docs/` branches skip env + install (markdown comes up instantly)
- **BRIEF_CONVENTIONS** — baked into every implementer brief: use the `effect` skill for Effect-TS code; pre-launch **forward-only, no backwards-compat shims**; comments explain the mechanism (no issue/PR/version refs); run `/simplify` then the gate before committing.

**One-time Trinity setup:**

1. Clone Trinity to a directory named `trinity` and check out the active release branch in the main checkout (`git switch release/x.x.x`). Release/integration branches live in the **main checkout**; worktrees are only for feature/fix work.
2. Drop the gitignored env files (`trinity/.env.local`, etc.) into the main checkout — the helper symlinks *these* into every worktree, so they only need to exist once.
3. `pnpm install` in the main checkout once.
4. Open Claude Code in the Trinity repo and you're ready: `/orchestrate`.

---

## Daily usage

### As the orchestrator (coordinating a batch / an issue)

```
/orchestrate work issue #1042
```

Claude will: discover the active integration branch, decompose the issue into independent tasks, make + verify a worktree per task, dispatch implementer sub-agents, review each PR's diff, and merge + clean up. You stay in the loop on the merge decisions.

### As the implementer (one specific thing, yourself)

```
build the toast-position fix
```

Claude codes it in a fresh worktree, simplifies, greens the gate, opens a PR targeting the integration branch, and hands back for you to review/merge.

### Making a worktree by hand

```bash
# from anywhere inside the repo:
~/.worktrees/setup-worktree.sh fix/toast-position release/0.3.10
```

Both args are **required** (no default base — integration branches roll over, so a hardcoded default goes stale). It creates `~/.worktrees/trinity/toast-position`, symlinks env files, and installs deps. If the base isn't a local ref yet, it tells you to `git fetch` first.

> **Always verify HEAD before dispatching an agent into a worktree:**
> ```bash
> git -C ~/.worktrees/trinity/toast-position rev-parse HEAD
> git rev-parse origin/release/0.3.10     # must match
> ```
> The helper doesn't verify this — a mismatch means the base is stale; fix it before any work starts.

---

## Onboarding a new project

Drop a `~/.worktrees/config/<project>.sh` (named after the repo's directory) declaring the keys you need — see [`config/example.sh`](config/example.sh) for an annotated template. Add it to *this* repo's `config/` and re-run `install.sh` so it's symlinked and shared with the team. A repo with no config still works; it just gets a bare worktree (no env, no install).

---

## The hard rules (Claude follows these; good to know)

- **Never** use the Agent tool's `isolation: "worktree"` param or any auto worktree provisioner — they seed worktrees at a **stale base** and put them in the wrong place. Only `setup-worktree.sh` makes worktrees.
- **Never squash-merge, never rebase.** Always real merge commits. Resolve parallel-branch conflicts at merge time.
- **Branch from the integration branch, not `main`.** PRs target the integration branch.
- **Implementers never merge their own PRs** — the orchestrator reviews the diff and merges.
- **After merge:** sync the local integration branch *first*, then delete the merged branch (only past git's "fully merged" check), remove the worktree, and close the issue yourself (`gh issue close` — GitHub won't auto-close, since PRs merge into the integration branch, not `main`).

---

## Layout of this repo

```
.
├── install.sh                     # symlink (or --copy) the pieces into place
├── bin/setup-worktree.sh          # the generic worktree helper
├── config/
│   ├── trinity.sh                 # Trinity's real config (working example)
│   └── example.sh                 # annotated template for new projects
└── skills/orchestrate/SKILL.md    # the /orchestrate playbook
```

To change the workflow: edit the file here, commit, push. Everyone who installed via symlink picks it up on `git pull`.

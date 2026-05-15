# Productivity Contract

**Status:** REQUIRED for every project running under codex-supervisor.
**Origin:** 2026-05-15 — diagnosed audit-loop pathology on `neural_grow` (13 product-source touches vs 6118 docs/planning touches over 7 days) and on `Swedish_Civic_Test` (workers running but 0 source commits in 30-minute windows).

## The problem this fixes

The CEO + per-team MANAGER + workers structure is structurally prone to producing *evidence-of-work* instead of *product*. Each layer has natural deliverables that are markdown:

- Planners "refresh queues" and "audit posture".
- Validators "enforce canonical policy" and "sync evidence".
- Managers "review acceptance" and "queue next tasks".
- CEOs "process inbox" and "archive logs".

Every one of those is real work that *the role description* makes legitimate. None of it ships product code. The factory loops indefinitely without shipping.

## The contract

Every project under codex-supervisor MUST:

### 1. Have a `GOAL.md` at repo root

`GOAL.md` is the single source of truth for *what we are shipping right now*. The CEO refuses to iterate when it is missing or stale. It names:

- the **sprint target** (one shippable sentence, ≤7 days)
- the **acceptance test** (commands that pass when the goal is met)
- **product source paths** (commits must touch ≥1 of these)
- **non-product paths** (commits touching ONLY these are reverted)
- **banned iteration types** (queue-refresh, planner-audit, etc.)
- **productivity targets** (commits/day, manager rejection rate)

Template: see `/Users/billy/Desktop/projects/CLAUDE.md` "Productivity Contract" section, or the GOAL.md template planted by `bootstrap-ai-project`.

### 2. Install the workspace pre-commit hook

```
ln -sf /Users/billy/Desktop/projects/.shared/productivity-pre-commit.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

`bootstrap-ai-project` does this automatically. The hook:

- Reads `GOAL.md` to extract product paths.
- Rejects any commit whose staged files don't touch a product path.
- Honors `[allow-meta]` in the commit message as the operator override.

### 3. Use the productivity-aware `/goal` templates

The workspace CLAUDE.md defines updated `/goal` templates for CEO, MANAGER, and worker that bake in:

- CEO: HOLDs all teams if GOAL.md is empty/stale.
- MANAGER: REJECTS worker iterations whose git diff didn't touch product paths.
- Worker: every iteration MUST commit a product-source change.

Old `/goal` templates without productivity gates are deprecated. Old projects must migrate.

### 4. CEO heartbeat must log progress

Every CEO iteration appends one line to `codex-tasks/logs/ceo-progress.log`:

```
YYYY-MM-DD HH:MM | source-commits=N | docs-commits=M | distance-to-goal=<one sentence>
```

If `source-commits=0` for ≥2 consecutive iterations, CEO is REQUIRED to:

- Stop the lowest-output pane.
- Append `[CEO->OPERATOR PRODUCTIVITY-STALL]` to `codex-tasks/ceo-inbox.txt` with diagnosis.

## How new projects pick this up

1. **`bootstrap-ai-project`** automatically:
   - Plants a `GOAL.md` template with placeholders.
   - Installs `.git/hooks/pre-commit` symlinked to the workspace hook.
   - Prints next-steps that point here.

2. **CEO `/goal` template** in workspace CLAUDE.md reads `GOAL.md` on every iteration; without it, the CEO HOLDs.

3. **MANAGER `/goal` template** enforces source-touch acceptance gate, so even if a worker tries to ship a doc-only iteration the manager reverts it.

4. **Pre-commit hook** is the last-line defense: even if someone bypasses the manager logic, git refuses the commit.

If any of these three layers (workspace CLAUDE.md, bootstrap script, pre-commit hook) hasn't been applied to an older project, run:

```bash
bootstrap-ai-project /path/to/older-project --force
```

then fill in its `GOAL.md`.

## Operator overrides

- `git commit --no-verify` — skip the pre-commit hook entirely (rare).
- `[allow-meta]` in commit message — bypass the product-path check for legitimately non-product work (release prep, docs that document a real product change in the same chain, infra).
- Edit `GOAL.md` directly — only operator does this; CEO requests new goals via inbox.

## Why this works

Audit-loop pathology happens because CEOs/MANAGERs naturally produce evidence-of-work that is markdown. By making source-touch a hard gate at three layers (worker reads GOAL.md before iterating; MANAGER rejects audit-only diffs; git hook rejects audit-only commits) we ensure that "iteration completed" = "product shipped a measurable amount". The CEO becomes a real conductor of progress, not a bookkeeper of its own meetings.

## See also

- `ai-factory.md` — high-level factory architecture (CEO + MANAGER + workers).
- `ceo-staffing.md` — how the CEO bootstraps teams (now subject to GOAL.md gate).
- `never-waste-workers.md` — the historical "always find work" rule (now narrowed: must be product source work).
- `right-sizing.md` — how many panes for the actual workload.

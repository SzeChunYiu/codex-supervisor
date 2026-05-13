# Never waste a worker

**Operator policy baked into codex-supervisor.** AI sessions running under
the supervisor should not sit idle, but they must stay convergent. A pane that
completes its `/goal` should immediately pick up useful work from the current
AI factory board or leave a validator handoff.
Shared acceptance blockers belong in `codex-tasks/blockers.txt`; dynamic
workers take that queue before ordinary open work.

## Why

Codex panes consume paid compute (active-CPU pricing). An idle GOAL_DONE pane
is waste, but unrelated fallback PRs are also waste because they make parallel
lanes produce their own stuff instead of a shared outcome. Every pane should be
doing useful work, verifying an artifact, removing a blocker, or telling the
VALIDATOR exactly what is needed next.

## How the supervisor enforces it

1. **`CONTINUOUS_LANES` defaults to `*`** (every lane is continuous).
   When a pane reaches "Goal achieved" and has no next task in its queue
   file, the supervisor re-sends its original `/goal` so the lane keeps
   iterating. Override by setting `CODEX_SUPERVISOR_CONTINUOUS_LANES` to
   a specific space-separated list, or to empty string to disable.

2. **`RESPAWN_ON_GOAL_DONE=1`** (default). Each restart spawns a fresh
   codex process so the worker doesn't accumulate context bloat across
   iterations.

## How project lanes must cooperate

Setting `CONTINUOUS_LANES=*` only matters if the lane's `/goal` knows what to
do when its specific queue is empty. **Every lane prompt must include
factory-board fallback behaviour.** Drop the canonical rule into the project's
coordination doc (e.g. `docs/parallel-sessions.md`):

> ## Rule N: Never idle — converge on the factory board
>
> When you finish your assigned `/goal` and your queue file is empty,
> do not create unrelated work. Read
> `docs/parallel-sessions/TEAM_PLAN.md` and, in order of preference:
>
> 1. Close the smallest unchecked acceptance item inside your writable lease.
> 2. Verify one artifact listed in the artifact ledger.
> 3. Write a validator handoff/proposed queue item if the next useful task
>    belongs to another lane, host, branch, or human decision.
> 4. Stop if the batch is accepted or all remaining gaps are outside your lease.
>
> A pane that goes GOAL_DONE because *the lane reached its rate-limit stop
> condition* is fine. A pane that goes GOAL_DONE while an acceptance gap existed
> inside its lease is a bug; the validator should fix the queue or lease.

## How `bootstrap-ai-project` should set this up

New projects bootstrapped via `bootstrap-ai-project` get this rule pre-
installed in their `docs/parallel-sessions.md` and the worker prompts
template includes "If your queue is empty, follow Rule N (never idle)."

## Reference template

See `templates/NEVER_IDLE_RULE.md` for the canonical text to drop into
each project's coordination doc.

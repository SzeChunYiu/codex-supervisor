## Rule N: Never idle — always find work

When you finish your assigned `/goal` and your queue file is empty, do
not create unrelated work. The supervisor may re-send your prompt; use
that iteration to converge on the current AI factory board in
`docs/parallel-sessions/TEAM_PLAN.md`.

1. **Take the next unchecked acceptance item** in `TEAM_PLAN.md` that
   fits your lane's writable lease.
2. **Verify one existing artifact** listed in the artifact ledger if no
   implementation item fits your lease.
3. **Write a validator handoff/proposed queue item** if the next useful
   task needs another lane, host, branch, or human decision.
4. **Stop** if the batch is accepted or all remaining gaps are outside
   your lease.

A pane that goes GOAL_DONE because the lane reached a rate-limit stop
condition is fine — that's an external block. A pane that goes
GOAL_DONE because *there were no tasks queued and no factory-board gap*
is fine. GOAL_DONE because the worker ignored an unchecked acceptance gap
is a bug. The supervisor defaults `CODEX_SUPERVISOR_CONTINUOUS_LANES=*`;
this rule keeps retries convergent instead of creating side quests.

**Cap blast radius:** stay in scope. Small bounded PRs only. If a
fallback task wants to touch a sibling lane's files, write a validator
handoff and stop.

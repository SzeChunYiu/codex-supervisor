# Planner lane

Legacy name for the fixed VALIDATOR lane. Prefer
`docs/parallel-sessions/validator-planner.md` for new projects.

The planner pane is the session leader. It does not own product code. It keeps
parallel work coherent by validating the latest pane outputs, updating the team
plan, and queueing the next smallest tasks for dynamic or specified worker
lanes.

In factory terms, this legacy lane is the VALIDATOR: it keeps one batch
outcome, acceptance checklist, artifact ledger, and queue sequence converging.

## Purpose

Maintain the current plan for the supervisor batch so worker panes can stay
compact, focused, and coordinated. Prefer written artifacts over chat memory.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/distributed-protocol.md`
- The project prompt file shown by `./codex-supervisor.sh prompts`
- Current supervisor status from `./codex-supervisor.sh status`
- Existing lane specs under `docs/parallel-sessions/`
- `docs/parallel-sessions/validator-planner.md` if present

## Writable scope

- Planning and coordination docs, especially `docs/parallel-sessions/TEAM_PLAN.md`
- Lane queue files under `codex-tasks/` when a next task is clear
- Handoff notes requested by the project
- Host/lane lease tables that record source tree, branch/worktree, and writable
  scope ownership

Do not edit implementation files unless the user explicitly asks the planner to
make code changes. The planner should delegate implementation to worker lanes.

## Iteration cycle

1. Inspect `git status`, supervisor status, and recent pane tails.
2. Summarize what each pane appears to have done recently.
3. Update `docs/parallel-sessions/TEAM_PLAN.md` with:
   - current batch outcome,
   - acceptance checklist and artifact ledger,
   - host assignment for each lane,
   - source tree class for each lane: canonical checkout, registered Git
     worktree, or registered execution mirror,
   - branch/worktree and writable-scope lease for each lane,
   - lane status,
   - blockers,
   - next recommended tasks.
4. Retire or flag stale leases before queueing more work. If two lanes claim
   the same branch/worktree/path, stop queueing implementation and record the
   conflict.
5. Add only clear, compact-safe `/goal` tasks that close an acceptance gap,
   verify an artifact, or remove a blocker. Use
   `codex-tasks/open.txt` for generic dynamic-worker tasks and
   `codex-tasks/<lane>.txt` for specified-lane tasks.
6. Stop after one planning refresh or when blocked.

## Stop rule

Stop after updating the team plan once. Do not keep chatting open-endedly; the
supervisor will respawn a fresh planner iteration when needed.

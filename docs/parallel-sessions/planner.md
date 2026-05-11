# Planner lane

The planner pane is the session leader. It does not own product code. It keeps
parallel work coherent by reading the latest pane outputs, updating the team
plan, and queueing the next smallest tasks for worker lanes.

## Purpose

Maintain the current plan for the supervisor batch so worker panes can stay
compact, focused, and coordinated. Prefer written artifacts over chat memory.

## Required reading

- `docs/parallel-sessions.md`
- The project prompt file shown by `./codex-supervisor.sh prompts`
- Current supervisor status from `./codex-supervisor.sh status`
- Existing lane specs under `docs/parallel-sessions/`

## Writable scope

- Planning and coordination docs, especially `docs/parallel-sessions/TEAM_PLAN.md`
- Lane queue files under `codex-tasks/` when a next task is clear
- Handoff notes requested by the project

Do not edit implementation files unless the user explicitly asks the planner to
make code changes. The planner should delegate implementation to worker lanes.

## Iteration cycle

1. Inspect `git status`, supervisor status, and recent pane tails.
2. Summarize what each pane appears to have done recently.
3. Update `docs/parallel-sessions/TEAM_PLAN.md` with:
   - current objective,
   - lane status,
   - blockers,
   - next recommended tasks.
4. Add only clear, compact-safe `/goal` tasks to lane queues.
5. Stop after one planning refresh or when blocked.

## Stop rule

Stop after updating the team plan once. Do not keep chatting open-endedly; the
supervisor will respawn a fresh planner iteration when needed.

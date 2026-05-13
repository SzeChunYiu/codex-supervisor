# Lane template

Copy this file to `docs/parallel-sessions/<lane>.md` and fill in the blanks.
The matching prompt should stay short and point here.

## Lane

- Pane: `PANE N`
- Label: `<lane>`
- Host role: `<local-writer | remote-writer | remote-executor | read-only-verifier>`
- Source tree: `<canonical checkout | registered Git worktree | registered execution mirror>`
- Branch/worktree: `<branch and worktree path, or read-only branch>`
- Writable scope: `<paths this lane may edit>`
- Do not edit: `<paths owned by other lanes>`
- Lease recorded in: `docs/parallel-sessions/TEAM_PLAN.md`

## Goal

Describe the lane's purpose in one short paragraph. Keep detailed task lists in
this markdown file, not in `codex-prompts.txt`.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/distributed-protocol.md` if this project can run on more than one host
- `docs/parallel-sessions/TEAM_PLAN.md`
- `<project docs or source files>`

## Preflight before editing

1. Confirm current host, `pwd`, `git status --short --branch`, `git remote -v`,
   and `git worktree list`.
2. Confirm this lane owns the branch/worktree and writable scope above.
3. If this lane is `remote-executor` or `read-only-verifier`, do not edit source
   unless this file explicitly grants a source-write lease.
4. If another lane owns the requested path or branch, stop and hand off.

## Iteration cycle

1. Re-read required docs.
2. Complete the preflight above.
3. Select one small task that maps to `TEAM_PLAN.md`.
4. Implement only that task inside the writable scope.
5. Run verification: `<commands>`.
6. Record changed files, host/path/branch, checklist item, and results.
7. Stop the goal when complete, blocked, or near the timebox.

## Compact-safe stop rule

Stop after one focused patch, after 30 minutes, or when blocked. Do not keep
asking follow-up questions in the same Codex session just to continue; let the
supervisor start the next iteration fresh.

## Handoff format

```text
Host/path/branch: <host> <pwd> <branch/worktree>
Checklist item: <TEAM_PLAN.md item or blocker>
Changed: <files>
Verified: <commands + result>
Blocked: <none or blocker>
Next: <small next task>
```

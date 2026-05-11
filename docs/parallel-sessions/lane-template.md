# Lane template

Copy this file to `docs/parallel-sessions/<lane>.md` and fill in the blanks.
The matching prompt should stay short and point here.

## Lane

- Pane: `PANE N`
- Label: `<lane>`
- Branch/worktree: `<branch or worktree rule>`
- Writable scope: `<paths this lane may edit>`
- Do not edit: `<paths owned by other lanes>`

## Goal

Describe the lane's purpose in one short paragraph. Keep detailed task lists in
this markdown file, not in `codex-prompts.txt`.

## Required reading

- `docs/parallel-sessions.md`
- `<project docs or source files>`

## Iteration cycle

1. Re-read required docs.
2. Select one small task.
3. Implement only that task.
4. Run verification: `<commands>`.
5. Record changed files and results.
6. Stop the goal when complete, blocked, or near the timebox.

## Compact-safe stop rule

Stop after one focused patch, after 30 minutes, or when blocked. Do not keep
asking follow-up questions in the same Codex session just to continue; let the
supervisor start the next iteration fresh.

## Handoff format

```text
Changed: <files>
Verified: <commands + result>
Blocked: <none or blocker>
Next: <small next task>
```

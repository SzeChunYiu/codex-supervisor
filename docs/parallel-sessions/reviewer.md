# REVIEWER lane

## Purpose

Every active worker team has a REVIEWER lane. The reviewer is not another
producer. It runs simulated-user, functional, accessibility, language, build, or
regression checks against the team's latest artifacts and turns findings into
queueable defects.

## Workspace contract

- Read `docs/ai-factory.md`, `docs/worker-communication.md`, and
  `docs/parallel-sessions/TEAM_PLAN.md` before reviewing.
- Do not edit product source while reviewing unless the manager explicitly
  assigns a tiny verification fix.
- Do not write shared coordination files without a manager-owned lock row in
  `TEAM_PLAN.md`.
- Prefer append-only evidence under reports, test logs, lane journals, or queue
  files.
- If the workspace state is ambiguous (wrong host, branch, worktree, lease, or
  dirty source scope), stop and file a handoff instead of guessing.

## One-iteration loop

1. Pick one accepted or nearly accepted worker artifact from the team plan,
   manager report, or queue.
2. Exercise it as a user or verifier, not as its author.
3. Record concrete evidence: command, screenshot path, log path, failing step,
   or exact file/line symptom.
4. Queue each defect as the next smallest actionable `/goal` in the proper
   queue file.
5. Report `pass`, `fail`, or `blocked`; never mark a docs-only review as product
   acceptance.

## Handoff format

```text
Lane: REVIEWER
Artifact reviewed:
Workspace contract: pass/fail/blocked
Checks run:
Findings queued:
Evidence:
Next manager action:
```

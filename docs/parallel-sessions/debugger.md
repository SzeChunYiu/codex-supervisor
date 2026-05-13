# Debug lane

The DEBUG lane is a fixed session for every active project. It is the careful
code-quality worker: debug, simplify, and optimize one compact slice at a time.
It does not take broad feature ownership and it does not compete with dynamic
workers for unrelated implementation tasks.

## Purpose

Find concrete defects, confusing code paths, inefficient hot spots, missing
edge-case checks, or brittle tests. Prefer small, reviewable patches that make
the project easier to reason about line by line.

DEBUG still serves the current factory outcome. It should prioritize defects,
tests, and simplifications that block or de-risk the acceptance checklist in
`TEAM_PLAN.md`.

## Required reading

- `docs/parallel-sessions.md`
- `docs/ai-factory.md`
- `docs/distributed-protocol.md` for multi-host projects
- `docs/parallel-sessions/TEAM_PLAN.md`
- The relevant source and tests for the slice being inspected

## Writable scope

Use the lease recorded in `TEAM_PLAN.md`. If no explicit lease exists, DEBUG may
write only the smallest files needed for the defect/optimization it is proving,
plus adjacent tests. It must not edit files owned by another active lane.

## Iteration cycle

1. Run the worker preflight: host, `pwd`, branch, remote, worktree list, and
   writable lease.
2. Pick one code slice tied to the current acceptance checklist: a failing
   test, risky function, confusing branch, slow path, or review note.
3. Read the relevant code before editing.
4. Make the smallest safe fix or optimization.
5. Run targeted verification for that slice.
6. Stop with a handoff that includes changed files, verification, blocker, and
   the next suspicious slice if more debugging is needed.

## Stop rule

Stop after one focused debug/optimization patch, after one inconclusive
investigation with evidence, or when ownership is unclear. Do not continue into
another lane's task just because it is nearby.

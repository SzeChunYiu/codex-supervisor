# Batch version-management system

Use this system when many AI panes are working on the same project. The goal is
to keep worker iterations small while publishing one coherent PR per accepted
batch instead of one PR for every small change.

## Core rule

**Workers create evidence and commits; the release train creates PRs.**

Individual panes may work in isolated branches/worktrees, but they do not open
review-facing PRs by default. The VALIDATOR or RELEASE_LEAD integrates accepted
worker commits into one batch branch and opens exactly one PR for the batch
outcome.

## Branch taxonomy

| Branch type | Owner | Purpose | PR policy |
| --- | --- | --- | --- |
| `main` | Human / protected repo rules | Stable accepted state. | Never edited directly by panes. |
| `batch/<date>-<slug>` | VALIDATOR or RELEASE_LEAD | Integration branch for one `TEAM_PLAN.md` batch outcome. | One review-facing PR. |
| `work/<batch>/<lane>-<task>` | Worker lane | Temporary worker branch/worktree for one leased task. | No PR unless validator requests a draft/debug PR. |
| `hotfix/<slug>` | RELEASE_LEAD | Emergency fix, revert, or security patch. | Allowed to bypass batching with explicit reason. |
| `experiment/<slug>` | Research lead | Disposable exploration that is not ready for product review. | No product PR until promoted into a batch. |

## Batch PR train

1. **Plan the train.** VALIDATOR writes the batch outcome, acceptance checklist,
   DRI rows, artifact ledger, leases, and version board before workers start.
2. **Lease work.** Each worker gets one source tree, branch/worktree, writable
   scope, and checklist ID. If ownership is unclear, the worker stops.
3. **Commit locally.** Workers make atomic commits with evidence in the message
   or handoff. They may push worker branches for backup, but they do not open
   normal PRs.
4. **Intake by evidence.** VALIDATOR/DEBUG accepts, rejects, or requests a
   follow-up for each worker commit. Accepted commits are merged or
   cherry-picked into `batch/<date>-<slug>`.
5. **Stabilize the train.** RELEASE_LEAD runs the batch verification suite,
   updates the version board, resolves integration conflicts, and verifies the
   final diff still maps to the acceptance checklist.
6. **Open one PR.** The PR title describes the batch outcome, not an individual
   worker task. The PR body links the version board, accepted checklist rows,
   artifacts, verification, known blockers, and worker branches.
7. **Merge and clean up.** After review, merge the batch PR, delete temporary
   worker branches, archive evidence, and queue only the next batch gaps.

## Version board

Every queue-backed project should keep
`docs/parallel-sessions/VERSION_BOARD.md` copied from
`templates/BATCH_VERSION_PLAN.md`. It is the release-train ledger:

- active batch branch and target base branch,
- PR grouping decision and split/exception reasons,
- worker branch intake table,
- accepted/rejected commit evidence,
- verification gates,
- final PR link and cleanup state.

## Split rules

Batching should reduce PR noise without hiding risk. Split into multiple batch
PRs only when one of these is true:

- different deploy/release order is required;
- ownership or review expertise is genuinely different;
- the diff is too large to review safely;
- a risky migration/security/live-ops change needs isolated rollback;
- a hotfix/revert cannot wait for the normal train.

Document the split reason in `VERSION_BOARD.md`. Without a split reason, queue
the work into the current batch instead of opening another PR.

## Commit and PR message policy

- Commits stay atomic and explain the why.
- Include checklist IDs when possible, e.g. `feat(factory): add batch PR board
  [A2]`.
- Preserve worker attribution in commit authorship, co-author trailers, or the
  PR manifest.
- The batch PR body is the source of truth for reviewers: outcome, included
  worker commits, verification, risks, and explicitly deferred work.

## Pane rules

- **VALIDATOR:** owns the version board, decides batch membership, rejects
  side-quest commits, and opens/updates the batch PR.
- **RELEASE_LEAD:** optional specified lead for larger trains; owns branch
  integration, final verification, PR body, merge readiness, and cleanup.
- **DEBUG:** reviews high-risk worker diffs before intake.
- **Dynamic workers:** produce one leased commit/report and hand it back; they
  do not open review-facing PRs by default.

## Existing-project rollout

For each existing supervised project:

1. Copy `templates/TEAM_PLAN.md` to `docs/parallel-sessions/TEAM_PLAN.md` if the
   project does not already have a factory board.
2. Copy `templates/BATCH_VERSION_PLAN.md` to
   `docs/parallel-sessions/VERSION_BOARD.md`.
3. Add or keep `codex-tasks/blockers.txt` and `codex-tasks/open.txt`.
4. Update the validator/lane docs to say worker branches feed the batch PR
   train and only RELEASE_LEAD/VALIDATOR opens normal PRs.
5. Run `csup factory-audit <project>` before starting more panes.

This applies the policy without rewriting every project history: old small PRs
stay as history, new work enters through the batch train.

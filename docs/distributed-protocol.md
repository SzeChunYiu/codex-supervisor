# Distributed codex-supervisor constitution

This is the constitution for any project that runs `codex-supervisor` or `csup`
on more than one possible host: laptop, local Mac, Mac mini, LUNARC, or any
future remote node. Its job is simple: keep parallel Codex sessions fast without
creating source-code ambiguity, duplicate writers, or mystery copies.

Use this file as the source document when creating or reviewing a project's
`docs/parallel-sessions.md`, lane specs, and `.codex-supervisor.toml`.

## Non-negotiable invariants

1. **One project identity.** A project has one canonical name in
   `.codex-supervisor.toml` and one canonical Git remote/trunk. Host-local
   paths are execution locations, not separate projects.
2. **No anonymous source copies.** Every source tree used by a worker must be
   one of: canonical checkout, registered Git worktree, or registered execution
   mirror. Random `cp -r`, untracked rsync clones, and "temporary" duplicate
   source directories are prohibited.
3. **One writable lease per scope.** At any time, exactly one lane owns a
   writable scope: branch, worktree, directory, module, migration, dataset
   writer, or deployment file. All other lanes treat that scope as read-only.
4. **One lane cannot run twice.** Do not run the same lane/session for the same
   project on two hosts unless one copy is explicitly marked read-only verifier.
5. **Git moves source; rsync moves artifacts.** Source changes travel through
   commits, branches, PRs, patches, or `git fetch/push`. Use rsync only for
   build outputs, datasets, logs, or a declared deployment mirror with a
   documented one-way direction.
6. **Validator-planner owns coordination, not product code.** The fixed
   VALIDATOR lane records host assignments, leases, blockers, validation
   results, and next queue items. Worker panes implement only inside their lane
   scope.
7. **Fail closed on ambiguity.** If a worker cannot prove which tree, branch,
   host, or writable scope it owns, it must stop and leave a handoff note rather
   than guessing.

## Required project files

Each supervised project should carry these files in the project's canonical
checkout:

| File | Purpose |
| --- | --- |
| `.codex-supervisor.toml` | Project name plus the only approved host stanzas. |
| `codex-prompts.txt` | Short `/goal` launch tickets only. |
| `codex-tasks/<lane>.txt` | Queue-backed work items when using `csup govern`. |
| `docs/parallel-sessions.md` | Project-local operating protocol that imports this constitution. |
| `docs/parallel-sessions/<lane>.md` | Lane lease, writable scope, branch/worktree rule, verification, handoff format. |
| `docs/parallel-sessions/TEAM_PLAN.md` | Validator-owned current host/lane assignment table and lease ledger. |

The project may add more docs, but these are the minimum files needed for a
fresh Codex pane to understand where it is allowed to write.

## Source tree classes

Use precise labels in `TEAM_PLAN.md` and lane specs.

### Canonical checkout

The human/operator-facing checkout for the project. It is where plans,
coordination docs, queue files, and final integration normally happen.

Rules:

- One canonical checkout per host at most.
- The operator may edit supervisor docs/config here.
- Write-heavy worker lanes should use registered worktrees instead of all
  editing this checkout.

### Registered Git worktree

A `git worktree` created from the canonical checkout and named in a lane spec.
This is the preferred write surface for implementation lanes.

Rules:

- One lane owns one worktree/branch at a time.
- Worktree path and branch are recorded in the lane spec or `TEAM_PLAN.md`.
- Remove or retire stale worktrees during the completion loop.

### Registered execution mirror

A host-local tree needed because execution must happen on that host, for
example LUNARC builds or SLURM-native data jobs.

Rules:

- It is declared in `.codex-supervisor.toml` as that host's `project_dir`.
- It has a declared role: `remote-writer`, `remote-executor`, or
  `read-only-verifier`.
- If it writes source, it must still use Git branch/patch flow.
- If it is a one-way deployment mirror, workers must not edit source there.

### Prohibited source tree

Any unregistered clone/copy/sync target that is not listed in the project
constitution. If a worker finds one, it may inspect it only to diagnose the
confusion, then must stop and ask the validator/operator to register, delete,
or ignore it.

## Host roles

Every host stanza in `.codex-supervisor.toml` should have one clear operational
role, even if the current `csup` parser treats the field as documentation:

```toml
[hosts."mac-mini"]
project_dir = "/Users/billy/Desktop/projects/<project>"
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "<project>-mac"
role = "local-writer"        # documentation contract

[hosts."lunarc"]
project_dir = "/projects/hep/fs10/shared/nnbar/billy/<project>"
prompts = "codex-prompts.txt"
tasks_dir = "codex-tasks"
session = "<project>-lunarc"
role = "remote-executor"     # or remote-writer / read-only-verifier
sync_policy = "git-only"     # or artifact-rsync-one-way
```

Allowed roles:

- `operator`: planning/config/docs only, no product-code lane.
- `debugger`: fixed debug/optimization lane with a narrow code-quality lease.
- `validator`: fixed validation/planning lane; writes markdown and queues
  follow-up prompts, not product code.
- `local-writer`: implementation lanes may write registered scopes locally.
- `remote-writer`: remote host may commit/patch source from registered scopes.
- `remote-executor`: remote host runs builds/tests/backfills; source is
  read-only unless a lane spec grants a branch/worktree lease.
- `read-only-verifier`: may inspect and run tests only.

Default to `local-writer` on one host and `remote-executor` or
`read-only-verifier` elsewhere. Do not use multiple `*-writer` hosts for the
same module unless the write scopes are disjoint and documented.

## Lease ledger

`docs/parallel-sessions/TEAM_PLAN.md` should contain a live table like this:

| Lane | Host | Role | Source tree | Branch/worktree | Writable scope | Status |
| --- | --- | --- | --- | --- | --- | --- |
| debug | mac-mini | debugger | registered worktree | `worktrees/debug` / `lane/debug` | one reviewed slice + tests | active |
| validator | mac-mini | validator | canonical checkout | `main` | coordination docs, queues | active |
| bugs | mac-mini | local-writer | registered worktree | `worktrees/bugs` / `lane/bugs` | `src/api/**`, tests for API | active |
| hpc | lunarc | remote-executor | execution mirror | `main` read-only | build/test outputs only | queued |

Ledger rules:

- The validator-planner updates the table before launching or queueing new lanes.
- A worker checks the table before editing.
- If two rows claim the same writable scope, both affected workers stop.
- If a host is unreachable, its leases remain reserved until the validator
  explicitly retires them or verifies the session is stopped.

## Fixed sessions and dynamic workers

Every active project has three fixed sessions:

- `DEBUG`: continuously inspects, debugs, and optimizes small code slices.
- `VALIDATOR`: validates worker results, updates markdown, and creates the next
  `/goal` prompts.

All remaining panes are either:

- dynamic workers generated from `CODEX_SUPERVISOR_DYNAMIC_WORKERS=N`, which
  consume generic open tasks such as `codex-tasks/open.txt`; or
- specified lanes named by prompt/queue when a task requires a special lease.

The validator should queue generic work into `codex-tasks/open.txt` and reserve
`codex-tasks/<lane>.txt` for tasks that truly need a specified lane.

## Operator preflight before any start

Run the smallest set of checks that proves there is no conflict:

```bash
csup hosts
csup status <project>
csup govern --dry-run --project=<project>
git -C <canonical-checkout> status --short --branch
git -C <canonical-checkout> worktree list
git -C <canonical-checkout> remote -v
```

For each remote execution mirror, verify identity before assigning source work:

```bash
ssh <host> 'cd <project_dir> && git status --short --branch && git remote -v && git worktree list'
```

Start only when the preflight proves:

- the selected host has real queued work and resource headroom;
- the lane is not already running anywhere;
- the branch/worktree/writable scope is not already leased;
- any remote `project_dir` is registered and points at the expected remote;
- source sync direction is Git or a documented one-way mirror.

## Worker preflight before editing

Every worker does this at the top of each compact-safe iteration:

1. Re-read project `docs/parallel-sessions.md`, this constitution if present,
   the lane spec, and `TEAM_PLAN.md`.
2. Print or inspect: current host, `pwd`, `git status --short --branch`,
   `git remote -v`, and `git worktree list`.
3. Confirm the lane owns the current branch/worktree and writable scope.
4. If on LUNARC or another remote host, confirm the lane role permits source
   writes. `remote-executor` and `read-only-verifier` are read-only by default.
5. If the requested task touches another lane's scope, stop and hand off.

This preflight is intentionally repetitive. Fresh Codex panes should not rely
on chat history to know whether a tree is safe.

## Source movement and sync policy

Use this decision table:

| Need | Allowed movement | Prohibited movement |
| --- | --- | --- |
| Move source change between hosts | Git branch, PR, `git format-patch`, `git fetch/push` | bidirectional source rsync |
| Seed a remote execution mirror | one documented `git clone` or one-way rsync from canonical with manifest | ad-hoc copied source trees |
| Return LUNARC build outputs | artifact rsync to an artifact/log directory | modifying local source files by rsync |
| Compare local vs remote | hashes, `git rev-parse`, manifests, `git diff --no-index` for diagnosis | assuming newer path is authoritative |

If an old remote copy is stale, do not "fix" it by editing both copies. Choose
one authority, sync in one direction, and record the decision in `TEAM_PLAN.md`.

## Conflict response

When a conflict is detected:

1. Stop the affected worker iteration.
2. Leave a handoff with host, path, branch, conflicting scope, and evidence.
3. Validator-planner decides one of:
   - retire one lane;
   - split the writable scopes;
   - move one lane to a different worktree/branch;
   - convert one host to read-only verifier;
   - merge/rebase completed work and release the lease.
4. Do not keep editing while waiting for resolution.

## Completion audit

Before declaring a distributed batch complete, the validator/operator verifies:

- every started lane has a handoff, commit, PR, artifact, or blocker;
- no lane is still running unintentionally on another host;
- `git worktree list` contains only intentional worktrees;
- dirty files are either committed, documented as handoff, or reverted by their
  owner;
- remote execution mirrors are either in sync with their declared branch or
  documented as stale/read-only;
- source changes moved by Git/patch, not by anonymous file copying;
- queues contain only intentional next tasks.

## Red flags that require stopping

- "I found another copy of the repo and edited that too."
- "Laptop and LUNARC are both on the same branch for the same lane."
- "The remote tree is not a Git checkout, but I changed source there anyway."
- "I rsynced the whole project back to local after remote edits."
- "Two panes changed the same file because tests needed it."
- "The lane spec says read-only verifier, but I made a fix there."
- "The validator table is missing or stale, but I know what to do from chat."

In every case, stop, preserve evidence, and let the validator/operator reassign
the work with a single clear source of truth.

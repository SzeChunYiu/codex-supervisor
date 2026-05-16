# Atomic Productivity Protocol

**Status:** REQUIRED for high-throughput codex-supervisor projects.

This protocol tunes parallel Codex CLI sessions for the thing the user actually
wants: faster real development, not more audits. It complements
`productivity-contract.md` and `right-sizing.md` by defining how each worker
chooses work, spends CPU/RAM, and writes prompts that finish one shippable slice
before expanding to the next atomic detail.

## Throughput loop

Every worker iteration must follow this cycle:

1. **Pick one atomic product slice.** The slice must touch a product path from
   `GOAL.md` or the lane doc and fit one compact-safe iteration.
2. **Inspect before editing.** Read the smallest relevant files and current
   tests. Do not start with a repo-wide audit unless the lane doc explicitly
   makes discovery the product deliverable.
3. **Ship the smallest working change.** Prefer code, content, data, test, art,
   or build pipeline artifacts over planning prose. Docs are allowed only when
   they unlock or record a concrete product change.
4. **Run the nearest verification.** Use the fastest command that exercises the
   changed surface, then escalate only on failure or release gates.
5. **Leave evidence and the next atom.** Append the exact files changed, command
   output, blocker if any, and one next task to the lane queue or manager note.

A manager must reject worker handoffs that contain only audits, queue grooming,
or status summaries when a product source path was available.

## Prompt engineering rules

Launch prompts stay short; the reusable behavior lives in markdown.

- Prompt line starts with `/goal`, names the pane and lane, and references this
  file plus the lane doc.
- Prompt says **real product change first** and **one atom per cycle**.
- Prompt does not include long checklists, branch policy, or architecture prose.
  Put those in lane markdown.
- Manager prompts say: accept only verified product deltas; turn broad goals into
  atomic tasks; stop or reassign idle/audit-loop panes.
- Worker prompts say: implement before auditing; avoid touching shared files
  outside lane scope; report exact evidence.

Good pattern:

```text
/goal You are PANE 2, lane COMPONENTS. Read docs/parallel-sessions/PRODUCTIVITY.md and docs/parallel-sessions/components.md; ship one verified product atom before any audit. Iterate until rate-limited.
```

## CPU and RAM rules

The supervisor already caps native helper threads per pane. Workers must keep
that advantage by avoiding accidental fan-out.

- Do not run full test/build suites by default; run nearest tests first.
- Do not launch watchers, dev servers, browsers, emulators, or Unity/Expo builds
  unless the lane explicitly needs them for the current atom.
- Use one heavy process per pane. If a build, Playwright run, Unity batchmode, or
  asset export is running, do not start another heavy command in the same pane.
- Prefer cached/package-local commands over reinstalling dependencies.
- Record heavy commands in the handoff so managers can avoid scheduling several
  heavy lanes on the same host at once.

Recommended per-pane environment remains conservative:
`UV_THREADPOOL_SIZE=2`, BLAS/OpenMP/VECLIB thread counts at `1`,
`TOKENIZERS_PARALLELISM=false`, and supervisor `nice` enabled. Raise limits only
for a measured lane with a before/after timing note.

## Atomic expansion philosophy

"Expand to every detail" does not mean opening every lane. It means repeatedly
splitting the product into the next smallest valuable atom and finishing that
atom completely:

- build the visible path, then edge cases, then tests, then polish;
- content/data: add one traceable batch, validate schema, then expand coverage;
- UI/art: ship one asset/component/screen, render it, then iterate detail;
- systems: add one API or class behavior, prove it with a focused test;
- release: clear one blocker with reproducible evidence.

Managers maintain the atom list. Workers finish atoms. CEOs compare shipped atoms
against `GOAL.md` and scale lanes only when the atom queue is deeper than current
capacity.

## Manager acceptance gate

A manager accepts an iteration only when the handoff includes:

- changed product files or a justified `[allow-meta]` infrastructure change;
- the verification command and result;
- no broad audit replacing an available implementation task;
- one next atom or a concrete blocker with evidence.

Otherwise the manager queues a correction and, after repeated audit-only loops,
stops or reassigns that pane.

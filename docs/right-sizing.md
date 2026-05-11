# Right-sizing principle

**Open the smallest pane count that fits the actual work, on the smallest set
of hosts that can hold it, and never exceed 8 panes for one project/batch.**
Running 12-20 total Codex sessions is fine only when split deliberately across
projects or hosts with measured headroom. Never default to "open every lane in
the prompts file" or "spread across both machines because we can."

This is a load-bearing operating principle for `codex-supervisor` and `csup`:
the supervisor *can* open many panes, but each pane costs ~500 MB RAM, ~10 s
of MCP boot time, a git worktree on disk, and (cumulatively) stresses tmux to
the point where the server crashes. Wrong-sizing isn't free — it directly
causes the chronic "tmux server died, all sessions lost" failure mode.

`codex-supervisor` enforces a per-session ceiling with
`CODEX_SUPERVISOR_MAX_PANES=8` by default. It also adds one planner pane by
default, projects per-pane RAM/disk before launch, lowers worker CPU priority
with `nice`, uses a lean worker `CODEX_HOME`, staggers multi-pane startup,
respawns dead panes, and recreates a missing tmux session after resource checks.
When using `csup` across hosts, the operator still must enforce a deliberate
total budget across all hosts and projects.

For queue-backed projects, prefer `csup govern --dry-run` before manual starts.
The governor reads `codex-tasks/<lane>.txt`, checks CPU/RAM/runtime-disk
headroom, and starts only queued lane subsets that fit the current host.

## Decision rule (apply at every `start`)

1. **Count the actual work.** Look at queue depth, open PRs, the backlog —
   not the maximum lane count the prompts file *could* support. If three
   queues have content and seven are empty, you need three panes, not ten.
2. **Pick the smallest host set that fits that work.** Two panes on one host
   is always cheaper than one pane on each of two hosts.
3. **Match the lane mix to the work type.** Bug-hunt PRs need `bugs` /
   `perf`. Backlog implementation needs `ux` / `data` / `test`. Don't open
   `parity` if there is no parity work in the backlog this week.
4. **Scale up only on demand.** When existing panes are saturated and a real
   queue is growing, *then* add a pane. Pre-emptively spinning up "in case"
   is a regression — measured in lost tmux servers, not gained throughput.

## How to decide concretely

Before any `csup start`:

```bash
# 1. Inspect queue depth across all lane files
wc -l <project>/codex-tasks/*.txt

# 2. Inspect open PR count (rough proxy for how much is in flight)
gh pr list --state open --base main --limit 100 | wc -l

# 3. Check current host headroom
df -h /                    # disk on the candidate host
free -h    # Linux         # RAM
sysctl vm.swapusage        # macOS swap
tmux ls                    # current supervisor sessions
```

Then choose the lane subset and host(s) accordingly. Keep each project/batch at
8 or fewer panes unless the user explicitly changes that cap after reviewing
resources. For 12-20 total sessions, spread them across hosts/projects only
when each host still has RAM/disk headroom after the per-pane budget. Justify
the choice in a one-line comment when starting (`csup start … # 3 lanes —
bugs+perf+ux backlog still has work`).

Automated path:

```bash
csup govern --dry-run
csup govern --apply
```

This uses the same rule but filters prompts with `CODEX_SUPERVISOR_LANES` and
keeps one planner pane per started session.

## When to ask the user

Only when the data is genuinely ambiguous (no recent merges, no queue
content, mixed signals). In every other case, decide and start small —
adding a pane is one command, but unwinding "I opened 10 panes and OOM'd
your machine" is much more expensive.

## What "rest mode" looks like

If after running the decision rule you find **zero work** that justifies
even one pane, the right answer is to **not start the supervisor at all**.
Leave the kill-switch (`~/.codex-supervisor.disabled`) in place. The agents
were not idle for free — they were idle because there is nothing for them
to do.

## Anti-patterns to avoid

- ❌ "The prompts file has 10 lines, so I'll open 10 panes."
- ❌ "Both machines are reachable, so I'll start on both."
- ❌ "8 panes on the Mac and 8 more on the laptop for the same project."
- ❌ "20 panes at once without a RAM/disk check because the laptop is powerful."
- ❌ "Just in case the user comes back and wants more throughput."
- ❌ "Watchdog brought it back at full size after a crash."  ← that's a bug, fix it.
- ✅ "Backlog has ~6 items in `ux`, ~2 in `perf`, nothing else open. Starting 2 panes on Mac mini, both `ux`."
- ✅ "Zero open queues, zero recent merges. Not starting anything."

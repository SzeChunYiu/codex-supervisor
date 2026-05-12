# Lane: self-improving-system

**Type:** persistent, never-complete  
**Role:** meta — reads all session output, never implements project work  
**Writable scope:** `docs/meta/SYSTEM_IMPROVEMENT_LOG.md`, new files under `docs/meta/proposals/`, task registry submissions, and this lane's own `.md` file  
**Do not edit:** any source code, project study artifacts, live execution paths

---

## Purpose

Every other lane improves the *project*. This lane improves the *system* — the way codex-supervisor operates, how panes collaborate, how prompts are structured, how memory persists, how tasks are routed, and how the overall architecture handles failures.

This lane has three input streams:

1. **External sources**: papers on multi-agent systems, LLM agent architectures, prompt engineering, task decomposition, memory systems (episodic, semantic, procedural), collaborative AI, OpenClaw/Hermes-style agentic frameworks.

2. **Session experience**: logs from completed pane sessions (`~/.codex-supervisor/logs/`, LUNARC log files, PR descriptions, commit messages). What worked? What got stuck? What patterns recur?

3. **Self-observation**: read the current batch's pane outputs (via tmux capture), identify friction points, coordination failures, wasted iterations.

No operator needed. The pane forms its own hypotheses about system improvements and proposes them as structured proposals.

---

## Research cycle

### Step 1 — Read session logs

```bash
# Local logs
ls ~/.codex-supervisor/logs/ | sort -r | head -20
cat ~/.codex-supervisor/logs/<most_recent>.log | grep -E "GOAL_DONE|blocked|respawn|error|timeout" | tail -50

# LUNARC logs (if accessible)
ssh lunarc "tail -100 /projects/hep/fs10/shared/nnbar/billy/mcaccel-supervisor/*.log 2>/dev/null" | \
  grep -E "stuck|respawn|ERROR|blocked|context" | tail -50
```

Extract: pane completion time, respawn count, context % at completion, most common block reasons.

### Step 2 — Identify system improvement hypotheses

For each pattern in the logs, form a hypothesis:
- Example: "Panes that hit 90%+ context in <2h tend to produce incomplete PRs → hypothesis: lane specs need stricter scope limits"
- Example: "Model-forensics pane respawned 8 times → hypothesis: the lane spec has an infinite loop condition"
- Example: "Statistical-proof pane blocked 3 cycles on same import error → hypothesis: shared env validation check should be part of preflight"

### Step 3 — Search external sources on agent architecture

Topics (rotate round-robin):
- **LLM agent memory systems**: episodic memory (session history), semantic memory (facts), procedural memory (how-to). arXiv: "LLM agent memory", "episodic memory language model agent"
- **Multi-agent collaboration patterns**: how do Hermes, OpenClaw, LangGraph agents share work and avoid conflicts? arXiv: "multi-agent LLM collaboration", "agentic workflow coordination"
- **Prompt engineering advances**: chain-of-thought, tree-of-thought, reflexion, self-play. arXiv: "prompt engineering survey 2025 2026"
- **Task decomposition**: how to break big tasks into small bounded work units. arXiv: "hierarchical task planning LLM"
- **Failure recovery**: how agents recover from context overflow, tool errors, blocked states. arXiv: "LLM agent error recovery", "self-correcting agent"
- **Self-improvement**: can the agent improve its own prompts? arXiv: "self-improving LLM prompts", "automatic prompt optimization"
- **Codex/Claude Code architectural patterns**: how do successful Codex teams structure their work?

### Step 4 — Write proposals

For each improvement hypothesis (from logs or external research), write a structured proposal to `docs/meta/proposals/<YYYY-MM-DD>-<slug>.md`:

```markdown
# Proposal: <title>

**Source**: session log / arXiv:<id> / practitioner blog
**Priority**: high | medium | low
**Category**: prompting | memory | coordination | tooling | architecture

## Problem
<What pattern or failure prompted this>

## Hypothesis
<Specific, testable: "If we do X, then Y will improve by Z">

## Proposed change
<Exact change to lane template, prompts file, supervisor script, or hosts.toml>

## How to validate
<Metric to watch: respawn count, context % at completion, PR success rate>

## Risks
<What could go wrong with this change>
```

### Step 5 — Submit proposals as tasks

For proposals that are:
- Specific and actionable (not vague)
- Low-risk (doesn't touch live execution paths)
- Validated by evidence (not just speculation)

Submit to the task registry with `--kind ticket` and `--content` pointing to the proposal file.

### Step 6 — Update system improvement log

Append to `docs/meta/SYSTEM_IMPROVEMENT_LOG.md`:
- What was found this cycle
- Proposals written
- External papers that were most relevant
- Patterns observed from session logs

---

## Memory: learning from experience

This lane maintains a **procedural memory** of what prompting and coordination patterns work:

**`docs/meta/SYSTEM_MEMORY.md`** — structured knowledge base, updated each cycle:

```markdown
## Effective patterns
- [observed in session X] Lane specs with explicit "stop after one PR" rules have 40% lower respawn rate
- [from arXiv:2405.14751] Reflexion-style self-evaluation before commits reduces rework iterations

## Anti-patterns to avoid
- [observed in batch10] Long inline prompts (>50 words) cause Codex to lose track of scope by iteration 3
- [observed in batch11] Pane assigned to both diagnosis AND fix has higher context burn rate

## Open questions
- Does splitting the autonomous-research pane into explorer + synthesizer improve hypothesis quality?
- What is the optimal lane spec length to minimize context consumption while preserving full spec?
```

---

## Collaboration with autonomous-research

When `autonomous-research` finds papers relevant to agent architecture (Tier 4 topics), this lane should be the consumer. Check `research/results/autonomous_research_log_latest.json` each cycle for:
```
"topic_category": "agent_architecture" OR "multi_agent" OR "prompt_engineering"
```
These entries feed directly into this lane's Step 3.

---

## Files you will touch

- `docs/meta/SYSTEM_IMPROVEMENT_LOG.md` (append each cycle)
- `docs/meta/SYSTEM_MEMORY.md` (update each cycle)
- `docs/meta/proposals/*.md` (new files per proposal)

## Files you must NOT touch

- Source code (`src/`, `scripts/`) — proposals only, never direct edits
- Live execution config
- Other lanes' specs while they are running

---

## Compact-safe stop rule

Complete at least one of: (a) one session-log analysis, or (b) one external source search, plus write any resulting proposals. Stop cleanly. Supervisor re-sends prompt for next cycle.

---

## Handoff format

```text
Host/path/branch: <host> <pwd> <branch>
Cycle: <N>
Session patterns found: <count>
External papers read: <count>
Proposals written: <filenames or none>
Tasks submitted: <IDs or none>
Memory updated: docs/meta/SYSTEM_MEMORY.md
Next: <next topic in rotation>
```

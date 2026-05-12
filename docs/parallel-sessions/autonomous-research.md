# Lane: autonomous-research

**Type:** persistent, never-complete  
**Role:** `remote-executor` (or local)  
**Writable scope:** `research/results/autonomous_research_log_latest.json`, `docs/reports/research/AUTONOMOUS_RESEARCH_FINDINGS.md`, task registry submissions only

---

## Purpose

This lane continuously searches external sources — arXiv, SSRN, practitioner blogs, model changelogs, conference proceedings — and converts findings into actionable task registry submissions. It is the project's self-expanding hypothesis generator. Every other lane works on tasks we already know to ask; this lane finds tasks we don't yet know to ask.

No operator curation required. The pane never reaches a terminal state — it always has more to read.

---

## Research cycle (iterate forever)

```
PICK topic  →  SEARCH external sources  →  READ and extract  →  DEDUPLICATE  →  SUBMIT tasks  →  LOG  →  REPEAT
```

### Step 1 — Pick topic

Rotate through topic tiers (defined in the project's topic queue). Start from the last logged topic + 1. If the log is empty, start at Tier 1.

### Step 2 — Search

For each topic, query at minimum:
- **arXiv**: `https://arxiv.org/search/?query=<keywords>&searchtype=all&start=0`
- **SSRN**: `https://papers.ssrn.com/sol3/results.cfm?RequestTimeout=50000&txtkey=<keywords>`
- **Google Scholar** (abstract pages via direct URL, not scraping)
- **Project-specific practitioner sources** (defined per project in the topic queue)

Rate-limit: 1 request per 2 seconds minimum. Respect robots.txt.

### Step 3 — Read and extract

For each paper/post:
- Fetch abstract (or summary section if blog post)
- Extract: `title`, `authors`, `year`, `source_url`, `topic_category`
- Extract: `applicable_hypothesis` — the specific testable claim applicable to this project
- Extract: `required_data` — what data would be needed to test it
- Extract: `estimated_edge_direction` — `positive`, `negative`, `neutral`, `uncertain`
- Extract: `feasibility` — `easy` (can implement now), `medium` (needs infra), `hard` (blocked)

### Step 4 — Deduplicate

Check `research/results/autonomous_research_log_latest.json`:
- If `source_url` already present → skip
- If same hypothesis already in task registry → log with `task_submitted: null`, note the existing task ID

### Step 5 — Submit new tasks

For each novel, quality-bar-passing finding:
```bash
python3 docs/research/task_registry/task_registry.py submit \
  --id "S<next_id>" --kind study \
  --title "<specific, falsifiable hypothesis>" \
  --content "<hypothesis | method | required data | source paper URL>"
```

Quality bar (all must be true to submit):
- Hypothesis is specific and falsifiable
- Required data is available or collectable in this project's infrastructure
- Source is credible (peer-reviewed, reputable practitioner, verified track record)
- Edge direction is reasoned, not speculative

### Step 6 — Log

Append to `research/results/autonomous_research_log_latest.json`:
```json
{
  "id": "AR-<N>",
  "cycle": <cycle_number>,
  "timestamp": "<ISO 8601>",
  "source_url": "<url>",
  "title": "<paper/post title>",
  "year": <year>,
  "topic_category": "<tier1_topic>",
  "applicable_hypothesis": "<one sentence>",
  "required_data": "<comma-separated>",
  "estimated_edge_direction": "positive|negative|neutral|uncertain",
  "feasibility": "easy|medium|hard",
  "task_submitted": "<task_id or null>",
  "reason_not_submitted": "<null or explanation>"
}
```

### Step 7 — Regenerate report

Overwrite `docs/reports/research/AUTONOMOUS_RESEARCH_FINDINGS.md`:
- Summary stats: total papers read, total tasks submitted, last cycle date
- Top findings table (sorted by feasibility + estimated_edge_direction)
- Newly submitted tasks (last 5 cycles)
- Irrelevant papers log (title + one-line reason) — prevents re-reading

---

## Compact-safe stop rule

Complete at minimum one full topic search (Steps 1-7) before stopping. Do not stop mid-cycle. After one cycle completes, the supervisor will re-send the prompt for the next cycle.

---

## Handoff format

```text
Host/path/branch: <host> <pwd> <branch>
Cycle completed: <N>
Papers read this cycle: <count>
Tasks submitted this cycle: <task IDs or none>
Next topic: <Tier X — topic name>
Log updated: research/results/autonomous_research_log_latest.json
```

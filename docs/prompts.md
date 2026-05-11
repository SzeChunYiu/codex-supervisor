# Prompt contract

Use `codex-supervisor` prompts as launch tickets, not as full specs. Every
non-comment line in `codex-prompts.txt` must obey this contract:

1. Start with `/goal` exactly.
2. Stay at or below 50 whitespace-separated words.
3. Reference at least one `.md` file.
4. Put every extra instruction, guardrail, checklist, and stop rule in markdown.
5. Keep one prompt per line; never paste multi-line instructions into the prompt file.
6. Keep the final pane count within `CODEX_SUPERVISOR_MAX_PANES` (default 8).
   By default the supervisor appends one generated `PLANNER` lane if no
   planner/leader lane exists, so leave room for it or define your own planner
   prompt. Start fewer worker lanes when the actual queue or host resources are
   smaller. For 12-20 total workers, split across multiple right-sized
   projects/hosts rather than one oversized prompt file.

Recommended shape:

```text
/goal You are PANE 0, lane BUGS. Read docs/parallel-sessions.md and docs/parallel-sessions/bugs.md, then complete one compact-safe iteration.
```

Why this contract exists:

- Short `/goal` lines survive TUI typing and resend reliably.
- Markdown specs are re-readable at every iteration and can change without
  restarting the supervisor.
- Small launch tickets reduce the chance that Codex reaches context compaction.
- Fresh Codex sessions can understand the lane by reading files instead of
  inheriting long chat history.

Validate before starting:

```sh
CODEX_SUPERVISOR_PROMPTS=codex-prompts.txt ./codex-supervisor.sh validate-prompts
```

If validation fails, shorten the `/goal` line or move details into the shared or
per-lane markdown file.

# Latest system live check — 2026-05-14

Question: are the jobs running with the latest system of work?

## Criteria

A project is considered on the latest system when:

1. Its CEO steering plan exists in the active project directory.
2. Its manager/meta prompts explicitly reference the CEO steering plan and meta queue.
3. Its manager panes are running now, or an existing manager layer is deliberately retained because adding panes would reduce efficiency.
4. Worker expansion is right-sized and not started when disk/capacity/resource evidence says no.

## Results

| Project | Latest CEO docs deployed | Latest manager prompts deployed | Manager panes running | Verdict |
|---|---:|---:|---:|---|
| neural_grow | yes | yes: `codex-prompts-meta.txt` now reads `docs/CEO_STEERING_PLAN_2026-05-14.md` and `codex-tasks/meta/ceo-steering.txt` | yes: `ng-meta-lunarc` has 2 live panes | YES |
| babbloo | yes | yes: `codex-prompts-laptop-meta.txt` now reads `docs/CEO_STEERING_PLAN_2026-05-14.md` and `codex-tasks/meta/ceo-steering.txt` | yes: `babbloo-laptop-meta` has 2 live panes; 7 workers still running | YES |
| nnbar | yes | yes: `codex-prompts-meta.txt` now reads `docs/CEO_STEERING_PLAN_2026-05-14.md` and `codex-tasks/meta/ceo-steering.txt` | yes: `nnbar-meta-lunarc` has 2 live panes | YES |

## Evidence commands run

- LUNARC socket check: `ssh -O check lunarc` returned connected.
- Direct tmux checks:
  - `ng-meta-lunarc`: two live `node` panes.
  - `babbloo-laptop-meta`: two live `node` panes.
  - `nnbar-meta-lunarc`: two live `node` panes.
- Status checks showed:
  - Babbloo: 7 worker panes + 2 laptop-meta panes.
  - NNBAR: existing worker fleet + 2 meta panes.
  - Neural grow: worker fleet plus restarted `ng-meta-lunarc` meta panes.

## Caveats

- LUNARC status commands still print the known `flatpak/libmount` warning; it does not prevent tmux pane verification.
- Babbloo LUNARC named sessions are not running, but Babbloo is intentionally using the verified laptop manager layer because it is accessible and right-sized.
- Mac-mini expansion remains skipped due low root disk/capacity.

## Conclusion

Yes. The running jobs now have the latest CEO/manager system wired into active steering docs, meta queues, updated manager prompts, and verified live manager panes.

# Dashboard company office UI — 2026-05-14

## Objective

Make `localhost:7777` clearly show company structure: who is CEO, who is manager/planner, and who is worker. Add a pixel-art virtual office view for the AI teams.

## Implementation

Updated `csup-dashboard` frontend only:

- Added a portfolio-level `AI company HQ` view on the overview page.
- Added a per-project `<project> AI company office` section above raw terminal panes.
- Added role classification:
  - CEO: real Codex/tmux `CEO` lane; the dashboard shows a missing-CEO warning
    instead of inventing a virtual CEO when no real pane exists.
  - Manager: DEBUGGER, VALIDATOR, manager/meta/debug lanes.
  - Planner: planner lanes.
  - Worker: normal implementation/research/QA lanes.
- Added pixel-art office styling:
  - Executive office.
  - Managers + planners row.
  - Worker floor.
  - Pixel avatars, status lights, role chips, office floor grid.

## Agent-office reference

I checked the GitHub repository `harishkotra/agent-office` (description: real-time pixel art agents in an office). I did not vendor/copy its code into `csup-dashboard`; instead I implemented a lightweight native dashboard version that maps our real tmux panes into CEO/manager/planner/worker office seats. This keeps localhost:7777 single-file, fast, and directly tied to the current supervisor state.

## Verification

- `python3 -m py_compile csup-dashboard` passed.
- `tests/test_dashboard_company_office.sh` passed.
- Restarted `csup-dashboard` on port `7777`.
- Browser verification on `http://127.0.0.1:7777` confirmed:
  - Overview title: `AI company HQ`.
  - Legend roles: `CEO`, `Manager`, `Planner`, `Worker`.
  - Portfolio cards show project CEOs and managers.
  - `babbloo` project page shows `babbloo AI company office` with Executive office, Managers + planners, and Worker floor.

## Caveat

This is a structural visualization layer; it does not replace the raw pane cards below it. Operators can use the office diagram first, then inspect individual terminal panes underneath.

## Motion update from agent-office request

After inspecting `harishkotra/agent-office` (MIT license), the dashboard office was upgraded to match the requested moving-agent feel without adding a Phaser/React dependency:

- Office people now walk with CSS `office-walk` motion.
- Pixel avatars step with `avatar-step` animation.
- Emote bubbles pulse with `office-emote` (`♛`, `☰`, `◇`, `…`, `✓`, `⏳`).
- Movement is deterministic per real pane, so each agent has a stable path but still visibly moves.
- Browser verification confirmed a worker card transform changes over time (`moved: true`) and animations are active.

This keeps the dashboard fast and single-file while adopting the visible agent-office style: real panes represented as moving pixel agents in an office.

## Sprite asset upgrade

The office now embeds the actual MIT-licensed `char_0.png` through `char_5.png` sprites from `harishkotra/agent-office` as data URIs. Each real tmux pane is assigned a deterministic character sprite. The avatar animation uses the same sheet geometry as agent-office (`16x32` frames scaled up), with `sprite-walk-down` cycling through walk frames while the seat card moves around the office floor.

Extra realism added:

- Desk/furniture floor overlays in each office zone.
- Multiple real character sprites instead of CSS block people.
- Sprite-frame animation verified in browser: background-position sampled `0px`, `-32px`, and `-64px` over time.
- Third-party MIT license copied to `docs/third-party/agent-office/LICENSE`.

## AgentOffice v2 style pass

The office visualization was upgraded again to better match the existing AgentOffice visual identity:

- Reworked office sections into top-down 16px-grid pixel maps rather than plain cards.
- Added functional zones and props: work desks, meeting room, collaboration whiteboards, coffee/pantry, decorative corners, laptops, monitors, keyboards, mugs, notepads, plants, bookshelves, printer, and water cooler.
- Changed agents into movable sprite containers with nameplates, role labels, status lights, emote bubbles, and compact thought bubbles.
- Added state-aware animation: active agents use 3-frame walk loops at roughly 8 FPS, while stopped/idle/offline agents hold a still sprite frame.
- Kept the style dark, cozy, UI-focused, pixelated, and readable at 2x zoom with hard edges and soft neon accents.

This remains a native dashboard implementation rather than a Phaser port: the CSS/DOM layer now intentionally mirrors AgentOffice's office-map style while staying single-file and tied to live `csup` pane state.

## Directional sprite pass

The active agents now choose deterministic facing directions. Down-facing agents use the down walk strip, while horizontal agents use the right-walk strip from the sprite sheet and flip it with `scaleX(-1)` for left movement. Hover/focus adds a small neon focus ring so the selected agent reads like a game entity without changing the underlying terminal-pane data model.

## Seat-plan and meaningful workflow animation pass

The office animation was refined after the small-wander issue: workers no longer drift randomly around the floor while supposedly working. The worker area now follows a Japanese-company-style team seating plan with two long shared desks and assigned chairs. Active workers stay at their own chair/desk and use a small typing/desk-work animation instead of walking in place.

New workflow semantics:

- Workers are assigned deterministic `team-long-desk-chair` seats.
- Worker desks are drawn as long team benches with individual chairs, laptops/monitors, and a visible route line.
- The manager/planner area has a `manager-review-desk` and the worker floor has a `manager-handoff` review point near that boundary.
- A `goal-done` worker uses `worker-submit-route`: leave chair, walk along the grid route to the review/handoff point, pause as if submitting work, then return to the same chair.
- Normal `working` workers stay seated and show `office-desk-work` / `office-typing`, so the animation now communicates actual work rather than aimless movement.

Browser verification on `http://127.0.0.1:7777/project/babbloo` confirmed workers render as `team-long-desk-chair at-seat`, have `working at desk` thoughts, do not wander away from their desk while working, and the simulated submit route moves through multiple grid positions toward the review point.

## Japanese shima seating realism pass

Refined again after checking Japanese office-layout references. The key visual rule is now the traditional Japanese `shima` island: desks are pushed together by section/team, workers sit facing each other across the island, and the manager/section-chief seat is at the end where the whole island is visible. References used:

- MANABINK notes that traditional Japanese offices use open rooms with desks pushed together by section as a `shima` island for collaboration and horenso reporting.
- Office-Com's desk-layout guide describes the `対向型（島型）` layout as Japan's most orthodox team layout, with desks facing each other and the manager usually seated at the island end to see the whole team.

Implementation changes:

- Worker floor now draws one shima island instead of two unrelated rows.
- Workers have top-row and bottom-row assigned chairs, facing each other across the long desk.
- Working workers are visually seated: their sprite is clipped/lowered behind the chair/desk and uses small `office-typing` / `office-desk-work` motion only.
- The section-manager endpoint is now inside the worker floor as `section-manager-desk` plus `section-manager-chair`.
- The only walking workflow for workers is `goal-done`: `worker-submit-route` goes from assigned seat to the section manager/handoff point, pauses, then returns.
- Background scene was improved with a darker wall band, better blue-purple floor texture, shima desk divider, night window, low storage, and stronger pixel furniture highlights.

Browser verification confirmed a seated worker has `seated-at-desk at-seat`, `working at desk`, avatar height `48px`, clipped lower body, and near-zero seat delta while working. A simulated completed worker moved through multiple route positions to the section-manager handoff route.

## One-shot handoff and seat-alignment correction

The previous CSS still allowed completed workers to keep looping the submit route, which looked like meaningless pacing. This pass makes handoff event-based:

- `goal-done` workers trigger `worker-submit-route` only once per pane transition.
- The dashboard tracks seen handoffs with `OFFICE_HANDOFF_SEEN` / `OFFICE_HANDOFF_ACTIVE_UNTIL` so repeated refresh polls do not restart the walk forever.
- After the one-shot route finishes, the worker returns to `seated-at-desk at-seat` even if the pane remains `goal-done`.
- The route animation now has `animation-iteration-count: 1` and ends back at the assigned chair.
- Seat/prop alignment was tightened: the shima island is one shared desk bank, top and bottom chairs align to the worker sprite coordinates, and laptop/keyboard props are placed on the same desk surface rather than floating between rows.

Browser verification after waiting for the route window to settle confirmed `submittingRoutesAfterSettling: 0`, all visible workers are seated, a seated worker has a clipped 48px sprite body, and the worker stays at its assigned seat while working.

## Screenshot-driven product polish pass

I captured the actual rendered `babbloo` office at 1440x950 and used the screenshot to fix the parts that still looked like marker-driven graphics rather than a coherent product scene.

Visual changes from the screenshot audit:

- Enlarged the worker zone so the shima island has breathing room instead of crowding sprites into one corner.
- Repositioned workers and chairs to wider, regular intervals across the island.
- Repositioned desk props so laptops, monitors, and keyboards sit on the desk plane rather than between seats.
- Hid thought bubbles by default; they now appear on hover/focus or during a handoff, reducing visual clutter.
- Tightened nameplates so labels are smaller and less overlapping.
- Added a subtle `SECTION TEAM SHIMA` floor label and kept the section-manager desk at the left end of the island.

Verification included a before/after screenshot saved locally:

- `docs/ceo-steering/assets/2026-05-15-office-before-product-grade.png`
- `docs/ceo-steering/assets/2026-05-15-office-after-product-grade.png`

The after screenshot shows a more coherent three-zone office: executive room, manager/planner room, and a larger worker shima island with aligned chairs, desk props, and seated agents.

## Team-structure and no-overlap correction

The next screenshot audit found the real problem: the office had sprites packed too tightly and the hierarchy was visually implicit. This pass makes both constraints explicit:

- Agent containers were narrowed from card-like 80px blocks to compact 48px map entities so adjacent sprites no longer collide.
- Manager seats were spread further apart in the manager/planner room.
- Worker shima seats were spread at wider regular intervals across the island.
- The office now renders a visible `team-structure` strip above the map: `CEO pane → Manager panes → Worker panes`.
- The strip lists the live panes and their states, matching the terminal cards below. The CEO is shown separately as the project-level direction role, while manager/worker panes are real captured tmux panes.
- New screenshot: `docs/ceo-steering/assets/2026-05-15-office-team-structure-no-overlap.png`.

Browser verification on `babbloo` confirmed: 11 office agents (10 real panes plus project CEO), 10 terminal panes below, zero measured agent overlaps, team-structure nodes for CEO/manager/worker, and no looping worker submit routes after settling.

## Agent-office repo recheck: what was missing

I refreshed `/tmp/agent-office` from `harishkotra/agent-office` and compared the dashboard against its current UI/game implementation. Important repo behaviors checked in `packages/ui/src/game/Game.ts`:

- AgentOffice stores each agent as a single container: focus ring, sprite, thought bubble, emote bubble, and label move together.
- It uses 16px grid coordinates and tweens containers to new cell positions.
- Walk animations are directional: right walk, flipped right walk for left, up walk, down walk.
- Sprites stop when movement completes.
- Emotes are temporary, while thought bubbles are compact overlays.
- A selected/focused agent gets a visible ring.

Dashboard gaps found and addressed in this pass:

- Our DOM agents had 80px layout boxes, so their bounding boxes overlapped even when sprites looked small. Fixed by reducing map agent containers to compact 48px entities and spreading seats.
- The hierarchy was implicit in room labels only. Fixed by adding a live `team-structure` strip: `CEO pane → Manager panes → Worker panes`, with the exact pane names and states synced from the terminal cards below.
- Manager and worker seats were still too close. Fixed by spreading manager seats and worker shima seats so the browser overlap audit reports zero overlaps.
- Handoff routes were already one-shot, and verification confirms no worker submit route remains active after settling.

## Team-sorted animation map correction

The office map was still organized by hierarchy (`CEO / managers / workers`), while the terminal pane cards below are grouped by actual team/session. This pass changes the animation area to follow the same team ordering as the TUI panes:

- The animated office map now renders `team-sorted-office` zones, one per captured instance/session.
- Each team zone lists agents in the exact pane order used by the terminal cards below.
- Role is still visible through each agent's role label/color, but role no longer controls the primary spatial grouping.
- The structure strip remains above the map for leadership context, but the animation floor itself is team-first.
- Pane fallback labels were normalized from `pane-3` to `pane3` so office labels match TUI labels exactly.

Browser verification on `babbloo` confirmed `officeMatchesPaneOrder: true`, zero measured overlaps, two team-sorted zones (`Team laptop · babbloo-laptop`, `Team laptop-meta · babbloo-laptop-meta`), and the office agent order exactly matches the terminal pane order below.

## CEO TUI visibility correction

The CEO role was visible in the animated structure, but an earlier dashboard
iteration used a virtual/project-level CEO card. That was wrong: the CEO must be
a real Codex/tmux pane.

The corrected dashboard now renders a `ceo-session-summary-pane`:

- If a real `CEO` lane exists, it lists the real host, session, pane index,
  lane, and state.
- If no real `CEO` lane exists, it shows `CEO Codex session missing` and tells
  the operator to restart with generated fixed roles enabled.
- The summary card states the CEO duty: review manager reports, communicate
  direction, and queue executive decisions.
- The regular terminal pane grid below remains the source of truth for the real
  CEO pane tail.

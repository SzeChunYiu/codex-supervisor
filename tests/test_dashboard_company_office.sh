#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DASHBOARD="${CSUP_DASHBOARD:-$ROOT/csup-dashboard}"

for needle in \
  'company-office' \
  'AI company HQ' \
  'team-sorted pixel office view' \
  'same order as TUI panes below' \
  'team-structure' \
  'CEO pane' \
  'Manager panes' \
  'Worker panes' \
  'same panes as terminal cards below' \
  'team-sorted-office' \
  'team-sorted-zone' \
  'team-pane-order' \
  'team-tui-pane-order' \
  'teamPaneRoleRank' \
  'sortTeamPaneItems' \
  'pane-role-badge' \
  'role-manager' \
  'role-worker' \
  'Manager pane: debugs, validates, accepts work and routes workers' \
  'Worker pane: executes one bounded task' \
  'Manager panes are shown first' \
  'Team ' \
  'gm-session-summary-pane' \
  'Real CEO Codex session' \
  'projectGmState' \
  'dashboard no longer fabricates a virtual CEO' \
  'CEO duty: decide which teams to open' \
  '16px-grid top-down pixel coworking map' \
  'office-zone' \
  'office-decor' \
  'work-desks' \
  'meeting-room' \
  'collaboration-area' \
  'coffee-pantry' \
  'decorative-corner' \
  'team-long-desk' \
  'Japanese shima island' \
  'shima-seat' \
  'section-team-seat' \
  'section-manager-desk' \
  'section-manager-chair' \
  'section-manager-only-route' \
  'SECTION TEAM SHIMA' \
  'office-zone.workers::after' \
  'face-up' \
  'seated-at-desk' \
  'office-window' \
  'low-storage' \
  'worker-chair' \
  'manager-review-desk' \
  'manager-handoff' \
  'submit-path' \
  'team-long-desk-chair' \
  'agent-thought' \
  'worker-submit-route' \
  'OFFICE_HANDOFF_SEEN' \
  'OFFICE_HANDOFF_ACTIVE_UNTIL' \
  'officeShouldRunHandoff' \
  'submitted · seated' \
  'submitting to section manager' \
  'office-desk-work' \
  'office-typing' \
  'at-seat .pixel-avatar.sprite-avatar' \
  'pixel office view' \
  'office-walk' \
  'avatar-step' \
  'office-emote' \
  'AGENT_OFFICE_CHARACTER_SPRITES' \
  'sprite-walk-down' \
  'sprite-walk-right' \
  'face-left' \
  'face-right' \
  'sprite-avatar' \
  'agent-office sprite' \
  'companyRoleForLane' \
  'renderPortfolioCompanyOffice'; do
  grep -Fq "$needle" "$DASHBOARD" || { echo "missing dashboard company office marker: $needle" >&2; exit 1; }
done

echo "ok: dashboard renders company org / pixel office markers"

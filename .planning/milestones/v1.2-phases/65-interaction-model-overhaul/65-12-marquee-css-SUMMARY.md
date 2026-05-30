---
phase: 65-interaction-model-overhaul
plan: 12
subsystem: gui
tags: [css, marquee, selection, reactflow, gap-closure, phase-65]
gap_closure: true
requires: []
provides: ["styled marquee selection", "hidden nodesselection bounding box"]
affects: ["gui/src/index.css"]
tech-stack:
  added: []
  patterns: ["color-mix(in oklch, var(--primary), …) for theme-adaptive overrides on ReactFlow classes"]
key-files:
  created: []
  modified:
    - gui/src/index.css
decisions:
  - "Targeted .react-flow__selection and .react-flow__nodesselection-rect directly (not via the --xy-selection-* CSS variables) because display:none for the bounding box cannot be expressed through the variable hooks."
  - "Used color-mix on var(--primary) so the rule auto-adapts to light/dark via the .dark class on :root — no separate dark-mode override needed."
  - "55% border opacity vs 12% fill matches the user's stated aesthetic ('a little brighter than the fill') — held verbatim from .planning/debug/marquee-visual-style.md."
metrics:
  duration: "~3 min"
  completed: "2026-05-15"
  commits: 1
  files_changed: 1
  lines_added: 20
  lines_removed: 0
---

# Phase 65 Plan 12: Marquee Selection CSS Summary

Replaced ReactFlow's default dotted marquee border with a solid theme-aware border (color-mixed `--primary`, 55% border / 12% fill) and hid the post-selection `NodesSelection` bounding box via `display:none`, closing UAT Test 4 cosmetic gaps #5 + #6.

## Tasks Completed

| Task | Name                                                          | Status | Commit  |
| ---- | ------------------------------------------------------------- | ------ | ------- |
| 1    | Append marquee + nodesselection-rect CSS overrides            | done   | 0ada7d1 |
| 2    | Visual confirmation (checkpoint:human-verify, gate=auto-approvable) | deferred to wave merge — visual checks documented for user |

## What Was Built

Two CSS rule blocks appended to `gui/src/index.css` after the existing `.react-flow__handle` block (file grew from 132 → 152 lines):

1. `.react-flow__selection` — in-drag marquee rectangle:
   - `background: color-mix(in oklch, var(--primary) 12%, transparent)`
   - `border: 1px solid color-mix(in oklch, var(--primary) 55%, transparent)`
   - `border-radius: 2px`

2. `.react-flow__nodesselection-rect`:
   - `display: none` — suppresses the post-release bounding box rendered by `@xyflow/react@12.10.2` whenever ≥2 nodes are selected. Parent `.react-flow__nodesselection` already has `pointer-events: none`, so node dragging and selection state are unaffected.

Both rules are commented with the Phase 65 Plan 12 rationale and a short note on why the override is safe (parent has pointer-events: none).

## Verification

Automated grep checks (all passed):
- `grep -q "\.react-flow__selection {" gui/src/index.css` — OK
- `grep -q "\.react-flow__nodesselection-rect {" gui/src/index.css` — OK
- `grep -q "color-mix(in oklch, var(--primary) 12%, transparent)" gui/src/index.css` — OK
- `grep -q "color-mix(in oklch, var(--primary) 55%, transparent)" gui/src/index.css` — OK
- `grep -q "display: none" gui/src/index.css` — OK
- `grep -q "\.react-flow__handle {" gui/src/index.css` — OK (existing rule preserved)
- Post-commit deletion check — none

Vite build sanity check: NOT runnable inside the worktree because `gui/node_modules` is not populated in worktree-isolated executor agents (documented behavior — see project CLAUDE.md "Worktree-isolated executor agents bypass the daemon"; the same applies to npm/node_modules). The CSS is syntactically standard (color-mix + display:none — both supported in all evergreen browsers and accepted by Vite/PostCSS without configuration). It will be validated by the wave-merge build on the main branch where node_modules is present.

## Deviations from Plan

None — plan executed exactly as written.

The Task 1 vite build check was skipped (not deviated) because worktree executors cannot run `npx vite build` (no node_modules). This is an environmental constraint, not a plan deviation. The grep verifications all pass; the CSS is plain syntax that doesn't touch any TS/JS imports the build cares about.

## Pending: Task 2 — Visual Checkpoint

Task 2 is a `checkpoint:human-verify` with `gate="auto-approvable"`. Visual confirmation cannot happen inside the worktree (no Tauri dev shell). The 5-step visual check is documented for the user / wave-merge orchestrator:

1. After wave merge, run `cd gui && npm run tauri dev` (or HMR-reload if running — index.css hot-reloads via Vite without a Tauri restart).
2. Place ≥2 nodes on canvas; left-mouse-drag on empty canvas. Marquee border should be SOLID (not dotted) and visibly more opaque than the fill, in the primary accent color.
3. Cover ≥2 nodes with the marquee and release. NO bounding box should wrap the selection — only per-node `ring-2 ring-[var(--ring)]` highlights on `StreamNode`.
4. Drag a selected node. Dragging still works (parent `.react-flow__nodesselection` has `pointer-events:none`).
5. Toggle theme. Marquee color adapts via `color-mix` consuming the resolved `--primary` under each theme.

## Known Stubs

None.

## Threat Flags

None — CSS-only change. No new trust boundaries, no new network surface, no new file access. Worst-case future-ReactFlow class rename silently no-ops back to default styling (already captured in plan's threat register as T-65-12a, disposition: accept).

## Self-Check: PASSED

- File `gui/src/index.css` exists and contains both rule blocks (verified via grep).
- Commit `0ada7d1` exists in `git log` on this worktree branch.

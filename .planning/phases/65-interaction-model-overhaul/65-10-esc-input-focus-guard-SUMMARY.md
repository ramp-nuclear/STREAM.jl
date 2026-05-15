---
phase: 65-interaction-model-overhaul
plan: 10
subsystem: gui-sidebar
tags: [selection, esc-handler, sidebar, gap-closure, phase-65]
gap_closure: true
requires: [65-03]
provides:
  - sidebar-esc-input-focus-guard
affects:
  - gui/src/components/sidebar/SidebarPanel.tsx
tech_stack:
  added: []
  patterns:
    - input-focus-guard
key_files:
  created:
    - gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx
  modified:
    - gui/src/components/sidebar/SidebarPanel.tsx
decisions:
  - "Mirror CanvasPanel.tsx:266-275 input-focus guard verbatim — single canonical guard idiom shared between the two document-level Esc listeners."
  - "Keep both Esc handlers (CanvasPanel + SidebarPanel) — they own different state sources (ReactFlow per-node `selected` flag vs zustand selection slice) and must both early-return on the same target predicate for the slices to stay in lockstep."
metrics:
  duration: "~6 minutes"
  completed_date: "2026-05-15"
  tasks_completed: 1
  files_created: 1
  files_modified: 1
  commits: 2
---

# Phase 65 Plan 10: Esc input-focus guard in SidebarPanel — gap closure Summary

Added the missing input-focus guard to `SidebarPanel.tsx`'s document-level Esc keydown listener, mirroring the canonical guard already present in `CanvasPanel.tsx:266-275`. Esc inside a text input is now a no-op for selection state, so the zustand selection slice and ReactFlow's per-node `selected` flag stay in lockstep (UAT Test 7 desync closed).

## What Changed

### Production code

- `gui/src/components/sidebar/SidebarPanel.tsx` (handler block at L74-103) — inserted the four-arm guard (`HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable`) between the existing `defaultPrevented` / `key !== "Escape"` early returns and the `selectionKind !== "none"` clear call. Updated the surrounding comment block to cite the Plan 10 fix and the CanvasPanel reference.

### Tests

- `gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx` (new, 4 cases):
  1. Esc inside a focused `<input>` (real InstanceNameField textbox) → `selectionKind === "component"` (NOT cleared).
  2. Esc with no input focused → `selectionKind === "none"` (cleared — regression guard for the existing canonical path).
  3. Esc inside a focused `<textarea>` → not cleared (edge — same guard arm).
  4. Esc inside a focused `contentEditable` div → not cleared (edge — same guard arm).
  - Helper `dispatchEscOn(el)` dispatches a bubbling keydown from the focused element (mirrors real-browser bubbling so `e.target` is the focused input, not document) — bubbling reaches the document-level listener naturally.

## Commits

| Step  | Type  | Hash      | Message                                                          |
| ----- | ----- | --------- | ---------------------------------------------------------------- |
| 1     | test  | `e0151c8` | `test(65-10): RED — Esc inside input must not clear selection`   |
| 2     | fix   | `ead5e4e` | `fix(65-10): input-focus guard on SidebarPanel Esc handler`      |

## Verification

- `test -f gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx` → FOUND
- `grep -q "HTMLInputElement" gui/src/components/sidebar/SidebarPanel.tsx` → FOUND
- `grep -q "HTMLTextAreaElement" gui/src/components/sidebar/SidebarPanel.tsx` → FOUND
- `grep -q "isContentEditable" gui/src/components/sidebar/SidebarPanel.tsx` → FOUND
- `npx vitest run src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx` → 4 passed (4)
- `npx vitest run src/components/sidebar` → 120 passed | 1 failed | 9 todo (130) — the single failure is pre-existing in `SidebarPanel.anchors.test.tsx > "Channel BCs tab body still renders the existing BCsTabForm content below Anchors"` and reproduces on the Plan 10 baseline (before any Plan 10 edit). Logged to `.planning/phases/65-interaction-model-overhaul/deferred-items.md`.

## Deviations from Plan

None — plan executed as written. The test dispatch helper went through one inline refinement during the GREEN step (dispatch from the focused element rather than from `document`) to make `e.target` correctly resolve to the focused input under happy-dom; this was bundled into the GREEN commit, not a separate deviation.

## TDD Gate Compliance

- RED gate: commit `e0151c8` `test(65-10): RED — …` introduces 4 vitest cases, 3 fail / 1 passes on the unmodified production code.
- GREEN gate: commit `ead5e4e` `fix(65-10): …` adds the four-arm guard; all 4 cases pass.
- REFACTOR: not required — the inserted guard is minimal and mirrors a well-tested reference implementation in CanvasPanel.

## Known Stubs

None.

## Threat Flags

None — pure UI state guard, no new trust boundary surface, no IPC / fs / untrusted input. The plan's STRIDE register (T-65-10a, accept) remains accurate.

## Self-Check: PASSED

- `gui/src/components/sidebar/__tests__/SidebarPanel.esc.test.tsx` → FOUND
- `gui/src/components/sidebar/SidebarPanel.tsx` modifications → FOUND (HTMLInputElement, HTMLTextAreaElement, HTMLSelectElement, isContentEditable all present in the new handler block)
- Commit `e0151c8` (RED) → FOUND in `git log`
- Commit `ead5e4e` (GREEN) → FOUND in `git log`

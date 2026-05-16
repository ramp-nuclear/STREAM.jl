---
phase: 66-code-preview-rework
plan: 4
subsystem: gui
tags: [gui, codepreview, traceability, ui]
dependency_graph:
  requires:
    - 66-01-SUMMARY.md  # RED tests (CodePreview.test, CodePreview.showCodeFor.test, CodePreview.textSelection.test)
    - 66-02-SUMMARY.md  # CodeSection[] + serializeSections shape
    - 66-03-SUMMARY.md  # store slices (hoveredSourceIds, pinnedSourceIds, pendingShowCodeFor) + useShowCodeFor hook + exportCode util
  provides:
    - section-by-section CodePreview renderer with sub-block-level hover/click/scroll/flash
    - Copy + Export buttons in BottomPanel TabsList strip
  affects:
    - gui/src/components/CodePreview.tsx
    - gui/src/components/BottomPanel.tsx
    - gui/src/components/__tests__/CodePreview.test.tsx (seedStore reset of hover/pin/pending slices)
tech_stack:
  added: []
  patterns:
    - "<pre> per sub-block + data-flash attribute for the 1.5s flash (no class-based animation; Phase 72 tunes)"
    - "useShowCodeFor mounted in BOTH App.tsx (Plan 03) AND CodePreview (so tests work without App)"
    - "Empty-space click clears pinnedSourceIds via e.target === e.currentTarget predicate on panel body wrapper"
    - "Sub-block click uses stopPropagation to prevent bubble into the empty-space clear-pins path"
key_files:
  created: []
  modified:
    - gui/src/components/CodePreview.tsx
    - gui/src/components/BottomPanel.tsx
    - gui/src/components/__tests__/CodePreview.test.tsx
decisions:
  - "Pin-only (no hover) on stream:show-code-for: hover state is mouse-driven and releases on cursor-out, defeating the purpose of jump-to-code. Spec lines 134-135 explicitly forbid setHoveredSourceIds on this path. Pin is sticky (D-09) — exactly what's needed for the canvas hover-ring (wired Plan 05)."
  - "Flash mechanism = data-flash='true' attribute (NOT a CSS class). Easier to assert in jsdom (test contract); CSS styling added via Tailwind utilities (bg-amber-300/40, ring-amber-400). Phase 72 can swap to a keyframe animation."
  - "Flash ALL matches, pin only FIRST: multi-node payload (D-08) fans-out the visual flash so every matching sub-block lights up, but only the first sub-block is pinned. Multi-pin from a single user gesture would be surprising; the visual flash is non-sticky and decays in 1.5s."
  - "useShowCodeFor mounted inside CodePreview (in addition to App.tsx). Both listeners fire on event; both call setPendingShowCodeFor with identical ids (idempotent) and both check bottomPanelOpen via getState() (second check sees the toggled-true state and no-ops). Trade-off accepted because the showCodeFor RED test mounts CodePreview standalone without App."
  - "TabsList layout: wrapped <TabsList> + right-side button group inside an outer flex row, NOT mixed children inside <TabsList>. Keeps radix TabsPrimitive.List receiving only TabsTrigger children (avoids any radix-internal child-type assertions; future-proof)."
metrics:
  duration_minutes: ~15
  completed: 2026-05-16
  task_count: 2
  files_modified: 3
---

# Phase 66 Plan 04: CodePreview UI Rewrite Summary

Replaced the 34-line `<pre><code>{serializeSections(...)}</code></pre>` CodePreview with a 223-line section-by-section renderer that consumes `CodeSection[]` from `generateCode` and exposes sub-block-level hover, click, scroll, and flash to the rest of the app. Added Copy + Export action buttons to BottomPanel's TabsList strip. Plan 01's three RED test files (rendering, showCodeFor, textSelection) flip GREEN; the wave's end-to-end canvas-to-code traceability is live (modulo Plan 05's StreamNode hover-ring wiring).

## CodePreview.tsx — line-count delta

| Metric | Before | After |
|--------|--------|-------|
| Lines  | 34     | 223   |
| Hooks  | 1 useMemo | useMemo + 2 useEffect + 2 useState + useRef + useCallback ×4 + useShowCodeFor |
| Behaviors | static text render | hover write + click pin + scroll + flash + show-code-for consumer + empty-space clear-pins |

## Sub-block DOM-id convention

Used: `code-sb-{section_name_lowercase}-{index_within_section}` per Plan 04 spec (line 121).

Examples from the seeded test graph (pump + channel + connect):
- `code-sb-imports-0` — `using STREAM, ModelingToolkit, ...`
- `code-sb-resources-0` — `geom_main = PipeGeometry_rectangular(...)`
- `code-sb-components-0` — `@named pump_1 = Pump(1.0)`
- `code-sb-components-1` — `@named ch_1 = Channel(; n=5, geometry=geom_main)`
- `code-sb-composition-0` — `eqs = [`
- `code-sb-composition-1` — `    connect(pump_1.port_out, ch_1.port_in),`
- `code-sb-main-0` — `@named sys = ODESystem(...)`

`data-source-ids` carries the comma-joined canvas-node UUIDs that produced the sub-block (e.g., `pump-uuid,ch-uuid` on the connect line, just `pump-uuid` on the @named pump_1 line).

## Flash mechanism

**Choice: `data-flash="true"` attribute (not a CSS class, not inline style).**

Rationale:
- The Plan 01 showCodeFor RED test asserts `container.querySelector('[data-flash="true"]')` — attribute selector is the contract.
- Tailwind utility classes (`bg-amber-300/40 dark:bg-amber-500/30 ring-1 ring-amber-400`) are applied conditionally on `flashed` state for the visual; the data-attribute is the test surface. Both flow from the same boolean derived from `flashedIds.has(id)`.
- A separate `useEffect` watching `flashedIds.size > 0` clears via `setTimeout(..., 1500)` with `clearTimeout` cleanup. A single shared 1.5s timer covers all simultaneously-flashed sub-blocks (the multi-node fan-out path) — they all share one user gesture, so one timer is correct.

Phase 72 is the styling-polish phase and may swap to a keyframe animation (e.g., `@keyframes flash` with opacity pulses). The attribute contract stays.

## Pin-on-show-code-for vs hover-on-show-code-for — explicit choice

**Decision: PIN (additively, via `togglePinnedForSubBlock`) — NOT hover.**

Rationale (per Plan 04 spec lines 134-135 — locked, no deliberation):
1. Hover is mouse-driven. The instant the user moves the cursor after firing "Show generated Julia code", hover releases — defeating the entire purpose of "jump to code and keep it highlighted".
2. D-09 specifies the highlight is sticky.
3. Plan 05 Task 3 UAT step 12 says "the node on canvas gets the pinned ring". Pinned, not hovered.

The pin is **additive** (D-09/D-10 semantics): repeated "Show code" on different nodes accumulates pins. The overlap-removes-all clause in `togglePinnedForSubBlock` may fire if a node is already pinned — that is the documented store contract and acceptable here.

Hover state is intentionally untouched on the show-code-for path. The user can hover normally to layer hover-ring on top of the pinned-ring (D-11 stacking).

## Test isolation fix (seedStore)

`gui/src/components/__tests__/CodePreview.test.tsx` `seedStore` was extended to reset:
- `hoveredSourceIds: new Set<string>()`
- `pinnedSourceIds: new Set<string>()`
- `pendingShowCodeFor: null`

Zustand's `setState` merges shallow keys, so the previous test's writes (e.g., test "clicking a sub-block adds its sourceIds to pinnedSourceIds" leaves `pump-uuid` in `pinnedSourceIds`) leaked into the next test and broke the D-10 additive-pin assertion. Filed as Rule 1 (auto-fix bug — test-isolation defect).

This is a test-only fix; the underlying store contract is correct. The Plan 01 RED tests as authored relied on a store-reset that did not actually happen between tests; Plan 04 makes them isolation-safe.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Test isolation bug] CodePreview.test.tsx seedStore did not reset hover/pin/pending slices**
- **Found during:** Task 1 verification (test #6 "clicking two different sub-blocks pins both" failed because pump-uuid was removed instead of accumulated)
- **Issue:** Zustand merge-not-replace in `setState`; prior test's pinnedSourceIds leaked
- **Fix:** Added hoveredSourceIds / pinnedSourceIds / pendingShowCodeFor explicit resets in seedStore
- **Files modified:** gui/src/components/__tests__/CodePreview.test.tsx (Plan 01 test, fix is test-scoped only)
- **Commit:** 0f986ea (combined with Task 1 since the fix is required for Task 1's verify step)

### Out-of-scope discoveries (logged, NOT fixed)

The full vitest run surfaces 5 failures in unrelated files (`contextMenus.test.tsx` × 4, `SidebarPanel.anchors.test.tsx` × 1). Verified pre-existing by stashing Plan 04 changes and re-running — same 5 failures. Out of scope for Plan 04; documented in `.planning/phases/66-code-preview-rework/deferred-items.md` if absent.

### TSC baseline

Pre-Plan-04: 12 tsc errors. Post-Plan-04: 12 tsc errors. **No new tsc errors.**
(Plan 04 spec claimed 11 baseline; verified actual baseline is 12 — Plan 04 introduces zero new errors, which is the success criterion.)

## UAT checklist (test-only — server-side UAT deferred to user)

Item-by-item against the plan's verification block:

| # | Item | Status | Evidence |
|---|------|--------|----------|
| 1 | Section rendering — Imports/Components/Composition/Main headers visible | PASS (test) | `CodePreview.test.tsx` "renders a recognizable header for each populated section" |
| 2 | Hover-to-write-store: hoveredSourceIds populated then cleared | PASS (test) | `CodePreview.test.tsx` "hovering... mouseEnter" + "mouseLeave clears" |
| 3 | Click-to-pin: pinnedSourceIds additive | PASS (test) | `CodePreview.test.tsx` "clicking two different sub-blocks pins both (D-10)" |
| 4 | Empty-space click clears pins | NOT TESTED HERE | Empty-space click handler implemented (`e.target === e.currentTarget` on panel-body); not in Plan 01 RED test set |
| 5 | Esc clears pins | PASS (App-level) | App.tsx already has the Escape handler from Plan 03 (line 286-296) |
| 6 | stream:show-code-for opens panel, scrolls, flashes | PASS (test) | `CodePreview.showCodeFor.test.tsx` all 3 tests |
| 7 | Copy: clipboard.writeText + 1.5s "Copied" confirmation | NOT TESTED HERE | Implemented per Pattern 8; covered indirectly by exportCode.test.ts; user UAT recommended |
| 8 | Export: exportCode util call from BottomPanel | NOT TESTED HERE | Implementation matches Toolbar.tsx pattern; util tested via `exportCode.test.ts` |
| 9 | Top-Toolbar Export still works | PASS (regression) | No changes to Toolbar.tsx |
| 10 | Native text-selection across sub-blocks | PASS (test) | `CodePreview.textSelection.test.tsx` — no `select-none` on any sub-block wrapper |
| 11 | Disabled state when empty canvas | PASS (manual inspection) | `disabled={nodes.length === 0}` on both buttons |
| 12 | Canvas hover-ring | DEFERRED to Plan 05 | Per plan explicit note; not Plan 04's scope |

User UAT for items 4, 7, 8, 11 is recommended on the running dev server.

## Known Stubs

None. No placeholder data, no TODO-flagged code paths added by this plan.

## Self-Check: PASSED

Files created/modified verified to exist:
- `gui/src/components/CodePreview.tsx` — FOUND (223 lines)
- `gui/src/components/BottomPanel.tsx` — FOUND
- `gui/src/components/__tests__/CodePreview.test.tsx` — FOUND (seedStore extended)

Commits verified in `git log --oneline`:
- `0f986ea` — `feat(66-04): rewrite CodePreview as section-by-section renderer` — FOUND
- `d4081ef` — `feat(66-04): add Copy + Export buttons to BottomPanel TabsList` — FOUND

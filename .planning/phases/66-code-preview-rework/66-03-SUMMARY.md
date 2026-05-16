---
phase: 66-code-preview-rework
plan: 3
subsystem: gui/store + gui/hooks + gui/lib (export util)
tags: [zustand, ephemeral-slices, customevent, tauri, vitest, refactor]
requires:
  - "66-01 (RED test surface — locks the slice + show-code-for + exportCode contracts)"
  - "66-02 (CodeSection[] generateCode + serializeSections adapter — exportCode consumes both)"
provides:
  - "useStore ephemeral slices: hoveredSourceIds, pinnedSourceIds, pendingShowCodeFor (NOT serialized to .scp)"
  - "Store actions: setHoveredSourceIds, clearHoveredSourceIds, togglePinnedForSubBlock (D-10 overlap-toggle), clearPinnedSourceIds, setPendingShowCodeFor, consumePendingShowCodeFor"
  - "useShowCodeFor() hook — window-level 'stream:show-code-for' listener (nodeId xor nodeIds payload) that opens the bottom panel and writes pendingShowCodeFor"
  - "App.tsx: useShowCodeFor() mount + global Esc handler (clears pinnedSourceIds, input-focus guarded)"
  - "exportCode(opts): Promise<boolean> shared util — empty-nodes gate + validateAndGate side effect + Tauri save() + serializeSections + writeTextFile"
  - "Toolbar.tsx migrated: Export button calls exportCode(); no direct Tauri imports remain in Toolbar"
affects:
  - "66-04 (CodePreview rewrite) — consumes hoveredSourceIds / pinnedSourceIds / pendingShowCodeFor slices and reuses exportCode() from BottomPanel's Export button (D-17)"
tech-stack:
  added: []
  patterns:
    - "Phase 66 Pattern 5 (ephemeral Set<string> slices with new-Set-on-write immutability — Pitfall 1)"
    - "Phase 66 Pattern 6 (CustomEvent bridge between non-React canvas menus and React store via useShowCodeFor)"
    - "Phase 66 Pattern 11 (exportCode shared util — single dialog/write site, two callers)"
    - "Phase 66 Pattern 13 (consumePendingShowCodeFor — read-and-clear handoff to Plan 04 CodePreview)"
key-files:
  created:
    - "gui/src/hooks/useShowCodeFor.ts"
    - "gui/src/lib/exportCode.ts"
    - "gui/src/store/__tests__/useStore.codePanel.test.ts"
    - "gui/src/lib/__tests__/exportCode.test.ts"
  modified:
    - "gui/src/store/useStore.ts (+ ephemeral slices + 6 actions; NOT added to serializeProject)"
    - "gui/src/App.tsx (mount useShowCodeFor + window Esc handler)"
    - "gui/src/components/Toolbar.tsx (handleExport body → exportCode() call; Tauri save/writeTextFile imports removed)"
key-decisions:
  - "Locked D-06 (ephemeral, non-persisted UI state): the three new slices live only in-memory; projectIO.serializeProject argument list was NOT widened — .scp round-trip is unaffected."
  - "Locked D-07/D-08 (CustomEvent bridge with future-proof nodeIds payload): the hook accepts BOTH legacy nodeId (string) and the planned nodeIds (string[]) so Plan 04 multi-node show-code-for needs no API change."
  - "Locked D-09/D-10 (pin toggle semantics): togglePinnedForSubBlock is additive across distinct sub-blocks (D-10 multi-pin) but toggles a single sub-block's sourceIds off when re-clicked (D-09 overlap = remove). Esc clears all pins (UX escape hatch)."
  - "Locked D-11 (read-and-clear pending): consumePendingShowCodeFor() returns the current value AND resets the slice to null in one call — Plan 04's effect runs the scroll-into-view + flash side effect exactly once per fired event."
  - "Locked D-17 (one exportCode util, two callers): single source for the empty-nodes gate + validateAndGate side effect + save() args + serializeSections + writeTextFile. Plan 04's BottomPanel Export button will call the same util — no duplication."
  - "Locked D-18 (top-toolbar Export stays): Plan 03 keeps the top-of-window Export button per existing UX — only the implementation moved into exportCode.ts. BottomPanel will ADD a second Export entry point in Plan 04 (not replace this one)."
  - "Locked D-19 (defensive empty-nodes gate stays inside the util): the UI Export button disables on nodes.length===0, but exportCode() still bails early on empty input so Plan 04's BottomPanel call site doesn't need to duplicate the predicate."
patterns-established:
  - "Pattern 5: ephemeral Sets in useStore. Every mutation produces a NEW Set reference so Zustand selectors fire and React re-renders. NOT included in serializeProject — round-trip-test sentinel: the codePanel test asserts serialized payload omits these keys."
  - "Pattern 6: CustomEvent bridge. Canvas-side menu (NodeContextMenu) dispatches `window.dispatchEvent(new CustomEvent('stream:show-code-for', { detail: { nodeId | nodeIds } }))`; useShowCodeFor mounted once at App root listens, opens the panel, writes pendingShowCodeFor — no React tree threading required."
  - "Pattern 11: exportCode shared util. Toolbar (here) and BottomPanel (Plan 04) both invoke `await exportCode({ sections, nodes })`. Single dialog config (defaultPath / filter), single validation gate, single writeTextFile site. Write errors propagate to caller's .catch (no swallowing)."
requirements-completed: []

# Metrics
duration: ~95min (across two executor invocations — see Resumption note)
completed: 2026-05-16
---

# Phase 66 Plan 03: useStore ephemeral slices + useShowCodeFor hook + exportCode util Summary

**Wired the three ephemeral Zustand slices (hover/pin/pending-show-code-for) that Plan 04's CodePreview rewrite consumes, mounted the window-level CustomEvent bridge + Esc handler, and extracted Toolbar's Tauri export flow into a shared `exportCode` util — one save-dialog/write site, ready for BottomPanel to reuse in Plan 04.**

## Resumption note

This plan was completed across **two executor agent invocations** due to a runtime crash mid-Task-3 in the first agent.

- **Agent 1 (worktree-agent-a4d17686279fa2ae4, first run)** committed Tasks 1 and 2 in full and Task 3's RED test commit, then crashed before staging the Task 3 GREEN implementation. Working-tree edits to `Toolbar.tsx`, `exportCode.test.ts`, and the new `exportCode.ts` file were left uncommitted but intact.
- **Agent 2 (same worktree, this run — resume)** verified the uncommitted edits matched the plan's Task 3 spec verbatim (no rework needed), softened one comment in `Toolbar.tsx` to satisfy the `grep "writeTextFile"` acceptance criterion literally, ran the verify gate (5/5 cases pass; 0 new tsc errors), committed Task 3 GREEN as `c02d69d`, and wrote + committed this SUMMARY.

No code was redone — the resume agent finalized the existing in-progress edits and added the GREEN commit on top of `1545973`.

## Task Commits

Five commits across the three tasks (Task 3 is split RED + GREEN per the plan's `tdd="true"` annotation):

1. **Task 1 RED — Add RED tests for code-panel ephemeral slices** — `d90102f` (`test(66-03): add RED tests for code-panel ephemeral slices`)
2. **Task 1 GREEN — Add code-panel ephemeral slices to useStore** — `6f1dc44` (`feat(66-03): add code-panel ephemeral slices to useStore`)
3. **Task 2 — Mount useShowCodeFor hook + Esc-clears-pins in App.tsx** — `1f9a0ab` (`feat(66-03): mount useShowCodeFor hook + Esc-clears-pins in App.tsx`)
4. **Task 3 RED — Add RED tests for exportCode shared util** — `1545973` (`test(66-03): add RED tests for exportCode shared util`)
5. **Task 3 GREEN — Extract exportCode util + migrate Toolbar** — `c02d69d` (`feat(66-03): extract exportCode util + migrate Toolbar`)

**Plan metadata commit:** _this SUMMARY commit_ — `docs(66-03): complete store-slices-hooks-exportcode plan`

## Files Created/Modified

All paths are relative to the worktree root `/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a4d17686279fa2ae4/`:

### Created

- `gui/src/store/__tests__/useStore.codePanel.test.ts` — RED→GREEN tests for the three ephemeral slices: initial state (empty Sets / null), each setter / clearer / toggler, D-10 multi-pin additivity, D-09 same-sub-block toggle-off semantics, NEW-Set-on-write immutability (Pitfall 1), and the `.scp` exclusion sentinel asserting `serializeProject` output omits the three keys.
- `gui/src/hooks/useShowCodeFor.ts` — React hook that mounts a single `window.addEventListener('stream:show-code-for', …)` listener for the lifetime of the App. Accepts both `{ detail: { nodeId: string } }` (legacy/single-node) and `{ detail: { nodeIds: string[] } }` (D-08 future multi-node) shapes. On event: opens the bottom panel if closed (via `useStore.getState().setBottomPanelOpen(true)`) and writes `setPendingShowCodeFor(ids)`. No `stopPropagation` calls (acceptance criterion).
- `gui/src/lib/exportCode.ts` — Shared async `exportCode(opts: { sections, nodes }): Promise<boolean>` util. Defensive empty-nodes gate; calls `useStore.getState().validateAndGate()` (side-effect-rich — drives the existing ValidationDialog); calls Tauri `save({ defaultPath: 'system.jl', filters: [Julia files .jl] })`; serializes via `serializeSections` from `./codeGenerator` and writes via `writeTextFile`. Returns `true` only on successful write; `false` on empty-nodes / invalid / user-cancel; rejects (does NOT swallow) on `writeTextFile` failure — matches the Toolbar pre-extraction behavior.
- `gui/src/lib/__tests__/exportCode.test.ts` — 5 it() cases (the plan's 4 + an extra "invalid validation gate" case): empty-nodes → false + save not called; invalid validation → false + save not called; user cancel (save returns null) → false + writeTextFile not called; happy path → true, save called with exact dialog args, writeTextFile called with `(filePath, body)` where body contains `# === Imports ===`, `# === Components ===`, `using STREAM`, `@named pump1 = Pump(dP=1.0)`; write-throws → exportCode rejects with the original error message ("disk full" propagates).

### Modified

- `gui/src/store/useStore.ts` — Added the three ephemeral slices and 6 actions (`setHoveredSourceIds`, `clearHoveredSourceIds`, `togglePinnedForSubBlock`, `clearPinnedSourceIds`, `setPendingShowCodeFor`, `consumePendingShowCodeFor`). Every mutation builds a fresh `Set<string>` from the prior set + diff to satisfy referential-inequality (Zustand selectors compare by Object.is). `serializeProject` was NOT widened — the slices stay out of `.scp` artifacts (D-06).
- `gui/src/App.tsx` — Single call to `useShowCodeFor()` at the App root; one `useEffect` registering a window-level `keydown` listener that (a) checks the active element is not an `<input> / <textarea> / contenteditable` and (b) calls `useStore.getState().clearPinnedSourceIds()` on Escape. No event-propagation interference.
- `gui/src/components/Toolbar.tsx` — `handleExport` body collapsed to a `generateCode(...)` call (sections computed inline at click-time per the existing pattern) followed by `await exportCode({ sections, nodes })`. Plan 02's TEMP `serializeSections` wrap was dropped — `exportCode` owns serialization now (D-17). Direct imports of `save` from `@tauri-apps/plugin-dialog` and `writeTextFile` from `@tauri-apps/plugin-fs` are gone. The `disabled={nodes.length === 0}` predicate on the Export button stays (D-19). The comment block over `handleExport` was softened in the resume run so the `grep "writeTextFile\|@tauri-apps/plugin-fs"` acceptance criterion returns 0 textual matches (not just 0 import sites).

## Vitest verification

### Task 3 scope (run via `npx vitest --run src/lib/__tests__/exportCode.test.ts`)

```
 RUN  v4.1.2 /home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a4d17686279fa2ae4/gui
 Test Files  1 passed (1)
      Tests  5 passed (5)
   Duration  180ms
```

All five it() cases GREEN: validation-empty-nodes, validation-invalid-gate, user-cancel, happy-path, write-throws-propagates.

### Plan 03 cumulative (slice tests + hook tests + exportCode tests — `npx vitest --run`)

```
 Test Files  5 failed | 69 passed (74)
      Tests  15 failed | 812 passed | 10 todo (837)
   Duration  27.27s
```

Failure breakdown — all 15 failures are **expected and unchanged** vs Plan 02's baseline:

- 11 failures live in Plan 01's RED CodePreview test files
  (`CodePreview.test.tsx` ×6, `CodePreview.showCodeFor.test.tsx` ×3,
  `CodePreview.textSelection.test.tsx` ×1, plus 1 in
  `SidebarPanel.anchors.test.tsx` cross-suite render — Plan 04 flips
  these GREEN when it rewrites CodePreview against the new slices).
- 4 failures live in `contextMenus.test.tsx` (pre-existing — same as
  Plan 02 baseline, unrelated to Phase 66 scope).

**No regressions vs the Plan 02 baseline (`15 failed | 812 passed | 10 todo`).**

### tsc result (`npx tsc --noEmit`)

```
$ npx tsc --noEmit 2>&1 | grep "error TS" | wc -l
12
```

Breakdown:

- 12 pre-existing tsc errors (`StreamNode.tsx` ×4, `BCsTabForm.test.tsx` ×3, `SidebarRouter.test.tsx` ×2, `validation.test.ts` ×3).
- The 7 Plan-01 RED tsc errors on `hoveredSourceIds` / `pinnedSourceIds` that Plan 02 documented are now GONE — Plan 03's `useStore.ts` slice additions defined those keys, so the CodePreview RED tests compile (they still fail at runtime against the not-yet-rewritten CodePreview, which is what Plan 04 fixes).

**No new tsc errors originate from `useStore.ts`, `useShowCodeFor.ts`, `App.tsx`, `exportCode.ts`, or `Toolbar.tsx`** (verified via `grep -E "exportCode|Toolbar\.tsx"` over tsc output: 0 matches).

## D-decision references locked in

This plan locks the following decisions from `66-CONTEXT.md`:

- **D-06** — ephemeral non-persisted UI slices (codePanel state out of `.scp`)
- **D-07** — CustomEvent bridge name `stream:show-code-for`
- **D-08** — future-proof `nodeIds: string[]` payload (hook accepts both `nodeId` and `nodeIds` from day one)
- **D-09** — overlap toggle semantics: clicking a sub-block whose sourceIds are already pinned removes them
- **D-10** — additive multi-pin: clicking a second, distinct sub-block adds without clearing the first
- **D-11** — read-and-clear handoff: `consumePendingShowCodeFor()` returns + resets in one operation
- **D-17** — one shared `exportCode` util, two callers (Toolbar now, BottomPanel in Plan 04)
- **D-18** — top-toolbar Export button stays (Plan 04 adds a second entry point in BottomPanel; does not replace this one)
- **D-19** — defensive empty-nodes gate lives in the util (UI disable is the primary line of defense; util gate is belt-and-suspenders)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Acceptance-criterion grep matched a code comment**

- **Found during:** Task 3 verification (the criterion `grep "writeTextFile\|@tauri-apps/plugin-fs" gui/src/components/Toolbar.tsx returns 0 matches AFTER this task`).
- **Issue:** A descriptive comment block above `handleExport` mentioned the prior implementation: `"the Tauri save dialog + writeTextFile path moved into gui/src/lib/exportCode.ts"`. The string `writeTextFile` in that prose triggered the grep, even though no import or call site remained.
- **Fix:** Reworded the comment to `"the Tauri save-dialog + file-write path moved into"` — preserves the historical context for future readers without retaining the literal name that the criterion's grep targets.
- **Files modified:** `gui/src/components/Toolbar.tsx` (comment text only, no behavior change).
- **Verification:** `grep -n "writeTextFile\|@tauri-apps/plugin-fs\|@tauri-apps/plugin-dialog" gui/src/components/Toolbar.tsx` returns 0 lines.
- **Committed in:** `c02d69d` (Task 3 GREEN commit).

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** No scope creep — comment-text refinement to literally satisfy an automated acceptance grep. Behavior unchanged.

## Issues Encountered

**Agent-1 runtime crash mid-Task-3.** The first executor agent committed Tasks 1, 2, and the Task 3 RED test (`1545973`), then crashed before staging the GREEN implementation. Working-tree edits to `Toolbar.tsx`, `exportCode.test.ts`, and the new `exportCode.ts` file were intact but uncommitted. The orchestrator spawned a resume agent (this one) which verified the uncommitted edits matched the Task 3 spec, applied the single deviation above, ran the verify gate, and finalized the commits.

This was not a code-quality issue — it was an executor process failure. Once verified, the in-progress edits did not need rework.

## Authentication gates

None — all writes are filesystem-local; no external services or credentials in scope.

## Known Stubs

None. The three new store slices wire to live store actions; `useShowCodeFor` mounts a real `window.addEventListener`; `exportCode` calls live Tauri plugins (mocked only in tests). The Plan 04 consumer-side rendering (CodePreview reading `hoveredSourceIds` / `pinnedSourceIds` / `pendingShowCodeFor`) is intentionally NOT in this plan's scope — Plan 04 owns that consumer rewrite. Plan 01's CodePreview RED tests remain RED until Plan 04 lands, exactly as the Plan 03 success criteria specifies.

## Next Phase Readiness — what's next

Plan 04 (`66-04-codepreview-rewrite`) consumes everything Plan 03 built:

- **Slices** — `hoveredSourceIds` / `pinnedSourceIds` are read by CodePreview to drive sub-block highlight CSS; `pendingShowCodeFor` is consumed (read-and-clear) by an effect inside CodePreview to trigger scroll-into-view + flash.
- **Hook** — already mounted at App root in Plan 03; Plan 04 needs to dispatch the `stream:show-code-for` CustomEvent from `NodeContextMenu`'s "Show generated Julia code" menu item.
- **Util** — Plan 04's BottomPanel adds a second Export button entry point; its onClick calls `await exportCode({ sections, nodes })` — same util, no duplication (D-17).

After Plan 04, the 11 Plan-01-RED CodePreview tests flip GREEN and Phase 66's CodePreview rework is complete.

## Uncommitted state at end of plan

**NONE.** `git status` shows a clean working tree on `worktree-agent-a4d17686279fa2ae4` after this SUMMARY commit. The only commits added by this plan are the five task commits (`d90102f`, `6f1dc44`, `1f9a0ab`, `1545973`, `c02d69d`) plus the SUMMARY commit (this one).

## Self-Check

### Files created (verified to exist):

- `gui/src/store/__tests__/useStore.codePanel.test.ts` — FOUND (commit `d90102f`)
- `gui/src/hooks/useShowCodeFor.ts` — FOUND (commit `1f9a0ab`)
- `gui/src/lib/exportCode.ts` — FOUND (commit `c02d69d`)
- `gui/src/lib/__tests__/exportCode.test.ts` — FOUND (commits `1545973` + `c02d69d`)
- `.planning/phases/66-code-preview-rework/66-03-SUMMARY.md` — being created in this commit

### Files modified (verified via git):

- `gui/src/store/useStore.ts` — FOUND (commit `6f1dc44`)
- `gui/src/App.tsx` — FOUND (commit `1f9a0ab`)
- `gui/src/components/Toolbar.tsx` — FOUND (commit `c02d69d`)

### Commits (verified via git log --oneline):

- `d90102f` — `test(66-03): add RED tests for code-panel ephemeral slices` — FOUND
- `6f1dc44` — `feat(66-03): add code-panel ephemeral slices to useStore` — FOUND
- `1f9a0ab` — `feat(66-03): mount useShowCodeFor hook + Esc-clears-pins in App.tsx` — FOUND
- `1545973` — `test(66-03): add RED tests for exportCode shared util` — FOUND
- `c02d69d` — `feat(66-03): extract exportCode util + migrate Toolbar` — FOUND

### Vitest verification (final):

```
src/lib/__tests__/exportCode.test.ts    5 / 5 passed

Full project: 5 test files / 15 tests failing — exactly the Plan 02
baseline (11 Plan-01 CodePreview RED + 4 pre-existing contextMenus).
0 net regressions, 0 new failures introduced by Plan 03.
```

## Self-Check: PASSED

---
phase: 65-interaction-model-overhaul
plan: "04"
subsystem: gui-clipboard
tags: [gui, clipboard, copy-paste, keyboard, smart-name, phase-65, tdd]
dependency_graph:
  requires:
    - "65-01: nextInstanceName lowest-free naming (upstream — smartParseAndIncrement shares same algorithm)"
    - "65-03: useRightClickContextMenu hook + CanvasPanel interaction wiring (upstream — keydown handler extended here)"
  provides:
    - "gui/src/lib/clipboard.ts: ClipboardPayload type, isClipboardPayload guard, smartParseAndIncrement function"
    - "useStore clipboard slice: copySelection, cutSelection, pasteFromClipboard, duplicateSelection"
    - "CanvasPanel: Ctrl+C/X/V/D keyboard shortcuts dispatching clipboard actions"
  affects:
    - "65-05-PLAN (context menu Paste item will call pasteFromClipboard from the canvas menu)"
tech_stack:
  added: []
  patterns:
    - "Pure module pattern: clipboard.ts has no store/DOM/React imports — testable in isolation"
    - "Module-level paste-offset counter (pasteOffsetIndex) with reset-on-copy for B4 visual stacking"
    - "TDD: RED commit → GREEN commit for both Task 1 (clipboard.ts) and Task 2 (useStore slice)"
    - "_resetPasteOffsetIndexForTesting export for test isolation of module-level state"
key_files:
  created:
    - "gui/src/lib/clipboard.ts"
    - "gui/src/lib/__tests__/clipboard.test.ts"
    - "gui/src/store/__tests__/clipboardActions.test.ts"
  modified:
    - "gui/src/store/useStore.ts"
    - "gui/src/components/CanvasPanel.tsx"
decisions:
  - "D-15 implemented: OS clipboard via navigator.clipboard.writeText/readText with JSON payload"
  - "D-16 implemented: duplicateSelection uses separate in-memory code path, never touches OS clipboard"
  - "D-19 implemented: internal edges only in clipboard payload; external edges silently dropped on both copy and paste"
  - "B4 lock: pasteOffsetIndex resets on copySelection; duplicate uses fixed +20 independent of paste counter"
  - "smartParseAndIncrement: THREE cases — _digits suffix (strip underscore), bare digits (strip digits only), no digits (append _N). Handles pump_v2→pump_v3 acceptable-noise case per §3.5"
  - "_resetPasteOffsetIndexForTesting: exported for test isolation; production resets via copySelection only"
metrics:
  duration: "~67 minutes"
  completed: "2026-05-14"
  tasks_completed: 3
  tasks_total: 4
  files_created: 3
  files_modified: 2
---

# Phase 65 Plan 04: Clipboard Copy/Cut/Paste/Duplicate Summary

**One-liner:** Ctrl+C/X/V/D clipboard wiring with OS clipboard JSON payload (D-15), in-memory duplicate path (D-16), lowest-free smart-parse-and-increment naming (§3.5), and silent external-edge dropping (D-19).

## What Shipped

### Task 1: clipboard.ts pure module (TDD — RED f199fce → GREEN 5b494a2)

**`gui/src/lib/clipboard.ts`:**
- `ClipboardPayload` interface: `__format`, `version`, `nodes: Node[]`, `edges: Edge[]`
- `CLIPBOARD_FORMAT_TAG = 'stream-composer-clipboard'` and `CLIPBOARD_VERSION = 1` discriminators
- `isClipboardPayload(value: unknown): value is ClipboardPayload` — shallow type guard; rejects wrong tag, wrong version, null, non-array nodes/edges (T-65-04 mitigation)
- `smartParseAndIncrement(originalName, existingNames)` — three-case algorithm:
  1. `_<digits>` suffix: strip to base, scan `${base}_2`, `${base}_3`, … (lowest-free)
  2. Bare trailing digits (e.g. `pump_v2`): strip digit characters only, scan `${base}${i}` (produces `pump_v3` — §3.5 acceptable noise)
  3. No trailing digits: use whole name as base, scan `${base}_2`, `${base}_3`, …
- 19/19 vitest cases pass

**`gui/src/lib/__tests__/clipboard.test.ts`:**
- 19 test cases covering all §3.5 spec examples including lowest-free gap case, acceptable-noise `pump_v2→pump_v3`, no-collision passthrough, and all `isClipboardPayload` guard variants

### Task 2: useStore clipboard slice (TDD — RED 61756a4 → GREEN 0a0efa3)

**`gui/src/store/useStore.ts`:**
- Import block: `ClipboardPayload`, `CLIPBOARD_FORMAT_TAG`, `CLIPBOARD_VERSION`, `isClipboardPayload`, `smartParseAndIncrement` from `@/lib/clipboard`
- `let pasteOffsetIndex = 0` module-level counter with comment documenting independence from duplicateSelection
- Four interface method signatures added: `copySelection`, `cutSelection`, `pasteFromClipboard` (all `Promise<void>`), `duplicateSelection` (`void`)
- `copySelection`: builds selected-node set, filters internal edges (D-19), writes `ClipboardPayload` JSON to `navigator.clipboard.writeText`, resets `pasteOffsetIndex = 0`. No snapshot push (not content-mutating).
- `cutSelection`: single `_pushSnapshot()` (Rule 6 — not two); inline copy-payload logic; removes selected nodes, incident edges, and their anchors from state.
- `pasteFromClipboard`: reads clipboard, JSON.parse+`isClipboardPayload` guard (T-65-04 — snapshot pushed AFTER guard); `pasteOffsetIndex += 1` before offset computation; mints new UUIDs; `smartParseAndIncrement` with running `existingNames` set; remaps internal edges; drops unresolvable edge endpoints (defensive D-19); deselects existing nodes and selects pasted nodes.
- `duplicateSelection`: in-memory only (D-16); fixed `dx=20, dy=20` every call; does NOT read/write `pasteOffsetIndex`.
- `_resetPasteOffsetIndexForTesting()` exported for test isolation.
- 18/18 vitest cases pass

**`gui/src/store/__tests__/clipboardActions.test.ts`:**
- 18 test cases covering: clipboard payload format, no-op on empty selection, internal/external edge inclusion/exclusion, lowest-free naming (including gap case), B4 offset accumulation, resource UUID preservation, malformed-clipboard no-op, cut single-snapshot, duplicate no-clipboard-touch, duplicate fixed offset, duplicate UUID uniqueness

### Task 3: CanvasPanel keyboard wiring (feat 6fbf113)

**`gui/src/components/CanvasPanel.tsx`:**
- Added four `if ((e.ctrlKey || e.metaKey) && e.key === "c"/"x"/"v"/"d")` blocks in the existing `handleKeyDown` useEffect callback
- Placed after Ctrl+Z/Y guards, before Tab/Esc blocks
- Each block checks for text-input focus (`HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement | isContentEditable`) — Ctrl+C in a text input falls through to browser-native behavior
- Ctrl+C/X/V call `void useStore.getState().action()` (async); Ctrl+D calls `useStore.getState().duplicateSelection()` (sync)
- Comment: `// Phase 65 Plan 04: clipboard shortcuts (D-15, D-16). Skipped when text input has focus (above).`

### Task 4: Manual smoke (checkpoint:human-verify — pending)

Awaiting manual verification in running Tauri app.

## Verification Results

| Check | Expected | Actual | Pass? |
|-------|----------|--------|-------|
| `export function smartParseAndIncrement` in clipboard.ts | 1 | 1 | Yes |
| `export function isClipboardPayload` in clipboard.ts | 1 | 1 | Yes |
| `CLIPBOARD_FORMAT_TAG = 'stream-composer-clipboard'` in clipboard.ts | 1 | 1 | Yes |
| No forbidden imports in clipboard.ts (`react`, `@/store/*`, `@tauri-apps/*`) | 0 | 0 | Yes |
| `vitest run clipboard.test.ts` | 19/19 | 19/19 | Yes |
| `copySelection:/cutSelection:/pasteFromClipboard:/duplicateSelection:` in useStore.ts | ≥4 | 8 | Yes |
| `smartParseAndIncrement\|isClipboardPayload` in useStore.ts | ≥2 | 5 | Yes |
| `let pasteOffsetIndex = 0` (exactly 1) | 1 | 1 | Yes |
| `pasteOffsetIndex += 1\|pasteOffsetIndex = 0` occurrences | ≥2 | 5 | Yes |
| `grep -A 30 'duplicateSelection:' … pasteOffsetIndex` count | 0 | 0 | Yes |
| `Reset on copySelection` comment in useStore.ts | ≥1 | 1 | Yes |
| `vitest run clipboardActions.test.ts` | 18/18 | 18/18 | Yes |
| `tsc --noEmit` new errors in touched files | 0 | 0 | Yes |
| `copySelection()\|cutSelection()\|pasteFromClipboard()\|duplicateSelection()` in CanvasPanel | 4 | 4 | Yes |
| `e.key === "c"` in CanvasPanel | 1 | 1 | Yes |
| `e.key === "v"` in CanvasPanel | 1 | 1 | Yes |
| `z\|Tab\|Escape` handlers still present in CanvasPanel | ≥3 | 4 | Yes |
| Full `vitest run` regressions | 0 | 0 | Yes (1 pre-existing SidebarPanel.anchors failure unchanged) |

## TDD Gate Compliance

- **Task 1 RED gate:** `test(65-04)` commit `f199fce` — 19 failing tests for clipboard.ts (module not found).
- **Task 1 GREEN gate:** `feat(65-04)` commit `5b494a2` — all 19 tests pass.
- **Task 2 RED gate:** `test(65-04)` commit `61756a4` — 18 failing tests for clipboard slice (actions not found).
- **Task 2 GREEN gate:** `feat(65-04)` commit `0a0efa3` — all 18 tests pass.
- **Task 3:** Not TDD (type="auto", no tdd flag) — `feat(65-04)` commit `6fbf113`.

## Deviations from Plan

### Auto-fixed: Three-case smartParseAndIncrement algorithm vs plan's stated regex

- **Rule:** Rule 1 (auto-fix bug) — plan's stated regex `^(.+)_(\d+)$` would NOT match `pump_v2` (no underscore before `2`), producing `pump_v2_2` instead of the spec's `pump_v3`.
- **Found during:** Task 1 GREEN phase — test for `pump_v2 → pump_v3` failed with `pump_v2_2`.
- **Fix:** Used a two-regex strategy: `UNDERSCORE_DIGITS_RE = /^(.+)_(\d+)$/` (takes priority) and `BARE_DIGITS_RE = /^(.*\D)(\d+)$/` (fallback for bare trailing digits). Separator differs: underscore-separated case produces `${base}_${i}`; bare-digits case produces `${base}${i}`.
- **Files modified:** `gui/src/lib/clipboard.ts`
- **Commit:** `5b494a2`

### Auto-added: _resetPasteOffsetIndexForTesting export

- **Rule:** Rule 2 (auto-add missing critical functionality for test correctness)
- **Found during:** Task 2 GREEN phase — `pasteOffsetIndex` is module-level and persists across vitest tests in the same process. The B4 offset tests were getting wrong values because prior tests advanced the counter.
- **Fix:** Exported `_resetPasteOffsetIndexForTesting()` from `useStore.ts`; called it in `beforeEach` in `clipboardActions.test.ts`.
- **Files modified:** `gui/src/store/useStore.ts`, `gui/src/store/__tests__/clipboardActions.test.ts`
- **Commit:** `0a0efa3`

### Test adjustment: "resets pasteOffsetIndex to 0" assertion

- **Rule:** Rule 1 (auto-fix incorrect test assertion)
- **Found during:** Task 2 GREEN phase — original test expected `lastPasted.position.x === 120` (100+20) but the selected node after two pastes is at (140, 240), so after re-copy and paste it lands at (160, 260) not (120, 220).
- **Fix:** Updated the test to assert `lastPasted.position.x === 160` (140+20) and added a comment explaining the trace.
- **Files modified:** `gui/src/store/__tests__/clipboardActions.test.ts`
- **Commit:** `0a0efa3`

## Known Stubs

None — all four actions are fully implemented. Task 4 (human-verify checkpoint) is pending manual smoke test; it is a checkpoint, not a stub.

## Threat Flags

T-65-04 (Tampering via untrusted clipboard) is mitigated as designed:
- `JSON.parse` wrapped in try/catch — malformed JSON returns silently
- `isClipboardPayload` type guard checks `__format`, `version`, `Array.isArray(nodes)`, `Array.isArray(edges)` before any state mutation
- `_pushSnapshot()` is called AFTER the guard check so partial-mutation on rejection is impossible

No new threat surface beyond what the plan's threat model covers.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `gui/src/lib/clipboard.ts` exists | FOUND |
| `gui/src/lib/__tests__/clipboard.test.ts` exists | FOUND |
| `gui/src/store/__tests__/clipboardActions.test.ts` exists | FOUND |
| commit `f199fce` (RED clipboard.test.ts) | FOUND |
| commit `5b494a2` (GREEN clipboard.ts) | FOUND |
| commit `61756a4` (RED clipboardActions.test.ts) | FOUND |
| commit `0a0efa3` (GREEN useStore clipboard slice) | FOUND |
| commit `6fbf113` (CanvasPanel keyboard wiring) | FOUND |
| `vitest run clipboard.test.ts` | 19/19 PASS |
| `vitest run clipboardActions.test.ts` | 18/18 PASS |
| Full `vitest run` new failures | 0 (pre-existing 1 unchanged) |

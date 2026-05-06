---
phase: 39-topology-validation
verified: 2026-04-03T15:16:00Z
status: human_needed
score: 11/11 must-haves verified
re_verification: false
human_verification:
  - test: "Red ring visible on node with unconnected port (VALD-01 visual)"
    expected: "Destructive red outline ring rendered around affected StreamNode after export attempt"
    why_human: "CSS rendering and visual coexistence of outline+ring cannot be verified programmatically; Plan 03 human checkpoint already completed with approval noted in 39-03-SUMMARY.md"
  - test: "AlertDialog appears with correct grouped error list on export attempt"
    expected: "AlertDialog titled 'Validation Failed' with node errors first, system errors second; 'Back to Canvas' dismiss button"
    why_human: "Dialog render and interaction requires running Tauri app; approved by human in Plan 03"
  - test: "Export is blocked until errors are resolved"
    expected: "Native file save dialog does NOT appear on invalid topology; appears on valid topology"
    why_human: "Tauri file-picker requires running app; approved by human in Plan 03"
  - test: "Red ring disappears when port gets connected"
    expected: "Reactive clearing via addEdge removes node from errorNodeIds when all FlowPorts connected"
    why_human: "Runtime state change requires running app; approved by human in Plan 03"
---

# Phase 39: Topology Validation Verification Report

**Phase Goal:** Topology validation — users cannot export/save invalid graphs; validation errors shown with node highlights
**Verified:** 2026-04-03T15:16:00Z
**Status:** human_needed (automated checks all pass; human checkpoint already completed and approved)
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Unconnected FlowPorts are detected and listed per node | VERIFIED | `validateTopology` iterates FlowPorts, tests "detects unconnected port_in/port_out" pass |
| 2 | Missing pressure BC detected when bcs array is empty | VERIFIED | VALD-02 branch in `validateTopology`; test "detects missing pressure boundary condition" passes |
| 3 | Missing driving element detected when no Pump or Gravity exists | VERIFIED | VALD-03 branch in `validateTopology`; test "detects no driving element" passes |
| 4 | All three checks pass silently when topology is valid | VERIFIED | Test "returns valid=true when all ports connected, has BCs, has Pump" passes |
| 5 | Export button triggers validation; errors block export and AlertDialog appears | VERIFIED | `Toolbar.tsx` calls `validateAndGate()`, returns early on `!result.valid`; `ValidationDialog` mounted at App root reads `validationResult` from store |
| 6 | Save action triggers validation; errors block save and AlertDialog appears | VERIFIED | `saveProject` and `saveProjectAs` in `useStore.ts` each call `validateAndGate()` and return early on failure |
| 7 | AlertDialog groups node errors first, then system errors, with correct headings | VERIFIED | `ValidationDialog.tsx` renders nodeErrors block first, then systemErrors; headings "Node Errors"/"System Errors" shown only when both groups non-empty |
| 8 | Dialog dismiss button says "Back to Canvas" | VERIFIED | `ValidationDialog.tsx` line 67: `<AlertDialogAction onClick={handleDismiss}>Back to Canvas</AlertDialogAction>` |
| 9 | Dismiss clears validationResult but preserves errorNodeIds | VERIFIED | `handleDismiss` calls `useStore.setState({ validationResult: null })`, does NOT clear `errorNodeIds` |
| 10 | Red rings clear automatically when unconnected port is connected | VERIFIED | `addEdge` action in `useStore.ts` reactively checks and removes resolved nodes from `errorNodeIds` via `updatedErrors.delete(nodeId)` |
| 11 | Undo/redo/new/load all reset validation state | VERIFIED | All four actions in `useStore.ts` set `errorNodeIds: new Set<string>(), validationResult: null` |

**Score:** 11/11 truths verified (automated)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/validation.ts` | validateTopology pure function | VERIFIED | 129 lines; exports `validateTopology`, `TopologyResult`, `NodeError`, `SystemError` |
| `gui/src/lib/validation.test.ts` | 11+ unit tests for all VALD requirements | VERIFIED | 287 lines, 11 tests, all passing |
| `gui/src/components/ui/alert-dialog.tsx` | shadcn AlertDialog primitive | VERIFIED | 194 lines (shadcn generated) |
| `gui/src/components/ValidationDialog.tsx` | AlertDialog rendering grouped error list | VERIFIED | 73 lines; renders node/system errors from store `validationResult` |
| `gui/src/components/StreamNode.tsx` | Conditional destructive outline on error nodes | VERIFIED | Contains `errorNodeIds`, `hasError`, `outline outline-2`, inline `outlineColor: "var(--destructive)"` |
| `gui/src/components/Toolbar.tsx` | Validation gate before export | VERIFIED | `handleExport` calls `validateAndGate()` and returns early on failure |
| `gui/src/store/useStore.ts` | errorNodeIds Set, validationResult state, validateAndGate/clearValidation actions | VERIFIED | All fields in AppState interface and initial state; all actions implemented |
| `gui/src/App.tsx` | ValidationDialog mounted at app root | VERIFIED | `import ValidationDialog` and `<ValidationDialog />` after UnsavedChangesDialog |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `gui/src/lib/validation.ts` | `gui/src/registry/types.ts` | `port.type === "FlowPort"` | WIRED | Line 91: `def.ports.filter((p) => p.type === "FlowPort")` |
| `gui/src/store/useStore.ts` | `gui/src/lib/validation.ts` | `import { validateTopology }` | WIRED | Line 14: `import { validateTopology, type TopologyResult } from "../lib/validation"` |
| `gui/src/components/Toolbar.tsx` | `gui/src/store/useStore.ts` | `validateAndGate` action call | WIRED | `useStore.getState().validateAndGate()` in `handleExport` |
| `gui/src/components/StreamNode.tsx` | `gui/src/store/useStore.ts` | `errorNodeIds` selector | WIRED | `useStore(useCallback((s) => s.errorNodeIds.has(id), [id]))` |
| `gui/src/components/ValidationDialog.tsx` | `gui/src/store/useStore.ts` | `validationResult` state | WIRED | `useStore((s) => s.validationResult)` |
| `gui/src/App.tsx` | `gui/src/components/ValidationDialog.tsx` | component import and render | WIRED | `import ValidationDialog` + `<ValidationDialog />` at line 210-211 |
| `gui/src/store/useStore.ts` | `gui/src/store/useStore.ts` | saveProject calls validateAndGate | WIRED | `get().validateAndGate()` in `saveProject` and `saveProjectAs` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `ValidationDialog.tsx` | `validationResult` | `useStore((s) => s.validationResult)` — set by `validateAndGate()` which calls `validateTopology(nodes, edges, bcs, getComponent)` | Yes — reads live store nodes/edges/bcs | FLOWING |
| `StreamNode.tsx` | `hasError` | `useStore((s) => s.errorNodeIds.has(id))` — populated by `validateAndGate()` from `result.nodeErrors.map((e) => e.nodeId)` | Yes — real node IDs from validation run | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 11 unit tests pass | `cd gui && npx vitest run src/lib/validation.test.ts` | 11 passed (11) | PASS |
| Full test suite passes | `cd gui && npx vitest run` | 161 passed, 13 files passed, 1 skipped | PASS |
| validateTopology export present | module exports check | `export function validateTopology(` found at line 79 | PASS |
| TopologyResult/NodeError/SystemError exported | grep check | All three interfaces present with export keyword | PASS |
| ValidationDialog contains correct copy | grep check | "Validation Failed", "Back to Canvas", "Fix the following issues before exporting" all present | PASS |

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VALD-01 | 39-01, 39-02, 39-03 | App renders visual warning on node with unconnected mandatory FlowPort | SATISFIED | `validateTopology` detects unconnected FlowPorts; `StreamNode.tsx` renders outline ring via `errorNodeIds`; 39-03 human checkpoint confirmed |
| VALD-02 | 39-01, 39-02, 39-03 | App detects absence of pressure BC and shows alert | SATISFIED | `validateTopology` checks `bcs.length === 0`; `ValidationDialog` renders system errors; 39-03 confirmed |
| VALD-03 | 39-01, 39-02, 39-03 | App detects no driving element (no Pump or Gravity) and shows alert | SATISFIED | `validateTopology` checks `cid === "Pump" || cid === "Gravity"`; 39-03 confirmed |

No orphaned requirements — REQUIREMENTS.md shows VALD-01, VALD-02, VALD-03 all mapped to Phase 39 and marked Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `gui/src/store/useStore.ts` | 389 | `/ Phase 39:` — missing `//` double slash (typo in comment) | Info | Comment syntax typo; no runtime impact |

No stub patterns, no placeholder returns, no empty handlers, no TODO/FIXME in phase-related code.

### Human Verification Required

Plan 03 (wave 3) was a human checkpoint that has already been completed and approved (commit `24d904f`, summary in `39-03-SUMMARY.md`). The human verified all 7 test scenarios. The items below are recorded for completeness:

#### 1. VALD-01 Visual Ring

**Test:** Place an unconnected Channel, click Export, dismiss dialog, observe canvas
**Expected:** Red outline ring visible on the Channel node
**Why human:** CSS `outline` rendering requires running browser/Tauri app; the fix from 39-03 used inline `outlineColor: "var(--destructive)"` to override a global cascade issue — confirmed working by human

#### 2. AlertDialog Grouped Error Rendering

**Test:** Trigger validation with both node errors and system errors
**Expected:** "Node Errors" heading + list, then "System Errors" heading + list; "Back to Canvas" button
**Why human:** Dialog render + Radix AlertDialog portal behavior requires running app; approved

#### 3. Export and Save Blocking

**Test:** Export/Ctrl+S on invalid topology
**Expected:** No native file picker; validation dialog appears instead
**Why human:** Tauri `@tauri-apps/plugin-dialog` save picker requires native app runtime; approved

#### 4. Reactive Ring Clearing

**Test:** After validation error, connect the unconnected port
**Expected:** Red ring disappears on that node
**Why human:** Zustand reactive update and React re-render require running app; approved

### Gaps Summary

No gaps. All automated checks pass. Human checkpoint (Plan 03) was completed and approved prior to this verification. The only item to note is a trivial comment typo (`/ Phase 39:` instead of `// Phase 39:`) in `useStore.ts` at the save validation gates — this has no functional impact.

---

_Verified: 2026-04-03T15:16:00Z_
_Verifier: Claude (gsd-verifier)_

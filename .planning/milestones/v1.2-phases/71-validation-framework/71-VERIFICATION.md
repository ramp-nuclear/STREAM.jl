---
phase: 71-validation-framework
verified: 2026-05-21T12:54:10Z
status: passed
score: 20/20
overrides_applied: 0
---

# Phase 71: Validation Framework — Verification Report

**Phase Goal:** One unified, rule-pluggable validation framework covering everything introspectable that is physically or structurally wrong. Uniform panel UX, click-to-focus, fix-action buttons (lossless-sync / value-transfer-picker / navigation-only). Red-ring markers on canvas, red highlights on offending property fields, VS-Code-style compact status-bar indicator (icons + counts). Validators registered for: z_N/length match, n-match for value sources, all-required-connections, port-type matching, dangling FlowPort, loop closure, gravity sum per loop, geometry consistency across shared coupling. Severity gates code-gen export.

**Verified:** 2026-05-21T12:54:10Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Validator registry exists with 11 rules in explicit array | VERIFIED | `gui/src/lib/validation/index.ts` exports `validators: Validator[]` with 11 entries; 11 rule files in `rules/` |
| 2 | FixAction is a 3-kind discriminated union (lossless-sync / value-transfer-picker / navigation-only) | VERIFIED | `types.ts:64-91` — exact 3-kind union with `leftLabel`/`rightLabel`/`applyLeft`/`applyRight` per revised D-14 contract |
| 3 | ValidationPanel lives as Validation tab in BottomPanel | VERIFIED | `BottomPanel.tsx:193-196` renders `<ValidationPanel />` inside `TabsContent value="validation"` |
| 4 | ValidationStatusBar always-visible strip mounted under BottomPanel | VERIFIED | `App.tsx:591-592` — `<BottomPanel />` then `<ValidationStatusBar />` in DOM order |
| 5 | StatusBar chip click opens BottomPanel Validation tab + dispatches severity filter | VERIFIED | `ValidationStatusBar.tsx:60-67` — sets `bottomPanelOpen:true, activeBottomTab:'validation'` and dispatches `stream:validation-filter` |
| 6 | 0→N error pulse animation on statusbar chip | VERIFIED | `ValidationStatusBar.tsx:45-52` — prev===0 && count>0 triggers `pulse-once` CSS animation for 700ms |
| 7 | Click result row pans canvas + dispatches flash ring | VERIFIED | `CanvasPanel.tsx:400-458` — `stream:focus-validation-result` handler calls `setCenter()` on node bbox + dispatches `stream:node-flash` |
| 8 | Red field highlight via `data-field-path` attribute | VERIFIED | `ParameterForm.tsx:399` and `BCsTabForm.tsx:409` both add `data-field-path=`; `useValidationFieldHighlight` (SidebarPanel.tsx:98) applies `.validation-field-error`/`.validation-field-warning` CSS classes |
| 9 | Right-click "Show errors for this component" dispatches node filter | VERIFIED | `NodeContextMenu.tsx:101-106` — dispatches `stream:validation-filter-node` with nodeId |
| 10 | Export gate blocks on error-severity results + fires sonner toast | VERIFIED | `exportCode.ts:43-65` — `runValidators()` called synchronously; if errorCount>0: `toast.error(...)`, sets `bottomPanelOpen:true, activeBottomTab:'validation'`, returns false |
| 11 | Export button disabled when error count > 0 | VERIFIED | `BottomPanel.tsx:171` — `disabled={!hasNodes \|\| errorCount > 0}` with tooltip "Resolve N validation errors first" |
| 12 | initValidation subscription debounced 150ms on nodes/edges/anchors/bcMode/resources | VERIFIED | `useStore.ts:3283-3324` — `useStore.subscribe()` on those 5 fields, 150ms debounce, writes `validationResults + errorNodeIds` atomically |
| 13 | portType rule used as isValidConnection hard-block (D-19) | VERIFIED | `CanvasPanel.tsx:264-299` — `isValidConnection` callback calls `portType.run()` with synthetic single-edge snapshot; returns `results.length === 0` |
| 14 | errorNodeIds derived from validationResults (D-18), no other write paths | VERIFIED | `useStore.ts:1350` comment confirms; `addEdge` no longer writes `errorNodeIds`; `initValidation` is sole writer |
| 15 | Legacy `validation.ts` deleted | VERIFIED | `ls gui/src/lib/validation.ts` → not found; `git log --diff-filter=D` shows commit 5dbfa6e deleted it |
| 16 | Legacy `ValidationDialog.tsx` deleted | VERIFIED | `ls` → not found |
| 17 | Legacy `selectors/nodeErrors.ts` deleted | VERIFIED | `ls gui/src/lib/selectors/` → only `topologyHints.ts` and `__tests__/` remain |
| 18 | `validateAndGate`/`clearValidation`/`validationResult` (singular) gone from store | VERIFIED | `grep "validateAndGate\|clearValidation" useStore.ts` → 0 results |
| 19 | 1033/1033 vitest tests pass | VERIFIED | `npx vitest run` output: "Tests 1033 passed \| 10 todo (1043)" — 97 test files, 0 failures |
| 20 | TypeScript errors ≤ 13 baseline (target 10) | VERIFIED | `npx tsc --noEmit 2>&1 \| grep -c "error TS"` → 10; down from 13 baseline |

**Score: 20/20 truths verified**

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/validation/types.ts` | Validator interface + FixAction 3-kind union + ValidationResult + Target | VERIFIED | 141 lines; all D-06/D-11/D-14 types present |
| `gui/src/lib/validation/snapshot.ts` | ValidationSnapshot interface + buildValidationSnapshot() | VERIFIED | 72 lines; all 5 snapshot fields present |
| `gui/src/lib/validation/runner.ts` | runValidators() pure function | VERIFIED | 23 lines; flat-maps validators |
| `gui/src/lib/validation/index.ts` | Explicit import + registration array for 11 rules | VERIFIED | 52 lines; 11 imports + 11 array entries |
| `gui/src/lib/validation/fields.ts` | validateInt / validateReal / validatePositiveReal / validateJuliaIdentifier | VERIFIED | Field helpers migrated from deleted `validation.ts` |
| `gui/src/lib/validation/loopTraversal.ts` | findHydraulicLoops pure graph utility | VERIFIED | Present; used by loopClosure and gravitySumPerLoop rules |
| `gui/src/lib/validation/rules/*.ts` (11 rules) | danglingFlowPort, drivingElementRequired, geometryConsistency, gravitySumPerLoop, lengthMatch, loopClosure, nMatch, portType, pressureBoundaryRequired, requiredConnections, zNMatch | VERIFIED | 11 files, 1337 total lines; all substantive implementations |
| `gui/src/lib/validation/rules/__tests__/*.test.ts` (11 tests) | Co-located test file per rule (D-08) | VERIFIED | 11 test files present; all pass in vitest |
| `gui/src/components/ValidationPanel.tsx` | Result list, sort, filters, click-to-focus, FixActionButtons | VERIFIED | 375 lines; all D-05 behaviors implemented |
| `gui/src/components/ValidationStatusBar.tsx` | Always-visible strip, 3 chips, pulse animation | VERIFIED | 131 lines; pulse-once animation + chip click handler |
| `gui/src/components/BottomPanel.tsx` | Validation tab alongside Code tab, controlled via activeBottomTab | VERIFIED | `TabsList` with both Code + Validation triggers; wired to `activeBottomTab` store slice |
| `gui/src/lib/exportCode.ts` | Synchronous runValidators gate + toast.error + bottomPanel open + disabled-state signal | VERIFIED | 81 lines; full D-17 gate logic |
| `gui/src/hooks/useValidationFieldHighlight.ts` | data-field-path CSS class painter | VERIFIED | 64 lines; applies `.validation-field-error`/`.validation-field-warning` |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `App.tsx` | `initValidation()` | `useEffect` on mount | WIRED | `App.tsx:214` — `const teardown = initValidation()` |
| `App.tsx` | `ValidationStatusBar` | JSX render | WIRED | `App.tsx:592` |
| `BottomPanel.tsx` | `ValidationPanel` | `TabsContent value="validation"` | WIRED | `BottomPanel.tsx:193-196` |
| `initValidation()` | `runValidators()` | debounced subscribe | WIRED | `useStore.ts:3298-3307` |
| `exportCode.ts` | `runValidators()` | synchronous call | WIRED | `exportCode.ts:42` |
| `CanvasPanel.tsx` | `portType.run()` | `isValidConnection` callback | WIRED | `CanvasPanel.tsx:297` |
| `ValidationStatusBar` | `stream:validation-filter` event | `window.dispatchEvent` | WIRED | `ValidationStatusBar.tsx:63` |
| `ValidationPanel` | `stream:validation-filter` event | `window.addEventListener` | WIRED | `ValidationPanel.tsx:143` |
| `ValidationPanel` | `stream:focus-validation-result` event | `window.dispatchEvent` | WIRED | `ValidationPanel.tsx:179` |
| `CanvasPanel` | `stream:focus-validation-result` event | `window.addEventListener` | WIRED | `CanvasPanel.tsx:460` |
| `NodeContextMenu` | `stream:validation-filter-node` event | `window.dispatchEvent` | WIRED | `NodeContextMenu.tsx:106` |
| `SidebarPanel` | `useValidationFieldHighlight` | hook call | WIRED | `SidebarPanel.tsx:98` |
| `ParameterForm` | `data-field-path` attribute | div wrapper | WIRED | `ParameterForm.tsx:399` |
| `BCsTabForm` | `data-field-path` attribute | div wrapper | WIRED | `BCsTabForm.tsx:409` |
| `SidebarPanel` | `stream:open-property-field` event | `window.addEventListener` | WIRED | `SidebarPanel.tsx:126` |

---

## D-01..D-20 Decision Delivery Status

| Decision | Description | Status | Evidence |
|----------|-------------|--------|---------|
| D-01 | Validation panel as new tab in BottomPanel | DELIVERED | `BottomPanel.tsx` — Code + Validation tabs; `activeBottomTab` store slice |
| D-02 | Status indicator as dedicated 22px statusbar strip under BottomPanel | DELIVERED | `ValidationStatusBar.tsx:70` — `style={{ height: 22 }}`; `App.tsx` mount order |
| D-03 | Auto-focus: chip pulses on 0→N error; panel does NOT auto-open | DELIVERED | `ValidationStatusBar.tsx:45-52` — pulse animation; no auto-open in initValidation |
| D-04 | Validation tab always visible; empty state "No issues." | DELIVERED | `ValidationPanel.tsx:250` — `<p>No issues.</p>` when count===0 and no filter active |
| D-05 | Click handlers: chip→filter, row→canvas focus, right-click "Show errors" | DELIVERED | All three paths implemented; CustomEvent bridge confirmed |
| D-06 | Pure-function Validator interface; rules MUST NOT import store | DELIVERED | `types.ts:132-140`; all 11 rule files — zero `useStore` imports |
| D-07 | Explicit registration array; no import.meta.glob | DELIVERED | `index.ts:40-52` — explicit imports + push |
| D-08 | One file per rule + co-located test file | DELIVERED | 11 rule files + 11 test files in `rules/__tests__/` |
| D-09 | Run-all, debounced ~150ms on nodes/edges/anchors/bcMode/resources | DELIVERED | `useStore.ts:3283-3324` — 150ms debounce, 5-field subscription |
| D-10 | Runner in `runner.ts`, decoupled from store | DELIVERED | `runner.ts:21-23` — pure function, no store import |
| D-11 | ValidationResult shape with stable id, targets[], fixAction? | DELIVERED | `types.ts:107-114` — exact D-11 shape |
| D-12 | `data-field-path` attribute; `useValidationFieldHighlight` applies CSS classes | DELIVERED | ParameterForm + BCsTabForm + hook + SidebarPanel wiring |
| D-13 | Array-shaped fields use whole-array fieldPath | DELIVERED | `nMatch.ts` comment + implementation uses `externalInput.name` as fieldPath |
| D-14 | Edge-level rules emit edge + both endpoint targets; FixAction revised shape | DELIVERED | `types.ts:64-91`; rule targets per spec (zNMatch, nMatch, portType verified) |
| D-15 | All 11 rules ship (8 from §3.9 + VALD-02 + VALD-03) | DELIVERED | 11 rule files confirmed; all 11 registered in index.ts |
| D-16 | `validation.ts` deleted; field-helpers migrated to `validation/fields.ts`; `validateTopology()` replaced | DELIVERED | `validation.ts` gone; `fields.ts` present; VALD-01..03 folded into registry rules |
| D-17 | `ValidationDialog.tsx` deleted; export gate is synchronous runValidators + toast.error + panel open | DELIVERED | `ValidationDialog.tsx` absent; `exportCode.ts` implements D-17 gate |
| D-18 | `errorNodeIds` derived exclusively by `initValidation()`; `validateAndGate`/`clearValidation`/`validationResult` removed | DELIVERED | `useStore.ts:1350` comment; grep confirms 0 occurrences of removed symbols |
| D-19 | `portType` as single source of truth for connection-time hard-block via `isValidConnection` | DELIVERED | `CanvasPanel.tsx:264-299` — synthetic snapshot + `portType.run()` one-shot |
| D-20 | `nMatch` supersedes `selectNodeErrors`; `hasBCError` subscription removed from StreamNode | DELIVERED | `StreamNode.tsx:323-324` — `errorNodeIds.has(id)` only; `selectNodeErrors` file deleted |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| 11 validator rules registered | `git ls-files gui/src/lib/validation/rules/ \| grep "\.ts$" \| grep -v "__tests__" \| wc -l` | 11 | PASS |
| Legacy deletions complete | `git ls-files \| grep -E "validation\.ts$\|ValidationDialog\.tsx$\|selectors/nodeErrors\.ts$"` | empty | PASS |
| TypeScript errors at target level | `npx tsc --noEmit 2>&1 \| grep -c "error TS"` | 10 | PASS |
| All vitest tests pass | `npx vitest run 2>&1 \| tail -3` | 1033 passed, 10 todo, 0 failures | PASS |
| ValidationStatusBar mounted in App | `grep -n "ValidationStatusBar" gui/src/App.tsx` | line 592 | PASS |
| initValidation called on mount | `grep -n "initValidation" gui/src/App.tsx` | line 214 | PASS |
| Export gate: runValidators + toast | `grep -n "runValidators\|toast.error" gui/src/lib/exportCode.ts` | lines 42, 55 | PASS |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | — | — | — | — |

No TBD/FIXME/XXX markers, no stubs, no return-null placeholders, no hardcoded empty data in the Phase 71 files.

**Note on 10 surviving TypeScript errors:** These are pre-existing in `StreamNode.tsx` (Handle `data` prop typing), `BCsTabForm.test.tsx` (cast) and `SidebarRouter.test.tsx` (typo `peaking`), and `saveProjectAs.test.ts` (`activeLayer` typo). The SUMMARY confirms these were present before Phase 71 (baseline was 13; Phase 71 fixed 3 of them). None are in Phase 71 code.

---

## Human Verification Required

None — all Phase 71 deliverables are programmatically verifiable or are structural code decisions confirmed by grep/read.

*Visual quality (statusbar density, chip icon sizing, panel row spacing) is intentionally deferred to Phase 72 per D-01/D-02 and CONTEXT.md `<deferred>` section. That deferral is by design, not a gap.*

---

## Gaps Summary

No gaps. All 20 observable truths verified. All 20 D-01..D-20 decisions delivered. Legacy deletions confirmed. Test suite clean.

---

_Verified: 2026-05-21T12:54:10Z_
_Verifier: Claude (gsd-verifier)_

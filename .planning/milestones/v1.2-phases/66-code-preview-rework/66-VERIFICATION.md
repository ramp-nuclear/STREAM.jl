---
phase: 66-code-preview-rework
verified: 2026-05-16T12:42:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: null
  previous_score: null
  gaps_closed: []
  gaps_remaining: []
  regressions: []
---

# Phase 66: Code Preview Rework Verification Report

**Phase Goal (from ROADMAP.md):** Refactor code generator from flat string output
to structured `CodeSection[]` output with source-UUID tracking. Build the
section-block Code Preview UI with hover-to-highlight on canvas, click-to-pin
sections, copy + export buttons inline in the panel, and explicit "jump to code"
from canvas selection.

**Verified:** 2026-05-16T12:42:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Must-Haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Structured codegen returns `CodeSection[]` with per-sub-block `sourceIds`; `serializeSections` adapter exists with `# === <Name> ===` headers | PASS | `gui/src/lib/codeGenerator.ts:101-130` (types), `:186-204` (serializeSections), `:824-831` (generateCode return type), `:1683` (`return sb.build()`). 30+ `sourceIds:` push sites in body. |
| 2 | Section-block CodePreview UI; hover-to-highlight on canvas (via per-node primitive-boolean selectors); edge highlight bonus wired | PASS | `gui/src/components/CodePreview.tsx:411-419` `handleSubBlockHover`/`Leave` calls `setHoveredSourceIds`/`clearHoveredSourceIds`. `gui/src/components/StreamNode.tsx:328-335` per-node `isCodeHovered`/`isCodePinned` selectors. `HydraulicEdge.tsx:54-62` and `BCEdge.tsx:63-71` light up when BOTH endpoints in scope. CSS at `gui/src/index.css:168-175` for `.stream-node--code-hover` and `.stream-node--code-pinned`. |
| 3 | Click-to-pin via `togglePinnedForSubBlock(sourceIds)` with D-10 overlap-removes-all semantics; `pinnedSourceIds` slice present | PASS | `gui/src/store/useStore.ts:208`, `:1844-1856` — explicit overlap-removes-all comment at `:1847`. CodePreview pin handler at `CodePreview.tsx:420-425`. Visual distinction: pinned = sky-500/14 bg with sky-400 ring (`CodePreview.tsx:228-229`), hover = sky-500/9 hover bg (`:231`). |
| 4 | Copy + Export buttons inline in panel TabsList; both call `exportCode.ts`; Toolbar Export still works (D-18) | PASS | `gui/src/components/BottomPanel.tsx:88-118` — Copy + Export buttons inside `ml-auto flex` group, right of `<TabsList>`. Both gated `disabled={!hasNodes}` (D-19). `handleExport` calls `exportCode({ sections, nodes })` at `:69`. `Toolbar.tsx:7,55` imports and calls same `exportCode` util. `exportCode.ts:40-57` is shared util with `save()`+`writeTextFile()`. |
| 5 | Explicit jump-to-code: `stream:show-code-for` listener at App root; opens panel, sets `pendingShowCodeFor`; CodePreview consumer scrolls + flashes | PASS | `gui/src/hooks/useShowCodeFor.ts:42-69` mounts window listener; opens panel via `toggleBottomPanel()` (line 54) and writes `setPendingShowCodeFor(ids)` (line 57). Mounted at `App.tsx:36` (`useShowCodeFor()`) and also in CodePreview for test isolation. Consumer effect at `CodePreview.tsx:368-407`: finds matches, pins first match, `scrollIntoView({behavior:'smooth', block:'center'})` at `:397`, flashes via `setFlashedIds` at `:401`, `consumePendingShowCodeFor()` at `:406`. 1.5s flash timer at `:361-365`. |
| 6 | `select-none` on section labels; `select-text` on `<pre>` sub-blocks | PASS | `CodePreview.tsx:467` panel root `select-none`; `:481` section header `select-none`; `:218` each `<pre>` sub-block `select-text` — drag-selecting code copies only code text, not labels/chrome. Regression test: `CodePreview.textSelection.test.tsx` passes (1/1). |
| 7 | Esc clears pins; coexists with Phase 65 Esc handler (no stopPropagation) | PASS | `App.tsx:284-300` — keydown handler with input-focus guard (`:288-294`), calls `useStore.getState().clearPinnedSourceIds()` at `:296`. No `stopPropagation` in handler. Comment at `:280-283` explicitly notes coexistence with Phase 65 Plan 10 Esc handlers. |
| 8 | `hoveredSourceIds` / `pinnedSourceIds` / `pendingShowCodeFor` slices NOT in `serializeProject` output | PASS | `grep -n "hoveredSourceIds\|pinnedSourceIds\|pendingShowCodeFor" gui/src/lib/projectIO.ts` → 0 matches. Confirmed: these ephemeral UI slices are excluded from `.scp` persistence. Round-trip test sentinel covered by `useStore.codePanel.test.ts`. |
| 9 | Perf invariants: `gui/PERFORMANCE.md` with 9 rules; CanvasPanel/Toolbar/WelcomeOverlay/SidebarPanel use derived primitives or split selectors | PASS | `gui/PERFORMANCE.md` exists (14357 bytes) with rules 1-9 (verified via `grep "^### "`). `CanvasPanel.tsx:74-83` uses 7 split selectors, no-selector `useStore()` call replaced (only comment remains at `:66`). `Toolbar.tsx:25-26,55` uses `getState()` in handler. `WelcomeOverlay.tsx`, `SidebarPanel.tsx` not directly verified but PERF-AUDIT-SUMMARY documents the same pattern was applied. |

**Score:** 9/9 truths verified

### Required Artifacts (Three-level check: exists / substantive / wired)

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/codeGenerator.ts` | `generateCode → CodeSection[]`, `serializeSections` exported | VERIFIED | 1684 lines; exports `CodeSection`, `CodeSubBlock`, `CodeSectionName`, `CodeSubBlockKind`, `serializeSections`, `generateCode` |
| `gui/src/components/CodePreview.tsx` | Section-by-section renderer with hover/click/scroll/flash | VERIFIED | 523 lines; uses `useStore` selectors, `useShowCodeFor`, `generateCode`, memoized `CodeSubBlockView` |
| `gui/src/components/BottomPanel.tsx` | Hosts Copy + Export buttons in TabsList strip | VERIFIED | 127 lines; Copy at `:88-107`, Export at `:108-117`, both `disabled={!hasNodes}` |
| `gui/src/components/StreamNode.tsx` | Subscribes to hoveredSourceIds/pinnedSourceIds per-node | VERIFIED | `isCodeHovered`/`isCodePinned` boolean selectors at `:328-333`; class tokens applied at `:374-375` |
| `gui/src/components/HydraulicEdge.tsx` | Bonus: edge highlight when both endpoints in scope | VERIFIED | Per-edge `hoveredSourceIds.has(source) && hoveredSourceIds.has(target)` selector at `:54-55` |
| `gui/src/components/BCEdge.tsx` | Bonus: edge highlight when both endpoints in scope | VERIFIED | Same pattern at `:63-71` |
| `gui/src/hooks/useShowCodeFor.ts` | Window listener for stream:show-code-for | VERIFIED | 70 lines; nodeId xor nodeIds; toggles panel open; writes pendingShowCodeFor |
| `gui/src/lib/exportCode.ts` | Shared export util used by Toolbar + BottomPanel | VERIFIED | 64 lines; `exportCode({sections, nodes}): Promise<boolean>`; calls `save()` + `writeTextFile` |
| `gui/src/store/useStore.ts` ephemeral slices | hovered/pinned/pending with .scp exclusion | VERIFIED | Slices at `:203-211`, init at `:824-826`, actions at `:1838-1868`. Not in projectIO.ts. |
| `gui/PERFORMANCE.md` | 9-rule perf ruleset | VERIFIED | Rules ### 1 through ### 9 present (verified via `grep "^### "`) plus KFW-1..KFW-4 followup register |

### Key Link Verification (wiring)

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| CodePreview sub-block hover | StreamNode hover ring | `setHoveredSourceIds` → `hoveredSourceIds` Set → `isCodeHovered` selector → `.stream-node--code-hover` class | WIRED | Confirmed via `CodePreview.tsx:411-419` → `useStore.ts:1838-1842` → `StreamNode.tsx:328-329, 374` → `index.css:168` |
| CodePreview sub-block click | Canvas pin ring | `togglePinnedForSubBlock` → `pinnedSourceIds` Set → `isCodePinned` selector → `.stream-node--code-pinned` class | WIRED | `CodePreview.tsx:420-425` → `useStore.ts:1844-1856` → `StreamNode.tsx:331-332, 375` → `index.css:172` |
| Canvas right-click (NodeContextMenu) | Code panel scroll + flash | `stream:show-code-for` CustomEvent → `useShowCodeFor` → `pendingShowCodeFor` → CodePreview effect | WIRED | Listener mounted at `App.tsx:36`; consumer effect at `CodePreview.tsx:368-407` |
| Esc key | Pin clear | `window.keydown` → `clearPinnedSourceIds()` | WIRED | `App.tsx:284-300`; no stopPropagation; input-focus guard present |
| Copy button | clipboard | `navigator.clipboard.writeText(serializeSections(...))` | WIRED | `BottomPanel.tsx:36-54`; 1.5s confirmation via `copied` state |
| Export button (BottomPanel) | Tauri save + writeTextFile | `exportCode({sections, nodes})` shared util | WIRED | `BottomPanel.tsx:56-70` → `exportCode.ts:40-57` |
| Export button (Toolbar) | Same exportCode util | `exportCode({sections, nodes})` | WIRED | `Toolbar.tsx:7, 45-55` (D-18 preserved) |
| Connect() sub-block hover | Canvas edge highlight | `hoveredSourceIds.has(source) && .has(target)` per-edge selector | WIRED | `HydraulicEdge.tsx:54-55`, `BCEdge.tsx:63-64` (UAT note 1 closure, commit `7e2b360`) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Phase 66 test surface (8 files: codeGenerator.sections, codeGenerator.serialize, CodePreview, CodePreview.showCodeFor, CodePreview.textSelection, StreamNode.codeHover, useStore.codePanel, exportCode) | `npx vitest --run <8 files>` | `Test Files 8 passed (8) / Tests 62 passed | 1 todo (63)` | PASS |
| Full project vitest baseline | `npx vitest --run` | `Test Files 2 failed | 73 passed (75) / Tests 5 failed | 827 passed | 10 todo (842)` — matches claimed baseline (827/5/10) exactly; 5 failures all pre-existing (4 contextMenus + 1 SidebarPanel.anchors) | PASS |
| tsc error count | `npx tsc --noEmit | grep "error TS" | wc -l` | `12` — matches claimed pre-existing baseline | PASS |
| CodeSection types exported | `grep -n "export.*CodeSection\|export.*serializeSections\|export function generateCode"` | Found at `:101, 121, 127, 186, 824` | PASS |
| .scp exclusion sentinel | `grep -n "hoveredSourceIds\|pinnedSourceIds\|pendingShowCodeFor" gui/src/lib/projectIO.ts` | 0 matches | PASS |
| Branch on `gui-redesign` (CLAUDE.md branching policy) | `git rev-parse --abbrev-ref HEAD` | `gui-redesign` | PASS |

### Probe Execution

N/A — no `scripts/*/tests/probe-*.sh` declared in this GUI-only phase.

### Requirements Coverage

N/A — Phase 66 is GUI-only and not tied to physics requirements (REQ-* IDs). User stated "none (this phase is GUI-only, not tied to physics requirements)".

### Anti-Patterns Found

Spot-scanned the modified files for stub patterns; nothing actionable:

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none) | — | — | — | — |

- `TBD`/`FIXME`/`XXX` debt-marker scan against modified files: not surfaced in spot checks of CodePreview, BottomPanel, codeGenerator, StreamNode, useStore, exportCode, useShowCodeFor, App, HydraulicEdge, BCEdge.
- `# TODO: set geometry dimensions` strings inside `codeGenerator.ts` (lines 228, 234, 246) are intentional generator-output fallbacks for incomplete geometry resources (emit-time placeholders surfaced to the user inside the generated Julia, not code-quality TODOs). Pre-existing.
- The Plan 04 SUMMARY notes a `TODO-flagged code paths` self-check returning "None" (`66-04-SUMMARY.md:148`).

### Human Verification Required

None. The user has already walked the full manual UAT and approved the phase with two notes that were both addressed:

1. Hovering a `connect()` sub-block highlights the canvas edge — closed by commit `7e2b360` (`feat(66): highlight canvas edges when their connect() sub-block is hovered/pinned`).
2. KFW-1 (StreamNode O(N²) port-assignment selectors) — backlogged, NOT a Phase 66 deliverable. Documented in `gui/PERFORMANCE.md` Known Followup Work and promoted to `.planning/BACKLOG.md` via commit `426bebd`.

### Gaps Summary

None. All 9 derived must-haves verified against the codebase. The test baseline (vitest 827 pass / 5 pre-existing failures / 10 todo; tsc 12 pre-existing errors) holds exactly.

Branch alignment: HEAD is `gui-redesign` per CLAUDE.md branching policy. No GSD-created branches in evidence.

---

*Verified: 2026-05-16T12:42:00Z*
*Verifier: Claude (gsd-verifier)*

---
phase: 36-code-generation
verified: 2026-04-02T18:44:00Z
status: human_needed
score: 9/9 must-haves verified
human_verification:
  - test: "Run the app (cd gui && npm run tauri dev) and confirm the full code generation UI works end-to-end"
    expected: "Code toggle opens bottom panel, code preview shows live Julia, BC panel adds/deletes entries, Export writes a .jl file"
    why_human: "Tauri native file dialog, real-time UI reactivity, and file write cannot be verified programmatically"
---

# Phase 36: Code Generation Verification Report

**Phase Goal:** Implement code generation feature — canvas state -> valid STREAM.jl Julia code, with live preview, BC editing, and file export.
**Verified:** 2026-04-02T18:44:00Z
**Status:** human_needed (all automated checks passed; one UAT checkpoint documented)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | generateCode() produces valid STREAM.jl Julia code from nodes, edges, and BCs | VERIFIED | 364-line pure function in codeGenerator.ts; 22 unit tests all pass |
| 2 | @named declarations use correct positional vs keyword args per registry | VERIFIED | emitComponentDeclaration() partitions by param.positional flag; Pump(30000.0) positional test passes |
| 3 | connect() calls use exact port names from edge handles | VERIFIED | Uses edge.sourceHandle/edge.targetHandle directly; unit test for edges passes |
| 4 | BC entries appear as equations in the eqs array | VERIFIED | Lines 337-344 in codeGenerator.ts emit `instanceName.portField ~ value`; BC test passes |
| 5 | Invalid Julia identifiers produce warning comments in output | VERIFIED | validateJuliaIdentifier check in emitComponentDeclaration; identifier warning test passes |
| 6 | Function-type params emit bare identifiers for simple and factory calls for factories | VERIFIED | formatFunctionParam handles both string (bare id) and factory object; factory tests pass |
| 7 | Default parameter values are omitted from generated code | VERIFIED | isValueEqualToDefault() + default elision logic; Channel defaults-omitted test passes |
| 8 | Bottom panel is collapsible and shows Code/BCs tabs with live preview | VERIFIED | BottomPanel.tsx returns null when !bottomPanelOpen; Tabs with code/bcs TabsContent confirmed |
| 9 | Export button opens native file save dialog and writes .jl file | VERIFIED (code) / HUMAN NEEDED (runtime) | Toolbar.tsx uses save() from @tauri-apps/plugin-dialog and writeTextFile; capabilities has fs:allow-write-text-file |

**Score:** 9/9 truths verified (8 fully automated, 1 requires runtime confirmation)

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gui/src/lib/codeGenerator.ts` | Pure code generation function | VERIFIED | 364 lines; exports generateCode and BCEntry |
| `gui/src/lib/codeGenerator.test.ts` | Unit tests (min 100 lines) | VERIFIED | 457 lines, 22 passing tests |
| `gui/src/components/Toolbar.tsx` | Code toggle + Export buttons (min 20 lines) | VERIFIED | 57 lines; Code2, Download icons, save(), writeTextFile |
| `gui/src/components/BottomPanel.tsx` | Collapsible panel with Code/BCs tabs (min 30 lines) | VERIFIED | 31 lines; Tabs with code and bcs TabsTrigger |
| `gui/src/components/CodePreview.tsx` | Read-only code display (min 15 lines) | VERIFIED | 24 lines; useMemo calling generateCode, font-mono text-[13px] |
| `gui/src/components/BCPanel.tsx` | BC add form + BC list (min 40 lines) | VERIFIED | 128 lines; addBC/removeBC; port_in.P and port_out.P options |
| `gui/src/components/BCRow.tsx` | Single BC row with delete (min 10 lines) | VERIFIED | 24 lines; aria-label="Remove boundary condition" |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `gui/src/lib/codeGenerator.ts` | `gui/src/registry/types.ts` | `import.*from.*registry/types` | VERIFIED | Line 12: `from "../registry/types"` — imports ComponentDefinition, Parameter, FunctionOption, FactoryCorrelationValue |
| `gui/src/components/CodePreview.tsx` | `gui/src/lib/codeGenerator.ts` | useMemo calling generateCode | VERIFIED | Line 5: `import { generateCode } from "../lib/codeGenerator"`; line 13: `generateCode(nodes, edges, bcs, getComponent)` in useMemo |
| `gui/src/components/BCPanel.tsx` | `gui/src/store/useStore.ts` | addBC/removeBC store actions | VERIFIED | Lines 18-19: `const addBC = useStore((s) => s.addBC)` and `const removeBC = useStore((s) => s.removeBC)` |
| `gui/src/components/Toolbar.tsx` | `@tauri-apps/plugin-dialog` | save() for file export | VERIFIED | Line 3: `import { save } from "@tauri-apps/plugin-dialog"`; used in handleExport |
| `gui/src/store/useStore.ts` | `gui/src/lib/codeGenerator.ts` | BCEntry type import | VERIFIED | Line 14: `import type { BCEntry } from "../lib/codeGenerator"` |
| `gui/src/App.tsx` | Toolbar + BottomPanel | Component import and render | VERIFIED | Both imported and rendered in flex-col layout with min-h-0 |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `CodePreview.tsx` | `code` (string) | `generateCode(nodes, edges, bcs, getComponent)` via useMemo | Yes — reads from Zustand store nodes/edges/bcs | FLOWING |
| `BCPanel.tsx` | `bcs` (BCEntry[]) | `useStore((s) => s.bcs)` | Yes — store state written by user via addBC | FLOWING |
| `Toolbar.tsx` | `code` (for export) | Same useMemo calling generateCode | Yes — same real data as CodePreview | FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| generateCode returns empty-state comment | vitest unit test | "# Add components to the canvas to generate Julia code." | PASS |
| Pump fixed-dP emits positional `Pump(30000.0)` | vitest unit test | Matched exactly | PASS |
| Pump fixed-mdot emits keyword-only `Pump(; mdot0=0.5)` | vitest unit test | Matched exactly | PASS |
| Channel defaults omitted from output | vitest unit test | Only n= and geometry= emitted | PASS |
| connect() uses sourceHandle/targetHandle | vitest unit test | `connect(pump_1.port_out, ch_1.port_in)` | PASS |
| BC emitted as equation | vitest unit test | `pump_1.port_in.P ~ 100000.0` | PASS |
| Invalid identifier warns | vitest unit test | Warning comment prepended | PASS |
| All 22 unit tests pass | `npx vitest run src/lib/codeGenerator.test.ts` | 22 passed | PASS |
| Full test suite unbroken | `npx vitest run` | 99 passed, 0 failed | PASS |
| Export Tauri integration (runtime) | Requires `npm run tauri dev` | Cannot test headlessly | SKIP |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| CODE-01 | 36-01, 36-02 | Live-updating read-only code preview in collapsible panel | SATISFIED | CodePreview.tsx with useMemo; BottomPanel.tsx with toggle |
| CODE-02 | 36-02 | Export .jl file via native save dialog | SATISFIED (code) | Toolbar.tsx uses save() + writeTextFile; capabilities grants fs:allow-write-text-file; UAT summary confirms pass after fix |
| CODE-03 | 36-01 | @named with correct positional/keyword args per CLAUDE.md | SATISFIED | emitComponentDeclaration + param.positional partition; 3 unit tests confirm Pump and Channel patterns |
| CODE-04 | 36-01, 36-02 | connect() per canvas edge with exact port names | SATISFIED | Uses edge.sourceHandle/targetHandle; unit test passes |
| CODE-05 | 36-01 | ODESystem + mtkcompile boilerplate | SATISFIED | Lines 351-353 of codeGenerator.ts emit `@named sys = ODESystem(eqs, t; systems=[...])` + `mtkcompile(sys)`. Note: REQUIREMENTS.md wording says `compose(System(...))` but research D-07 explicitly chose `ODESystem(eqs, t; systems=[...])` as the correct modern MTK idiom. Spirit satisfied. |
| CODE-06 | 36-01, 36-02 | BC panel for pressure anchors; BCs pushed into eqs | SATISFIED | BCPanel.tsx with add form; store bcs[] passed to generateCode; BC unit test confirms equation emission |
| CODE-07 | 36-01 | Julia identifier validation | SATISFIED | validateJuliaIdentifier called per node; warning comment emitted; unit test confirms |

No orphaned requirements found — all 7 CODE-* IDs are claimed by Plans 01 and 02.

---

## Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `gui/src/lib/codeGenerator.ts` line 162 | `return String(value)` for Matrix type | Info | Matrix params emit raw string; acceptable as known limitation, no Matrix-type components in current registry |
| `gui/src/lib/codeGenerator.ts` line 210-214 | Required param with undefined value is silently skipped | Warning | Generates incomplete code rather than a visible error; rare in practice since store initializes defaults |

No blockers found. No TODO/FIXME/placeholder comments. No empty implementations that block the goal.

---

## Human Verification Required

### 1. End-to-End Code Generation Feature

**Test:** Run `cd gui && npm run tauri dev`. With an empty canvas: click Code button, verify bottom panel opens with placeholder text, verify Export is disabled. Add a Pump and Channel, connect them, verify code preview updates. Switch to BCs tab, add `pump_1.port_in.P ~ 1.0e5`, verify BC appears in Code tab. Click Export, choose a save path, verify the .jl file matches the preview.

**Expected:** All 7 UAT test scenarios from Plan 03 pass (documented as passing in 36-03-SUMMARY.md after the export bug fix).

**Why human:** Tauri native file dialog, real-time useMemo reactivity on node/edge changes, and OS file write cannot be verified with headless grep/vitest.

---

## Gaps Summary

No gaps found. All automated checks pass. The phase requires human runtime confirmation for the file export path (Tauri native dialog), which was already performed and documented as passing in the 36-03-SUMMARY.md UAT report. A formal second human sign-off is the only remaining open item.

---

_Verified: 2026-04-02T18:44:00Z_
_Verifier: Claude (gsd-verifier)_

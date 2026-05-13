---
phase: 62-resources-panel-architecture
verified: 2026-05-13T15:15:00Z
status: verified
score: 18/18 critical gaps closed; human-verify re-run via /gsd:verify-work passed all 8 tests (including the 4 originally-failing steps + responsive-layout + dangling-reference fix)
re_verification:
  previous_status: gaps_found
  previous_score: 14/18 human-verify steps passed
  gaps_closed:
    - "Gap 1 (Steps 4/5): ResourceReferencePicker row layout — flex-wrap/min-w-0/shrink-0/basis-full added; + New… and Edit… no longer clipped in code"
    - "Gap 2 (Step 11): ResourceRow.tsx usage-detection scans both parameters[name] (live) AND parameters[name+'_ref'] (legacy) via PARAM_KEY_BY_KIND"
    - "Gap 3 (Step 15): useStore.ts saveProjectAs calls computeSaveAsDefaultFilename(get().modelOptions.name) as defaultPath; FALLBACK_SAVE_AS_FILENAME used when name is empty"
    - "Gap 4 (Step 7 + general): 62-15-COPY-AUDIT.md exists; all 19 OLD-string instances removed from source; all NEW-string instances confirmed present; Save failed / Open failed copy; (leave unset — set in code) sentinel; Used by N component(s). in AlertDialog"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Verify + New… button is visible and clickable in the Geometry and Power Shape picker rows at the default 320px sidebar width"
    expected: "Both + New… and Edit… buttons are fully visible (not clipped) in the picker row; clicking + New… opens the resource creation popover"
    why_human: "happy-dom does not implement CSS flex layout — className discipline verified in code but visual non-clipping requires a real browser at the actual sidebar width"
  - test: "Right-click a geometry resource that is referenced by at least one component node → select Delete from context menu"
    expected: "AlertDialog appears with title 'Delete geometry <name>?' and description 'Delete geometry <name>? Used by N component(s).' and Cancel button focused by default"
    why_human: "Radix AlertDialog first-focus and visual rendering require a live browser; vitest confirms the logic path but not the actual dialog appearance"
  - test: "Enter a name in Model Options (e.g. 'phase62-smoke'), then File → Save As"
    expected: "OS file picker pre-fills the default filename as 'phase62-smoke.scp' (not 'project.scp')"
    why_human: "computeSaveAsDefaultFilename is unit-tested; the Tauri native OS dialog cannot be exercised in vitest — requires a full Tauri dev build"
  - test: "Walk through Steps 4, 7, 11, 15 of the original 18-step human-verify protocol focusing on the four previously-failed items"
    expected: "All four previously-failed steps now pass; no new regressions in steps 1-3, 6, 8-10, 12-14, 16-18"
    why_human: "Full end-to-end re-run of the human-verify protocol needed to confirm no behavioral regression from the gap-closure changes across all 18 steps"
---

# Phase 62: Resources panel architecture — Re-verification Report

**Phase Goal:** Navigator restructure to `Project → Model Options + Resources + Components`. Foreign-key UUID references. `.scp` save format. Reference picker UX. Sources toolbox category.

**Verified:** 2026-05-13T12:10:00Z
**Status:** human_needed — all 4 critical gaps closed in code; human visual re-confirmation required for the 4 previously-failed steps before the phase is marked complete.
**Re-verification:** Yes — after gap closure (Plans 62-12 through 62-15).

---

## Re-verification Summary

| Gap | Plan | Code Evidence | Automated Gate |
|-----|------|---------------|----------------|
| Gap 1: picker overflow (Steps 4/5) | 62-12 | `flex flex-wrap` + `basis-full sm:basis-0` + `shrink-0` ×5 present in `ResourceReferencePicker.tsx` | vitest 14/14 picker tests pass |
| Gap 2: AlertDialog missing (Step 11) | 62-13 | `PARAM_KEY_BY_KIND` with `["geometry","geometry_ref"]` / `["power_shape","power_shape_ref"]` + `paramKeys.some(k => params[k] === resource.uuid)` in `ResourceRow.tsx` | vitest 22/22 ResourcesTreePanel tests pass |
| Gap 3: Save As filename (Step 15) | 62-14 | `computeSaveAsDefaultFilename(get().modelOptions.name)` at `defaultPath` call site in `saveProjectAs`; `FALLBACK_SAVE_AS_FILENAME = "project.scp"` for empty name | vitest 15/15 saveProjectAs tests pass |
| Gap 4: Copy audit (Step 7 + general) | 62-15 | All 5 OLD-string gates return 0 in non-test src; all 8 NEW-string gates return ≥1; `62-15-COPY-AUDIT.md` exists (9.8 KB) | vitest 440/440 full suite pass; 0 regressions |

---

## Automated Gates

| Check | Result | Notes |
|-------|--------|-------|
| `npx vitest run` (full suite) | **440 pass / 13 todo / 0 fail** | Baseline was 406 pass before gap closure; +34 new pinning tests added by plans 62-12..62-15 |
| `npx tsc --noEmit — error TS count` | **8 pre-existing errors** | Unchanged from baseline documented in 62-12-SUMMARY. All 8 are pre-existing: StreamNode.tsx ×2, ToolboxPanel.test.tsx ×1, SidebarRouter.test.tsx ×2, validation.test.ts ×3. Zero new errors introduced by gap-closure plans. |

---

## Gap 1 Code Verification — ResourceReferencePicker row layout

**File:** `gui/src/components/sidebar/ResourceReferencePicker.tsx`

Verified present:
- Line 123: `<div className="flex flex-wrap items-center gap-[8px]">` — outer container has `flex-wrap`
- Line 124: `<div className="flex-1 min-w-0 basis-full sm:basis-0">` — Select wrapper has `min-w-0` + `basis-full sm:basis-0`
- Line 111: `<Button variant="outline" size="sm" className="shrink-0">` — `+ New…` trigger has `shrink-0`
- Line 183: `<span tabIndex={0} className="inline-flex shrink-0">` — disabled-Edit span wrapper has `shrink-0`
- Line 195: `<Button variant="outline" size="sm" className="shrink-0" onClick={handleEdit}>` — enabled-Edit button has `shrink-0`

Grep counts: `flex-wrap` ×2, `shrink-0` ×5, `basis-full` ×2, `min-w-0` ×1 — all match the plan's gate thresholds (≥2, ≥3, ≥1, ≥1 respectively).

**Status: VERIFIED (code) — visual confirmation deferred to human re-run of Step 5**

---

## Gap 2 Code Verification — Delete AlertDialog usage detection

**File:** `gui/src/components/resources/ResourceRow.tsx`

Verified present:
- Lines 58-62: `PARAM_KEY_BY_KIND` constant maps `geometry: ["geometry", "geometry_ref"]`, `powerShape: ["power_shape", "power_shape_ref"]`, `fluid: []`
- Line 101: `return paramKeys.some((k) => params[k] === resource.uuid);` — OR-scan across both live and legacy keys
- Old `refKey`-only useMemo has been removed; the dual-key scan replaces it

Dual-key coverage: `geometry_ref` appears ×2, `power_shape_ref` appears ×3, `PARAM_KEY_BY_KIND` appears ×3. AlertDialog description at line 351: `Delete ${kindLabel(kind)} ${resource.name}? Used by ${usages.length} component(s).` — matches plan 62-15 copy rewrite (no "It is" prefix).

**Status: VERIFIED (code) — live-app AlertDialog appearance deferred to human re-run of Step 11**

---

## Gap 3 Code Verification — Save As default filename from Model Options Name

**File:** `gui/src/store/useStore.ts`

Verified present:
- Line 324: `const FALLBACK_SAVE_AS_FILENAME = \`project.${PROJECT_FILE_EXTENSION}\` as const;`
- Line 362: `export function computeSaveAsDefaultFilename(name: string): string` — exported for unit testing
- Line 1211: `defaultPath: computeSaveAsDefaultFilename(get().modelOptions.name),` — live call inside `saveProjectAs`
- No remaining `defaultPath: \`project.\`` hardcode (`grep -c` returns 0)

Sanitization: trims, strips OS-illegal chars, collapses whitespace, case-insensitive `.scp` suffix check, empty falls back to `FALLBACK_SAVE_AS_FILENAME`. Does NOT lowercase (preserves user-typed case).

**Status: VERIFIED (code) — OS picker pre-fill behavior deferred to human re-run of Step 15 (requires Tauri dev build)**

---

## Gap 4 Code Verification — Professional copy pass (62-15)

**Artifact:** `62-15-COPY-AUDIT.md` — EXISTS (9,791 bytes, committed 2026-05-13)

OLD-string gates (all must be 0 in non-test source):

| Pattern | Count in src/ (excl. tests) |
|---------|---------------------------|
| `fill in code` | 0 |
| `Please pick` | 0 |
| `is planned for a future release` | 0 |
| `It is used by` | 0 |
| `Couldn't save project` OR `Couldn't open this project` | 0 |

NEW-string gates (all must be ≥1 in owning file):

| Pattern | File | Count |
|---------|------|-------|
| `set in code` | `useStore.ts` | 1 |
| `set in code` | `ResourceReferencePicker.tsx` | 2 |
| `Pick a resource first` | `ResourceReferencePicker.tsx` | 2 |
| `Save failed` | `useStore.ts` | 2 |
| `Open failed` | `useStore.ts` | 2 |
| `Multiple fluids not yet supported` | `ResourcesTreePanel.tsx` | 1 |
| `Used by ${usages.length}` | `ResourceRow.tsx` | 1 |
| `Amplitude must be finite` | `PowerShapeResourceEditor.tsx` | 1 |

Sentinel value `SENTINEL_POWER_SHAPE_NAME` at `useStore.ts:58`: `"(leave unset — set in code)"` — NEW value confirmed, OLD `fill in code` gone.

**Status: VERIFIED (code) — engineering-tool voice confirmed across all 19 substitution table rows**

---

## Original 14 Passing Steps — Regression Check

Plans 62-12 through 62-15 modified layout classes, usage-detection logic, save-dialog plumbing, and string literals only. No behavioral changes were made to: tab switching (Step 3), resource creation auto-suggest (Step 6), Resources tree grouping (Step 9), inline rename (Step 10), selection mutual exclusivity (Step 12), Model Options form (Step 13), Esc cascade (Step 14), round-trip open/save (Step 16), code preview (Step 17), stale-format error dialog (Step 18).

Full vitest suite: 440 pass / 0 fail. The 34 net-new tests added by the gap plans cover the specific surfaces changed; the 406 original passing tests are all still passing.

**Regression status: NO REGRESSIONS DETECTED in automated tests**

---

## Human Verification Required

The following four items were machine-verified (code and vitest pass) but require human visual confirmation in the live Tauri app. These correspond directly to the four original failing steps.

### 1. Picker overflow fix (Steps 4 and 5)

**Test:** Open the app at default sidebar width (~320px). Navigate to a component with a Geometry parameter. Observe the reference picker row.
**Expected:** All three controls (`<select>`, `+ New…`, `Edit…`) are fully visible — `+ New…` is not clipped or hidden. The row may wrap to two lines at narrow widths.
**Why human:** CSS flex wrap behavior with `basis-full sm:basis-0` cannot be verified under happy-dom, which does not implement real layout geometry.

### 2. Delete AlertDialog for used resources (Step 11)

**Test:** In the Resources tab, create a geometry `mtr_ch`. Add a Channel component and set its Geometry parameter to `mtr_ch`. Right-click `mtr_ch` → Delete.
**Expected:** AlertDialog appears with title "Delete geometry mtr_ch?" and body "Delete geometry mtr_ch? Used by 1 component(s)." Cancel button is focused by default. Clicking Cancel preserves the resource; clicking "Delete anyway" removes it.
**Why human:** Radix AlertDialog rendering, first-focus behavior, and context menu → dialog transition require a real browser; jsdom/happy-dom does not render Radix portals faithfully.

### 3. Save As pre-fills model name (Step 15)

**Test:** In Model Options, set Name to `phase62-smoke`. Click File → Save As.
**Expected:** The native OS file-save dialog opens with default filename `phase62-smoke.scp` (not `project.scp`).
**Why human:** `computeSaveAsDefaultFilename` and the `defaultPath` wiring are unit-tested; the Tauri native OS dialog cannot be exercised in vitest — requires a full `npm run tauri dev` build.

### 4. Full 18-step human-verify re-run

**Test:** Re-execute the original 18-step verification protocol, focusing on steps 4, 5, 7, 11, 15 (the four previously-failed items and the copy-quality step), while spot-checking all 18 steps for regressions.
**Expected:** All 18 steps pass. The previously-failed steps now pass without reintroducing regressions in any of the 14 originally-passing steps.
**Why human:** End-to-end behavioral confirmation of the full phase goal requires a live app session.

---

## Non-Critical Gaps (Deferred — Parked as Todos)

These items were deferred in the original verification and remain parked. No change.

| Issue | Routed to | Todo file |
|-------|-----------|-----------|
| Codegen Power Shape variable names verbose / not deduped | Phase 66 (Code preview rework) | `.planning/todos/pending/codegen-resource-naming-dedup.md` |
| CAC component has only 1 thermal connection (should be 2) | Phase 63 (BCs tab + value-source) | `.planning/todos/pending/cac-two-thermal-port-connections.md` |
| Panel resize bounds — content escapes viewport | Phase 72 (Design system) | `.planning/todos/pending/panel-resize-overflow-bounds.md` |
| GUI visual design pass (overall polish) | Phase 72 (Design system) | `.planning/todos/pending/gui-visual-design-pass.md` |

---

_Verified: 2026-05-13T12:10:00Z_
_Verifier: Claude (gsd-verifier) — re-verification after gap closure_

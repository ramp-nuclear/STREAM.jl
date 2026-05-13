---
phase: 62-resources-panel-architecture
verified: 2026-05-13T03:30:00Z
status: gaps_found
score: 14/18 human-verify steps passed
source: human-verify checkpoint (62-11) — user-driven 18-step protocol
---

# Phase 62: Resources panel architecture — Verification Report

**Phase Goal:** Navigator restructure to `Project → Model Options + Resources + Components`. Foreign-key UUID references. `.scp` save format. Reference picker UX. Sources toolbox category.

**Verified:** 2026-05-13T03:30:00Z
**Status:** gaps_found
**Score:** 14/18 human-verify steps passed, 4 gaps requiring fix plans

## Automated Verification

| Check | Result |
|-------|--------|
| GUI vitest suite | ✓ 406 pass / 13 todo (0 fail) |
| TypeScript `tsc --noEmit` | ✓ 6 errors (baseline, all pre-existing — 0 new) |
| INV-CG-05 smoke gate (cold-start Julia) | ✓ `DONE: simple_loop ran end-to-end` |
| CONS-01..04 Julia conservation invariants | ✓ 28/28 assertions pass |
| `.streamgui` hard cutover (no migration shim) | ✓ 0 references remain in `gui/src/` |

## Human-Verify Protocol (18 steps)

| # | Step | Result |
|---|------|--------|
| 1 | `npm run dev` opens Composer | ✓ |
| 2 | Tab strip + SOURCES header visible | ✓ |
| 3 | Ctrl+1/2/3 switches tabs; Ctrl+Tab does not | ✓ |
| 4 | Empty-state copy on Geometry field shows correctly | ⚠ Partial — button overflows panel bounds |
| 5 | `+ New…` popover anchored, non-dismiss-on-outside, Esc closes with focus return | ✗ FAILED — `+ New…` button clipped out of view |
| 6 | Create flow auto-suggests `geometry_1`, auto-selects on Create | ✓ |
| 7 | Sentinel `(leave unset — fill in code)` shown with separator; disabled Edit tooltip | ⚠ Partial — tooltip copy "AI-ish", not professional |
| 8 | Power Shape create flow works | ✓ |
| 9 | Resources tab tree groups correct; sentinel filtered | ✓ |
| 10 | Inline rename via double-click works | ✓ |
| 11 | Right-click → Delete on USED geometry shows confirmation AlertDialog | ✗ FAILED — no dialog appeared |
| 12 | Selection mutual exclusivity surfaced in right panel | ✓ |
| 13 | Project tab Model Options form works | ✓ |
| 14 | Esc cascade clears selection | ✓ |
| 15 | Save As default filename = Model Options Name field | ✗ FAILED — defaulted to `project.scp` |
| 16 | New Project → Open → fixture round-trips canvas + Resources + Model Options + active tab | ✓ |
| 17 | Code Preview shows Resources block + per-kind Power Shape forms | ✓ (codegen verbosity noted, deferred to Phase 66) |
| 18 | Stale `.streamgui` open → clean error dialog | ✓ |

## Gaps Summary

### Critical Gaps (Block Phase Completion)

1. **`+ New…` button overflow in reference picker rows** (Steps 4 / 5)
   - Missing: bounded layout in `ResourceReferencePicker` row — the `<select>` dropdown + `+ New…` + `Edit…` buttons exceed the default right-panel width and the rightmost button is clipped.
   - Impact: user cannot create a resource from the picker at all — the primary creation entry point is invisible.
   - Fix: layout the picker row to fit within the panel's content width. Options: (a) wrap the buttons below the dropdown at narrow widths; (b) collapse `+ New…` / `Edit…` to icon-only buttons with tooltips; (c) bump the default right-panel width AND clamp the picker row to a max width with overflow wrapping. Pick the simplest of these that respects the broader-scope panel-resize todo (Phase 72) without preempting it.
   - Plan files most affected: `gui/src/components/sidebar/ResourceReferencePicker.tsx`, possibly `gui/src/components/sidebar/SidebarPanel.tsx` (default width).
   - Root plan: 62-08 (ResourceReferencePicker row layout).

2. **Delete confirmation AlertDialog missing for used resources** (Step 11)
   - Missing: the Plan 62-06 D-03 spec requires "Delete geometry mtr_ch? It is used by N component(s)." AlertDialog before destructive delete. The right-click Delete action currently deletes silently (or does nothing visible) without any confirmation surface.
   - Impact: silent destructive operation when a resource is in use. The user explicitly hit Delete on `mtr_ch` referenced by 1 component and no dialog appeared.
   - Fix: implement the AlertDialog flow in `ResourcesTreePanel.tsx` (or wherever the Delete handler lives). Wire usage count via `useResourceUsages(uuid)` or equivalent store selector. Default focused button = Cancel.
   - Plan files most affected: `gui/src/components/resources/ResourcesTreePanel.tsx`, `gui/src/components/resources/ResourceRow.tsx`.
   - Root plan: 62-06 (Resources tree context menu).

3. **Save As default filename not derived from Model Options Name** (Step 15)
   - Missing: when the user clicks File → Save As, the OS dialog's default filename should be `<modelOptions.name>.scp` (e.g. `phase62-smoke.scp`), not the literal `project.scp`. The Model Options Name field exists (62-07) but isn't piped into the save flow.
   - Impact: user has to retype the project name every time they Save As — friction; explicit acceptance criterion.
   - Fix: in the Save As handler (likely in `gui/src/store/useStore.ts` or `gui/src/lib/projectIO.ts`), pass `state.modelOptions.name + ".scp"` as the `defaultPath` argument to the Tauri save dialog. Handle the case where the user has not set a name (fall back to `project.scp`).
   - Plan files most affected: `gui/src/store/useStore.ts`, `gui/src/lib/projectIO.ts`.
   - Root plan: 62-04 (projectIO) bridged with 62-07 (Model Options).

4. **Professional copy pass — user-facing strings read as "AI-ish"** (Step 7 + general)
   - Missing: tone audit. Strings like the disabled `Edit…` tooltip, sentinel labels, empty-state copy, error dialogs use verbose / casual phrasing that does not match a scientific engineering tool's voice.
   - Impact: ergonomic — the app feels unfinished and tonally inconsistent. User feedback verbatim: "Need to rethink wording in this phase I think to stuff that is more professional to have in a software like this."
   - Fix: audit every user-facing string introduced in Phase 62 (Plans 62-05 through 62-09 plus toolbar / dialog copy). Rewrite to terse, declarative, engineering-tool voice. No em-dashes in body text where a period works. No "AI-ish" reassurances. Concrete substitutions: tooltips should be 1 line ≤ 60 chars, error dialogs should state the fact then the action.
   - Plan files most affected: all 62-* TSX components, especially `ResourceReferencePicker.tsx`, `ResourceCreationPopover.tsx`, `ResourcesTreePanel.tsx`, `SidebarPanel.tsx`, `ModelOptionsPanel.tsx`, `projectIO.ts` (error messages).
   - Root plan: cross-cutting — touch all Phase 62 surfaces.

### Non-Critical Gaps (Deferred — Parked as Todos)

| Issue | Routed to | Todo file |
|-------|-----------|-----------|
| Codegen Power Shape variable names verbose / not deduped | Phase 66 (Code preview rework) | `.planning/todos/pending/codegen-resource-naming-dedup.md` |
| CAC component has only 1 thermal connection (should be 2) | Phase 63 (BCs tab + value-source) | `.planning/todos/pending/cac-two-thermal-port-connections.md` |
| Panel resize bounds — content escapes viewport | Phase 72 (Design system) | `.planning/todos/pending/panel-resize-overflow-bounds.md` |
| GUI visual design pass (overall polish, not Phase 62 in-scope) | Phase 72 (Design system) | `.planning/todos/pending/gui-visual-design-pass.md` |

## Recommended Fix Plans

The `/gsd:plan-phase 62 --gaps` cycle should generate one fix plan per Critical Gap:

### 62-12-PLAN.md: ResourceReferencePicker row layout fix
**Objective:** Eliminate `+ New…` / `Edit…` button overflow in the reference picker row at default panel widths. Layout must respect `min-w-0` and either wrap-below or icon-collapse at narrow widths.
**Tasks:** ~2 (layout fix + vitest assertion that all three controls are visible at 280px panel width)
**Root plan:** 62-08

### 62-13-PLAN.md: Resources tree Delete confirmation AlertDialog
**Objective:** Wire the missing AlertDialog for the per-row Delete context-menu action per D-03. Show usage count; Cancel-focused-by-default; destructive button styling.
**Tasks:** ~2 (AlertDialog wiring + vitest assertions including the "used by N components" copy)
**Root plan:** 62-06

### 62-14-PLAN.md: Save As default filename from Model Options Name
**Objective:** Pipe `modelOptions.name` into the Tauri save dialog's `defaultPath` so Save As pre-fills `<name>.scp`.
**Tasks:** ~2 (handler edit + vitest mock of the save path argument)
**Root plan:** 62-04 / 62-07 bridge

### 62-15-PLAN.md: Professional copy pass across Phase 62 surfaces
**Objective:** Audit and rewrite every user-facing string introduced in Phase 62 to engineering-tool voice. Terse, declarative, no AI-isms.
**Tasks:** ~3 (audit list with current vs proposed strings; apply rewrites; snapshot tests pinning the final copy)
**Root plan:** cross-cutting (touches all 62-* TSX files)

After these four gap plans land:
- Re-run `/gsd:execute-phase 62 --gaps-only`
- Re-execute the 18-step human-verify protocol (focusing on steps 4, 5, 7, 11, 15)
- On approval, run `/gsd:complete-phase 62` to advance to Phase 63.

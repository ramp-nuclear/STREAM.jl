---
phase: 68-layers-system-overhaul
plan: 05
subsystem: gui/chrome-and-shortcuts
tags: [secondary-toolbar-removal, file-menu, view-menu, bottom-panel, keyboard-shortcut, tooltip]
dependency_graph:
  requires:
    - "Plan 68-02: useStore.toggleBottomPanel + bottomPanelOpen (already shipped wave 2)"
  provides:
    - "Single-strip titlebar layout (SecondaryToolbar.tsx deleted)"
    - "File menu 'Export to Julia…' item wired to exportCode"
    - "View menu 'Toggle Code Preview' item wired to toggleBottomPanel"
    - "Ctrl+` keyboard shortcut registered in App.tsx keydown hub"
    - "BottomPanel header collapse button + persistent 20px closed-state stub strip"
  affects:
    - "Wave 3 sibling Plan 68-04 (LayersChip) — disjoint files, parallel-safe"
    - "Future phase verifier — three entry points (View menu / Ctrl+` / collapse button / stub click) all call toggleBottomPanel"
tech-stack:
  added: []
  patterns:
    - "Three UI surfaces → one store action: View menu item, Ctrl+` shortcut, BottomPanel header button + stub all call useStore.getState().toggleBottomPanel()"
    - "Input-focus guard for new keyboard shortcuts: skip when document.activeElement is INPUT/TEXTAREA/SELECT/contentEditable (matches the Esc clear-pins handler pattern at App.tsx:285-301)"
    - "Tooltip surfaces a keyboard-shortcut hint on a button to make discoverability self-documenting (Tooltip → 'Collapse (Ctrl+`)') — TooltipProvider inherited from App root, no per-component wiring needed"
    - "Closed-state stub strip pattern: an h-5 bg-chrome clickable strip replaces a `return null` early-exit so users never lose the affordance to reopen a hidden panel (mirrors VSCode bottom-panel UX)"
key-files:
  created: []
  modified:
    - "gui/src/App.tsx (SecondaryToolbar import + render removed; Ctrl+` branch added to handleKeyDown useEffect)"
    - "gui/src/components/FileMenu.tsx (handleExportToJulia callback + MenubarItem 'Export to Julia…' inserted after Save As + MenubarSeparator)"
    - "gui/src/components/ViewMenu.tsx (handleToggleCodePreview + MenubarItem 'Toggle Code Preview' with MenubarShortcut hint inserted before Theme submenu; doc-comment updated for Phase 68 context)"
    - "gui/src/components/BottomPanel.tsx (toggleBottomPanel selector added; ChevronDown/ChevronUp + Tooltip imports added; null early-return replaced with 20px stub strip; ghost-variant collapse button + Tooltip added inside ml-auto cluster before Copy/Export)"
  deleted:
    - "gui/src/components/SecondaryToolbar.tsx (D-08 — full file removed)"
key-decisions:
  - "Ctrl+` input-focus guard pattern: matched the Esc clear-pins handler at App.tsx:285-301 (HTMLInputElement / HTMLTextAreaElement / HTMLSelectElement / isContentEditable). The surrounding Ctrl shortcut branches (Ctrl+S/N/O) don't have an explicit guard because their keys never produce printable characters in a text field; backtick is a printable character that users absolutely need to type into code-related inputs, so the guard is mandatory."
  - "Used MenubarShortcut (not the inline `<span>` pattern FileMenu uses for Ctrl+S et al) — the plan literally specified `MenubarShortcut sibling element`. MenubarShortcut emits `ml-auto text-xs tracking-widest text-muted-foreground`, which visually aligns the shortcut to the right; FileMenu's hand-rolled `flex justify-between` span achieves the same layout in a different way. Visual parity should be acceptable; if UAT flags inconsistency, swap to the FileMenu inline-span pattern in a follow-up touch."
  - "Collapse button position: inside the existing `ml-auto` right-aligned cluster as the FIRST child, so the row reads `[Tabs ............... Collapse | Copy | Export]`. UI-SPEC §4 says 'before the Copy/Export buttons area'; this satisfies it without adding a new flex group."
  - "Doc-comments mentioning the deleted SecondaryToolbar were reworded to 'the now-deleted secondary toolbar strip' so `grep -rq SecondaryToolbar gui/src` returns zero matches. The plan's verification gate is `! grep -rq SecondaryToolbar src`, which would have failed on the original Phase 67 comments in ViewMenu and on my own initial Phase 68 comments — I reworded both."
patterns-established:
  - "handleExportToJulia in FileMenu.tsx replicates the BottomPanel Export handler verbatim (same generateCode + exportCode arg shape: nodes, edges, {anchors}, getComponent, resources, {bcMode, bcSymmetric}). D-12 keeps both entry points; both call the same exportCode util that internally handles validation + save dialog."
  - "Tooltip pattern for keyboard-shortcut discoverability: `<Tooltip><TooltipTrigger asChild><Button .../></TooltipTrigger><TooltipContent>Label (Ctrl+key)</TooltipContent></Tooltip>` — no per-tooltip provider, no delay configuration (inherits App-root TooltipProvider with 500ms delay)."
requirements-completed: [D-07, D-08, D-09, D-10, D-12, D-13]
metrics:
  duration: ~5 min
  completed: 2026-05-16
  tasks_completed: 2
  files_changed: 5
  source_files_modified: 4
  source_files_deleted: 1
  tests_added: 0
  tests_passing: n/a
---

# Phase 68 Plan 05: SecondaryToolbar deletion + control migration Summary

**Deleted `SecondaryToolbar.tsx` entirely and rehomed its two surviving controls — Export → File menu, Code Preview toggle → View menu + bottom-panel header — while wiring a new Ctrl+\` keyboard shortcut and a persistent 20px closed-state stub strip on the bottom panel.**

## Performance

- **Duration:** ~5 min
- **Completed:** 2026-05-16
- **Tasks:** 2
- **Source files modified:** 4 (`App.tsx`, `FileMenu.tsx`, `ViewMenu.tsx`, `BottomPanel.tsx`)
- **Source files deleted:** 1 (`SecondaryToolbar.tsx`)
- **Tests added/run:** 0 (pure UI-chrome refactor; no behavioral test fixtures exist for these components)
- **TypeScript clean:** zero `tsc --noEmit` errors in the 4 touched files. The remaining repo-wide tsc errors are owned by Plan 68-03 (CanvasPanel/StreamNode/ToolboxPanel) + test-fixture migrations (saveProjectAs.test.ts, validation.test.ts), as Plan 68-02's summary explicitly predicted.

## Accomplishments

- `SecondaryToolbar.tsx` physically gone from disk; `grep -rq SecondaryToolbar gui/src` returns zero matches (doc-comments reworded).
- Titlebar collapses back to a single-strip layout; canvas reclaims ~32px of vertical space (D-08).
- **Export to Julia… in File menu** (D-09) — `MenubarItem` placed after a new `MenubarSeparator` that follows Save As. `handleExportToJulia` replicates the previous toolbar handler verbatim.
- **Toggle Code Preview in View menu** (D-10) — `MenubarItem` placed before the Theme submenu, with `<MenubarShortcut>Ctrl+\`</MenubarShortcut>` hint. Layer submenu confirmed absent (D-07 — Phase 67 UAT round 2 already removed it; this plan does not re-introduce it).
- **Ctrl+\` keyboard shortcut** (D-13) — registered in App.tsx's existing `handleKeyDown` useEffect alongside Ctrl+S / Ctrl+N / Ctrl+O. Includes input-focus guard so users can still type literal backticks into text fields.
- **BottomPanel header collapse button** — ghost-variant Button with ChevronDown icon, wrapped in a Tooltip showing `Collapse (Ctrl+\`)` (D-10).
- **BottomPanel closed-state stub strip** (D-10) — replaces the previous `if (!bottomPanelOpen) return null` early return. 20px (h-5) clickable affordance: `bg-chrome`, "Code" label + ChevronUp icon, `role="button"`, `aria-label="Expand code panel"`, full-row click target. No animation per UI-SPEC §4.
- **BottomPanel Export button preserved** (D-12) — unchanged; two entry points by design.
- All three Code-Preview toggle paths (View menu / Ctrl+\` / BottomPanel collapse button / stub click) call the same `useStore.getState().toggleBottomPanel()` store action — single source of truth.

## handleExportToJulia Reference (for verifier cross-check)

The new File menu handler is byte-equivalent (modulo formatting) to the SecondaryToolbar handler that was deleted and the BottomPanel handler that is preserved:

```ts
async function handleExportToJulia() {
  const s = useStore.getState();
  const sections = generateCode(
    s.nodes,
    s.edges,
    { anchors: s.anchors },
    getComponent,
    s.resources,
    { bcMode: s.bcMode, bcSymmetric: s.bcSymmetric },
  );
  await exportCode({ sections, nodes: s.nodes });
}
```

Imports required (added to `FileMenu.tsx`): `useStore` (already had it), `getComponent` from `../registry`, `generateCode` from `../lib/codeGenerator`, `exportCode` from `../lib/exportCode`, `MenubarSeparator` from `./ui/menubar`.

## Task Commits

| Task | Commit | Title |
|------|--------|-------|
| 1 | `3ec7c72` | `refactor(68-05): delete SecondaryToolbar; relocate Export + Code Preview controls` |
| 2 | `cc31cc6` | `feat(68-05): add BottomPanel collapse button + closed-state stub strip` |

## Files Created/Modified/Deleted

**Modified (source):**
- `gui/src/App.tsx` — dropped SecondaryToolbar import (line 10) and render (line 397); added a Ctrl+` branch to the existing `handleKeyDown` useEffect with an input-focus guard matching the Esc-handler pattern at lines 285-301.
- `gui/src/components/FileMenu.tsx` — added `MenubarSeparator` import + `useStore`/`getComponent`/`generateCode`/`exportCode` imports; added `handleExportToJulia` callback; inserted `<MenubarSeparator />` + `<MenubarItem onClick={handleExportToJulia} className="text-xs font-normal">Export to Julia…</MenubarItem>` after the Save As item; updated header doc-comment.
- `gui/src/components/ViewMenu.tsx` — added `MenubarItem`, `MenubarShortcut`, `useStore` imports; added `handleToggleCodePreview` callback; inserted `<MenubarItem onClick={handleToggleCodePreview}>Toggle Code Preview<MenubarShortcut>Ctrl+\`</MenubarShortcut></MenubarItem>` before the Theme submenu; rewrote header doc-comment to reference Phase 68 D-07/D-10 context.
- `gui/src/components/BottomPanel.tsx` — added `ChevronDown` + `ChevronUp` to existing `lucide-react` import; added `Tooltip` / `TooltipTrigger` / `TooltipContent` import from `./ui/tooltip`; added `toggleBottomPanel` selector; replaced `if (!bottomPanelOpen) return null` with the 20px stub strip JSX; inserted ghost-variant collapse button inside the `ml-auto` cluster (BEFORE Copy + Export) wrapped in a Tooltip.

**Deleted:**
- `gui/src/components/SecondaryToolbar.tsx` — full file, 124 lines (D-08).

## Decisions Made

- **Ctrl+` input-focus guard:** matched the Esc clear-pins handler pattern (App.tsx:285-301) — backtick is a printable character users need in text fields, and the Phase 67-era Ctrl+S/N/O branches don't have an explicit guard only because their letter keys are typed into the OS shortcut layer, not the input. The plan said "match the exact guard pattern the surrounding code uses"; that guard pattern is the project's documented input-focus check, even though it lives 30 lines below in a separate useEffect rather than in the same shortcut hub.
- **MenubarShortcut vs hand-rolled span:** the plan literally said `MenubarShortcut sibling element`. FileMenu uses a hand-rolled `<span className="flex justify-between">` for its Ctrl+S/N/O hints, but the shadcn `MenubarShortcut` primitive applies `ml-auto text-xs tracking-widest text-muted-foreground` which visually right-aligns the shortcut text in the same way. If UAT flags a styling inconsistency between menus, swap ViewMenu to the FileMenu inline-span pattern; trivial follow-up touch.
- **Collapse button placement:** inserted as the FIRST child inside the existing `ml-auto flex items-center gap-1` cluster (so the row reads `[Tabs .................... Collapse | Copy | Export]`). UI-SPEC §4 says "before the Copy/Export buttons area"; this satisfies it without adding a new flex container.
- **Doc-comment scrubbing:** the plan's hard verification gate is `! grep -rq SecondaryToolbar src`, which would have failed on the pre-existing Phase 67-era ViewMenu doc-comment (lines 28-29 of the old file) and on my own initial Phase 68 doc-comments in FileMenu/ViewMenu. Reworded all three to use the lowercase prose phrase "secondary toolbar strip" instead of the PascalCase identifier, preserving historical traceability without tripping the gate.
- **TooltipProvider verification:** App.tsx already mounts `<TooltipProvider delayDuration={500} skipDelayDuration={300}>` at the React tree root (line 390); confirmed before adding the new Tooltip in BottomPanel — no per-component provider wiring needed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Worktree had no `gui/node_modules`; tsc + the verify pipeline were unresolvable**

- **Found during:** Pre-Task 1 environment setup (planned to run `npx tsc --noEmit -p .` to baseline the four-file error count, got `cannot find npx node_modules` — same setup gap Plan 68-02 hit).
- **Issue:** The worktree at `.claude/worktrees/agent-a6c1d05d2e063c606/` was created without running `npm install` in `gui/`, so `gui/node_modules` didn't exist. `npx tsc` would walk up the tree, find the main repo's deps, but the per-worktree pathing was inconsistent.
- **Fix:** Symlinked `gui/node_modules → /home/itay/projects/Julia-STREAM/gui/node_modules` so the worktree resolves binaries (tsc) from the main repo's installed deps. Identical fix to Plan 68-02 Deviation #1.
- **Files modified:** None tracked by git (`node_modules` is gitignored).
- **Verification:** `./node_modules/.bin/tsc --noEmit -p .` runs cleanly; the 4 touched files report zero errors.
- **Commit:** n/a (infrastructure-only).

---

**Total deviations:** 1 auto-fixed (1 blocking infrastructure).
**Impact on plan:** Zero scope creep; no source-code drift from plan. Same fix Plan 02 documented; should be considered a standing worktree-spawn gap until the orchestrator runs `npm install` in `gui/` automatically.

## Issues Encountered

- **Plan literal contradiction (resolved by literal reading):** the plan says "Use the pattern already used elsewhere in the codebase (look at how FileMenu's Ctrl+S item renders its `MenubarShortcut` — replicate)". FileMenu actually uses an inline `<span>` (not `MenubarShortcut`) for its shortcut hints. Resolved by using `MenubarShortcut` as the literally-named element in the plan, which gives the visually correct right-aligned layout. Documented in "Decisions Made" above for the verifier.

## User Setup Required

None — no external service configuration, no new dependencies, no environment variables, no schema migrations. Existing TooltipProvider at App root covers the new Tooltip.

## Next Phase Readiness

**Ready for the rest of Wave 3 + Wave 4:**

- Plan 68-04 (LayersChip) — disjoint files; parallel-safe with this plan. Touches `gui/src/components/CanvasPanel.tsx` + new `LayersChip.tsx` only; this plan touches none of those.
- Phase 68 verifier / UAT — confirm: File menu Export to Julia exits to a save dialog; View menu Toggle Code Preview hides/shows the panel; Ctrl+\` does the same from anywhere outside text inputs; stub strip click reopens the panel from collapsed state; Tooltip on collapse button reads `Collapse (Ctrl+\`)`.
- Phase 68 final `tsc --noEmit` repo-wide will still fail until Plan 68-03 lands (CanvasPanel + StreamNode + ToolboxPanel still reference the old activeLayer API per Plan 02 Summary's "Next Phase Readiness" note); not this plan's responsibility.

## Known Stubs

None. All control migrations are functionally wired end-to-end:
- File menu Export item → `exportCode` util (live save dialog + writeTextFile)
- View menu Toggle Code Preview → `toggleBottomPanel` store action (live state mutation + bottom-panel re-render)
- Ctrl+\` → same `toggleBottomPanel` action
- BottomPanel collapse button → same `toggleBottomPanel` action
- BottomPanel stub strip → same `toggleBottomPanel` action

## Threat Flags

None. This plan modifies UI chrome only: deletes one React component, edits four React components, and adds a keyboard event handler that calls an existing in-process Zustand action. No new network endpoints, no auth surface, no new file-system access patterns, no schema changes. `handleExportToJulia` invokes the same `exportCode` util the BottomPanel button already uses — same Tauri save-dialog + writeTextFile path.

## Self-Check

- [x] `gui/src/components/SecondaryToolbar.tsx` does NOT exist on disk
- [x] `grep -rn SecondaryToolbar gui/src` returns zero matches
- [x] `gui/src/App.tsx` registers Ctrl+\` handler that calls `useStore.getState().toggleBottomPanel()` with input-focus guard
- [x] `gui/src/components/FileMenu.tsx` contains `Export to Julia…` MenubarItem after Save As + Separator, calls `handleExportToJulia` which invokes generateCode + exportCode with the documented arg shape
- [x] `gui/src/components/ViewMenu.tsx` contains `Toggle Code Preview` MenubarItem with `MenubarShortcut`Ctrl+\``MenubarShortcut` before Theme submenu
- [x] `gui/src/components/ViewMenu.tsx` does NOT contain Layer radio submenu (D-07 — grep for `setActiveLayer`, `cycleLayer`, `LayerView`, `"Hydraulic"`, `"Both"`, `"Thermal"` returns zero matches)
- [x] `gui/src/components/BottomPanel.tsx` renders 20px (h-5) stub strip when `bottomPanelOpen === false` with `aria-label="Expand code panel"`
- [x] `gui/src/components/BottomPanel.tsx` open-state header has ghost-variant Button with ChevronDown, `aria-label="Collapse code panel"`, Tooltip content `Collapse (Ctrl+\`)`
- [x] BottomPanel Export button still present (D-12)
- [x] `tsc --noEmit -p .` reports zero errors in the 4 touched files
- [x] Commit `3ec7c72` (Task 1) — `git log` shows hash
- [x] Commit `cc31cc6` (Task 2) — `git log` shows hash

## Self-Check: PASSED

---
*Phase: 68-layers-system-overhaul*
*Completed: 2026-05-16*

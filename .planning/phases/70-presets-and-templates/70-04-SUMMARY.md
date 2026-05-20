---
phase: 70-presets-and-templates
plan: "04"
subsystem: gui
tags: [react, zustand, tauri-fs, context-menu, inline-rename, drag-and-drop, watcher]
dependency_graph:
  requires:
    - 70-01 (Tauri capabilities: fs:allow-watch, opener plugin)
    - 70-02 (presetIO.ts — PresetIndexEntry, isValidPresetName, PRESET_NAME_RE)
    - 70-03 (useStore presets slice — projectPresets, libraryPresets, refreshPresetsDir, renamePreset, deletePreset, setProjectPresets)
  provides:
    - gui/src/components/PresetRow.tsx (entry row: drag, inline rename, context menu, delete modal)
    - gui/src/components/PresetsPanel.tsx (4th-tab body: two collapsible sections, FS watcher, empty states, skeleton)
  affects:
    - gui/src/App.tsx (plan 70-06 slots <PresetsPanel /> into <TabsContent value="Presets">)
    - gui/src/components/CanvasPanel.tsx (plan 70-06 adds application/stream-preset drop handler)
tech_stack:
  added: []
  patterns:
    - "Watcher useEffect keyed on currentProjectDir for D-06 project-switch rebinding"
    - "cancelled flag inside async setup to prevent post-unmount state mutation (Pitfall 4 / T-70-14)"
    - "Dynamic import of @tauri-apps/plugin-fs and @tauri-apps/api/path inside useEffect (mirrors autoRecover.ts pattern)"
    - "ResourceRow inline-rename state machine cloned and adapted for preset rename"
    - "ContextMenu wrapping <li> with asChild trigger (ResourceRow pattern)"
    - "AlertDialog delete confirmation with UI-SPEC verbatim copy"
key_files:
  created:
    - gui/src/components/PresetRow.tsx
    - gui/src/components/PresetsPanel.tsx
decisions:
  - "Moved onRequestReveal to a callback prop on PresetRow — keeps row pure; PresetsPanel injects the revealItemInDir call"
  - "reveal() uses dynamic import of @tauri-apps/plugin-opener to avoid top-level import (consistent with watcher lazy-import pattern)"
  - "refreshPresetsDir not in useEffect dep array — it's a stable store function reference (Zustand pattern)"
metrics:
  duration: "~20 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 0
---

# Phase 70 Plan 04: Presets Panel UI Summary

**One-liner:** PresetRow component (drag, inline rename, Radix ContextMenu, AlertDialog delete confirm) and PresetsPanel (two collapsible sections, debounced FS watcher useEffect, three empty states, skeleton) — the complete Presets-tab body, ready to slot into App.tsx in plan 70-06.

## What Was Built

### Task 1: gui/src/components/PresetRow.tsx (commit 8ca3314)

Entry row component for a single preset in the Presets tab.

**Props:** `{ entry: PresetIndexEntry; onRequestReveal: () => void }`

**Features:**
- `<li>` with `draggable={!renaming}` and `onDragStart` setting `application/stream-preset` MIME type with `{ filePath, store }` JSON payload (D-16).
- `GripVertical` drag handle icon (always visible, left column).
- **Inline rename** state machine (F2 to enter, Enter/blur to commit, Esc to cancel):
  - Uses project-wide `Input` chokepoint wrapper (auto-selects on focus per feedback memory).
  - Live validation on every keystroke: empty / invalid charset / collision produces error string set in `title` attribute and `border-destructive` class.
  - `commitRename` calls `useStore.getState().renamePreset(filePath, newName)`; on error, stays in rename mode with error message.
- **Name tooltip:** Radix `Tooltip` wrapping name span, `side="right"`, shows `entry.description` when non-empty; omitted otherwise.
- **ContextMenu** (right-click): Rename / Delete (destructive) / separator / Reveal in Finder/Explorer. Order matches UI-SPEC Surface 3.
- **AlertDialog** delete confirmation: title "Delete preset?", description per UI-SPEC copywriting contract, "Keep Preset" / "Delete Preset" buttons.
- D-19.1: no "Edit description" action.
- F2 keyboard shortcut triggers `startRename`.

### Task 2: gui/src/components/PresetsPanel.tsx (commit c88dc0a)

Tab body component for the Presets tab.

**No props** (reads from store via `useStore` selectors).

**Sections:**
- "Project" and "Library" collapsible sections with `ChevronDown` toggle buttons (rotated -90° when collapsed, `transition-transform duration-150`).
- Section headers: `text-xs font-semibold uppercase tracking-wide text-muted-foreground`.

**Watcher lifecycle (`useEffect` keyed on `currentProjectDir`):**
- Derives `currentProjectDir` from `currentFilePath` by stripping trailing path segment.
- Dynamically imports `@tauri-apps/api/path` and `@tauri-apps/plugin-fs` inside the async setup (consistent with `autoRecover.ts` pattern).
- `mkdir(..., { recursive: true })` before watching each directory (Pitfall 8).
- `refreshPresetsDir("library", libDir)` then `watch(libDir, ..., { delayMs: 200 })` for Library.
- `refreshPresetsDir("project", projDir)` then `watch(projDir, ..., { delayMs: 200 })` for Project (only when project is open).
- When no project is open: `useStore.getState().setProjectPresets([])`.
- `cancelled` flag throughout async setup prevents state mutation after unmount/dep-change (T-70-14).
- Cleanup: `unwatchers.forEach(fn => fn())`.

**Render states (per section):**
- `loading === true` → 2 skeleton rows (`h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]`).
- No project open (Project section only) → "Open a project to use the Project store."
- Empty presets → two-line empty state per UI-SPEC copywriting contract.
- Non-empty → `<ul role="list" className="space-y-px">` of `<PresetRow>` entries.

**Reveal handler:** `reveal(filePath)` dynamically imports `revealItemInDir` from `@tauri-apps/plugin-opener` and calls it; errors go to `console.error` (not surfaced to user — reveal failures are non-critical).

## Deviations from Plan

None — plan executed exactly as written.

## Threat Model Compliance

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-70-14 | MITIGATED | `cancelled` flag + cleanup `unwatchers.forEach(fn => fn())` prevents stale watcher updates after project switch. |
| T-70-15 | MITIGATED | `revealItemInDir` scoped to provided file path; ACL from 70-01 restricts to preset dirs. |
| T-70-16 | INHERITED | `refreshPresetsDir` in store (70-03) validates via `deserializePreset`; bad files skipped — no special handling needed in panel. |
| T-70-17 | MITIGATED | `delayMs: 200` debounce on both watchers coalesces rapid write bursts. |

## Known Stubs

None — both components consume live store data (`projectPresets`, `libraryPresets`) populated by the watcher-driven `refreshPresetsDir` action.

## Threat Flags

None — no new network endpoints, auth paths, or file-access patterns beyond the plan's threat model.

## Self-Check: PASSED

- [x] `gui/src/components/PresetRow.tsx` exists and default-exports `PresetRow`
- [x] `gui/src/components/PresetsPanel.tsx` exists and default-exports `PresetsPanel`
- [x] Commit 8ca3314 exists (Task 1: PresetRow)
- [x] Commit c88dc0a exists (Task 2: PresetsPanel)
- [x] `grep -c '<ContextMenuItem' src/components/PresetRow.tsx` = 3
- [x] `grep -c '"Edit description"' src/components/PresetRow.tsx` = 0
- [x] `grep -c 'application/stream-preset' src/components/PresetRow.tsx` = 1
- [x] `grep -c "delayMs: 200" src/components/PresetsPanel.tsx` = 2 (one per watcher)
- [x] `grep -c "mkdir.*recursive: true" src/components/PresetsPanel.tsx` = 2 (lib + proj)
- [x] `grep -c "\[currentProjectDir\]" src/components/PresetsPanel.tsx` = 1 (dep array)
- [x] Three empty states present with UI-SPEC verbatim copy
- [x] Skeleton rows render while `loading === true`
- [x] No new tsc errors in PresetRow.tsx or PresetsPanel.tsx (pre-existing errors in StreamNode.tsx/useStore.ts unchanged)
- [x] Uses project-wide `Input` wrapper (not raw `<input>`) in PresetRow
- [x] No modifications to SavePresetModal.tsx, StreamNode.tsx, or projectIO.ts (sibling plan 70-05 territory)

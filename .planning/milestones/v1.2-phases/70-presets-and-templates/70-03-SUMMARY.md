---
phase: 70-presets-and-templates
plan: "03"
subsystem: gui
tags: [zustand, preset-store, tauri-fs, vitest, uuid, smart-name]
dependency_graph:
  requires:
    - 70-02 (presetIO.ts — PresetIndexEntry, deserializePreset, serializePreset, autoExtendSelection, normalizeLayout, isValidPresetName)
  provides:
    - gui/src/store/useStore.ts presets slice (projectPresets, libraryPresets, 7 actions)
    - gui/src/store/__tests__/presetActions.test.ts (17 vitest tests)
  affects:
    - gui/src/store/useStore.ts (ActiveLeftTab extended; state + actions added)
    - gui/src/components/PresetsPanel.tsx (plan 70-04 imports refreshPresetsDir)
    - gui/src/components/SavePresetModal.tsx (plan 70-05 imports saveSelectionAsPreset)
    - gui/src/components/FileMenu.tsx (plan 70-06 imports loadPresetFromPath)
tech_stack:
  added: []
  patterns:
    - "Dynamic import of @tauri-apps/plugin-fs inside async store actions (mirrors saveProject pattern)"
    - "pasteFromClipboard oldToNew UUID remap pattern cloned for loadPresetAtPosition"
    - "Per-file try/catch in refreshPresetsDir for Tauri mid-write resilience (Pitfall 3)"
    - "PARAM_KEY_BY_KIND inlined in store (Pitfall 5 — avoids component-from-store import)"
key_files:
  created:
    - gui/src/store/__tests__/presetActions.test.ts
  modified:
    - gui/src/store/useStore.ts
decisions:
  - "ActiveLeftTab extended to 4-variant union in useStore.ts only; projectIO.ts imports the type and inherits automatically (Pitfall 6)"
  - "collectedGeometries/collectedPowerShapes typed as GeometryResource[]/PowerShapeResource[] (local types, no import gymnastics)"
  - "loadPresetAtPosition builds newGeomsTyped/newPSTyped maps and merges in a single set() call for atomicity"
  - "node_modules symlink created in worktree to run vitest (worktree has no node_modules; symlink to main gui/node_modules)"
  - "Pre-existing test failures in AppShell.test.tsx and contextMenus.test.tsx are out of scope (confirmed by reproducing on main gui-redesign branch)"
metrics:
  duration: "~35 minutes"
  completed_date: "2026-05-20"
  tasks_completed: 4
  tasks_total: 4
  files_created: 1
  files_modified: 1
---

# Phase 70 Plan 03: Presets Store Slice Summary

**One-liner:** Zustand presets slice with 7 async Tauri-FS actions (refresh, save, load-at-position, load-from-path, rename, delete), ActiveLeftTab extended to include "Presets", and 17 vitest tests under fully mocked Tauri — zero real filesystem operations.

## What Was Built

### Tasks 1–3: useStore.ts additions (commit 8b7f3e0)

All modifications to `gui/src/store/useStore.ts` were committed in a single atomic commit covering Tasks 1, 2, and 3 (all touch the same file).

**Task 1 — ActiveLeftTab extension + state fields + refresh action:**
- Extended `ActiveLeftTab` union: `"Components" | "Resources" | "Project" | "Presets"`.
- Added named imports from `../lib/presetIO`: `autoExtendSelection`, `deserializePreset`, `normalizeLayout`, `serializePreset`, `isValidPresetName`, `PresetIndexEntry`.
- Added `projectPresets: [] as PresetIndexEntry[]` and `libraryPresets: [] as PresetIndexEntry[]` to initial state.
- Added `setProjectPresets` and `setLibraryPresets` trivial setters (pattern: `setActiveLeftTab`).
- Added `refreshPresetsDir(store, dir)`: dynamic-imports `readDir`/`readTextFile`, filters `.scpr` files, per-file try/catch skips unreadable files, catches directory-not-found at the outer level, populates `projectPresets` or `libraryPresets`.

**Task 2 — saveSelectionAsPreset + loadPresetAtPosition + loadPresetFromPath:**

`saveSelectionAsPreset`:
- Charset guard via `isValidPresetName` (T-70-08).
- Minimum 2 selected components guard.
- `autoExtendSelection` for BC-hop (D-12).
- Strips `data.autoExtended` from preset nodes (Pitfall 7 defense-in-depth).
- Collects embedded `GeometryResource`/`PowerShapeResource` by UUID dedup across 4 parameter keys (`geometry`, `geometry_ref`, `power_shape`, `power_shape_ref`).
- Excludes `SENTINEL_UNSET_POWER_SHAPE` from embedded resources.
- `normalizeLayout` for bbox-top-left at (0,0) (D-11).
- Resolves library dir via `appConfigDir` + `join`; project dir via `currentFilePath` regex + `join`.
- `mkdir` before write (Pitfall 8).
- `serializePreset` then `writeTextFile`.
- `refreshPresetsDir` immediately after write (consistent state before watcher fires).
- NO `_pushSnapshot` (file I/O not undo-able).

`loadPresetAtPosition`:
- Reads `.scpr` via `readTextFile` + `deserializePreset`.
- **Resource remap**: mints new UUIDs for each embedded geometry/power_shape, applies `smartParseAndIncrement` for name collisions, builds `resOldToNew` map.
- **Component remap**: builds `oldToNew` node UUID map, smart-names each component name, remaps all 4 PARAM_KEY_BY_KIND keys via `resOldToNew`, positions nodes at bbox-center of anchor.
- **Edge remap**: `flatMap` with `oldToNew` lookup, drops edges with missing endpoints.
- Single `set()` call: deselects existing nodes, merges new nodes/edges/resources atomically.
- `get()._pushSnapshot()` before `set()` so the full load is a single undo step (D-18).
- Auto-selects all placed nodes (`selected: true`).

`loadPresetFromPath`:
- Opens `plugin-dialog` file picker filtered to `.scpr`.
- Delegates to `loadPresetAtPosition`.

**Task 3 — renamePreset + deletePreset:**

`renamePreset`:
- Charset guard.
- Reads + parses existing file.
- Derives new path from dir + new name + `.scpr`.
- Collision check: attempts `readTextFile(newPath)`; if succeeds, throws "already exists".
- Rewrites JSON with updated `name` field via `serializePreset`.
- Writes to new path, removes old path (when basename changed).
- Determines store from `projectPresets`/`libraryPresets` arrays and calls `refreshPresetsDir`.
- NO `_pushSnapshot`.

`deletePreset`:
- `remove(filePath)`.
- Determines store from arrays and calls `refreshPresetsDir`.
- NO `_pushSnapshot`.

### Task 4: presetActions.test.ts (commit 121f1c7)

17 vitest tests in 5 `describe` blocks:

| Block | Tests |
|-------|-------|
| `refreshPresetsDir` | 3: populates from valid files; skips corrupt files; handles missing dir |
| `saveSelectionAsPreset` | 5: writes correct JSON; throws <2 selected; throws invalid name; throws no project path; auto-extend BC neighbour |
| `loadPresetAtPosition` | 5: mints new UUIDs; smart-names collisions; adds resources + remaps UUIDs; auto-selects; deselects pre-existing |
| `renamePreset` | 3: rewrites JSON + file; throws on charset; throws on collision |
| `deletePreset` | 1: calls remove with correct path |

All 17 pass. Zero real filesystem operations. All Tauri surfaces mocked:
- `@tauri-apps/plugin-fs`: `writeTextFile`, `readTextFile`, `remove`, `mkdir`, `readDir`, `rename`
- `@tauri-apps/api/path`: `join` (joins with `/`), `appConfigDir` (returns `/mock/config`)
- `@tauri-apps/plugin-dialog`: `open`

## Deviations from Plan

### Auto-fixed Issues

None. Plan executed as written.

### Implementation Notes

**1. node_modules symlink for worktree testing**

The worktree has no `node_modules` directory. To run `vitest` from the worktree, a symlink was created:

```
/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-aadfc8c1c47ae30f7/gui/node_modules
  -> /home/itay/projects/Julia-STREAM/gui/node_modules
```

This symlink is not tracked by git (gitignored). The worktree's `vitest.config.ts` + the symlinked `node_modules` allows `vitest run` to succeed.

**2. Pre-existing test failures (out of scope)**

3 test files in the full suite fail: `AppShell.test.tsx`, `contextMenus.test.tsx`, `SidebarPanel.anchors.test.tsx`. Reproduced identically on the `gui-redesign` main branch — not introduced by this plan. Logged per deviation-rules scope-boundary: do not fix, do not retry.

## Threat Model Compliance

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-70-08 | MITIGATED | `saveSelectionAsPreset` + `renamePreset` call `isValidPresetName` before any FS write. Verified by tests. |
| T-70-09 | MITIGATED | Charset `[A-Za-z0-9_-]+` rejects `.`, `/`, `\`, so `name + ".scpr"` cannot escape the preset dir. |
| T-70-10 | MITIGATED | `SENTINEL_UNSET_POWER_SHAPE` excluded from embedded resources (no sentinel leaks). Light-water fluid not collected. |
| T-70-11 | ACCEPTED | `deserializePreset` validates `format_version`+`kind`; deeper component-shape validation deferred to Phase 71. |
| T-70-12 | ACCEPTED | No per-dir size cap; per-user preset libs expected to be small. |
| T-70-13 | MITIGATED | Regex `[/\\][^/\\]+$` matches both POSIX and Windows separators. Used in `renamePreset` and project-store dir derivation. |

## Known Stubs

None — this is a pure store slice with no UI rendering.

## Threat Flags

None — no new network endpoints, auth paths, or file-access patterns beyond those already in the threat model for this plan.

## Self-Check: PASSED

- [x] `gui/src/store/useStore.ts` exists and contains `ActiveLeftTab` with `"Presets"`
- [x] `gui/src/store/__tests__/presetActions.test.ts` exists
- [x] Commit 8b7f3e0 exists (Tasks 1-3: presets slice)
- [x] Commit 121f1c7 exists (Task 4: tests)
- [x] `projectPresets` and `libraryPresets` fields present in state
- [x] All 7 actions present in useStore.ts
- [x] 17 vitest tests pass; >= 12 required
- [x] All tests use `vi.mock` for `@tauri-apps/plugin-fs`, `@tauri-apps/api/path`, `@tauri-apps/plugin-dialog`
- [x] Zero real filesystem operations in tests
- [x] No `_pushSnapshot` in `saveSelectionAsPreset`, `renamePreset`, `deletePreset`, `refreshPresetsDir`
- [x] Single `_pushSnapshot` in `loadPresetAtPosition`

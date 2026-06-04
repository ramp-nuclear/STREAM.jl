---
phase: 62
plan: 04
subsystem: gui-persistence
tags: [gui, persistence, hard-cutover, scp-v2, inv-10]
requires: [62-02]
provides:
  - "StreamProject v2.0 schema (projectIO.ts)"
  - "Tauri save/open wired to .scp filter"
  - "INV-10 file-not-found UX + relocatePowerShapeFile action"
  - "absolute->relative path conversion for file_loaded PowerShapes"
affects:
  - gui/src/lib/projectIO.ts
  - gui/src/store/useStore.ts
  - gui/src/lib/__tests__/projectIO.scp.test.ts
tech-stack:
  added: []
  patterns:
    - "Strict format_version: '2.0' literal — no read-side migration shim"
    - "Sentinel re-injection on load (in-memory-only PowerShape + Fluid)"
    - "Computed relative paths (Tauri 2 path plugin lacks relative())"
key-files:
  created:
    - .planning/phases/62-resources-panel-architecture/62-04-SUMMARY.md
    - gui/src/lib/__tests__/projectIO.scp.test.ts
  modified:
    - gui/src/lib/projectIO.ts
    - gui/src/store/useStore.ts
  deleted:
    - gui/src/lib/__tests__/projectIO.test.ts
decisions:
  - "Legacy projectIO.test.ts (tested v1 numeric-version shape) deleted — hard cutover applies to tests as well as source"
  - "Tauri 2 @tauri-apps/api/path does not expose relative(); rolled a local computeRelativePath() helper rather than introducing a third-party dep"
  - "INV-10 load-time surface is a Tauri message() dialog (warning kind); per-resource path_missing flag drives the inline banner that lives in the editor (62-08)"
metrics:
  duration: "~30 minutes"
  completed: "2026-05-13"
  tasks_completed: "4 of 4 (Task 4 was a vacuous no-op)"
  tests: "25 new vitest cases / 25 passing (covers INV-06, INV-07, INV-08, INV-09, INV-11, INV-13)"
---

# Phase 62 Plan 04: .scp v2.0 Persistence + Hard Cutover Summary

Lock the v2.0 persistence shape that downstream Wave 3 codegen and example
fixtures depend on. After this plan, projects on disk speak v2.0 only — no
legacy fallback path, no `.streamgui` reference survives anywhere in
`gui/src` or `gui/src-tauri`. The format is strict on the version string and
empty-state tolerant on every other top-level field.

## Final shape of StreamProject v2.0

```ts
interface StreamProject {
  format_version: "2.0";                       // strict literal — no migration
  model_options: ModelOptionsSliceState;       // { name, description, default_fluid, g_default, solver: { abstol, reltol, dtmax } }
  resources: {
    geometries: GeometryResource[];            // Record<uuid,T> on the store side; T[] on disk
    power_shapes: PowerShapeResource[];        // sentinel NOT serialized
    fluids: FluidResource[];                   // light_water placeholder NOT serialized
  };
  components: Node[];                          // ReactFlow Node[]; was `nodes`
  connections: Edge[];                         // ReactFlow Edge[]; was `edges`
  bcs: BCEntry[];                              // unchanged
  layout: {
    active_left_tab: "Components" | "Resources" | "Project";  // D-08 / D-29
    active_layer: "Hydraulic" | "Both" | "Thermal";           // was top-level activeLayer
  };
}
```

Serialization rule: the **store** keeps `resources.{geometries,powerShapes,fluids}`
as `Record<uuid, T>`; the **disk** keeps them as arrays. `serializeProject`
converts via `Object.values()` and filters out:

- `uuid === SENTINEL_UNSET_POWER_SHAPE` from `powerShapes`
- `name === "light_water"` from `fluids`

`deserializeProject` is empty-state tolerant per RESEARCH Pitfall 3: a minimal
`{"format_version":"2.0"}` parses to a fully-populated empty project (all
arrays default to `[]`, layout defaults to `{ active_left_tab: "Components",
active_layer: "Both" }`, model_options defaults are seeded from the same
constants the store's initial state uses).

## Sentinel + light_water re-injection (loadProjectFromPath)

The disk format strips the unset PowerShape sentinel and the light_water
Fluid placeholder; the in-memory store always has them. `loadProjectFromPath`
performs the conversion:

```ts
const powerShapesRecord = {
  [SENTINEL_UNSET_POWER_SHAPE]: { uuid: SENTINEL_UNSET_POWER_SHAPE, name: "(leave unset — fill in code)", kind: "unset", params: {} },
};
for (const ps of project.resources.power_shapes) {
  if (ps.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;  // defensive — malformed file
  powerShapesRecord[ps.uuid] = ps;
}

const fluidsRecord = {
  [SENTINEL_LIGHT_WATER_FLUID]: { uuid: SENTINEL_LIGHT_WATER_FLUID, name: "light_water" },
};
for (const f of project.resources.fluids) {
  if (f.uuid === SENTINEL_LIGHT_WATER_FLUID) continue;
  fluidsRecord[f.uuid] = f;
}
```

Defensive: a hand-edited `.scp` that re-introduced the sentinel UUID would
otherwise have its sentinel record clobbered by the legitimate in-memory one.
The guard `continue` keeps the in-memory shape stable.

## INV-10 implementation details

D-24 in CONTEXT.md is explicit: *"On file-not-found at load: user-visible
error with `Locate file…` action."* This is implemented in three layers:

**1. Store slice — `missingFilePowerShapes: Array<{ uuid, name, pathTried }>`**

Default `[]`. Populated by `loadProjectFromPath` immediately after the
deserialize-and-rehydrate step. Cleared on `newProject` and on `loadProject`
before delegating to `loadProjectFromPath`.

**2. Post-load existence check (loadProjectFromPath)**

For each `file_loaded` PowerShape:

- Resolve absolute path: if `params.path` is relative, `await pathApi.join(scpDir, ps.params.path)`; otherwise use as-is. `scpDir` = `pathApi.dirname(filePath)`.
- Call `await fsApi.exists(absPath)`; on `false` (or thrown), set:
  - `params.path_missing = true`
  - `params.absolute_path_attempted = absPath`
  - push `{ uuid, name, pathTried: absPath }` onto `missingFilePowerShapes`
- The check is fail-soft: a missing file does NOT abort the load. The
  project loads, the in-memory PowerShape carries the `path_missing` flag.

**3. User-visible surface**

- Load-time: a single Tauri `message()` dialog (`kind: "warning"`) fires once
  if `missing.length > 0`. Copy: *"N power shape file(s) could not be found.
  Open the Resources tab to relocate them."* (singular form for N=1 names
  the specific file).
- Per-resource banner: the in-memory `params.path_missing` + `params.absolute_path_attempted`
  drive the inline banner that the PowerShapeResourceEditor will render
  (mount point lives in 62-08; data is plumbed here).

**4. relocatePowerShapeFile action**

Signature: `relocatePowerShapeFile(uuid: string): Promise<void>`.

Body:
- Open Tauri CSV file picker (filter: `[{ name: "CSV (Power Shape)", extensions: ["csv"] }]`).
- If user cancels: no-op.
- Defensively re-check existence on the chosen path via `fsApi.exists`.
- Convert absolute -> relative-to-`.scp` via `computeRelativePath(dirname(currentFilePath), newAbs)`. If the project has not been saved yet (`currentFilePath === null`), store the absolute path — it will be relativized at first save.
- `_pushSnapshot()`, then `set(...)`:
  - Update `resources.powerShapes[uuid].params.path` to the new (relative) path.
  - Clear `path_missing` and `absolute_path_attempted` if the chosen file existed.
  - Drop the entry from `missingFilePowerShapes` on success; keep it (with updated `pathTried`) if the user picked another missing file.
- `isDirty: true`.

## absolute -> relative path conversion (D-24, RESEARCH Pitfall 5)

Tauri 2's `@tauri-apps/api/path` plugin does NOT expose `relative()` — it
exposes `dirname`, `join`, `appDataDir`, `extname`, `resolve`, and a few
others, but the path-relativization primitive is missing. Rather than pull
in a third-party dep, this plan rolls a local `computeRelativePath(fromDir,
toAbs)` helper:

- Normalize backslashes to forward slashes; strip trailing separators.
- Detect Windows-drive divergence (`C:\` vs `D:\` — no common root, return
  absolute unchanged).
- Walk segments, count the unmatched prefix length on the `from` side as
  `..` hops, append the suffix on the `to` side.

The save-time fixup is performed via a **transient copy** of the PowerShapes
Record (`relativizePowerShapePaths` helper) — the in-memory state is NOT
mutated during save. This is what RESEARCH Pitfall 5 specifically warned
against.

## Hard-cutover gate

```bash
$ grep -rc "streamgui" gui/src/ gui/src-tauri/ 2>/dev/null | grep -v ':0$'
# (empty)
```

Zero `.streamgui` references in either `gui/src/` or `gui/src-tauri/`.

The legacy `gui/src/lib/__tests__/projectIO.test.ts` (which exercised the v1
`{version, nodes, edges}` shape and contained 15 `.streamgui` doc-string
references) is deleted. The legacy `gui/export_examples/*.streamgui` files
do not exist in this branch — Task 4 was a vacuous no-op (the directory
itself does not exist in `gui-redesign`).

## Commits

- `e70335d` test(62-04): add failing projectIO.scp v2.0 round-trip + strict-version tests (RED)
- `5d6983f` feat(62-04): rewrite projectIO.ts for .scp v2.0 schema; strip v1 migration shim (GREEN — Task 1)
- `3b43447` feat(62-04): wire useStore.ts for .scp v2.0 persistence + INV-10 file-not-found UX (Task 2)
- `085a77a` chore(62-04): strip residual .streamgui doc-comment references (final cutover scrub)

Task 3 (the dedicated vitest file) was authored in the RED commit and
re-verified after each subsequent change; no standalone Task 3 commit was
made. Task 4 (deletion of `gui/export_examples/*.streamgui`) was vacuously
satisfied — the directory does not exist in this branch.

## Test results

- New vitest file `projectIO.scp.test.ts`: 25 cases, all green
- Full GUI vitest suite: 295 tests pass (17 todo, 1 skipped) — no regressions
- TypeScript baseline: 7 pre-existing errors elsewhere unchanged; 0 new errors in projectIO.ts or useStore.ts
- INV-06 round-trip / INV-13 structural stability: rich fixture (4 nodes, 2 geometries, 3 user PowerShapes + sentinel, file_loaded path, modelOptions filled, activeLeftTab = Resources) round-trips successfully
- INV-07 / INV-08 strict format_version: 6 rejection cases covered (missing, "1.5", "3.0", numeric 2, legacy `version: 2`, legacy `version: 1`)
- INV-09 relative-path preservation: `"shapes/mtr.csv"` round-trips byte-identical
- INV-11 active tab round-trip: parameterized over `Components | Resources | Project`
- Sentinel-skip on save: confirmed
- Empty-state tolerance: `{"format_version":"2.0"}` parses to a fully-populated default project

## Deviations from plan

**None substantive. Three minor adaptations:**

1. **Tauri path API gap (Rule 3 — blocking).** The plan instructed the
   executor to use the `relative()` helper from `@tauri-apps/api/path`.
   That helper does not exist in Tauri 2. I rolled a local
   `computeRelativePath()` helper (~40 lines) inside `useStore.ts` and
   adjusted both call sites (`relativizePowerShapePaths`, `relocatePowerShapeFile`).
   Behavior matches the plan's spec (relative POSIX-style path; falls back
   to absolute when paths share no common root).

2. **Worktree environment fix-up (Rule 3 — blocking).** The worktree had
   no `gui/node_modules/`; `npx vitest` fetched a fresh 4.1.6 binary that
   failed to load the project's `vitest.config.ts`. I created a symlink
   `gui/node_modules -> /home/itay/projects/Julia-STREAM/gui/node_modules`
   so the worktree picks up the main repo's installed dependencies
   (vitest 4.1.2 matches `package.json`). The symlink is not staged
   (node_modules is gitignored).

3. **Task 4 vacuous no-op.** The `gui/export_examples/` directory does not
   exist in the `gui-redesign` branch — no `.streamgui` files to delete.
   Documented in the Task 4 commit message and in this summary.

No threat flags. No new untracked files staged beyond what plan files_modified declared.

## Self-Check: PASSED

- [x] `gui/src/lib/projectIO.ts` — exists, rewritten for v2.0
- [x] `gui/src/store/useStore.ts` — exists, .scp wiring + INV-10 plumbed
- [x] `gui/src/lib/__tests__/projectIO.scp.test.ts` — exists, 25 tests pass
- [x] `gui/src/lib/__tests__/projectIO.test.ts` — deleted (hard cutover applies to tests too)
- [x] Commit `e70335d` exists (RED)
- [x] Commit `5d6983f` exists (Task 1 GREEN)
- [x] Commit `3b43447` exists (Task 2)
- [x] Commit `085a77a` exists (cleanup)
- [x] `grep -rc streamgui gui/src/ gui/src-tauri/` returns 0
- [x] All Task 1/2/3 acceptance grep gates pass
- [x] Full vitest suite green (295 passing)

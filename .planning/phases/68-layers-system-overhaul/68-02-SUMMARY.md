---
phase: 68-layers-system-overhaul
plan: 02
subsystem: gui/state-and-persistence
tags: [layers, zustand, scp, projectIO, persistence, tdd, backward-compat-shim]
dependency_graph:
  requires:
    - "Plan 68-01: gui/src/lib/layers.ts (LayerKey, ActiveLayers, ALL_LAYERS_ON)"
  provides:
    - "useStore: activeLayers + hideOffLayer state, toggleLayer/setLayerVisible/setAllLayersVisible/setHideOffLayer actions"
    - "projectIO: layout.active_layers + layout.hide_off_layer schema + one-shot legacy active_layer read shim"
  affects:
    - "Plan 68-03 (CanvasPanel enrichment) — reads activeLayers + hideOffLayer; calls toggleLayer/setLayerVisible"
    - "Plan 68-04 (LayersChip popover) — reads activeLayers; calls toggleLayer + setHideOffLayer"
    - "Plan 68-05 (SecondaryToolbar deletion + ViewMenu cleanup) — must not reference removed setActiveLayer/cycleLayer"
tech-stack:
  added: []
  patterns:
    - "One-shot legacy-field read shim in deserializer (no write-side compat — D-05 + CLAUDE.md no-back-compat-during-heavy-dev)"
    - "4-layer Record<LayerKey, boolean> with ALL_LAYERS_ON overlay for partial reads (missing keys default to true)"
    - "Layer state lives in the layout block alongside snap_to_grid / active_left_tab — NOT in the undoable CanvasSnapshot"
key-files:
  created: []
  modified:
    - "gui/src/store/useStore.ts (state slice + 4 actions + 6 serialize/deserialize call sites + newProject reset)"
    - "gui/src/lib/projectIO.ts (StreamProject['layout'] schema + SerializeProjectArgs/DeserializeProjectResult types + deserializer shim + defaultLayout)"
    - "gui/src/store/__tests__/useStore.test.ts (replaced activeLayer describe with 13-test activeLayers block)"
    - "gui/src/store/__tests__/useStore.codePanel.test.ts (fixture migration to new serialize args)"
    - "gui/src/store/__tests__/saveAndOpenErrors.test.ts (resetStore fixture migration)"
    - "gui/src/lib/__tests__/projectIO.snapToGrid.test.ts (fixture migration + 8 new tests A-H)"
key-decisions:
  - "Shim mapping (per CONTEXT.md Claude's-Discretion + tests C/D/E): legacy active_layer string `Both`/missing → ALL_LAYERS_ON; `Hydraulic` → only Hydraulic true; `Thermal` → only Thermal true"
  - "New active_layers wins when both fields present (Test G) — overlaid onto ALL_LAYERS_ON so partial objects default missing keys to true"
  - "Write side never emits the legacy active_layer string (Test H) — clean break per D-05"
  - "Layer state is NOT undoable (CanvasSnapshot unchanged) — mirrors the prior activeLayer behavior and the comment at useStore.ts:145"
patterns-established:
  - "Per-key partial-overlay read shim: `{...ALL_LAYERS_ON, ...rawPartial}` — guarantees forward-compat when future layer keys are added"
  - "Setter convention: every layer setter sets isDirty: true so saves capture changes (matches setSnapToGrid pattern)"
  - "Test-fixture migration tracked as 'fixture-update touch only' commits — no new behavioral tests in pure-fixture files (codePanel, saveAndOpenErrors)"
requirements-completed: [D-05]
metrics:
  duration: ~25 min
  completed: 2026-05-16
  tasks_completed: 2
  files_changed: 6
  tests_added: 21    # 13 store + 8 projectIO
  tests_passing: 91  # across all 4 verify files
---

# Phase 68 Plan 02: Store + .scp 4-layer migration Summary

**Replaced the v0.8 `activeLayer: LayerView` three-mode store slice with a `Record<LayerKey, boolean>` 4-layer independent-toggle state + `hideOffLayer` boolean, migrated the `.scp` `layout` block to `active_layers` + `hide_off_layer`, and added a one-shot read shim that auto-translates legacy `active_layer` strings into the new shape.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-05-16
- **Tasks:** 2 (each split RED + GREEN per TDD)
- **Files modified:** 6 (2 source, 4 test)
- **Tests added:** 21 (13 store + 8 projectIO)
- **Tests passing:** 91 across the four verify files (zero regressions)

## Accomplishments

- Store contract is now the 4-layer shape Wave 3 (Plans 03, 04, 05) was promised — `activeLayers`, `hideOffLayer`, `toggleLayer`, `setLayerVisible`, `setAllLayersVisible`, `setHideOffLayer`.
- Old API physically gone — `setActiveLayer`, `cycleLayer`, the typed `activeLayer` field, and `LayerView` import are deleted. Test 11/12/13 in the new store suite assert `undefined` on each of them.
- `.scp` schema migrated and round-tripping works under TDD test suite — new files write `active_layers` + `hide_off_layer`; old files with `active_layer: "Both"/"Hydraulic"/"Thermal"` are read correctly via the documented shim.
- All four serialize call sites (saveProject, saveProjectAs, AutoRecover writer, AutoRecover hydrate) updated; both load paths (loadProjectFromPath + AutoRecover hydrate) read the new fields; `newProject` resets to ALL_LAYERS_ON.

## Contract Exposed to Downstream Plans

**Plans 03, 04, 05 read from `useStore`:**

```ts
const activeLayers = useStore(s => s.activeLayers);       // ActiveLayers (Record<LayerKey, boolean>)
const hideOffLayer = useStore(s => s.hideOffLayer);       // boolean
const toggleLayer  = useStore(s => s.toggleLayer);        // (key: LayerKey) => void
const setLayerVisible    = useStore(s => s.setLayerVisible);    // (key, visible) => void
const setAllLayersVisible = useStore(s => s.setAllLayersVisible); // (visible) => void
const setHideOffLayer    = useStore(s => s.setHideOffLayer);    // (value) => void
```

**.scp `layout` block schema (Plan 03/04/05 do NOT touch this — informational):**

```jsonc
{
  "layout": {
    "active_left_tab": "Components",                         // unchanged
    "active_layers": {                                       // NEW (Phase 68)
      "Hydraulic": true,
      "Thermal": true,
      "Sources": true,
      "ReactorPhysics": true
    },
    "hide_off_layer": false,                                 // NEW (Phase 68)
    "snap_to_grid": false                                    // unchanged
  }
  // `active_layer` (singular) is NEVER written. Read-side compat only.
}
```

**`SerializeProjectArgs` (consumed by `serializeProject(...)`):**

```ts
interface SerializeProjectArgs {
  // ... unchanged fields ...
  activeLayers: ActiveLayers;   // REPLACES `activeLayer: LayerView`
  hideOffLayer: boolean;        // NEW
  snapToGrid: boolean;
}
```

**`DeserializeProjectResult.layout`:** same shape as the `.scp` schema above; the deserializer's shim guarantees `active_layers` and `hide_off_layer` are always populated.

## Legacy Read Shim — Authoritative Mapping

| `.scp` content                                           | Resolved `active_layers`                                                | Resolved `hide_off_layer` |
| -------------------------------------------------------- | ----------------------------------------------------------------------- | ------------------------- |
| `active_layers: {...}` present (any keys)                | `{ ...ALL_LAYERS_ON, ...rawActiveLayers }` — new wins; missing → true   | `hide_off_layer` or `false` |
| `active_layer: "Both"`, no `active_layers`               | `{ H: true, T: true, S: true, RP: true }`                              | `false`                   |
| `active_layer: "Hydraulic"`, no `active_layers`          | `{ H: true, T: false, S: false, RP: false }`                           | `false`                   |
| `active_layer: "Thermal"`, no `active_layers`            | `{ H: false, T: true, S: false, RP: false }`                           | `false`                   |
| Neither field present                                    | `ALL_LAYERS_ON`                                                         | `false`                   |
| Both `active_layers` and `active_layer` present          | new `active_layers` wins; legacy field ignored                          | per `hide_off_layer`      |

(H = Hydraulic, T = Thermal, S = Sources, RP = ReactorPhysics)

Per CLAUDE.md no-back-compat-during-heavy-dev: this is a one-shot read-side shim only; old `.scp` files are translated on first load and the next save writes the new format. There is no write-side compatibility.

## Task Commits

Each task followed TDD with separate RED and GREEN commits per the plan's `tdd="true"` flag:

1. **Task 1 RED:** `fd8130b` — `test(68-02): add failing tests for 4-layer store API`
2. **Task 1 GREEN:** `e2721ad` — `feat(68-02): replace activeLayer slice with 4-layer state in useStore`
3. **Task 2 RED:** `1d0690c` — `test(68-02): add failing tests for .scp active_layers + legacy shim`
4. **Task 2 GREEN:** `2acdb61` — `feat(68-02): migrate .scp layout block to 4-layer + legacy shim`

## Files Created/Modified

**Modified (source):**
- `gui/src/store/useStore.ts` — `LayerView` import replaced with `{ LayerKey, ActiveLayers, ALL_LAYERS_ON }`; AppState slice updated (activeLayers + hideOffLayer + 4 actions); 4 serialize call sites + 2 load paths + newProject reset updated.
- `gui/src/lib/projectIO.ts` — `StreamProject["layout"]` and `SerializeProjectArgs` types migrated; `defaultLayout()` returns new fields; `serializeProject` writes new fields and never writes legacy; `deserializeProject` implements the one-shot read shim.

**Modified (tests):**
- `gui/src/store/__tests__/useStore.test.ts` — replaced `describe("activeLayer")` with a 13-test `describe("activeLayers")` block.
- `gui/src/store/__tests__/useStore.codePanel.test.ts` — fixture-only update at line 226 (replaced `activeLayer` arg with `activeLayers + hideOffLayer`).
- `gui/src/store/__tests__/saveAndOpenErrors.test.ts` — fixture-only update at line 74 (resetStore).
- `gui/src/lib/__tests__/projectIO.snapToGrid.test.ts` — `makeMinimalSerializeArgs` migrated to new args; appended a 5-test round-trip block + a 5-test legacy-compat block (8 new tests total: A-H from the plan's `<behavior>`).

## Decisions Made

- **Shim returns `{ ...ALL_LAYERS_ON, ...rawActiveLayers }`** rather than raw `rawActiveLayers`. This is forward-compat: if a future layer key (say `"Acoustic"`) is added and an older `.scp` lacks it, the missing key defaults to `true` rather than `undefined`. Cleaner than a strict equality check and matches Wave 1's `ALL_LAYERS_ON` design intent.
- **Legacy comment lines retained** (useStore.ts:213 + projectIO.ts:116 reference `activeLayer: LayerView` historically) — kept as deliberate explanatory comments for code archaeology / phase-doc traceability. Verified the references are physically gone from typed code by the deny-grep with comment exclusion.
- **No new behavioral tests in codePanel/saveAndOpenErrors** — kept as fixture-only touches per plan instruction; those files have their own concerns (code-panel slice exclusion, save/open error paths) and shouldn't grow layer-system tests.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] Worktree had no `gui/node_modules`; vitest was unresolvable**
- **Found during:** Task 1 RED (`npx vitest run …` failed with `Cannot find package 'vitest'`)
- **Issue:** The worktree at `.claude/worktrees/agent-aa9aa203c8b0014a3` was created without running `npm install` in `gui/`, so `gui/node_modules` didn't exist. `npx vitest` walked up the tree, found a stale `.vite-temp` from the main repo, and crashed on a transitive `vitest/config` resolve.
- **Fix:** Symlinked `gui/node_modules → /home/itay/projects/Julia-STREAM/gui/node_modules` so the worktree uses the main repo's installed deps. This avoids a multi-minute `npm install` and is consistent with how the worktree spawn is supposed to work (deps come from main, code is isolated).
- **Files modified:** None tracked by git (`node_modules` is gitignored).
- **Verification:** `./node_modules/.bin/vitest run` succeeds and all 91 tests across the four verify files pass.
- **Commit:** n/a (infrastructure-only deviation; no code change).

---

**Total deviations:** 1 auto-fixed (1 blocking infrastructure).
**Impact on plan:** Zero scope creep; no source-code drift from plan. The plan's `<verify>` command `npx vitest` is replaced 1-for-1 with `./node_modules/.bin/vitest` after the symlink; identical semantics.

## Issues Encountered

- **Plan-language nit (not a deviation):** The plan's grep verification `grep ... | grep -v '^//'` does not strip indented `//` lines. Two deliberate explanatory comments remain (`useStore.ts:213` and `projectIO.ts:116`) that reference the deleted `activeLayer: LayerView` in prose. Verified manually they are not typed code by re-running the grep with `awk '$3 ~ /^[[:space:]]*\/\//'` filter — both flagged as `COMMENT:`. Acceptable per spirit of the acceptance criterion ("old API physically removed" — the typed field/setters are gone; the words live on as documentation).

## User Setup Required

None — no external service configuration, no new dependencies, no environment variables, no schema migrations beyond the in-app read shim.

## Next Phase Readiness

**Ready for Wave 3 (Plans 68-03, 68-04, 68-05):**
- Plans 03 (CanvasPanel enrichment) and 04 (LayersChip) can now import `useStore` and consume `activeLayers` + `hideOffLayer` via selectors and call the four new setters.
- Plan 05 (SecondaryToolbar deletion + ViewMenu/App cleanup) must ensure none of its deletions/additions re-introduce a reference to the now-deleted `setActiveLayer` / `cycleLayer` / `activeLayer` / `LayerView` symbols — running `cd gui && npx tsc --noEmit` after Wave 3 lands will catch any stragglers (and is the documented success gate at the bottom of the plan's `<verification>` block).

**Expected non-blocker for Wave 3:** A repo-wide `tsc --noEmit` still fails after Wave 2 because Plans 03/04/05 own the remaining consumers (`CanvasPanel.tsx`, `StreamNode.tsx`, `ToolboxPanel.tsx`, `ViewMenu.tsx`, `SecondaryToolbar.tsx`, `App.tsx`, `BottomPanel.tsx`) that still reference the old API. Wave 2 deliberately unblocks Wave 3 — full tsc clean is Plan 05's responsibility.

## TDD Gate Compliance

| Plan task | Gate | Commit | Status |
| --------- | ---- | ------ | ------ |
| Task 1    | RED  | `fd8130b` | 11/13 new tests failed against old store; 2 default-state assertions accidentally passed via the `beforeEach` setState |
| Task 1    | GREEN | `e2721ad` | All 13 store tests + 21 codePanel tests pass (72/72) |
| Task 2    | RED  | `1d0690c` | 8/13 projectIO tests failed against old projectIO (5 pre-existing snap-to-grid tests still passed) |
| Task 2    | GREEN | `2acdb61` | All 13 projectIO tests pass; full Wave 2 suite is 91/91 |

REFACTOR pass: not needed. The implementation is minimal and clear; no duplication to consolidate. The shim block in `deserializeProject` is a deliberate flat `if/else if/else` ladder for readability over a lookup-table abstraction (only 3 legacy values to handle).

## Known Stubs

None. The 4-layer state is fully wired end-to-end through the store and `.scp` round-trip. Wave 3 (Plans 03/04/05) consumes these slices to produce UI; that's not a stub of this plan's scope — it's the next plan's scope.

## Threat Flags

None. This plan modifies in-process Zustand state and the local-file `.scp` JSON schema. No network surface, no auth path, no new file-system access patterns (the writes already existed; only field names changed). The legacy-read shim parses untrusted JSON values with `as string | undefined` casts and never executes them — pure data transformation.

## Self-Check

- [x] `gui/src/store/useStore.ts` — `activeLayers` + `hideOffLayer` fields and 4 setters present; old API physically gone (deny-grep clean modulo 2 documentation comments)
- [x] `gui/src/lib/projectIO.ts` — `SerializeProjectArgs` + `DeserializeProjectResult` migrated; `serializeProject` writes new fields only; `deserializeProject` implements the documented shim
- [x] `gui/src/store/__tests__/useStore.test.ts` — 13-test `describe("activeLayers")` block present and passing
- [x] `gui/src/lib/__tests__/projectIO.snapToGrid.test.ts` — 8 new tests A-H present and passing; fixture migrated
- [x] `gui/src/store/__tests__/useStore.codePanel.test.ts` — fixture migrated; 21 tests pass
- [x] `gui/src/store/__tests__/saveAndOpenErrors.test.ts` — fixture migrated
- [x] Commit `fd8130b` (Task 1 RED) — `git log` shows hash
- [x] Commit `e2721ad` (Task 1 GREEN) — `git log` shows hash
- [x] Commit `1d0690c` (Task 2 RED) — `git log` shows hash
- [x] Commit `2acdb61` (Task 2 GREEN) — `git log` shows hash
- [x] Full Wave 2 verification: `vitest run` on all 4 plan files → 91/91 pass

## Self-Check: PASSED

---
*Phase: 68-layers-system-overhaul*
*Completed: 2026-05-16*

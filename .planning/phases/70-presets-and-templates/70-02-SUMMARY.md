---
phase: 70-presets-and-templates
plan: "02"
subsystem: gui
tags: [presetIO, serialization, typescript, vitest, preset-schema]
dependency_graph:
  requires: []
  provides:
    - gui/src/lib/presetIO.ts
  affects:
    - gui/src/store/useStore.ts (plan 70-03 imports PresetIndexEntry, deserializePreset)
    - gui/src/components/SavePresetModal.tsx (plan 70-04 imports serializePreset, autoExtendSelection, normalizeLayout, isValidPresetName)
    - gui/src/components/PresetsPanel.tsx (plan 70-05 imports PresetIndexEntry type)
tech_stack:
  added: []
  patterns:
    - "projectIO.ts format-version constant pattern applied to .scpr schema"
    - "XOR-snapshot pattern for one-hop graph extension (prevents recursive expansion)"
key_files:
  created:
    - gui/src/lib/presetIO.ts
    - gui/src/lib/__tests__/presetIO.test.ts
  modified: []
decisions:
  - "autoExtendSelection XOR check uses snapshot of original selection (not growing extendedIds) to enforce one-hop D-13 invariant — discovered during test authoring"
  - "normalizeLayout returns {} for empty nodes array (safe against Math.min spread of empty)"
  - "serializePreset strips data.autoExtended via shallow data clone (defense-in-depth Pitfall 7)"
  - "deserializePreset provides defensive defaults only for description ?? '' and resources.fluids ?? [] — other required fields are not defaulted"
metrics:
  duration: "~8 minutes"
  completed: "2026-05-20T20:03:17Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 1
---

# Phase 70 Plan 02: presetIO Pure Library Summary

**One-liner:** Pure `.scpr` v1.0 serialize/deserialize library with BC-hop auto-extend, bbox layout normalization, and preset-name charset gate — 18 vitest tests, zero Tauri imports.

## What Was Built

### `gui/src/lib/presetIO.ts` (new, 341 lines)

Pure TypeScript module with 10 named exports. Zero Tauri imports; fully testable in vitest node environment.

| Export | Kind | Purpose |
|--------|------|---------|
| `PRESET_FORMAT_VERSION` | const | `"1.0" as const` — schema version lock |
| `PRESET_NAME_RE` | const | `/^[A-Za-z0-9_-]+$/` — charset gate (D-10) |
| `isValidPresetName` | function | `PRESET_NAME_RE.test(name)` |
| `StreamPreset` | interface | `.scpr` v1.0 schema (D-07) |
| `PresetIndexEntry` | interface | Tab index entry; consumed by plan 70-03 |
| `SerializePresetArgs` | interface | Args for `serializePreset` |
| `serializePreset` | function | Builds `StreamPreset`, strips `data.autoExtended`, returns JSON |
| `deserializePreset` | function | Parses JSON, strict format_version + kind checks |
| `autoExtendSelection` | function | One-hop BC-edge extension + edge partition |
| `normalizeLayout` | function | Shifts positions so bbox-top-left = (0,0) |

### `gui/src/lib/__tests__/presetIO.test.ts` (new, 270 lines)

18 vitest tests in 6 `describe` blocks:
- **round-trip** (2): minimal preset + autoExtended stripping
- **rejection** (3): missing format_version, wrong format_version, wrong kind
- **autoExtendSelection** (6): BC hop, non-BC no-hop, single-hop invariant D-13, keptEdges, droppedEdges, empty-selection
- **normalizeLayout** (3): positive shift, negative coords, empty array
- **isValidPresetName** (3): accepts, rejects charset violations, rejects regex failures
- **PRESET_FORMAT_VERSION** (1): literal lock

All 18 tests pass. Zero `vi.mock`. Zero filesystem reads.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed autoExtendSelection single-hop invariant (D-13)**

- **Found during:** Task 2 test authoring — the D-13 single-hop test `{A}` + `A--bc--B--bc--C` → `{A,B}` was failing; C was being added.
- **Issue:** The XOR check (`originalIds.has(source) !== originalIds.has(target)`) was evaluated against the *growing* `extendedIds` set. When B was added during the A--B edge iteration, the subsequent B--C edge evaluated B as "inside" (it had just been added), triggering a second hop and adding C — violating D-13.
- **Fix:** Snapshot `originalIds = new Set(selectedNodeIds)` before the loop. XOR evaluated against `originalIds` only; `extendedIds` still accumulates additions. Enforces strict one-hop semantics regardless of edge ordering.
- **Files modified:** `gui/src/lib/presetIO.ts`
- **Commit:** 2248c9c (included in Task 2 commit alongside test file)

## Threat Model Compliance

| Threat ID | Status | Notes |
|-----------|--------|-------|
| T-70-04 | MITIGATED | Strict `format_version === "1.0"` + `kind === "preset"` checks; both throw. No `eval`. Verified by 3 rejection tests. |
| T-70-06 | MITIGATED | `data.autoExtended` stripped via shallow clone in `serializePreset`. Verified by Test 1.2. |
| T-70-07 | MITIGATED | `PRESET_NAME_RE` `/^[A-Za-z0-9_-]+$/` rejects path separators, Unicode, spaces. Verified by isValidPresetName tests. |
| T-70-05 | ACCEPTED | No size cap at this layer; Tauri FS gate is upstream. |

## Known Stubs

None — this is a pure utility module with no data sources or UI rendering.

## Threat Flags

None — no new network endpoints, auth paths, or trust boundaries introduced. The `deserializePreset` boundary was already in the threat model (T-70-04).

## Self-Check

- [x] `gui/src/lib/presetIO.ts` exists
- [x] `gui/src/lib/__tests__/presetIO.test.ts` exists
- [x] Commit 33c9f2e exists (Task 1)
- [x] Commit 2248c9c exists (Task 2 + bug fix)
- [x] `grep -c 'tauri' gui/src/lib/presetIO.ts` = 0
- [x] 10 named exports verified by grep
- [x] 18 vitest tests pass (0 failed)
- [x] Zero `vi.mock` in test file
- [x] Zero filesystem reads in test file

## Self-Check: PASSED

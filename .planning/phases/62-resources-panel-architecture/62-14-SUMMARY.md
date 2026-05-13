---
phase: 62
plan: 14
subsystem: gui/store/persistence
tags: [gui, persistence, save-as, model-options, gap-closure]
gap_closure: true
gap_source: 62-VERIFICATION.md
gap_step: 15
root_plan: 62-04
requirements: []
dependency_graph:
  requires: ["62-04 (saveProjectAs action / Tauri dialog plumbing)", "62-07 (Model Options Name field commits to modelOptions.name)"]
  provides: ["File → Save As pre-fills OS picker with <name>.scp (sanitized) instead of literal project.scp"]
  affects: ["gui/src/store/useStore.ts"]
tech_stack:
  added: []
  patterns: ["pure module-level helper + lazy get() read inside async action"]
key_files:
  created:
    - gui/src/store/__tests__/saveProjectAs.test.ts
  modified:
    - gui/src/store/useStore.ts
decisions:
  - "Sanitize but do NOT lowercase: preserve original case so a user typing `Phase62.SCP` stays `Phase62.SCP`."
  - "Case-insensitive endsWith for the `.scp` suffix check (no double extension whether user types `.scp` or `.SCP`)."
  - "Collapse internal whitespace runs to a single space (cosmetic; prevents `my   project` becoming a 3-space-padded filename)."
  - "Helper is module-scoped + exported for unit testing only; not part of the store's public reactive API surface."
  - "Lazy `get().modelOptions.name` read inside the async action body — reflects a name edit between action start and dialog open."
metrics:
  duration_minutes: 4
  completed: 2026-05-13
  tests_added: 15
  files_modified: 2
---

# Phase 62 Plan 14: Save As default filename from Model Options name — Summary

## One-liner

Pipe `modelOptions.name` (Plan 62-07's Model Options form Name field) into the Tauri `save()` dialog's `defaultPath` via a new pure helper `computeSaveAsDefaultFilename`, so File → Save As pre-fills `<name>.scp` (sanitized, no double-extension, empty-fallback to `project.scp`) instead of the pre-Phase-62-14 literal `project.scp` hardcode. Closes VERIFICATION.md Critical Gap #3.

## What changed

### `gui/src/store/useStore.ts`

1. New module-level constant:
   ```ts
   const FALLBACK_SAVE_AS_FILENAME = `project.${PROJECT_FILE_EXTENSION}` as const;
   ```
2. New module-level regex (eslint-disable for the control-char range):
   ```ts
   const ILLEGAL_FILENAME_CHARS_RE = /[\\/:*?"<>|\x00-\x1f]/g;
   ```
3. New exported helper:
   ```ts
   export function computeSaveAsDefaultFilename(name: string): string
   ```
   Sanitization order:
   1. `name.trim()`.
   2. Strip OS-illegal characters with the regex above (`/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`, ASCII control `\x00-\x1f`).
   3. Collapse runs of internal whitespace to a single space (`/\s+/g` → `" "`).
   4. Trim again (step 2 can leave whitespace adjacent to stripped chars, e.g. `" my : project "`).
   5. Empty → return `FALLBACK_SAVE_AS_FILENAME` (`"project.scp"`).
   6. Case-insensitive `endsWith(".scp")` → return the sanitized string unchanged (preserves original case).
   7. Otherwise → append `.${PROJECT_FILE_EXTENSION}`.

   Does NOT lowercase, enforce Julia-identifier rules, or strip filename-legal unicode — `modelOptions.name` is a free-form project label per Plan 62-07.

4. Call site change in `saveProjectAs` (formerly line 1149):
   ```ts
   // before
   defaultPath: `project.${PROJECT_FILE_EXTENSION}`,
   // after
   defaultPath: computeSaveAsDefaultFilename(get().modelOptions.name),
   ```
   Reading `get().modelOptions.name` inside the async body (rather than via destructuring at the top) ensures a name edit committed between the action's start and the actual `save()` await is reflected.

### `gui/src/store/__tests__/saveProjectAs.test.ts` (new)

Two top-level `describe` blocks:

- **`computeSaveAsDefaultFilename` (11 cases, pure helper, no store/mocks):**
  - empty → `"project.scp"`
  - whitespace-only → `"project.scp"`
  - `"phase62-smoke"` → `"phase62-smoke.scp"`
  - `"phase62-smoke.scp"` → `"phase62-smoke.scp"` (no double extension)
  - `"PHASE62.SCP"` → `"PHASE62.SCP"` (case-insensitive endsWith, original case preserved, no lowercase)
  - `"my/bad:name?"` → `"mybadname.scp"`
  - `'/:*?"<>|'` → `"project.scp"` (full-strip empty fallback)
  - `"  trim me  "` → `"trim me.scp"`
  - `"a\x00b\x1fc"` → `"abc.scp"` (control chars)
  - `"multi   space"` → `"multi space.scp"` (internal-whitespace collapse)
  - `"unicode-café"` → `"unicode-café.scp"`

- **`saveProjectAs Tauri dialog defaultPath` (4 cases, store + mocked plugins):**
  - Happy path: `modelOptions.name = "phase62-smoke"` → `saveMock` receives `defaultPath: "phase62-smoke.scp"`, filter extension `"scp"`.
  - Empty-name fallback: `modelOptions.name = ""` → `defaultPath: "project.scp"`.
  - User-cancel: `saveMock` resolves to `null` → `currentFilePath` stays `null`, `writeTextFile` never called for the .scp.
  - Successful save: `saveMock` resolves to `"/tmp/myproj.scp"` → `writeTextFile` called with that path + a valid `format_version: "2.0"` JSON payload; `currentFilePath` set; `isDirty` false.

## Mocking pattern

```ts
const saveMock = vi.fn();
const writeTextFileMock = vi.fn();
// ... etc

vi.mock("@tauri-apps/plugin-dialog", () => ({ save: saveMock, message: messageMock, open: vi.fn() }));
vi.mock("@tauri-apps/plugin-fs",     () => ({ writeTextFile: writeTextFileMock, readTextFile: readTextFileMock, mkdir: mkdirMock, exists: vi.fn().mockResolvedValue(true) }));
vi.mock("@tauri-apps/api/path",      () => ({ dirname: dirnameMock, join: joinMock, appDataDir: appDataDirMock }));

import useStore, { computeSaveAsDefaultFilename, ... } from "../useStore";
```

`vi.mock` calls are hoisted to the top of the module by vitest's transformer, so the dynamic `await import("@tauri-apps/plugin-dialog")` inside `saveProjectAs` resolves to the mock. This matches the reference shape in `gui/src/lib/__tests__/projectIO.scp.test.ts`.

`@tauri-apps/api/path` is also mocked because `saveProjectAs` invokes `relativizePowerShapePaths` (Phase 62-04 D-24 absolute→relative conversion for `file_loaded` PowerShapes) which calls `dirname`. The mock returns `"/tmp"` so the conversion does not throw inside the test.

The `dirname`/`appDataDir` mocks are also exercised by `addToRecent` / `saveRecentFiles` (the second `writeTextFile` call observed in the "successful save" test — `recent.json` write). The test uses `mock.calls.find(call => call[0] === "/tmp/myproj.scp")` to disambiguate from the `recent.json` write rather than asserting `toHaveBeenCalledTimes(1)`.

## Deviations from plan

### Rule 3 — Auto-fix blocking issue: validateAndGate stub

**Found during:** integration test setup (first run of GREEN phase).

**Plan said:** `<vitest_mock_pattern>` preferred approach (a) — "ensure the test's reset state passes validation (no nodes / no edges / nothing to validate — the empty-project state validates clean)".

**Reality:** `validateTopology(nodes, edges, bcs, getComponent)` rejects an empty graph because:
- VALD-02: `bcs.length === 0` → systemError "No pressure boundary condition"
- VALD-03: no `Pump` or `Gravity` node → systemError "No driving element"

An empty canvas therefore returns `valid: false`, causing `saveProjectAs` to short-circuit before the dialog opens. `saveMock` was never called → all 3 integration tests failed.

**Fix:** Used the plan's documented fallback approach (b): stub `validateAndGate` inside `resetStore` to return `{ valid: true, nodeErrors: [], systemErrors: [] }`. This isolates the test to the dialog-arg plumbing (the SUT) and avoids fabricating a 4-node graph with a Pump and a BC just to satisfy validation. Helper unit tests are unaffected — they never touch the store.

**Files modified:** `gui/src/store/__tests__/saveProjectAs.test.ts` (one extra field in the `resetStore` setState call).

**Commit:** `6c886d2` (folded into the GREEN commit since the failing-state and the fix are part of the same TDD GREEN cycle).

### Rule 1 — Bug-style fix: writeTextFile call-count assertion

**Found during:** integration test "successful save".

**Issue:** Test asserted `expect(writeTextFileMock).toHaveBeenCalledTimes(1)`, but `saveProjectAs` triggers `writeTextFile` twice — once for the `.scp` file itself and once via `saveRecentFiles` for `recent.json` (both go through the same mocked `@tauri-apps/plugin-fs.writeTextFile`).

**Fix:** Replaced the count-based assertion with a `mock.calls.find(call => call[0] === "/tmp/myproj.scp")` lookup. Still verifies the .scp write happened with the right path and JSON payload, and is robust to the parallel `recent.json` write.

**Files modified:** `gui/src/store/__tests__/saveProjectAs.test.ts`.

**Commit:** `6c886d2` (folded into the GREEN commit).

## Verification

| Check                                                                | Result                          |
| -------------------------------------------------------------------- | ------------------------------- |
| `cd gui && npx vitest run src/store/__tests__/saveProjectAs.test.ts` | 15/15 passed                    |
| `cd gui && npx vitest run src/store/__tests__/`                      | 122/122 passed across 6 files   |
| `cd gui && npx vitest run src/lib/__tests__/projectIO.scp.test.ts`   | 25/25 passed (regression clean) |
| `cd gui && npx tsc --noEmit` error count                             | 8 (baseline 8 — unchanged)      |
| `grep -cE "export function computeSaveAsDefaultFilename" useStore.ts`| 1                               |
| `grep -cE "computeSaveAsDefaultFilename\(" useStore.ts`              | 2 (definition + call site)      |
| `grep -cE 'defaultPath: \`project\.' useStore.ts`                    | 0 (hardcode removed)            |
| `grep -cE "FALLBACK_SAVE_AS_FILENAME" useStore.ts`                   | 3                               |

## TDD Gate Compliance

| Gate     | Commit    | Notes                                                         |
| -------- | --------- | ------------------------------------------------------------- |
| RED      | `b523149` | New test file added, 14/15 fail (helper undefined)            |
| GREEN    | `6c886d2` | Helper implemented + saveProjectAs wired; 15/15 pass          |
| REFACTOR | — (skipped) | Implementation is already minimal; no cleanup needed         |

## Commits

| Hash      | Type   | Subject                                                                          |
| --------- | ------ | -------------------------------------------------------------------------------- |
| `b523149` | test   | failing tests for computeSaveAsDefaultFilename + saveProjectAs defaultPath (RED) |
| `6c886d2` | feat   | pipe modelOptions.name into saveProjectAs defaultPath (GREEN)                    |

## Manual human-verify (deferred)

Per plan, the manual re-run of VERIFICATION Step 15 (full Tauri dev build → enter a name in Model Options → File → Save As → confirm the OS picker pre-fills `<name>.scp`) is deferred to the post-gap-closure consolidated checkpoint plan, not run here.

## Self-Check: PASSED

- `gui/src/store/useStore.ts` modified — FOUND
- `gui/src/store/__tests__/saveProjectAs.test.ts` created — FOUND
- Commit `b523149` (RED) — FOUND in git log
- Commit `6c886d2` (GREEN) — FOUND in git log

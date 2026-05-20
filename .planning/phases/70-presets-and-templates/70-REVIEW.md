---
phase: 70-presets-and-templates
reviewed: 2026-05-20T23:55:00Z
depth: standard
files_reviewed: 17
files_reviewed_list:
  - gui/src-tauri/Cargo.toml
  - gui/src-tauri/capabilities/default.json
  - gui/src/App.tsx
  - gui/src/components/CanvasPanel.tsx
  - gui/src/components/FileMenu.tsx
  - gui/src/components/PresetRow.tsx
  - gui/src/components/PresetsPanel.tsx
  - gui/src/components/SavePresetModal.tsx
  - gui/src/components/StreamNode.tsx
  - gui/src/components/canvasMenus/NodeContextMenu.tsx
  - gui/src/components/ui/radio-group.tsx
  - gui/src/components/ui/textarea.tsx
  - gui/src/lib/__tests__/presetIO.test.ts
  - gui/src/lib/presetIO.ts
  - gui/src/lib/projectIO.ts
  - gui/src/store/__tests__/presetActions.test.ts
  - gui/src/store/useStore.ts
findings:
  critical: 3
  warning: 11
  info: 4
  total: 18
status: issues_found
---

# Phase 70: Code Review Report

**Reviewed:** 2026-05-20T23:55:00Z
**Depth:** standard
**Files Reviewed:** 17
**Status:** issues_found

## Summary

Phase 70 implements the presets & templates feature: a `.scpr` v1.0 format
(separate from `.scp` projects), seven Zustand store actions, a two-section
left-panel tab, a SavePresetModal with auto-extend-by-1-BC-hop, a per-row
context menu / inline rename / drag source, and wiring through FileMenu,
NodeContextMenu, CanvasPanel drop handler, and a Ctrl+4 accelerator.

Core serialization (`presetIO.ts`) is clean, well-tested, and honors the
project's "no back-compat" stance with strict format_version + kind guards.
The auto-extend + edge-partition algorithm is correct (snapshot of initial
selection prevents recursive hops; one unit test verifies this explicitly).

The findings below cluster around three areas:

1. **FS capabilities mismatch for project-store watcher (Critical).** The
   panel watches `<projectDir>/presets/` for any open project, but the only
   FS scopes granted are `$HOME`, `$APPDATA`, and `$APPCONFIG`. Projects
   saved outside `$HOME` (e.g. `/tmp/`, `/mnt/`, `/var/`) will fail at
   runtime when `watch()` or `mkdir()` is invoked.
2. **Effect re-bind UX during project switch (Warning).** `loading` is
   never reset to `true` on project change, so the panel keeps showing
   the prior project's presets without a skeleton until the rebind
   completes. Also a small race where `setProjectPresets([])` runs even
   after `cancelled=true`.
3. **A scattering of code-quality issues**: redundant capabilities, mixed
   path separators, swallowed errors, dead duplicate reads of
   `state.resources`, and a couple of UX rough edges (no error toast on
   delete failure, stale `name` field on Discard, etc.).

No security vulnerabilities, hardcoded secrets, or injection vectors found.
The dynamic `import()` paths are all static strings.

## Critical Issues

### CR-01: Project-store preset watcher unreachable for projects outside `$HOME`

**File:** `gui/src-tauri/capabilities/default.json:6-28`
**Issue:** `PresetsPanel.useEffect` calls `mkdir(<projectDir>/presets)` and
`watch(<projectDir>/presets)` whenever a project is open. The Tauri FS
permissions granted are `fs:scope-home-recursive`,
`fs:scope-appdata-recursive`, `fs:scope-appconfig-recursive`, plus explicit
allow-lists for `$APPCONFIG/presets/**` and `$APPDATA/STREAM-Composer/autorecover/**`.
There is no scope covering arbitrary filesystem paths. A user who saves
their project under `/tmp/foo/project.scp`, `/mnt/...`, `/var/...`, or
`C:\ProgramData\...` (anywhere outside `$HOME`/`$APPDATA`/`$APPCONFIG`) will
trigger a `forbidden path` runtime error from the FS plugin the moment they
switch to the Presets tab. The errors today are swallowed by the
`.catch(() => {})` on `mkdir` and the outer `try` in `refreshPresetsDir`,
so the user sees a silently-empty Project section with no feedback.

Note: `projectIO.saveProject` already works for arbitrary paths because the
save dialog returns a path the FS plugin grants ambient access to via the
dialog handle — but watch / readDir / mkdir are not coupled to a dialog
handle and require explicit scope.

**Fix:** Either (a) add a permissive runtime scope for project directories
(documented Tauri pattern: prompt for and store the project parent dir as
a runtime-allowed path via the `fs:scope` permission with `requireLiteralLeadingDot=false`),
or (b) explicitly accept that project presets only work in standard
locations and surface a clear error to the user when the watch/mkdir fails
instead of swallowing it:
```ts
// PresetsPanel.tsx setup()
const projDir = await join(currentProjectDir, "presets");
try {
  await mkdir(projDir, { recursive: true });
  await refreshPresetsDir("project", projDir);
  unwatchers.push(await watch(projDir, /* ... */));
} catch (err) {
  // Don't swallow — surface to user
  console.error("Project preset directory unavailable:", err);
  useStore.getState().setProjectPresets([]);
  // TODO: toast/banner: "Project presets unavailable: directory not in allowed FS scope"
}
```

### CR-02: `PresetsPanel` cleanup races with `setProjectPresets([])` and never resets `loading`

**File:** `gui/src/components/PresetsPanel.tsx:91-97`
**Issue:** Two distinct defects in the watcher effect:

1. **Race on "no project" branch.** When `currentProjectDir === null`, the
   code calls `useStore.getState().setProjectPresets([])` *unconditionally*
   after the awaits — there is no `if (cancelled) return;` guard between
   the library-store await chain and this clear. If the user closes a
   project (project→null transition), the effect for the prior project is
   running; cleanup sets `cancelled=true`, then the new no-project effect
   runs and calls `setProjectPresets([])`. Conversely, if a fast switch
   happens (project A → project B), the in-flight effect for A may complete
   `await mkdir/watch` *after* the cleanup runs, then fall through and
   `setLoading(false)` — never clearing presets because `currentProjectDir`
   was non-null at effect-start time.

2. **`loading` never resets on rebind.** `useState(true)` initializes `loading`
   to `true` on the first mount only. On project switch, the effect re-runs
   but never calls `setLoading(true)` to reset the skeleton state. Users
   see the prior project's preset list during the switch instead of a
   loading skeleton.

**Fix:**
```ts
useEffect(() => {
  let cancelled = false;
  const unwatchers: UnwatchFn[] = [];
  setLoading(true); // reset on every rebind so the skeleton shows

  async function setup() {
    // ... existing logic ...
    if (currentProjectDir) {
      // ... existing path ...
    } else {
      if (cancelled) return; // guard the no-project clear
      useStore.getState().setProjectPresets([]);
    }
    if (cancelled) return;
    setLoading(false);
  }
  // ... existing return ...
}, [currentProjectDir]);
```

### CR-03: Concurrent dynamic-import + `onClose()` ordering in `NodeContextMenu.handleSaveSelectionAsPreset`

**File:** `gui/src/components/canvasMenus/NodeContextMenu.tsx:28-44`
**Issue:** The handler reads selection, then fires `import("@/lib/presetIO").then(...)`
which schedules the auto-extend + amber-flag paint + `dispatchEvent` on the
microtask queue. Then `onClose()` runs *synchronously* on the same tick.
Consequence: the context-menu closes first, then the modal opens.

That ordering is benign on its own, but it has a real consequence: between
`onClose()` and the `then` callback, the user may have right-clicked
elsewhere, started a new selection drag, or pressed Esc — any of which can
change `useStore.getState().nodes` between the snapshot read at line 30
and the `setState` at lines 35-39. The paint may then mark nodes that are
no longer in the auto-extended set, leaving stale `autoExtended: true`
flags on the canvas until the modal opens and `SavePresetModal`'s own
cleanup function eventually clears them.

Compare `FileMenu.handleSaveSelectionAsPreset` (lines 71-86) which has the
same dynamic-import pattern but no `onClose()` competing with it — the
Menubar item closes the menu via Radix internals after the synchronous
handler returns, which is still microtask-ordered before the dynamic
import resolves.

**Fix:** Either await the dynamic import before closing the menu, or use a
static top-of-file import (the `autoExtendSelection` symbol is already
imported as `SavePresetModal`'s top-level dependency, so the static import
adds zero bytes):
```ts
import { autoExtendSelection } from "@/lib/presetIO";
// ...
function handleSaveSelectionAsPreset() {
  const { nodes, edges } = useStore.getState();
  const selectedIds = new Set(nodes.filter((n) => n.selected).map((n) => n.id));
  const { extendedIds } = autoExtendSelection(selectedIds, nodes, edges);
  const extras = new Set([...extendedIds].filter((id) => !selectedIds.has(id)));
  if (extras.size > 0) {
    useStore.setState((state) => ({
      nodes: state.nodes.map((n) =>
        extras.has(n.id) ? { ...n, data: { ...n.data, autoExtended: true } } : n,
      ),
    }));
  }
  window.dispatchEvent(new CustomEvent("stream:open-save-preset"));
  onClose();
}
```
(Same fix applies to `FileMenu.handleSaveSelectionAsPreset` — eliminate the
dynamic import there too for consistency.)

## Warnings

### WR-01: `refreshPresetsDir` silently swallows non-ENOENT errors

**File:** `gui/src/store/useStore.ts:2784-2805`
**Issue:** The outer `try { ... } catch { /* silent no-op */ }` blanket-swallows
`readDir` errors. The comment claims it tolerates "directory may not exist
yet (first run)", but it equally swallows permission errors, IO errors,
and the CR-01 scope-denied case. Users see an empty preset list with no
indication anything went wrong.

**Fix:** Narrow the catch to ENOENT-equivalent or surface the error:
```ts
} catch (err) {
  // Only "directory does not exist" is expected; everything else logs.
  const msg = err instanceof Error ? err.message : String(err);
  if (!/no such file|not found|ENOENT/i.test(msg)) {
    console.error("[refreshPresetsDir] readDir failed for", dir, err);
  }
}
```

### WR-02: `mkdir(...).catch(() => {})` hides real failures

**File:** `gui/src/components/PresetsPanel.tsx:51, 73` and `gui/src/store/useStore.ts:2921`
**Issue:** Three sites swallow `mkdir` errors with `.catch(() => {})`. The
inline comment "Pitfall 8: ensure the directory exists before watching"
implies these are defensive idempotent creates, but disk-full, permission-denied,
and scope-denied (CR-01) errors all vanish too. Same pattern as WR-01;
combined with the silent watcher path, a Project section that "just stays
empty" is now the failure mode for several distinct errors.

**Fix:** Log unexpected errors; only swallow EEXIST-equivalent:
```ts
await mkdir(libDir, { recursive: true }).catch((err) => {
  const msg = err instanceof Error ? err.message : String(err);
  if (!/already exists|EEXIST/i.test(msg)) {
    console.error("[PresetsPanel] mkdir failed:", err);
  }
});
```

### WR-03: Hardcoded `/` separator in path concatenation on Windows

**File:** `gui/src/store/useStore.ts:2790, 2795, 2933, 3104, 3158`
**Issue:** Several spots concatenate paths with a literal `"/"`:
- `dir + "/" + f.name` (refreshPresetsDir)
- `dir + "/" + name + ".scpr"` (saveSelectionAsPreset)
- `dir + "/" + newName + ".scpr"` (renamePreset)

Elsewhere in the same file, paths are joined via `await join(...)` from
`@tauri-apps/api/path`, which handles platform separators. On Windows the
Tauri FS plugin tolerates forward slashes today, but the inconsistency is
brittle — and a path stored in `PresetIndexEntry.filePath` of the form
`C:\Users\foo\AppData\.../STREAM-Composer\presets/my_preset.scpr` may not
match a watcher event that reports the path with all backslashes,
breaking the "refresh on rename" round-trip.

**Fix:** Use `join` consistently:
```ts
const filePath = await join(dir, name + ".scpr");
```

### WR-04: Capability list double-grants `$APPCONFIG/presets/**`

**File:** `gui/src-tauri/capabilities/default.json:22-28`
**Issue:** Line 22 grants `fs:scope-appconfig-recursive` (all of
`$APPCONFIG`), and lines 23-28 also grant an explicit
`{"identifier": "fs:scope", "allow": [{ "path": "$APPCONFIG/presets/**" }]}`.
The second entry is fully subsumed by the first. Either remove the
explicit `$APPCONFIG/presets/**` scope (cleaner, since `fs:scope-appconfig-recursive`
covers it), or tighten the recursive grant to just `$APPCONFIG/presets/**`
+ `$APPCONFIG/STREAM-Composer/**` (least privilege — recommended for a
desktop app that doesn't need access to every appconfig file on the
system).

**Fix:** Drop the redundant block:
```json
{
  "identifier": "fs:scope",
  "allow": [
    { "path": "$APPCONFIG/STREAM-Composer/**" }
  ]
}
```
and remove `fs:scope-appconfig-recursive` and the explicit `$APPCONFIG/presets/**`
entry. (Note: this requires renaming the library directory to live under
`$APPCONFIG/STREAM-Composer/presets/`, not `$APPCONFIG/presets/`, to avoid
collisions with other apps. Worth doing before public release.)

### WR-05: `saveSelectionAsPreset` overwrites an existing file with no collision check

**File:** `gui/src/store/useStore.ts:2924-2934`
**Issue:** `writeTextFile(filePath, json)` silently overwrites an existing
`.scpr` file. The UI (`SavePresetModal`) does check `existingNames` and
disables Save on collision, but `renamePreset` (line 3107) DOES guard
collision before writing while `saveSelectionAsPreset` does not. The
asymmetry means any caller bypassing the modal — including future
keyboard-shortcut saves, scripted automation, or even a Save then Discard
sequence where the in-memory `libraryPresets` is stale due to the watcher
debounce — can silently destroy a user's preset.

The `CLAUDE.md` "trust the caller" guidance applies to caller-supplied
*data*, not to file-overwriting side-effects. Per the heavy-dev policy,
losing work to a missed UI gate is the kind of thing the no-back-compat
stance was about avoiding.

**Fix:** Mirror `renamePreset`'s collision check:
```ts
// Before writeTextFile:
try {
  await readTextFile(filePath);
  throw new Error("A preset named '" + name + "' already exists in " + targetStore);
} catch (err) {
  if (err instanceof Error && err.message.startsWith("A preset named")) throw err;
  // else: file doesn't exist, proceed
}
await writeTextFile(filePath, json);
```

### WR-06: `loadPresetAtPosition` doesn't validate componentIds against the registry

**File:** `gui/src/store/useStore.ts:2946-3070`
**Issue:** The function blindly adds every node from `preset.components`
to the canvas without checking that `(node.data as StreamNodeData).componentId`
is registered. If a user loads a `.scpr` saved by a future version
referencing a component that doesn't exist in the current build, those
nodes are added with `componentId: <unknown>` and `StreamNode.tsx:362`
returns `null` — the nodes are silently invisible but counted as selected,
take up undo slots, and break edge endpoints.

While the "no back-compat during heavy dev" policy means old files can
break, *silently* breaking is worse than failing loudly. A simple
fail-loud here gives users useful feedback.

**Fix:** Filter or fail loudly on unknown componentIds:
```ts
const unknownIds = preset.components
  .map((n) => (n.data as StreamNodeData).componentId)
  .filter((id) => !getComponent(id));
if (unknownIds.length > 0) {
  throw new Error(
    "Preset references unknown components: " + unknownIds.join(", "),
  );
}
```

### WR-07: `PresetRow.handleConfirmedDelete` swallows errors silently

**File:** `gui/src/components/PresetRow.tsx:132-135`
**Issue:** `await useStore.getState().deletePreset(entry.filePath)` is
not wrapped in try/catch. If `deletePreset` throws (FS permission denied,
file in use on Windows, etc.), the AlertDialog closes via the unconditional
`setConfirmOpen(false)` — wait, actually that line runs *after* the await,
so if the await throws, `setConfirmOpen(false)` never runs and the modal
stays open with no error feedback. Either path is bad: silent dismissal
of a real error, or a stuck modal.

**Fix:**
```ts
async function handleConfirmedDelete() {
  try {
    await useStore.getState().deletePreset(entry.filePath);
  } catch (err) {
    console.error("Delete preset failed:", err);
    // TODO: surface to user via toast
  } finally {
    setConfirmOpen(false);
  }
}
```

### WR-08: `SavePresetModal` retains stale name/description on Discard

**File:** `gui/src/components/SavePresetModal.tsx:152-169`
**Issue:** Field state (`name`, `description`, `store`) is only reset in
the `handleSave` success path. If the user types a name, picks Discard
(or ESC, or click-outside), and reopens the modal, the previous name is
still in the input. Combined with the live collision check, this means a
user who saved a preset, then opened "Save selection as preset…" again
on a different selection, sees their last-used name pre-filled and
flagged as a collision — confusing UX.

**Fix:** Reset on every close, not just successful save:
```ts
useEffect(() => {
  if (open) return;
  // Modal just closed (any path) — reset for next open.
  setName("");
  setDescription("");
  setStore("library");
  setSaving(false);
}, [open]);
```

### WR-09: `loadPresetAtPosition` reads `state.resources` twice with no intervening mutation

**File:** `gui/src/store/useStore.ts:2957, 3055`
**Issue:** `const currentResources = get().resources;` at line 2957 and
`const currentResState = get().resources;` at line 3055. No `set()` runs
between them. The second read is dead — `currentResources` and
`currentResState` are guaranteed identical. Minor but easy to fix; signals
that the author wasn't sure whether the resource reads needed re-syncing.

**Fix:** Reuse the first read:
```ts
// Remove line 3055; in the set() body, replace currentResState with currentResources.
```

### WR-10: Mixed concerns in capability scope name

**File:** `gui/src-tauri/capabilities/default.json:30-34`
**Issue:** The autorecover scope uses `$APPDATA/STREAM-Composer/autorecover/**`
(with brand path segment), while the presets scope uses `$APPCONFIG/presets/**`
(without brand path segment). When STREAM-Composer is published, presets
saved by other apps to `$APPCONFIG/presets/` could collide. This is the
same point raised in WR-04 fix — flagged separately because it's an
identifier-naming convention drift that's easy to miss.

**Fix:** Rename library preset directory to `$APPCONFIG/STREAM-Composer/presets/`
and update both the capability path and `useStore.saveSelectionAsPreset`
+ `PresetsPanel.useEffect` to compose `appConfigDir + "STREAM-Composer/presets"`.

### WR-11: `commitRename` re-reads store on every keystroke

**File:** `gui/src/components/PresetRow.tsx:78-94, 169-172`
**Issue:** The `onChange` handler calls `validateNewName` which calls
`useStore.getState()` and runs `pool.some(...)` on every keystroke. For a
library with hundreds of presets this is a few hundred string comparisons
per keystroke — not catastrophic, but unnecessary, and the result is
already memoizable. Also, the validation set is recomputed in `SavePresetModal`
via `useMemo` — same data, different implementation pattern. Quality
issue, not a bug.

**Fix:** Compute the collision set once when `renaming` flips to true:
```ts
const collisionSet = useMemo(() => {
  if (!renaming) return new Set<string>();
  const state = useStore.getState();
  const pool = entry.store === "project" ? state.projectPresets : state.libraryPresets;
  return new Set(pool.filter((e) => e.filePath !== entry.filePath).map((e) => e.name));
}, [renaming, entry.store, entry.filePath]);
```

## Info

### IN-01: Inconsistent dynamic-import strategy across preset triggers

**File:** `gui/src/components/FileMenu.tsx:74`, `gui/src/components/canvasMenus/NodeContextMenu.tsx:31`
**Issue:** Both files dynamically import `@/lib/presetIO` via `.then()` to
schedule the auto-extend paint. The module is already eagerly loaded by
`SavePresetModal.tsx` (top-of-file `import`), so the dynamic import buys
nothing — `presetIO` is in the main bundle either way. Switch to static
imports for clarity (see CR-03 fix).

### IN-02: Unused `_allNodes` parameter in `autoExtendSelection`

**File:** `gui/src/lib/presetIO.ts:268-272`
**Issue:** The function signature accepts `_allNodes: Node[]` but only
uses `selectedNodeIds` and `allEdges`. The `_` prefix and comment signal
deliberate API-stability padding, but the underscore-prefix lint
suppression carries no information beyond "trust me, I meant this." If
the future use case is concrete, document it; otherwise drop the
parameter.

**Fix:** Either remove the parameter or document the planned use case
in the JSDoc explicitly:
```ts
* @param _allNodes — Reserved for future use; currently unused. (Will be
*                    needed when D-13's one-hop invariant is lifted to
*                    component-type-aware multi-hop in Phase XX.)
```

### IN-03: `data: rest as typeof n.data` cast loses `StreamNodeData` precision

**File:** `gui/src/components/SavePresetModal.tsx:110-117`
**Issue:** The cleanup that strips `autoExtended` builds `rest` as
`Record<string, unknown>` then casts to `typeof n.data`. This bypasses
TypeScript's structural check — `rest` could be missing required
`StreamNodeData` fields (`componentId`, `instanceName`, `parameters`)
and the cast would silently accept it. In practice it can't happen because
the spread carries those fields, but the cast hides the safety.

**Fix:** Type the destructure more precisely:
```ts
const { autoExtended: _x, ...rest } = n.data as StreamNodeData;
return { ...n, data: rest };
```
(`StreamNodeData.autoExtended` is `?: boolean`, so destructuring it out
yields the rest typed as `Omit<StreamNodeData, 'autoExtended'>` which is
structurally compatible with `StreamNodeData`.)

### IN-04: Phase-70 selection-count UI rule is counter-intuitive on cross-selection right-click

**File:** `gui/src/components/canvasMenus/NodeContextMenu.tsx:24, 85`
**Issue:** "Save selection as preset…" is shown when `selectionCount >= 2`,
based on what nodes are currently selected — but right-clicking a node
does NOT select it (see `useRightClickContextMenu.ts:143-155`). Consequence:
if the user selects nodes A and B, then right-clicks an unselected node C,
the menu shows "Save selection as preset…" and the saved preset will be
{A, B} — not including C. The expected behavior under "right-click is also
a selection gesture" (which many tools follow) is unclear from this code.

This matches the UI-SPEC (D-15.1) per the comment, but the documented
behavior is unintuitive and a likely source of UAT complaints. Worth
double-checking with the design owner. Not a bug — flagging as info.

---

## Notes (out of scope)

- Vendor files (`radio-group.tsx`, `textarea.tsx`) are upstream shadcn
  registry code and contain no defects worth flagging.
- `StreamNode.tsx` was touched only to add the amber dashed outline at
  lines 409-411 (`nodeData.autoExtended ? "outline outline-2 outline-dashed
  outline-[oklch(0.769_0.188_70.08)] outline-offset-2" : ""`). The new
  outline coexists cleanly with `selected` / `hasAnyError` / `isCodeHovered`
  / `isCodePinned` outline rules and uses an inline OKLCH value rather
  than a token — minor theme-drift concern, but every other outline color
  in this file uses `var(--ring)` or `var(--destructive)`. Worth adding
  `--amber-preset-outline` to the theme tokens in a follow-up.
- The drag-source MIME type `application/stream-preset` and the drop
  handler in `CanvasPanel.tsx:172-194` are correctly paired and
  defensively `try { JSON.parse }`-wrapped.
- `presetIO.test.ts` and `presetActions.test.ts` are thorough — round-trip,
  rejection branches, single-hop invariant, edge partitioning, smart-name
  collision, embedded-resource UUID remap, deselect-prior-on-load, and
  the rename collision branch are all covered.

---

_Reviewed: 2026-05-20T23:55:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

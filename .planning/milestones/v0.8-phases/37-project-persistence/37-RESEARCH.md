# Phase 37: Project Persistence - Research

**Researched:** 2026-04-02
**Domain:** Tauri v2 file I/O, Zustand state serialization, native dialogs
**Confidence:** HIGH

## Summary

Phase 37 adds save/load/resume functionality to the STREAM Composer GUI. The technical domain is well-constrained: all necessary Tauri plugins (`plugin-dialog`, `plugin-fs`) and APIs (`@tauri-apps/api/window`) are already installed and used in the codebase. The core work is (1) serializing/deserializing Zustand store state as `.streamgui` JSON files, (2) adding a File dropdown menu to the toolbar, (3) tracking dirty state and guarding against data loss, and (4) persisting a recent-projects list in Tauri's `appDataDir`.

The `@tauri-apps/plugin-dialog` v2.4+ `message()` function supports 3-button dialogs with `{ yes, no, cancel }` custom button labels, which maps directly to the "Save / Don't Save / Cancel" unsaved-changes guard. The `@tauri-apps/api/window` provides `getCurrentWindow().setTitle()` and `onCloseRequested()` with `event.preventDefault()` for the window-close guard. No new Tauri plugins are needed.

**Primary recommendation:** Implement as two plans: Plan 01 adds the store state (isDirty, currentFilePath, recentFiles) and all file I/O logic (save, load, new, recent.json); Plan 02 adds the UI surfaces (FileMenu dropdown, WelcomeOverlay, keyboard shortcuts, window title sync, close guard).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Add a `File` dropdown button at the left of the Toolbar with four items: New / Open... (Ctrl+O) / Save (Ctrl+S) / Save As... Keyboard shortcuts also work independently. The existing Code and Export buttons stay where they are.
- **D-02:** Save vs Save As semantics: Save overwrites the current file without a dialog (once a path is established). Save As always opens the native file save dialog and can update the current file path. First Save on a new/unsaved project behaves like Save As (no path yet -> prompt).
- **D-03:** The `.streamgui` file is a JSON object containing: `{ version, nodes, edges, bcs }`. Transient UI state (`selectedNodeId`, `bottomPanelOpen`) is NOT serialized -- those reset to defaults on load. A `version` field is included for forward compatibility.
- **D-04:** `nodes` serializes the full ReactFlow node array (id, type, position, data). `edges` serializes the full ReactFlow edge array (id, source, target, sourceHandle, targetHandle). `bcs` serializes the BCEntry array as-is.
- **D-05:** Recent projects list (last 5 files) is stored in a `recent.json` file in Tauri's `app_data_dir` via `@tauri-apps/plugin-fs`. Format: `{ "files": ["abs/path1.streamgui", ...] }`. No new plugin required -- plugin-fs is already installed.
- **D-06:** The recent projects list is shown as a welcome overlay centered on the canvas when the canvas is empty (no nodes and no edges). The overlay shows the app name, a list of up to 5 recent file names (clickable to open), and an "Open file..." button. It disappears as soon as any node is added to the canvas.
- **D-07:** Recent list is updated on every successful Save and Open. The opened/saved file moves to the top; the list is deduplicated by path; truncated to 5 entries.
- **D-08:** Dirty state is tracked as a boolean `isDirty` in the Zustand store. Set to `true` on any store mutation that changes canvas content (node/edge/BC/param changes). Set to `false` after a successful Save and after loading a project.
- **D-09:** Window title indicates dirty state: `STREAM Composer*` when dirty, `STREAM Composer` (or `filename.streamgui - STREAM Composer`) when clean. Updated via Tauri `getCurrentWindow().setTitle()`.
- **D-10:** Window-close guard uses Tauri's `onCloseRequested` listener. When dirty, shows a native-style confirmation dialog (via `@tauri-apps/plugin-dialog`) with three choices: "Save" / "Don't Save" / "Cancel". If Save is chosen, the app saves then closes; Don't Save closes without saving; Cancel aborts the close.
- **D-11:** New and Open actions also check `isDirty` before proceeding. If dirty, show the same dialog (Save / Don't Save / Cancel). Cancel returns to the current state.

### Claude's Discretion
- Exact `recent.json` read/write error handling (missing file -> treat as empty list; write failure -> silent, don't block user)
- Whether the welcome overlay shows when `recent.json` has no entries yet (show overlay with just "Open file..." button, no list)
- `instanceCounters` reset strategy on New (reset to empty object for clean naming)
- Keyboard shortcut implementation approach (keydown listener in App.tsx vs. useEffect hook)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PERS-01 | User can save the full canvas state as a `.streamgui` JSON file via Ctrl+S / File->Save | D-02/D-03/D-04: JSON schema with version+nodes+edges+bcs; `writeTextFile` + `save()` dialog APIs verified available |
| PERS-02 | User can open an existing `.streamgui` file to fully restore the canvas via Ctrl+O / File->Open | `open()` dialog + `readTextFile` APIs verified; `fs:allow-read-text-file` permission needed |
| PERS-03 | App shows "unsaved changes" confirmation dialog before closing/new/open when dirty | `message()` with `{ yes, no, cancel }` custom buttons returns `MessageDialogResult` string; `onCloseRequested` with `preventDefault()` verified |
| PERS-04 | App shows "Recent Projects" list on startup/empty canvas (last 5 files) | `appDataDir()` from `@tauri-apps/api/path` + `readTextFile`/`writeTextFile` with `BaseDirectory.AppData`; `fs:default` already grants AppData read access |
</phase_requirements>

## Standard Stack

### Core (already installed)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `@tauri-apps/plugin-dialog` | ^2.6.0 | File open/save dialogs, 3-button confirmation dialog | Already used in Toolbar for export |
| `@tauri-apps/plugin-fs` | ^2.4.5 | `readTextFile`, `writeTextFile` for .streamgui and recent.json | Already used in Toolbar for export |
| `@tauri-apps/api` | ^2 | `getCurrentWindow()` for setTitle, onCloseRequested; `appDataDir()` from path module | Already installed, window API is the standard Tauri v2 approach |
| `zustand` | ^5.0.12 | State management: isDirty, currentFilePath, recentFiles | Already the project store |
| `zundo` | ^2.3.0 | Undo/redo temporal middleware | Already wrapping the store |

### Supporting (need to install)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| shadcn `dropdown-menu` | N/A (shadcn component) | File menu dropdown UI | `npx shadcn@latest add dropdown-menu` |

### Alternatives Considered
None -- all decisions are locked. The stack is fully determined by existing project dependencies.

**Installation:**
```bash
cd gui && npx shadcn@latest add dropdown-menu
```

No npm packages to install -- all Tauri plugins are already present.

## Architecture Patterns

### Recommended Project Structure
```
gui/src/
  store/useStore.ts           # Add isDirty, currentFilePath, recentFiles + file I/O actions
  lib/projectIO.ts            # NEW: serialize/deserialize/save/load/recent.json helpers (pure logic)
  components/Toolbar.tsx      # Add FileMenu dropdown at left
  components/FileMenu.tsx     # NEW: DropdownMenu wrapper (File > New/Open/Save/Save As)
  components/WelcomeOverlay.tsx  # NEW: centered overlay on empty canvas
  components/CanvasPanel.tsx  # Add WelcomeOverlay conditional render
  App.tsx                     # Add onCloseRequested + keyboard shortcuts
```

### Pattern 1: Separate File I/O Logic from Store
**What:** Extract all serialization, deserialization, and file system operations into `lib/projectIO.ts` as pure async functions. Store actions call these functions.
**When to use:** Always -- keeps the store thin and the I/O logic testable without React.
**Example:**
```typescript
// lib/projectIO.ts
import { readTextFile, writeTextFile } from "@tauri-apps/plugin-fs";
import { open, save, message } from "@tauri-apps/plugin-dialog";
import { appDataDir } from "@tauri-apps/api/path";
import { join } from "@tauri-apps/api/path";

export interface StreamProject {
  version: 1;
  nodes: unknown[];
  edges: unknown[];
  bcs: unknown[];
}

export function serializeProject(nodes: unknown[], edges: unknown[], bcs: unknown[]): string {
  const project: StreamProject = { version: 1, nodes, edges, bcs };
  return JSON.stringify(project, null, 2);
}

export function deserializeProject(json: string): StreamProject {
  const data = JSON.parse(json);
  if (!data.version || !Array.isArray(data.nodes) || !Array.isArray(data.edges) || !Array.isArray(data.bcs)) {
    throw new Error("Invalid .streamgui file");
  }
  return data as StreamProject;
}
```

### Pattern 2: Dirty State via Zustand Middleware or Manual Flagging
**What:** Set `isDirty = true` inside every mutating action (addNode, removeNode, addEdge, etc.). Set `isDirty = false` after save/load/new.
**When to use:** This is the simplest approach given the store already has explicit actions for every mutation.
**Why not middleware:** A Zustand middleware that auto-sets isDirty on any state change would also trigger on non-content changes (selectNode, toggleBottomPanel). Manual flagging in each content-mutating action is more precise and matches the zundo `partialize` pattern already in use.

### Pattern 3: Window Title Sync via useEffect
**What:** A `useEffect` in `App.tsx` that watches `isDirty` and `currentFilePath` and calls `getCurrentWindow().setTitle()`.
**When to use:** Always -- React effect is the idiomatic way to sync external state with component state.
**Example:**
```typescript
// In App.tsx
useEffect(() => {
  const win = getCurrentWindow();
  const filename = currentFilePath ? currentFilePath.split(/[/\\]/).pop() : null;
  const dirty = isDirty ? "*" : "";
  const title = filename
    ? `${filename}${dirty} - STREAM Composer`
    : `STREAM Composer${dirty}`;
  win.setTitle(title);
}, [isDirty, currentFilePath]);
```

### Pattern 4: 3-Button Dialog via message() with Custom Buttons
**What:** Use `message()` from `@tauri-apps/plugin-dialog` with `buttons: { yes: "Save", no: "Don't Save", cancel: "Cancel" }`. Returns the button key string.
**When to use:** For the unsaved-changes guard (D-10, D-11).
**Example:**
```typescript
// Source: @tauri-apps/plugin-dialog v2.4+ type definitions
import { message } from "@tauri-apps/plugin-dialog";

const result = await message("Your project has unsaved changes that will be lost.", {
  title: "Save changes?",
  kind: "warning",
  buttons: { yes: "Save", no: "Don't Save", cancel: "Cancel" },
});
// result is "Save" | "Don't Save" | "Cancel"
```

### Pattern 5: instanceCounters Reset on New Project
**What:** The module-level `instanceCounters` object must be cleared when creating a new project, so the next component gets `pump_1` not `pump_5`.
**When to use:** When implementing the `newProject` action.
**Approach:** Export a `resetInstanceCounters()` function from useStore.ts, or clear the object in the `newProject` action directly (since it is module-scoped, not in Zustand state).

### Anti-Patterns to Avoid
- **Storing isDirty in zundo partialize:** `isDirty` is metadata, not undoable content. Do NOT include it in the partialize function -- it should be outside the temporal wrapper or excluded.
- **Using `ask()` for unsaved-changes:** `ask()` only supports Yes/No (2 buttons, returns boolean). Use `message()` with custom `{ yes, no, cancel }` buttons for the 3-button pattern.
- **Reading window title to detect dirty state:** The title is a derived view. Always read `isDirty` from the store.
- **Blocking the UI thread on file I/O:** All Tauri file operations are async. Never use synchronous wrappers.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File open/save dialogs | Custom file picker UI | `@tauri-apps/plugin-dialog` `open()` / `save()` | OS-native dialogs handle permissions, file system browsing, recent locations |
| 3-button confirmation dialog | Custom modal with 3 buttons | `@tauri-apps/plugin-dialog` `message()` with `{ yes, no, cancel }` | Native OS dialog, blocks interaction, consistent with platform UX |
| App data directory | Hardcoded path (`~/.config/...`) | `appDataDir()` from `@tauri-apps/api/path` | Cross-platform (Linux XDG, Windows AppData, macOS ~/Library) |
| Dropdown menu | Custom popover with click handling | shadcn `DropdownMenu` (Radix UI) | Keyboard navigation, focus management, accessibility |
| Window close interception | `window.onbeforeunload` | `getCurrentWindow().onCloseRequested()` | Tauri v2 webview does not fire `beforeunload` reliably; `onCloseRequested` is the official API |

**Key insight:** Every I/O primitive (file dialogs, text file read/write, app data path, window management) already exists as a Tauri v2 API or plugin. The phase is purely composition and state management.

## Common Pitfalls

### Pitfall 1: Missing `fs:allow-read-text-file` Permission
**What goes wrong:** `readTextFile()` for user-chosen `.streamgui` files fails silently or throws a permission error at runtime.
**Why it happens:** The current capabilities only have `fs:default` (which covers AppData dirs) + `fs:allow-write-text-file` + `fs:scope-home-recursive`. Reading arbitrary user-selected files requires `fs:allow-read-text-file`.
**How to avoid:** Add `"fs:allow-read-text-file"` to `gui/src-tauri/capabilities/default.json` permissions array.
**Warning signs:** File open works in dev but fails in production builds; error messages about "not allowed" in console.

### Pitfall 2: `message()` Return Value is Button Label, Not Key
**What goes wrong:** Comparing `result === "yes"` when the actual return is `"Save"` (the custom label).
**Why it happens:** When using custom button labels in `message()`, the `MessageDialogResult` is the label string provided, not the key name.
**How to avoid:** Compare against the exact label strings: `result === "Save"`, `result === "Don't Save"`, `result === "Cancel"`.
**Warning signs:** Dialog shows correct buttons but the wrong action fires.

### Pitfall 3: onCloseRequested Handler Must Call preventDefault Synchronously
**What goes wrong:** Window closes before the save dialog can show.
**Why it happens:** The `onCloseRequested` handler receives a `CloseRequestedEvent`. If you do async work (show dialog, save file) without calling `event.preventDefault()` first, the window closes immediately.
**How to avoid:** Always call `event.preventDefault()` at the start of the handler when `isDirty` is true, then show the dialog. If the user chooses "Don't Save" or "Save" (after saving), call `getCurrentWindow().close()` to actually close. If "Cancel", do nothing (window stays open).
**Warning signs:** Window flickers closed then reopens, or closes before dialog appears.

### Pitfall 4: Recent.json File Does Not Exist on First Run
**What goes wrong:** `readTextFile()` throws an error because `recent.json` doesn't exist yet.
**Why it happens:** First time the app runs, no recent.json exists in appDataDir.
**How to avoid:** Wrap `readTextFile` in try/catch; on error, return empty array `[]`. The `appDataDir()` directory itself may also not exist -- use `mkdir` or `exists` check before writing.
**Warning signs:** Console error on first launch, empty recent list even after opening files.

### Pitfall 5: isDirty Triggered by Non-Content Changes
**What goes wrong:** The dirty indicator shows after selecting a node or toggling the bottom panel.
**Why it happens:** If isDirty is set by a middleware watching all state changes rather than content-specific mutations.
**How to avoid:** Only set `isDirty = true` in content-mutating actions: addNode, removeNode, addEdge, removeEdge, updateNodeParams, addBC, removeBC, and onNodesChange/onEdgesChange (for position changes).
**Warning signs:** Asterisk appears in title without making any canvas changes.

### Pitfall 6: instanceCounters Not Reconstructed on Load
**What goes wrong:** After loading a project with `pump_3`, the next pump is named `pump_1` (collision).
**Why it happens:** The module-level `instanceCounters` is not part of Zustand state and doesn't get restored on load.
**How to avoid:** After loading nodes, scan all instance names to reconstruct the max counter per component type. E.g., if nodes contain `pump_1`, `pump_3`, set `instanceCounters["Pump"] = 3`.
**Warning signs:** Duplicate instance names after load + add new component.

### Pitfall 7: appDataDir May Not Exist
**What goes wrong:** `writeTextFile` to `appDataDir/recent.json` fails because the directory does not exist.
**Why it happens:** On first run, Tauri's app data directory may not be created yet.
**How to avoid:** Use `mkdir` from `@tauri-apps/plugin-fs` with `recursive: true` before the first write, or use `BaseDirectory.AppData` option in `writeTextFile` (which auto-resolves the path).
**Warning signs:** Recent files never persist between sessions.

## Code Examples

### Saving a Project
```typescript
// Source: Tauri v2 plugin-dialog + plugin-fs type definitions (verified from node_modules)
import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";

async function saveProject(
  filePath: string | null,
  content: string,
): Promise<string | null> {
  let targetPath = filePath;
  if (!targetPath) {
    targetPath = await save({
      defaultPath: "project.streamgui",
      filters: [{ name: "STREAM Composer Projects", extensions: ["streamgui"] }],
    });
  }
  if (!targetPath) return null; // User cancelled
  await writeTextFile(targetPath, content);
  return targetPath;
}
```

### Opening a Project
```typescript
import { open as openDialog } from "@tauri-apps/plugin-dialog";
import { readTextFile } from "@tauri-apps/plugin-fs";

async function openProject(): Promise<{ path: string; content: string } | null> {
  const filePath = await openDialog({
    filters: [{ name: "STREAM Composer Projects", extensions: ["streamgui"] }],
    multiple: false,
  });
  if (!filePath) return null; // User cancelled
  const content = await readTextFile(filePath as string);
  return { path: filePath as string, content };
}
```

### 3-Button Unsaved Changes Dialog
```typescript
import { message } from "@tauri-apps/plugin-dialog";

type UnsavedAction = "save" | "discard" | "cancel";

async function promptUnsavedChanges(): Promise<UnsavedAction> {
  const result = await message(
    "Your project has unsaved changes that will be lost.",
    {
      title: "Save changes?",
      kind: "warning",
      buttons: { yes: "Save", no: "Don't Save", cancel: "Cancel" },
    },
  );
  if (result === "Save") return "save";
  if (result === "Don't Save") return "discard";
  return "cancel";
}
```

### Window Close Guard
```typescript
import { getCurrentWindow } from "@tauri-apps/api/window";

// In App.tsx useEffect
useEffect(() => {
  let unlisten: (() => void) | undefined;
  getCurrentWindow().onCloseRequested(async (event) => {
    const isDirty = useStore.getState().isDirty;
    if (!isDirty) return; // Allow close

    event.preventDefault(); // MUST call before async work
    const action = await promptUnsavedChanges();
    if (action === "save") {
      await performSave();
      await getCurrentWindow().close();
    } else if (action === "discard") {
      await getCurrentWindow().close();
    }
    // "cancel" -> do nothing, window stays open
  }).then((fn) => { unlisten = fn; });

  return () => { unlisten?.(); };
}, []);
```

### Recent Projects I/O
```typescript
import { readTextFile, writeTextFile, mkdir, exists } from "@tauri-apps/plugin-fs";
import { appDataDir, join } from "@tauri-apps/api/path";

async function getRecentFilePath(): Promise<string> {
  const dir = await appDataDir();
  return await join(dir, "recent.json");
}

async function loadRecentFiles(): Promise<string[]> {
  try {
    const path = await getRecentFilePath();
    const content = await readTextFile(path);
    const data = JSON.parse(content);
    return Array.isArray(data.files) ? data.files : [];
  } catch {
    return []; // File doesn't exist or is malformed
  }
}

async function saveRecentFiles(files: string[]): Promise<void> {
  try {
    const dir = await appDataDir();
    if (!(await exists(dir))) {
      await mkdir(dir, { recursive: true });
    }
    const path = await join(dir, "recent.json");
    await writeTextFile(path, JSON.stringify({ files }, null, 2));
  } catch {
    // Silent failure -- don't block user operations
  }
}

function addToRecent(files: string[], newPath: string): string[] {
  const filtered = files.filter((f) => f !== newPath);
  return [newPath, ...filtered].slice(0, 5);
}
```

## Tauri Permissions Update Required

The current `gui/src-tauri/capabilities/default.json` must be updated:

```json
{
  "permissions": [
    "core:default",
    "opener:default",
    "dialog:default",
    "fs:default",
    "fs:allow-write-text-file",
    "fs:allow-read-text-file",
    "fs:allow-exists",
    "fs:allow-mkdir",
    "fs:scope-home-recursive"
  ]
}
```

Added permissions:
- `fs:allow-read-text-file` -- required for reading `.streamgui` files from user-selected paths
- `fs:allow-exists` -- required for checking if appDataDir exists before writing recent.json
- `fs:allow-mkdir` -- required for creating appDataDir on first run

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | `gui/vitest.config.ts` |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PERS-01 | Serialize project to JSON, save via writeTextFile | unit | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "serialize"` | Wave 0 |
| PERS-02 | Deserialize JSON, restore store state | unit | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "deserialize"` | Wave 0 |
| PERS-03 | isDirty tracking, unsaved dialog logic | unit | `cd gui && npx vitest run src/store/__tests__/useStore.test.ts -t "dirty"` | Extend existing |
| PERS-04 | Recent files list management (add, deduplicate, truncate) | unit | `cd gui && npx vitest run src/lib/__tests__/projectIO.test.ts -t "recent"` | Wave 0 |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/lib/__tests__/projectIO.test.ts` -- covers PERS-01, PERS-02, PERS-04 (serialization, deserialization, recent files logic)
- [ ] Extend `gui/src/store/__tests__/useStore.test.ts` -- covers PERS-03 (isDirty state tracking)
- [ ] Tauri API mocks for `readTextFile`, `writeTextFile`, `appDataDir`, dialog functions (tests run in node environment, not Tauri webview)

**Note:** Component tests for FileMenu and WelcomeOverlay require jsdom environment (`@vitest-environment jsdom` docblock) per project convention. The Tauri plugin imports must be mocked since they use IPC that is unavailable outside the Tauri runtime.

## Sources

### Primary (HIGH confidence)
- `gui/node_modules/@tauri-apps/plugin-dialog/dist-js/index.d.ts` -- verified `message()` supports `{ yes, no, cancel }` custom buttons (v2.4+), returns `MessageDialogResult` string
- `gui/node_modules/@tauri-apps/api/window.d.ts` -- verified `getCurrentWindow().setTitle()`, `onCloseRequested()` with `CloseRequestedEvent.preventDefault()`
- `gui/node_modules/@tauri-apps/plugin-fs/dist-js/index.d.ts` -- verified `readTextFile`, `writeTextFile`, `BaseDirectory.AppData`
- `gui/node_modules/@tauri-apps/api/path.d.ts` -- verified `appDataDir()` function
- `gui/src-tauri/gen/schemas/acl-manifests.json` -- verified `fs:allow-read-text-file`, `fs:allow-exists`, `fs:allow-mkdir` permission identifiers exist
- `gui/src/store/useStore.ts` -- current store shape with temporal middleware, partialize config
- `gui/src/components/Toolbar.tsx` -- current toolbar using plugin-dialog save + plugin-fs writeTextFile
- `gui/src-tauri/capabilities/default.json` -- current permissions (missing read-text-file)

### Secondary (MEDIUM confidence)
- `.planning/phases/37-project-persistence/37-UI-SPEC.md` -- UI design contract with component inventory, interaction contracts, copywriting
- `.planning/phases/37-project-persistence/37-CONTEXT.md` -- locked decisions D-01 through D-11

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all packages already installed, type definitions verified locally
- Architecture: HIGH -- patterns derived from existing codebase conventions and verified Tauri APIs
- Pitfalls: HIGH -- derived from reading actual type signatures and understanding Tauri v2 permission model

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable -- Tauri v2 APIs are released and unlikely to change)

# Phase 37: Project Persistence - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can save, load, and resume their work across sessions without data loss. Delivers: `.streamgui` JSON save/load, File menu (New/Open/Save/Save As), unsaved-changes guard (window close + New + Open), and a recent projects welcome overlay. No visual design pass — that is Phase 38.

</domain>

<decisions>
## Implementation Decisions

### File Menu Surface
- **D-01:** Add a `File ▾` dropdown button at the left of the Toolbar with four items: New / Open... (Ctrl+O) / Save (Ctrl+S) / Save As... Keyboard shortcuts also work independently. The existing Code and Export buttons stay where they are.
- **D-02:** Save vs Save As semantics: Save overwrites the current file without a dialog (once a path is established). Save As always opens the native file save dialog and can update the current file path. First Save on a new/unsaved project behaves like Save As (no path yet → prompt).

### .streamgui Serialization
- **D-03:** The `.streamgui` file is a JSON object containing: `{ version, nodes, edges, bcs }`. Transient UI state (`selectedNodeId`, `bottomPanelOpen`) is NOT serialized — those reset to defaults on load. A `version` field is included for forward compatibility.
- **D-04:** `nodes` serializes the full ReactFlow node array (id, type, position, data). `edges` serializes the full ReactFlow edge array (id, source, target, sourceHandle, targetHandle). `bcs` serializes the BCEntry array as-is.

### Recent Projects
- **D-05:** Recent projects list (last 5 files) is stored in a `recent.json` file in Tauri's `app_data_dir` via `@tauri-apps/plugin-fs`. Format: `{ "files": ["abs/path1.streamgui", ...] }`. No new plugin required — plugin-fs is already installed.
- **D-06:** The recent projects list is shown as a welcome overlay centered on the canvas when the canvas is empty (no nodes and no edges). The overlay shows the app name, a list of up to 5 recent file names (clickable to open), and an "Open file..." button. It disappears as soon as any node is added to the canvas.
- **D-07:** Recent list is updated on every successful Save and Open. The opened/saved file moves to the top; the list is deduplicated by path; truncated to 5 entries.

### Unsaved Changes Guard
- **D-08:** Dirty state is tracked as a boolean `isDirty` in the Zustand store. Set to `true` on any store mutation that changes canvas content (node/edge/BC/param changes). Set to `false` after a successful Save and after loading a project.
- **D-09:** Window title indicates dirty state: `STREAM Composer*` when dirty, `STREAM Composer` (or `filename.streamgui — STREAM Composer`) when clean. Updated via Tauri `getCurrentWindow().setTitle()`.
- **D-10:** Window-close guard uses Tauri's `onCloseRequested` listener. When dirty, shows a native-style confirmation dialog (via `@tauri-apps/plugin-dialog`) with three choices: "Save" / "Don't Save" / "Cancel". If Save is chosen, the app saves then closes; Don't Save closes without saving; Cancel aborts the close.
- **D-11:** New and Open actions also check `isDirty` before proceeding. If dirty, show the same dialog (Save / Don't Save / Cancel). Cancel returns to the current state.

### Claude's Discretion
- Exact `recent.json` read/write error handling (missing file → treat as empty list; write failure → silent, don't block user)
- Whether the welcome overlay shows when `recent.json` has no entries yet (show overlay with just "Open file..." button, no list)
- `instanceCounters` reset strategy on New (reset to empty object for clean naming)
- Keyboard shortcut implementation approach (keydown listener in App.tsx vs. useEffect hook)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"Project Persistence" → PERS-01..PERS-04 — Exact acceptance criteria for this phase

### Roadmap
- `.planning/ROADMAP.md` §"Phase 37: Project Persistence" — Success criteria and depends-on

### Existing store and components
- `gui/src/store/useStore.ts` — Current Zustand store with zundo temporal middleware: `nodes`, `edges`, `bcs`, `selectedNodeId`, `bottomPanelOpen`. Phase 37 adds `isDirty`, `currentFilePath`, `recentFiles`, and actions: `saveProject`, `loadProject`, `newProject`, `setCurrentFilePath`, `addRecentFile`.
- `gui/src/components/Toolbar.tsx` — Current toolbar with Code + Export buttons. Phase 37 adds the File dropdown at the left. Already uses `@tauri-apps/plugin-dialog` and `@tauri-apps/plugin-fs`.
- `gui/src/App.tsx` — Root component. Phase 37 adds `onCloseRequested` handler and keyboard shortcut listeners here.

### Tauri APIs (already installed, no new plugins needed)
- `@tauri-apps/plugin-dialog` — `open()` for file open dialog, `save()` for file save dialog, `ask()` / `confirm()` for confirmation dialogs
- `@tauri-apps/plugin-fs` — `readTextFile()`, `writeTextFile()`, `appDataDir()` for recent.json storage
- `@tauri-apps/api` window API — `getCurrentWindow().setTitle()` for dirty-state indicator, `getCurrentWindow().onCloseRequested()` for close guard

### Prior phase context
- `.planning/phases/36-code-generation/36-CONTEXT.md` — D-01/D-02: bottom panel layout; D-11: Export already uses plugin-dialog save dialog (reuse pattern for Save As)
- `.planning/phases/33-project-scaffold/33-CONTEXT.md` — D-06: Zustand store minimum shape established

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/Toolbar.tsx`: already imports `@tauri-apps/plugin-dialog` (save) and `@tauri-apps/plugin-fs` (writeTextFile) — exact pattern to reuse for Save As and Open
- `gui/src/store/useStore.ts`: zundo temporal store pattern is established; adding `isDirty` and file-path state follows the same shape
- shadcn/ui `DropdownMenu` component: available in `gui/src/components/ui/` — use for the File menu dropdown

### Established Patterns
- All file I/O goes through Tauri plugins (no `window.fetch`, no Node.js fs) — maintain this
- Zustand actions are defined inside the `temporal()` wrapper — new actions follow the same pattern
- `@tauri-apps/plugin-dialog` uses async/await pattern already established in Toolbar

### Integration Points
- `App.tsx`: add `onCloseRequested` listener and global keydown handler (Ctrl+S, Ctrl+O)
- `Toolbar.tsx`: add File dropdown to the left side; keep Code and Export unchanged on the right
- `CanvasPanel.tsx`: add the welcome overlay as a conditionally-rendered absolute-positioned div when `nodes.length === 0 && edges.length === 0`
- `useStore.ts`: add `isDirty`, `currentFilePath: string | null`, `recentFiles: string[]` state fields

</code_context>

<specifics>
## Specific Ideas

- File dropdown layout: `[File ▾] [Code] ... [Export .jl]` — File button at left, existing buttons preserved at right
- Welcome overlay: centered card on canvas background, shows app name + recent file list (clickable entries) + "Open file..." button
- Title format when a file is open: `filename.streamgui — STREAM Composer` (with asterisk when dirty: `filename.streamgui* — STREAM Composer`)
- Close guard dialog: same three-button pattern as macOS "Save changes?" dialogs — Save / Don't Save / Cancel

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 37-project-persistence*
*Context gathered: 2026-04-02*

# Phase 70: Presets and Templates — Research

**Researched:** 2026-05-20
**Domain:** Tauri 2 file-watching, `.scpr` schema, ReactFlow drag/drop placement, Zustand store slice design
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- D-01: 4th tab "Presets" in left panel; Ctrl+4 keybind.
- D-02: Supersedes §3.14 literal wording; own tab, not a sibling category inside Components.
- D-03: Two sections per tab — "Project" (`<project>/presets/`) and "Library" (`appConfigDir/stream-composer/presets/`); both collapsible.
- D-04: Two stores. Project = `<project-dir>/presets/*.scpr`. Library = Tauri `appConfigDir/stream-composer/presets/*.scpr`. No hardcoded `~/.config`.
- D-05: Both directories FS-watched (Tauri `watch` plugin), debounced ~200ms.
- D-06: Project store rebinds on project switch; Library is persistent.
- D-07: `.scpr` schema locked (format_version: "1.0", kind: "preset", name, description, resources, components, connections, layout).
- D-08: IO in `projectIO.ts` or sibling `presetIO.ts` in same `lib/` dir.
- D-09: `name` field MUST match filename stem; rename updates both.
- D-10: `name` charset `[A-Za-z0-9_-]+`; validated at save time.
- D-11: `layout` normalized to bbox-top-left at (0,0) at save time.
- D-12/D-13: Auto-extend one hop along BC edges only; cross-boundary FlowPort + thermal-pair edges dropped; one hop only (non-recursive).
- D-14: Layer assignment preserved through round-trip.
- D-15/D-15.1: "Save selection as preset…" modal (Name + Description + Store radio); default Library; right-click (≥2 selected) + File menu (disabled when <2).
- D-16: Drag from Presets tab → bbox-center at cursor on drop.
- D-17: File → Load preset… → bbox-center at viewport center.
- D-18/D-18.1: Auto-select-after-load; mint-new-UUID per component; smart-name-increment for components AND embedded resources; no auto-dedupe-by-content.
- D-19/D-19.1: Right-click on entry → Rename (inline) / Delete (confirmation modal) / Reveal in Finder. No "Edit description" action.

### Claude's Discretion

- Preset tab visual style: follows Phase 62 ToolboxPanel + Resources tab patterns.
- Loading state: skeleton rows while watcher initializes.
- Tooltip metadata: name + description; planner decides whether to show component count.
- Save modal field order, labels, button labels: UI-SPEC owns this.
- Empty-state copy: in UI-SPEC.
- Drag image: generic preset icon (not mini-render per CONTEXT.md).

### Deferred Ideas (OUT OF SCOPE)

- Passive identity (UUID + version field) on presets.
- Auto-dedupe embedded resources by content.
- Preset preview thumbnail.
- Edit description from right-click.
- Preset categories/tags.
- Bulk operations.
- Import preset from URL/share.
</user_constraints>

---

## Phase Goal Restated

Phase 70 adds a reusable component-bundle template system to STREAM Composer. Users can multi-select components on the canvas and save the selection (plus any auto-extended BC-source components) as a named `.scpr` file in either a per-project or user-global library. Templates can then be dragged from a new 4th "Presets" tab in the left panel or loaded via `File → Load preset…`. On load, all component and resource names are incremented to avoid collisions, every node gets a new UUID, and all placed components are auto-selected. The entire feature is copy-paste with no identity — no link back to the source `.scpr` after placement.

---

## Architecture

### Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `.scpr` serialize / deserialize | `gui/src/lib/presetIO.ts` (new) | — | Mirrors `.scp` pattern: projectIO.ts owns project IO; presetIO.ts owns preset IO |
| Auto-extend selection (BC-hop) | Pure helper function in `presetIO.ts` or new `gui/src/lib/presetUtils.ts` | Caller in store action `saveSelectionAsPreset` | Pure graph-walk; no side effects; easily tested |
| Watcher lifecycle | `gui/src/store/useStore.ts` new `presets` slice | React effect in `PresetsPanel.tsx` triggers mount/cleanup | Store owns watcher teardown refs; panel triggers via useEffect |
| Presets tab UI | `gui/src/components/PresetsPanel.tsx` (new) | `gui/src/App.tsx` tab registration | New panel component mirrors ResourcesTreePanel structure |
| Save-as-Preset modal | `gui/src/components/SavePresetModal.tsx` (new) | Opened from NodeContextMenu + FileMenu | Radix Dialog; same chrome as Phase 67 modals |
| Drop placement math | `gui/src/components/CanvasPanel.tsx` (extend `onDrop`) | Store action `loadPreset` | screenToFlowPosition already called there for component drag |
| File → Load preset… | `gui/src/components/FileMenu.tsx` (extend) | Store action `loadPresetFromPath` | File menu already owns all file-system-opened project actions |
| File-system watcher events → store | Store `presetsSlice` (new) | `PresetsPanel.tsx` mounts/unmounts watchers | Watcher callback calls `set({ presets: ... })` |
| Ctrl+4 keybind | `gui/src/App.tsx` (extend `handleLeftTabKey`) | — | Mirrors Ctrl+1/2/3 pattern on lines 281-302 |
| UUID generation | `crypto.randomUUID()` (existing browser API) | — | Already used everywhere in store |

---

## Open Questions Resolved

### Q1 — Tauri file-watching surface

**Tauri version in use:** `tauri = "2"` (Cargo.toml line 22). Plugin: `tauri-plugin-fs = "2.4.5"` (already installed as a dependency in both `Cargo.toml` and `package.json`).

**Watch API (confirmed from installed `@tauri-apps/plugin-fs/dist-js/index.d.ts`):**

```typescript
import { watch, type WatchEvent, type UnwatchFn } from "@tauri-apps/plugin-fs";

// Returns a cleanup function (UnwatchFn = () => void)
const unwatch: UnwatchFn = await watch(
  absoluteDirPath,          // string — computed from appConfigDir/join or project dir
  (event: WatchEvent) => {
    // event.type: WatchEventKind ('any' | {create:...} | {modify:...} | {remove:...} | 'other')
    // event.paths: string[]  — absolute paths affected
    refreshPresetsForStore(storeId);
  },
  { delayMs: 200 }          // debounce ~200ms per D-05
);
// call unwatch() on cleanup
```

**WatchEvent shape (from dist-js/index.d.ts lines 757-828):**
- `type: WatchEventKind` — discriminated union: `'any'` | `{ create: WatchEventKindCreate }` | `{ modify: WatchEventKindModify }` | `{ remove: WatchEventKindRemove }` | `'other'`
- `paths: string[]` — absolute paths affected
- `attrs: unknown`

**`WatchEventKindCreate.kind`:** `'any' | 'file' | 'folder' | 'other'`
**`WatchEventKindRemove.kind`:** `'any' | 'file' | 'folder' | 'other'`
**`WatchEventKindModify.kind`:** `'any' | 'data' | 'metadata' | 'rename' | 'other'`

**Cargo.toml change required:** `tauri-plugin-fs` must gain the `watch` feature flag:
```toml
# Before:
tauri-plugin-fs = "2.4.5"
# After:
tauri-plugin-fs = { version = "2.4.5", features = ["watch"] }
```

**`capabilities/default.json` additions required:**
```json
"fs:allow-watch",
"fs:allow-unwatch",
"fs:scope-appconfig-recursive",
{
  "identifier": "fs:scope",
  "allow": [
    { "path": "$APPCONFIG/stream-composer/presets/**" }
  ]
}
```

The `scope-appconfig-recursive` and `allow-watch` / `allow-unwatch` identifiers are confirmed present in `gen/schemas/acl-manifests.json`. The `$APPCONFIG` scope variable is confirmed in the ACL manifest.

**Debounce strategy:** Use `watch()` (not `watchImmediate()`); pass `delayMs: 200`. This coalesces rapid save-bursts from editors. No additional JS-side debounce needed — the plugin's built-in delay is sufficient for this use case.

**Platform note:** `watch()` returns `UnwatchFn` that must be called on cleanup. Store the return value in a `useRef` inside the watcher effect and call it in the effect's cleanup function.

[VERIFIED: @tauri-apps/plugin-fs/dist-js/index.d.ts + gen/schemas/acl-manifests.json in codebase]

---

### Q2 — `appConfigDir` cross-platform resolution

**JS-side API (confirmed from `@tauri-apps/api/path.d.ts` line 109):**
```typescript
import { appConfigDir, join } from "@tauri-apps/api/path";
const dir = await appConfigDir();
const presetDir = await join(dir, "stream-composer", "presets");
```

`appConfigDir()` resolves to `${configDir}/${bundleIdentifier}` where `bundleIdentifier` is the `identifier` field in `tauri.conf.json`. Current identifier: `"com.stream.composer"`.

**Resolved paths:**
- Linux: `~/.config/com.stream.composer/` (XDG_CONFIG_HOME, typically `~/.config`)
- macOS: `~/Library/Application Support/com.stream.composer/`
- Windows: `%APPDATA%\com.stream.composer\`

Note: The `identifier` is `com.stream.composer`, not `stream-composer`. So the library preset store will resolve to `~/.config/com.stream.composer/presets/` on Linux (not `~/.config/stream-composer/presets/` as CONTEXT.md suggests in passing). This is expected — the identifier drives the path, not the product name. The CONTEXT.md example paths are illustrative, not literal.

**Permissions required:** `appConfigDir` is a pure path computation call with no I/O permissions; it works without additional capability entries. The `fs:scope-appconfig-recursive` entry in capabilities is needed to allow FS reads/writes within that directory.

**`BaseDirectory.AppConfig` (enum value 13)** can be used in `watch()` options as `baseDir: BaseDirectory.AppConfig` when watching relative paths, but for absolute-path watching (safer and mirrors existing `autoRecover.ts` pattern of building absolute paths with `appDataDir + join`), pass the absolute path directly.

[VERIFIED: @tauri-apps/api/path.d.ts + tauri.conf.json in codebase]

---

### Q3 — `.scpr` schema authoring and parsing

**Pattern to follow:** `gui/src/lib/projectIO.ts` — pure serialize/deserialize functions, no side effects, no Tauri imports, fully testable in vitest node environment.

**Recommendation:** New file `gui/src/lib/presetIO.ts` (D-08: "planner's call" — separate file keeps concerns clean and avoids bloating projectIO.ts which is already 306 lines).

**Schema TypeScript interface:**
```typescript
export const PRESET_FORMAT_VERSION = "1.0" as const;

export interface StreamPreset {
  format_version: typeof PRESET_FORMAT_VERSION;
  kind: "preset";
  name: string;                    // matches filename stem; [A-Za-z0-9_-]+ (D-10)
  description: string;             // optional; empty string if none
  resources: {
    geometries: GeometryResource[];
    power_shapes: PowerShapeResource[];
    fluids: FluidResource[];
  };
  components: Node[];              // ReactFlow Node[] — same shape as .scp
  connections: Edge[];             // ReactFlow Edge[] — internal edges only
  layout: Record<string, { x: number; y: number }>; // normalized bbox-top-left=(0,0)
}
```

**Parsing strategy:** Follow projectIO.ts pattern exactly:
- `serializePreset(args): string` — builds `StreamPreset` object, `JSON.stringify(project, null, 2)`.
- `deserializePreset(json: string): StreamPreset` — `JSON.parse` then strict `format_version === "1.0"` and `kind === "preset"` check; throw on mismatch.
- No upgraders, no fallbacks. Broken files → error toast via `@tauri-apps/plugin-dialog`'s `message()` (the existing project error pattern, lines 2459-2464 in useStore.ts).

**Zod vs hand-written:** No Zod in the project; do not add it. Match the existing hand-written discriminant-check style of `deserializeProject`.

**`format_version: "1.0"` invariant:** This is the only valid value. The check is `parsed.format_version !== "1.0"` (string literal, no coercion). Old/broken files throw immediately.

[VERIFIED: gui/src/lib/projectIO.ts — established pattern in codebase]

---

### Q4 — Auto-extend algorithm (D-12 / D-13)

**BC edge identification:** BC edges in the store have `type === "bcEdge"` (confirmed from `CanvasPanel.tsx` line 144: `else if (edge.type === "bcEdge") edgeLayerKey = "Sources"`). The `BCEdgeData` interface on `edge.data` carries `{ componentId, externalInputName, targetSide }`.

**FlowPort edge identification:** FlowPort edges have `type === "hydraulicEdge"`.

**Thermal-pair edge identification:** Thermal edges have `type` that is neither `"hydraulicEdge"` nor `"bcEdge"` (see `codeGenerator.ts` which separates `flowEdges` vs `thermalEdges` vs bcEdge).

**Auto-extend algorithm (pure function, no store reads needed at call time):**
```
function autoExtendSelection(
  selectedNodeIds: Set<string>,
  allNodes: Node[],
  allEdges: Edge[]
): { extendedIds: Set<string>; droppedEdges: Edge[]; keptEdges: Edge[] }
```

Steps:
1. Build `extendedSet = new Set(selectedNodeIds)`.
2. For each `bcEdge` in `allEdges`:
   - If exactly one endpoint is in `extendedSet` (XOR check), add the OTHER endpoint to `extendedSet`.
   - This is one hop; do not iterate.
3. After extension, partition `allEdges` into:
   - `keptEdges`: both endpoints in `extendedSet`.
   - `droppedEdges`: one or both endpoints outside `extendedSet` (these are cross-boundary — drop).

**No existing store helper for this.** The closest is the clipboard's edge-filter in `pasteFromClipboard` (useStore.ts line 2047-2061) which filters to internal edges only — the pattern is identical for the "drop cross-boundary" step. Implement as a pure function in `presetIO.ts` or a new `presetUtils.ts`.

**Cross-boundary detection for all edge types:** After the BC-hop extension, iterate all edges. Any edge where `selectedIds.has(e.source) !== selectedIds.has(e.target)` (i.e., one end is inside, one outside the extended set) is cross-boundary and dropped. This uniformly handles FlowPort, thermal-pair, and remaining BC edges.

[VERIFIED: BCEdge type confirmed in CanvasPanel.tsx; edge classification in codeGenerator.ts; clipboard pattern in useStore.ts]

---

### Q5 — Embedded-resource semantics on save and load

**On save:** Walk `extendedSet` (post-auto-extend). For each node, read `node.data.parameters.geometry` and `node.data.parameters.power_shape` (and the `_ref`-suffixed aliases per ResourceRow.tsx lines 58-62). Resolve UUIDs to full `GeometryResource` / `PowerShapeResource` objects from `store.resources.geometries[uuid]` / `store.resources.powerShapes[uuid]`. Deep-copy into the preset's `resources` block. Light water fluid placeholder is excluded (same filter as `serializeProject`).

**On load — resource collision handling:** For each embedded resource in the preset's `resources` block:
1. Check if a same-name resource already exists in `store.resources` (by `name` field, not UUID).
2. If no collision → add with a mint-new UUID (re-key the object).
3. If collision → apply `smartParseAndIncrement(embeddedName, existingNamesSet)` to derive a new non-colliding name, then add with mint-new UUID.
4. **No content-dedupe** (D-18.1): even byte-identical resources get a new entry. User merges manually.

**Helper to reuse:** `duplicateResource` in `useStore.ts` (lines 1735-1786) is close in spirit but duplicates an existing resource by UUID. For preset load, the pattern is different — inserting a foreign resource with potential rename. The `smartParseAndIncrement` from `clipboard.ts` (line 87) is the right utility to call directly; the store action `addGeometry` / `addPowerShape` (from Phase 62) can accept a fully-formed resource object with a pre-minted UUID.

**UUID remapping:** After adding each embedded resource with its new UUID, build an `oldUUID → newUUID` remapping. Apply this remapping to all component `data.parameters.geometry` / `data.parameters.power_shape` fields in the loaded node set before adding them to the canvas.

[VERIFIED: useStore.ts duplicateResource pattern; ResourceRow.tsx PARAM_KEY_BY_KIND; clipboard.ts smartParseAndIncrement]

---

### Q6 — Drop placement math

**Drag-from-toolbox case (D-16 — bbox-center at cursor):**

`screenToFlowPosition({ x: event.clientX, y: event.clientY })` is already called in `CanvasPanel.tsx` line 175 for component drops. For preset drops, the caller needs to:
1. Compute the bbox of the normalized layout (D-11: already bbox-top-left at (0,0), so bbox-width = max(x + nodeWidth), bbox-height = max(y + nodeHeight)).
2. Compute the offset: `bboxCenterX = bboxWidth / 2`, `bboxCenterY = bboxHeight / 2`.
3. Place each node at: `{ x: cursorFlowPos.x - bboxCenterX + node.layout.x, y: cursorFlowPos.y - bboxCenterY + node.layout.y }`.

**File → Load preset… case (D-17 — bbox-center at viewport center):**

`getViewport()` is available from `useReactFlow()` (confirmed from `@xyflow/react` types: `ReactFlowInstance.getViewport: GetViewport`). But the store action `loadPresetFromPath` runs outside a React component and cannot call hooks. Two options:
- **Option A (preferred):** Pass the viewport as an argument from the FileMenu handler (which lives inside a React component that can call `useReactFlow`). Similar to how `CanvasPanel.tsx` passes `screenToFlowPosition` to store actions via callback.
- **Option B:** Store the viewport in Zustand state (not recommended — Zustand store is not the right place for transient viewport state).

The existing precedent is the clipboard paste — `pasteFromClipboard` in useStore.ts uses a module-level `pasteOffsetIndex` counter and does NOT use viewport position. For "viewport center" placement, Option A is cleaner: the `FileMenu.tsx` handler obtains viewport via `useReactFlow().getViewport()` and passes the center coordinates to the store action.

**screenToFlowPosition formula for viewport center:**
```typescript
const vp = getViewport(); // { x, y, zoom }
// Viewport center in flow coordinates:
const centerX = (-vp.x + window.innerWidth / 2) / vp.zoom;
const centerY = (-vp.y + window.innerHeight / 2) / vp.zoom;
```

[VERIFIED: CanvasPanel.tsx screenToFlowPosition usage; @xyflow/react types for getViewport; useStore.ts pasteFromClipboard pattern]

---

### Q7 — Mint-new-UUID on load

**UUID utility:** `crypto.randomUUID()` — already used throughout `useStore.ts` (e.g., line 1753 in `duplicateResource`, line 2016 in `pasteFromClipboard`). No additional import needed; this is a browser-native API available in all Tauri WebView environments.

**Node UUID remapping pattern:** Identical to `pasteFromClipboard` (useStore.ts lines 2015-2045). Build `oldToNew = new Map<string, string>()`, call `crypto.randomUUID()` per node, remap edge source/target IDs. The load-preset code should copy this pattern verbatim, adding the resource-UUID remapping step.

[VERIFIED: useStore.ts pasteFromClipboard — established pattern]

---

### Q8 — File-system watcher integration with the store slice

**Proposed store slice shape:**

```typescript
// In useStore.ts — new section
export interface PresetIndexEntry {
  name: string;           // matches filename stem
  description: string;   // from preset JSON; empty string if none
  filePath: string;       // absolute path to .scpr file
  store: "project" | "library";
}

// State additions:
projectPresets: PresetIndexEntry[];
libraryPresets: PresetIndexEntry[];
// Watcher teardown functions (NOT in Zustand state — store in useRef in PresetsPanel)
// Store-level actions:
setProjectPresets: (entries: PresetIndexEntry[]) => void;
setLibraryPresets: (entries: PresetIndexEntry[]) => void;
refreshPresetsDir: (store: "project" | "library", dir: string) => Promise<void>;
```

**Watcher lifecycle:** The watchers should be started/stopped in a `useEffect` inside `PresetsPanel.tsx`, NOT inside the Zustand store (Zustand actions are synchronous; async watcher setup belongs in React lifecycle). The teardown functions are held in `useRef<UnwatchFn[]>`.

```typescript
// In PresetsPanel.tsx:
useEffect(() => {
  const unwatchers: UnwatchFn[] = [];
  
  async function setup() {
    // 1. Get dirs
    const { appConfigDir, join } = await import("@tauri-apps/api/path");
    const libDir = await join(await appConfigDir(), "presets");
    const projDir = currentProjectDir ? await join(currentProjectDir, "presets") : null;
    
    // 2. Ensure dirs exist (mkdir recursive, ignore EEXIST)
    await mkdir(libDir, { recursive: true }).catch(() => {});
    
    // 3. Initial scan
    await store.refreshPresetsDir("library", libDir);
    if (projDir) await store.refreshPresetsDir("project", projDir);
    
    // 4. Watch
    const unwatchLib = await watch(libDir, () => store.refreshPresetsDir("library", libDir), { delayMs: 200 });
    unwatchers.push(unwatchLib);
    if (projDir) {
      const unwatchProj = await watch(projDir, () => store.refreshPresetsDir("project", projDir), { delayMs: 200 });
      unwatchers.push(unwatchProj);
    }
  }
  
  setup().catch(console.error);
  return () => { unwatchers.forEach(fn => fn()); };
}, [currentProjectDir]);
```

**`refreshPresetsDir` store action:** reads the directory with `readDir`, filters `*.scpr` files, reads each with `readTextFile`, parses with `deserializePreset`, extracts `{ name, description }`, builds `PresetIndexEntry[]`, calls `set({ projectPresets: ... })` or `set({ libraryPresets: ... })`. Files that fail to parse are surfaced via `message()` toast (per existing pattern) and skipped.

**D-06 (project switch rebinding):** The `currentProjectDir` passed to the watcher effect is derived from `useStore(s => s.currentFilePath)`. When the file path changes, the effect re-runs (because `currentProjectDir` is in the deps array), the old watchers are cleaned up, and new ones are started for the new project directory.

[ASSUMED: The split of watcher lifecycle into PresetsPanel useEffect (not useStore) is a design recommendation — the project has no prior example of this pattern, though autoRecover.ts in useStore.ts does use async patterns similarly]

---

### Q9 — Selection-extension preview (auto-extend visualization)

**Current selection state:** ReactFlow nodes carry `node.selected: boolean`. The canvas renders selected nodes with a blue selection ring via ReactFlow's built-in selection style.

**No existing "ghost/preview" or secondary selection state exists** in the codebase. There is no amber ring, dashed outline, or "pending add" visual treatment in any current component.

**Proposed minimal addition:** Add a `data.autoExtended?: boolean` transient field to nodes temporarily during the "Save selection as preset…" flow. In `StreamNode.tsx`, check `data.autoExtended` to apply a secondary outline CSS class (`outline outline-2 outline-dashed outline-[oklch(0.769_0.188_70.08)] outline-offset-2`). This field:
- Is set when the user triggers "Save selection as preset…" (in the modal-open handler).
- Is cleared when the Save modal closes (onOpenChange → false) or on Save.
- Never persisted to `.scp` (filtered out by `serializeProject` / strip on save).
- Visible only transiently.

Alternative (lower coupling): pass a `Set<string>` of "auto-extended node IDs" as React state in the `SavePresetModal` component and pass it down to `CanvasPanel` via context or prop. This avoids touching node data but requires React context threading.

**Recommendation:** The `data.autoExtended` approach is simpler, matches how `data.selected` works (ReactFlow already does this pattern), and requires zero context threading. Strip the field on serialize.

[ASSUMED: The specific approach (data.autoExtended vs context vs other) is a planner call; the codebase has no prior "transient visual overlay" example to clone exactly]

---

### Q10 — Testing surface

**Test framework:** Vitest (confirmed: `vitest` in devDependencies; `npm run test` = `vitest run --passWithNoTests`). Existing test patterns: `gui/src/lib/__tests__/` for pure lib functions, `gui/src/store/__tests__/` for store actions with mocked Tauri, `gui/src/components/__tests__/` for React components with Testing Library.

**Tests this phase needs:**

**Unit tests (pure functions — vitest node environment, no Tauri mock needed):**
1. `presetIO.test.ts` — `serializePreset` / `deserializePreset` round-trip; version rejection (format_version ≠ "1.0" throws); kind rejection (kind ≠ "preset" throws); empty resources tolerance.
2. `presetIO.test.ts` — `autoExtendSelection`: BC-edge hop adds correct nodes; non-BC edges not extended; already-selected BC source not duplicated; cross-boundary edges correctly identified; single-hop invariant (BC source's other connections to outside nodes dropped).
3. `presetIO.test.ts` — layout normalization: `normalizeLayout` shifts all positions so bbox-top-left is at (0,0).
4. `smartParseAndIncrement` already tested in `clipboard.test.ts` — reuse, no new tests needed.

**Store action tests (Tauri mocked per existing `saveAndOpenErrors.test.ts` pattern):**
5. `saveSelectionAsPreset` — writes correct `.scpr` JSON, calls `writeTextFile` with expected path.
6. `loadPresetAtPosition` — mints new UUIDs, smart-names components, adds resources, auto-selects all added nodes.
7. `renamePreset` — renames file AND updates `name` field inside JSON.
8. `deletePreset` — calls `remove` on file path.

**Manual UAT (requires Tauri build — autonomous: false):**
- Drag-from-preset-tab drop placement (bbox-center at cursor).
- File → Load preset… placement at viewport center.
- File-watcher live updates (save a `.scpr` externally; verify Presets tab updates without restart).
- Cross-platform `appConfigDir` paths (Linux confirmed in dev environment; macOS/Windows require hardware).
- Reveal in Finder/Explorer via `revealItemInDir`.
- Ctrl+4 keybind switches to Presets tab.

[VERIFIED: vitest test file locations and patterns from existing `gui/src/lib/__tests__/` and `gui/src/store/__tests__/`]

---

## Files to Create

| File | Purpose |
|------|---------|
| `gui/src/lib/presetIO.ts` | `.scpr` serialize / deserialize, `autoExtendSelection`, `normalizeLayout` |
| `gui/src/lib/__tests__/presetIO.test.ts` | Unit tests for all pure presetIO functions |
| `gui/src/components/PresetsPanel.tsx` | 4th left-panel tab body (two-section list, drag handles, context menus, skeletons, empty states) |
| `gui/src/components/SavePresetModal.tsx` | Radix Dialog with Name + Description + Store radio + validation |
| `gui/src/store/__tests__/presetActions.test.ts` | Store action tests (save, load, rename, delete) |

---

## Files to Modify

| File | Change |
|------|--------|
| `gui/src/store/useStore.ts` | Add `projectPresets`, `libraryPresets`, `PresetIndexEntry` type; add `setProjectPresets`, `setLibraryPresets`, `refreshPresetsDir`, `saveSelectionAsPreset`, `loadPresetAtPosition`, `loadPresetFromPath`, `renamePreset`, `deletePreset` actions; extend `ActiveLeftTab` to add `"Presets"` |
| `gui/src/lib/projectIO.ts` | Add `"Presets"` to `ActiveLeftTab` union (it's re-exported from here for the `.scp` layout type) — OR import the type from useStore only; check which file owns the canonical union |
| `gui/src/App.tsx` | Add Ctrl+4 to `handleLeftTabKey` effect (line 281); add `"Presets"` tab with `BookMarked` icon to `ResponsiveTabsList` tabs array; add `<TabsContent value="Presets">` mounting `<PresetsPanel />`; extend `onValueChange` type cast |
| `gui/src/components/FileMenu.tsx` | Add separator + "Load preset…" + "Save selection as preset…" (disabled when `selectedNodeCount < 2`) menu items |
| `gui/src/components/canvasMenus/NodeContextMenu.tsx` | Add "Save selection as preset…" `DropdownMenuItem` visible when selection count ≥ 2; opens `SavePresetModal` |
| `gui/src-tauri/Cargo.toml` | Change `tauri-plugin-fs = "2.4.5"` → `tauri-plugin-fs = { version = "2.4.5", features = ["watch"] }` |
| `gui/src-tauri/capabilities/default.json` | Add `"fs:allow-watch"`, `"fs:allow-unwatch"`, `"fs:scope-appconfig-recursive"`, and fs scope entry for `$APPCONFIG/presets/**` |
| `gui/src/components/StreamNode.tsx` (or equivalent node renderer) | Add `data.autoExtended` visual treatment (amber dashed outline) for auto-extend preview |

---

## Risk / Pitfalls

### Pitfall 1: `watch` feature flag missing from Cargo.toml
**What goes wrong:** Importing `watch` from `@tauri-apps/plugin-fs` at JS runtime fails with an IPC error because the Rust side does not expose the command. The JS package includes the types/exports regardless of whether the Rust feature is enabled.
**Prevention:** The first task in any wave that touches the watcher MUST update `Cargo.toml` and rebuild. Rebuild is required (`cargo build` or `tauri dev`); hot-reload does not pick up Cargo feature changes.

### Pitfall 2: `appConfigDir` returns `com.stream.composer` not `stream-composer`
**What goes wrong:** If code hardcodes a `stream-composer` subdirectory assumption (from the CONTEXT.md illustrative example), the preset store path differs from what `appConfigDir()` + `join("presets")` actually resolves to.
**Prevention:** Always construct the path as `await join(await appConfigDir(), "presets")` — never hardcode intermediate segments. The identifier in `tauri.conf.json` (`com.stream.composer`) is baked into the resolved path.

### Pitfall 3: Watcher fires on partial writes (editor save-burst)
**What goes wrong:** An external editor saves a `.scpr` in two phases (truncate then write). The watcher fires after the truncate, and `readTextFile` reads an empty or partial file, causing `JSON.parse` to throw.
**Prevention:** The `delayMs: 200` debounce in `watch()` coalesces burst events. The `refreshPresetsDir` action must catch parse errors per-file (try/catch around `deserializePreset`) and surface a toast for unreadable files without crashing the refresh loop.

### Pitfall 4: Project store watcher outlives the project
**What goes wrong:** When the user opens a different project, the old project's watcher is still active and fires events that update `projectPresets` for the wrong directory.
**Prevention:** The `currentProjectDir` in the `PresetsPanel` `useEffect` deps array triggers cleanup (unwatch) of the old watcher before starting the new one. This is the standard React effect cleanup pattern.

### Pitfall 5: UUID remapping misses resource references in component parameters
**What goes wrong:** After loading a preset, the embedded resources get new UUIDs. If the UUID remapping pass doesn't cover all parameter keys (`geometry`, `geometry_ref`, `power_shape`, `power_shape_ref` — the dual-key pattern per ResourceRow.tsx lines 58-62), some components reference stale UUIDs that no longer exist in the project's resource store.
**Prevention:** Apply the resource UUID remapping to ALL four parameter key variants. Copy the `PARAM_KEY_BY_KIND` pattern from `ResourceRow.tsx` into the load-preset utility.

### Pitfall 6: `ActiveLeftTab` type in `projectIO.ts` and `useStore.ts` need simultaneous update
**What goes wrong:** `ActiveLeftTab = "Components" | "Resources" | "Project"` is exported from `useStore.ts` line 141 and imported by `projectIO.ts`. Adding `"Presets"` to the union but not updating both files causes TypeScript errors.
**Prevention:** Update the union in `useStore.ts` first; `projectIO.ts` imports the type from `useStore.ts`, so it inherits the change automatically.

### Pitfall 7: `data.autoExtended` persisted in `.scp` if not explicitly stripped
**What goes wrong:** If the user triggers "Save selection as preset…" then saves the project without dismissing the modal (or if cleanup is delayed), `data.autoExtended: true` ends up in the `.scp` file. On reload, nodes have a permanent amber outline.
**Prevention:** `serializeProject` in `projectIO.ts` should strip `data.autoExtended` from all nodes before serializing. Alternatively, clear `autoExtended` on any project save action. The auto-clear on modal dismiss (D-15: "highlights clear when modal is dismissed") is the primary cleanup path.

### Pitfall 8: `watch()` called before the directory exists
**What goes wrong:** If `~/.config/com.stream.composer/presets/` does not exist (first launch), `watch(nonexistentDir, ...)` may fail or silently emit no events on some platforms.
**Prevention:** Always call `mkdir(presetDir, { recursive: true })` before starting the watcher. The `recursive: true` flag makes `mkdir` a no-op if the directory already exists.

### Pitfall 9: `NodeContextMenu` only shows context menu for single-node right-click
**What goes wrong:** D-15.1 requires "Save selection as preset…" on right-click when selection count ≥ 2. But the current `NodeContextMenu` receives a single `nodeId`. If the user right-clicks a node that is part of a multi-selection, the context menu must reflect the full selection, not just the single node.
**Prevention:** In `NodeContextMenu.tsx`, read `useStore.getState().nodes.filter(n => n.selected).length` to determine selection count. Conditionally render the "Save selection as preset…" item only when count ≥ 2. This is a read (no mutation) so it's safe to do synchronously in the render.

---

## Test Strategy

`nyquist_validation` is `false` in `.planning/config.json`. The Validation Architecture section is omitted per config.

**Unit test targets (vitest, node environment — no Tauri mock needed):**

| Test | File | Type |
|------|------|------|
| `serializePreset` / `deserializePreset` round-trip | `presetIO.test.ts` | Unit |
| `deserializePreset` rejects wrong `format_version` | `presetIO.test.ts` | Unit |
| `deserializePreset` rejects wrong `kind` | `presetIO.test.ts` | Unit |
| `autoExtendSelection` — BC hop adds correct nodes | `presetIO.test.ts` | Unit |
| `autoExtendSelection` — non-BC edges not extended | `presetIO.test.ts` | Unit |
| `autoExtendSelection` — single-hop only (D-13) | `presetIO.test.ts` | Unit |
| `autoExtendSelection` — cross-boundary edges dropped | `presetIO.test.ts` | Unit |
| `normalizeLayout` — bbox-top-left at (0,0) | `presetIO.test.ts` | Unit |
| Name validation regex `[A-Za-z0-9_-]+` | `presetIO.test.ts` | Unit |

**Store action tests (Tauri mocked — follows `saveAndOpenErrors.test.ts` pattern):**

| Test | File | Type |
|------|------|------|
| `saveSelectionAsPreset` writes correct `.scpr` JSON | `presetActions.test.ts` | Integration |
| `loadPresetAtPosition` mints new UUIDs per node | `presetActions.test.ts` | Integration |
| `loadPresetAtPosition` smart-names collisions | `presetActions.test.ts` | Integration |
| `loadPresetAtPosition` adds embedded resources, remaps UUIDs | `presetActions.test.ts` | Integration |
| `loadPresetAtPosition` auto-selects all placed nodes | `presetActions.test.ts` | Integration |
| `renamePreset` renames file AND updates name field | `presetActions.test.ts` | Integration |
| `deletePreset` calls remove on correct path | `presetActions.test.ts` | Integration |

**Manual UAT (requires running Tauri build — `autonomous: false`):**
- Drag preset from tab → drop on canvas → bbox-center at cursor.
- File → Load preset… → lands at viewport center.
- File-watcher: save `.scpr` externally; Presets tab updates without app restart.
- Rename preset entry → filename changes; JSON `name` field updates.
- Delete preset → confirmation modal; entry disappears after file removal.
- Ctrl+4 switches to Presets tab.
- Cross-platform `appConfigDir` resolution (Linux in dev environment).
- Reveal in Finder/Explorer opens correct directory.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Watcher lifecycle belongs in PresetsPanel useEffect (not useStore action) | Q8 | Low — code-organization decision, can be refactored |
| A2 | `data.autoExtended` field on nodes is the right mechanism for auto-extend preview | Q9 | Low — alternative: React context; behavior is identical |
| A3 | `currentProjectDir` derived from `currentFilePath` (strip filename) in PresetsPanel | Q8 | Low — straightforward path manipulation |
| A4 | `getViewport()` called from FileMenu handler (not from store action) for viewport-center placement | Q6 | Low — alternative: store viewport in Zustand state |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `@tauri-apps/plugin-fs` (watch) | D-05 FS watcher | ✓ (partial — pkg installed but Cargo feature not enabled) | 2.4.5 | None — must add `features = ["watch"]` to Cargo.toml |
| `@tauri-apps/api/path` `appConfigDir` | D-04 library store | ✓ | @tauri-apps/api ^2 | None — use as-is |
| `@tauri-apps/plugin-opener` `revealItemInDir` | D-19 Reveal in Finder | ✓ | ^2 | None — already installed |
| `shadcn textarea` | Save modal Description field | ✗ (not in components.json) | — | `npx shadcn add textarea` |
| `shadcn radio-group` | Save modal Store selector | ✗ (not in components.json) | — | `npx shadcn add radio-group` |
| `lucide-react BookMarked` | Presets tab icon | ✓ | lucide-react ^1.7.0 | LayoutTemplate (alternative) |
| `crypto.randomUUID()` | UUID minting on load | ✓ | browser native | None — already used everywhere |

**Missing dependencies with no fallback:**
- `tauri-plugin-fs` `watch` feature: requires Cargo.toml update + `cargo build` (not a hot-reload change).

**Missing dependencies with fallback:**
- `shadcn textarea`: install via `npx shadcn add textarea` (official registry, no security concern).
- `shadcn radio-group`: install via `npx shadcn add radio-group` (official registry, no security concern).

---

## Sources

### Primary (HIGH confidence)
- `gui/src-tauri/Cargo.toml` — Tauri 2 version confirmed; `tauri-plugin-fs = "2.4.5"` present
- `gui/node_modules/@tauri-apps/plugin-fs/dist-js/index.d.ts` — `watch`, `WatchEvent`, `UnwatchFn` type signatures verified
- `gui/node_modules/@tauri-apps/api/path.d.ts` — `appConfigDir()` signature and doc-comment verified
- `gui/src-tauri/capabilities/default.json` — existing permission entries; `allow-watch` / `allow-unwatch` confirmed present in ACL manifests
- `gui/src-tauri/gen/schemas/acl-manifests.json` — `scope-appconfig-recursive`, `allow-watch`, `allow-unwatch` verified
- `gui/src/lib/projectIO.ts` — established serialize/deserialize pattern for `.scpr` to follow
- `gui/src/lib/clipboard.ts` — `smartParseAndIncrement` utility (confirmed reusable)
- `gui/src/store/useStore.ts` lines 1748, 2078-2150, 1989-2068 — `duplicateResource`, `duplicateSelection`, `pasteFromClipboard` patterns
- `gui/src/components/CanvasPanel.tsx` lines 94, 175 — `useReactFlow().screenToFlowPosition` drop placement
- `gui/src/components/canvasMenus/NodeContextMenu.tsx` — existing context menu structure to extend
- `gui/src/components/FileMenu.tsx` — existing file menu structure to extend
- `gui/src/lib/bcMode.ts` — BC edge identification (`type === "bcEdge"`)
- `gui/src/App.tsx` lines 281-302 — `handleLeftTabKey` Ctrl+1/2/3 pattern to extend for Ctrl+4
- `gui/src/components/ResponsiveTabsList.tsx` — tab strip component interface; new tab slots in by adding to `tabs` array
- `gui/src/components/resources/ResourceRow.tsx` — entry row + context menu + inline rename pattern to clone
- `gui/src/components/resources/ResourceGroupHeader.tsx` — section header pattern to clone
- `gui/src/lib/autoRecover.ts` — `appDataDir` + `join` pattern (analogous to `appConfigDir` + `join`)

### Secondary (MEDIUM confidence)
- Tauri 2 `watch` official docs (WebFetch) — confirmed feature flag requirement in Cargo.toml; `delayMs` parameter

---

## Metadata

**Confidence breakdown:**
- Schema and IO: HIGH — established pattern in codebase, fully verified
- Tauri watch API: HIGH — confirmed from installed node_modules types + ACL manifests
- Store slice design: MEDIUM-HIGH — 4 small assumptions logged; all low-risk
- Auto-extend algorithm: HIGH — edge type classification confirmed from CanvasPanel + bcMode.ts
- Drop placement: HIGH — screenToFlowPosition usage confirmed; getViewport type confirmed

**Research date:** 2026-05-20
**Valid until:** 2026-06-20 (stable stack; main risk is Tauri plugin API churn)

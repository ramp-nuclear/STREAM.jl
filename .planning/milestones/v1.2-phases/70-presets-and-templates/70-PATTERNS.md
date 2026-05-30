# Phase 70: Presets and Templates — Pattern Map

**Mapped:** 2026-05-20
**Files analyzed:** 13 (5 new, 8 modified)
**Analogs found:** 13 / 13

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|----------------|---------------|
| `gui/src/lib/presetIO.ts` (new) | utility / IO | file-I/O + transform | `gui/src/lib/projectIO.ts` | exact |
| `gui/src/lib/__tests__/presetIO.test.ts` (new) | test | — | `gui/src/lib/__tests__/clipboard.test.ts` + `projectIO.snapToGrid.test.ts` | exact |
| `gui/src/components/PresetsPanel.tsx` (new) | component | event-driven (FS watch) | `gui/src/components/ToolboxPanel.tsx` + `gui/src/components/resources/ResourcesTreePanel.tsx` | role-match |
| `gui/src/components/SavePresetModal.tsx` (new) | component | request-response | `gui/src/components/AboutDialog.tsx` | role-match |
| `gui/src/store/__tests__/presetActions.test.ts` (new) | test | — | `gui/src/store/__tests__/autoRecover.actions.test.ts` | exact |
| `gui/src/store/useStore.ts` (modify) | store | CRUD + event-driven | self (existing slice pattern) | exact |
| `gui/src/lib/projectIO.ts` (modify) | utility / IO | transform | self | exact |
| `gui/src/App.tsx` (modify) | component | request-response | self (lines 281–302, 487–513) | exact |
| `gui/src/components/FileMenu.tsx` (modify) | component | request-response | self (lines 108–118) | exact |
| `gui/src/components/canvasMenus/NodeContextMenu.tsx` (modify) | component | request-response | self (lines 50–64) | exact |
| `gui/src-tauri/Cargo.toml` (modify) | config | — | self (line 26) | exact |
| `gui/src-tauri/capabilities/default.json` (modify) | config | — | self (lines 6–35) | exact |
| `gui/src/components/StreamNode.tsx` (modify — autoExtended highlight) | component | transform | self | partial |

---

## Pattern Assignments

---

### `gui/src/lib/presetIO.ts` (new — utility, file-I/O + transform)

**Analog:** `gui/src/lib/projectIO.ts`

**Imports pattern** (lines 1–22, copy and adapt):
```typescript
// presetIO.ts — Pure serialization / deserialization for the .scpr v1.0 schema.
// Zero side-effects. All FS I/O handled in useStore.ts.
// Fully testable in vitest node environment.

import type { Node, Edge } from "@xyflow/react";
import type {
  GeometryResource,
  PowerShapeResource,
  FluidResource,
} from "../store/useStore";
```
Adaptation: remove `AnchorEntry`, `LayerKey`, `ActiveLayers`, `ActiveLeftTab`, `ModelOptionsSliceState` — presets have none of these.

**Format-version constant pattern** (lines 38–38, copy verbatim, change string):
```typescript
export const PRESET_FORMAT_VERSION = "1.0" as const;
```

**Interface definition pattern** (lines 44–68, adapt shape):
```typescript
export interface StreamPreset {
  format_version: typeof PRESET_FORMAT_VERSION;
  kind: "preset";
  name: string;
  description: string;
  resources: {
    geometries: GeometryResource[];
    power_shapes: PowerShapeResource[];
    fluids: FluidResource[];
  };
  components: Node[];
  connections: Edge[];
  layout: Record<string, { x: number; y: number }>;
}
```
Adaptation: `StreamPreset` replaces `StreamProject`; no `model_options`, `anchors`, or layout-ui fields.

**Serialize function pattern** (lines 137–167, adapt):
```typescript
export function serializePreset(args: SerializePresetArgs): string {
  const preset: StreamPreset = {
    format_version: PRESET_FORMAT_VERSION,
    kind: "preset",
    name: args.name,
    description: args.description,
    resources: { geometries: args.geometries, power_shapes: args.powerShapes, fluids: [] },
    components: args.components,
    connections: args.connections,
    layout: args.layout,
  };
  return JSON.stringify(preset, null, 2);
}
```
Note: `args.components` must have `data.autoExtended` stripped before call (per RESEARCH.md Pitfall 7).

**Deserialize function pattern** (lines 191–281, adapt):
```typescript
export function deserializePreset(json: string): StreamPreset {
  const parsed = JSON.parse(json) as Record<string, unknown>;
  if (parsed.format_version !== PRESET_FORMAT_VERSION) {
    const got = parsed.format_version === undefined
      ? "missing format_version"
      : "got '" + String(parsed.format_version) + "'";
    throw new Error("Invalid .scpr file: expected format_version '"
      + PRESET_FORMAT_VERSION + "', " + got);
  }
  if (parsed.kind !== "preset") {
    throw new Error("Invalid .scpr file: expected kind 'preset', got '"
      + String(parsed.kind) + "'");
  }
  // ... field extraction with ?? defaults
}
```
Adaptation: add `kind` check (projectIO has no `kind` field); no legacy shims; no `active_layer` migration.

**`autoExtendSelection` pure-function pattern** — no existing analog; implement fresh per RESEARCH.md Q4:
```typescript
export function autoExtendSelection(
  selectedNodeIds: Set<string>,
  allNodes: Node[],
  allEdges: Edge[],
): { extendedIds: Set<string>; keptEdges: Edge[]; droppedEdges: Edge[] }
```
The edge-drop logic at the end mirrors `pasteFromClipboard` in `useStore.ts` lines 2047–2061 (filter edges whose both endpoints are in the id set).

**`normalizeLayout` pure-function** — no existing analog; compute bbox-top-left at (0,0):
```typescript
export function normalizeLayout(
  nodes: Node[],
): Record<string, { x: number; y: number }>
```

**Name-validation helper:**
```typescript
const PRESET_NAME_RE = /^[A-Za-z0-9_-]+$/;
export function isValidPresetName(name: string): boolean {
  return PRESET_NAME_RE.test(name);
}
```

---

### `gui/src/lib/__tests__/presetIO.test.ts` (new — test)

**Analog:** `gui/src/lib/__tests__/clipboard.test.ts` + `gui/src/lib/__tests__/projectIO.snapToGrid.test.ts`

**Test file header pattern** (`clipboard.test.ts` lines 1–7):
```typescript
import { describe, it, expect } from "vitest";
import {
  serializePreset,
  deserializePreset,
  autoExtendSelection,
  normalizeLayout,
  isValidPresetName,
  PRESET_FORMAT_VERSION,
} from "../presetIO";
```

**Round-trip test pattern** (`projectIO.snapToGrid.test.ts` lines 10–85):
```typescript
describe("serializePreset / deserializePreset round-trip", () => {
  it("round-trips a minimal preset", () => {
    const json = serializePreset({ name: "test", description: "", ... });
    const result = deserializePreset(json);
    expect(result.format_version).toBe("1.0");
    expect(result.kind).toBe("preset");
  });
  it("rejects wrong format_version", () => {
    expect(() => deserializePreset(JSON.stringify({ format_version: "2.0", kind: "preset" })))
      .toThrow("format_version");
  });
  it("rejects wrong kind", () => {
    expect(() => deserializePreset(JSON.stringify({ format_version: "1.0", kind: "project" })))
      .toThrow("kind");
  });
});
```

**Naming-test pattern** (`clipboard.test.ts` lines 9–119): copy the `describe` block structure, adapt for `autoExtendSelection` and `normalizeLayout`.

---

### `gui/src/components/PresetsPanel.tsx` (new — component, event-driven)

**Analog 1:** `gui/src/components/ToolboxPanel.tsx` — outer scrollable container + category headings structure  
**Analog 2:** `gui/src/components/resources/ResourceGroupHeader.tsx` — section header visual treatment (no `+` button for Presets sections)

**Outer container pattern** (`ToolboxPanel.tsx` lines 28–31):
```tsx
export default function PresetsPanel() {
  return (
    <div className="h-full p-2 overflow-y-auto min-w-0">
      {/* "Project" section then "Library" section */}
    </div>
  );
}
```

**Section header pattern** (`ToolboxPanel.tsx` lines 32–34 visual treatment; `ResourceGroupHeader.tsx` lines 124–133 layout):
```tsx
// Collapsible section header — no "+" button (presets created from canvas)
<div className="flex items-center justify-between gap-1 pl-[8px] pr-[4px] mt-[8px] min-w-0">
  <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground truncate min-w-0">
    {label}
  </div>
  <button onClick={() => setExpanded(v => !v)} ...>
    <ChevronDown className={cn("h-4 w-4 transition-transform duration-150",
      !expanded && "-rotate-90")} />
  </button>
</div>
```
Adaptation: `ResourceGroupHeader` has a `+` button right affordance — replace with a chevron toggle button. No `onAdd`, `resourceKind`, `disabled`, or `disabledTooltip` props.

**Entry row pattern** (`gui/src/components/resources/ResourceRow.tsx` lines 217–224 row class; lines 268–282 `<li>` shape):
```tsx
<li
  draggable
  onDragStart={handleDragStart}
  className="h-[22px] px-[8px] text-[13px] flex items-center gap-2 cursor-grab select-none min-w-0 overflow-hidden hover:bg-accent rounded-sm"
>
  <GripVertical className="h-3 w-3 text-muted-foreground shrink-0" />
  <Tooltip>
    <TooltipTrigger asChild>
      <span className="truncate flex-1">{entry.name}</span>
    </TooltipTrigger>
    {entry.description && (
      <TooltipContent side="right" className="max-w-[200px] whitespace-normal">
        {entry.description}
      </TooltipContent>
    )}
  </Tooltip>
</li>
```
Adaptation: add `draggable` + `onDragStart` (absent in ResourceRow); add `GripVertical` drag handle column; tooltip wraps name span (ResourceRow uses name span only).

**Inline rename pattern** (`ResourceRow.tsx` lines 78–165 full rename state machine):
```tsx
// Lift verbatim from ResourceRow lines 78–165:
const [renaming, setRenaming] = useState(false);
const [renameValue, setRenameValue] = useState(entry.name);
const [renameError, setRenameError] = useState<string | null>(null);
const inputRef = useRef<HTMLInputElement | null>(null);
// ...focus effect, commitRename, cancelRename, handleRowKeyDown (F2)
// Input inside row when renaming:
<Input
  ref={inputRef}
  value={renameValue}
  className={cn("h-[24px] py-0 px-[6px] text-[13px] shadow-none",
    renameError && "border-destructive ring-destructive/30")}
  title={renameError ?? undefined}
  onKeyDown={(e) => { if (e.key === "Enter") commitRename(); if (e.key === "Escape") cancelRename(); }}
  onBlur={commitRename}
/>
```
Adaptation: `commitRename` calls `renamePreset(entry.filePath, renameValue)` store action instead of `renameResource`.

**Context menu pattern** (`ResourceRow.tsx` lines 289–305):
```tsx
<ContextMenu>
  <ContextMenuTrigger asChild>{baseRow}</ContextMenuTrigger>
  <ContextMenuContent>
    <ContextMenuItem onSelect={startRename}>Rename</ContextMenuItem>
    <ContextMenuItem variant="destructive" onSelect={() => setConfirmOpen(true)}>Delete</ContextMenuItem>
    <ContextMenuSeparator />
    <ContextMenuItem onSelect={handleReveal}>Reveal in Finder/Explorer</ContextMenuItem>
  </ContextMenuContent>
</ContextMenu>
```
Adaptation: replace "Duplicate" + "Show usages" items with "Reveal in Finder/Explorer". Menu order per UI-SPEC: Rename → Delete → separator → Reveal.

**Delete confirmation AlertDialog pattern** (`ResourceRow.tsx` lines 344–366):
```tsx
<AlertDialog open={confirmOpen} onOpenChange={setConfirmOpen}>
  <AlertDialogContent>
    <AlertDialogHeader>
      <AlertDialogTitle>Delete preset?</AlertDialogTitle>
      <AlertDialogDescription>
        {`Delete ${entry.name}? This removes the file from ${storeName} and cannot be undone.`}
      </AlertDialogDescription>
    </AlertDialogHeader>
    <AlertDialogFooter>
      <AlertDialogCancel>Keep Preset</AlertDialogCancel>
      <AlertDialogAction variant="destructive" onClick={handleConfirmedDelete}>
        Delete Preset
      </AlertDialogAction>
    </AlertDialogFooter>
  </AlertDialogContent>
</AlertDialog>
```
Adaptation: button copy changed to "Keep Preset" / "Delete Preset" per UI-SPEC. Description wording per copywriting contract.

**Drag-from-toolbox pattern** (`ToolboxItem.tsx` lines 20–23):
```tsx
const onDragStart = (event: React.DragEvent) => {
  event.dataTransfer.setData("application/stream-preset", JSON.stringify({ filePath: entry.filePath, store: entry.store }));
  event.dataTransfer.effectAllowed = "move";
};
```
Adaptation: MIME type is `application/stream-preset` (not `application/streamcomponent`); payload is `{ filePath, store }` (not a component ID string).

**Watcher lifecycle pattern** (`gui/src/lib/autoRecover.ts` lines 78–80 `appDataDir + join` pattern adapted to `appConfigDir`):
```tsx
useEffect(() => {
  const unwatchers: UnwatchFn[] = [];
  async function setup() {
    const { appConfigDir, join } = await import("@tauri-apps/api/path");
    const { watch, mkdir } = await import("@tauri-apps/plugin-fs");
    const libDir = await join(await appConfigDir(), "presets");
    await mkdir(libDir, { recursive: true }).catch(() => {});
    await store.refreshPresetsDir("library", libDir);
    const unwatchLib = await watch(libDir,
      () => store.refreshPresetsDir("library", libDir),
      { delayMs: 200 });
    unwatchers.push(unwatchLib);
    if (projDir) {
      await mkdir(projDir, { recursive: true }).catch(() => {});
      await store.refreshPresetsDir("project", projDir);
      const unwatchProj = await watch(projDir,
        () => store.refreshPresetsDir("project", projDir),
        { delayMs: 200 });
      unwatchers.push(unwatchProj);
    }
  }
  setup().catch(console.error);
  return () => { unwatchers.forEach(fn => fn()); };
}, [currentProjectDir]);  // re-runs on project switch (D-06)
```
Pattern origin: `autoRecover.ts` lines 78–80, 116–118 (`appDataDir` → `appConfigDir`; `writeSidecar` → `refreshPresetsDir`). The dependency on `currentProjectDir` (derived from `useStore(s => s.currentFilePath)`) handles D-06 project-switch rebinding.

**Skeleton loading pattern** — no existing analog; minimal implementation:
```tsx
// While watcher initializes (loading === true):
<li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
<li className="h-[22px] bg-muted animate-pulse rounded-sm mx-[8px]" />
```

**Empty state pattern** — no existing analog; two-line copy per UI-SPEC:
```tsx
<div className="px-[8px] py-[4px]">
  <p className="text-xs font-medium text-muted-foreground">No project presets yet.</p>
  <p className="text-xs text-muted-foreground">Multi-select components and right-click to save.</p>
</div>
```

---

### `gui/src/components/SavePresetModal.tsx` (new — component, request-response)

**Analog:** `gui/src/components/AboutDialog.tsx`

**Dialog chrome pattern** (`AboutDialog.tsx` lines 1–61, copy structure):
```tsx
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "./ui/dialog";
import { Button } from "./ui/button";

interface Props {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  // additional: initialSelection: Node[], onSave: (name, desc, store) => void
}

export default function SavePresetModal({ open, onOpenChange, ... }: Props) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Save as Preset</DialogTitle>
        </DialogHeader>
        {/* fields */}
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>Discard</Button>
          <Button variant="default" disabled={!isValid} onClick={handleSave}>Save Preset</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```
Adaptation: `AboutDialog` uses `Button variant="outline"` with label "Close"; SavePresetModal uses `variant="ghost"` / `variant="default"` with "Discard" / "Save Preset". Add Name (Input), Description (Textarea), Store (RadioGroup) field groups.

**Input with validation pattern** (`ResourceRow.tsx` lines 229–261 rename Input):
```tsx
<Input
  value={nameValue}
  onChange={(e) => { setNameValue(e.target.value); validateName(e.target.value); }}
  placeholder="e.g. mtr-fuel-assembly"
  aria-invalid={nameError ? true : undefined}
  className={cn(nameError && "border-destructive ring-destructive/30")}
/>
{nameError && (
  <p className="text-destructive text-xs leading-[1.4]">{nameError}</p>
)}
```
Adaptation: validation is against `PRESET_NAME_RE` + collision check against existing `.scpr` stems in the chosen store (live on keystroke).

**Auto-extended count info text** (no existing analog; per UI-SPEC Surface 9 A-07):
```tsx
{autoExtendedCount > 0 && (
  <p className="text-xs text-muted-foreground">
    {autoExtendedCount} additional component(s) included via BC connections.
  </p>
)}
```

**Focus-on-open pattern** (`ResourceRow.tsx` lines 113–121 useEffect focus pattern):
```tsx
useEffect(() => {
  if (open) {
    const t = setTimeout(() => nameInputRef.current?.focus(), 0);
    return () => clearTimeout(t);
  }
}, [open]);
```

---

### `gui/src/store/__tests__/presetActions.test.ts` (new — test)

**Analog:** `gui/src/store/__tests__/autoRecover.actions.test.ts`

**Tauri mock pattern** (`autoRecover.actions.test.ts` lines 7–41):
```typescript
import { describe, it, expect, vi, beforeEach } from "vitest";
import useStore from "../useStore";

const mockWriteTextFile = vi.fn<(path: string, content: string) => Promise<void>>();
const mockReadTextFile = vi.fn<(path: string) => Promise<string>>();
const mockRemove = vi.fn<(path: string) => Promise<void>>();
const mockReadDir = vi.fn<(path: string) => Promise<{ name: string }[]>>();

vi.mock("@tauri-apps/plugin-fs", () => ({
  writeTextFile: (p: string, c: string) => mockWriteTextFile(p, c),
  readTextFile: (p: string) => mockReadTextFile(p),
  remove: (p: string) => mockRemove(p),
  readDir: (p: string) => mockReadDir(p),
}));
vi.mock("@tauri-apps/api/path", () => ({
  join: (...parts: string[]) => Promise.resolve(parts.join("/")),
  appConfigDir: () => Promise.resolve("/mock/config"),
}));
```
Adaptation: mock the FS functions used by preset actions; mock `@tauri-apps/api/path` for path resolution.

**Store-reset pattern** (`resources.slice.test.ts` lines 10–39):
```typescript
beforeEach(() => {
  useStore.setState({ nodes: [], edges: [], projectPresets: [], libraryPresets: [], isDirty: false });
  vi.clearAllMocks();
});
```

---

## Modified File Pattern Notes

---

### `gui/src/store/useStore.ts` — new `presets` slice

**Where to add:** After line 141 (`export type ActiveLeftTab = ...`).

**Type extension pattern** (line 141):
```typescript
// BEFORE:
export type ActiveLeftTab = "Components" | "Resources" | "Project";
// AFTER:
export type ActiveLeftTab = "Components" | "Resources" | "Project" | "Presets";
```
Note: `projectIO.ts` imports `ActiveLeftTab` FROM `useStore.ts` (line 22 of projectIO.ts) — update the union only in `useStore.ts`; `projectIO.ts` inherits the new type automatically.

**New state fields** — add after existing layout state (near line 887):
```typescript
projectPresets: [] as PresetIndexEntry[],
libraryPresets: [] as PresetIndexEntry[],
```

**New action implementations** — follow `setActiveLeftTab` pattern (line 1809):
```typescript
setProjectPresets: (entries) => set({ projectPresets: entries }),
setLibraryPresets: (entries) => set({ libraryPresets: entries }),
refreshPresetsDir: async (store, dir) => {
  const { readDir, readTextFile } = await import("@tauri-apps/plugin-fs");
  const entries: PresetIndexEntry[] = [];
  try {
    const files = await readDir(dir);
    for (const f of files) {
      if (!f.name?.endsWith(".scpr")) continue;
      try {
        const json = await readTextFile(dir + "/" + f.name);
        const preset = deserializePreset(json);
        entries.push({ name: preset.name, description: preset.description,
          filePath: dir + "/" + f.name, store });
      } catch {
        // per-file: surface toast and skip
      }
    }
  } catch { /* dir may not exist yet */ }
  if (store === "project") set({ projectPresets: entries });
  else set({ libraryPresets: entries });
},
```

**`saveSelectionAsPreset` action** — follows `duplicateResource` pattern (lines 1735–1785, `_pushSnapshot` + `set`):
```typescript
saveSelectionAsPreset: async (name, description, targetStore) => {
  const { nodes, edges } = get();
  const selectedIds = new Set(nodes.filter(n => n.selected).map(n => n.id));
  const { extendedIds, keptEdges } = autoExtendSelection(selectedIds, nodes, edges);
  // ... build preset, serialize, writeTextFile
  // NO _pushSnapshot — file I/O is not an undo-able action
},
```

**`loadPresetAtPosition` action** — follows `pasteFromClipboard` pattern (lines 2015–2068, `oldToNew` map + `crypto.randomUUID()` + `smartParseAndIncrement`):
```typescript
// Clone from pasteFromClipboard lines 2016–2068:
const oldToNew = new Map<string, string>();
const existingNames = new Set(get().nodes.map(n => (n.data as StreamNodeData).instanceName));
const newNodes: Node[] = preset.components.map((srcNode) => {
  const newId = crypto.randomUUID();
  oldToNew.set(srcNode.id, newId);
  const srcData = srcNode.data as StreamNodeData;
  const newName = smartParseAndIncrement(srcData.instanceName, existingNames);
  existingNames.add(newName);
  return { ...srcNode, id: newId, position: computedPosition(srcNode, ...), selected: true,
    data: { ...srcData, instanceName: newName } };
});
// Edge remapping: clone from lines 2049–2061
```

---

### `gui/src/App.tsx` — Ctrl+4 keybind + 4th tab

**Ctrl+4 addition** (`App.tsx` lines 281–302 `handleLeftTabKey` effect):
```tsx
// BEFORE (line 296):
} else if (e.key === "3") {
  e.preventDefault();
  setActiveLeftTab("Project");
}
// AFTER:
} else if (e.key === "3") {
  e.preventDefault();
  setActiveLeftTab("Project");
} else if (e.key === "4") {
  e.preventDefault();
  setActiveLeftTab("Presets");
}
```

**4th tab addition** (`App.tsx` lines 490–513, `onValueChange` cast + `tabs` array + `TabsContent`):
```tsx
// Tabs onValueChange (line 490):
onValueChange={(v) => setActiveLeftTab(v as "Components" | "Resources" | "Project" | "Presets")}

// ResponsiveTabsList tabs array (lines 494–500):
tabs={[
  { value: "Components", label: "Components", icon: Boxes },
  { value: "Resources",  label: "Resources",  icon: Library },
  { value: "Project",    label: "Project",     icon: Settings2 },
  { value: "Presets",    label: "Presets",     icon: BookMarked }, // NEW
]}

// New TabsContent (after line 512):
<TabsContent value="Presets" className="flex-1 min-h-0 overflow-hidden mt-0">
  <PresetsPanel />
</TabsContent>
```
Add `import { Boxes, Library, Settings2, BookMarked } from "lucide-react";` (line 21).

---

### `gui/src/components/FileMenu.tsx` — two new menu items

**Insertion point:** After `MenubarSeparator` (after line 108), before `MenubarItem onClick={handleExportToJulia}`.

**Pattern** (`FileMenu.tsx` lines 108–115, copy MenubarItem shape):
```tsx
<MenubarSeparator />
<MenubarItem onClick={handleLoadPreset}>
  Load preset…
</MenubarItem>
<MenubarItem
  onClick={handleSaveSelectionAsPreset}
  disabled={selectedNodeCount < 2}
>
  Save selection as preset…
</MenubarItem>
<MenubarSeparator />
<MenubarItem onClick={handleExportToJulia} className="text-xs font-normal">
  Export to Julia…
</MenubarItem>
```
Note: no shortcut hints for the two new items (consistent with "Export to Julia…" which also lacks a shortcut hint — line 110).

`selectedNodeCount` from `useStore((s) => s.nodes.filter(n => n.selected).length)`.

For `handleLoadPreset`, the handler needs `getViewport()` from `useReactFlow()` to compute viewport center for D-17 placement. Use:
```tsx
const { getViewport } = useReactFlow();
async function handleLoadPreset() {
  const vp = getViewport();
  const centerX = (-vp.x + window.innerWidth / 2) / vp.zoom;
  const centerY = (-vp.y + window.innerHeight / 2) / vp.zoom;
  await useStore.getState().loadPresetFromPath({ centerX, centerY });
}
```
`FileMenu.tsx` must be rendered inside a `ReactFlowProvider` (it already is — `App.tsx` line 457 wraps the whole tree in `ReactFlowProvider`).

---

### `gui/src/components/canvasMenus/NodeContextMenu.tsx` — "Save selection as preset…"

**Insertion point:** Before `DropdownMenuSeparator` (line 58).

**Pattern** (`NodeContextMenu.tsx` lines 50–63):
```tsx
{/* Visible only when selection count ≥ 2 */}
{useStore.getState().nodes.filter(n => n.selected).length >= 2 && (
  <DropdownMenuItem onSelect={handleSaveSelectionAsPreset}>
    Save selection as preset…
  </DropdownMenuItem>
)}
<DropdownMenuSeparator />
<DropdownMenuItem variant="destructive" onSelect={handleDelete}>
  Delete
</DropdownMenuItem>
```
`handleSaveSelectionAsPreset` opens `SavePresetModal` — dispatch a custom event or set a Zustand flag; prefer a custom event (mirrors the `stream:focus-instance-name` pattern at line 24).

---

### `gui/src-tauri/Cargo.toml` — watch feature flag

**Current** (line 26):
```toml
tauri-plugin-fs = "2.4.5"
```
**After:**
```toml
tauri-plugin-fs = { version = "2.4.5", features = ["watch"] }
```
This is a Rust build change — requires `cargo build` / `tauri dev` restart; hot-reload does NOT pick it up.

---

### `gui/src-tauri/capabilities/default.json` — fs watch + appconfig permissions

**Insertion pattern** (after the existing `fs:allow-read-dir` entry at line 20, mirroring existing `fs:scope` block at lines 20–25):
```json
"fs:allow-watch",
"fs:allow-unwatch",
"fs:scope-appconfig-recursive",
{
  "identifier": "fs:scope",
  "allow": [
    { "path": "$APPCONFIG/presets/**" }
  ]
}
```
`$APPCONFIG` is a confirmed ACL scope variable (RESEARCH.md Q1).

---

### `gui/src/components/StreamNode.tsx` — `data.autoExtended` amber outline

**No existing analog** — new transient visual treatment.

**Implementation sketch** (inspect how `node.selected` renders today; add `data.autoExtended` check alongside):
```tsx
// In StreamNode outer wrapper className:
cn(
  baseNodeClasses,
  node.selected && "ring-2 ring-primary",
  (node.data as StreamNodeData).autoExtended &&
    "outline outline-2 outline-dashed outline-[oklch(0.769_0.188_70.08)] outline-offset-2",
)
```
`data.autoExtended` is a transient boolean — set in the `openSavePresetModal` handler and cleared on `SavePresetModal` `onOpenChange → false`. Must be stripped by `serializeProject` before write (per RESEARCH.md Pitfall 7).

---

## Shared Patterns

### Tauri FS path construction (applies to PresetsPanel, store actions)
**Source:** `gui/src/lib/autoRecover.ts` lines 78–80
```typescript
const { appConfigDir, join } = await import("@tauri-apps/api/path");
const dir = await appConfigDir();
const presetDir = await join(dir, "presets");
```
Apply to: `PresetsPanel.tsx` watcher setup, `saveSelectionAsPreset` store action, `loadPresetFromPath` store action.

### `crypto.randomUUID()` for UUID minting (applies to loadPresetAtPosition)
**Source:** `gui/src/store/useStore.ts` line 1753 + line 2024
```typescript
const newUuid = crypto.randomUUID();
```
Apply to: every component node load and every embedded resource insertion in `loadPresetAtPosition`. No import required (browser-native).

### `smartParseAndIncrement` for name collision (applies to loadPresetAtPosition)
**Source:** `gui/src/lib/clipboard.ts` lines 87–119
```typescript
import { smartParseAndIncrement } from "@/lib/clipboard";
const newName = smartParseAndIncrement(srcData.instanceName, existingNames);
existingNames.add(newName); // keep running set stable across batch
```
Apply to: component name collision in `loadPresetAtPosition`; embedded resource name collision in `loadPresetAtPosition`.

### `oldToNew` UUID remapping for edges (applies to loadPresetAtPosition)
**Source:** `gui/src/store/useStore.ts` lines 2016, 2049–2061
```typescript
const oldToNew = new Map<string, string>();
// ... per node: oldToNew.set(srcNode.id, newId)
const newEdges: Edge[] = preset.connections.flatMap((srcEdge) => {
  const newSource = oldToNew.get(srcEdge.source);
  const newTarget = oldToNew.get(srcEdge.target);
  if (!newSource || !newTarget) return [];
  return [{ ...srcEdge, id: crypto.randomUUID(), source: newSource, target: newTarget }];
});
```
Apply to: `loadPresetAtPosition` store action.

### Resource UUID remapping (applies to loadPresetAtPosition — new, no existing analog)
After building `oldResUuidToNew: Map<string, string>` from embedded resource insertion, remap:
```typescript
// PARAM_KEY_BY_KIND from ResourceRow.tsx lines 58–62:
const PARAM_KEY_BY_KIND = {
  geometry: ["geometry", "geometry_ref"],
  powerShape: ["power_shape", "power_shape_ref"],
};
// Apply remapping to node parameters before placing nodes
```

### Radix Dialog chrome (applies to SavePresetModal)
**Source:** `gui/src/components/AboutDialog.tsx` lines 1–61
```typescript
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "./ui/dialog";
// Controlled: open prop + onOpenChange callback
// ESC closes via Dialog default onOpenChange behavior — no custom handler needed
```
Apply to: `SavePresetModal.tsx` only.

### Vitest node-environment test structure (applies to presetIO.test.ts)
**Source:** `gui/src/lib/__tests__/clipboard.test.ts` lines 1–7
```typescript
import { describe, it, expect } from "vitest";
// No vi.mock needed — presetIO.ts has zero Tauri imports
```
Apply to: `presetIO.test.ts`. Store-action tests (`presetActions.test.ts`) need `vi.mock("@tauri-apps/plugin-fs", ...)`.

---

## No Analog Found

| File / Feature | Reason |
|----------------|--------|
| `watch()` / `UnwatchFn` watcher lifecycle | `tauri-plugin-fs` `watch` export is new to this phase; `autoRecover.ts` uses polling writes, not watches. RESEARCH.md Q1 provides the confirmed API sketch. |
| `data.autoExtended` transient visual outline | No prior "transient node overlay" exists; RESEARCH.md Q9 provides the implementation sketch. |
| `normalizeLayout` bbox normalization | No prior canvas normalization utility exists; pure geometry math, no analog needed. |
| `autoExtendSelection` BC-edge hop | No prior graph-walk selection extension exists; RESEARCH.md Q4 provides the algorithm. |
| Skeleton loading rows | No prior skeleton loading in left-panel tabs. Minimal `animate-pulse bg-muted` implementation. |

---

## Metadata

**Analog search scope:** `gui/src/lib/`, `gui/src/components/`, `gui/src/store/`, `gui/src-tauri/`
**Files read:** 16 source files + 3 test files
**Pattern extraction date:** 2026-05-20

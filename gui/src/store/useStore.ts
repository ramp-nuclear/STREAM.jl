import { create } from "zustand";
import { subscribeWithSelector } from "zustand/middleware";
import {
  Node,
  Edge,
  Connection,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge as rfAddEdge,
  NodeChange,
  EdgeChange,
  MarkerType,
} from "@xyflow/react";
import { getComponent } from "../registry";
import { validateTopology, type TopologyResult } from "../lib/validation";
import {
  bcModeKey,
  type BCModeEntry,
  type BCEdgeData,
} from "@/lib/bcMode";
import type { AnchorEntry } from "@/lib/anchors";
import { defaultSourceValueEntry } from "@/lib/sourceValueEntry";
import {
  serializeProject,
  deserializeProject,
  addToRecent,
} from "../lib/projectIO";
import { type LayerKey, type ActiveLayers, ALL_LAYERS_ON } from "../lib/layers";
import {
  type ClipboardPayload,
  CLIPBOARD_FORMAT_TAG,
  CLIPBOARD_VERSION,
  isClipboardPayload,
  smartParseAndIncrement,
} from "@/lib/clipboard";
import {
  autoExtendSelection,
  deserializePreset,
  normalizeLayout,
  serializePreset,
  isValidPresetName,
  type PresetIndexEntry,
} from "../lib/presetIO";

// ---------------------------------------------------------------------------
// Phase 65 Plan 04: paste-offset counter (B4 lock).
// Reset on copySelection — purely for visual paste offset stacking, NOT identity.
// Independent of duplicateSelection which uses a fixed +20.
// ---------------------------------------------------------------------------
let pasteOffsetIndex = 0;

// ---------------------------------------------------------------------------
// Phase 62 Resources / ModelOptions / Tabs / Selection — types and constants
// ---------------------------------------------------------------------------

/**
 * Sentinel UUID for the "unset" Power Shape (D-26, RESEARCH §"Alternatives Considered").
 * This UUID is baked into the store's initial state as the value `power_shape_ref`
 * carries when the user has not yet picked a real Power Shape. It is NOT serialized
 * into `.scp` directly (the deserialize path re-injects it on load), is NOT shown
 * in the Resources tab Power Shapes group, and is NOT renameable, deletable, or
 * duplicable.
 */
export const SENTINEL_UNSET_POWER_SHAPE = "00000000-0000-0000-0000-000000000000";

/**
 * Sentinel UUID for the single non-editable "light_water" Fluid row. Deterministic
 * constant (rather than runtime-minted) so .scp round-trips that reference the fluid
 * by UUID remain stable across processes / machines / OSes. Phase 62 ships fluids
 * as a placeholder only (single non-editable row) per D-03 + UI-SPEC.
 */
export const SENTINEL_LIGHT_WATER_FLUID = "00000000-0000-0000-0000-000000000001";

const DEFAULT_FLUID = "water";
const DEFAULT_G = 9.80665;
const DEFAULT_SOLVER = {
  abstol: 1e-8,
  reltol: 1e-6,
  dtmax: null as number | null,
};

// Verbatim user-facing copy per 62-UI-SPEC "Power Shape picker — extra fixed top
// entry". Contains a U+2014 em-dash; this is user-facing UI copy, NOT a Julia
// identifier, so the Unicode exception in CLAUDE.md / feedback_ascii_variable_names
// (Julia identifiers only) does not apply.
const SENTINEL_POWER_SHAPE_NAME = "(leave unset — set in code)";

// Julia identifier regex used to validate user-supplied Resource names (per 62
// UI-SPEC popover validation messages; matches §3.5 instance-name rules).
const JULIA_IDENT_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;

export interface GeometryResource {
  uuid: string;
  name: string;
  kind: "rectangular" | "circular";
  params: {
    L: number;
    W?: number;
    H?: number;
    D?: number;
  };
}

export interface PowerShapeResource {
  uuid: string;
  name: string;
  kind: "uniform" | "z_cosine" | "file_loaded" | "unset";
  params: {
    amplitude?: number;
    path?: string;
    /** Set true when load-time file-existence check fails for file_loaded
     * power shape; consumed by SidebarPanel to render the "Locate file..."
     * banner (INV-10 / D-24). Persisted-on-disk flag is implementation-
     * incidental: it is set only at load time and re-cleared on relocate. */
    path_missing?: boolean;
    /** The absolute path that was checked and not found — used by the
     * banner copy. Stored alongside path_missing; cleared on relocate. */
    absolute_path_attempted?: string;
  };
}

export interface FluidResource {
  uuid: string;
  name: string;
}

export type SelectionKind = "none" | "component" | "resource" | "project";

export type SelectedResourceKind = "geometry" | "powerShape" | "fluid" | null;

export interface ResourcesSliceState {
  geometries: Record<string, GeometryResource>;
  powerShapes: Record<string, PowerShapeResource>;
  fluids: Record<string, FluidResource>;
}

export interface ModelOptionsSliceState {
  name: string;
  description: string;
  default_fluid: string;
  g_default: number;
  solver: {
    abstol: number;
    reltol: number;
    dtmax: number | null;
  };
}

export type ActiveLeftTab = "Components" | "Presets" | "Resources" | "Project";

// Snapshot of undoable canvas + resources content (not UI state like selection,
// active tab, or panels). Phase 62 extension: `resources` and `modelOptions` are
// undoable; `activeLeftTab` is NOT (mirrors `selectedNodeId` / `activeLayer`).
// Phase 63 extension: `bcMode`, `bcSymmetric` are undoable — every BC slice
// mutation (setBCMode, clearBCMode, etc.) pushes a snapshot.
// Phase 63.1 D-15: `errorTagsByNodeId` removed from the undoable slice set;
// ring/error state is now derived on demand by selectNodeErrors (no stored
// derived state, so no snapshot field is needed).
// Phase 63.1 D-02 / D-03: legacy boundary-conditions slice removed; the new
// per-node pressure anchor Record (`anchors`) replaces it as the undoable slice.
interface CanvasSnapshot {
  nodes: Node[];
  edges: Edge[];
  anchors: Record<string, AnchorEntry>;
  resources: ResourcesSliceState;
  modelOptions: ModelOptionsSliceState;
  bcMode: Record<string, BCModeEntry>;
  bcSymmetric: Record<string, boolean>;
}

export interface StreamNodeData {
  componentId: string;
  instanceName: string;
  parameters: Record<string, unknown>;
  constructorMode?: string;
  /** Transient flag set by SavePresetModal to paint the amber dashed outline
   * on auto-extended (BC-hop-included) nodes. Cleared on modal close.
   * Stripped by serializeProject before writing to disk (Pitfall 7). */
  autoExtended?: boolean;
}

interface AppState {
  nodes: Node[];
  edges: Edge[];
  selectedNodeId: string | null;
  // Phase 63.1 D-02: per-node pressure anchor Record (replaces legacy
  // boundary-conditions slice). `anchors[nodeId] === undefined` is the
  // canonical "no anchor on that component" sentinel (D-02 at-most-one).
  anchors: Record<string, AnchorEntry>;
  bottomPanelOpen: boolean;
  bottomPanelHeight: number;
  setBottomPanelHeight: (height: number) => void;
  toolboxCollapsed: boolean;
  sidebarCollapsed: boolean;
  setToolboxCollapsed: (collapsed: boolean) => void;
  setSidebarCollapsed: (collapsed: boolean) => void;
  // Topology validation (Phase 39)
  errorNodeIds: Set<string>;
  validationResult: TopologyResult | null;
  validateAndGate: () => TopologyResult;
  clearValidation: () => void;
  // Phase 66 Plan 03: code-panel ephemeral slices (session-only, NOT persisted in .scp).
  //
  // hoveredSourceIds — sub-block hover in CodePreview drives a hover ring on
  //   the matching canvas StreamNode(s). Mirrors the errorNodeIds Set pattern
  //   for primitive-boolean selector subscriptions (Pitfall 1: every mutation
  //   produces a NEW Set reference so Zustand shallow equality fires re-renders).
  // pinnedSourceIds — sub-block click toggles a "sticky" pin ring on the
  //   matching canvas StreamNode(s). D-10 overlap-toggle: any overlap with an
  //   already-pinned id removes ALL of the second sub-block's ids.
  // pendingShowCodeFor — one-shot signal written by useShowCodeFor() when a
  //   `stream:show-code-for` CustomEvent fires; consumed (read + cleared
  //   atomically) by CodePreview on next mount/update to scroll-into-view +
  //   flash the matching sub-blocks. null = no pending request.
  hoveredSourceIds: Set<string>;
  pinnedSourceIds: Set<string>;
  pendingShowCodeFor: string[] | null;
  setHoveredSourceIds: (ids: string[]) => void;
  clearHoveredSourceIds: () => void;
  togglePinnedForSubBlock: (subBlockSourceIds: string[]) => void;
  clearPinnedSourceIds: () => void;
  setPendingShowCodeFor: (ids: string[]) => void;
  consumePendingShowCodeFor: () => string[] | null;
  // Phase 68: 4-layer independent-toggle state (persisted in .scp layout
  // block, NOT in undo stack). Replaces the v0.8 `activeLayer: LayerView`
  // three-mode shape per D-05. See `gui/src/lib/layers.ts` for the LayerKey
  // taxonomy (Hydraulic / Thermal / Sources / ReactorPhysics).
  activeLayers: ActiveLayers;
  hideOffLayer: boolean;
  toggleLayer: (key: LayerKey) => void;
  setLayerVisible: (key: LayerKey, visible: boolean) => void;
  setAllLayersVisible: (visible: boolean) => void;
  setHideOffLayer: (value: boolean) => void;
  // Snap-to-grid (Phase 65 D-10 — persisted in .scp layout block)
  snapToGrid: boolean;
  setSnapToGrid: (v: boolean) => void;
  // Phase 65 Plan 13: viewport interaction lock (session-only, NOT persisted in .scp).
  interactiveLocked: boolean;
  setInteractiveLocked: (v: boolean) => void;
  // Persistence state
  isDirty: boolean;
  currentFilePath: string | null;
  recentFiles: string[];
  // AutoRecover: stable UUID for untitled projects (D-04)
  untitledProjectUuid: string;
  // Undo/redo — explicit history stack, not auto-tracked middleware
  _undoPast: CanvasSnapshot[];
  _undoFuture: CanvasSnapshot[];
  /** Push a snapshot of the current canvas state before a mutation. Call before set(). */
  _pushSnapshot: () => void;
  undo: () => void;
  redo: () => void;
  // Canvas actions
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  selectNode: (nodeId: string | null) => void;
  addNode: (componentId: string, position: { x: number; y: number }) => void;
  removeNode: (nodeId: string) => void;
  addEdge: (connection: Connection) => void;
  removeEdge: (edgeId: string) => void;
  updateNodeParams: (nodeId: string, patch: Partial<StreamNodeData>) => void;
  // Phase 63.1 D-02: anchors slice actions.
  // setAnchor writes anchors[nodeId] = entry under snapshot-before-mutate
  // discipline; calling twice on the same nodeId overwrites (at-most-one).
  // clearAnchor deletes the entry via immutable spread+delete (Pattern B).
  // Replaces the legacy boundary-conditions slice actions.
  setAnchor: (nodeId: string, entry: AnchorEntry) => void;
  clearAnchor: (nodeId: string) => void;
  toggleBottomPanel: () => void;
  // ----- Phase 62: Resources slice -----
  resources: ResourcesSliceState;
  addGeometry: (g: Omit<GeometryResource, "uuid">) => string;
  addPowerShape: (p: Omit<PowerShapeResource, "uuid">) => string;
  renameResource: (
    kind: "geometry" | "powerShape",
    uuid: string,
    newName: string,
  ) => void;
  updateResource: (
    kind: "geometry" | "powerShape",
    uuid: string,
    patch: Partial<GeometryResource> | Partial<PowerShapeResource>,
  ) => void;
  removeResource: (kind: "geometry" | "powerShape", uuid: string) => void;
  duplicateResource: (
    kind: "geometry" | "powerShape",
    uuid: string,
  ) => string;
  // ----- Phase 62: ModelOptions slice -----
  modelOptions: ModelOptionsSliceState;
  setModelOptions: (patch: Partial<ModelOptionsSliceState>) => void;
  // ----- Phase 62: Active left tab (UI state, but persisted in .scp layout) -----
  activeLeftTab: ActiveLeftTab;
  setActiveLeftTab: (tab: ActiveLeftTab) => void;
  // ----- Phase 62: Selection-kind router (D-05) -----
  selectedResourceId: string | null;
  selectedResourceKind: SelectedResourceKind;
  selectionKind: SelectionKind;
  selectResource: (
    uuid: string,
    kind: "geometry" | "powerShape" | "fluid",
  ) => void;
  clearSelection: () => void;
  // ----- Phase 62: INV-10 file-not-found UX for file_loaded PowerShapes -----
  // Populated on loadProjectFromPath when a file_loaded Power Shape's CSV
  // path resolves but does not exist on disk. Cleared on newProject /
  // loadProject start / successful relocate.
  missingFilePowerShapes: Array<{ uuid: string; name: string; pathTried: string }>;
  relocatePowerShapeFile: (uuid: string) => Promise<void>;
  // ----- Phase 63: BCs-tab slice (D-23 single source-of-truth) -----
  // Composite key bcModeKey(componentId, externalInputName) → entry. Absence of
  // a key = required-unset (D-09 sentinel-by-absence, no `{mode: "unset"}`).
  bcMode: Record<string, BCModeEntry>;
  // Composite key `${nodeId}::${baseField}` (e.g., "ch1::T_wall") → symmetric ON/OFF.
  // Default ON per CD-05 (persisted per-component-instance).
  bcSymmetric: Record<string, boolean>;
  // Phase 63.1 D-15: errorTagsByNodeId slice + _checkBCNMismatch action removed.
  // Ring/error state now derives from selectNodeErrors
  // (gui/src/lib/selectors/nodeErrors.ts). Phase 71 will continue extending
  // the selector library — additional validators follow the same pure
  // (state, nodeId) -> string[] shape (D-19 foundation).
  // BC actions
  setBCMode: (
    componentId: string,
    externalInputName: string,
    entry: BCModeEntry,
  ) => void;
  clearBCMode: (componentId: string, externalInputName: string) => void;
  setBCSymmetric: (nodeId: string, baseField: string, symmetric: boolean) => void;
  /** Phase 63.1 D-07 / D-08: hoist "Promote to shared source" from the
   *  BCsTabForm UI into the store. Spawns the corresponding value-source
   *  node (WallTemperature / HeatFluxSource) at (consumer.x - 160,
   *  consumer.y - 40) per RESEARCH §A6, seeds `n` from the consumer so the
   *  brand-new pair is not flagged by the n-mismatch selector, then calls
   *  setBCMode with mode="source" + sourceNodeId — which materializes the
   *  dashed BC edge via the existing setBCMode edge-add branch. No-op when
   *  the consumer node is missing OR the registry's external_inputs entry
   *  has no `source_component`. */
  promoteToSharedSource: (
    consumerNodeId: string,
    externalInputName: string,
  ) => void;
  /** Internal: invoked by onEdgesChange when a `type === "bcEdge"` edge is
   *  removed. Reverts the matching bcMode entry to undefined (required-unset).
   *  Phase 63.1 D-15: tag-clearing logic removed (selectNodeErrors auto-clears
   *  the ring on the next render). NEVER pushes a snapshot — the outer
   *  onEdgesChange does. */
  _revertBCModeForEdge: (edge: Edge) => void;
  // File I/O actions
  saveProject: () => Promise<void>;
  saveProjectAs: () => Promise<void>;
  loadProject: () => Promise<void>;
  loadProjectFromPath: (path: string) => Promise<void>;
  newProject: () => Promise<void>;
  setRecentFiles: (files: string[]) => void;
  // Phase 65 Plan 04: Clipboard actions (D-15, D-16, D-19)
  copySelection: () => Promise<void>;
  cutSelection: () => Promise<void>;
  pasteFromClipboard: () => Promise<void>;
  duplicateSelection: () => void;
  // Phase 65 Plan 08: AutoRecover restore actions (D-03/D-04)
  recoverFromSidecar: (basename: string) => Promise<void>;
  discardAllSidecars: () => Promise<void>;
  // ---------------------------------------------------------------------------
  // Phase 70 Plan 03: Presets slice (D-04, D-06)
  // ---------------------------------------------------------------------------
  projectPresets: PresetIndexEntry[];
  libraryPresets: PresetIndexEntry[];
  setProjectPresets: (entries: PresetIndexEntry[]) => void;
  setLibraryPresets: (entries: PresetIndexEntry[]) => void;
  refreshPresetsDir: (store: "project" | "library", dir: string) => Promise<void>;
  saveSelectionAsPreset: (
    name: string,
    description: string,
    targetStore: "project" | "library",
  ) => Promise<{ filePath: string }>;
  loadPresetAtPosition: (
    filePath: string,
    anchor: { x: number; y: number },
  ) => Promise<void>;
  loadPresetFromPath: (anchor: { x: number; y: number }) => Promise<void>;
  renamePreset: (filePath: string, newName: string) => Promise<void>;
  deletePreset: (filePath: string) => Promise<void>;
}

// ---------------------------------------------------------------------------
// Phase 65 D-17/D-18: Toolbox-drop instance name helper — lowest-free positive
// integer suffix, recomputed from current store state on every request.
// Mirrors nextResourceName (Phase 62) — same algorithm, same contract.
// ASCII-only by construction (per CLAUDE.md / feedback_ascii_variable_names).
// ---------------------------------------------------------------------------
export function nextInstanceName(
  componentId: string,
  existingInstanceNames: Set<string>,
): string {
  const lowerCaseId = componentId.toLowerCase();
  const prefix = `${lowerCaseId}_`;
  for (let i = 1; i < 10_000; i++) {
    const candidate = `${prefix}${i}`;
    if (!existingInstanceNames.has(candidate)) return candidate;
  }
  throw new Error(`nextInstanceName: exhausted candidates for ${componentId}`);
}

// ---------------------------------------------------------------------------
// Phase 62: Resource name helper — lowest-free-positive-integer per kind (D-19)
// ---------------------------------------------------------------------------
//
// Uses *lowest free* rather than *next after highest* so that after deleting
// `geometry_2` and re-creating, the new resource lands at `geometry_2`
// (matches user mental model — D-19).
// ASCII-only by construction (per CLAUDE.md / feedback_ascii_variable_names).
export function nextResourceName(
  kind: "geometry" | "powerShape",
  existingNames: Set<string>,
): string {
  const prefix = kind === "geometry" ? "geometry_" : "power_shape_";
  for (let i = 1; i < 10_000; i++) {
    const candidate = `${prefix}${i}`;
    if (!existingNames.has(candidate)) return candidate;
  }
  // Defensive — unreachable in practice; the loop bound is well above any
  // realistic per-kind resource count.
  throw new Error(`nextResourceName: exhausted candidates for ${kind}`);
}

// ---------------------------------------------------------------------------
// Phase 62: name validation — Julia identifier + per-kind uniqueness
// ---------------------------------------------------------------------------

function validateResourceName(
  kind: "geometry" | "powerShape",
  name: string,
  existing: Record<string, { name: string }>,
  ignoreUuid?: string,
): void {
  if (!JULIA_IDENT_RE.test(name)) {
    // Verbatim UI-SPEC copy (popover validation message).
    throw new Error(
      "Use ASCII letters, digits, and underscores; must not start with a digit.",
    );
  }
  for (const [uuid, rec] of Object.entries(existing)) {
    if (uuid === ignoreUuid) continue;
    if (rec.name === name) {
      const label = kind === "geometry" ? "geometry" : "power shape";
      // Verbatim UI-SPEC copy.
      throw new Error(`A ${label} named ${name} already exists.`);
    }
  }
}

// Derive the selection-kind discriminator from the current selection ids.
// Explicit state synced inside selectNode/selectResource/clearSelection — see
// RESEARCH Pattern 4 (zustand selectors do not auto-recompute on dependents).
function deriveSelectionKind(
  selectedNodeId: string | null,
  selectedResourceId: string | null,
): SelectionKind {
  if (selectedNodeId != null) return "component";
  if (selectedResourceId != null) return "resource";
  return "none";
}

// ---------------------------------------------------------------------------
// recent.json helpers (module-level async, not store actions)
// ---------------------------------------------------------------------------

const RECENT_FILE_NAME = "recent.json";

// ---------------------------------------------------------------------------
// Phase 62: project file extension (.scp) — single source of truth
// ---------------------------------------------------------------------------
// Per RESEARCH "Anti-Patterns", extracting the extension to a constant
// prevents the next renamer from missing a Tauri filter site.
const PROJECT_FILE_EXTENSION = "scp";
const PROJECT_FILE_LABEL = "STREAM Composer Projects";

// Pre-Phase-62-14 hardcoded default; still the fallback when modelOptions.name
// is empty / whitespace / fully sanitized away. Kept as a named constant so a
// future renamer can grep one source of truth.
const FALLBACK_SAVE_AS_FILENAME = `project.${PROJECT_FILE_EXTENSION}` as const;

// Regex for OS-illegal filename characters. Reserved on Windows, problematic
// on POSIX, OR ASCII control range (\x00-\x1f). Stripped at sanitization
// step 2 of computeSaveAsDefaultFilename.
//
// eslint-disable-next-line no-control-regex
const ILLEGAL_FILENAME_CHARS_RE = /[\\/:*?"<>|\x00-\x1f]/g;

/**
 * Derive the default filename passed to the Tauri save() dialog for
 * File → Save As. Sanitizes OS-illegal characters and appends `.scp`
 * exactly once. Empty / whitespace-only / fully-sanitized-empty names
 * fall back to `project.scp` (the pre-Phase-62-14 hardcode).
 *
 * Sanitization order:
 *   1. Trim leading/trailing whitespace.
 *   2. Strip OS-illegal chars: `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, `|`,
 *      and ASCII control characters (\x00-\x1f).
 *   3. Collapse runs of internal whitespace to a single space.
 *   4. Trim again (step 2 can leave whitespace adjacent to stripped chars).
 *   5. Empty result → fall back to `project.scp`.
 *   6. Result already ends with `.scp` (case-insensitive) → return as-is
 *      (preserves original case; do NOT double-append).
 *   7. Otherwise → append `.scp`.
 *
 * Does NOT lowercase, enforce Julia-identifier rules, or strip filename-legal
 * unicode — `modelOptions.name` is a free-form project label per Plan 62-07.
 *
 * Phase 62-14 — closes VERIFICATION.md Critical Gap #3.
 *
 * Exported for unit testing only; not part of the store's public API.
 *
 * @param name Raw `modelOptions.name` from the Model Options form.
 * @returns A filename string suitable for the Tauri save() dialog's
 *          `defaultPath` argument. Always non-empty and always ends in `.scp`
 *          (case-insensitive).
 */
export function computeSaveAsDefaultFilename(name: string): string {
  const trimmed = name.trim();
  if (trimmed.length === 0) return FALLBACK_SAVE_AS_FILENAME;

  const stripped = trimmed
    .replace(ILLEGAL_FILENAME_CHARS_RE, "")
    .replace(/\s+/g, " ")
    .trim();

  if (stripped.length === 0) return FALLBACK_SAVE_AS_FILENAME;

  const ext = `.${PROJECT_FILE_EXTENSION}`;
  if (stripped.toLowerCase().endsWith(ext.toLowerCase())) {
    return stripped;
  }
  return `${stripped}${ext}`;
}

async function loadRecentFiles(): Promise<string[]> {
  try {
    // Dynamic imports to avoid breaking vitest (Tauri APIs unavailable in node env)
    const { appDataDir, join } = await import("@tauri-apps/api/path");
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const dir = await appDataDir();
    const path = await join(dir, RECENT_FILE_NAME);
    const content = await readTextFile(path);
    const parsed = JSON.parse(content) as { files?: string[] };
    return Array.isArray(parsed.files) ? parsed.files : [];
  } catch {
    return [];
  }
}

async function saveRecentFiles(files: string[]): Promise<void> {
  try {
    const { appDataDir, join } = await import("@tauri-apps/api/path");
    const { writeTextFile, mkdir } = await import("@tauri-apps/plugin-fs");
    const dir = await appDataDir();
    await mkdir(dir, { recursive: true });
    const path = await join(dir, RECENT_FILE_NAME);
    await writeTextFile(path, JSON.stringify({ files }, null, 2));
  } catch {
    // Silent failure — don't block user if recent.json write fails
  }
}

// ---------------------------------------------------------------------------
// Phase 62: absolute-path detection (cross-platform)
// ---------------------------------------------------------------------------
function isAbsolutePath(p: string): boolean {
  // Unix absolute -> leading '/'.  Windows absolute -> 'C:\' / 'C:/' style.
  return p.startsWith("/") || /^[A-Za-z]:[\\/]/.test(p);
}

// Compute a relative path from `fromDir` to `toAbs`. The Tauri 2 `path` plugin
// does NOT expose `relative()`, so we do it manually here. Both inputs MUST be
// absolute; mixing styles (Windows / POSIX) is not supported — the function
// normalizes both to POSIX-style forward slashes before walking the segments.
//
// Returns a forward-slash-joined relative path. Falls back to `toAbs` if the
// two paths have no common root (e.g., different Windows drives).
function computeRelativePath(fromDir: string, toAbs: string): string {
  const norm = (s: string) => s.replace(/\\/g, "/").replace(/\/+$/, "");
  const fromParts = norm(fromDir).split("/").filter((p) => p.length > 0);
  const toParts = norm(toAbs).split("/").filter((p) => p.length > 0);

  // Detect Windows-drive divergence (e.g., C:\ vs D:\) — no relative path exists.
  if (
    /^[A-Za-z]:$/.test(fromParts[0] ?? "") &&
    /^[A-Za-z]:$/.test(toParts[0] ?? "") &&
    fromParts[0].toLowerCase() !== toParts[0].toLowerCase()
  ) {
    return toAbs;
  }

  let i = 0;
  while (
    i < fromParts.length &&
    i < toParts.length &&
    fromParts[i] === toParts[i]
  ) {
    i++;
  }
  const ups = new Array(fromParts.length - i).fill("..");
  const downs = toParts.slice(i);
  const segments = [...ups, ...downs];
  return segments.length === 0 ? "." : segments.join("/");
}

// Build a snapshot of powerShapes with file_loaded paths converted from
// absolute -> relative-to-(.scp dirname). Pure: returns a new Record; does
// NOT mutate input. Used at save time per D-24 + RESEARCH Pitfall 5.
async function relativizePowerShapePaths(
  powerShapes: Record<string, PowerShapeResource>,
  scpFilePath: string,
): Promise<Record<string, PowerShapeResource>> {
  const out: Record<string, PowerShapeResource> = {};
  // Lazy-import the Tauri path API so the vitest node env doesn't trip.
  const pathApi = await import("@tauri-apps/api/path");
  const scpDir = await pathApi.dirname(scpFilePath);
  for (const [uuid, ps] of Object.entries(powerShapes)) {
    if (ps.kind !== "file_loaded" || !ps.params.path) {
      out[uuid] = ps;
      continue;
    }
    const p = ps.params.path;
    if (!isAbsolutePath(p)) {
      out[uuid] = ps;
      continue;
    }
    try {
      // Tauri 2's path plugin does not expose relative(); compute manually.
      // If the two paths share no common root (e.g., different Windows drives),
      // computeRelativePath returns the absolute form unchanged.
      const rel = computeRelativePath(scpDir, p);
      out[uuid] = { ...ps, params: { ...ps.params, path: rel } };
    } catch {
      out[uuid] = ps;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// Phase 63 BC slice helpers (private, module-level)
// ---------------------------------------------------------------------------

/** Strip a trailing `_left` / `_right` suffix from an external_input name to
 *  get the base field. e.g. `T_wall_left` → `T_wall`, `q_right` → `q`. If the
 *  name has no `_left`/`_right` suffix, returns it unchanged (defensive). */
function stripSideSuffix(externalInputName: string): string {
  if (externalInputName.endsWith("_left")) {
    return externalInputName.slice(0, -"_left".length);
  }
  if (externalInputName.endsWith("_right")) {
    return externalInputName.slice(0, -"_right".length);
  }
  return externalInputName;
}

/** Return the paired sibling name (`T_wall_left` ↔ `T_wall_right`) by swapping
 *  the `_left`/`_right` suffix. Returns `null` if the name has no such suffix
 *  (e.g., a single-handed BC with no sibling — codegen tolerates this). */
function siblingExternalInputName(externalInputName: string): string | null {
  if (externalInputName.endsWith("_left")) {
    return externalInputName.slice(0, -"_left".length) + "_right";
  }
  if (externalInputName.endsWith("_right")) {
    return externalInputName.slice(0, -"_right".length) + "_left";
  }
  return null;
}

// Phase 63.1 D-15: addTagInPlace / removeTagInPlace helpers removed alongside
// errorTagsByNodeId slice — ring state now derives from selectNodeErrors
// (gui/src/lib/selectors/nodeErrors.ts).

// ---------------------------------------------------------------------------
// _reconcileBCEdgesForBaseField — pure edge reconciliation for a consumer pair
//
// Plan 63.1-12 amend (2026-05-14): the previous per-side helper
// (_reconcileEdgesForBCMode) used `externalInputName` as the bcEdge
// `targetHandle`, which produced two latent bugs:
//   1) When the consumer is bound on T_wall_right but not T_wall_left, the
//      edge was created with targetHandle="T_wall_right" — but the registry
//      only declares ONE BCPort handle per consumer pair (T_wall_left on the
//      bottom edge). ReactFlow then dropped the edge silently.
//   2) In asymmetric mode, changing the left side to a non-source mode
//      removed the edge even though the right side was still source-bound.
//
// New contract:
//   • One bcEdge per (sourceNode, consumer, baseField). targetHandle is
//     ALWAYS the consumer's actual BCPort handle name (e.g. "T_wall_left").
//   • The edge exists iff AT LEAST ONE of the sibling bcMode entries
//     ({base}_left / {base}_right) is in source mode pointing to that
//     sourceNode.
//   • BCEdge.tsx derives the L/R/L+R side tag from bcMode at render time;
//     the edge data is otherwise opaque.
//
// Pure: returns a new edges array; does NOT call set() or _pushSnapshot.
// ---------------------------------------------------------------------------
function _reconcileBCEdgesForBaseField(
  edges: Edge[],
  nodes: Node[],
  consumerNodeId: string,
  baseField: string,
  nextBCMode: Record<string, BCModeEntry>,
): Edge[] {
  const consumerNode = nodes.find((n) => n.id === consumerNodeId);
  if (!consumerNode) return edges;
  const consumerComp = getComponent(
    (consumerNode.data as unknown as StreamNodeData).componentId,
  );
  if (!consumerComp) return edges;
  // Consumer's actual BCPort handle for this pair — registered as
  // `${baseField}_left` on the bottom edge (e.g. T_wall_left on Channel).
  const bcPortHandle = consumerComp.ports.find(
    (p) =>
      p.type === "BCPort" &&
      (p.name === `${baseField}_left` || p.name === baseField),
  );
  if (!bcPortHandle) return edges;
  const targetHandleName = bcPortHandle.name;

  const leftEntry = nextBCMode[bcModeKey(consumerNodeId, `${baseField}_left`)];
  const rightEntry = nextBCMode[bcModeKey(consumerNodeId, `${baseField}_right`)];
  const boundSources = new Set<string>();
  if (leftEntry?.mode === "source" && leftEntry.sourceNodeId) {
    boundSources.add(leftEntry.sourceNodeId);
  }
  if (rightEntry?.mode === "source" && rightEntry.sourceNodeId) {
    boundSources.add(rightEntry.sourceNodeId);
  }

  // Drop any existing bcEdge for this consumer + targetHandle whose source
  // is no longer bound by any side.
  let nextEdges = edges.filter(
    (e) =>
      !(
        e.type === "bcEdge" &&
        e.target === consumerNodeId &&
        e.targetHandle === targetHandleName &&
        !boundSources.has(e.source)
      ),
  );

  // Materialize one bcEdge per bound source (idempotent).
  for (const sourceId of boundSources) {
    const dup = nextEdges.some(
      (e) =>
        e.type === "bcEdge" &&
        e.source === sourceId &&
        e.target === consumerNodeId &&
        e.targetHandle === targetHandleName,
    );
    if (dup) continue;
    const sourceNode = nodes.find((n) => n.id === sourceId);
    if (!sourceNode) continue;
    const sourceComp = getComponent(
      (sourceNode.data as unknown as StreamNodeData).componentId,
    );
    const sourcePort = sourceComp?.ports.find((p) => p.type === "BCPort");
    if (!sourcePort) continue;
    const edgeId = `bce-${sourceId}-${consumerNodeId}-${baseField}-${crypto.randomUUID().slice(0, 8)}`;
    const bcData: BCEdgeData = {
      componentId: consumerNodeId,
      externalInputName: targetHandleName,
      targetSide: "both",
    };
    nextEdges = [
      ...nextEdges,
      {
        id: edgeId,
        source: sourceId,
        sourceHandle: sourcePort.name,
        target: consumerNodeId,
        targetHandle: targetHandleName,
        type: "bcEdge",
        data: bcData as unknown as Record<string, unknown>,
      } as Edge,
    ];
  }

  return nextEdges;
}

// ---------------------------------------------------------------------------
// Edge enrichment: arrowheads for hydraulic edges
// ---------------------------------------------------------------------------

/**
 * Enrich edges with hydraulic arrowheads and custom edge type.
 * Pure function — does NOT call get(). Used by addEdge and loadProjectFromPath.
 */
export function enrichEdges(edges: Edge[], nodes: Node[]): Edge[] {
  // Step 1: Set hydraulicEdge type + arrowhead for hydraulic; strip arrowhead from thermal;
  // assign bcEdge type + BCEdgeData payload for BCPort.
  const typedEdges = edges.map((e) => {
    const srcNode = nodes.find((n) => n.id === e.source);
    if (!srcNode) return e;
    const srcComp = getComponent((srcNode.data as unknown as StreamNodeData).componentId);
    if (!srcComp) return e;
    const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
    if (srcPort?.type === "ThermalPort") {
      // Thermal edge: keep smoothstep, no arrowhead
      const { markerEnd, ...rest } = e as Edge & { markerEnd?: unknown };
      return rest;
    }
    if (srcPort?.type === "BCPort") {
      // Phase 63 BC edge: strip markerEnd, set type "bcEdge", attach BCEdgeData.
      // Preserve any existing data.targetSide (round-trip through .scp load /
      // edge-cycle action); default `both` per D-11.
      const existingData = e.data as BCEdgeData | undefined;
      const { markerEnd, ...rest } = e as Edge & { markerEnd?: unknown };
      const bcData: BCEdgeData = {
        componentId: e.target,
        externalInputName: e.targetHandle ?? "",
        targetSide: existingData?.targetSide ?? "both",
      };
      return {
        ...rest,
        type: "bcEdge",
        data: bcData as unknown as Record<string, unknown>,
      } as Edge;
    }
    // Hydraulic edge: custom type + filled arrowhead
    return {
      ...e,
      type: "hydraulicEdge",
      markerEnd: {
        type: MarkerType.ArrowClosed,
        width: 16,
        height: 16,
        color: "#b1b1b7",
      },
    };
  });

  return typedEdges;
}

// ---------------------------------------------------------------------------
// Store
// ---------------------------------------------------------------------------

const useStore = create<AppState>()(subscribeWithSelector((set, get) => ({
  nodes: [],
  edges: [],
  selectedNodeId: null,
  // Phase 63.1 D-02: anchors Record (replaces legacy boundary-conditions array).
  anchors: {},
  bottomPanelOpen: false,
  bottomPanelHeight: 240,
  setBottomPanelHeight: (height) => set({ bottomPanelHeight: height }),
  toolboxCollapsed: false,
  sidebarCollapsed: false,
  // Topology validation (Phase 39) initial state
  errorNodeIds: new Set<string>(),
  validationResult: null,
  // Phase 66 Plan 03: code-panel ephemeral slices initial state.
  // All three start empty/null. Session-only — NOT serialized to .scp
  // (verified: serializeProject's args list does not include these keys).
  hoveredSourceIds: new Set<string>(),
  pinnedSourceIds: new Set<string>(),
  pendingShowCodeFor: null,
  // Phase 68: 4-layer independent-toggle initial state. Shallow-clone the
  // constant so consumer mutations cannot leak back to ALL_LAYERS_ON.
  activeLayers: { ...ALL_LAYERS_ON },
  hideOffLayer: false,
  // Snap-to-grid initial state (Phase 65 D-10 — OFF by default)
  snapToGrid: false,
  interactiveLocked: false,
  // Persistence initial state
  isDirty: false,
  currentFilePath: null,
  recentFiles: [],
  untitledProjectUuid: crypto.randomUUID(),

  // ---------------------------------------------------------------------------
  // Phase 62: Resources slice (D-09, D-10, D-11, D-26)
  // ---------------------------------------------------------------------------
  // Initial state bakes:
  //   - powerShapes: { [SENTINEL_UNSET_POWER_SHAPE]: <the unset sentinel> }
  //     (the only "unset" PowerShape that ever exists in the store)
  //   - fluids:      { [SENTINEL_LIGHT_WATER_FLUID]: { name: "light_water" } }
  //     (single non-editable placeholder per D-03 + UI-SPEC; Phase 62 OOS for
  //     editable fluids — full multi-fluid lands in v0.6+)
  resources: {
    geometries: {},
    powerShapes: {
      [SENTINEL_UNSET_POWER_SHAPE]: {
        uuid: SENTINEL_UNSET_POWER_SHAPE,
        name: SENTINEL_POWER_SHAPE_NAME,
        kind: "unset",
        params: {},
      },
    },
    fluids: {
      [SENTINEL_LIGHT_WATER_FLUID]: {
        uuid: SENTINEL_LIGHT_WATER_FLUID,
        name: "light_water",
      },
    },
  },

  // ---------------------------------------------------------------------------
  // Phase 62: ModelOptions slice (D-04 + CD-04)
  // ---------------------------------------------------------------------------
  modelOptions: {
    name: "",
    description: "",
    default_fluid: DEFAULT_FLUID,
    g_default: DEFAULT_G,
    solver: { ...DEFAULT_SOLVER },
  },

  // ---------------------------------------------------------------------------
  // Phase 62: Active left tab (D-01, D-08)
  // ---------------------------------------------------------------------------
  activeLeftTab: "Components",

  // ---------------------------------------------------------------------------
  // Phase 62: Selection-kind discriminator (D-05)
  // ---------------------------------------------------------------------------
  selectedResourceId: null,
  selectedResourceKind: null,
  selectionKind: "none",

  // ---------------------------------------------------------------------------
  // Phase 62: INV-10 missing-file PowerShapes (file-not-found UX)
  // ---------------------------------------------------------------------------
  missingFilePowerShapes: [],

  // ---------------------------------------------------------------------------
  // Phase 63: BCs-tab slice initial state (D-23)
  // ---------------------------------------------------------------------------
  // All three slices start empty. `bcMode[key] === undefined` is the canonical
  // required-unset sentinel (D-09 sentinel-by-absence). `bcSymmetric` default
  // ON is encoded by the *consumer* defaulting `(state.bcSymmetric[key] ?? true)`
  // — we do not pre-populate per-(node, baseField) entries because we don't
  // know which keys will exist until the user creates the consumer node.
  bcMode: {},
  bcSymmetric: {},
  // Phase 63.1 D-15: errorTagsByNodeId initial state removed (slice deleted).

  // ---------------------------------------------------------------------------
  // Phase 70 Plan 03: Presets slice initial state (D-04)
  // ---------------------------------------------------------------------------
  projectPresets: [] as PresetIndexEntry[],
  libraryPresets: [] as PresetIndexEntry[],

  // ---------------------------------------------------------------------------
  // Undo / redo — explicit history stack
  //
  // Why not zundo (temporal middleware)? ReactFlow fires many "noise" change
  // events (select, dimensions, intermediate drag positions) that caused
  // spurious history entries and required multiple Ctrl+Z presses.
  // Explicit push-before-mutation is simpler and fully predictable.
  // ---------------------------------------------------------------------------

  _undoPast: [],
  _undoFuture: [],

  _pushSnapshot: () => {
    const {
      nodes,
      edges,
      anchors,
      resources,
      modelOptions,
      bcMode,
      bcSymmetric,
      _undoPast,
    } = get();
    set({
      _undoPast: [
        ..._undoPast,
        {
          nodes,
          edges,
          anchors,
          resources,
          modelOptions,
          bcMode,
          bcSymmetric,
        },
      ].slice(-50),
      _undoFuture: [],
    });
  },

  undo: () => {
    const {
      nodes,
      edges,
      anchors,
      resources,
      modelOptions,
      bcMode,
      bcSymmetric,
      _undoPast,
      _undoFuture,
    } = get();
    if (_undoPast.length === 0) return;
    const prev = _undoPast[_undoPast.length - 1];
    set({
      nodes: prev.nodes,
      edges: prev.edges,
      anchors: prev.anchors,
      resources: prev.resources,
      modelOptions: prev.modelOptions,
      bcMode: prev.bcMode,
      bcSymmetric: prev.bcSymmetric,
      _undoPast: _undoPast.slice(0, -1),
      _undoFuture: [
        {
          nodes,
          edges,
          anchors,
          resources,
          modelOptions,
          bcMode,
          bcSymmetric,
        },
        ..._undoFuture,
      ].slice(0, 50),
      isDirty: true,
      errorNodeIds: new Set<string>(),
      validationResult: null,
    });
  },

  redo: () => {
    const {
      nodes,
      edges,
      anchors,
      resources,
      modelOptions,
      bcMode,
      bcSymmetric,
      _undoPast,
      _undoFuture,
    } = get();
    if (_undoFuture.length === 0) return;
    const next = _undoFuture[0];
    set({
      nodes: next.nodes,
      edges: next.edges,
      anchors: next.anchors,
      resources: next.resources,
      modelOptions: next.modelOptions,
      bcMode: next.bcMode,
      bcSymmetric: next.bcSymmetric,
      _undoPast: [
        ..._undoPast,
        {
          nodes,
          edges,
          anchors,
          resources,
          modelOptions,
          bcMode,
          bcSymmetric,
        },
      ].slice(-50),
      _undoFuture: _undoFuture.slice(1),
      isDirty: true,
      errorNodeIds: new Set<string>(),
      validationResult: null,
    });
  },

  // ---------------------------------------------------------------------------
  // Phase 68: 4-layer independent-toggle actions (persisted in .scp layout
  // block — every setter marks isDirty so saves capture the change).
  // ---------------------------------------------------------------------------

  toggleLayer: (key) =>
    set((state) => ({
      activeLayers: { ...state.activeLayers, [key]: !state.activeLayers[key] },
      isDirty: true,
    })),

  setLayerVisible: (key, visible) =>
    set((state) => ({
      activeLayers: { ...state.activeLayers, [key]: visible },
      isDirty: true,
    })),

  setAllLayersVisible: (visible) =>
    set(() => ({
      activeLayers: {
        Hydraulic: visible,
        Thermal: visible,
        Sources: visible,
        ReactorPhysics: visible,
      },
      isDirty: true,
    })),

  setHideOffLayer: (value) => set({ hideOffLayer: value, isDirty: true }),

  // Phase 65 D-10: snap-to-grid toggle — persisted in .scp layout block
  setSnapToGrid: (v) => set({ snapToGrid: v, isDirty: true }),

  // Phase 65 Plan 13: do NOT set isDirty — session preference, not project state.
  setInteractiveLocked: (v) => set({ interactiveLocked: v }),

  // ---------------------------------------------------------------------------
  // Canvas actions (content-mutating — set isDirty: true)
  // ---------------------------------------------------------------------------

  onNodesChange: (changes) => {
    // D-22: sync selectedNodeId from ReactFlow select events (fixes click-vs-drag
    // stale Properties). Runs BEFORE the isContentless early-return so a pure
    // select batch (which IS contentless from a dirty-doc perspective) still
    // updates the selection. selectNode is a no-op when the id already matches.
    for (const c of changes) {
      if (c.type !== "select") continue;
      if (c.selected) {
        if (get().selectedNodeId !== c.id) {
          get().selectNode(c.id);
        }
      } else {
        // selected:false → clear if this is the currently-selected node.
        if (get().selectedNodeId === c.id) {
          get().selectNode(null);
        }
      }
    }

    // Skip contentless events (selection highlight, layout measurement) — they
    // are not content mutations and must not dirty the document or push history.
    const isContentless = changes.every(
      (c) => c.type === "select" || c.type === "dimensions",
    );
    if (isContentless) {
      set({ nodes: applyNodeChanges(changes, get().nodes) });
      return;
    }

    // Keyboard-delete (Delete/Backspace on selected node): snapshot before removal.
    if (changes.some((c) => c.type === "remove")) {
      get()._pushSnapshot();
    }

    set({ nodes: applyNodeChanges(changes, get().nodes), isDirty: true });
  },

  onEdgesChange: (changes) => {
    const isContentless = changes.every((c) => c.type === "select");
    if (isContentless) return;

    // Keyboard-delete on selected edge: snapshot before removal.
    if (changes.some((c) => c.type === "remove")) {
      get()._pushSnapshot();
    }

    // Phase 63 D-23 bidirectional sync: when a `type === "bcEdge"` edge is
    // removed (via keyboard delete or programmatically), revert the matching
    // bcMode entry to undefined (required-unset) and clear bc-n-mismatch tags.
    // Must run BEFORE applyEdgeChanges so we can read the about-to-be-removed
    // edge from the current edges list.
    const currentEdges = get().edges;
    for (const c of changes) {
      if (c.type !== "remove") continue;
      const removedEdge = currentEdges.find((e) => e.id === c.id);
      if (!removedEdge) continue;
      if (removedEdge.type === "bcEdge") {
        get()._revertBCModeForEdge(removedEdge);
      }
    }

    set({ edges: applyEdgeChanges(changes, get().edges), isDirty: true });
  },

  // selectNode is NOT content-mutating — do NOT set isDirty.
  // Phase 62 D-05: selection scopes are exclusive — selecting a canvas node
  // clears the resource selection (and vice-versa in selectResource).
  selectNode: (nodeId) =>
    set({
      selectedNodeId: nodeId,
      selectedResourceId: null,
      selectedResourceKind: null,
      selectionKind: deriveSelectionKind(nodeId, null),
    }),

  addNode: (componentId, position) => {
    get()._pushSnapshot();
    const id = crypto.randomUUID();
    const component = getComponent(componentId);
    const defaultParams: Record<string, unknown> = {};
    if (component) {
      for (const param of component.parameters) {
        if (param.default !== undefined && param.default !== null) {
          defaultParams[param.name] = param.default;
        }
      }
    }
    const defaultMode =
      component?.constructorModes[0]?.mode ?? "default";
    const existing = new Set(
      get().nodes.map((n) => (n.data as unknown as StreamNodeData).instanceName),
    );
    const newNode: Node = {
      id,
      type: "streamNode",
      position,
      data: {
        componentId,
        instanceName: nextInstanceName(componentId, existing),
        parameters: defaultParams,
        constructorMode: defaultMode,
      } satisfies StreamNodeData,
    };
    set({ nodes: [...get().nodes, newNode], isDirty: true });
  },

  updateNodeParams: (nodeId, patch) => {
    get()._pushSnapshot();
    const { nodes } = get();
    set({
      nodes: nodes.map((n) => {
        if (n.id !== nodeId) return n;
        const data = n.data as unknown as StreamNodeData;
        return {
          ...n,
          data: {
            ...data,
            ...(patch.instanceName !== undefined && {
              instanceName: patch.instanceName,
            }),
            ...(patch.constructorMode !== undefined && {
              constructorMode: patch.constructorMode,
            }),
            ...(patch.parameters !== undefined && {
              parameters: { ...data.parameters, ...patch.parameters },
            }),
          },
        };
      }),
      isDirty: true,
    });
  },

  removeNode: (nodeId) => {
    get()._pushSnapshot();
    const { nodes, edges, anchors, selectedNodeId, selectedResourceId } = get();
    const clearedSelectedNode = selectedNodeId === nodeId ? null : selectedNodeId;
    // Phase 63.1 D-02: purge any pressure anchor on the deleted node so the
    // anchors Record never carries orphan entries (mirrors clearAnchor's
    // immutable spread+delete idiom — Pattern B). Replaces the legacy
    // boundary-conditions filter that previously lived at this site.
    const nextAnchors: Record<string, AnchorEntry> = { ...anchors };
    delete nextAnchors[nodeId];
    set({
      nodes: nodes.filter((n) => n.id !== nodeId),
      edges: edges.filter(
        (e) => e.source !== nodeId && e.target !== nodeId,
      ),
      anchors: nextAnchors,
      selectedNodeId: null,
      selectionKind: deriveSelectionKind(clearedSelectedNode, selectedResourceId),
      isDirty: true,
    });
  },

  addEdge: (connection) => {
    get()._pushSnapshot();
    const newEdges = rfAddEdge(connection, get().edges);

    // Apply thermal edge styling (per D-03, UI-SPEC): amber dashed for ThermalPort edges
    const styledEdges = newEdges.map((e) => {
      // Only style edges that don't already have a style (the newly added one)
      if (e.style) return e;
      // Check if this edge connects ThermalPorts
      const srcNode = get().nodes.find((n) => n.id === e.source);
      const tgtNode = get().nodes.find((n) => n.id === e.target);
      if (!srcNode || !tgtNode) return e;
      const srcComp = getComponent((srcNode.data as unknown as StreamNodeData).componentId);
      const tgtComp = getComponent((tgtNode.data as unknown as StreamNodeData).componentId);
      if (!srcComp || !tgtComp) return e;
      const srcPort = srcComp.ports.find((p) => p.name === e.sourceHandle);
      const tgtPort = tgtComp.ports.find((p) => p.name === e.targetHandle);
      if (srcPort?.type === "ThermalPort" && tgtPort?.type === "ThermalPort") {
        return { ...e, style: { stroke: "#f59e0b", strokeDasharray: "6 3" } };
      }
      return e;
    });

    // Apply hydraulic arrowheads and parallel offset for bidirectional pairs
    const finalEdges = enrichEdges(styledEdges, get().nodes);

    // Phase 63 D-22 / 63.1 D-15 — canvas-drag BCPort branch. enrichEdges has
    // just assigned `type: "bcEdge"` for BCPort sources. Ring/error state for
    // any n-mismatch is now derived by selectNodeErrors on next render — no
    // per-event mutation needed here (D-15 selector-derived validator).
    if (connection.source && connection.target) {
      const srcNode = get().nodes.find((n) => n.id === connection.source);
      if (srcNode) {
        const srcComp = getComponent(
          (srcNode.data as unknown as StreamNodeData).componentId,
        );
        const srcPort = srcComp?.ports.find((p) => p.name === connection.sourceHandle);
        if (srcPort?.type === "BCPort") {
          // CR-01 (D-20): materialize bcMode on canvas-drag — without this
          // the visible BC edge has no backing bcMode entry, so codegen and
          // any re-render diverge from the canvas. Mirrors setBCMode's
          // symmetric-mirror rule (default ON): when the dropped target is
          // `${base}_left` the sibling `${base}_right` key is also seeded.
          if (connection.targetHandle) {
            const key = bcModeKey(connection.target, connection.targetHandle);
            const baseField = stripSideSuffix(connection.targetHandle);
            const symKey = `${connection.target}::${baseField}`;
            const symmetric = get().bcSymmetric[symKey] ?? true;
            const siblingName = symmetric
              ? siblingExternalInputName(connection.targetHandle)
              : null;
            const entry: BCModeEntry = {
              mode: "source",
              sourceNodeId: connection.source,
            };
            const nextBCMode: Record<string, BCModeEntry> = {
              ...get().bcMode,
              [key]: entry,
            };
            if (siblingName) {
              nextBCMode[bcModeKey(connection.target, siblingName)] = entry;
            }
            set({ edges: finalEdges, isDirty: true, bcMode: nextBCMode });
          } else {
            set({ edges: finalEdges, isDirty: true });
          }
          return;
        }
      }
    }

    const { errorNodeIds } = get();

    if (errorNodeIds.size > 0) {
      const updatedErrors = new Set(errorNodeIds);
      for (const nodeId of [connection.source, connection.target]) {
        if (!nodeId || !updatedErrors.has(nodeId)) continue;
        const node = get().nodes.find((n) => n.id === nodeId);
        if (!node) continue;
        const data = node.data as { componentId: string };
        const def = getComponent(data.componentId);
        if (!def) continue;
        const flowPorts = def.ports.filter((p) => p.type === "FlowPort");
        const allConnected = flowPorts.every((port) => {
          const isInput = port.name.includes("in");
          return finalEdges.some((e) =>
            isInput
              ? e.target === nodeId && e.targetHandle === port.name
              : e.source === nodeId && e.sourceHandle === port.name,
          );
        });
        if (allConnected) updatedErrors.delete(nodeId);
      }
      set({ edges: finalEdges, isDirty: true, errorNodeIds: updatedErrors });
    } else {
      set({ edges: finalEdges, isDirty: true });
    }
  },

  removeEdge: (edgeId) => {
    get()._pushSnapshot();
    const edges = get().edges.filter((e) => e.id !== edgeId);
    set({ edges, isDirty: true });
  },

  // Phase 63.1 D-02 / D-03: anchors slice actions (replace the legacy
  // boundary-conditions slice actions, which are physically removed).
  // Snapshot-before-mutate discipline (Pattern A); at-most-one per nodeId so
  // setAnchor on an existing key overwrites without dedup logic.
  setAnchor: (nodeId, entry) => {
    get()._pushSnapshot();
    set({
      anchors: { ...get().anchors, [nodeId]: entry },
      isDirty: true,
    });
  },

  clearAnchor: (nodeId) => {
    get()._pushSnapshot();
    const next = { ...get().anchors };
    delete next[nodeId];
    set({ anchors: next, isDirty: true });
  },

  // ---------------------------------------------------------------------------
  // Phase 63: BCs-tab slice actions (D-23 bidirectional sync)
  //
  // Every BC mutation MUST call _pushSnapshot() BEFORE set(...) — mirrors the
  // Phase 62 Resources slice discipline. `_revertBCModeForEdge` is the lone
  // exception (called from onEdgesChange which already pushed a snapshot).
  // ---------------------------------------------------------------------------

  setBCMode: (componentId, externalInputName, entry) => {
    get()._pushSnapshot();
    const state = get();
    const key = bcModeKey(componentId, externalInputName);
    const baseField = stripSideSuffix(externalInputName);
    // Default symmetric ON (CD-05). Consumer reads `bcSymmetric[symKey] ?? true`.
    const symKey = `${componentId}::${baseField}`;
    const symmetric = state.bcSymmetric[symKey] ?? true;
    const siblingName = symmetric ? siblingExternalInputName(externalInputName) : null;
    const siblingKey = siblingName ? bcModeKey(componentId, siblingName) : null;

    // Compute new bcMode map.
    const previous = state.bcMode[key];
    const nextBCMode: Record<string, BCModeEntry> = {
      ...state.bcMode,
      [key]: entry,
    };
    if (siblingKey) {
      nextBCMode[siblingKey] = entry;
    }

    // Plan 63.1-12 amend: reconcile edges per (consumer, baseField) ONCE
    // using the consumer's BCPort handle (not the per-side externalInputName).
    // This keeps the edge alive whenever ANY sibling is source-bound and
    // routes it to the consumer's actual ReactFlow handle.
    // (`previous` is intentionally unread now — the new helper reads the full
    // post-mutation bcMode and reconciles strictly by current binding state.)
    void previous;
    const nextEdges = _reconcileBCEdgesForBaseField(
      state.edges,
      state.nodes,
      componentId,
      baseField,
      nextBCMode,
    );

    set({ bcMode: nextBCMode, edges: nextEdges, isDirty: true });
    // Phase 63.1 D-15: no _checkBCNMismatch call — selectNodeErrors recomputes
    // the bc-n-mismatch tag from nodes + bcMode on next render.
  },

  clearBCMode: (componentId, externalInputName) => {
    get()._pushSnapshot();
    const state = get();
    const key = bcModeKey(componentId, externalInputName);
    const baseField = stripSideSuffix(externalInputName);
    const symKey = `${componentId}::${baseField}`;
    const symmetric = state.bcSymmetric[symKey] ?? true;
    const siblingName = symmetric ? siblingExternalInputName(externalInputName) : null;
    const siblingKey = siblingName ? bcModeKey(componentId, siblingName) : null;

    // Remove the bcMode entry (and sibling).
    const nextBCMode: Record<string, BCModeEntry> = { ...state.bcMode };
    delete nextBCMode[key];
    if (siblingKey) delete nextBCMode[siblingKey];

    // Remove any BC edge whose target matches this consumer + handle(s).
    const handlesToRemove = new Set<string>([externalInputName]);
    if (siblingName) handlesToRemove.add(siblingName);
    const nextEdges = state.edges.filter(
      (e) =>
        !(
          e.type === "bcEdge" &&
          e.target === componentId &&
          handlesToRemove.has(e.targetHandle ?? "")
        ),
    );

    // Phase 63.1 D-15: bc-n-mismatch tag-clearing logic removed — selectNodeErrors
    // re-derives the tag set from `bcMode` on the next render, so once the
    // source-mode entry is gone the tag stops appearing.

    set({
      bcMode: nextBCMode,
      edges: nextEdges,
      isDirty: true,
    });
  },

  // Phase 63.1 D-07 / D-08: promote inline external-input binding to a shared
  // canvas value-source node. Hoisted verbatim from BCsTabForm.handleNewSource
  // (Plan 63-C) so the operation is a single store action. Snapshot discipline
  // follows Pattern A — the action itself does not push a snapshot at the top:
  // both `addNode` and `setBCMode` push their own. That yields two undo steps
  // for one Promote click, which behaves correctly (Ctrl+Z first reverts the
  // BC-mode dispatch, a second Ctrl+Z reverts the spawn + n-seed). Plan notes
  // a future refactor may suppress the inner snapshots — out of scope here.
  promoteToSharedSource: (consumerNodeId, externalInputName) => {
    const state = get();
    const consumer = state.nodes.find((n) => n.id === consumerNodeId);
    if (!consumer) return;
    const consumerData = consumer.data as unknown as StreamNodeData;
    const consumerComp = getComponent(consumerData.componentId);
    const sourceCompId = consumerComp?.external_inputs?.find(
      (e) => e.name === externalInputName,
    )?.source_component;
    if (!sourceCompId) return;

    // Spawn the value-source node. addNode currently returns void (RESEARCH
    // A2); identify the freshly-added node by diffing pre/post id sets — the
    // proven shape from the hoisted BCsTabForm.handleNewSource. RESEARCH §A6
    // pins the spawn offset to (-160, -40) so the new node clears the
    // consumer's bounding box without colliding with the legacy `+ New`
    // button's `-120, 0` slot (now removed in Task 2).
    const beforeIds = new Set(state.nodes.map((n) => n.id));
    get().addNode(sourceCompId, {
      x: consumer.position.x - 160,
      y: consumer.position.y - 40,
    });
    const afterNodes = get().nodes;
    const newNode = afterNodes.find((n) => !beforeIds.has(n.id));
    if (!newNode) return;

    // Seed n on the new source-block from the consumer FIRST so the subsequent
    // setBCMode (which materializes the BC edge) does NOT flag the brand-new
    // pair as mismatched (D-20 explicit; selectNodeErrors derives the
    // bc-n-mismatch tag from `nodes + bcMode`).
    //
    // GAP-RC-3 (Plan 63.1-13): also seed the type_union scalar value parameter
    // with a physically benign neutral default so the freshly-spawned source's
    // canvas label reads as muted-gray ("T_wall = 300 K") rather than
    // destructive-red "(unset)" before any user input. The user can immediately
    // override via the Properties panel (Plan 11 RC-1 closure).
    //   T_wall = 300.0 K — room temperature, clearly a placeholder.
    //   q     = 0.0 W/m² — natural "no-source" default for HFS.
    // Plan 63.1-14 (GAP-RC-4): seed as SourceValueEntry { mode:"value", value:N }
    // so the spawned source stores the new entry shape from first write.
    const SOURCE_DEFAULT_SEED: Record<string, Record<string, unknown>> = {
      WallTemperature: { T_wall: defaultSourceValueEntry(300.0) },
      HeatFluxSource: { q: defaultSourceValueEntry(0.0) },
    };
    const valueSeed = SOURCE_DEFAULT_SEED[sourceCompId] ?? {};
    const consumerN =
      (consumerData.parameters?.n as number | undefined) ?? 1;
    get().updateNodeParams(newNode.id, {
      parameters: { n: consumerN, ...valueSeed },
    });

    // setBCMode internally materializes the dashed BC edge via its
    // edge-materialization branch (useStore.ts §setBCMode L1144-1186). It
    // also honors the symmetric-mirror discipline — if `bcSymmetric` is ON,
    // the sibling external input gets the same source-mode entry + edge.
    get().setBCMode(consumerNodeId, externalInputName, {
      mode: "source",
      sourceNodeId: newNode.id,
    });
  },

  setBCSymmetric: (nodeId, baseField, symmetric) => {
    get()._pushSnapshot();
    const state = get();
    const symKey = `${nodeId}::${baseField}`;
    const nextBCSymmetric: Record<string, boolean> = {
      ...state.bcSymmetric,
      [symKey]: symmetric,
    };
    let nextBCMode = state.bcMode;
    let nextEdges = state.edges;

    if (symmetric) {
      // Plan 63.1-10 + 63.1-12 amend: when symmetric flips ON, reconcile the
      // pair so both sibling bcMode entries agree, then run a single
      // per-baseField edge reconciliation.
      //   CR-02 (D-21): leftEntry undefined + rightEntry defined → collapse
      //                 to "neither set".
      //   CR-03 (D-21): leftEntry defined + leftEntry !== rightEntry → mirror
      //                 left → right.
      const leftKey = bcModeKey(nodeId, `${baseField}_left`);
      const rightKey = bcModeKey(nodeId, `${baseField}_right`);
      const leftEntry = state.bcMode[leftKey];
      const rightEntry = state.bcMode[rightKey];

      if (leftEntry === undefined && rightEntry !== undefined) {
        const nbm = { ...state.bcMode };
        delete nbm[rightKey];
        nextBCMode = nbm;
      } else if (leftEntry !== undefined && leftEntry !== rightEntry) {
        nextBCMode = { ...state.bcMode, [rightKey]: leftEntry };
      }
    }

    nextEdges = _reconcileBCEdgesForBaseField(
      nextEdges,
      state.nodes,
      nodeId,
      baseField,
      nextBCMode,
    );

    set({
      bcMode: nextBCMode,
      bcSymmetric: nextBCSymmetric,
      edges: nextEdges,
      isDirty: true,
    });
  },

  // cycleBCEdgeTargetSide retired in Plan 63.1-12 amend (2026-05-14).
  // BCEdge side tag is now a pure derived render from bcMode; BCs tab is
  // the single source of truth for BC state.

  _revertBCModeForEdge: (edge) => {
    if (edge.type !== "bcEdge") return;
    const state = get();
    const data = edge.data as BCEdgeData | undefined;
    if (!data) return;
    const { componentId, externalInputName } = data;
    const key = bcModeKey(componentId, externalInputName);
    const baseField = stripSideSuffix(externalInputName);
    const symKey = `${componentId}::${baseField}`;
    const symmetric = state.bcSymmetric[symKey] ?? true;
    const siblingName = symmetric ? siblingExternalInputName(externalInputName) : null;
    const siblingKey = siblingName ? bcModeKey(componentId, siblingName) : null;

    const nextBCMode: Record<string, BCModeEntry> = { ...state.bcMode };
    delete nextBCMode[key];
    if (siblingKey) delete nextBCMode[siblingKey];

    // Phase 63.1 D-15: tag-clearing logic removed — selectNodeErrors
    // re-derives bc-n-mismatch from `bcMode` on next render.

    set({ bcMode: nextBCMode });
  },

  // ---------------------------------------------------------------------------
  // Phase 62: Resources slice actions (D-09..D-13, D-26)
  //
  // Every Resource mutation MUST call _pushSnapshot() BEFORE the set(...) —
  // RESEARCH Pitfall 2 (snapshot omitted on rename caused undo regressions).
  // ---------------------------------------------------------------------------

  addGeometry: (g) => {
    const { resources } = get();
    validateResourceName("geometry", g.name, resources.geometries);
    get()._pushSnapshot();
    const uuid = crypto.randomUUID();
    const newRecord: GeometryResource = { uuid, ...g };
    set({
      resources: {
        ...resources,
        geometries: { ...resources.geometries, [uuid]: newRecord },
      },
      isDirty: true,
    });
    return uuid;
  },

  addPowerShape: (p) => {
    if (p.kind === "unset") {
      // D-26: the "unset" kind is reserved for the sentinel; users may not
      // create another. Pickable user kinds are uniform | z_cosine | file_loaded.
      throw new Error(
        "Cannot create a Power Shape with kind \"unset\"; the unset sentinel is built-in.",
      );
    }
    const { resources } = get();
    validateResourceName("powerShape", p.name, resources.powerShapes);
    get()._pushSnapshot();
    const uuid = crypto.randomUUID();
    const newRecord: PowerShapeResource = { uuid, ...p };
    set({
      resources: {
        ...resources,
        powerShapes: { ...resources.powerShapes, [uuid]: newRecord },
      },
      isDirty: true,
    });
    return uuid;
  },

  renameResource: (kind, uuid, newName) => {
    if (kind === "powerShape" && uuid === SENTINEL_UNSET_POWER_SHAPE) {
      // D-26: sentinel is uneditable. No-op rather than throw (UI never
      // surfaces a rename affordance on the sentinel row in the first place).
      return;
    }
    const { resources } = get();
    const bucket =
      kind === "geometry" ? resources.geometries : resources.powerShapes;
    const existing = bucket[uuid];
    if (!existing) return; // unknown uuid — silently no-op
    validateResourceName(kind, newName, bucket, uuid);
    get()._pushSnapshot();
    const updated = { ...existing, name: newName };
    if (kind === "geometry") {
      set({
        resources: {
          ...resources,
          geometries: { ...resources.geometries, [uuid]: updated as GeometryResource },
        },
        isDirty: true,
      });
    } else {
      set({
        resources: {
          ...resources,
          powerShapes: {
            ...resources.powerShapes,
            [uuid]: updated as PowerShapeResource,
          },
        },
        isDirty: true,
      });
    }
  },

  updateResource: (kind, uuid, patch) => {
    if (kind === "powerShape" && uuid === SENTINEL_UNSET_POWER_SHAPE) {
      // D-26: sentinel is uneditable.
      return;
    }
    const { resources } = get();
    const bucket =
      kind === "geometry" ? resources.geometries : resources.powerShapes;
    const existing = bucket[uuid];
    if (!existing) return;
    // If the patch contains a name change, validate it. (Name change via
    // updateResource is unusual — the standard path is renameResource — but the
    // popover form may submit a unified patch.)
    if ("name" in patch && typeof patch.name === "string" && patch.name !== existing.name) {
      validateResourceName(kind, patch.name, bucket, uuid);
    }
    get()._pushSnapshot();
    const merged = { ...existing, ...patch, uuid };
    if (kind === "geometry") {
      set({
        resources: {
          ...resources,
          geometries: { ...resources.geometries, [uuid]: merged as GeometryResource },
        },
        isDirty: true,
      });
    } else {
      set({
        resources: {
          ...resources,
          powerShapes: {
            ...resources.powerShapes,
            [uuid]: merged as PowerShapeResource,
          },
        },
        isDirty: true,
      });
    }
  },

  removeResource: (kind, uuid) => {
    if (kind === "powerShape" && uuid === SENTINEL_UNSET_POWER_SHAPE) {
      // D-26: sentinel cannot be removed. No-op.
      return;
    }
    const { resources } = get();
    const bucket =
      kind === "geometry" ? resources.geometries : resources.powerShapes;
    if (!bucket[uuid]) return;
    get()._pushSnapshot();
    if (kind === "geometry") {
      const { [uuid]: _removed, ...rest } = resources.geometries;
      void _removed;
      set({
        resources: { ...resources, geometries: rest },
        isDirty: true,
      });
    } else {
      const { [uuid]: _removed, ...rest } = resources.powerShapes;
      void _removed;
      set({
        resources: { ...resources, powerShapes: rest },
        isDirty: true,
      });
    }
  },

  duplicateResource: (kind, uuid) => {
    if (kind === "powerShape" && uuid === SENTINEL_UNSET_POWER_SHAPE) {
      // D-26: the sentinel cannot be duplicated. Throw so the caller surfaces
      // a useful error rather than silently returning an empty string.
      throw new Error("The unset Power Shape sentinel cannot be duplicated.");
    }
    const { resources } = get();
    const bucket =
      kind === "geometry" ? resources.geometries : resources.powerShapes;
    const existing = bucket[uuid];
    if (!existing) {
      throw new Error(`duplicateResource: unknown ${kind} uuid ${uuid}`);
    }
    // Smart-name-increment per D-19 — lowest-free positive integer in the same
    // namespace as the source name's kind.
    const existingNames = new Set(Object.values(bucket).map((r) => r.name));
    const newName = nextResourceName(kind, existingNames);
    get()._pushSnapshot();
    const newUuid = crypto.randomUUID();
    if (kind === "geometry") {
      const src = existing as GeometryResource;
      const copy: GeometryResource = {
        uuid: newUuid,
        name: newName,
        kind: src.kind,
        params: { ...src.params },
      };
      set({
        resources: {
          ...resources,
          geometries: { ...resources.geometries, [newUuid]: copy },
        },
        isDirty: true,
      });
    } else {
      const src = existing as PowerShapeResource;
      const copy: PowerShapeResource = {
        uuid: newUuid,
        name: newName,
        kind: src.kind,
        params: { ...src.params },
      };
      set({
        resources: {
          ...resources,
          powerShapes: { ...resources.powerShapes, [newUuid]: copy },
        },
        isDirty: true,
      });
    }
    return newUuid;
  },

  // ---------------------------------------------------------------------------
  // Phase 62: ModelOptions slice actions (D-04 + CD-04)
  // ---------------------------------------------------------------------------

  setModelOptions: (patch) => {
    get()._pushSnapshot();
    const { modelOptions } = get();
    set({
      modelOptions: { ...modelOptions, ...patch },
      isDirty: true,
    });
  },

  // ---------------------------------------------------------------------------
  // Phase 62: Active left tab (D-01, D-08)
  // ---------------------------------------------------------------------------
  //
  // Per D-29 + RESEARCH §Cross-Cutting Invariants: layout edits are persisted in
  // the .scp `layout` block but NOT pushed into the undo stack (UI state, not
  // content state). `setActiveLeftTab` DOES set isDirty: true because the saved
  // active tab differs from what's on disk.
  setActiveLeftTab: (tab) => set({ activeLeftTab: tab, isDirty: true }),

  // ---------------------------------------------------------------------------
  // Phase 62: Selection-kind router (D-05)
  // ---------------------------------------------------------------------------

  selectResource: (uuid, kind) =>
    set({
      selectedResourceId: uuid,
      selectedResourceKind: kind,
      selectedNodeId: null,
      selectionKind: deriveSelectionKind(null, uuid),
    }),

  clearSelection: () =>
    set({
      selectedNodeId: null,
      selectedResourceId: null,
      selectedResourceKind: null,
      selectionKind: "none",
    }),

  // toggleBottomPanel is NOT content-mutating — do NOT set isDirty
  toggleBottomPanel: () => set({ bottomPanelOpen: !get().bottomPanelOpen }),

  // ---------------------------------------------------------------------------
  // Topology validation (Phase 39)
  // ---------------------------------------------------------------------------

  validateAndGate: () => {
    const { nodes, edges, anchors } = get();
    // 63.1-04: anchors slice replaces the legacy boundary-conditions array
    // for the export gate. validateTopology now takes the anchors Record
    // directly and checks `Object.keys(anchors).length === 0` to surface the
    // "No pressure boundary condition" SystemError.
    const result = validateTopology(nodes, edges, anchors, getComponent);
    const errorIds = new Set(result.nodeErrors.map((e) => e.nodeId));
    set({ errorNodeIds: errorIds, validationResult: result });
    return result;
  },

  clearValidation: () => {
    set({ errorNodeIds: new Set<string>(), validationResult: null });
  },

  // ---------------------------------------------------------------------------
  // Phase 66 Plan 03: code-panel ephemeral actions
  //
  // Every mutation produces a NEW Set / array reference (Pitfall 1 — in-place
  // mutation would keep the same reference, Zustand's shallow equality
  // returns true, and subscribed components would never re-render).
  // Session-only — none of these set isDirty.
  // ---------------------------------------------------------------------------

  setHoveredSourceIds: (ids) =>
    set({ hoveredSourceIds: new Set(ids) }),

  clearHoveredSourceIds: () =>
    set({ hoveredSourceIds: new Set<string>() }),

  togglePinnedForSubBlock: (subBlockSourceIds) =>
    set((s) => {
      const next = new Set(s.pinnedSourceIds);
      // CONTEXT D-10: any overlap with currently-pinned ids → remove ALL of
      // this sub-block's ids (overlap-removes-all). Otherwise → add ALL.
      const anyPinned = subBlockSourceIds.some((id) => next.has(id));
      if (anyPinned) {
        for (const id of subBlockSourceIds) next.delete(id);
      } else {
        for (const id of subBlockSourceIds) next.add(id);
      }
      return { pinnedSourceIds: next };
    }),

  clearPinnedSourceIds: () =>
    set({ pinnedSourceIds: new Set<string>() }),

  setPendingShowCodeFor: (ids) =>
    set({ pendingShowCodeFor: [...ids] }),

  consumePendingShowCodeFor: () => {
    const current = get().pendingShowCodeFor;
    set({ pendingShowCodeFor: null });
    return current;
  },

  // Panel collapse is NOT content-mutating — do NOT set isDirty
  setToolboxCollapsed: (collapsed) => set({ toolboxCollapsed: collapsed }),
  setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),

  // ---------------------------------------------------------------------------
  // setRecentFiles
  // ---------------------------------------------------------------------------

  setRecentFiles: (files) => set({ recentFiles: files }),

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 04: Clipboard actions (D-15, D-16, D-19)
  // ---------------------------------------------------------------------------

  // Internal helper — builds ClipboardPayload from current selection WITHOUT
  // pushing a snapshot or touching the OS clipboard. Used by both copySelection
  // and cutSelection so cut takes exactly ONE snapshot (Rule 6).
  // (Not exposed on the State interface; accessed only from within this closure.)

  copySelection: async () => {
    const { nodes, edges } = get();
    const selected = nodes.filter((n) => n.selected);
    if (selected.length === 0) return;

    const selectedIds = new Set(selected.map((n) => n.id));
    // D-19: internal edges only — both endpoints must be in the selection.
    const internalEdges = edges.filter(
      (e) => selectedIds.has(e.source) && selectedIds.has(e.target),
    );

    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: selected,
      edges: internalEdges,
    };

    try {
      await navigator.clipboard.writeText(JSON.stringify(payload));
    } catch {
      // Tauri webview may not have clipboard permission in some test envs — no-op.
    }

    // B4 lock: reset paste-offset sequence whenever the clipboard is refreshed.
    pasteOffsetIndex = 0;
  },

  cutSelection: async () => {
    const { nodes, edges, anchors, selectedNodeId, selectedResourceId } = get();
    const selected = nodes.filter((n) => n.selected);
    if (selected.length === 0) return;

    const selectedIds = new Set(selected.map((n) => n.id));

    // Build payload (same logic as copySelection, inline to avoid a second
    // _pushSnapshot — Rule 6: cut takes exactly ONE snapshot).
    const internalEdges = edges.filter(
      (e) => selectedIds.has(e.source) && selectedIds.has(e.target),
    );
    const payload: ClipboardPayload = {
      __format: CLIPBOARD_FORMAT_TAG,
      version: CLIPBOARD_VERSION,
      nodes: selected,
      edges: internalEdges,
    };
    try {
      await navigator.clipboard.writeText(JSON.stringify(payload));
    } catch {
      // clipboard not available — no-op
    }
    pasteOffsetIndex = 0;

    // Single snapshot for the entire cut operation.
    get()._pushSnapshot();

    // Remove selected nodes, their incident edges, and their anchors.
    const nextAnchors = { ...anchors };
    for (const id of selectedIds) {
      delete nextAnchors[id];
    }
    const clearedSelectedNode = selectedNodeId && selectedIds.has(selectedNodeId) ? null : selectedNodeId;

    set({
      nodes: nodes.filter((n) => !selectedIds.has(n.id)),
      edges: edges.filter(
        (e) => !selectedIds.has(e.source) && !selectedIds.has(e.target),
      ),
      anchors: nextAnchors,
      selectedNodeId: clearedSelectedNode,
      selectionKind: deriveSelectionKind(clearedSelectedNode, selectedResourceId),
      isDirty: true,
    });
  },

  pasteFromClipboard: async () => {
    let raw: string;
    try {
      raw = await navigator.clipboard.readText();
    } catch {
      return; // clipboard not available
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return; // malformed JSON — silent no-op (T-65-04)
    }

    if (!isClipboardPayload(parsed)) return; // wrong shape — silent no-op

    // Snapshot pushed AFTER the guard check so malformed input cannot
    // partially mutate state (T-65-04).
    get()._pushSnapshot();

    // B4 lock: each successive paste lands at original + N*20.
    pasteOffsetIndex += 1;
    const dx = pasteOffsetIndex * 20;
    const dy = pasteOffsetIndex * 20;

    // Build old-id → new-id map and mint new nodes.
    const oldToNew = new Map<string, string>();
    const existingNames = new Set(
      get().nodes.map(
        (n) => (n.data as unknown as StreamNodeData).instanceName,
      ),
    );

    const newNodes: Node[] = parsed.nodes.map((srcNode) => {
      const newId = crypto.randomUUID();
      oldToNew.set(srcNode.id, newId);

      const srcData = srcNode.data as unknown as StreamNodeData;
      const newName = smartParseAndIncrement(srcData.instanceName, existingNames);
      existingNames.add(newName); // keep the running set stable across the batch

      return {
        ...srcNode,
        id: newId,
        position: {
          x: srcNode.position.x + dx,
          y: srcNode.position.y + dy,
        },
        selected: true,
        data: {
          ...srcData,
          instanceName: newName,
          // componentId, parameters (incl. resource UUIDs), constructorMode preserved verbatim (D-19)
        } as unknown as Record<string, unknown>,
      };
    });

    // Remap edges; drop any edge whose source or target didn't make it into
    // the id map (defensive against malformed payload — D-19 receive side).
    const newEdges: Edge[] = parsed.edges.flatMap((srcEdge) => {
      const newSource = oldToNew.get(srcEdge.source);
      const newTarget = oldToNew.get(srcEdge.target);
      if (!newSource || !newTarget) return []; // silently drop
      return [
        {
          ...srcEdge,
          id: crypto.randomUUID(),
          source: newSource,
          target: newTarget,
        },
      ];
    });

    // Deselect all existing nodes/edges; select only the fresh pastes.
    const existingNodes = get().nodes.map((n) =>
      n.selected ? { ...n, selected: false } : n,
    );
    const existingEdges = get().edges.map((e) =>
      e.selected ? { ...e, selected: false } : e,
    );

    set({
      nodes: [...existingNodes, ...newNodes],
      edges: [...existingEdges, ...newEdges],
      isDirty: true,
    });
  },

  duplicateSelection: () => {
    const { nodes, edges } = get();
    const selected = nodes.filter((n) => n.selected);
    if (selected.length === 0) return;

    const selectedIds = new Set(selected.map((n) => n.id));
    const internalEdges = edges.filter(
      (e) => selectedIds.has(e.source) && selectedIds.has(e.target),
    );

    get()._pushSnapshot();

    // D-16: fixed +20px offset on EVERY call — does NOT accumulate (B4 lock).
    // Intentionally independent from the paste-offset counter used by pasteFromClipboard.
    const dx = 20;
    const dy = 20;

    const oldToNew = new Map<string, string>();
    const existingNames = new Set(
      nodes.map((n) => (n.data as unknown as StreamNodeData).instanceName),
    );

    const newNodes: Node[] = selected.map((srcNode) => {
      const newId = crypto.randomUUID();
      oldToNew.set(srcNode.id, newId);

      const srcData = srcNode.data as unknown as StreamNodeData;
      const newName = smartParseAndIncrement(srcData.instanceName, existingNames);
      existingNames.add(newName);

      return {
        ...srcNode,
        id: newId,
        position: {
          x: srcNode.position.x + dx,
          y: srcNode.position.y + dy,
        },
        selected: true,
        data: {
          ...srcData,
          instanceName: newName,
        } as unknown as Record<string, unknown>,
      };
    });

    const newEdges: Edge[] = internalEdges.flatMap((srcEdge) => {
      const newSource = oldToNew.get(srcEdge.source);
      const newTarget = oldToNew.get(srcEdge.target);
      if (!newSource || !newTarget) return [];
      return [
        {
          ...srcEdge,
          id: crypto.randomUUID(),
          source: newSource,
          target: newTarget,
        },
      ];
    });

    // Deselect originals; select duplicates.
    const updatedNodes = nodes.map((n) =>
      n.selected ? { ...n, selected: false } : n,
    );
    const updatedEdges = edges.map((e) =>
      e.selected ? { ...e, selected: false } : e,
    );

    set({
      nodes: [...updatedNodes, ...newNodes],
      edges: [...updatedEdges, ...newEdges],
      isDirty: true,
    });
  },

  // ---------------------------------------------------------------------------
  // saveProject (D-02)
  // ---------------------------------------------------------------------------

  saveProject: async () => {
    // Phase 39: validation gate (D-01, D-02)
    const result = get().validateAndGate();
    if (!result.valid) return;

    const { currentFilePath } = get();
    if (!currentFilePath) {
      return get().saveProjectAs();
    }
    try {
      const { writeTextFile } = await import("@tauri-apps/plugin-fs");
      // Phase 62: absolute->relative path conversion for file_loaded
      // PowerShapes (D-24 + RESEARCH Pitfall 5). Transient copy — does NOT
      // mutate in-memory state.
      const state = get();
      const relPowerShapes = await relativizePowerShapePaths(
        state.resources.powerShapes,
        currentFilePath,
      );
      const json = serializeProject({
        nodes: state.nodes,
        edges: state.edges,
        anchors: state.anchors,
        resources: {
          geometries: state.resources.geometries,
          powerShapes: relPowerShapes,
          fluids: state.resources.fluids,
        },
        modelOptions: state.modelOptions,
        activeLeftTab: state.activeLeftTab,
        activeLayers: state.activeLayers,
        hideOffLayer: state.hideOffLayer,
        snapToGrid: state.snapToGrid,
      });
      await writeTextFile(currentFilePath, json);
      const updated = addToRecent(state.recentFiles, currentFilePath);
      set({ isDirty: false, recentFiles: updated });
      await saveRecentFiles(updated);
      // Clear sidecar after successful save — the on-disk file is now authoritative
      const { clearSidecar, getSidecarBasename } = await import("../lib/autoRecover");
      await clearSidecar(getSidecarBasename(currentFilePath, get().untitledProjectUuid));
    } catch (err) {
      console.error("[saveProject] write failed:", err);
      try {
        const { message } = await import("@tauri-apps/plugin-dialog");
        await message(
          "Save failed. Check the file is writable and there is disk space.",
          { title: "Save Failed", kind: "error" },
        );
      } catch (dialogErr) {
        console.error("[saveProject] error dialog failed:", dialogErr);
      }
    }
  },

  // ---------------------------------------------------------------------------
  // saveProjectAs (D-02)
  // ---------------------------------------------------------------------------

  saveProjectAs: async () => {
    // Phase 39: validation gate (D-01, D-02)
    const result = get().validateAndGate();
    if (!result.valid) return;

    try {
      const { save } = await import("@tauri-apps/plugin-dialog");
      // Phase 62-14 (Critical Gap #3): derive defaultPath from the current
      // modelOptions.name (read lazily via get() so a name edit between
      // action start and dialog open is reflected).
      const filePath = await save({
        defaultPath: computeSaveAsDefaultFilename(get().modelOptions.name),
        filters: [
          { name: PROJECT_FILE_LABEL, extensions: [PROJECT_FILE_EXTENSION] },
        ],
      });
      if (!filePath) return;

      const { writeTextFile } = await import("@tauri-apps/plugin-fs");
      // Phase 62: absolute->relative path conversion for file_loaded
      // PowerShapes (D-24 + RESEARCH Pitfall 5). Transient copy — does NOT
      // mutate in-memory state.
      const state = get();
      const relPowerShapes = await relativizePowerShapePaths(
        state.resources.powerShapes,
        filePath,
      );
      const json = serializeProject({
        nodes: state.nodes,
        edges: state.edges,
        anchors: state.anchors,
        resources: {
          geometries: state.resources.geometries,
          powerShapes: relPowerShapes,
          fluids: state.resources.fluids,
        },
        modelOptions: state.modelOptions,
        activeLeftTab: state.activeLeftTab,
        activeLayers: state.activeLayers,
        hideOffLayer: state.hideOffLayer,
        snapToGrid: state.snapToGrid,
      });
      await writeTextFile(filePath, json);
      // Capture uuid + previous file path before set() clears untitled state
      // (consumed below by clearSidecar — Plan 65-07 D-02/D-06)
      const prevUuid = get().untitledProjectUuid;
      const prevFilePath = get().currentFilePath;
      const updated = addToRecent(get().recentFiles, filePath);
      set({ isDirty: false, currentFilePath: filePath, recentFiles: updated });
      await saveRecentFiles(updated);
      // Clear sidecar after successful save — the on-disk file is now authoritative
      const { clearSidecar, getSidecarBasename } = await import("../lib/autoRecover");
      await clearSidecar(getSidecarBasename(prevFilePath, prevUuid));
    } catch (err) {
      console.error("[saveProjectAs] write failed:", err);
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Save failed. Check the file is writable and there is disk space.",
        { title: "Save Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // loadProject (D-02)
  // ---------------------------------------------------------------------------

  loadProject: async () => {
    try {
      const { open } = await import("@tauri-apps/plugin-dialog");
      const filePath = await open({
        filters: [
          { name: PROJECT_FILE_LABEL, extensions: [PROJECT_FILE_EXTENSION] },
        ],
        multiple: false,
      });
      if (!filePath) return;
      const path = Array.isArray(filePath) ? filePath[0] : filePath;
      // Clear any stale missing-file alerts before the new load populates fresh ones.
      set({ missingFilePowerShapes: [] });
      await get().loadProjectFromPath(path);
    } catch (err) {
      console.error("[loadProject] open failed:", err);
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Open failed. The file may be missing, corrupted, or not a valid .scp file.",
        { title: "Open Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // loadProjectFromPath
  // ---------------------------------------------------------------------------

  loadProjectFromPath: async (filePath: string) => {
    try {
      const { readTextFile } = await import("@tauri-apps/plugin-fs");
      const content = await readTextFile(filePath);
      const project = deserializeProject(content);

      // Re-enrich edges for arrowheads and parallel offset (handles pre-Phase-42 saves)
      const enrichedProjectEdges = enrichEdges(
        project.connections,
        project.components,
      );

      // Phase 62: convert disk-format arrays back to Records keyed by uuid.
      // Re-inject the unset PowerShape sentinel (D-26) and the light_water
      // Fluid placeholder — both live in-memory only.
      const geometriesRecord: Record<string, GeometryResource> = {};
      for (const g of project.resources.geometries) geometriesRecord[g.uuid] = g;

      const powerShapesRecord: Record<string, PowerShapeResource> = {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: SENTINEL_POWER_SHAPE_NAME,
          kind: "unset",
          params: {},
        },
      };
      for (const ps of project.resources.power_shapes) {
        // Defensive: refuse to clobber the sentinel if a malformed file
        // re-introduced it.
        if (ps.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;
        powerShapesRecord[ps.uuid] = ps;
      }

      const fluidsRecord: Record<string, FluidResource> = {
        [SENTINEL_LIGHT_WATER_FLUID]: {
          uuid: SENTINEL_LIGHT_WATER_FLUID,
          name: "light_water",
        },
      };
      for (const f of project.resources.fluids) {
        if (f.uuid === SENTINEL_LIGHT_WATER_FLUID) continue;
        fluidsRecord[f.uuid] = f;
      }

      // Phase 62 INV-10: file-existence check for file_loaded PowerShapes.
      // Resolve relative paths against dirname(filePath); set path_missing
      // and populate missingFilePowerShapes for the load-time surface.
      const pathApi = await import("@tauri-apps/api/path");
      const fsApi = await import("@tauri-apps/plugin-fs");
      const scpDir = await pathApi.dirname(filePath);
      const missing: Array<{ uuid: string; name: string; pathTried: string }> = [];
      for (const ps of Object.values(powerShapesRecord)) {
        if (ps.kind !== "file_loaded" || !ps.params.path) continue;
        let absPath: string;
        if (isAbsolutePath(ps.params.path)) {
          absPath = ps.params.path;
        } else {
          try {
            absPath = await pathApi.join(scpDir, ps.params.path);
          } catch {
            absPath = ps.params.path;
          }
        }
        let exists = false;
        try {
          exists = await fsApi.exists(absPath);
        } catch {
          exists = false;
        }
        if (!exists) {
          powerShapesRecord[ps.uuid] = {
            ...ps,
            params: {
              ...ps.params,
              path_missing: true,
              absolute_path_attempted: absPath,
            },
          };
          missing.push({ uuid: ps.uuid, name: ps.name, pathTried: absPath });
        }
      }

      const updated = addToRecent(get().recentFiles, filePath);
      set({
        nodes: project.components,
        edges: enrichedProjectEdges,
        // Phase 63.1 D-02 / D-14: anchors Record replaces legacy
        // boundary-conditions array on load. No legacy fallback per D-14 —
        // old .streamgui files lose their anchor data (accepted breakage).
        anchors: project.anchors,
        // Phase 68: 4-layer state restored from .scp. The legacy
        // `active_layer` string field is auto-converted by deserializeProject
        // (see projectIO.ts shim — "Both"/missing → all true, "Hydraulic" /
        // "Thermal" → only that key true).
        activeLayers: project.layout.active_layers,
        hideOffLayer: project.layout.hide_off_layer,
        // Phase 65 D-10: restore snap-to-grid from .scp layout block (default false)
        snapToGrid: project.layout.snap_to_grid ?? false,
        currentFilePath: filePath,
        isDirty: false,
        selectedNodeId: null,
        recentFiles: updated,
        _undoPast: [],
        _undoFuture: [],
        errorNodeIds: new Set<string>(),
        validationResult: null,
        // Phase 62: resources + modelOptions + activeLeftTab restored from .scp
        resources: {
          geometries: geometriesRecord,
          powerShapes: powerShapesRecord,
          fluids: fluidsRecord,
        },
        modelOptions: project.model_options,
        activeLeftTab: project.layout.active_left_tab,
        // Selection discriminator reset
        selectedResourceId: null,
        selectedResourceKind: null,
        selectionKind: "none",
        // INV-10 surface: populate missing-file PowerShape list (cleared if empty)
        missingFilePowerShapes: missing,
        // Phase 63: reset BC slices on project load — .scp persistence for
        // bcMode / bcSymmetric is out of scope for 63-B (Phase 66 owns scp
        // schema evolution). Reset to empty so a freshly-loaded project
        // doesn't carry stale BC state from the previous session.
        // Phase 63.1 D-15: errorTagsByNodeId removed.
        bcMode: {},
        bcSymmetric: {},
      });
      await saveRecentFiles(updated);

      // INV-10 user-visible error surface: if any file_loaded PowerShape
      // failed the existence check, show a single non-blocking notification
      // pointing the user at the Resources tab to relocate them.
      if (missing.length > 0) {
        try {
          const { message } = await import("@tauri-apps/plugin-dialog");
          await message(
            missing.length === 1
              ? `1 power-shape file not found: ${missing[0].pathTried}. Open the Resources tab to relocate.`
              : `${missing.length} power-shape file(s) not found. Open the Resources tab to relocate.`,
            { title: "Missing power-shape file", kind: "warning" },
          );
        } catch {
          // Dialog plugin unavailable (e.g., tests) — the inline banner in
          // the PowerShape editor still surfaces the path_missing flag.
        }
      }
    } catch (err) {
      console.error("[loadProjectFromPath] open failed:", err);
      const { message } = await import("@tauri-apps/plugin-dialog");
      await message(
        "Open failed. The file may be missing, corrupted, or not a valid .scp file.",
        { title: "Open Failed", kind: "error" },
      );
    }
  },

  // ---------------------------------------------------------------------------
  // newProject (D-11)
  // ---------------------------------------------------------------------------

  newProject: async () => {
    // Clear the prior project's sidecar before resetting state (best-effort).
    // Plan 65-07 D-02/D-06. `clearInstanceCounters()` removed — Plan 65-01
    // deleted that module-level counter in favor of lowest-free naming.
    const { clearSidecar, getSidecarBasename } = await import("../lib/autoRecover");
    const prevFilePath = get().currentFilePath;
    const prevUuid = get().untitledProjectUuid;
    await clearSidecar(getSidecarBasename(prevFilePath, prevUuid));

    set({
      nodes: [],
      edges: [],
      // Phase 63.1 D-02: reset anchors Record on newProject.
      anchors: {},
      // Phase 68: reset to 4-layer defaults (all on, dim off).
      activeLayers: { ...ALL_LAYERS_ON },
      hideOffLayer: false,
      // Phase 65 D-10: snap-to-grid defaults to OFF on new projects
      snapToGrid: false,
      currentFilePath: null,
      isDirty: false,
      selectedNodeId: null,
      bottomPanelOpen: false,
      toolboxCollapsed: false,
      sidebarCollapsed: false,
      _undoPast: [],
      _undoFuture: [],
      errorNodeIds: new Set<string>(),
      validationResult: null,
      // Phase 62: reset Resources / ModelOptions / Tabs / Selection to initial values
      resources: {
        geometries: {},
        powerShapes: {
          [SENTINEL_UNSET_POWER_SHAPE]: {
            uuid: SENTINEL_UNSET_POWER_SHAPE,
            name: SENTINEL_POWER_SHAPE_NAME,
            kind: "unset",
            params: {},
          },
        },
        fluids: {
          [SENTINEL_LIGHT_WATER_FLUID]: {
            uuid: SENTINEL_LIGHT_WATER_FLUID,
            name: "light_water",
          },
        },
      },
      modelOptions: {
        name: "",
        description: "",
        default_fluid: DEFAULT_FLUID,
        g_default: DEFAULT_G,
        solver: { ...DEFAULT_SOLVER },
      },
      activeLeftTab: "Components",
      selectedResourceId: null,
      selectedResourceKind: null,
      selectionKind: "none",
      missingFilePowerShapes: [],
      // Phase 63: reset BC slices on newProject.
      // Phase 63.1 D-15: errorTagsByNodeId removed.
      bcMode: {},
      bcSymmetric: {},
      // Plan 65-07 D-04: regenerate uuid so the new untitled project gets a
      // fresh sidecar filename (prevents sidecar collision with the previous
      // untitled project).
      untitledProjectUuid: crypto.randomUUID(),
    });
  },

  // ---------------------------------------------------------------------------
  // Phase 62 INV-10: relocatePowerShapeFile — user-driven "Locate file…"
  // Opens a Tauri CSV file picker. On a valid pick, converts the chosen
  // absolute path to relative-to-.scp (D-24), updates the resource, clears
  // path_missing, drops the resource from missingFilePowerShapes.
  // ---------------------------------------------------------------------------
  relocatePowerShapeFile: async (uuid: string) => {
    const ps = get().resources.powerShapes[uuid];
    if (!ps || ps.kind !== "file_loaded") return;
    const { open } = await import("@tauri-apps/plugin-dialog");
    const picked = await open({
      filters: [{ name: "CSV (Power Shape)", extensions: ["csv"] }],
      multiple: false,
    });
    if (!picked) return; // user cancelled
    const newAbs = Array.isArray(picked) ? picked[0] : picked;
    if (!newAbs) return;

    // Defensive: re-check existence on the chosen path.
    const fsApi = await import("@tauri-apps/plugin-fs");
    let stillMissing = false;
    try {
      stillMissing = !(await fsApi.exists(String(newAbs)));
    } catch {
      stillMissing = true;
    }

    // Convert absolute -> relative-to-.scp per D-24.
    const currentFilePath = get().currentFilePath;
    let storedPath: string = String(newAbs);
    if (currentFilePath) {
      try {
        const pathApi = await import("@tauri-apps/api/path");
        const dir = await pathApi.dirname(currentFilePath);
        storedPath = computeRelativePath(dir, String(newAbs));
      } catch {
        // Fall back to the absolute path if relativization fails.
        storedPath = String(newAbs);
      }
    }

    get()._pushSnapshot();
    const state = get();
    const updatedPs: PowerShapeResource = {
      ...ps,
      params: {
        ...ps.params,
        path: storedPath,
        path_missing: stillMissing ? true : undefined,
        absolute_path_attempted: stillMissing ? String(newAbs) : undefined,
      },
    };
    set({
      resources: {
        ...state.resources,
        powerShapes: { ...state.resources.powerShapes, [uuid]: updatedPs },
      },
      missingFilePowerShapes: stillMissing
        ? state.missingFilePowerShapes.map((m) =>
            m.uuid === uuid ? { ...m, pathTried: String(newAbs) } : m,
          )
        : state.missingFilePowerShapes.filter((m) => m.uuid !== uuid),
      isDirty: true,
    });
  },

  // ---------------------------------------------------------------------------
  // Phase 65 Plan 08: AutoRecover restore actions (D-03/D-04)
  // ---------------------------------------------------------------------------

  /**
   * Hydrate the store from a sidecar file after a crash is detected on launch.
   *
   * On success: populates nodes/edges/anchors/resources/modelOptions/layout from the
   * sidecar; sets isDirty=true and currentFilePath=null (D-04: recovered state is
   * in-memory unsaved — user must Save As to persist to a named file).
   * On failure (null sidecar, malformed JSON): clears the sidecar to prevent a
   * repeated boot-loop failure; store state is left unchanged.
   *
   * # Arguments
   * - `basename` — sidecar basename (e.g. "foo.scp.autosave")
   */
  recoverFromSidecar: async (basename: string) => {
    const { readSidecar, clearSidecar, clearLockfile } = await import(
      "../lib/autoRecover"
    );

    const text = await readSidecar(basename);
    if (text === null) {
      // Sidecar missing or unreadable — clean up and bail out silently
      await clearSidecar(basename);
      await clearLockfile();
      return;
    }

    let project;
    try {
      project = deserializeProject(text);
    } catch {
      // Malformed / incompatible sidecar — remove it to prevent boot-loop
      await clearSidecar(basename);
      await clearLockfile();
      return;
    }

    // Re-enrich edges (handles pre-Phase-42 saves)
    const enrichedEdges = enrichEdges(project.connections, project.components);

    // Phase 62: re-inject sentinel resources (same pattern as loadProjectFromPath)
    const geometriesRecord: Record<string, GeometryResource> = {};
    for (const g of project.resources.geometries) geometriesRecord[g.uuid] = g;

    const powerShapesRecord: Record<string, PowerShapeResource> = {
      [SENTINEL_UNSET_POWER_SHAPE]: {
        uuid: SENTINEL_UNSET_POWER_SHAPE,
        name: "(leave unset — set in code)",
        kind: "unset",
        params: {},
      },
    };
    for (const ps of project.resources.power_shapes) {
      if (ps.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;
      powerShapesRecord[ps.uuid] = ps;
    }

    const fluidsRecord: Record<string, FluidResource> = {
      [SENTINEL_LIGHT_WATER_FLUID]: {
        uuid: SENTINEL_LIGHT_WATER_FLUID,
        name: "light_water",
      },
    };
    for (const f of project.resources.fluids) {
      if (f.uuid === SENTINEL_LIGHT_WATER_FLUID) continue;
      fluidsRecord[f.uuid] = f;
    }

    set({
      nodes: project.components,
      edges: enrichedEdges,
      anchors: project.anchors,
      // Phase 68: 4-layer state restored from sidecar (same shim path as
      // loadProjectFromPath — projectIO normalizes legacy active_layer).
      activeLayers: project.layout.active_layers,
      hideOffLayer: project.layout.hide_off_layer,
      snapToGrid: project.layout.snap_to_grid ?? false,
      // D-04: recovered state is always in-memory unsaved; user must Save As
      currentFilePath: null,
      isDirty: true,
      selectedNodeId: null,
      _undoPast: [],
      _undoFuture: [],
      errorNodeIds: new Set<string>(),
      validationResult: null,
      resources: {
        geometries: geometriesRecord,
        powerShapes: powerShapesRecord,
        fluids: fluidsRecord,
      },
      modelOptions: project.model_options,
      activeLeftTab: project.layout.active_left_tab,
      selectedResourceId: null,
      selectedResourceKind: null,
      selectionKind: "none",
      missingFilePowerShapes: [],
      bcMode: {},
      bcSymmetric: {},
    });

    // Clear the sidecar and lockfile after successful hydration
    await clearSidecar(basename);
    await clearLockfile();
  },

  /**
   * Discard all sidecar files and the lockfile.
   *
   * Called when the user clicks "Discard" on the restore modal. Clears every
   * autosave sidecar (not just the one shown in the modal) and removes the
   * stale lockfile so the next launch starts clean.
   */
  discardAllSidecars: async () => {
    const { enumerateSidecars, clearSidecar, clearLockfile } = await import(
      "../lib/autoRecover"
    );
    const basenames = await enumerateSidecars();
    await Promise.all(basenames.map((b) => clearSidecar(b)));
    await clearLockfile();
  },

  // ---------------------------------------------------------------------------
  // Phase 70 Plan 03: Presets slice actions (D-04, D-06, D-09, D-10, D-11,
  // D-12, D-18, D-18.1, D-19)
  // ---------------------------------------------------------------------------

  setProjectPresets: (entries) => set({ projectPresets: entries }),
  setLibraryPresets: (entries) => set({ libraryPresets: entries }),

  // refreshPresetsDir — scan a directory for .scpr files, parse each, and
  // populate the corresponding presets array. Per-file try/catch tolerates
  // mid-write states (Pitfall 3). Directory-level try/catch tolerates the
  // directory not existing on first run (Pitfall 8 defense-in-depth).
  // NO _pushSnapshot — file I/O is not an undo-able action.
  refreshPresetsDir: async (store, dir) => {
    const { readDir, readTextFile } = await import("@tauri-apps/plugin-fs");
    const entries: PresetIndexEntry[] = [];
    try {
      const files = await readDir(dir);
      for (const f of files) {
        if (!f.name?.endsWith(".scpr")) continue;
        if (!f.isFile) continue;
        try {
          const json = await readTextFile(dir + "/" + f.name);
          const preset = deserializePreset(json);
          entries.push({
            name: preset.name,
            description: preset.description,
            filePath: dir + "/" + f.name,
            store,
          });
        } catch (err) {
          console.error("[refreshPresetsDir] Failed to read preset", f.name, err);
        }
      }
    } catch (err) {
      // WR-01: only "directory does not exist" is expected; log everything else.
      const msg = err instanceof Error ? err.message : String(err);
      if (!/no such file|not found|ENOENT/i.test(msg)) {
        console.error("[refreshPresetsDir] readDir failed for", dir, err);
      }
    }
    if (store === "project") {
      set({ projectPresets: entries });
    } else {
      set({ libraryPresets: entries });
    }
  },

  // saveSelectionAsPreset — serialize the current selection (auto-extended per
  // D-12) to a .scpr file in the chosen store directory. Guards charset (T-70-08)
  // and project-open state. NO _pushSnapshot — file I/O is not undo-able.
  saveSelectionAsPreset: async (name, description, targetStore) => {
    // T-70-08: charset guard (defense-in-depth; UI also validates).
    if (!isValidPresetName(name)) {
      throw new Error(
        "Invalid preset name '" + name + "': must match [A-Za-z0-9_-]+",
      );
    }

    const { nodes, edges, resources, currentFilePath } = get();

    // Require at least 2 selected components.
    const selectedIds = new Set(
      nodes.filter((n) => n.selected).map((n) => n.id),
    );
    if (selectedIds.size < 2) {
      throw new Error("Need at least 2 selected components to save as preset");
    }

    // D-12: auto-extend one hop along BC edges; drop cross-boundary edges.
    const { extendedIds, keptEdges } = autoExtendSelection(
      selectedIds,
      nodes,
      edges,
    );

    // Filter nodes to the extended set; strip data.autoExtended (Pitfall 7).
    const presetNodes = nodes
      .filter((n) => extendedIds.has(n.id))
      .map((n) => {
        const d = n.data as Record<string, unknown>;
        if ("autoExtended" in d) {
          const { autoExtended: _stripped, ...rest } = d;
          void _stripped;
          return { ...n, data: rest };
        }
        return n;
      });

    // Q5: collect embedded resource copies by UUID (dedup by UUID).
    // PARAM_KEY_BY_KIND inlined to avoid component-from-store import (Pitfall 5).
    const PARAM_RESOURCE_KEYS = [
      "geometry",
      "geometry_ref",
      "power_shape",
      "power_shape_ref",
    ] as const;

    const seenGeomUuids = new Set<string>();
    const seenPsUuids = new Set<string>();
    const collectedGeometries: GeometryResource[] = [];
    const collectedPowerShapes: PowerShapeResource[] = [];

    for (const node of presetNodes) {
      const params = (node.data as Record<string, unknown>).parameters as
        | Record<string, unknown>
        | undefined;
      if (!params) continue;
      for (const key of PARAM_RESOURCE_KEYS) {
        const val = params[key];
        if (typeof val !== "string") continue;
        const uuid = val;
        // Geometry keys
        if (key === "geometry" || key === "geometry_ref") {
          if (!seenGeomUuids.has(uuid) && resources.geometries[uuid]) {
            seenGeomUuids.add(uuid);
            collectedGeometries.push({ ...resources.geometries[uuid] });
          }
        }
        // PowerShape keys — exclude the sentinel (unset)
        if (key === "power_shape" || key === "power_shape_ref") {
          if (
            !seenPsUuids.has(uuid) &&
            resources.powerShapes[uuid] &&
            uuid !== SENTINEL_UNSET_POWER_SHAPE
          ) {
            seenPsUuids.add(uuid);
            collectedPowerShapes.push({ ...resources.powerShapes[uuid] });
          }
        }
      }
    }

    // D-11: normalize layout to bbox-top-left at (0,0).
    const layout = normalizeLayout(presetNodes);

    // Resolve target directory (D-04, T-70-13).
    const { join } = await import("@tauri-apps/api/path");
    let dir: string;
    if (targetStore === "library") {
      const { appConfigDir } = await import("@tauri-apps/api/path");
      dir = await join(await appConfigDir(), "presets");
    } else {
      // Project store: derive dir from currentFilePath (T-70-13).
      if (!currentFilePath) {
        throw new Error(
          "Cannot save to Project preset store: no project file is open",
        );
      }
      // Strip filename — support both POSIX and Windows separators.
      const projDir = currentFilePath.replace(/[/\\][^/\\]+$/, "");
      dir = await join(projDir, "presets");
    }

    // Ensure directory exists (Pitfall 8).
    // WR-02: log unexpected errors; only swallow EEXIST-equivalent.
    const { mkdir, writeTextFile } = await import("@tauri-apps/plugin-fs");
    await mkdir(dir, { recursive: true }).catch((err) => {
      const msg = err instanceof Error ? err.message : String(err);
      if (!/already exists|EEXIST/i.test(msg)) {
        console.error("[saveSelectionAsPreset] mkdir failed:", err);
      }
    });

    // Serialize and write.
    const json = serializePreset({
      name,
      description,
      components: presetNodes,
      connections: keptEdges,
      geometries: collectedGeometries,
      powerShapes: collectedPowerShapes,
      layout,
    });
    const filePath = dir + "/" + name + ".scpr";
    await writeTextFile(filePath, json);

    // Refresh the slice immediately (watcher may fire later too, but be
    // consistent right away — D-06).
    await get().refreshPresetsDir(targetStore, dir);

    return { filePath };
  },

  // loadPresetAtPosition — mint new UUIDs for every node/edge/resource, apply
  // smart-name-increment, remap resource UUID references, position bundle with
  // bbox-center at anchor, auto-select all placed nodes (D-18, D-18.1, Q7).
  loadPresetAtPosition: async (filePath, anchor) => {
    const { readTextFile } = await import("@tauri-apps/plugin-fs");
    const json = await readTextFile(filePath);
    const preset = deserializePreset(json);

    // PARAM_KEY_BY_KIND inlined (Pitfall 5).
    const GEOM_KEYS = ["geometry", "geometry_ref"] as const;
    const PS_KEYS = ["power_shape", "power_shape_ref"] as const;

    // ---- Step 1: Resource UUID remap — add embedded resources with new UUIDs.
    const resOldToNew = new Map<string, string>();
    const currentResources = get().resources;

    // Smart-name sets per kind (built from current store).
    const existingGeomNames = new Set(
      Object.values(currentResources.geometries).map((r) => r.name),
    );
    const existingPsNames = new Set(
      Object.values(currentResources.powerShapes)
        .filter((r) => r.uuid !== SENTINEL_UNSET_POWER_SHAPE)
        .map((r) => r.name),
    );

    // Accumulated new resource maps to add atomically in the set() call.
    const newGeomsTyped: Record<string, GeometryResource> = {};
    const newPSTyped: Record<string, PowerShapeResource> = {};

    for (const emb of preset.resources.geometries) {
      const newResId = crypto.randomUUID();
      const incrementedName = smartParseAndIncrement(emb.name, existingGeomNames);
      existingGeomNames.add(incrementedName);
      resOldToNew.set(emb.uuid, newResId);
      newGeomsTyped[newResId] = { ...emb, uuid: newResId, name: incrementedName };
    }
    for (const emb of preset.resources.power_shapes) {
      if (emb.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;
      const newResId = crypto.randomUUID();
      const incrementedName = smartParseAndIncrement(emb.name, existingPsNames);
      existingPsNames.add(incrementedName);
      resOldToNew.set(emb.uuid, newResId);
      newPSTyped[newResId] = { ...emb, uuid: newResId, name: incrementedName };
    }

    // ---- Step 2: Component UUID remap + smart-name + position.
    const oldToNew = new Map<string, string>();
    const existingNames = new Set(
      get().nodes.map((n) => (n.data as unknown as StreamNodeData).instanceName),
    );

    // Compute bbox-center offset from normalized layout (D-11: top-left at 0,0).
    const layoutValues = Object.values(preset.layout);
    const maxX =
      layoutValues.length > 0 ? Math.max(...layoutValues.map((p) => p.x)) : 0;
    const maxY =
      layoutValues.length > 0 ? Math.max(...layoutValues.map((p) => p.y)) : 0;
    const offsetX = anchor.x - maxX / 2;
    const offsetY = anchor.y - maxY / 2;

    const newNodes = preset.components.map((srcNode) => {
      const newId = crypto.randomUUID();
      oldToNew.set(srcNode.id, newId);

      const srcData = srcNode.data as unknown as StreamNodeData;
      const newName = smartParseAndIncrement(srcData.instanceName, existingNames);
      existingNames.add(newName);

      // Remap resource UUID references in parameters (Pitfall 5).
      const newParams = { ...(srcData.parameters as Record<string, unknown>) };
      for (const key of [...GEOM_KEYS, ...PS_KEYS]) {
        const val = newParams[key];
        if (typeof val === "string" && resOldToNew.has(val)) {
          newParams[key] = resOldToNew.get(val);
        }
      }

      const layoutPos = preset.layout[srcNode.id] ?? { x: 0, y: 0 };

      return {
        ...srcNode,
        id: newId,
        position: {
          x: offsetX + layoutPos.x,
          y: offsetY + layoutPos.y,
        },
        selected: true, // D-18: auto-select all placed nodes.
        data: {
          ...srcData,
          instanceName: newName,
          parameters: newParams,
        } as unknown as Record<string, unknown>,
      };
    });

    // ---- Step 3: Edge UUID remap.
    const newEdges = preset.connections.flatMap((srcEdge) => {
      const newSource = oldToNew.get(srcEdge.source);
      const newTarget = oldToNew.get(srcEdge.target);
      if (!newSource || !newTarget) return []; // defensive drop
      return [
        {
          ...srcEdge,
          id: crypto.randomUUID(),
          source: newSource,
          target: newTarget,
        },
      ];
    });

    // ---- Step 4: Single set() — deselect existing + add new + merge resources.
    const currentResState = get().resources;
    get()._pushSnapshot(); // load is undo-able as a single op (D-18).
    set((state) => ({
      nodes: [
        ...state.nodes.map((n) => (n.selected ? { ...n, selected: false } : n)),
        ...newNodes,
      ],
      edges: [...state.edges, ...newEdges],
      resources: {
        ...currentResState,
        geometries: { ...currentResState.geometries, ...newGeomsTyped },
        powerShapes: { ...currentResState.powerShapes, ...newPSTyped },
      },
      isDirty: true,
    }));
  },

  // loadPresetFromPath — file picker then delegate to loadPresetAtPosition.
  // The anchor (viewport center) is computed by the caller (FileMenu handler).
  loadPresetFromPath: async (anchor) => {
    const { open } = await import("@tauri-apps/plugin-dialog");
    const selected = await open({
      filters: [{ name: "STREAM Composer Preset", extensions: ["scpr"] }],
      multiple: false,
    });
    if (!selected) return; // user cancelled
    await get().loadPresetAtPosition(selected as string, anchor);
  },

  // renamePreset — rewrite the on-disk JSON name field AND rename the file
  // (D-09, D-19). Guards charset (T-70-08) and collision.
  // NO _pushSnapshot — file I/O is not undo-able.
  renamePreset: async (filePath, newName) => {
    if (!isValidPresetName(newName)) {
      throw new Error(
        "Invalid preset name '" + newName + "': must match [A-Za-z0-9_-]+",
      );
    }

    const { readTextFile, writeTextFile, remove } = await import(
      "@tauri-apps/plugin-fs"
    );

    // Read + parse existing file to get the full preset object.
    const oldJson = await readTextFile(filePath);
    const preset = deserializePreset(oldJson);

    // Derive parent directory and new path.
    const dir = filePath.replace(/[/\\][^/\\]+$/, "");
    const newPath = dir + "/" + newName + ".scpr";

    // Guard collision: if target path differs, check it doesn't already exist.
    if (newPath !== filePath) {
      try {
        await readTextFile(newPath);
        // If readTextFile succeeds, the file exists — collision.
        throw new Error(
          "A preset named '" + newName + "' already exists in this store",
        );
      } catch (err) {
        // Re-throw only the collision error; other errors (file not found) are expected.
        if (
          err instanceof Error &&
          err.message.startsWith("A preset named")
        ) {
          throw err;
        }
        // Otherwise the file does not exist — safe to proceed.
      }
    }

    // Rewrite JSON with updated name field.
    const newJson = serializePreset({
      name: newName,
      description: preset.description,
      components: preset.components,
      connections: preset.connections,
      geometries: preset.resources.geometries,
      powerShapes: preset.resources.power_shapes,
      layout: preset.layout,
    });

    await writeTextFile(newPath, newJson);
    if (newPath !== filePath) {
      await remove(filePath);
    }

    // Determine which store the entry lives in and refresh.
    const { projectPresets, libraryPresets } = get();
    const inProject = projectPresets.some((e) => e.filePath === filePath);
    const store = inProject ? "project" : "library";
    await get().refreshPresetsDir(store, dir);
  },

  // deletePreset — unlink the .scpr file and refresh the relevant store slice.
  // NO _pushSnapshot — file I/O is not undo-able.
  deletePreset: async (filePath) => {
    const { remove } = await import("@tauri-apps/plugin-fs");
    await remove(filePath);

    // Determine store from current arrays then refresh.
    const { projectPresets, libraryPresets } = get();
    const inProject = projectPresets.some((e) => e.filePath === filePath);
    const dir = filePath.replace(/[/\\][^/\\]+$/, "");
    const store = inProject ? "project" : "library";
    await get().refreshPresetsDir(store, dir);
  },
})));

/**
 * Initialize recent files from disk on app startup.
 * Call this from App.tsx on mount.
 */
export async function initializeRecentFiles(): Promise<void> {
  const files = await loadRecentFiles();
  useStore.setState({ recentFiles: files });
}

/**
 * Reset the paste-offset counter to 0.
 * Exposed for test isolation only — production code resets via copySelection.
 * @internal
 */
export function _resetPasteOffsetIndexForTesting(): void {
  pasteOffsetIndex = 0;
}

/**
 * Initialize the AutoRecover substrate (Plan 65-07 D-01/D-02/D-06).
 *
 * Call this from App.tsx on mount (alongside initializeRecentFiles).
 * Returns a teardown function to call on app unmount (clears lockfile + unsubscribes).
 *
 * Wires:
 * - A debounced isDirty subscription that calls writeSidecar ~2s after each edit
 * - Writes the running.lock file (PID + timestamp) for crash detection on next launch
 *
 * Plan 65-08 calls teardown from App.tsx's unmount / beforeunload hook.
 */
export async function initAutoRecover(): Promise<{ teardown: () => Promise<void> }> {
  const {
    createDebouncedSidecarWriter,
    getSidecarBasename,
    writeLockfile,
    clearLockfile,
  } = await import("../lib/autoRecover");

  // Get the current process PID via Tauri command
  let pid = 0;
  try {
    const { invoke } = await import("@tauri-apps/api/core");
    pid = await invoke<number>("get_pid");
  } catch {
    // Non-Tauri environment (tests, dev preview without IPC) — use 0 as sentinel
  }

  // Build the debounced writer.
  // serialize() is called at write time (not schedule time) so it captures the
  // latest state at the moment the debounce fires. D-06: bit-identical to Save.
  const writer = createDebouncedSidecarWriter(
    2000,
    () => {
      const state = useStore.getState();
      return serializeProject({
        nodes: state.nodes,
        edges: state.edges,
        anchors: state.anchors,
        resources: state.resources,
        modelOptions: state.modelOptions,
        activeLeftTab: state.activeLeftTab,
        activeLayers: state.activeLayers,
        hideOffLayer: state.hideOffLayer,
        snapToGrid: state.snapToGrid,
      });
    },
    () => {
      const state = useStore.getState();
      return getSidecarBasename(state.currentFilePath, state.untitledProjectUuid);
    },
  );

  // Subscribe to isDirty changes.
  // Phase 65 Plan 14: selector-gated — schedule/cancel fire only on isDirty transitions.
  // Semantic shift from Plan 07 ("rapid edits reset the timer") to "2s after first edit
  // in the dirty session". Both satisfy the AutoRecover goal of "save within ~2s of
  // user activity" — the new semantics is a stricter, simpler guarantee. Source:
  // .planning/debug/gui-drag-perf.md (per-pixel mousemove no longer reschedules timer).
  const unsubscribe = useStore.subscribe(
    (state) => state.isDirty,
    (isDirty) => {
      if (isDirty) writer.schedule();
      else writer.cancel();
    },
  );

  // Write the running.lock file (crash detection D-02)
  await writeLockfile(pid);

  async function teardown(): Promise<void> {
    unsubscribe();
    writer.cancel();
    await clearLockfile();
  }

  return { teardown };
}

export default useStore;

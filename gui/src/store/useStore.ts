import { create } from "zustand";
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
  cycleBCEdgeTargetSide as cycleBCEdgeTargetSidePure,
  type BCModeEntry,
  type BCEdgeData,
} from "@/lib/bcMode";
import type { AnchorEntry } from "@/lib/anchors";
import {
  serializeProject,
  deserializeProject,
  addToRecent,
  reconstructInstanceCounters,
} from "../lib/projectIO";
import type { LayerView } from "../lib/layers";

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

export type ActiveLeftTab = "Components" | "Resources" | "Project";

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
  // Layer view state (persisted in .scp layout block, NOT in undo stack)
  activeLayer: LayerView;
  setActiveLayer: (layer: LayerView) => void;
  cycleLayer: () => void;
  // Persistence state
  isDirty: boolean;
  currentFilePath: string | null;
  recentFiles: string[];
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
  cycleBCEdgeTargetSide: (edgeId: string) => void;
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
}

// Per-type instance counters for default naming (module-level, not tracked by zundo)
const instanceCounters: Record<string, number> = {};

function getNextInstanceName(componentId: string): string {
  const count = (instanceCounters[componentId.toLowerCase()] ?? 0) + 1;
  instanceCounters[componentId.toLowerCase()] = count;
  return `${componentId.toLowerCase()}_${count}`;
}

function clearInstanceCounters(): void {
  Object.keys(instanceCounters).forEach((k) => delete instanceCounters[k]);
}

// ---------------------------------------------------------------------------
// Phase 62: Resource name helper — lowest-free-positive-integer per kind (D-19)
// ---------------------------------------------------------------------------
//
// Mirrors `getNextInstanceName` algorithmic shape, but uses *lowest free* rather
// than *next after highest* so that after deleting `geometry_2` and re-creating,
// the new resource lands at `geometry_2` (matches user mental model — D-19).
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
// _reconcileEdgesForBCMode — pure edges reconciliation for ONE consumer side
//
// Plan 63.1-10 (CR-02 / CR-03): extracted from setBCMode's inline
// edge-materialization block so setBCMode and setBCSymmetric share the
// add/remove logic instead of duplicating it.
//
// Semantics — operates on ONE (consumerNodeId, externalInputName) pair only.
// Sibling reconciliation is the caller's responsibility (loop or second call).
//   • prev="source", new="source" same sourceNodeId → no-op (idempotent)
//   • prev="source", new="source" different source → swap the bcEdge
//   • prev="source", new is anything else (or undefined) → remove the bcEdge
//   • prev=undefined / non-source, new="source" → add a new bcEdge
//   • prev=undefined / non-source, new=undefined / non-source → no-op
//
// `symmetric` is reserved for future use (caller currently passes false at
// every call-site; siblings are handled by issuing a second call).
//
// Pure: returns a new edges array; does NOT call set() or _pushSnapshot.
// ---------------------------------------------------------------------------
function _reconcileEdgesForBCMode(
  edges: Edge[],
  nodes: Node[],
  consumerNodeId: string,
  externalInputName: string,
  prevEntry: BCModeEntry | undefined,
  newEntry: BCModeEntry | undefined,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _symmetric: boolean,
): Edge[] {
  let nextEdges = edges;

  // Remove any prior source-mode edge bound to this (consumer, handle).
  // This covers prev="source" → non-source/undefined transitions AND the
  // source-A → source-B swap (the add step below re-emits a fresh edge).
  if (prevEntry?.mode === "source") {
    nextEdges = nextEdges.filter(
      (e) =>
        !(
          e.type === "bcEdge" &&
          e.target === consumerNodeId &&
          e.targetHandle === externalInputName
        ),
    );
  }

  // If the new entry is source-mode, materialize the BC edge (idempotent).
  if (newEntry?.mode === "source") {
    const sourceNode = nodes.find((n) => n.id === newEntry.sourceNodeId);
    if (!sourceNode) return nextEdges;
    const sourceComp = getComponent(
      (sourceNode.data as unknown as StreamNodeData).componentId,
    );
    const sourcePort = sourceComp?.ports.find((p) => p.type === "BCPort");
    if (!sourcePort) return nextEdges;
    const dup = nextEdges.some(
      (e) =>
        e.type === "bcEdge" &&
        e.source === newEntry.sourceNodeId &&
        e.sourceHandle === sourcePort.name &&
        e.target === consumerNodeId &&
        e.targetHandle === externalInputName,
    );
    if (dup) return nextEdges;
    const edgeId = `bce-${newEntry.sourceNodeId}-${consumerNodeId}-${externalInputName}-${crypto.randomUUID().slice(0, 8)}`;
    const bcData: BCEdgeData = {
      componentId: consumerNodeId,
      externalInputName,
      targetSide: "both",
    };
    nextEdges = [
      ...nextEdges,
      {
        id: edgeId,
        source: newEntry.sourceNodeId,
        sourceHandle: sourcePort.name,
        target: consumerNodeId,
        targetHandle: externalInputName,
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

const useStore = create<AppState>()((set, get) => ({
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
  // Layer view initial state
  activeLayer: "Both" as LayerView,
  // Persistence initial state
  isDirty: false,
  currentFilePath: null,
  recentFiles: [],

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
  // Layer view actions (persisted in .scp layout block — set isDirty so saves capture)
  // ---------------------------------------------------------------------------

  setActiveLayer: (layer) => set({ activeLayer: layer, isDirty: true }),

  cycleLayer: () => {
    const order: LayerView[] = ["Hydraulic", "Both", "Thermal"];
    const { activeLayer } = get();
    const idx = order.indexOf(activeLayer);
    set({ activeLayer: order[(idx + 1) % 3], isDirty: true });
  },

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
    const newNode: Node = {
      id,
      type: "streamNode",
      position,
      data: {
        componentId,
        instanceName: getNextInstanceName(componentId),
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

    // Compute new edges via the shared helper. One call per side (primary +
    // sibling when symmetric). Plan 63.1-10: extracted helper, no inline
    // edge-materialization here anymore.
    let nextEdges = _reconcileEdgesForBCMode(
      state.edges,
      state.nodes,
      componentId,
      externalInputName,
      previous,
      entry,
      false,
    );
    if (siblingKey && siblingName) {
      nextEdges = _reconcileEdgesForBCMode(
        nextEdges,
        state.nodes,
        componentId,
        siblingName,
        state.bcMode[siblingKey],
        entry,
        false,
      );
    }

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
    const consumerN =
      (consumerData.parameters?.n as number | undefined) ?? 1;
    get().updateNodeParams(newNode.id, {
      parameters: { n: consumerN },
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
      // Plan 63.1-10: setBCSymmetric(true) now reconciles BOTH the bcMode map
      // AND the BC edges on the right side. Two edge-holes are covered:
      //   CR-02 (D-21): leftEntry undefined + rightEntry defined → delete
      //                 rightKey AND remove the dangling right-side BC edge.
      //   CR-03 (D-21): leftEntry defined + leftEntry !== rightEntry → mirror
      //                 left → right AND add/remove the right-side BC edge to
      //                 match the new mode.
      const leftKey = bcModeKey(nodeId, `${baseField}_left`);
      const rightKey = bcModeKey(nodeId, `${baseField}_right`);
      const leftEntry = state.bcMode[leftKey];
      const rightEntry = state.bcMode[rightKey];
      const rightInputName = `${baseField}_right`;

      if (leftEntry === undefined && rightEntry !== undefined) {
        // CR-02 (D-21): collapse the pair to "neither set".
        const nbm = { ...state.bcMode };
        delete nbm[rightKey];
        nextBCMode = nbm;
        nextEdges = _reconcileEdgesForBCMode(
          nextEdges,
          state.nodes,
          nodeId,
          rightInputName,
          rightEntry,
          undefined,
          false,
        );
      } else if (leftEntry !== undefined && leftEntry !== rightEntry) {
        // CR-03 (D-21): mirror left → right AND reconcile the right BC edge.
        nextBCMode = { ...state.bcMode, [rightKey]: leftEntry };
        nextEdges = _reconcileEdgesForBCMode(
          nextEdges,
          state.nodes,
          nodeId,
          rightInputName,
          rightEntry,
          leftEntry,
          false,
        );
      }
    }

    set({
      bcMode: nextBCMode,
      bcSymmetric: nextBCSymmetric,
      edges: nextEdges,
      isDirty: true,
    });
  },

  cycleBCEdgeTargetSide: (edgeId) => {
    get()._pushSnapshot();
    const state = get();
    const nextEdges = state.edges.map((e) => {
      if (e.id !== edgeId) return e;
      if (e.type !== "bcEdge") return e;
      const data = (e.data as BCEdgeData | undefined) ?? {
        componentId: e.target,
        externalInputName: e.targetHandle ?? "",
        targetSide: "both" as const,
      };
      const nextSide = cycleBCEdgeTargetSidePure(data.targetSide);
      return { ...e, data: { ...data, targetSide: nextSide } } as Edge;
    });
    set({ edges: nextEdges, isDirty: true });
  },

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

  // Panel collapse is NOT content-mutating — do NOT set isDirty
  setToolboxCollapsed: (collapsed) => set({ toolboxCollapsed: collapsed }),
  setSidebarCollapsed: (collapsed) => set({ sidebarCollapsed: collapsed }),

  // ---------------------------------------------------------------------------
  // setRecentFiles
  // ---------------------------------------------------------------------------

  setRecentFiles: (files) => set({ recentFiles: files }),

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
        activeLayer: state.activeLayer,
      });
      await writeTextFile(currentFilePath, json);
      const updated = addToRecent(state.recentFiles, currentFilePath);
      set({ isDirty: false, recentFiles: updated });
      await saveRecentFiles(updated);
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
        activeLayer: state.activeLayer,
      });
      await writeTextFile(filePath, json);
      const updated = addToRecent(state.recentFiles, filePath);
      set({ isDirty: false, currentFilePath: filePath, recentFiles: updated });
      await saveRecentFiles(updated);
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

      const reconstructed = reconstructInstanceCounters(project.components);
      clearInstanceCounters();
      Object.assign(instanceCounters, reconstructed);

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
        activeLayer: (project.layout.active_layer ?? "Both") as LayerView,
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
    clearInstanceCounters();
    set({
      nodes: [],
      edges: [],
      // Phase 63.1 D-02: reset anchors Record on newProject.
      anchors: {},
      activeLayer: "Both" as LayerView,
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
}));

/**
 * Initialize recent files from disk on app startup.
 * Call this from App.tsx on mount.
 */
export async function initializeRecentFiles(): Promise<void> {
  const files = await loadRecentFiles();
  useStore.setState({ recentFiles: files });
}

export default useStore;

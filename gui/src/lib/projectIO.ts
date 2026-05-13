// projectIO.ts — Pure serialization / deserialization for the .scp v2.0 schema.
//
// Phase 62 hard-cutover: legacy numeric-version (v1/v2) form is rejected
// outright (D-28). There is NO migration shim. The deserialize side throws
// cleanly on any non-"2.0" format_version (INV-07 / INV-08).
//
// Zero side-effects in this module. All file system I/O is handled in
// useStore.ts (which is responsible for absolute->relative path conversion of
// file_loaded Power Shape paths per D-24 / RESEARCH Pitfall 5). projectIO is
// fully testable in a vitest node environment.

import type { Node, Edge } from "@xyflow/react";
import type { AnchorEntry } from "./anchors";
import type { LayerView } from "./layers";
import {
  SENTINEL_UNSET_POWER_SHAPE,
  type GeometryResource,
  type PowerShapeResource,
  type FluidResource,
  type ModelOptionsSliceState,
  type ActiveLeftTab,
} from "../store/useStore";

// Re-export the sentinel constant so consumers of projectIO can filter without
// dual-importing from the store.
export { SENTINEL_UNSET_POWER_SHAPE };

// ---------------------------------------------------------------------------
// Format constant
// ---------------------------------------------------------------------------

/**
 * Single source of truth for the .scp format version.
 *
 * Per D-27, the on-disk schema is `format_version: "2.0"`. Hard-cutover from
 * the legacy numeric-version form (pre-v2.0) (D-28); no migration.
 */
export const PROJECT_FORMAT_VERSION = "2.0" as const;

// ---------------------------------------------------------------------------
// Types — the v2.0 schema (D-27, D-29)
// ---------------------------------------------------------------------------

export interface StreamProject {
  format_version: typeof PROJECT_FORMAT_VERSION;
  model_options: ModelOptionsSliceState;
  resources: {
    geometries: GeometryResource[];
    power_shapes: PowerShapeResource[]; // sentinel NOT included
    fluids: FluidResource[]; // light_water NOT included
  };
  components: Node[]; // ReactFlow Node[] — same in-memory shape as pre-Phase-62
  connections: Edge[]; // renamed from "edges" per CONTEXT.md storage shape
  // Phase 63.1 D-02 / D-14: pressure-anchor Record keyed by nodeId (replaces
  // the legacy boundary-conditions Array). No legacy fallback on load — old
  // .streamgui files lose their anchor data on deserialize (accepted breakage).
  anchors: Record<string, AnchorEntry>;
  layout: {
    active_left_tab: ActiveLeftTab; // D-08 / D-29
    active_layer: LayerView; // moved from top-level (was StreamProject.activeLayer)
  };
}

// ---------------------------------------------------------------------------
// Default factories (used by deserializeProject empty-state tolerance — Pitfall 3)
// ---------------------------------------------------------------------------

const DEFAULT_FLUID = "water";
const DEFAULT_G = 9.80665;

function defaultModelOptions(): ModelOptionsSliceState {
  return {
    name: "",
    description: "",
    default_fluid: DEFAULT_FLUID,
    g_default: DEFAULT_G,
    solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
  };
}

function defaultLayout(): StreamProject["layout"] {
  return { active_left_tab: "Components", active_layer: "Both" };
}

// ---------------------------------------------------------------------------
// serializeProject
// ---------------------------------------------------------------------------

export interface SerializeProjectArgs {
  nodes: Node[];
  edges: Edge[];
  // Phase 63.1 D-02: pressure-anchor Record (replaces legacy
  // boundary-conditions Array). Keys are nodeIds (stable UUIDs); written
  // verbatim to disk (no Array conversion).
  anchors: Record<string, AnchorEntry>;
  resources: {
    geometries: Record<string, GeometryResource>;
    powerShapes: Record<string, PowerShapeResource>;
    fluids: Record<string, FluidResource>;
  };
  modelOptions: ModelOptionsSliceState;
  activeLeftTab: ActiveLeftTab;
  activeLayer: LayerView;
}

/**
 * Serialize the in-memory state to a JSON string for writing to a `.scp` file.
 *
 * Conversions:
 *  - resources.geometries / .powerShapes / .fluids: Record<uuid, T> -> T[]
 *  - SENTINEL_UNSET_POWER_SHAPE is filtered out (D-26 — sentinel is in-memory only)
 *  - light_water Fluid placeholder is filtered out (re-injected at load time)
 *  - activeLeftTab + activeLayer are nested under `layout` (D-29)
 *
 * # Arguments
 * - `args` — single args object; see {@link SerializeProjectArgs}
 *
 * # Returns
 * Pretty-printed JSON matching the v2.0 schema.
 */
export function serializeProject(args: SerializeProjectArgs): string {
  const geometries = Object.values(args.resources.geometries);
  const power_shapes = Object.values(args.resources.powerShapes).filter(
    (p) => p.uuid !== SENTINEL_UNSET_POWER_SHAPE,
  );
  const fluids = Object.values(args.resources.fluids).filter(
    (f) => f.name !== "light_water",
  );

  const project: StreamProject = {
    format_version: PROJECT_FORMAT_VERSION,
    model_options: args.modelOptions,
    resources: { geometries, power_shapes, fluids },
    components: args.nodes,
    connections: args.edges,
    // Phase 63.1 D-02: write the anchors Record verbatim — keys are nodeIds,
    // values are AnchorEntry; no Array conversion (Record on disk).
    anchors: args.anchors,
    layout: {
      active_left_tab: args.activeLeftTab,
      active_layer: args.activeLayer,
    },
  };

  return JSON.stringify(project, null, 2);
}

// ---------------------------------------------------------------------------
// deserializeProject
// ---------------------------------------------------------------------------

/**
 * Parse a `.scp` JSON string back into a {@link StreamProject}.
 *
 * Behaviour:
 *  - Strict on `format_version`: anything other than the literal string "2.0"
 *    throws. Legacy numeric-version form throws (D-28).
 *  - Empty-state tolerant: missing top-level fields default gracefully so a
 *    minimal `{"format_version":"2.0"}` parses to a fully-populated empty
 *    project (RESEARCH Pitfall 3).
 *  - No defensive try/catch around individual fields — the function either
 *    succeeds or throws. The consumer wraps in try/catch and surfaces the
 *    user-facing dialog.
 *
 * # Throws
 *  - `SyntaxError` if `json` is not valid JSON (from `JSON.parse`)
 *  - `Error` with a message containing "format_version" if version is missing
 *    or not the literal "2.0"
 */
export function deserializeProject(json: string): StreamProject {
  // Let JSON.parse throw SyntaxError on malformed input — don't swallow it.
  const parsed = JSON.parse(json) as Record<string, unknown>;

  // Strict format_version check (INV-07, INV-08, D-28). Hard-cutover guard:
  // any missing / wrong / numeric version is a rejection — no migration.
  if (parsed.format_version !== PROJECT_FORMAT_VERSION) {
    const got =
      parsed.format_version === undefined
        ? "missing format_version"
        : "got '" + String(parsed.format_version) + "'";
    throw new Error("Invalid .scp file: expected format_version '" + PROJECT_FORMAT_VERSION + "', " + got);
  }

  // Empty-state tolerance — every top-level field is optional once
  // format_version has validated.
  const rawResources = (parsed.resources as Record<string, unknown>) ?? {};
  const geometries = (rawResources.geometries as GeometryResource[]) ?? [];
  const power_shapes =
    (rawResources.power_shapes as PowerShapeResource[]) ?? [];
  const fluids = (rawResources.fluids as FluidResource[]) ?? [];

  const rawLayout = (parsed.layout as Record<string, unknown>) ?? {};
  const layout: StreamProject["layout"] = {
    active_left_tab:
      (rawLayout.active_left_tab as ActiveLeftTab) ?? defaultLayout().active_left_tab,
    active_layer:
      (rawLayout.active_layer as LayerView) ?? defaultLayout().active_layer,
  };

  const model_options =
    (parsed.model_options as ModelOptionsSliceState) ?? defaultModelOptions();

  const components = (parsed.components as Node[]) ?? [];
  const connections = (parsed.connections as Edge[]) ?? [];
  // Phase 63.1 D-14: no legacy boundary-conditions fallback. Old .streamgui
  // files lose their anchor data on load — accepted breakage (per
  // CLAUDE.md "no back-compat during heavy dev"). When both the legacy
  // field and `anchors` are present in the JSON, `anchors` wins and the
  // legacy field is silently dropped.
  const anchors = (parsed.anchors as Record<string, AnchorEntry>) ?? {};

  return {
    format_version: PROJECT_FORMAT_VERSION,
    model_options,
    resources: { geometries, power_shapes, fluids },
    components,
    connections,
    anchors,
    layout,
  };
}

// ---------------------------------------------------------------------------
// addToRecent (unchanged from pre-Phase-62)
// ---------------------------------------------------------------------------

/**
 * Add a file path to the recent-files list.
 *
 * Behaviour (per D-07):
 *  - Deduplicate: if `newPath` already exists it is removed first.
 *  - Prepend: `newPath` is inserted at index 0.
 *  - Truncate: result is limited to 5 entries.
 *
 * # Arguments
 * - `files`   — Current recent-files array
 * - `newPath` — Absolute path of the file just opened or saved
 *
 * # Returns
 * New array (does not mutate `files`).
 */
export function addToRecent(files: string[], newPath: string): string[] {
  const deduped = files.filter((f) => f !== newPath);
  return [newPath, ...deduped].slice(0, 5);
}

// ---------------------------------------------------------------------------
// reconstructInstanceCounters (unchanged from pre-Phase-62)
// ---------------------------------------------------------------------------

/**
 * Reconstruct module-level instance counters from a loaded node array.
 *
 * When a project is loaded the in-memory `instanceCounters` object must be
 * restored so that subsequent `addNode` calls continue numbering correctly
 * (e.g. if loaded nodes include `pump_3`, the next pump should be `pump_4`).
 *
 * Naming convention assumed: `<componentId_lowercase>_<N>` (e.g. `pump_3`).
 * Nodes whose `instanceName` does not match this pattern are ignored.
 *
 * # Arguments
 * - `nodes` — ReactFlow node array from the loaded project
 *
 * # Returns
 * Record mapping lowercase component prefix to the max counter seen.
 */
export function reconstructInstanceCounters(
  nodes: Node[],
): Record<string, number> {
  const counters: Record<string, number> = {};

  for (const node of nodes) {
    const data = node.data as { componentId?: string; instanceName?: unknown };
    if (!data?.componentId || typeof data.instanceName !== "string") continue;

    const key = data.componentId.toLowerCase();
    const pattern = new RegExp(`^${key}_(\\d+)$`);
    const match = pattern.exec(data.instanceName);
    if (!match) continue;

    const num = parseInt(match[1], 10);
    if (counters[key] === undefined || num > counters[key]) {
      counters[key] = num;
    }
  }

  return counters;
}

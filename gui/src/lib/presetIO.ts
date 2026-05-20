// presetIO.ts — Pure serialization / deserialization for the .scpr v1.0 schema.
//
// Zero side-effects. All FS I/O handled in useStore.ts.
// Fully testable in vitest node environment.
//
// Per CLAUDE.md no-back-compat rule: `.scpr v1.0` is the only valid format.
// No upgraders, no fallbacks. Old or broken files throw on the strict
// format_version / kind check.

import type { Node, Edge } from "@xyflow/react";
import type {
  GeometryResource,
  PowerShapeResource,
  FluidResource,
} from "../store/useStore";

// ---------------------------------------------------------------------------
// Format constant
// ---------------------------------------------------------------------------

/**
 * Single source of truth for the .scpr format version.
 *
 * Per D-07, the on-disk schema is `format_version: "1.0"`. No migration.
 */
export const PRESET_FORMAT_VERSION = "1.0" as const;

// ---------------------------------------------------------------------------
// Name validation
// ---------------------------------------------------------------------------

/**
 * Regex for valid preset names (D-10).
 *
 * Accepts ASCII alphanumeric characters, underscores, and hyphens.
 * Rejects spaces, Unicode, path separators, dots, parens, semicolons, etc.
 */
export const PRESET_NAME_RE = /^[A-Za-z0-9_-]+$/;

/**
 * Returns `true` if `name` is a valid preset name per D-10 (`[A-Za-z0-9_-]+`).
 *
 * # Arguments
 * - `name` — The preset name string to validate.
 *
 * # Returns
 * Boolean: `true` if valid, `false` otherwise.
 */
export function isValidPresetName(name: string): boolean {
  return PRESET_NAME_RE.test(name);
}

// ---------------------------------------------------------------------------
// Types — the v1.0 schema (D-07)
// ---------------------------------------------------------------------------

/**
 * The `.scpr` v1.0 preset schema.
 *
 * A slimmed-down, self-contained sub-graph of a STREAM Composer project.
 * Contains the preset's components, internal connections, embedded resource
 * copies, and a normalized layout (bbox-top-left at (0,0) per D-11).
 */
export interface StreamPreset {
  format_version: typeof PRESET_FORMAT_VERSION;
  kind: "preset";
  name: string; // matches filename stem; [A-Za-z0-9_-]+ (D-10)
  description: string; // empty string if none
  resources: {
    geometries: GeometryResource[];
    power_shapes: PowerShapeResource[];
    fluids: FluidResource[];
  };
  components: Node[]; // ReactFlow Node[] — same shape as .scp
  connections: Edge[]; // internal edges only (after auto-extend + cross-boundary drop)
  layout: Record<string, { x: number; y: number }>; // normalized bbox-top-left=(0,0) per D-11
}

/**
 * An entry in the preset index shown in the Presets tab.
 *
 * Derived from parsing each `.scpr` file; cached in the store
 * (`projectPresets` / `libraryPresets`) by the watcher-driven
 * `refreshPresetsDir` action in useStore.ts.
 */
export interface PresetIndexEntry {
  name: string; // matches filename stem
  description: string; // from preset JSON; empty string if none
  filePath: string; // absolute path to .scpr file
  store: "project" | "library";
}

// ---------------------------------------------------------------------------
// serializePreset
// ---------------------------------------------------------------------------

/**
 * Arguments for {@link serializePreset}.
 *
 * Fluids array is always empty (light-water is excluded from presets,
 * matching the `serializeProject` light-water exclusion — RESEARCH.md Q5).
 */
export interface SerializePresetArgs {
  name: string;
  description: string;
  components: Node[];
  connections: Edge[];
  geometries: GeometryResource[];
  powerShapes: PowerShapeResource[];
  layout: Record<string, { x: number; y: number }>;
}

/**
 * Serialize the given selection to a JSON string for writing to a `.scpr` file.
 *
 * Defense-in-depth: strips `data.autoExtended` from every component node
 * before assembling (per Pitfall 7 in RESEARCH.md), even if the caller has
 * already stripped it. This prevents the transient highlight field from
 * leaking into the persisted file.
 *
 * # Arguments
 * - `args` — see {@link SerializePresetArgs}
 *
 * # Returns
 * Pretty-printed JSON matching the v1.0 `.scpr` schema.
 */
export function serializePreset(args: SerializePresetArgs): string {
  // Strip data.autoExtended from every component (defense-in-depth, Pitfall 7).
  const components = args.components.map((node) => {
    if (
      node.data &&
      typeof node.data === "object" &&
      "autoExtended" in node.data
    ) {
      // Shallow clone of data without the autoExtended key.
      const { autoExtended: _stripped, ...restData } = node.data as Record<
        string,
        unknown
      >;
      return { ...node, data: restData };
    }
    return node;
  });

  const preset: StreamPreset = {
    format_version: PRESET_FORMAT_VERSION,
    kind: "preset",
    name: args.name,
    description: args.description,
    resources: {
      geometries: args.geometries,
      power_shapes: args.powerShapes,
      fluids: [], // light-water excluded (per RESEARCH.md Q5)
    },
    components,
    connections: args.connections,
    layout: args.layout,
  };

  return JSON.stringify(preset, null, 2);
}

// ---------------------------------------------------------------------------
// deserializePreset
// ---------------------------------------------------------------------------

/**
 * Parse a `.scpr` JSON string back into a {@link StreamPreset}.
 *
 * Behaviour:
 *  - Strict on `format_version`: anything other than the literal string "1.0"
 *    throws (with a descriptive message indicating "missing format_version" or
 *    "got '<value>'").
 *  - Strict on `kind`: anything other than the literal string "preset" throws.
 *  - Defensive defaults only for optional-by-convention fields:
 *      `description ?? ""`, `resources.fluids ?? []`.
 *  - No defaults for `format_version`, `kind`, `name`, `components`,
 *    `connections`, or `layout` — those are required by schema; missing fields
 *    surface as type errors in tests.
 *
 * # Arguments
 * - `json` — Raw JSON string read from a `.scpr` file.
 *
 * # Returns
 * Fully-typed {@link StreamPreset}.
 *
 * # Throws
 * - `SyntaxError` if `json` is not valid JSON.
 * - `Error` with a message containing "format_version" if version is missing
 *   or not the literal "1.0".
 * - `Error` with a message containing "kind" if kind is missing or not "preset".
 */
export function deserializePreset(json: string): StreamPreset {
  // Let JSON.parse throw SyntaxError on malformed input — don't swallow it.
  const parsed = JSON.parse(json) as Record<string, unknown>;

  // Strict format_version check.
  if (parsed.format_version !== PRESET_FORMAT_VERSION) {
    const got =
      parsed.format_version === undefined
        ? "missing format_version"
        : "got '" + String(parsed.format_version) + "'";
    throw new Error(
      "Invalid .scpr file: expected format_version '" +
        PRESET_FORMAT_VERSION +
        "', " +
        got,
    );
  }

  // Strict kind check.
  if (parsed.kind !== "preset") {
    throw new Error(
      "Invalid .scpr file: expected kind 'preset', got '" +
        String(parsed.kind) +
        "'",
    );
  }

  // Build the typed result.
  const rawResources = (parsed.resources as Record<string, unknown>) ?? {};

  return {
    format_version: PRESET_FORMAT_VERSION,
    kind: "preset",
    name: parsed.name as string,
    description: (parsed.description as string) ?? "",
    resources: {
      geometries: (rawResources.geometries as GeometryResource[]) ?? [],
      power_shapes: (rawResources.power_shapes as PowerShapeResource[]) ?? [],
      fluids: (rawResources.fluids as FluidResource[]) ?? [],
    },
    components: parsed.components as Node[],
    connections: parsed.connections as Edge[],
    layout: parsed.layout as Record<string, { x: number; y: number }>,
  };
}

// ---------------------------------------------------------------------------
// autoExtendSelection
// ---------------------------------------------------------------------------

/**
 * Extend a selection by one hop along BC edges only (D-12 / D-13).
 *
 * Starting from `selectedNodeIds`, adds any unselected component on the
 * other end of a BC edge connected to a selected component. This is one
 * hop only — non-recursive (D-13).
 *
 * After extension, partitions all edges into:
 *  - `keptEdges`: both endpoints in `extendedIds` — included in the preset.
 *  - `droppedEdges`: one or both endpoints outside `extendedIds` — cross-
 *    boundary; excluded from the preset.
 *
 * # Arguments
 * - `selectedNodeIds` — The user's explicit selection (a Set of node IDs).
 * - `_allNodes`       — All nodes currently on the canvas (unused in the
 *                       current algorithm but included for API consistency
 *                       and potential future use).
 * - `allEdges`        — All edges currently on the canvas.
 *
 * # Returns
 * An object with:
 *  - `extendedIds`  — The original selection plus any one-hop BC neighbours.
 *  - `keptEdges`    — Edges fully inside `extendedIds`.
 *  - `droppedEdges` — Edges with at least one endpoint outside `extendedIds`.
 */
export function autoExtendSelection(
  selectedNodeIds: Set<string>,
  _allNodes: Node[],
  allEdges: Edge[],
): { extendedIds: Set<string>; keptEdges: Edge[]; droppedEdges: Edge[] } {
  // Copy the selected IDs into a mutable set.
  const extendedIds = new Set(selectedNodeIds);

  // Single-pass: for each BC edge, add the other endpoint if exactly one
  // endpoint is currently in the extended set (XOR check).
  for (const edge of allEdges) {
    if (edge.type !== "bcEdge") continue;
    const sourceIn = extendedIds.has(edge.source);
    const targetIn = extendedIds.has(edge.target);
    if (sourceIn !== targetIn) {
      // Exactly one endpoint is in the set — add the other (one hop only).
      if (sourceIn) {
        extendedIds.add(edge.target);
      } else {
        extendedIds.add(edge.source);
      }
    }
  }

  // Partition all edges: kept iff both endpoints are in extendedIds.
  const keptEdges: Edge[] = [];
  const droppedEdges: Edge[] = [];
  for (const edge of allEdges) {
    if (extendedIds.has(edge.source) && extendedIds.has(edge.target)) {
      keptEdges.push(edge);
    } else {
      droppedEdges.push(edge);
    }
  }

  return { extendedIds, keptEdges, droppedEdges };
}

// ---------------------------------------------------------------------------
// normalizeLayout
// ---------------------------------------------------------------------------

/**
 * Normalize a set of nodes' positions so the bounding box top-left is at (0, 0).
 *
 * Per D-11: layout is normalized to bbox-top-left at (0,0) at save time,
 * making drop-placement math trivial and decoupling saved coordinates from
 * wherever the user had the components on the source canvas.
 *
 * # Arguments
 * - `nodes` — ReactFlow Node array whose positions should be normalized.
 *
 * # Returns
 * A `Record<nodeId, { x, y }>` where every position is offset by
 * `(-minX, -minY)` of the original bounding box. Returns `{}` for an
 * empty array without crashing.
 */
export function normalizeLayout(
  nodes: Node[],
): Record<string, { x: number; y: number }> {
  if (nodes.length === 0) return {};

  const minX = Math.min(...nodes.map((n) => n.position.x));
  const minY = Math.min(...nodes.map((n) => n.position.y));

  const layout: Record<string, { x: number; y: number }> = {};
  for (const node of nodes) {
    layout[node.id] = {
      x: node.position.x - minX,
      y: node.position.y - minY,
    };
  }
  return layout;
}

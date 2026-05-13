// bcMode.ts — Phase 63: shared BCs-tab + canvas BC edge types and pure helpers.
//
// Zero React dependencies, zero zustand dependencies, zero ReactFlow imports.
// This module is consumed by:
//   - gui/src/store/useStore.ts        (the BC slice + actions; Phase 63-B-02)
//   - gui/src/lib/codeGenerator.ts     (per-mode emit logic; Phase 63-B-04)
//   - gui/src/components/sidebar/BCsTabForm.tsx     (UI, Phase 63-C — not yet)
//   - gui/src/components/BCEdge.tsx                 (custom edge, Phase 63-D — not yet)
//   - gui/src/components/CanvasPanel.tsx (isValidConnection — must stay PURE;
//                                         see RESEARCH Pitfall 7. This is why
//                                         `isAllowedBCConnection` is registry-
//                                         grounded by component ID rather than
//                                         reaching into store state.)
//
// Single composite key: `${componentId}::${externalInputName}` is the canonical
// store-key shape. Component UUIDs are crypto.randomUUID() outputs (no `::`),
// so the separator is collision-free for v1.2 (D-23).
//
// Sentinel-via-absence (D-09): `bcMode[key] === undefined` is the required-unset
// sentinel. There is NO `{mode: "unset"}` entry. Codegen emits a TODO comment +
// no binding equation when the key is missing. UI checks `active === undefined`
// to render the no-active-pill state. Mirrors useStore.ts SENTINEL_UNSET_POWER_
// SHAPE in spirit, but here the *absence* is the sentinel — there is no UUID.

// ---------------------------------------------------------------------------
// BCMode discriminated union (D-04..D-08, D-23)
// ---------------------------------------------------------------------------

/** The five BC mode strings. Lowercase by store convention; the registry's
 *  `bc_modes` array uses Capitalized labels for display, but the store entries
 *  use the lowercase form for type discrimination. */
export type BCMode = "value" | "profile" | "function" | "mark" | "source";

/** Per-(componentId, externalInputName) entry in the `bcMode` store slice. The
 *  discriminated union mirrors useStore.PowerShapeResource.kind in shape (see
 *  63-PATTERNS.md "Discriminated-union pattern"). */
export type BCModeEntry =
  | { mode: "value"; value: number }
  | { mode: "profile"; preset: "cosine"; amplitude: number; peakingFactor: number }
  | { mode: "profile"; preset: "file"; path: string }
  | { mode: "function"; signature: "fn(t)" | "fn(t, i)"; functionName: string }
  | { mode: "mark" }
  | { mode: "source"; sourceNodeId: string };

// ---------------------------------------------------------------------------
// BCEdgeData — payload riding on ReactFlow `Edge.data` for `type === "bcEdge"`
// edges. Populated by `enrichEdges` BCPort branch in useStore.ts.
// ---------------------------------------------------------------------------

export interface BCEdgeData {
  /** The consumer node id (Channel / ChannelHeatFlux). */
  componentId: string;
  /** The external_input variable name on the consumer (e.g., "T_wall_left"). */
  externalInputName: string;
  /** Which side(s) the edge binds. Default `both`. Cycles via the inline chip
   *  (Phase 63-D, D-11). The `cycleBCEdgeTargetSide` helper below walks the
   *  cycle order; the store action of the same name applies it to an edge. */
  targetSide: "left" | "right" | "both";
}

// ---------------------------------------------------------------------------
// bcModeKey — the canonical composite-key constructor (D-23)
// ---------------------------------------------------------------------------

/**
 * Build the composite key used in the `bcMode` store slice.
 *
 * Format: `${componentId}::${externalInputName}` — the `::` separator is safe
 * because component UUIDs (crypto.randomUUID outputs) do not contain `::` and
 * external_input names are validated Julia identifiers (D-23 collision-free).
 *
 * @param componentId  The consumer node's id (NOT its componentId/type — the
 *                     per-instance node id from `state.nodes[i].id`).
 * @param externalInputName  e.g., "T_wall_left", "T_wall_right", "q_left", "q_right".
 */
export function bcModeKey(componentId: string, externalInputName: string): string {
  return `${componentId}::${externalInputName}`;
}

// ---------------------------------------------------------------------------
// isAllowedBCConnection — registry-grounded type allow-list (D-21)
// ---------------------------------------------------------------------------
//
// Pure. No store reads. Consumed by `CanvasPanel.isValidConnection` (Phase 63-D)
// — must stay pure because ReactFlow re-invokes the callback on every drag
// frame. Mutating state in there violates the ReactFlow purity rule (RESEARCH
// Pitfall 7).
//
// The allow-list is intentionally registry-grounded by component-ID string
// rather than by querying the registry — this keeps the function dependency-
// free of the registry module and trivially testable. The four enumerated
// pairs are the complete set of allowed BCPort connections in v1.2.

export function isAllowedBCConnection(
  sourceComponentId: string,
  targetComponentId: string,
): boolean {
  // WallTemperature.T_wall_out → Channel.T_wall_*  (allowed)
  if (sourceComponentId === "WallTemperature" && targetComponentId === "Channel") {
    return true;
  }
  // HeatFluxSource.q_out → ChannelHeatFlux.q_*  (allowed)
  if (sourceComponentId === "HeatFluxSource" && targetComponentId === "ChannelHeatFlux") {
    return true;
  }
  // Everything else (including any pair where target is ChannelAndContacts —
  // CAC has no BCs tab; wall conditions arrive via ThermalPort only per
  // feedback_channel_hd_connection_rule.md / D-25) is hard-blocked.
  return false;
}

// ---------------------------------------------------------------------------
// cycleBCEdgeTargetSide — pure helper (D-11)
// ---------------------------------------------------------------------------
//
// Cycle order: both → left → right → both. Re-exported under the same name
// from the store as an action on a specific edge id; this pure helper is the
// underlying cycle function.

export function cycleBCEdgeTargetSide(
  current: "left" | "right" | "both",
): "left" | "right" | "both" {
  if (current === "both") return "left";
  if (current === "left") return "right";
  return "both";
}

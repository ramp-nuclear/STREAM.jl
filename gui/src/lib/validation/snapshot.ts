// snapshot.ts — ValidationSnapshot type + buildValidationSnapshot helper (Phase 71)
//
// D-06: ValidationSnapshot carries everything any rule could read.
// Rule files import this type to declare their run() parameter type.
// buildValidationSnapshot(state) is called by the store subscription
// (initValidation) once per debounced tick.

import type { Node, Edge } from "@xyflow/react";
import type { AnchorEntry } from "@/lib/anchors";
import type { BCModeEntry } from "@/lib/bcMode";
import type { ComponentDefinition } from "../../registry/types";
import type {
  AppState,
  ResourcesSliceState,
} from "../../store/useStore";
import { getComponent } from "../../registry";

// ---------------------------------------------------------------------------
// ValidationSnapshot — the read-only view of store state passed to every rule
// ---------------------------------------------------------------------------

/** Pure-data snapshot of the store fields that validators are allowed to read.
 *
 * Rule files MUST NOT import the store directly (D-06 purity invariant).
 * They receive a ValidationSnapshot built once per debounced tick by
 * initValidation() in useStore.ts.
 *
 * # Fields
 * - `nodes`: ReactFlow Node[] at the time of the snapshot
 * - `edges`: ReactFlow Edge[] at the time of the snapshot
 * - `anchors`: Record<nodeId, AnchorEntry> — pressure-anchor slice
 * - `bcMode`: Record<key, BCModeEntry> — BC mode slice (key = `${componentId}::${externalInputName}`)
 * - `resources`: geometry / power-shape / fluid resource records
 * - `getComponentDef`: look up a ComponentDefinition by componentId
 */
export interface ValidationSnapshot {
  nodes: Node[];
  edges: Edge[];
  anchors: Record<string, AnchorEntry>;
  bcMode: Record<string, BCModeEntry>;
  resources: ResourcesSliceState;
  getComponentDef: (id: string) => ComponentDefinition | undefined;
}

// ---------------------------------------------------------------------------
// buildValidationSnapshot — builds a snapshot from the full AppState
// ---------------------------------------------------------------------------

/** Build a ValidationSnapshot from the current store state.
 *
 * Called by initValidation()'s debounced subscription immediately before
 * runValidators(snapshot). Only the fields declared in ValidationSnapshot
 * are included — all UI state, history stacks, and session-only slices are
 * excluded.
 *
 * # Arguments
 * - `state`: the full AppState (obtained via useStore.getState())
 *
 * # Returns
 * A ValidationSnapshot suitable for passing to runValidators().
 */
export function buildValidationSnapshot(state: AppState): ValidationSnapshot {
  return {
    nodes: state.nodes,
    edges: state.edges,
    anchors: state.anchors,
    bcMode: state.bcMode,
    resources: state.resources,
    getComponentDef: (id: string): ComponentDefinition | undefined =>
      getComponent(id),
  };
}

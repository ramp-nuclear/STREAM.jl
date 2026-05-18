// Phase 69 Plan 01 Task 3 — pure search-pool helper for the Ctrl+P palette.
//
// Mirrors the `gui/src/lib/selectors/nodeErrors.ts` pattern (Phase 63.1 D-19):
// zero React, zero zustand, zero ReactFlow runtime imports — pure data
// transformation. CommandPalette.tsx wraps the call in useMemo so the pool
// only rebuilds when nodes/resources change.
//
// Search-pool rules (locked by Plan 01 <behavior> + D-05/D-06):
//   - one row per canvas node (instance name + component type label)
//   - nodes with an unknown componentId are silently skipped (defensive)
//   - one row per geometry / power-shape / fluid resource
//   - SENTINEL_UNSET_POWER_SHAPE is filtered out (mirrors ResourcesTreePanel D-26)
//   - SENTINEL_LIGHT_WATER_FLUID is NOT filtered — light_water IS a real
//     selectable fluid; only the power-shape "(leave unset)" placeholder
//     should never appear as a jump target
//   - exactly one "Project Options" row (D-05) appended last

import type { Node } from "@xyflow/react";

import { SENTINEL_UNSET_POWER_SHAPE, type ResourcesSliceState, type StreamNodeData } from "@/store/useStore";
import { getComponent } from "@/registry";
import type { ComponentDefinition } from "@/registry/types";

/**
 * Discriminated union of palette result items. The `kind` tag drives the
 * row icon, the on-select dispatch (Plan 02), and the off-layer chip
 * (D-08; only `kind === "component"` items consult `activeLayers`).
 */
export type SearchItem =
  | {
      kind: "component";
      /** node.id — also the cmdk filter value. */
      id: string;
      /** Instance name as shown on the canvas (StreamNodeData.instanceName). */
      name: string;
      /** Component type label (registry `label`, e.g. "Channel"). */
      typeLabel: string;
      /** Full node reference — Plan 02 reads `.position` for setCenter (D-04). */
      node: Node;
      /** Component definition — Plan 02 reads `.category` for layer lookup (D-03). */
      comp: ComponentDefinition;
    }
  | { kind: "geometry"; id: string; name: string; uuid: string }
  | { kind: "powerShape"; id: string; name: string; uuid: string }
  | { kind: "fluid"; id: string; name: string; uuid: string }
  | { kind: "modelOptions"; id: "modelOptions"; name: "Project Options" };

/**
 * Build the flat list of jump-to-X items the command palette searches over.
 *
 * Pure function: same `(nodes, resources)` input → identical output every time.
 * Designed for `useMemo([nodes, resources])` consumption inside CommandPalette.
 *
 * @param nodes Current canvas nodes (read from `useStore`).
 * @param resources Resources slice (geometries, powerShapes, fluids).
 * @returns Flat array of `SearchItem`s, always ending with the "Project Options" row.
 */
export function buildSearchPool(
  nodes: Node[],
  resources: ResourcesSliceState,
): SearchItem[] {
  const items: SearchItem[] = [];

  // Components — one row per canvas node, instanceName as the search target,
  // typeLabel as the inline secondary label. Unknown componentId is dropped
  // (defensive — registry should be consistent, but we never crash the palette
  // on a stale node).
  for (const node of nodes) {
    const data = node.data as unknown as StreamNodeData;
    const comp = getComponent(data.componentId);
    if (!comp) continue;
    items.push({
      kind: "component",
      id: node.id,
      name: data.instanceName,
      typeLabel: comp.label,
      node,
      comp,
    });
  }

  // Geometries — every record.
  for (const g of Object.values(resources.geometries)) {
    items.push({
      kind: "geometry",
      id: `geo:${g.uuid}`,
      name: g.name,
      uuid: g.uuid,
    });
  }

  // Power shapes — skip the (leave unset) sentinel (mirrors ResourcesTreePanel
  // D-26 filtering; the sentinel is not a navigable target).
  for (const p of Object.values(resources.powerShapes)) {
    if (p.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;
    items.push({
      kind: "powerShape",
      id: `ps:${p.uuid}`,
      name: p.name,
      uuid: p.uuid,
    });
  }

  // Fluids — every record (no sentinel filtering; light_water is a real
  // selectable fluid).
  for (const f of Object.values(resources.fluids)) {
    items.push({
      kind: "fluid",
      id: `fl:${f.uuid}`,
      name: f.name,
      uuid: f.uuid,
    });
  }

  // Single "Project Options" row, always emitted last (D-05).
  items.push({
    kind: "modelOptions",
    id: "modelOptions",
    name: "Project Options",
  });

  return items;
}

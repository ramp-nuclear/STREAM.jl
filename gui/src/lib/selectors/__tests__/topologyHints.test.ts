// @vitest-environment node
//
// topologyHints.test.ts — Phase 64 Plan 04 (RED → GREEN).
//
// Unit tests for the pure topology-hint validator `selectTopologyHints`
// (D-15). The selector emits `"topology-axis-collision"` when a node has BOTH
// a FlowPort AND a thermal pair AND `detectAxisCollision` (Plan 01) returns
// true — i.e., the §3.4 "crowded edge" CAC case where flow + thermal layers
// both resolve to the same axis.
//
// Like `nodeErrors.test.ts`, this is a pure-selector test: zero React, zero
// Zustand, zero ReactFlow runtime imports. The selector is wired into
// `StreamNode.tsx` via a primitive-boolean Zustand selector (Pattern 1 / Pitfall 3).

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ComponentDefinition, Port } from "../../../registry/types";
import {
  selectTopologyHints,
  HINT_AXIS_COLLISION,
} from "../topologyHints";

// ---------------------------------------------------------------------------
// Fixture helpers (inline, small — match autoflip.test.ts style).
// ---------------------------------------------------------------------------

function makeNode(
  id: string,
  componentId: string,
  x: number,
  y: number,
  parameters: Record<string, unknown> = {},
): Node {
  return {
    id,
    type: "streamNode",
    position: { x, y },
    measured: { width: 140, height: 70 },
    data: { componentId, instanceName: id, parameters },
  } as unknown as Node;
}

function flowEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id,
    source,
    sourceHandle,
    target,
    targetHandle,
    type: "hydraulicEdge",
  } as Edge;
}

function thermalEdge(
  id: string,
  source: string,
  sourceHandle: string,
  target: string,
  targetHandle: string,
): Edge {
  return {
    id,
    source,
    sourceHandle,
    target,
    targetHandle,
    type: "default",
  } as Edge;
}

// Component fixtures — mirror gui/src/registry/components.json for the three
// shapes this validator cares about: dual-layer (CAC), flow-only (Pump),
// thermal-only-pair (HeatDiffusion).

const CAC_DEF: ComponentDefinition = {
  id: "ChannelAndContacts",
  label: "Channel and Contacts",
  category: "Hydraulic",
  description: "test fixture",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
    {
      name: "thermal_left",
      type: "ThermalPort",
      array_size: "n",
      default_axis: "vertical",
      pair_with: "thermal_right",
    },
    {
      name: "thermal_right",
      type: "ThermalPort",
      array_size: "n",
      default_axis: "vertical",
      pair_with: "thermal_left",
    },
  ] as Port[],
  parameters: [],
} as unknown as ComponentDefinition;

const PUMP_DEF: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "test fixture",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ] as Port[],
  parameters: [],
} as unknown as ComponentDefinition;

const HD_DEF: ComponentDefinition = {
  id: "HeatDiffusion",
  label: "Heat Diffusion",
  category: "Thermal",
  description: "test fixture",
  ports: [
    {
      name: "thermal_left",
      type: "ThermalPort",
      array_size: "nz",
      default_axis: "horizontal",
      pair_with: "thermal_right",
    },
    {
      name: "thermal_right",
      type: "ThermalPort",
      array_size: "nz",
      default_axis: "horizontal",
      pair_with: "thermal_left",
    },
  ] as Port[],
  parameters: [],
} as unknown as ComponentDefinition;

const getComponent = (id: string): ComponentDefinition | undefined => {
  switch (id) {
    case "ChannelAndContacts":
      return CAC_DEF;
    case "Pump":
      return PUMP_DEF;
    case "HeatDiffusion":
      return HD_DEF;
    default:
      return undefined;
  }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("selectTopologyHints (D-15)", () => {
  it("D-15: CAC with hydraulic neighbor LEFT and thermal neighbor RIGHT (both horizontal axes) → emits 'topology-axis-collision'", () => {
    // Layout:
    //   pump (-300, 0) --flow--> cac (0, 0) --thermal--> hd (300, 0)
    // Flow axis: cac.port_in faces LEFT (neighbor pump is left of cac).
    // Thermal axis: thermal neighbor hd is RIGHT — pair axis flips to horizontal.
    // Both layers want the horizontal axis → collision.
    const state = {
      nodes: [
        makeNode("pump1", "Pump", -300, 0),
        makeNode("cac1", "ChannelAndContacts", 0, 0, { n: 4 }),
        makeNode("hd1", "HeatDiffusion", 300, 0, { nz: 4, nx: 4 }),
      ],
      edges: [
        flowEdge("e_flow", "pump1", "port_out", "cac1", "port_in"),
        thermalEdge("e_th", "cac1", "thermal_right", "hd1", "thermal_left"),
      ],
    };
    expect(selectTopologyHints(state, "cac1", getComponent)).toEqual([
      "topology-axis-collision",
    ]);
    expect(selectTopologyHints(state, "cac1", getComponent)).toContain(
      HINT_AXIS_COLLISION,
    );
  });

  it("D-15: CAC with hydraulic neighbor LEFT and thermal neighbor ABOVE (axes orthogonal) → returns []", () => {
    // Flow axis: horizontal (pump to the left).
    // Thermal axis: vertical (hd directly above).
    // Orthogonal → no collision.
    const state = {
      nodes: [
        makeNode("pump1", "Pump", -300, 0),
        makeNode("cac1", "ChannelAndContacts", 0, 0, { n: 4 }),
        makeNode("hd1", "HeatDiffusion", 0, -300, { nz: 4, nx: 4 }),
      ],
      edges: [
        flowEdge("e_flow", "pump1", "port_out", "cac1", "port_in"),
        thermalEdge("e_th", "cac1", "thermal_left", "hd1", "thermal_right"),
      ],
    };
    expect(selectTopologyHints(state, "cac1", getComponent)).toEqual([]);
  });

  it("D-15: Pump (no thermal pair) → returns [] regardless of neighbors", () => {
    const state = {
      nodes: [
        makeNode("p1", "Pump", 0, 0),
        makeNode("p2", "Pump", 300, 0),
      ],
      edges: [flowEdge("e", "p1", "port_out", "p2", "port_in")],
    };
    expect(selectTopologyHints(state, "p1", getComponent)).toEqual([]);
    expect(selectTopologyHints(state, "p2", getComponent)).toEqual([]);
  });

  it("D-15: HeatDiffusion (thermal pair only, no FlowPort) → returns []", () => {
    // D-15 only fires when BOTH layers exist on the same component — HD is
    // thermal-only, so even with the maximal crowded layout the hint is
    // suppressed.
    const state = {
      nodes: [
        makeNode("cac1", "ChannelAndContacts", -300, 0, { n: 4 }),
        makeNode("hd1", "HeatDiffusion", 0, 0, { nz: 4, nx: 4 }),
        makeNode("cac2", "ChannelAndContacts", 300, 0, { n: 4 }),
      ],
      edges: [
        thermalEdge("e1", "cac1", "thermal_right", "hd1", "thermal_left"),
        thermalEdge("e2", "hd1", "thermal_right", "cac2", "thermal_left"),
      ],
    };
    expect(selectTopologyHints(state, "hd1", getComponent)).toEqual([]);
  });

  it("D-15: isolated CAC (no edges) → returns [] (no axes to collide)", () => {
    const state = {
      nodes: [makeNode("cac1", "ChannelAndContacts", 0, 0, { n: 4 })],
      edges: [],
    };
    expect(selectTopologyHints(state, "cac1", getComponent)).toEqual([]);
  });

  it("D-15: returns [] when node id not found", () => {
    const state = {
      nodes: [makeNode("cac1", "ChannelAndContacts", 0, 0, { n: 4 })],
      edges: [],
    };
    expect(selectTopologyHints(state, "missing", getComponent)).toEqual([]);
  });

  it("D-15: returns [] when component lookup fails (unknown componentId)", () => {
    const state = {
      nodes: [makeNode("x1", "UnknownComponent", 0, 0)],
      edges: [],
    };
    expect(selectTopologyHints(state, "x1", getComponent)).toEqual([]);
  });

  it("Stable shape: returns a fresh array each call (consumers MUST wrap with .length > 0)", () => {
    // Consumers wrap with `selectTopologyHints(...).length > 0` and return a
    // primitive boolean; the selector itself does not memoize. Empty-result
    // calls return [] which is not referentially equal across calls — that's
    // fine because the consumer collapses to a boolean before Zustand sees it.
    const state = {
      nodes: [makeNode("cac1", "ChannelAndContacts", 0, 0, { n: 4 })],
      edges: [],
    };
    const a = selectTopologyHints(state, "cac1", getComponent);
    const b = selectTopologyHints(state, "cac1", getComponent);
    expect(a).toEqual([]);
    expect(b).toEqual([]);
    // referential inequality is expected and acceptable per consumer-wrap rule
    expect(Object.is(a, b)).toBe(false);
  });

  it("Tag constant: HINT_AXIS_COLLISION is the exact string emitted", () => {
    expect(HINT_AXIS_COLLISION).toBe("topology-axis-collision");
  });
});

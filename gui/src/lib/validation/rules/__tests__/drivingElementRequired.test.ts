// drivingElementRequired.test.ts — Unit tests for VALD-03 (Phase 71, Plan 08)
//
// D-16: drivingElementRequired lifts VALD-03 from validateTopology() per D-16.
// System-level rule: targets = [] (no specific node).
//
// Test cases:
//   1. snapshot.nodes empty → 1 error result, validatorId 'driving_element_required'
//   2. snapshot.nodes contains a Pump → no result
//   3. snapshot.nodes contains a Gravity → no result
//   4. snapshot.nodes contains only Channel + HX (no driving element) → 1 error

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";

// Import the rule (GREEN phase will create this file)
import { drivingElementRequired } from "../drivingElementRequired";

// ---------------------------------------------------------------------------
// Minimal node factory
// ---------------------------------------------------------------------------

function makeNode(id: string, componentId: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: { componentId, instanceName: componentId.toLowerCase() + "_1", parameters: {} },
  };
}

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(nodes: Node[], edges: Edge[] = []): ValidationSnapshot {
  return {
    nodes,
    edges,
    anchors: {},
    bcMode: {},
    resources: { geometries: {}, powerShapes: {}, fluids: {} },
    getComponentDef: () => undefined,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("drivingElementRequired validator", () => {
  it("emits one warning when nodes list is empty", () => {
    const snapshot = makeSnapshot([]);
    const results = drivingElementRequired.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("warning");
    expect(results[0].validatorId).toBe("driving_element_required");
    expect(results[0].id).toBe("driving_element_required::system");
    expect(results[0].targets).toEqual([]);
    expect(results[0].description).toBe("No driving element");
  });

  it("emits no result when a Pump node exists", () => {
    const snapshot = makeSnapshot([
      makeNode("n1", "Channel"),
      makeNode("n2", "Pump"),
    ]);
    const results = drivingElementRequired.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits no result when a Gravity node exists", () => {
    const snapshot = makeSnapshot([
      makeNode("n1", "Channel"),
      makeNode("n2", "Gravity"),
    ]);
    const results = drivingElementRequired.run(snapshot);
    expect(results).toHaveLength(0);
  });

  it("emits one warning when nodes contain only non-driving elements", () => {
    const snapshot = makeSnapshot([
      makeNode("n1", "Channel"),
      makeNode("n2", "HeatExchanger"),
    ]);
    const results = drivingElementRequired.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("warning");
    expect(results[0].validatorId).toBe("driving_element_required");
  });
});

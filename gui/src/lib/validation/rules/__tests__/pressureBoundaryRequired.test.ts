// pressureBoundaryRequired.test.ts — Unit tests for VALD-02 (Phase 71, Plan 08)
//
// D-16: pressureBoundaryRequired lifts VALD-02 from validateTopology() per D-16.
// System-level rule: targets = [] (no specific node).
//
// Test cases:
//   1. snapshot.anchors = {} → 1 error result, validatorId 'pressure_boundary_required'
//   2. snapshot.anchors has one entry → no result

import { describe, it, expect } from "vitest";
import type { Node, Edge } from "@xyflow/react";
import type { ValidationSnapshot } from "../../snapshot";
import type { AnchorEntry } from "@/lib/anchors";

// Import the rule (GREEN phase will create this file)
import { pressureBoundaryRequired } from "../pressureBoundaryRequired";

// ---------------------------------------------------------------------------
// Snapshot factory
// ---------------------------------------------------------------------------

function makeSnapshot(
  anchors: Record<string, AnchorEntry>,
  nodes: Node[] = [],
  edges: Edge[] = [],
): ValidationSnapshot {
  return {
    nodes,
    edges,
    anchors,
    bcMode: {},
    resources: { geometries: {}, powerShapes: {}, fluids: {} },
    getComponentDef: () => undefined,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("pressureBoundaryRequired validator", () => {
  it("emits one error when anchors is empty", () => {
    const snapshot = makeSnapshot({});
    const results = pressureBoundaryRequired.run(snapshot);
    expect(results).toHaveLength(1);
    expect(results[0].severity).toBe("error");
    expect(results[0].validatorId).toBe("pressure_boundary_required");
    expect(results[0].id).toBe("pressure_boundary_required::system");
    expect(results[0].targets).toEqual([]);
    expect(results[0].description).toBe("No pressure anchor");
  });

  it("emits no result when at least one anchor exists", () => {
    const anchors: Record<string, AnchorEntry> = {
      n1: { portField: "port_in.P", value: 1e5 },
    };
    const snapshot = makeSnapshot(anchors);
    const results = pressureBoundaryRequired.run(snapshot);
    expect(results).toHaveLength(0);
  });
});

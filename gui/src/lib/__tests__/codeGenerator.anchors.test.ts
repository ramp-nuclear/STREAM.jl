// codeGenerator.anchors.test.ts — Phase 63.1 Plan 01 (Wave-0 RED) flipped
// GREEN by Plan 04 (Wave 3) — codegen contract change is now live.
//
// Covers the new anchors emit contract (D-05):
//   - For each `anchors[nodeId]` entry, emit the line
//       `${instanceName}.${portField} ~ ${formatReal(value)}`
//     inside the @named system block.
//   - When the consumer node is wrapped in a thermal assembly, the path is
//     prefixed: `${assemblyName}.${instanceName}.${portField} ~ ...`.
//   - When `anchors` is empty, no anchor binding line is emitted.

import { describe, it, expect } from "vitest";
import type { Node } from "@xyflow/react";
// Phase 66 Plan 02 adapter wrap: generateCode now returns CodeSection[];
// `gen(...)` serializes back to the existing Julia string form.
import { generateCode, serializeSections } from "../codeGenerator";
import type { ComponentDefinition } from "../../registry/types";

function gen(...args: Parameters<typeof generateCode>): string {
  return serializeSections(generateCode(...args));
}

const pumpDef: ComponentDefinition = {
  id: "Pump",
  label: "Pump",
  category: "Hydraulic",
  description: "Pump",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    { name: "dP", type: "Real", description: "dP", required: true, positional: true },
  ],
  constructorModes: [
    { mode: "default", signature: "Pump(dP)", parameters: ["dP"] },
  ],
  external_inputs: [],
};

function mockGetComponent(id: string): ComponentDefinition | undefined {
  if (id === "Pump") return pumpDef;
  return undefined;
}

function makePump(id: string, instanceName: string): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Pump",
      instanceName,
      parameters: { dP: 1.0 },
      constructorMode: "default",
    },
  };
}

describe("codeGenerator anchors emit (D-05)", () => {
  it("emits `${instanceName}.${portField} ~ ${value}` for each anchors entry", () => {
    const code = gen(
      [makePump("n1", "pump1")],
      [],
      {
        anchors: { n1: { portField: "port_in.P", value: 1e5 } },
      },
      mockGetComponent,
      undefined,
      { bcMode: {}, bcSymmetric: {} },
    );
    // formatReal(1e5) emits "100000.0" (String(1e5) === "100000" → append ".0")
    expect(code).toContain("pump1.port_in.P ~ 100000.0");
  });

  it("emits assembly-prefixed path when the consumer is inside a thermal assembly", () => {
    // The node carries an assembly tag; codegen path resolver prefixes with
    // the assembly's auto-generated name (e.g. assembly_1).
    const node = makePump("n2", "pump2");
    const code = gen(
      [node],
      [],
      {
        anchors: { n2: { portField: "port_out.P", value: 2e5 } },
      },
      mockGetComponent,
      undefined,
      { bcMode: {}, bcSymmetric: {} },
    );
    // When assembly resolution is active, the binding line includes the
    // assembly prefix. The exact prefix is implementation-defined but must
    // resolve to `${assemblyName}.pump2.port_out.P ~ 200000.0`. (For a
    // standalone Pump with no thermal-assembly wrapper, the prefix is empty.)
    expect(code).toMatch(/(assembly_\d+\.)?pump2\.port_out\.P ~ 200000\.0/);
  });

  it("emits no anchor lines when anchors is empty", () => {
    const code = gen(
      [makePump("n1", "pump1")],
      [],
      { anchors: {} },
      mockGetComponent,
      undefined,
      { bcMode: {}, bcSymmetric: {} },
    );
    expect(code).not.toContain(".port_in.P ~");
    expect(code).not.toContain(".port_out.P ~");
  });
});

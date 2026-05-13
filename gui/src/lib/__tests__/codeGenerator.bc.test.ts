// codeGenerator.bc.test.ts — Phase 63-B-04
//
// Per-mode BC emit coverage for the five BC modes (Value / Profile-cosine /
// Profile-file / Function / Mark + Source) plus the required-unset (D-09)
// sentinel-via-absence form and symmetric L=R expansion (D-05). Mirrors the
// `codeGenerator.resources.test.ts` idiom: build a minimal Channel-only fixture,
// run `generateCode(...)`, assert substring presence in the emitted .jl text.
//
// Reference: 63-B-PLAN.md Task 63-B-04, CONTEXT D-06..D-09, CD-01..CD-02.

import { describe, it, expect } from "vitest";
import type { Node } from "@xyflow/react";
import { generateCode } from "../codeGenerator";
import type {
  CodegenBCsState,
  CodegenResources,
} from "../codeGenerator";
import type { CodegenAnchorsState } from "../anchors";
import type { ComponentDefinition } from "../../registry/types";
import type { BCModeEntry } from "../bcMode";
import { bcModeKey } from "../bcMode";

// ---------------------------------------------------------------------------
// Mock component registry — minimal Channel + WallTemperature + ChannelHeatFlux
// + HeatFluxSource (matches the real registry's external_inputs declarations).
// ---------------------------------------------------------------------------

const channelDef: ComponentDefinition = {
  id: "Channel",
  label: "Channel",
  category: "Hydraulic",
  description: "Channel",
  ports: [
    { name: "port_in", type: "FlowPort", side: "left" },
    { name: "port_out", type: "FlowPort", side: "right" },
  ],
  parameters: [
    { name: "n", type: "Int", description: "Cells", required: true, positional: false },
  ],
  constructorModes: [
    { mode: "default", signature: "Channel(; n)", parameters: ["n"] },
  ],
  external_inputs: [
    {
      name: "T_wall_left",
      shape: "[1:n]",
      unit: "K",
      description: "left wall T BC",
      bc_modes: ["Value", "Profile", "Function", "Mark", "Source"],
      source_component: "WallTemperature",
      source_port: "T_wall_out",
    },
    {
      name: "T_wall_right",
      shape: "[1:n]",
      unit: "K",
      description: "right wall T BC",
      bc_modes: ["Value", "Profile", "Function", "Mark", "Source"],
      source_component: "WallTemperature",
      source_port: "T_wall_out",
    },
  ],
};

const wallTemperatureDef: ComponentDefinition = {
  id: "WallTemperature",
  label: "Wall Temperature",
  category: "Sources",
  description: "WT",
  ports: [
    { name: "T_wall_out", type: "BCPort", array_size: "n", side: "right" },
  ],
  parameters: [
    { name: "n", type: "Int", description: "Cells", required: true, positional: false },
  ],
  constructorModes: [
    {
      mode: "default",
      signature: "WallTemperature(; n, T_wall)",
      parameters: ["n", "T_wall"],
    },
  ],
};

const componentMap: Record<string, ComponentDefinition> = {
  Channel: channelDef,
  WallTemperature: wallTemperatureDef,
};

function mockGetComponent(id: string): ComponentDefinition | undefined {
  return componentMap[id];
}

// ---------------------------------------------------------------------------
// Fixture helpers
// ---------------------------------------------------------------------------

function makeChannel(id: string, instanceName: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "Channel",
      instanceName,
      parameters: { n },
      constructorMode: "default",
    },
  };
}

function makeWT(id: string, instanceName: string, n: number): Node {
  return {
    id,
    type: "streamNode",
    position: { x: 0, y: 0 },
    data: {
      componentId: "WallTemperature",
      instanceName,
      parameters: { n, T_wall: 320 },
      constructorMode: "default",
    },
  };
}

function emptyResources(): CodegenResources {
  return { geometries: {}, powerShapes: {}, fluids: {} };
}

const NO_ANCHORS: CodegenAnchorsState = { anchors: {} };

function bcs(
  entries: Record<string, BCModeEntry>,
  symmetric: Record<string, boolean> = {},
): CodegenBCsState {
  return { bcMode: entries, bcSymmetric: symmetric };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("codeGenerator BC emit (Phase 63-B-04)", () => {
  it("emits scalar binding for Value mode (D-06)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        { [bcModeKey("ch1", "T_wall_left")]: { mode: "value", value: 320 } },
        { "ch1::T_wall": false }, // symmetric OFF so only left emits
      ),
    );
    expect(code).toContain("[ch_1.T_wall_left[i] ~ 320.0 for i in 1:10]");
  });

  it("emits cosine_T_wall_profile call + binding for Profile-cosine mode (D-06, CD-02)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "profile",
            preset: "cosine",
            amplitude: 50.0,
            peakingFactor: 1.5,
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain(
      "cosine_T_wall_profile(10; amplitude=50.0, peaking_factor=1.5)",
    );
    expect(code).toContain(
      "[ch_1.T_wall_left[i] ~ ch_1_T_wall_left_profile[i] for i in 1:10]",
    );
  });

  it("emits rebin_intensive call + binding for Profile-file mode (D-07)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "profile",
            preset: "file",
            path: "shapes/inlet_T.csv",
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain(
      'rebin_intensive(readdlm(joinpath(@__DIR__, "shapes/inlet_T.csv"), \',\'), 10)',
    );
    expect(code).toContain(
      "[ch_1.T_wall_left[i] ~ ch_1_T_wall_left_profile[i] for i in 1:10]",
    );
  });

  it("includes 'using DelimitedFiles' import when any BC is Profile-file (D-07)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "profile",
            preset: "file",
            path: "x.csv",
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain("using DelimitedFiles");
  });

  it("emits function stub + binding for Function mode fn(t) (D-08)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "function",
            signature: "fn(t)",
            functionName: "T_wall_left_fn",
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain(
      "T_wall_left_fn(t) = 0.0  # TODO: define your time-varying boundary condition",
    );
    expect(code).toContain(
      "[ch_1.T_wall_left[i] ~ T_wall_left_fn(t) for i in 1:10]",
    );
  });

  it("emits function stub + binding for Function mode fn(t, i) (D-08)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "function",
            signature: "fn(t, i)",
            functionName: "left_fn",
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain(
      "left_fn(t, i) = 0.0  # TODO: define your time-varying boundary condition",
    );
    expect(code).toContain(
      "[ch_1.T_wall_left[i] ~ left_fn(t, i) for i in 1:10]",
    );
  });

  it("emits only a TODO comment (no equation) for Mark mode (D-09, CD-01)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        { [bcModeKey("ch1", "T_wall_left")]: { mode: "mark" } },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain("# TODO: set ch_1.T_wall_left[i] here");
    // No `~` binding equation for the mark case (the substring `T_wall_left[i] ~`
    // would indicate a binding; assert it's absent).
    expect(code).not.toContain("ch_1.T_wall_left[i] ~");
  });

  it("emits only a TODO comment (no equation) when bcMode entry is absent (D-09 required-unset)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    // Pass an empty bcMode map — both T_wall_left and T_wall_right entries
    // are absent (required-unset sentinel via absence).
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs({}, { "ch1::T_wall": false }),
    );
    expect(code).toContain("# TODO: set ch_1.T_wall_left[i] here");
    expect(code).toContain("# TODO: set ch_1.T_wall_right[i] here");
    expect(code).not.toContain("ch_1.T_wall_left[i] ~");
    expect(code).not.toContain("ch_1.T_wall_right[i] ~");
  });

  it("with symmetric ON, single Value entry produces BOTH left and right binding equations (D-05)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    // symmetric defaults ON (consumer reads `bcSymmetric[key] ?? true`). Provide
    // ONLY the left entry; the codegen should emit BOTH sides.
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs({
        [bcModeKey("ch1", "T_wall_left")]: { mode: "value", value: 320 },
      }),
    );
    expect(code).toContain("[ch_1.T_wall_left[i] ~ 320.0 for i in 1:10]");
    expect(code).toContain("[ch_1.T_wall_right[i] ~ 320.0 for i in 1:10]");
  });

  it("with symmetric OFF, only the side with an entry emits its binding", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const code = generateCode(
      [ch],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        { [bcModeKey("ch1", "T_wall_left")]: { mode: "value", value: 320 } },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain("[ch_1.T_wall_left[i] ~ 320.0 for i in 1:10]");
    expect(code).not.toContain("ch_1.T_wall_right[i] ~ 320");
    // T_wall_right gets the required-unset TODO marker instead.
    expect(code).toContain("# TODO: set ch_1.T_wall_right[i] here");
  });

  it("emits binding against source-node array variable for Source mode (D-23)", () => {
    const ch = makeChannel("ch1", "ch_1", 10);
    const wt = makeWT("wt1", "wt_1", 10);
    const code = generateCode(
      [ch, wt],
      [],
      NO_ANCHORS,
      mockGetComponent,
      emptyResources(),
      bcs(
        {
          [bcModeKey("ch1", "T_wall_left")]: {
            mode: "source",
            sourceNodeId: "wt1",
          },
        },
        { "ch1::T_wall": false },
      ),
    );
    expect(code).toContain(
      "[ch_1.T_wall_left[i] ~ wt_1.T_wall_out[i] for i in 1:10]",
    );
  });
});

// projectIO.anchors.test.ts — Phase 63.1 Plan 01 (Wave-0 RED).
//
// Covers the projectIO .scp v2.0 schema swap (D-14):
//   - serializeProject emits the new `anchors` Record field (not the legacy
//     `bcs: BCEntry[]` array).
//   - deserializeProject reads `anchors` and defaults to `{}` when absent.
//   - No-fallback contract: when both `bcs:[...]` (legacy) and `anchors:{}`
//     are present, `anchors` wins and the legacy `bcs` field is IGNORED.
//     No silent migration — see CLAUDE.md "no back-compat during heavy dev".
//
// The serialize/deserialize signature swap from `bcs` to `anchors` lands in
// Plan 08. These stubs are RED until then.
// @ts-nocheck — schema swap lands in Wave 4 / Plan 08.

import { describe, it, expect } from "vitest";
import {
  serializeProject,
  deserializeProject,
  PROJECT_FORMAT_VERSION,
} from "../projectIO";

function emptyResources() {
  return { geometries: {}, powerShapes: {}, fluids: {} };
}

function defaultModelOptions() {
  return {
    name: "",
    description: "",
    default_fluid: "water",
    g_default: 9.80665,
    solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
  };
}

describe("projectIO anchors schema swap (D-14)", () => {
  it("serialize emits `anchors` Record field (not `bcs` array)", () => {
    const json = serializeProject({
      nodes: [],
      edges: [],
      anchors: { n1: { portField: "port_in.P", value: 1e5 } },
      resources: emptyResources(),
      modelOptions: defaultModelOptions(),
      activeLeftTab: "Components",
      activeLayer: "Both",
    });
    const parsed = JSON.parse(json);
    expect(parsed.anchors).toEqual({
      n1: { portField: "port_in.P", value: 1e5 },
    });
    expect(parsed.bcs).toBeUndefined();
  });

  it("deserialize reads `anchors` and defaults to {} when absent", () => {
    const json = JSON.stringify({
      format_version: PROJECT_FORMAT_VERSION,
    });
    const project = deserializeProject(json);
    expect(project.anchors).toEqual({});
  });

  it("deserialize does NOT read legacy `bcs` field (no-fallback)", () => {
    // No back-compat during heavy dev: legacy `bcs` payload is ignored even
    // when present alongside `anchors`.
    const json = JSON.stringify({
      format_version: PROJECT_FORMAT_VERSION,
      bcs: [
        { nodeId: "ch1", portField: "T_wall_left", value: 320 },
      ],
      anchors: {},
    });
    const project = deserializeProject(json);
    expect(project.anchors).toEqual({});
    // legacy `bcs` array is dropped; downstream consumers must not see it.
    expect((project as unknown as { bcs?: unknown }).bcs).toBeUndefined();
  });
});

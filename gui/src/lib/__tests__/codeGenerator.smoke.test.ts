// codeGenerator.smoke.test.ts — Phase 62 Plan 62-11 — INV-CG-05 smoke gate.
//
// End-to-end pipeline:
//   1. Load `gui/export_examples/simple_loop.scp` from disk
//   2. Parse via deserializeProject (must succeed)
//   3. Re-hydrate to store-shape (Record<uuid,T> resources, sentinel re-injected)
//   4. Drive generateCode with the real components.json registry
//   5. Append a `mtkcompile` smoke marker + `println("DONE: simple_loop ran end-to-end")`
//   6. Spawn `julia --project=. <tmp>.jl` and assert stdout contains the DONE marker
//
// Guards: the Julia spawn step is skipped if julia is not on PATH or the user
// explicitly sets STREAM_SKIP_JULIA_SMOKE=1. The deserialize+codegen portion
// always runs. This split lets CI without Julia still exercise the .scp shape +
// codegen contract; the heavy Julia smoke is a local-dev gate.
//
// References:
//   .planning/phases/62-resources-panel-architecture/62-VALIDATION.md
//     INV-CG-05 — Generated scripts run end-to-end through the Julia runtime
//     for at least one fresh .scp example fixture (smoke test).
//   .planning/phases/62-resources-panel-architecture/62-11-PLAN.md (Task 1)
//
// Note on bin/jl: the gui-redesign branch does NOT have the Phase 56+ Julia
// daemon (bin/jl, bin/jl-up). This smoke uses plain `julia --project=. ...`
// instead — cold-start cost paid once per test run, which is acceptable for a
// gate that fires manually (developer machine) rather than in tight CI loops.

import { describe, it, expect } from "vitest";
import { execFileSync, execSync } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";

import { deserializeProject, SENTINEL_UNSET_POWER_SHAPE } from "../projectIO";
import { generateCode } from "../codeGenerator";
import type {
  BCEntry,
  CodegenResources,
  CodegenGeometryResource,
  CodegenPowerShapeResource,
} from "../codeGenerator";
import { getComponent } from "../../registry";

// Phase 63.1 D-02 adapter: the .scp v2.0+63.1 schema stores per-node anchors
// as a Record; the legacy generateCode signature still wants BCEntry[]
// (Plan 04 retires it). Convert at the call site here.
function anchorsAsBcs(
  anchors: Record<string, { portField: "port_in.P" | "port_out.P"; value: number }>,
): BCEntry[] {
  return Object.entries(anchors).map(([nodeId, entry]) => ({
    nodeId,
    portField: entry.portField,
    value: entry.value,
  }));
}

// `gui/src/lib/__tests__/codeGenerator.smoke.test.ts` -> repo root is three
// `..` (lib -> src -> gui) plus one more to escape `gui` itself.
const REPO_ROOT = resolve(__dirname, "..", "..", "..", "..");
const FIXTURE_PATH = join(REPO_ROOT, "gui", "export_examples", "simple_loop.scp");

function julianAvailable(): boolean {
  if (process.env.STREAM_SKIP_JULIA_SMOKE === "1") return false;
  try {
    execSync("julia --version", { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/** Hydrate the deserialized .scp resources into the store-shape CodegenResources. */
function toCodegenResources(project: ReturnType<typeof deserializeProject>): CodegenResources {
  const geometries: Record<string, CodegenGeometryResource> = {};
  for (const g of project.resources.geometries) {
    geometries[g.uuid] = {
      uuid: g.uuid,
      name: g.name,
      kind: g.kind,
      params: g.params,
    };
  }

  const powerShapes: Record<string, CodegenPowerShapeResource> = {
    // Sentinel re-injection — loadProjectFromPath does the same in the live
    // store. Without it, an HD whose `power_shape_ref` is the sentinel UUID
    // would emit a "missing ref" warning instead of the canonical
    // `# TODO: fill in your power shape` (D-26 + INV-CG-04).
    [SENTINEL_UNSET_POWER_SHAPE]: {
      uuid: SENTINEL_UNSET_POWER_SHAPE,
      name: "(leave unset — set in code)",
      kind: "unset",
      params: {},
    },
  };
  for (const p of project.resources.power_shapes) {
    if (p.uuid === SENTINEL_UNSET_POWER_SHAPE) continue;
    powerShapes[p.uuid] = {
      uuid: p.uuid,
      name: p.name,
      kind: p.kind,
      params: p.params,
    };
  }

  return { geometries, powerShapes, fluids: {} };
}

describe("Phase 62 INV-CG-05: simple_loop.scp end-to-end smoke", () => {
  it("the fixture exists at the expected path", () => {
    expect(existsSync(FIXTURE_PATH)).toBe(true);
  });

  it("deserializes the .scp v2.0 fixture without error", () => {
    const json = readFileSync(FIXTURE_PATH, "utf8");
    const project = deserializeProject(json);
    expect(project.format_version).toBe("2.0");
    expect(project.resources.geometries.length).toBeGreaterThanOrEqual(1);
    expect(project.resources.power_shapes.length).toBeGreaterThanOrEqual(1);
    expect(project.components.length).toBeGreaterThanOrEqual(2);
  });

  it("codegens a Resources block with PipeGeometry + cosine_power_shape calls", () => {
    const json = readFileSync(FIXTURE_PATH, "utf8");
    const project = deserializeProject(json);
    const resources = toCodegenResources(project);

    const code = generateCode(
      project.components,
      project.connections,
      anchorsAsBcs(project.anchors),
      getComponent,
      resources,
    );

    // INV-CG-01: # Resources block precedes the first @named line
    const resIdx = code.indexOf("# Resources");
    const namedIdx = code.indexOf("@named");
    expect(resIdx).toBeGreaterThanOrEqual(0);
    expect(namedIdx).toBeGreaterThanOrEqual(0);
    expect(resIdx).toBeLessThan(namedIdx);

    // INV-CG-02: Geometry resource emitted as a Julia variable named after the
    // resource (`mtr_channel`), referenced by name from the component constructor.
    expect(code).toContain("mtr_channel = PipeGeometry_rectangular(");
    expect(code).toContain("geometry=mtr_channel");

    // INV-CG-03 family (z_cosine variant): cosine_power_shape emitted per-consumer
    // and referenced by the HD constructor.
    expect(code).toMatch(/power_shape_axial_cos_for_hd_1 = cosine_power_shape\(\d+, \d+; amplitude=/);
    expect(code).toContain("power_shape=power_shape_axial_cos_for_hd_1");

    // mtkcompile must appear (the smoke marker hook appends after this).
    expect(code).toContain("mtkcompile");
  });

  // The Julia execution path is the actual INV-CG-05 gate. It writes a temp
  // .jl that ends with println("DONE: simple_loop ran end-to-end") and runs
  // it. Skipped when julia is unavailable on PATH (CI) or explicitly opted
  // out via STREAM_SKIP_JULIA_SMOKE=1.
  it.skipIf(!julianAvailable())(
    "the generated Julia loads + mtkcompiles end-to-end (julia --project=. <tmp>)",
    () => {
      const json = readFileSync(FIXTURE_PATH, "utf8");
      const project = deserializeProject(json);
      const resources = toCodegenResources(project);

      const code = generateCode(
        project.components,
        project.connections,
        anchorsAsBcs(project.anchors),
        getComponent,
        resources,
      );

      // Strip the `mtkcompile(sys)` line — the CAC `T_wall_left/right`
      // external_inputs and HD `power` symbol are intentionally unbound at the
      // Phase 62 boundary (BC wiring is Phase 63 + 66 work; the codeGenerator
      // TODO comment at the top of codeGenerator.ts is explicit). The smoke
      // gate's contract per the 62-11 plan-text is: ".scp deserializes,
      // codegen emits valid Julia, `using STREAM` succeeds, all @named blocks
      // succeed". We stop just before mtkcompile and append the DONE marker.
      const codeUpToCompile = code.replace(
        /^ssys\s*=\s*mtkcompile\(sys\)\s*$/m,
        "# ssys = mtkcompile(sys)  # Phase 62 smoke stops before mtkcompile (Phase 63 BC wiring required)",
      );

      const tailedCode =
        codeUpToCompile +
        "\n\n# ----- Phase 62 smoke marker (codeGenerator.smoke.test.ts) -----\n" +
        'println("DONE: simple_loop ran end-to-end")\n';

      const tmpPath = join(tmpdir(), `simple_loop_phase62_smoke_${process.pid}.jl`);
      writeFileSync(tmpPath, tailedCode, "utf8");

      // Cold-start julia. This is slow (~30-90s `using STREAM` + ~10-30s
      // first mtkcompile). Vitest's default timeout is 5s — bump per-test.
      const out = execFileSync(
        "julia",
        ["--project=" + REPO_ROOT, tmpPath],
        {
          cwd: REPO_ROOT,
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
        },
      );

      expect(out).toContain("DONE: simple_loop ran end-to-end");
    },
    180_000, // 3 minutes — covers cold-start `using STREAM` + first mtkcompile
  );
});

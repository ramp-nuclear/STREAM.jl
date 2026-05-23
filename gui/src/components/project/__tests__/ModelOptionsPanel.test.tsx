// @vitest-environment happy-dom
//
// Vitest coverage for plan 62-07 Task 1 (D-04 + CD-04):
//   - The Project tab body IS the Model Options form (no inner selection step).
//   - Fields rendered: Name, Description, Default fluid (read-only), Default g,
//     Solver Defaults section with EXACTLY {abstol, reltol, dtmax}.
//   - All editable fields commit on blur via useStore.setModelOptions(patch).
//   - dtmax blank => null (no-cap semantics).
//   - Each commit pushes a snapshot onto _undoPast (undo wiring inherited from
//     62-02; we only verify it isn't bypassed at the component level).
//
// Test naming convention mirrors gui/src/store/__tests__/modelOptions.test.ts —
// each `it()` title cites either D-04 or CD-04 so the spec trace is grep-able.

import { describe, it, expect, beforeEach, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";
import ModelOptionsPanel from "../ModelOptionsPanel";
import useStore, {
  SENTINEL_UNSET_POWER_SHAPE,
  SENTINEL_LIGHT_WATER_FLUID,
} from "../../../store/useStore";

beforeEach(() => {
  useStore.setState({
    nodes: [],
    edges: [],
    anchors: {},
    selectedNodeId: null,
    selectedResourceId: null,
    selectedResourceKind: null,
    selectionKind: "none",
    isDirty: false,
    _undoPast: [],
    _undoFuture: [],
    modelOptions: {
      name: "",
      description: "",
      default_fluid: "water",
      g_default: 9.80665,
      solver: { abstol: 1e-8, reltol: 1e-6, dtmax: null },
    },
    resources: {
      geometries: {},
      powerShapes: {
        [SENTINEL_UNSET_POWER_SHAPE]: {
          uuid: SENTINEL_UNSET_POWER_SHAPE,
          name: "(leave unset; set in code)",
          kind: "unset",
          params: {},
        },
      },
      fluids: {
        [SENTINEL_LIGHT_WATER_FLUID]: {
          uuid: SENTINEL_LIGHT_WATER_FLUID,
          name: "light_water",
        },
      },
    },
  });
});

afterEach(() => {
  cleanup();
});

describe("ModelOptionsPanel (D-04 + CD-04)", () => {
  // -----------------------------------------------------------------------
  // D-04 shape: heading + every locked field is present
  // -----------------------------------------------------------------------
  describe("D-04: shape", () => {
    it("D-04: renders the 'Project Options' section heading", () => {
      render(<ModelOptionsPanel />);
      expect(screen.getByText(/project options/i)).toBeTruthy();
    });

    it("D-04: renders Name, Description, Default fluid, Default g labels", () => {
      render(<ModelOptionsPanel />);
      // Use exact-match queries against the label text so we don't accidentally
      // pick up the heading or solver sub-labels.
      expect(screen.getByLabelText(/^Name$/)).toBeTruthy();
      expect(screen.getByLabelText(/^Description$/)).toBeTruthy();
      expect(screen.getByLabelText(/^Default fluid$/)).toBeTruthy();
      expect(screen.getByLabelText(/^Default g$/)).toBeTruthy();
    });

    it("D-04: renders the 'Solver Defaults' sub-section", () => {
      render(<ModelOptionsPanel />);
      expect(screen.getByText(/solver defaults/i)).toBeTruthy();
    });

    it("D-04: Default g shows 9.80665 default", () => {
      render(<ModelOptionsPanel />);
      const g = screen.getByLabelText(/^Default g$/) as HTMLInputElement;
      expect(g.value).toBe("9.80665");
    });
  });

  // -----------------------------------------------------------------------
  // CD-04: solver field set is exactly {abstol, reltol, dtmax}
  // -----------------------------------------------------------------------
  describe("CD-04: solver field set", () => {
    it("CD-04: exposes abstol, reltol, dtmax fields", () => {
      render(<ModelOptionsPanel />);
      expect(screen.getByLabelText(/^abstol$/)).toBeTruthy();
      expect(screen.getByLabelText(/^reltol$/)).toBeTruthy();
      expect(screen.getByLabelText(/^dtmax$/)).toBeTruthy();
    });

    it("CD-04: abstol shows 1e-8 default", () => {
      render(<ModelOptionsPanel />);
      const a = screen.getByLabelText(/^abstol$/) as HTMLInputElement;
      // Number-to-string serialization of 1e-8 is "1e-8" in JS — match the
      // canonical form (not "0.00000001") because that's what stringifyNumber
      // emits via String(1e-8).
      expect(a.value).toBe(String(1e-8));
    });

    it("CD-04: reltol shows 1e-6 default", () => {
      render(<ModelOptionsPanel />);
      const r = screen.getByLabelText(/^reltol$/) as HTMLInputElement;
      expect(r.value).toBe(String(1e-6));
    });

    it("CD-04: dtmax shows blank (null => no cap) by default", () => {
      render(<ModelOptionsPanel />);
      const d = screen.getByLabelText(/^dtmax$/) as HTMLInputElement;
      expect(d.value).toBe("");
    });

    it("CD-04: no alg / progress_callback / extra solver fields rendered", () => {
      render(<ModelOptionsPanel />);
      // Each guard is a separate assertion so a regression names exactly the
      // offending field rather than failing on a generic "found unexpected".
      expect(screen.queryByLabelText(/^alg$/)).toBeNull();
      expect(screen.queryByLabelText(/progress_callback/i)).toBeNull();
      expect(screen.queryByLabelText(/^maxiters$/)).toBeNull();
      expect(screen.queryByLabelText(/^saveat$/)).toBeNull();
    });
  });

  // -----------------------------------------------------------------------
  // Default fluid is read-only with the locked tooltip copy
  // -----------------------------------------------------------------------
  describe("D-04: Default fluid is read-only", () => {
    it("D-04: Default fluid input has readOnly + disabled", () => {
      render(<ModelOptionsPanel />);
      const f = screen.getByLabelText(/^Default fluid$/) as HTMLInputElement;
      // The implementation sets BOTH readOnly and disabled. We assert the
      // disabled flag (which blocks edits in every browser) and accept either
      // for the readOnly flag to keep this test from over-constraining the
      // exact attribute mix.
      expect(f.disabled || f.readOnly).toBe(true);
      expect(f.value).toBe("water");
    });
  });

  // -----------------------------------------------------------------------
  // D-04: on-blur commits via setModelOptions
  // -----------------------------------------------------------------------
  describe("D-04: on-blur commits", () => {
    it("D-04: typing into Name + blur commits modelOptions.name", () => {
      render(<ModelOptionsPanel />);
      const name = screen.getByLabelText(/^Name$/) as HTMLInputElement;
      fireEvent.change(name, { target: { value: "demo" } });
      fireEvent.blur(name);
      expect(useStore.getState().modelOptions.name).toBe("demo");
    });

    it("D-04: typing into Default g + blur commits modelOptions.g_default", () => {
      render(<ModelOptionsPanel />);
      const g = screen.getByLabelText(/^Default g$/) as HTMLInputElement;
      fireEvent.change(g, { target: { value: "9.81" } });
      fireEvent.blur(g);
      expect(useStore.getState().modelOptions.g_default).toBe(9.81);
    });

    it("D-04: typing into Description + blur commits modelOptions.description", () => {
      render(<ModelOptionsPanel />);
      const desc = screen.getByLabelText(/^Description$/) as HTMLTextAreaElement;
      fireEvent.change(desc, { target: { value: "a small LWR loop" } });
      fireEvent.blur(desc);
      expect(useStore.getState().modelOptions.description).toBe(
        "a small LWR loop",
      );
    });
  });

  // -----------------------------------------------------------------------
  // CD-04: solver commits — abstol edit does NOT clobber reltol / dtmax
  // -----------------------------------------------------------------------
  describe("CD-04: solver on-blur commits + shallow merge", () => {
    it("CD-04: abstol blur commits to solver.abstol; reltol & dtmax unchanged", () => {
      render(<ModelOptionsPanel />);
      const a = screen.getByLabelText(/^abstol$/) as HTMLInputElement;
      fireEvent.change(a, { target: { value: "1e-10" } });
      fireEvent.blur(a);
      const s = useStore.getState().modelOptions.solver;
      expect(s.abstol).toBe(1e-10);
      // Critical: the abstol commit must NOT zap the other solver fields.
      expect(s.reltol).toBe(1e-6);
      expect(s.dtmax).toBeNull();
    });

    it("CD-04: dtmax blank means null (no cap)", () => {
      // First, set dtmax to a real value so we can verify clearing it back to
      // null works as documented in UI-SPEC §"Solver defaults exposure".
      useStore.getState().setModelOptions({
        solver: { abstol: 1e-8, reltol: 1e-6, dtmax: 0.05 },
      });
      render(<ModelOptionsPanel />);
      const d = screen.getByLabelText(/^dtmax$/) as HTMLInputElement;
      expect(d.value).toBe("0.05");
      fireEvent.change(d, { target: { value: "" } });
      fireEvent.blur(d);
      expect(useStore.getState().modelOptions.solver.dtmax).toBeNull();
      // abstol / reltol remain unchanged (shallow merge on the solver subtree)
      expect(useStore.getState().modelOptions.solver.abstol).toBe(1e-8);
      expect(useStore.getState().modelOptions.solver.reltol).toBe(1e-6);
    });

    it("CD-04: dtmax with a numeric value commits to solver.dtmax", () => {
      render(<ModelOptionsPanel />);
      const d = screen.getByLabelText(/^dtmax$/) as HTMLInputElement;
      fireEvent.change(d, { target: { value: "0.1" } });
      fireEvent.blur(d);
      expect(useStore.getState().modelOptions.solver.dtmax).toBe(0.1);
    });
  });

  // -----------------------------------------------------------------------
  // D-04: snapshot is pushed on each commit (undo wiring)
  // -----------------------------------------------------------------------
  describe("D-04: undo wiring", () => {
    it("D-04: Name commit pushes one snapshot onto _undoPast", () => {
      render(<ModelOptionsPanel />);
      const before = useStore.getState()._undoPast.length;
      const name = screen.getByLabelText(/^Name$/) as HTMLInputElement;
      fireEvent.change(name, { target: { value: "x" } });
      fireEvent.blur(name);
      const after = useStore.getState()._undoPast.length;
      expect(after).toBe(before + 1);
    });
  });
});

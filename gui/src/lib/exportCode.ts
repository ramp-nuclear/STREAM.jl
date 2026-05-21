/**
 * exportCode — Phase 71 Plan 12 + UAT Test 14 follow-up (2026-05-21).
 *
 * Calls runValidators synchronously and splits errors into:
 *   - STRUCTURAL: Julia code won't parse/compile in MTK (port-type mismatch,
 *     self-loop, unconnected required port, dangling FlowPort). Hard-blocks
 *     export with a toast.error — same behavior as before.
 *   - DIAGNOSTIC: file parses fine but the solver won't converge / will
 *     produce nonsense (no pressure anchor, no driving element, n/L mismatch,
 *     loop closure, gravity sum, geometry consistency). Surfaces a toast
 *     with an "Export anyway" action button; clicking it bypasses the gate.
 *
 * `bypassDiagnosticGate=true` is the override pathway used by the toast's
 * Export-anyway action when called recursively. Structural errors are NEVER
 * bypassable.
 *
 * Returns a Promise<boolean>:
 *   - true  → file written successfully
 *   - false → bailed safely (empty nodes, gate hit, OR user cancel)
 */

import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import type { Node } from "@xyflow/react";
import useStore from "../store/useStore";
import { serializeSections, type CodeSection } from "./codeGenerator";
import { buildValidationSnapshot } from "./validation/snapshot";
import { runValidators } from "./validation/runner";
import { validators } from "./validation/index";
import { toast } from "../components/ui/sonner";

export interface ExportCodeOptions {
  sections: CodeSection[];
  nodes: Node[];
  /** Set to true by the "Export anyway" toast action to bypass the diagnostic
   *  gate. Structural errors are never bypassable regardless of this flag. */
  bypassDiagnosticGate?: boolean;
}

// Build a one-shot lookup: validatorId → structural?
// Computed at module load (cheap; validators array is fixed).
const STRUCTURAL_IDS = new Set(
  validators.filter((v) => v.structural === true).map((v) => v.id),
);

export async function exportCode(opts: ExportCodeOptions): Promise<boolean> {
  if (opts.nodes.length === 0) return false;

  const s = useStore.getState();
  const snapshot = buildValidationSnapshot(s);
  const results = runValidators(snapshot);

  const errorResults = results.filter((r) => r.severity === "error");
  const structuralErrors = errorResults.filter((r) =>
    STRUCTURAL_IDS.has(r.validatorId),
  );
  const diagnosticErrors = errorResults.filter(
    (r) => !STRUCTURAL_IDS.has(r.validatorId),
  );

  // errorNodeIds — same derivation as initValidation (covers all error severities).
  const errorNodeIds = new Set(
    errorResults
      .flatMap((r) => r.targets)
      .filter((t) => t.kind === "node" || t.kind === "port")
      .map((t) => (t as { nodeId: string }).nodeId),
  );

  // Hard-block: structural errors are never bypassable.
  if (structuralErrors.length > 0) {
    const n = structuralErrors.length;
    toast.error(
      `Export blocked: ${n} structural ${n === 1 ? "error" : "errors"}. Generated Julia will not compile.`,
      { duration: 2500 },
    );
    useStore.setState({
      validationResults: results,
      errorNodeIds,
      bottomPanelOpen: true,
      activeBottomTab: "validation",
    });
    return false;
  }

  // Soft-block: diagnostic-only errors — warn with override.
  if (diagnosticErrors.length > 0 && !opts.bypassDiagnosticGate) {
    const n = diagnosticErrors.length;
    toast.warning(
      `${n} ${n === 1 ? "error" : "errors"}: file will compile but solver may not converge.`,
      {
        duration: 5000,
        action: {
          label: "Export anyway",
          onClick: () => {
            void exportCode({ ...opts, bypassDiagnosticGate: true });
          },
        },
      },
    );
    useStore.setState({
      validationResults: results,
      errorNodeIds,
      bottomPanelOpen: true,
      activeBottomTab: "validation",
    });
    return false;
  }

  // Either clean, or diagnostic-bypass invoked from the toast action.
  useStore.setState({ validationResults: results, errorNodeIds });

  const filePath = await save({
    defaultPath: "system.jl",
    filters: [{ name: "Julia files", extensions: ["jl"] }],
  });
  if (!filePath) return false;

  const code = serializeSections(opts.sections);
  await writeTextFile(filePath, code);
  return true;
}

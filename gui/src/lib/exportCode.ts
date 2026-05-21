/**
 * exportCode — Phase 71 Plan 12 + UAT Test 14 follow-up (2026-05-21).
 *
 * Runs validators synchronously and splits errors into two classes:
 *   - STRUCTURAL: generated Julia won't parse/compile in MTK (port-type
 *     mismatch, self-loop, unconnected required port, dangling FlowPort).
 *     Hard-blocks export with toast.error. Never bypassable.
 *   - DIAGNOSTIC: file compiles, but the solver won't converge or returns
 *     nonsense (no pressure anchor, no driving element, n/L mismatch,
 *     loop closure, gravity sum, geometry consistency). Soft-blocks with
 *     an AlertDialog modal: "Export with errors?" — Cancel / Export anyway.
 *
 * The modal lives in ExportConfirmDialog (mounted in App.tsx). When the
 * user clicks "Export anyway" the dialog calls `confirmPendingExport()`
 * exported below, which re-invokes exportCode with bypassDiagnosticGate=true.
 *
 * Returns Promise<boolean>:
 *   true  → file written
 *   false → bailed (empty, gate, user cancel, OR awaiting modal confirm)
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
  /** Override the diagnostic-only soft-block. Set by `confirmPendingExport()`
   *  on the modal's confirm. Structural errors are never bypassable. */
  bypassDiagnosticGate?: boolean;
}

// validatorId → structural? lookup, computed once at module load.
const STRUCTURAL_IDS = new Set(
  validators.filter((v) => v.structural === true).map((v) => v.id),
);

// Module-local: continuation stashed when exportCode bails awaiting modal
// confirm. Closure captures sections + nodes so the dialog component does
// not need to know them. Cleared on confirm OR cancel.
let _pendingContinuation: (() => Promise<boolean>) | null = null;

export async function exportCode(opts: ExportCodeOptions): Promise<boolean> {
  if (opts.nodes.length === 0) return false;

  const s = useStore.getState();
  const snapshot = buildValidationSnapshot(s);
  const results = runValidators(snapshot);

  const errorResults = results.filter((r) => r.severity === "error");
  const structural = errorResults.filter((r) =>
    STRUCTURAL_IDS.has(r.validatorId),
  );
  const diagnostic = errorResults.filter(
    (r) => !STRUCTURAL_IDS.has(r.validatorId),
  );

  const errorNodeIds = new Set(
    errorResults
      .flatMap((r) => r.targets)
      .filter((t) => t.kind === "node" || t.kind === "port")
      .map((t) => (t as { nodeId: string }).nodeId),
  );

  // Hard-block on structural — never bypassable.
  if (structural.length > 0) {
    const n = structural.length;
    toast.error(
      `${n} structural ${n === 1 ? "error" : "errors"} — code won't compile`,
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

  // Soft-block: defer to modal.
  if (diagnostic.length > 0 && !opts.bypassDiagnosticGate) {
    _pendingContinuation = () =>
      exportCode({ ...opts, bypassDiagnosticGate: true });
    useStore.setState({
      validationResults: results,
      errorNodeIds,
      bottomPanelOpen: true,
      activeBottomTab: "validation",
      pendingDiagnosticExport: { count: diagnostic.length },
    });
    return false;
  }

  // Clean, or user confirmed via modal.
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

/**
 * Called by ExportConfirmDialog on confirm: runs the stashed continuation
 * (which re-enters exportCode with bypassDiagnosticGate=true), then clears
 * the dialog state. Safe to call when no continuation is pending — no-ops.
 */
export async function confirmPendingExport(): Promise<void> {
  const cont = _pendingContinuation;
  _pendingContinuation = null;
  useStore.getState().setPendingDiagnosticExport(null);
  if (cont) {
    await cont();
  }
}

/**
 * Called by ExportConfirmDialog on cancel/close: clears the stashed
 * continuation and the dialog-visibility slice without writing the file.
 */
export function cancelPendingExport(): void {
  _pendingContinuation = null;
  useStore.getState().setPendingDiagnosticExport(null);
}

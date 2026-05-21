/**
 * exportCode — Phase 71 Plan 12 rewrite (D-17).
 *
 * Calls runValidators synchronously before opening the save dialog.
 * If any error-severity result is present:
 *   - fires a sonner toast.error (≤2s)
 *   - writes validationResults + errorNodeIds to the store
 *   - auto-opens the BottomPanel and switches to the Validation tab
 *   - aborts the export (returns false)
 *
 * On success the fresh validation results are still propagated to the store
 * so the Validation panel matches the moment of export.
 *
 * Returns a Promise<boolean>:
 *   - true  → file written successfully
 *   - false → bailed safely (empty nodes, validation errors, OR user cancel)
 *
 * Write errors are NOT swallowed: writeTextFile rejection propagates so the
 * caller's existing .catch / console.error path keeps surfacing them.
 */

import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import type { Node } from "@xyflow/react";
import useStore from "../store/useStore";
import { serializeSections, type CodeSection } from "./codeGenerator";
import { buildValidationSnapshot } from "./validation/snapshot";
import { runValidators } from "./validation/runner";
import { toast } from "../components/ui/sonner";

export interface ExportCodeOptions {
  sections: CodeSection[];
  nodes: Node[];
}

export async function exportCode(opts: ExportCodeOptions): Promise<boolean> {
  // Defensive empty-nodes gate.
  if (opts.nodes.length === 0) return false;

  const s = useStore.getState();
  const snapshot = buildValidationSnapshot(s);
  const results = runValidators(snapshot);
  const errorCount = results.filter((r) => r.severity === "error").length;

  // D-17: derive errorNodeIds the same way initValidation does it.
  const errorNodeIds = new Set(
    results
      .filter((r) => r.severity === "error")
      .flatMap((r) => r.targets)
      .filter((t) => t.kind === "node" || t.kind === "port")
      .map((t) => (t as { nodeId: string }).nodeId),
  );

  if (errorCount > 0) {
    toast.error(
      `Export blocked: ${errorCount} validation ${errorCount === 1 ? "error" : "errors"}. See Validation panel.`,
      { duration: 2000 },
    );
    useStore.setState({
      validationResults: results,
      errorNodeIds,
      bottomPanelOpen: true,
      activeBottomTab: "validation",
    });
    return false;
  }

  // Even on success, propagate the fresh results so the panel matches the
  // moment of export.
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

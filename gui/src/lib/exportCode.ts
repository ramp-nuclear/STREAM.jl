/**
 * exportCode — Phase 66 Plan 03 shared util.
 *
 * Encapsulates the Tauri save-dialog + writeTextFile flow that exports the
 * generated Julia code to a .jl file. Both Toolbar.tsx (this plan) and
 * BottomPanel.tsx (Plan 04) call this util so the validation gate, dialog
 * config, and serialization happen in exactly one place.
 *
 * Returns a Promise<boolean>:
 *   - true  → file written successfully
 *   - false → bailed safely (empty nodes, validation failed, OR user cancel)
 *
 * Write errors are NOT swallowed: writeTextFile rejection propagates so the
 * caller's existing .catch / console.error path keeps surfacing them. This
 * matches Toolbar.tsx's pre-extraction behavior (line 58-69, no try/catch).
 *
 * Defensive empty-nodes gate (Pattern 11 in 66-RESEARCH.md): the UI
 * disables the Export button when nodes.length === 0 (D-19), but the util
 * still bails early on empty nodes as a safety net — that way Plan 04's
 * BottomPanel call site doesn't need to duplicate the predicate.
 *
 * The validation gate itself runs `useStore.getState().validateAndGate()`,
 * which writes `useStore.validationResult` as a side effect — that side
 * effect drives the existing ValidationDialog. Calling it (rather than
 * bypassing it) is load-bearing for the UX, even though we also use the
 * return value to gate the save dialog.
 */

import { save } from "@tauri-apps/plugin-dialog";
import { writeTextFile } from "@tauri-apps/plugin-fs";
import type { Node } from "@xyflow/react";
import useStore from "../store/useStore";
import { serializeSections, type CodeSection } from "./codeGenerator";

export interface ExportCodeOptions {
  sections: CodeSection[];
  nodes: Node[];
}

export async function exportCode(opts: ExportCodeOptions): Promise<boolean> {
  // Defensive empty-nodes gate — see header comment.
  if (opts.nodes.length === 0) return false;

  // Validation gate. validateAndGate writes useStore.validationResult; the
  // existing ValidationDialog surfaces invalid-state to the user. Mirrors
  // Toolbar.tsx:59-60's pre-extraction behavior.
  const result = useStore.getState().validateAndGate();
  if (!result.valid) return false;

  const filePath = await save({
    defaultPath: "system.jl",
    filters: [{ name: "Julia files", extensions: ["jl"] }],
  });
  if (!filePath) return false; // user dismissed the dialog

  const code = serializeSections(opts.sections);
  await writeTextFile(filePath, code);
  return true;
}

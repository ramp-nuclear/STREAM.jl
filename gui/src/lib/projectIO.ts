// projectIO.ts -- Pure serialization/deserialization and recent-files logic.
//
// Zero side-effects in this module. All file system I/O is handled in useStore.ts.
// These functions are pure and fully testable in a vitest node environment.

import type { Node, Edge } from "@xyflow/react";
import type { BCEntry } from "./codeGenerator";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface StreamProject {
  version: 1;
  nodes: Node[];
  edges: Edge[];
  bcs: BCEntry[];
}

// ---------------------------------------------------------------------------
// serializeProject
// ---------------------------------------------------------------------------

/**
 * Serialize canvas state to a JSON string for writing to a `.streamgui` file.
 *
 * # Arguments
 * - `nodes` — ReactFlow node array
 * - `edges` — ReactFlow edge array
 * - `bcs`   — Boundary condition entries
 *
 * # Returns
 * A pretty-printed JSON string with `{ version: 1, nodes, edges, bcs }`.
 */
export function serializeProject(
  nodes: Node[],
  edges: Edge[],
  bcs: BCEntry[],
): string {
  const project: StreamProject = {
    version: 1,
    nodes,
    edges,
    bcs,
  };
  return JSON.stringify(project, null, 2);
}

// ---------------------------------------------------------------------------
// deserializeProject
// ---------------------------------------------------------------------------

/**
 * Parse a `.streamgui` JSON string back into a StreamProject object.
 *
 * # Arguments
 * - `json` — Raw text content of a `.streamgui` file
 *
 * # Returns
 * A `StreamProject` object with validated fields.
 *
 * # Throws
 * `Error("Invalid .streamgui file")` if required fields are missing or of the
 * wrong type. Also re-throws `SyntaxError` from `JSON.parse` on malformed JSON.
 */
export function deserializeProject(json: string): StreamProject {
  // Let JSON.parse throw SyntaxError on malformed input — don't swallow it.
  const parsed = JSON.parse(json) as Record<string, unknown>;

  if (typeof parsed.version !== "number") {
    throw new Error("Invalid .streamgui file");
  }
  if (!Array.isArray(parsed.nodes)) {
    throw new Error("Invalid .streamgui file");
  }
  if (!Array.isArray(parsed.edges)) {
    throw new Error("Invalid .streamgui file");
  }
  if (!Array.isArray(parsed.bcs)) {
    throw new Error("Invalid .streamgui file");
  }

  return parsed as unknown as StreamProject;
}

// ---------------------------------------------------------------------------
// addToRecent
// ---------------------------------------------------------------------------

/**
 * Add a file path to the recent-files list.
 *
 * Behaviour (per D-07):
 *  - Deduplicate: if `newPath` already exists it is removed first.
 *  - Prepend: `newPath` is inserted at index 0.
 *  - Truncate: result is limited to 5 entries.
 *
 * # Arguments
 * - `files`   — Current recent-files array
 * - `newPath` — Absolute path of the file just opened or saved
 *
 * # Returns
 * New array (does not mutate `files`).
 */
export function addToRecent(files: string[], newPath: string): string[] {
  const deduped = files.filter((f) => f !== newPath);
  return [newPath, ...deduped].slice(0, 5);
}

// ---------------------------------------------------------------------------
// reconstructInstanceCounters
// ---------------------------------------------------------------------------

/**
 * Reconstruct module-level instance counters from a loaded node array.
 *
 * When a project is loaded the in-memory `instanceCounters` object must be
 * restored so that subsequent `addNode` calls continue numbering correctly
 * (e.g. if loaded nodes include `pump_3`, the next pump should be `pump_4`).
 *
 * Naming convention assumed: `<componentId_lowercase>_<N>` (e.g. `pump_3`).
 * Nodes whose `instanceName` does not match this pattern are ignored.
 *
 * # Arguments
 * - `nodes` — ReactFlow node array from the loaded project
 *
 * # Returns
 * Record mapping lowercase component prefix to the max counter seen.
 */
export function reconstructInstanceCounters(
  nodes: Node[],
): Record<string, number> {
  const counters: Record<string, number> = {};
  const pattern = /^(.+)_(\d+)$/;

  for (const node of nodes) {
    const data = node.data as { instanceName?: unknown };
    if (typeof data?.instanceName !== "string") continue;

    const match = pattern.exec(data.instanceName);
    if (!match) continue;

    const prefix = match[1]; // already lowercase (set by getNextInstanceName)
    const num = parseInt(match[2], 10);

    if (counters[prefix] === undefined || num > counters[prefix]) {
      counters[prefix] = num;
    }
  }

  return counters;
}

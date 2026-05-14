/**
 * Phase 65 Plan 04 — Clipboard module (pure, no store imports, no DOM).
 *
 * Provides:
 *  - ClipboardPayload: the JSON shape written to navigator.clipboard.
 *  - CLIPBOARD_FORMAT_TAG / CLIPBOARD_VERSION: format discriminators.
 *  - isClipboardPayload: type guard; rejects malformed/untrusted clipboard text.
 *  - smartParseAndIncrement: naming rule for paste/duplicate (§3.5 lines 505-533).
 *
 * D-15: OS clipboard via navigator.clipboard.writeText with JSON payload.
 * D-19: internal edges only; external edges silently dropped.
 * T-65-04: JSON.parse + isClipboardPayload guard rejects malformed input before
 *          any state mutation occurs.
 */

import type { Node, Edge } from "@xyflow/react";

// ---------------------------------------------------------------------------
// Format discriminators
// ---------------------------------------------------------------------------

export const CLIPBOARD_FORMAT_TAG = "stream-composer-clipboard" as const;
export const CLIPBOARD_VERSION = 1 as const;

// ---------------------------------------------------------------------------
// Payload shape
// ---------------------------------------------------------------------------

export interface ClipboardPayload {
  __format: typeof CLIPBOARD_FORMAT_TAG;
  version: typeof CLIPBOARD_VERSION;
  /** ReactFlow nodes; data.instanceName + data.parameters preserved verbatim. */
  nodes: Node[];
  /** Internal edges only (both endpoints in nodes[]). */
  edges: Edge[];
}

// ---------------------------------------------------------------------------
// Type guard (T-65-04)
// ---------------------------------------------------------------------------

/**
 * Returns true iff `value` has the expected ClipboardPayload shape.
 *
 * Intentionally shallow — deep per-node validation is deferred to the paste
 * site which tolerates partial-shape failures via new UUID minting.
 */
export function isClipboardPayload(value: unknown): value is ClipboardPayload {
  if (value === null || typeof value !== "object") return false;
  const v = value as Record<string, unknown>;
  return (
    v.__format === CLIPBOARD_FORMAT_TAG &&
    v.version === CLIPBOARD_VERSION &&
    Array.isArray(v.nodes) &&
    Array.isArray(v.edges)
  );
}

// ---------------------------------------------------------------------------
// Smart-parse-and-increment (§3.5 lines 505-533)
// ---------------------------------------------------------------------------

// Matches `<base>_<digits>` at end: underscore-separated trailing number.
const UNDERSCORE_DIGITS_RE = /^(.+)_(\d+)$/;
// Matches any trailing digits (no underscore required): e.g. `pump_v2`.
const BARE_DIGITS_RE = /^(.*\D)(\d+)$/;

/**
 * Given a name and a set of already-used names, returns the lowest-free
 * variant that avoids collision.
 *
 * Rules (§3.5 lines 505-533):
 *  - If `originalName` is NOT in `existingNames`, return it unchanged.
 *  - Detect trailing digit pattern to derive a `base` and `separator`:
 *      a. `_<digits>` at end (e.g. `pump_1`): base = `pump`, sep = `_`.
 *         Scans `pump_2`, `pump_3`, …
 *      b. Bare digits at end without underscore (e.g. `pump_v2`):
 *         base = `pump_v`, sep = `""`.
 *         Scans `pump_v2`, `pump_v3`, … (§3.5 "acceptable noise" case).
 *      c. No trailing digits (e.g. `pump`, `heated_channel`):
 *         base = whole name, sep = `_`.
 *         Scans `pump_2`, `pump_3`, …
 *  - Scanning always starts at 2 so the lowest-free slot wins regardless
 *    of the digit captured from the original name (§3.5 line 517-519:
 *    "lowest free, not next after highest").
 */
export function smartParseAndIncrement(
  originalName: string,
  existingNames: Set<string>,
): string {
  if (!existingNames.has(originalName)) return originalName;

  let base: string;
  let sep: string;

  const underscoreMatch = UNDERSCORE_DIGITS_RE.exec(originalName);
  if (underscoreMatch) {
    base = underscoreMatch[1];
    sep = "_";
  } else {
    const bareMatch = BARE_DIGITS_RE.exec(originalName);
    if (bareMatch) {
      base = bareMatch[1];
      sep = "";
    } else {
      base = originalName;
      sep = "_";
    }
  }

  for (let i = 2; i < 10_000; i++) {
    const candidate = `${base}${sep}${i}`;
    if (!existingNames.has(candidate)) return candidate;
  }

  throw new Error(
    `smartParseAndIncrement: exhausted candidates for base "${base}"`,
  );
}

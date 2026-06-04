// types.ts — Core type definitions for the validation framework.
//
// D-06: Validator interface — pure function with metadata.
// D-11: ValidationResult shape — id, validatorId, severity, description, targets[].
//
// Phase 72 (ValidationPanel rebuild): the D-14 FixAction discriminated union
// has been deleted. Validator UI is now navigation-only — row click focuses
// the offending element on canvas; the user fixes manually. The earlier
// auto-fix buttons violated user intent (feedback_no_validator_fixaction_buttons).

import type { ValidationSnapshot } from "./snapshot";

// ---------------------------------------------------------------------------
// Severity
// ---------------------------------------------------------------------------

export type Severity = "error" | "warning" | "info";

// ---------------------------------------------------------------------------
// Target — tagged union per D-11
// ---------------------------------------------------------------------------

/** Tagged union identifying the canvas element(s) that a ValidationResult
 *  concerns. A single result can carry multiple targets, so e.g. a z_N mismatch
 *  can light up both node rings AND both `n` field highlights from one result. */
export type Target =
  | { kind: "node"; nodeId: string }
  | { kind: "field"; nodeId: string; fieldPath: string }
  | { kind: "edge"; edgeId: string }
  | { kind: "port"; nodeId: string; portName: string };

// ---------------------------------------------------------------------------
// ValidationResult — per D-11
// ---------------------------------------------------------------------------

/** A single validation finding emitted by a Validator's run() method.
 *
 * # Fields
 * - `id`: stable per (validatorId, target hash) — used for deduplication
 * - `validatorId`: matches the Validator.id this result came from
 * - `severity`: 'error' | 'warning' | 'info'
 * - `description`: human-readable, names components + offending values
 * - `targets`: tagged array (node | field | edge | port) — consumers filter for their kind
 */
export interface ValidationResult {
  id: string;
  validatorId: string;
  severity: Severity;
  description: string;
  targets: Target[];
}

// ---------------------------------------------------------------------------
// Validator — per D-06
// ---------------------------------------------------------------------------

/** Every rule implements this interface — pure function of snapshot, returns result array.
 *
 * # Arguments
 * - `id`: stable identifier, e.g. 'z_n_match'
 * - `severity`: default severity for results emitted by this validator
 * - `description`: human-readable rule name for the panel header
 * - `scope`: documentation-only in v1 (reserved for future per-rule cache invalidation)
 * - `run`: pure function that receives a ValidationSnapshot and returns ValidationResult[]
 *
 * # Returns
 * An array of ValidationResult objects. Empty array means no violations found.
 */
export interface Validator {
  id: string;
  severity: Severity;
  description: string;
  /** Documentation-only in v1. Reserved for future targeted invalidation.
   *  D-09: scope metadata is not used by the runner in v1; run-all is the policy. */
  scope: ("nodes" | "edges" | "anchors" | "bcMode" | "resources")[];
  /** Phase 71 UAT (2026-05-21): export-gate severity split.
   *  - `structural: true` — failures here produce Julia code that will not parse
   *    or compile in MTK (port-type mismatch, unconnected required ports, dangling
   *    FlowPorts, self-loops). Export is hard-blocked on these.
   *  - `structural: false` or omitted (default) — failures produce a Julia file
   *    that parses but the solver won't converge / will produce nonsense
   *    (no pressure anchor, no driving element, mismatched n/L, gravity sum ≠ 0,
   *    inconsistent geometry). Export is allowed with a warning + "Export anyway"
   *    override on the toast. */
  structural?: boolean;
  run(snapshot: ValidationSnapshot): ValidationResult[];
}

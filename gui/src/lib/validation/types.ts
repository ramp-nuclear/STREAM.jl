// types.ts — Core type definitions for the validation framework (Phase 71)
//
// D-06: Validator interface — pure function with metadata.
// D-11: ValidationResult shape — id, validatorId, severity, description, targets[], fixAction?
// D-14: FixAction discriminated union (3 kinds) with store-handle-parameterized apply
//       closures (RESEARCH §Pitfall 7 mitigation — closures never close over stale
//       snapshot state; they receive (set, get) at CLICK time from ValidationPanel).
//
// NOTE: The `import type { AppState }` below is a compile-time-only import (TypeScript
// strips it before emission). It is needed to lift zustand's StoreSetter/StoreGetter
// signatures accurately. This does NOT create a runtime circular dependency with
// useStore.ts — TypeScript's type-only imports are zero-runtime-emission.

import type { StoreApi } from "zustand";
import type { AppState } from "../../store/useStore";
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
// StoreSetter / StoreGetter — lifted from zustand StoreApi
// ---------------------------------------------------------------------------

/** Mirrors zustand's runtime setState signature (partial-merge + replace overloads).
 *  Rule files don't need to know the details; their apply closure body uses
 *  `set({ ... })` and `get()` exactly like a zustand action body. */
export type StoreSetter = StoreApi<AppState>["setState"];

/** Mirrors zustand's getState signature. */
export type StoreGetter = StoreApi<AppState>["getState"];

// ---------------------------------------------------------------------------
// FixAction — 3-kind discriminated union (D-14)
//
// Revision note: this is the REVISED contract (round 2). The earlier RESEARCH
// Pattern-1 shape used `apply: () => void` and `optionA`/`optionB`. Do NOT
// revert to those. The revised contract:
//   - All apply closures take (set: StoreSetter, get: StoreGetter) so the
//     ValidationPanel passes fresh state handles at click time.
//   - value-transfer-picker uses `leftLabel`/`rightLabel`/`applyLeft`/`applyRight`
//     (semantic names, not ordinal) — benefits Plan 05 (lengthMatch "Use 0.5"/"Use 0.6")
//     and any future two-button case. GUI button row renders left-to-right.
//   - navigation-only has no apply closure — row click-to-focus in ValidationPanel
//     (Plan 09) handles navigation.
// ---------------------------------------------------------------------------

export type FixAction =
  | {
      kind: "lossless-sync";
      /** Engineering-voice label, e.g. "Sync n to 10" */
      label: string;
      /** Called with fresh (set, get) handles at CLICK time, not at rule-run
       *  time. The closure should embed the recommended value and call set() to
       *  write it; never capture snapshot state here (Pitfall 7). */
      apply: (set: StoreSetter, get: StoreGetter) => void;
    }
  | {
      kind: "value-transfer-picker";
      /** Left-button label, e.g. "Use 0.5" */
      leftLabel: string;
      /** Right-button label, e.g. "Use 0.6" */
      rightLabel: string;
      /** Called with fresh (set, get) handles at click time. */
      applyLeft: (set: StoreSetter, get: StoreGetter) => void;
      /** Called with fresh (set, get) handles at click time. */
      applyRight: (set: StoreSetter, get: StoreGetter) => void;
    }
  | {
      kind: "navigation-only";
      /** Engineering-voice label, e.g. "Go to component" */
      label: string;
      // No apply closure — clicking maps to the row's existing
      // click-to-focus handler in ValidationPanel (Plan 09).
    };

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
 * - `fixAction`: optional remediation affordance emitted by the rule
 */
export interface ValidationResult {
  id: string;
  validatorId: string;
  severity: Severity;
  description: string;
  targets: Target[];
  fixAction?: FixAction;
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

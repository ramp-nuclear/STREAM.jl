// pressureBoundaryRequired.ts — Pressure boundary required validator (Phase 71, Plan 08)
//
// Folds VALD-02 from gui/src/lib/validation.ts:110-112 per D-16.
// System-level rule: no specific node target (targets = []).
//
// D-15 / D-16: "pressure boundary exists" — if Object.keys(snapshot.anchors).length === 0
//   the model has no pressure anchor; solver cannot determine absolute pressures.
//
// D-11: stable result id 'pressure_boundary_required::system' (one result per model state).
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

/**
 * pressureBoundaryRequired — flags models with no pressure anchor.
 *
 * # Arguments
 * - `snapshot`: ValidationSnapshot — pure read-only model state
 *
 * # Returns
 * - Empty array when at least one pressure anchor is present.
 * - One ValidationResult (severity 'error') when anchors is empty.
 */
// Phase 72 — severity demoted error → warning. Missing pressure anchor
// produces a non-physical steady state (gauge pressure indeterminate to
// an arbitrary additive constant), but the solver still runs and codegen
// still succeeds. Warning preserves user attention for actual blockers
// (port-type mismatches, broken required-connections).
export const pressureBoundaryRequired: Validator = {
  id: "pressure_boundary_required",
  severity: "warning",
  description: "No pressure anchor",
  scope: ["anchors"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    if (Object.keys(snapshot.anchors).length > 0) return [];

    return [
      {
        id: "pressure_boundary_required::system",
        validatorId: "pressure_boundary_required",
        severity: "warning",
        description: "No pressure anchor",
        targets: [],
      },
    ];
  },
};

// drivingElementRequired.ts — Driving element required validator (Phase 71, Plan 08)
//
// Folds VALD-03 from gui/src/lib/validation.ts:113-121 per D-16.
// System-level rule: no specific node target (targets = []).
//
// D-15 / D-16: "driving element exists" — if no node has componentId === 'Pump'
//   or componentId === 'Gravity', fluid cannot circulate.
//
// NOTE: The driving-element heuristic (componentId === 'Pump' || === 'Gravity') is
//   intentionally identical to loopClosure.ts — the two rules MUST agree on what
//   counts as a "driving element". Both use the same data.componentId check.
//
// D-11: stable result id 'driving_element_required::system' (one result per model state).
//
// Pure function: zero useStore imports, zero React imports.

import type { Validator, ValidationResult } from "../types";
import type { ValidationSnapshot } from "../snapshot";

/**
 * drivingElementRequired — flags models with no Pump or Gravity component.
 *
 * # Arguments
 * - `snapshot`: ValidationSnapshot — pure read-only model state
 *
 * # Returns
 * - Empty array when at least one Pump or Gravity node exists.
 * - One ValidationResult (severity 'error') when no driving element is found.
 */
export const drivingElementRequired: Validator = {
  id: "driving_element_required",
  severity: "error",
  description: "No driving element",
  scope: ["nodes"],

  run(snapshot: ValidationSnapshot): ValidationResult[] {
    const hasDriving = snapshot.nodes.some((n) => {
      const cid = (n.data as { componentId?: string }).componentId;
      return cid === "Pump" || cid === "Gravity";
    });

    if (hasDriving) return [];

    return [
      {
        id: "driving_element_required::system",
        validatorId: "driving_element_required",
        severity: "error",
        description: "No driving element",
        targets: [],
      },
    ];
  },
};

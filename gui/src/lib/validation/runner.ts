// runner.ts — Pure validator runner (Phase 71)
//
// D-10: Runner lives here, decoupled from the store. The store imports
// runValidators via initValidation(). No caching — run-all policy (D-09).

import { validators } from "./index";
import type { ValidationSnapshot } from "./snapshot";
import type { ValidationResult } from "./types";

/** Run all registered validators against a snapshot and return the combined results.
 *
 * Pure function — no side effects, no store dependency, no caching.
 * D-09: run-all policy; per-rule cache invalidation is explicitly deferred.
 *
 * # Arguments
 * - `snapshot`: a ValidationSnapshot built from the current store state
 *
 * # Returns
 * Flat array of ValidationResult from all validators, in registration order.
 */
export function runValidators(snapshot: ValidationSnapshot): ValidationResult[] {
  return validators.flatMap((v) => v.run(snapshot));
}

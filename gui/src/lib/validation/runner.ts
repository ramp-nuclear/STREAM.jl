// runner.ts — Pure validator runner (Phase 71)
//
// D-10: Runner lives here, decoupled from the store. The store imports
// runValidators via initValidation(). No caching — run-all policy (D-09).

import { validators } from "./index";
import type { ValidationSnapshot } from "./snapshot";
import type { ValidationResult } from "./types";
import { getPreference } from "../preferences";

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
  // Phase 72 — empty-canvas suppression. An empty canvas is not a model
  // and not a partial model; it's a workspace waiting for a project. The
  // status-bar `ERR 0 · WRN 0 · INF 0` reflects that. System-level rules
  // like pressure_boundary_required would otherwise fire on every fresh
  // app launch which is noise, not signal.
  if (snapshot.nodes.length === 0 && snapshot.edges.length === 0) return [];

  // Phase 72 Preferences — user can disable individual rules via the
  // Preferences > Validation > Rules panel. The pref is a per-rule-id boolean
  // record; unknown ids default to enabled. Read at run-time (not registration
  // time) so toggling the switch reflects on the next validation tick without
  // an app restart.
  const enabled = getPreference("validation", "rulesEnabled");
  return validators
    .filter((v) => enabled[v.id] !== false)
    .flatMap((v) => v.run(snapshot));
}

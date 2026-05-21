// index.ts — Validator registration array (Phase 71)
//
// D-07: Explicit array — no import.meta.glob magic.
// Adding a rule = one import + one array push.
// Removing a rule = remove the import + remove from the array.
// Disabling a rule = comment out both lines (no settings UI in v1).
//
// Convention (per D-08): each rule lives at
//   gui/src/lib/validation/rules/<name>.ts
// with a co-located test at
//   gui/src/lib/validation/rules/__tests__/<name>.test.ts
//
// Phase 71 UAT (2026-05-21): danglingFlowPort removed — requiredConnections
// subsumes it for the FlowPort case. The two rules were double-counting
// unconnected FlowPorts (6 errors on a bare Channel where 4 was correct).
// D-16's "verbatim VALD-01 lift" no longer applies post-Plan-13 cleanup.

import type { Validator } from "./types";
import { portType } from "./rules/portType";
import { requiredConnections } from "./rules/requiredConnections";
import { zNMatch } from "./rules/zNMatch";
import { lengthMatch } from "./rules/lengthMatch";
import { geometryConsistency } from "./rules/geometryConsistency";
import { nMatch } from "./rules/nMatch";
import { loopClosure } from "./rules/loopClosure";
import { gravitySumPerLoop } from "./rules/gravitySumPerLoop";
import { pressureBoundaryRequired } from "./rules/pressureBoundaryRequired";
import { drivingElementRequired } from "./rules/drivingElementRequired";

/** All registered validators. The runner (runner.ts) flat-maps over this array
 *  once per debounced tick — no per-rule cache in v1. */
export const validators: Validator[] = [
  portType,
  requiredConnections,
  zNMatch,
  lengthMatch,
  geometryConsistency,
  nMatch,
  loopClosure,
  gravitySumPerLoop,
  pressureBoundaryRequired,
  drivingElementRequired,
];

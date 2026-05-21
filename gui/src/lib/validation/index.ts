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
// Example (once rules land in Plans 04-08):
//   import { zNMatch } from './rules/zNMatch';
//   import { lengthMatch } from './rules/lengthMatch';
//   ...
//   export const validators: Validator[] = [
//     zNMatch, lengthMatch, nMatch, portType,
//     requiredConnections, danglingFlowPort,
//     loopClosure, gravitySumPerLoop, geometryConsistency,
//     pressureBoundaryRequired, drivingElementRequired,
//   ];

import type { Validator } from "./types";
import { portType } from "./rules/portType";
import { requiredConnections } from "./rules/requiredConnections";
import { danglingFlowPort } from "./rules/danglingFlowPort";
import { zNMatch } from "./rules/zNMatch";
import { lengthMatch } from "./rules/lengthMatch";
import { geometryConsistency } from "./rules/geometryConsistency";
import { nMatch } from "./rules/nMatch";
import { loopClosure } from "./rules/loopClosure";

/** All registered validators. Rules plans append by importing each rule and
 *  pushing to this array. The runner (runner.ts) flat-maps over this array
 *  once per debounced tick — no per-rule cache in v1. */
export const validators: Validator[] = [
  portType,
  requiredConnections,
  danglingFlowPort,
  zNMatch,
  lengthMatch,
  geometryConsistency,
  nMatch,
  loopClosure,
];

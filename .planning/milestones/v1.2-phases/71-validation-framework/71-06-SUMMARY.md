---
phase: 71-validation-framework
plan: 06
subsystem: ui
tags: [validation, rules, n-match, bc, sources, fix-action, vitest]

# Dependency graph
requires:
  - phase: 71-validation-framework
    provides: "Plan 01 types.ts FixAction discriminated union + ValidationResult schema + Validator interface"
  - phase: 71-validation-framework
    provides: "Plan 05 zNMatch.ts pattern + test fixture approach for lossless-sync rules"
provides:
  - "nMatch: Validator — single source of truth for value-source n vs consumer n mismatch (D-20)"
  - "FixAction lossless-sync: channel-wins policy propagates consumer.n to source.n"
  - "8 unit tests covering all acceptance-criteria branches including FixAction.apply invocation"
affects:
  - "71-09 (ValidationPanel must invoke apply(set,get) on click — nMatch is the canonical consumer)"
  - "71-13 (Plan 13 removes selectNodeErrors + hasBCError subscription from StreamNode.tsx)"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "bcMode key parsing: consumerId::externalInputName split at first '::' to extract both parts"
    - "Channel-wins lossless-sync: consumer.n is canonical (derives from z_N/L); apply propagates consumer→source, NOT max-wins"
    - "Pitfall-7 mitigation: apply closure captures only primitive values at rule-run time; reads live store via get() at click time"

key-files:
  created:
    - gui/src/lib/validation/rules/nMatch.ts
    - gui/src/lib/validation/rules/__tests__/nMatch.test.ts
  modified:
    - gui/src/lib/validation/index.ts

key-decisions:
  - "Channel-wins (NOT max-wins): consumer n is canonical because it derives from geometric z_N/L; apply writes consumerN to source side only. This differs from zNMatch (max-wins) which has no canonical side."
  - "FixAction label: 'Sync n to 3' — terse engineering voice, omits source-instance name (row description already names both); matches §3.9 canonical 'Sync n: WallTemperature → 10' in spirit."
  - "Targets include 5 entries per binding: 2 node, 2 field(n) symmetric, 1 field(externalInputName) whole-array. D-13 + D-14 satisfied."
  - "Store mutator confirmed as updateNodeParams(nodeId, {parameters:{n:v}}) — plural, patch-style per useStore.ts:1237."

patterns-established:
  - "bcMode source-binding iteration pattern: iterate Object.entries(snapshot.bcMode), filter mode==='source', parse key at first '::'"

requirements-completed: [D-07, D-08, D-12, D-13, D-14, D-15, D-20]

# Metrics
duration: 15min
completed: 2026-05-21
---

# Phase 71 Plan 06: nMatch Rule Summary

**nMatch validator: single source of truth for value-source n-mismatch per D-20, emitting lossless-sync FixAction with channel-wins policy and symmetric D-13/D-14 targets**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-21T15:10:00Z
- **Completed:** 2026-05-21T15:25:00Z
- **Tasks:** 1
- **Files modified:** 3

## Accomplishments
- `nMatch.ts` created: pure-function Validator (id: `n_match`) iterating `snapshot.bcMode` source-mode entries, emitting `ValidationResult{severity:'error'}` per mismatched (consumer, source) n pair
- FixAction `lossless-sync` with `label: 'Sync n to <consumerN>'` (channel wins); `apply(set, get)` closure calls `live.updateNodeParams(sourceId, {parameters:{n:consumerN}})` at click time
- 8 vitest tests cover: match (no result), mismatch (1 error + full target structure), dual-binding partial match (1 result for mismatched only), no-source-bindings (no result), undefined-n defensive (no result), HFS/CHF symmetric case, fixAction label + fixAction.apply invocation with channel-wins assertion
- `index.ts` updated: nMatch imported and pushed to validators array (7 total rule imports)

## Engineering details

- **Store mutator used in apply closure:** `updateNodeParams(nodeId, {parameters:{n:v}})` (confirmed from `useStore.ts:1237`)
- **Label chosen:** `"Sync n to 3"` (consumerN wins; terse, engineering voice)
- **D-13 whole-array fieldPath:** targets include `{kind:'field', nodeId:consumerId, fieldPath:externalInputName}` for the BC field row
- **D-14 symmetric targets:** targets include `{kind:'field', fieldPath:'n'}` on BOTH consumer and source sides + `{kind:'node'}` on both sides
- **Line count of nMatch.ts:** 113 lines
- **Test count:** 8 `it()` blocks

## Task Commits

1. **Task 1: nMatch rule + tests** — `f265707` (feat)

**Plan metadata:** committed in final docs commit (see below)

## Files Created/Modified
- `gui/src/lib/validation/rules/nMatch.ts` — nMatch Validator with FixAction lossless-sync, channel-wins policy, D-13/D-14 targets
- `gui/src/lib/validation/rules/__tests__/nMatch.test.ts` — 8 tests (all pass)
- `gui/src/lib/validation/index.ts` — nMatch registered (7th import + array push)

## Decisions Made

- **Channel-wins policy (documented):** §3.9 line 994 calls this "lossless" — discretization can be changed without altering physics meaningfully. Per §3.11 the consumer (Channel/CHF) owns geometric discretization via z_N/L; value source is downstream. apply propagates consumer→source. Differs from zNMatch (max-wins) which has no canonical side.
- **`updateNodeParams` (plural, patch-style):** confirmed from `useStore.ts:1237`. Single call with `{parameters:{n:v}}` merges via spread — matches zNMatch precedent.
- **Comment adjusted:** removed "useStore" from inline comment to keep `grep -cE "useStore|..."` returning 0 (purity-contract verification gate).

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- **TSC baseline:** 13 pre-existing errors (unchanged after this plan — confirmed via `npx tsc --noEmit`).
- **grep single-quote vs double-quote:** Plan's verification `grep -c "kind: 'lossless-sync'"` uses single quotes; source uses double quotes — grep returned 0 against single-quote pattern. Confirmed via double-quote grep returning 1. Functional parity confirmed; the source style is correct for the codebase.
- **Comment contained "useStore":** The JSDoc header initially read "zero useStore imports" — this caused `grep -cE "useStore..."` to return 1 instead of 0. Fixed by rewriting comment to "zero store imports" — purity contract verification passes.

## Known Stubs

None.

## Threat Flags

None — this plan adds a pure-function validator file and a test file. No new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- `gui/src/lib/validation/rules/nMatch.ts` — FOUND
- `gui/src/lib/validation/rules/__tests__/nMatch.test.ts` — FOUND
- `gui/src/lib/validation/index.ts` — modified (7 rule imports confirmed)
- commit `f265707` — FOUND
- TSC errors: 13 (baseline unchanged)
- `npm run test -- --run src/lib/validation/rules/__tests__/nMatch.test.ts` — 8/8 PASS

## Next Phase Readiness
- Plan 09 (ValidationPanel) can invoke `fixAction.apply(useStore.setState, useStore.getState)` on click for nMatch's "Sync n to N" button — the closure contract is live
- Plan 13 can now remove `selectNodeErrors` + `hasBCError` subscription from `StreamNode.tsx` — nMatch is the registered single source of truth per D-20
- Registry array now at 7 validators; Plans 10/11 (loopClosure, gravitySumPerLoop) complete the §3.9 rule set

---
*Phase: 71-validation-framework*
*Completed: 2026-05-21*

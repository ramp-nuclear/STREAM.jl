# Phase 61 — Deferred Items

Out-of-scope issues observed during execution. Recorded per executor scope-boundary rule
("only auto-fix issues DIRECTLY caused by the current task's changes"); these were already
broken on the `gui-redesign` working branch before Plan 61-01 started.

## Pre-existing TypeScript build errors (baseline, NOT introduced by Plan 61-01)

Reproducer: `git stash && cd gui && npm run build` from the worktree tip (HEAD = 67cafa7,
before Plan 01 edits) produced exactly these 7 errors. Plan 01 added zero new errors
beyond this baseline.

1. `src/components/StreamNode.tsx(73,13)` — `error TS2322: ... Property 'data' does not
   exist on type 'IntrinsicAttributes & HandleProps & ...'`. Passing a `data` prop to
   `<Handle>` from `@xyflow/react`. Likely caused by a `@xyflow/react` major-version
   typing change since the GUI was last rebuilt. Affects FlowPort handles.
2. `src/components/StreamNode.tsx(88,11)` — same issue, ThermalPort handles branch.
3. `src/lib/codeGenerator.ts(315,3)` — `error TS6133: 'nodes' is declared but its value
   is never read.` Unused parameter in `detectThermalTopology`.
4. `src/lib/codeGenerator.ts(736,13)` — `error TS6133: 'singlePort' is declared but its
   value is never read.` Unused local in the array-port ConstantTemperature handler.
5. `src/lib/validation.test.ts(6,8)` — `error TS6133: 'TopologyResult' is declared but
   its value is never read.` Unused type import.
6. `src/lib/validation.test.ts(7,8)` — same, `'NodeError'`.
7. `src/lib/validation.test.ts(8,8)` — same, `'SystemError'`.

**Recommended owner:** A GUI hygiene plan in this phase (or Phase 62/63 frontend prep)
should fix these; they were not on the Plan 61-01 task surface and fixing them here
would expand scope beyond "schema vocabulary extension".

**Test impact:** Vitest still runs because `npm test` only invokes Vitest, not the full
`tsc` gate. The build-time errors do not block test execution.

---
phase: 64-connection-routing
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/lib/autoflip.ts
  - gui/src/lib/__tests__/autoflip.test.ts
autonomous: true
requirements: []
must_haves:
  truths:
    - "Pure module `gui/src/lib/autoflip.ts` exports `resolveFlowPortSide`, `resolveAsymmetricOffset`, `resolveThermalPairSides`, and `detectAxisCollision` with no React, ReactFlow runtime, or Zustand imports (only `import type` is allowed). The module is a pure function of `(nodes, edges)` — no internal state, no `.scp` serialization, no side effects (D-02)."
    - "Given a node with zero connected edges on a port, `resolveFlowPortSide` returns the registry-default side passed in (D-11)."
    - "Given a connected neighbor, `resolveFlowPortSide` chooses left/right/top/bottom by the dominant axis of node-center-to-node-center vector with `|dx| >= |dy|` preferring horizontal (D-13, D-16)."
    - "`resolveAsymmetricOffset` returns `{ left: '25%' | '75%' }` for top/bottom sides and `{ top: '25%' | '75%' }` for left/right sides, with `port_in` at 25% and `port_out` at 75% per reading-direction rule (D-09, D-10)."
    - "`resolveAsymmetricOffset` returns `undefined` when the two FlowPorts of a node resolve to different sides (D-09 only fires on same-side collision)."
    - "`resolveThermalPairSides` returns the spatial-suffix-locked sides: `thermal_left` always maps to spatial `left` (or `top` when axis vertical), `thermal_right` mirrors it; only the axis flips between horizontal and vertical based on aggregated `|dx|` vs `|dy|` of all thermal neighbors (D-12, D-18)."
    - "`resolveThermalPairSides` with zero thermal neighbors returns the registry `default_axis`-derived pair sides (D-11)."
    - "`detectAxisCollision(nodes, edges, nodeId, getComponent)` returns `true` exactly when both the FlowPort axis and the thermal-pair axis resolve to the same orientation (both horizontal or both vertical) for a node that has both a FlowPort and a thermal pair (D-15)."
    - "Anti-parallel sibling detection helper `findAntiParallelSibling(edge, edges)` filters by same edge type (`hydraulicEdge` only) per D-17."
    - "`pnpm -C gui vitest run src/lib/__tests__/autoflip.test.ts` exits 0 with all rule tests passing."
  artifacts:
    - path: "gui/src/lib/autoflip.ts"
      provides: "Pure geometric autoflip rules"
      contains: "export function resolveFlowPortSide"
      min_lines: 120
    - path: "gui/src/lib/__tests__/autoflip.test.ts"
      provides: "Unit tests for D-09, D-10, D-11, D-13, D-14, D-15, D-16, D-17, D-18"
      contains: "describe(\"resolveFlowPortSide\""
      min_lines: 150
  key_links:
    - from: "gui/src/lib/autoflip.ts"
      to: "gui/src/registry/types.ts"
      via: "import type { ComponentDefinition, Port }"
      pattern: "import type.*ComponentDefinition"
    - from: "gui/src/lib/__tests__/autoflip.test.ts"
      to: "gui/src/lib/autoflip.ts"
      via: "import { resolveFlowPortSide, ... }"
      pattern: "import.*from.*autoflip"
---

<objective>
Create the pure autoflip module that encodes every geometric rule from CONTEXT D-09 through D-18. No React, no Zustand, no ReactFlow runtime — only `import type` from peer modules. Mirrors the `gui/src/lib/layers.ts` and `gui/src/lib/selectors/nodeErrors.ts` precedents.

Purpose: Isolating the rules in a pure module lets Plans 03 and 04 wire them into render paths without re-implementing geometry, and makes every rule trivially unit-testable via Vitest. Plans 03 and 04 both depend on this module.

Output: One new pure module (`gui/src/lib/autoflip.ts`) and one test file covering each locked decision with at least one assertion per ID.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/64-connection-routing/64-CONTEXT.md
@.planning/phases/64-connection-routing/64-RESEARCH.md
@.planning/notes/gui-redesign-design-decisions.md
@gui/src/lib/layers.ts
@gui/src/lib/selectors/nodeErrors.ts
@gui/src/registry/types.ts
@gui/src/registry/components.json

<interfaces>
<!-- Key types autoflip consumes. The Port shape in the registry is the contract. -->

From gui/src/registry/types.ts (verified — Port interface):
- `Port` carries optional `side?: "left" | "right" | "top" | "bottom"`, optional `default_axis?: "horizontal" | "vertical"`, optional `pair_with?: string`, and `type: "FlowPort" | "ThermalPort" | "BCPort"`. The schema is already Phase 64-ready.

From `@xyflow/react` (type-only):
- `Node` has `position: { x, y }` (top-left corner) and `measured?: { width?, height? }` (set after first render).
- `Edge` has `source`, `target`, `sourceHandle`, `targetHandle`, `type`, and `id`.

From the registry (verified — `components.json`):
- CAC thermal pair lines 116-117: `{ "name": "thermal_left", "type": "ThermalPort", "array_size": "n", "default_axis": "vertical", "pair_with": "thermal_right" }` — no `side` field. Mirror entry for `thermal_right`.
- HD thermal pair lines 917-918: same shape, `default_axis: "horizontal"`.
- Every FlowPort carries `"side"` (e.g. `port_in: "left"`, `port_out: "right"`) — that is the D-11 registry-default fallback.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — Write autoflip rule unit tests</name>
  <files>gui/src/lib/__tests__/autoflip.test.ts</files>
  <read_first>
    - .planning/phases/64-connection-routing/64-CONTEXT.md (decisions section — every D-ID is testable)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Code Examples section — reference implementation shapes)
    - gui/src/lib/selectors/__tests__/nodeErrors.test.ts (test-style template)
    - gui/src/lib/selectors/nodeErrors.ts (pure-module template)
    - gui/src/registry/types.ts (Port + ComponentDefinition shapes)
    - gui/src/registry/components.json (registry-default sides + thermal default_axis)
  </read_first>
  <behavior>
    Test groups (one `describe` per function):
    - `describe("resolveFlowPortSide")`:
      - Test: D-11 — `port_in` with no edges returns the supplied `defaultSide` ("left").
      - Test: D-13/D-16 — neighbor to the right (`dx=200, dy=0`) resolves to "right".
      - Test: D-13/D-16 — neighbor below (`dx=0, dy=200`) resolves to "bottom".
      - Test: D-13 tie-break — `|dx| == |dy|` resolves to horizontal (`dx=100, dy=100` → "right"; `dx=-100, dy=100` → "left").
      - Test: D-14 — strict comparison, no dead zone (single-pixel flip at 45°).
      - Test: targetHandle filter — `port_in` only inspects edges whose `targetHandle === portName` and `target === nodeId`; an unrelated `port_out`-handle edge does not influence `port_in` resolution.
    - `describe("resolveAsymmetricOffset")`:
      - Test: D-09 — when both FlowPorts of a Pump resolve to "right", `port_in` returns `{ top: "25%" }` and `port_out` returns `{ top: "75%" }`.
      - Test: D-10 — when both resolve to "bottom", `port_in` returns `{ left: "25%" }` and `port_out` returns `{ left: "75%" }`.
      - Test: D-09 negative — when ports resolve to different sides, returns `undefined`.
      - Test: D-12 — never invoked for ThermalPorts (function only inspects FlowPorts).
    - `describe("resolveThermalPairSides")`:
      - Test: D-11 — zero thermal edges + `default_axis: "vertical"` → `thermal_left` maps to `top`, `thermal_right` to `bottom` (D-18 suffix-locking).
      - Test: D-11 — zero thermal edges + `default_axis: "horizontal"` → `thermal_left` maps to `left`, `thermal_right` to `right`.
      - Test: D-18 — when neighbors are vertically above/below (aggregated `|dy| > |dx|`), axis flips to vertical so `thermal_left` → "top" / `thermal_right` → "bottom", regardless of which thermal port carries the edge.
      - Test: D-18 — when neighbors are horizontally left/right (aggregated `|dx| > |dy|`), axis is horizontal so `thermal_left` → "left" / `thermal_right` → "right".
      - Test: D-13 — tie-break aggregated `|dx| == |dy|` prefers horizontal axis.
    - `describe("detectAxisCollision")`:
      - Test: D-15 — CAC node with FlowPort axis "horizontal" (port_in connected to a node directly left) AND thermal pair axis "horizontal" (HD neighbor directly right) returns `true`.
      - Test: D-15 — CAC node with FlowPort axis "horizontal" but thermal pair axis "vertical" returns `false`.
      - Test: D-15 — Pump (no thermal pair) returns `false`.
    - `describe("findAntiParallelSibling")`:
      - Test: D-08 — two edges `A→B` and `B→A`, both `type: "hydraulicEdge"`, returns the sibling.
      - Test: D-17 — `A→B` of type `hydraulicEdge` and `B→A` of type `bcEdge` returns `undefined` (same-type-only).
      - Test: D-17 — `A→B` of type `hydraulicEdge` and an unrelated thermal-styled edge between the same nodes (no `type: "hydraulicEdge"`) returns `undefined`.

    Fixture helpers:
    - `makeNode(id, x, y, componentId, w=140, h=70)` returning an `@xyflow/react` `Node` shape with `position` and `measured`.
    - `makeEdge(id, source, target, sourceHandle, targetHandle, type="hydraulicEdge")`.
    - `makeGetComponent(map)` returning the registry-lookup function used by the autoflip helpers.

    All tests must run under `@vitest-environment node` (no DOM needed for pure functions). The test file must NOT import anything from `@xyflow/react` at runtime — only `import type { Node, Edge }`.
  </behavior>
  <action>
    Create `gui/src/lib/__tests__/autoflip.test.ts`. Use Vitest's `describe`/`it`/`expect`. Add the `@vitest-environment node` docblock (Pitfall avoid: do not pull happy-dom in for pure tests). Import the four exports from `../autoflip` — these do not exist yet, so the test file fails to compile (RED state). Encode every D-ID listed in `<behavior>` as a separate `it(...)` with a comment naming the D-ID it covers. Use the fixture helpers described above (small, inline, no shared module). For `findAntiParallelSibling`, the same-type filter is `edge.type === "hydraulicEdge"` only — bcEdge and styled thermal edges do not count, implementing D-17. Do NOT implement `autoflip.ts` in this task — that is Task 2.
  </action>
  <verify>
    <automated>cd gui && pnpm vitest run src/lib/__tests__/autoflip.test.ts 2>&amp;1 | grep -E "FAIL|Cannot find module" &amp;&amp; echo "RED confirmed"</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: file `gui/src/lib/__tests__/autoflip.test.ts` exists and contains the literal string `from "../autoflip"`.
    - Source assertion: `grep -c '\bit(' gui/src/lib/__tests__/autoflip.test.ts` returns at least 18 (one `it(` per D-ID enumerated above).
    - Test command: `cd gui && pnpm vitest run src/lib/__tests__/autoflip.test.ts` exits non-zero with a "Cannot find module" or "Failed to resolve import" error pointing at `../autoflip`. This is the expected RED state before Task 2.
    - Source assertion: `grep -c "@vitest-environment node" gui/src/lib/__tests__/autoflip.test.ts` equals 1.
    - Source assertion (no DOM in pure tests): `grep -c "happy-dom" gui/src/lib/__tests__/autoflip.test.ts` equals 0.
  </acceptance_criteria>
  <done>RED state established: the test file imports a not-yet-existing module and every D-ID has at least one named assertion.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GREEN — Implement autoflip pure module</name>
  <files>gui/src/lib/autoflip.ts</files>
  <read_first>
    - gui/src/lib/__tests__/autoflip.test.ts (from Task 1 — the test contract drives the implementation)
    - gui/src/lib/layers.ts (pure-helper module template — match its shape, docstring style, sectioning)
    - gui/src/lib/selectors/nodeErrors.ts (NodeErrorsInput sub-state pattern — adopt the same "selector takes only what it needs" purity discipline)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Code Examples section — reference implementations to mirror, including the `nodeCenter` fallback for unmeasured nodes)
    - gui/src/registry/types.ts (Port + ComponentDefinition for `getComponent` callback signature)
  </read_first>
  <behavior>
    Module exports (matching the test file's imports):
    - `type Side = "left" | "right" | "top" | "bottom"`.
    - `type OffsetStyle = { left?: string; top?: string }`.
    - `function nodeCenter(n: Node): { x: number; y: number }` — internal, uses `n.measured?.width ?? 140` / `n.measured?.height ?? 70` and `position.x + w/2`, `position.y + h/2`.
    - `function resolveFlowPortSide(nodes, edges, nodeId, portName, defaultSide, getComponent)` — implements D-11 (no edge → defaultSide), D-13/D-16 (center-to-center, tie-break horizontal), D-14 (strict comparison).
    - `function resolveAsymmetricOffset(nodes, edges, nodeId, side, portName, defaultSide, getComponent)` — implements D-09 (25%/75%), D-10 (reading-direction: top/bottom-side offset uses `left` key; left/right-side offset uses `top` key), returns `undefined` when sibling resolves to a different side.
    - `function resolveThermalPairSides(nodes, edges, nodeId, thisPortName, pairWith, defaultAxis, getComponent)` — implements D-12 (always opposing faces), D-18 (suffix is definitive: `thermal_left` → spatial-left-or-top, `thermal_right` → spatial-right-or-bottom, only axis flips), D-11 (no edges → defaultAxis).
    - `function detectAxisCollision(nodes, edges, nodeId, getComponent)` — returns `boolean`; both FlowPort axis and thermal-pair axis horizontal, or both vertical.
    - `function findAntiParallelSibling(edge, edges): Edge | undefined` — D-08 swap detection filtered by `e.type === "hydraulicEdge"` per D-17 (same-type-only).

    Implementation discipline:
    - Zero runtime imports from `@xyflow/react`, `zustand`, or `react`. Only `import type`.
    - Pure functions — no closures over module state, no `Date.now`, no randomness.
    - `getComponent` is a callback (`(id: string) => ComponentDefinition | undefined`) passed in by the caller — the module does not import the registry singleton (keeps it tree-shakeable and trivially mockable from tests).
    - The "in vs out" port heuristic uses `portName.includes("in")` matching the precedent in `StreamNode.tsx:150` (FlowPortHandle). Document this explicitly with a code comment.

    After implementing, Task 1's tests transition from RED to GREEN. Run them as the verification.
  </behavior>
  <action>
    Create `gui/src/lib/autoflip.ts` implementing the six exports listed in `<behavior>` against the contract Task 1 already encoded. Match the docstring + section-header style of `gui/src/lib/layers.ts` (use `// ----- ... -----` block dividers per function, JSDoc `/** ... */` on exports). For `resolveThermalPairSides`, follow D-18 strictly: the per-suffix side assignment is fixed (`endsWith("_left")` → left/top, `endsWith("_right")` → right/bottom); only the axis flips based on aggregated `|sumDx|` vs `|sumDy|` over all thermal edges touching either pair member. Tie-break: `sumDx >= sumDy` → horizontal axis (D-13). Use the pseudocode in RESEARCH.md `## Code Examples` as the seed, but trim to what the tests actually require — do not add untested complexity.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/lib/__tests__/autoflip.test.ts</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: `gui/src/lib/autoflip.ts` exists.
    - Source assertion (no React/ReactFlow runtime imports): `grep -v '^import type' gui/src/lib/autoflip.ts | grep -cE "from \"@xyflow/react\"|from \"react\"|from \"zustand\"" ` returns 0.
    - Source assertion (six required exports): `grep -cE "^export (function|type) (resolveFlowPortSide|resolveAsymmetricOffset|resolveThermalPairSides|detectAxisCollision|findAntiParallelSibling|Side|OffsetStyle)" gui/src/lib/autoflip.ts` returns at least 6.
    - Test command: `cd gui && pnpm vitest run src/lib/__tests__/autoflip.test.ts` exits 0 with every test passing.
    - Behavior assertion: every D-ID listed in the must_haves truths has a corresponding green test in the Task 1 spec file.
  </acceptance_criteria>
  <done>All autoflip rules implemented per the locked decisions; Task 1's RED tests turn GREEN; pure-module purity invariants hold.</done>
</task>

</tasks>

<verification>
- `pnpm -C gui vitest run src/lib/__tests__/autoflip.test.ts` exits 0 (all rule tests green).
- `grep -v '^import type' gui/src/lib/autoflip.ts | grep -cE "from \"@xyflow/react\"|from \"react\""` returns 0 (purity invariant).
- Module exports are stable for downstream consumers (Plans 03 and 04).
</verification>

<success_criteria>
Plan 64-01 is complete when:
- [ ] `gui/src/lib/autoflip.ts` exists and exports the six required symbols.
- [ ] `gui/src/lib/__tests__/autoflip.test.ts` has at least 18 named `it(...)` cases (one per D-ID) and all pass.
- [ ] Zero runtime imports from `@xyflow/react`, `zustand`, or `react` in `autoflip.ts`.
- [ ] All locked decisions D-08, D-09, D-10, D-11, D-12, D-13, D-14, D-15, D-16, D-17, D-18 have at least one source-assertable test.
</success_criteria>

<output>
After completion, create `.planning/phases/64-connection-routing/64-01-SUMMARY.md` documenting:
- Final shape of `autoflip.ts` exports (function signatures).
- Test count and which D-IDs each test covers.
- Any deviations from the RESEARCH.md sketch (and why).
- Confirmation that the module has zero runtime imports from React/ReactFlow/Zustand.
</output>

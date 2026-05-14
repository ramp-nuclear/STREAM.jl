---
phase: 64-connection-routing
plan: 04
type: execute
wave: 2
depends_on: [01]
files_modified:
  - gui/src/lib/selectors/topologyHints.ts
  - gui/src/lib/selectors/__tests__/topologyHints.test.ts
  - gui/src/components/StreamNode.tsx
  - gui/src/components/__tests__/StreamNode.topologyHint.test.tsx
autonomous: true
requirements: []
must_haves:
  truths:
    - "A new pure selector `gui/src/lib/selectors/topologyHints.ts` exports `selectTopologyHints(state, nodeId, getComponent): string[]` mirroring the `nodeErrors.ts` template — zero React, zero Zustand, zero ReactFlow runtime imports."
    - "The selector emits the tag `\"topology-axis-collision\"` exactly when D-15's conditions hold: the node has both a FlowPort and a thermal pair, AND `detectAxisCollision` (from Plan 01) returns true."
    - "The selector is wired into `StreamNode.tsx` via a primitive-boolean Zustand selector (`hasTopologyHint`) following the Pitfall-3 / Pattern-1 precedent from `hasBCError`."
    - "When `hasTopologyHint` is true, a small non-blocking yellow chip with the message \"Hydraulic and thermal neighbors on same axis — consider repositioning.\" renders inside the StreamNode (e.g. a `<div data-testid=\"topology-hint-chip\">` with amber-500 background, positioned in the bottom-right of the node)."
    - "The chip is NON-BLOCKING (D-15): it does not change the red-ring (`hasAnyError`) state, does not block code-gen, and does not toggle `errorNodeIds`."
    - "When no axis collision exists, no chip renders (`queryByTestId(\"topology-hint-chip\")` returns null)."
    - "`pnpm -C gui vitest run src/lib/selectors/__tests__/topologyHints.test.ts src/components/__tests__/StreamNode.topologyHint.test.tsx` exits 0."
  artifacts:
    - path: "gui/src/lib/selectors/topologyHints.ts"
      provides: "Pure topology-axis-collision validator (D-15)"
      contains: "export function selectTopologyHints"
    - path: "gui/src/lib/selectors/__tests__/topologyHints.test.ts"
      provides: "Pure-selector tests covering D-15 / D-17 / non-blocking severity invariant"
      contains: "describe(\"selectTopologyHints"
    - path: "gui/src/components/__tests__/StreamNode.topologyHint.test.tsx"
      provides: "Rendered yellow-chip test"
      contains: "topology-hint-chip"
  key_links:
    - from: "gui/src/lib/selectors/topologyHints.ts"
      to: "gui/src/lib/autoflip.ts"
      via: "import { detectAxisCollision } from \"../autoflip\""
      pattern: "from \"../autoflip\""
    - from: "gui/src/components/StreamNode.tsx"
      to: "gui/src/lib/selectors/topologyHints.ts"
      via: "useStore(useCallback(s => selectTopologyHints(s, id, getComponent).length > 0, [id]))"
      pattern: "selectTopologyHints"
---

<objective>
Add the D-15 topology-hint validator as a pure selector mirroring `gui/src/lib/selectors/nodeErrors.ts`, then surface it inside `StreamNode.tsx` as a non-blocking yellow chip. Resolves Open Question 3 from the research by introducing a "warning" severity discriminator that does not contaminate the existing red-ring error path.

Purpose: §3.4's "crowded edge" CAC case (flow + thermal both wanting the same axis → 4 handles on 2 edges) is rare but ugly when it happens. D-15 mandates a non-blocking topology hint to suggest the user reposition. Autoflip alone interleaves the handles (25%/75% flow + centered thermal); this plan adds the textual nudge.

Output: One new pure selector + tests, one StreamNode patch + rendered-chip test. Depends on Plan 01's `detectAxisCollision` export. Wave 2 alongside Plan 03 — they touch overlapping files (`StreamNode.tsx`), so this plan runs AFTER Plan 03 finishes touching `StreamNode.tsx` to avoid edit conflicts. See "Sequencing note" below.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/64-connection-routing/64-CONTEXT.md
@.planning/phases/64-connection-routing/64-RESEARCH.md
@.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md
@gui/src/lib/autoflip.ts
@gui/src/lib/selectors/nodeErrors.ts
@gui/src/lib/selectors/__tests__/nodeErrors.test.ts
@gui/src/components/StreamNode.tsx
@gui/src/registry/components.json

<sequencing_note>
Plan 03 and Plan 04 both modify `StreamNode.tsx`. Per the orchestrator's wave assignment rule (same-wave plans must not overlap files), this is a wave conflict. Resolution: Plan 04 RUNS AFTER Plan 03 in execution order even though both depend only on Plan 01. The orchestrator should sequence them; if running with `--parallel`, Plan 04 must wait for Plan 03's `StreamNode.tsx` write to land. Alternative: bump Plan 04 to wave 3. The phase-level wave assignment in the frontmatter retains `wave: 2` for dependency-graph correctness but the executor MUST sequence reads/writes to `StreamNode.tsx` (Plan 03 first).
</sequencing_note>

<interfaces>
<!-- Contract from Plan 01. -->

From `gui/src/lib/autoflip.ts`:
- `detectAxisCollision(nodes, edges, nodeId, getComponent): boolean`.
- `type Side = "left" | "right" | "top" | "bottom"`.

From `gui/src/lib/selectors/nodeErrors.ts` (the template):
- `selectNodeErrors(state: NodeErrorsInput, nodeId): string[]` — pure, returns string tags. Wired in `StreamNode.tsx:199-204` via primitive-boolean selector.

Phase 64 wires `selectTopologyHints` analogously but to a yellow chip surface (non-blocking) instead of the red ring.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — selectTopologyHints pure selector + tests</name>
  <files>
    gui/src/lib/selectors/__tests__/topologyHints.test.ts
    gui/src/lib/selectors/topologyHints.ts
  </files>
  <read_first>
    - gui/src/lib/selectors/nodeErrors.ts (the pure-selector template — match its shape exactly)
    - gui/src/lib/selectors/__tests__/nodeErrors.test.ts (the test template)
    - gui/src/lib/autoflip.ts (Plan 01 — `detectAxisCollision` signature)
    - .planning/phases/64-connection-routing/64-CONTEXT.md (D-15)
    - gui/src/registry/components.json (CAC entry — the canonical D-15 trigger)
  </read_first>
  <behavior>
    Test groups in `topologyHints.test.ts`:
    - `describe("selectTopologyHints (D-15)")`:
      - Test: CAC node with hydraulic neighbor to the left AND thermal neighbor to the right (both axes horizontal) → returns `["topology-axis-collision"]`.
      - Test: CAC node with hydraulic neighbor to the left AND thermal neighbor above (axes orthogonal) → returns `[]`.
      - Test: Pump node (no thermal pair) → returns `[]` regardless of neighbors.
      - Test: HeatDiffusion node (thermal pair, no FlowPort) → returns `[]` (D-15 only fires when BOTH layers exist on the same component).
      - Test: isolated CAC (no edges) → returns `[]` (no axes to collide).
      - Test: stable result — calling the selector twice with identical state returns referentially-equal-by-`Object.is` arrays only if both are empty (`[] === []` is false; that's fine — consumers wrap with `.length > 0`).

    Implementation of `topologyHints.ts`:
    - Mirror `nodeErrors.ts`'s file header (zero React/zustand/runtime ReactFlow imports; only `import type`).
    - `export interface TopologyHintsInput { nodes: Node[]; edges: Edge[] }` (sub-state type — selector takes only what it needs).
    - `export function selectTopologyHints(state, nodeId, getComponent): string[]` — body delegates to `detectAxisCollision(state.nodes, state.edges, nodeId, getComponent)`. Pre-check: node exists, component lookup succeeds, component has both a FlowPort AND a thermal pair (via `pair_with`). Return `[]` for any pre-check miss.
    - Export the tag constant: `export const HINT_AXIS_COLLISION = "topology-axis-collision"` so consumers reference the constant instead of stringly-typing the tag.
  </behavior>
  <action>
    Create both files in a single task. First write `gui/src/lib/selectors/__tests__/topologyHints.test.ts` (with the `@vitest-environment node` docblock — pure selector, no DOM); it imports from `../topologyHints` which does not exist yet (RED). Then write `gui/src/lib/selectors/topologyHints.ts` to make the tests pass: delegate the axis-collision math to `detectAxisCollision` from `../autoflip`, add the `pair_with`-presence pre-check, return the tag array. Match the style of `nodeErrors.ts` — same header block, same "consumers MUST wrap with primitive return" advisory comment, same section-divider conventions. The module must export both `selectTopologyHints` and `HINT_AXIS_COLLISION`.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/lib/selectors/__tests__/topologyHints.test.ts</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: `gui/src/lib/selectors/topologyHints.ts` exists.
    - Source assertion: `gui/src/lib/selectors/__tests__/topologyHints.test.ts` exists and has `grep -c '\bit(' ` returning at least 5.
    - Source assertion (no React/runtime ReactFlow imports): `grep -v '^import type' gui/src/lib/selectors/topologyHints.ts | grep -cE "from \"@xyflow/react\"|from \"react\"|from \"zustand\""` returns 0.
    - Source assertion: contains the literal `HINT_AXIS_COLLISION = "topology-axis-collision"`.
    - Test command: `cd gui && pnpm vitest run src/lib/selectors/__tests__/topologyHints.test.ts` exits 0.
  </acceptance_criteria>
  <done>Pure selector implemented + tested; ready to be consumed from `StreamNode.tsx`.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: RED — StreamNode topology-hint chip render test</name>
  <files>gui/src/components/__tests__/StreamNode.topologyHint.test.tsx</files>
  <read_first>
    - gui/src/components/StreamNode.tsx (current state — should already include Plan 03's autoflip wiring)
    - gui/src/components/__tests__/StreamNode.anchor.test.tsx (rendered-StreamNode test template)
    - gui/src/lib/selectors/topologyHints.ts (Task 1 — the selector being wired in)
    - .planning/phases/64-connection-routing/64-CONTEXT.md (D-15 — non-blocking yellow chip)
    - gui/src/registry/components.json (CAC entry — the canonical D-15 trigger)
  </read_first>
  <behavior>
    Test cases:
    - Test (D-15 positive): Render a CAC with both axes resolving to horizontal (configure `useStore.setState` with nodes/edges that trigger `detectAxisCollision === true`). Assert `getByTestId("topology-hint-chip")` is present AND its `textContent` contains the substring "same axis".
    - Test (D-15 negative): Render an isolated Pump (no thermal pair, no edges). Assert `queryByTestId("topology-hint-chip")` is `null`.
    - Test (D-15 negative): Render a CAC with axes resolved to orthogonal orientations. Assert chip is null.
    - Test (non-blocking — D-15 severity): When the chip is present, the rendered node's root `<div>` does NOT have the `ring-destructive` class (the red-ring outline reserved for blocking errors). The chip and the red ring are independent surfaces.

    Fixture pattern matches `StreamNode.anchor.test.tsx`. Reset `useStore` between tests.
  </behavior>
  <action>
    Create `gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` with `@vitest-environment happy-dom`. Each `it(...)` references D-15. The "non-blocking" test asserts the absence of `ring-destructive` on the rendered node root via `container.querySelector("[class*=\"ring-destructive\"]")` being `null`. Do NOT modify `StreamNode.tsx` in this task.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/StreamNode.topologyHint.test.tsx 2>&amp;1 | grep -E "FAIL|✗" &amp;&amp; echo "RED confirmed"</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: file `gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` exists.
    - Source assertion: `grep -c '\bit(' gui/src/components/__tests__/StreamNode.topologyHint.test.tsx` returns at least 4.
    - Source assertion: contains the literal string `topology-hint-chip` AND `ring-destructive`.
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/StreamNode.topologyHint.test.tsx` exits non-zero (RED — chip not yet wired).
  </acceptance_criteria>
  <done>RED state: rendered-chip tests fail because `StreamNode.tsx` does not yet emit the chip element.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: GREEN — Wire topology hint into StreamNode</name>
  <files>gui/src/components/StreamNode.tsx</files>
  <read_first>
    - gui/src/components/StreamNode.tsx (current state including Plan 03's autoflip wiring — read in full)
    - gui/src/lib/selectors/topologyHints.ts (Task 1)
    - gui/src/components/__tests__/StreamNode.topologyHint.test.tsx (Task 2)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Pattern 1 — primitive selector; Pitfall 3 — fresh-object selector)
  </read_first>
  <behavior>
    Changes:
    - Add `import { selectTopologyHints } from "@/lib/selectors/topologyHints"`.
    - Inside `StreamNode` (after the existing `hasBCError` selector), add:
      `const hasTopologyHint = useStore(useCallback((s) => selectTopologyHints(s as unknown as TopologyHintsInput, id, getComponent).length > 0, [id]))` — primitive boolean (Pitfall 3 guarded).
    - Inside the node's JSX, after the existing `<div data-testid="source-block-label">` block (if present) and before the handle-render blocks, render the chip conditionally:
      - If `hasTopologyHint` is true, render a `<div data-testid="topology-hint-chip" role="status" aria-label="Topology hint" className="absolute right-1 bottom-1 text-[10px] rounded border bg-amber-100 text-amber-900 px-1 py-0.5">Hydraulic and thermal neighbors on same axis — consider repositioning.</div>`.
      - The chip lives INSIDE the node's main `<div>` container so it sits within the node bounds.
    - Do NOT mix `hasTopologyHint` into `hasAnyError`. D-15 mandates non-blocking severity — the chip is independent of the red-ring outline. The red ring stays driven by `hasError || hasBCError` only.
    - Add an `import type { TopologyHintsInput } from "@/lib/selectors/topologyHints"` (with `export interface TopologyHintsInput` added to the selector file in Task 1).
  </behavior>
  <action>
    Patch `gui/src/components/StreamNode.tsx` per the `<behavior>` block. The chip element MUST carry `data-testid="topology-hint-chip"` for the test to find it. The text MUST contain the substring "same axis" so the test's `textContent.includes("same axis")` assertion passes. Style hint: use Tailwind `amber-100` / `amber-900` (matches the existing thermal accent color family `#f59e0b`). Render the chip inside the existing `<div>` returned from `StreamNode` (i.e., before the `flowPorts.map`, after the existing optional `sourceLabel` div).
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/StreamNode.topologyHint.test.tsx src/components/__tests__/StreamNode.autoflip.test.tsx src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: `grep -c "selectTopologyHints" gui/src/components/StreamNode.tsx` is at least 1.
    - Source assertion: `grep -c "topology-hint-chip" gui/src/components/StreamNode.tsx` is at least 1.
    - Source assertion (non-blocking discipline — chip is NOT mixed into hasAnyError): `grep -E "hasAnyError\s*=" gui/src/components/StreamNode.tsx | grep -c "hasTopologyHint"` returns 0.
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/StreamNode.topologyHint.test.tsx` exits 0.
    - Test command (regression on Plan 03 + Phase 63.1 tests): `cd gui && pnpm vitest run src/components/__tests__/StreamNode.autoflip.test.tsx src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx` exits 0.
    - Behavior assertion: when both axes are horizontal on a CAC, the rendered node contains exactly one element with `data-testid="topology-hint-chip"` and zero elements with `ring-destructive` (when no other error tags are present).
  </acceptance_criteria>
  <done>Yellow non-blocking topology-hint chip wired in; selector tests + chip render tests green; red-ring path unchanged; full Phase 64 surface tests pass.</done>
</task>

</tasks>

<verification>
- `pnpm -C gui vitest run src/lib/selectors/__tests__/topologyHints.test.ts` exits 0.
- `pnpm -C gui vitest run src/components/__tests__/StreamNode.topologyHint.test.tsx` exits 0.
- Full Phase 64 vitest pass: `pnpm -C gui vitest run src/lib/__tests__/autoflip.test.ts src/lib/selectors/__tests__/topologyHints.test.ts src/components/__tests__/HydraulicEdge.bow.test.tsx src/components/__tests__/StreamNode.autoflip.test.tsx src/components/__tests__/StreamNode.topologyHint.test.tsx` exits 0.
- No regression on Phase 63.1 surfaces: `pnpm -C gui vitest run src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx src/components/__tests__/BCEdge.test.tsx src/lib/selectors/__tests__/nodeErrors.test.ts` exits 0.
</verification>

<success_criteria>
Plan 64-04 complete when:
- [ ] `gui/src/lib/selectors/topologyHints.ts` exists with the pure-selector signature mirroring `nodeErrors.ts`.
- [ ] `selectTopologyHints` delegates to `detectAxisCollision` from `autoflip.ts`.
- [ ] Yellow chip renders in `StreamNode.tsx` exactly when D-15 fires.
- [ ] Chip is non-blocking — does not contribute to `hasAnyError`, does not toggle `errorNodeIds`, does not gate code-gen.
- [ ] All RED tests turn GREEN; no Phase 63.1 / Plan 03 regressions.
</success_criteria>

<output>
After completion, create `.planning/phases/64-connection-routing/64-04-SUMMARY.md` documenting:
- Final selector contract.
- Final chip render path (selector → primitive boolean → conditional render).
- Confirmation of non-blocking discipline (red-ring untouched).
- Test counts and pass-rate.
- Note: if D-15 was difficult to manually trigger during the Plan 03 smoke checkpoint, suggest a follow-up phase to expand validator severity-routing into a unified panel (Phase 71 candidate).
</output>

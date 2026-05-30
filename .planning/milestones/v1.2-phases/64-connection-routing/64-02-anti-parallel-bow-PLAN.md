---
phase: 64-connection-routing
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/components/HydraulicEdge.tsx
  - gui/src/components/__tests__/HydraulicEdge.bow.test.tsx
autonomous: true
requirements: []
must_haves:
  truths:
    - "Anti-parallel offset for bidirectional pairs is delivered as a polish hook inside `HydraulicEdge.tsx` — a custom-edge tweak, not architectural (D-06)."
    - "When two hydraulic edges exist between the same node pair in opposite directions (D-08), each draws a ±8px perpendicular bow at the smoothstep midpoint (D-07)."
    - "Bidirectional-pair detection filters by `edge.type === \"hydraulicEdge\"`; a BCEdge or a thermal-styled edge between the same node pair does NOT count as a sibling (D-17)."
    - "Bow direction is stable: ordering by edge `id` so the smaller-id edge bows `+8px` and the larger-id edge bows `-8px` — the two siblings bow in opposite directions, no flicker."
    - "A solitary hydraulic edge (no anti-parallel sibling) renders with zero bow — pixel-identical to the pre-Phase-64 path."
    - "Edge component reads sibling state via `useStore.getState().edges` synchronously inside render (Pattern 3 — no hook subscription); no `useStore(...)` hook is added inside `HydraulicEdge` (Pitfall: render-storm)."
    - "`pnpm -C gui vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx` exits 0."
  artifacts:
    - path: "gui/src/components/HydraulicEdge.tsx"
      provides: "HydraulicEdge with anti-parallel ±8px bow"
      contains: "BOW_PX"
    - path: "gui/src/components/__tests__/HydraulicEdge.bow.test.tsx"
      provides: "Anti-parallel bow detection + filter + direction tests"
      contains: "describe(\"HydraulicEdge anti-parallel bow\""
  key_links:
    - from: "gui/src/components/HydraulicEdge.tsx"
      to: "gui/src/store/useStore"
      via: "useStore.getState().edges (no hook subscription)"
      pattern: "useStore\\.getState\\(\\)\\.edges"
---

<objective>
Add the anti-parallel ±8px perpendicular bow to `HydraulicEdge.tsx` per D-06, D-07, D-08, and the D-17 same-type-only refinement. The edge component reads the sibling synchronously via `useStore.getState()` (Pattern 3 — edges already re-render every drag frame; subscribing would cause a re-render storm).

Purpose: Closes the Example-1 X-cross visual ugliness for bidirectional hydraulic pairs without architectural change. Self-contained edge tweak; runs in Wave 1 parallel to Plan 01 because the bow logic does not depend on autoflip outputs (the bow is applied to whatever endpoint coordinates ReactFlow hands the edge).

Output: Patched `HydraulicEdge.tsx` and a Vitest spec asserting bow detection, type filter (D-17), direction stability, and zero-bow fallback.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/64-connection-routing/64-CONTEXT.md
@.planning/phases/64-connection-routing/64-RESEARCH.md
@gui/src/components/HydraulicEdge.tsx
@gui/src/components/BCEdge.tsx
@gui/src/components/CanvasPanel.tsx
@gui/src/components/__tests__/BCEdge.test.tsx

<interfaces>
<!-- The shape `HydraulicEdge` consumes from ReactFlow and Zustand. -->

From `@xyflow/react`:
- `EdgeProps` provides `id`, `source`, `target`, `sourceX`, `sourceY`, `targetX`, `targetY`, `sourcePosition`, `targetPosition`, `style`, `markerEnd`.
- `getSmoothStepPath({ sourceX, sourceY, targetX, targetY, sourcePosition, targetPosition, ... })` returns `[path, labelX, labelY]`.

From `gui/src/store/useStore.ts`:
- `useStore.getState().edges: Edge[]` — synchronous read, no subscription. The CanvasPanel `getPortType` helper (line 27-34) already uses this pattern.

From the test precedent `gui/src/components/__tests__/BCEdge.test.tsx`:
- Edge components render inside `<ReactFlowProvider>` + an `<svg>` wrapper; assertions usually target the rendered `<path d="..." />` (`container.querySelector("path")`).
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — Write anti-parallel bow tests</name>
  <files>gui/src/components/__tests__/HydraulicEdge.bow.test.tsx</files>
  <read_first>
    - gui/src/components/HydraulicEdge.tsx (current 32-line implementation)
    - gui/src/components/__tests__/BCEdge.test.tsx (edge-component test template)
    - .planning/phases/64-connection-routing/64-CONTEXT.md (D-06, D-07, D-08, D-17)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Pitfall 4 — same-type filter)
    - gui/src/store/useStore.ts (lines 27-34 of CanvasPanel.tsx show the getState pattern)
  </read_first>
  <behavior>
    Test groups:
    - `describe("HydraulicEdge anti-parallel bow")`:
      - Test: solitary hydraulic edge (only one edge in `useStore.getState().edges`) renders the same SVG path as a pre-Phase-64 baseline (no bow). Assert by computing the expected unmodified `getSmoothStepPath` result with the same inputs and comparing.
      - Test: D-08 — two hydraulic edges between (A, B) in opposite directions, edge under test has the smaller id ("e1" vs "e2") → rendered path's perpendicular offset at midpoint is `+8px` from baseline.
      - Test: D-08 — the sibling edge (larger id "e2") → rendered path's perpendicular offset at midpoint is `−8px` from baseline. Direction stability: the two siblings bow in OPPOSITE directions.
      - Test: D-17 — `A→B` hydraulicEdge + `B→A` `type: "bcEdge"` → no bow (zero offset) on the hydraulic edge. The BCEdge does not count as a sibling.
      - Test: D-17 — `A→B` hydraulicEdge + an edge `B→A` with `type` set to a thermal value (any string other than `"hydraulicEdge"`) → no bow.
      - Test: render-storm guard — `HydraulicEdge` source code contains zero `useStore(` hook subscriptions (only the synchronous `useStore.getState()` read pattern). Asserted via a string grep against the source file (`fs.readFileSync`).

    Fixture pattern:
    - `setupStore(edgesArray)` — `useStore.setState({ edges: edgesArray, ...emptyDefaults })` before each test; restore with `cleanup()` after.
    - `renderEdge(props)` — wraps `<HydraulicEdge {...props} />` in `<ReactFlowProvider><svg>...</svg></ReactFlowProvider>` and returns the rendered SVG container.
    - To assert perpendicular offset: parse the `d` attribute from the rendered `<path>` element; compute the midpoint y (for horizontal source→target) or midpoint x (for vertical) and compare against the baseline midpoint ±8.

    For determinism: use fixed source/target coordinates (`sourceX=0, sourceY=0, targetX=200, targetY=0`, both `sourcePosition: Position.Right`, `targetPosition: Position.Left`) so the smoothstep midpoint is at exactly `(100, 0)` in the no-bow baseline.
  </behavior>
  <action>
    Create `gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` with the `@vitest-environment happy-dom` docblock. Import `useStore` and reset edges via `setState` before each test. Add a helper `extractMidpointY(svgPath: string): number` that parses the SVG `d` attribute (the path string returned by `getSmoothStepPath` has a deterministic format — extract the y-coordinate of the midline). Use `@testing-library/react`'s `render` and `cleanup`. For the render-storm guard test, read `gui/src/components/HydraulicEdge.tsx` via `node:fs` and assert `!source.includes("useStore(")` (note the paren — `useStore.getState()` does NOT match). Document the rationale inline with a Pitfall reference. Do NOT modify `HydraulicEdge.tsx` in this task.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx 2>&amp;1 | grep -E "FAIL|✗" &amp;&amp; echo "RED confirmed"</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: file `gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` exists.
    - Source assertion: `grep -c '\bit(' gui/src/components/__tests__/HydraulicEdge.bow.test.tsx` returns at least 6.
    - Source assertion: contains the literal string `"hydraulicEdge"` and the literal string `"bcEdge"` (D-17 filter coverage).
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx` exits non-zero — the bow tests fail because `HydraulicEdge.tsx` does not yet implement bowing.
    - Source assertion: includes `@vitest-environment happy-dom`.
  </acceptance_criteria>
  <done>RED state: test file exists, runs, and reports failing assertions for every bow scenario except possibly the no-sibling baseline.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GREEN — Implement anti-parallel bow in HydraulicEdge</name>
  <files>gui/src/components/HydraulicEdge.tsx</files>
  <read_first>
    - gui/src/components/HydraulicEdge.tsx (the 32-line file being edited)
    - gui/src/components/__tests__/HydraulicEdge.bow.test.tsx (from Task 1 — the contract)
    - gui/src/components/CanvasPanel.tsx (lines 27-34 — `getPortType` reference for the `useStore.getState()` pattern)
    - gui/src/components/BCEdge.tsx (an existing edge component reading store state — for reference on `memo` + `EdgeProps` destructuring)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Code Examples §"Anti-parallel bow inside HydraulicEdge" — implementation strategy)
  </read_first>
  <behavior>
    Implementation discipline:
    - `const BOW_PX = 8` module constant (D-07).
    - Inside the function body: `const allEdges = useStore.getState().edges` — synchronous read, no hook.
    - `const sibling = allEdges.find(e => e.id !== id && e.type === "hydraulicEdge" && e.source === target && e.target === source)` — D-08 swap + D-17 same-type filter.
    - `const bow = sibling ? (id < sibling.id ? BOW_PX : -BOW_PX) : 0` — deterministic direction by lexicographic id ordering.
    - Apply bow by **pre-offsetting endpoint coords perpendicular to the dominant axis** before calling `getSmoothStepPath` (RESEARCH.md "Option (a)"): for a primarily horizontal edge (`sourcePosition` is Left or Right), shift both `sourceY` and `targetY` by `bow`; for a primarily vertical edge, shift `sourceX` and `targetX` by `bow`. This produces a parallel-shifted smoothstep — visually the two siblings render as parallel offset paths, equivalent to a "bow" at the midpoint where the two would otherwise overlap.
    - Do NOT introduce `useStore(...)` hook subscriptions (Pitfall — re-render storm in the edge component).
    - Preserve existing behavior: still uses `BaseEdge`, still consumes `style` and `markerEnd` from props.

    Implementation strategy choice: pre-offset the endpoint coords. Document the choice in a code comment with a reference to RESEARCH.md §"Anti-parallel bow inside HydraulicEdge" and explain it's strategy (a) (simpler than a custom path string). The "perpendicular axis" rule:
    - If `sourcePosition` is `Position.Left` or `Position.Right` → axis is horizontal → bow applies to Y.
    - Otherwise → bow applies to X.
  </behavior>
  <action>
    Replace the body of `HydraulicEdge.tsx` with the bow-aware implementation. Add the `BOW_PX = 8` constant at module scope. Inside the function: synchronously read `useStore.getState().edges`, find the same-type swap sibling, compute the signed bow, and shift the smoothstep endpoints perpendicular to the dominant axis BEFORE calling `getSmoothStepPath`. Keep `memo(HydraulicEdge)` as the default export. Import `useStore` from `../store/useStore` (matches the pattern in `BCEdge.tsx`). Add an inline comment block documenting D-07 (8px), D-08 (swap), D-17 (same-type filter), and Pattern 3 (`getState()` over `useStore()` hook to avoid render-storm on drag).
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: `gui/src/components/HydraulicEdge.tsx` contains `const BOW_PX = 8`.
    - Source assertion: `grep -c "useStore.getState()" gui/src/components/HydraulicEdge.tsx` is at least 1.
    - Source assertion (render-storm guard): `grep -E "useStore\(" gui/src/components/HydraulicEdge.tsx | grep -v "useStore\.getState"` returns no matches (no hook subscriptions).
    - Source assertion (D-17): file contains the literal string `"hydraulicEdge"` (the same-type filter).
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx` exits 0 with every test passing.
    - Regression test command: `cd gui && pnpm vitest run src/components/__tests__/BCEdge.test.tsx` still exits 0 (BCEdge is a sibling, not modified, but we sanity-check that the same Zustand reset pattern in tests doesn't conflict).
  </acceptance_criteria>
  <done>Anti-parallel bow renders for hydraulic↔hydraulic pairs only; tests green; render-storm guard holds.</done>
</task>

</tasks>

<verification>
- `pnpm -C gui vitest run src/components/__tests__/HydraulicEdge.bow.test.tsx` exits 0.
- `pnpm -C gui vitest run src/components/__tests__/BCEdge.test.tsx` still exits 0 (no regression on sibling edge component).
- `grep -E "useStore\(" gui/src/components/HydraulicEdge.tsx | grep -v "useStore\.getState"` returns no matches.
</verification>

<success_criteria>
Plan 64-02 complete when:
- [ ] `HydraulicEdge.tsx` reads `useStore.getState().edges` synchronously (no hook subscription).
- [ ] Anti-parallel sibling detection filters by `type === "hydraulicEdge"` (D-17).
- [ ] Bow direction is deterministic and opposite between siblings (lexicographic id ordering).
- [ ] All 6+ bow tests pass.
- [ ] BCEdge tests unchanged (no regression).
</success_criteria>

<output>
After completion, create `.planning/phases/64-connection-routing/64-02-SUMMARY.md` documenting:
- Final diff summary of `HydraulicEdge.tsx`.
- Chosen bow strategy (endpoint pre-offset) with reference to RESEARCH.md.
- Test count and what each asserts.
- Confirmation that no `useStore(` hook subscriptions were added (render-storm guard).
</output>

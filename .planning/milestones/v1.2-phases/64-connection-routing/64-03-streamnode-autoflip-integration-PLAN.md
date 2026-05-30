---
phase: 64-connection-routing
plan: 03
type: execute
wave: 2
depends_on: ["64-01"]
files_modified:
  - gui/src/components/StreamNode.tsx
  - gui/src/components/__tests__/StreamNode.autoflip.test.tsx
autonomous: true
requirements: []
must_haves:
  truths:
    - "`FlowPortHandle` in `StreamNode.tsx` consumes `resolveFlowPortSide(nodes, edges, nodeId, portName, registryDefaultSide, getComponent)` via a primitive-string Zustand selector (Pattern 1) — `port.side` from the registry is the D-11 fallback, never the live source of truth. Because ReactFlow re-renders nodes on every position update during a drag, the selector re-evaluates each frame, satisfying D-01 (autoflip recomputes live during drag)."
    - "The autoflip path stores nothing in node data, nothing in Zustand state, and nothing in the `.scp` file — sides are derived per render from `(s.nodes, s.edges)` plus the registry default. A `useStore` primitive-string selector cache is the only allowed implementation-level memoization, and it is NOT persisted (D-02, D-03)."
    - "The selectors that resolve sides read `s.nodes` and `s.edges` directly — they never filter by `s.activeLayer` or by any layer-derived field on the edge. Switching the active layer dims handles visually but does NOT re-route edges (D-05)."
    - "Anchor glyph position (D-04) derives from the same resolved side as the `<Handle>` — anchor and handle never decouple visually."
    - "When both FlowPorts of a node resolve to the same side, ReactFlow places them at 25% (port_in) and 75% (port_out) along the appropriate axis via inline `style.left`/`style.top` per D-09 and D-10."
    - "Thermal `<Handle>` block in `StreamNode.tsx` consumes `resolveThermalPairSides(nodes, edges, nodeId, port.name, port.pair_with!, port.default_axis!, getComponent)` for components carrying `pair_with` (CAC + HD); the resolved side replaces the latent `port.side!` non-null assertion (Pitfall 6 — CAC thermal `side` is undefined in the registry today)."
    - "After any port's resolved side changes, `useUpdateNodeInternals(nodeId)` fires from a `useEffect` keyed on a concatenated resolved-side string so ReactFlow re-measures handle DOM (Pattern 2, Pitfall 1)."
    - "Every `<Handle>` in `StreamNode.tsx` resolves to a defined `Position` — no `Position` is ever `undefined` for any registered component (closes the latent CAC thermal bug)."
    - "All resolved-side selectors return primitive strings, never fresh objects/arrays (Pitfall 3 — re-render storm)."
    - "Rendered-handle tests with `@vitest-environment happy-dom` + `<ReactFlowProvider>` assert correct `react-flow__handle-{position}` class for representative §3.3 layouts (Example 1 X-cross, Examples 3-4 vertical stack)."
  artifacts:
    - path: "gui/src/components/StreamNode.tsx"
      provides: "Autoflipped FlowPort and thermal-pair handles + anchor co-location + useUpdateNodeInternals wiring"
      contains: "resolveFlowPortSide"
    - path: "gui/src/components/__tests__/StreamNode.autoflip.test.tsx"
      provides: "Rendered-handle assertions for representative layouts"
      contains: "describe(\"StreamNode autoflip"
  key_links:
    - from: "gui/src/components/StreamNode.tsx"
      to: "gui/src/lib/autoflip.ts"
      via: "import { resolveFlowPortSide, resolveAsymmetricOffset, resolveThermalPairSides, type Side, type OffsetStyle }"
      pattern: "from \"@/lib/autoflip\"|from \"../lib/autoflip\""
    - from: "gui/src/components/StreamNode.tsx"
      to: "@xyflow/react useUpdateNodeInternals"
      via: "useEffect keyed on resolvedSideKey"
      pattern: "useUpdateNodeInternals\\("
---

<objective>
Wire the Plan 01 autoflip module into `StreamNode.tsx`'s handle render path. Replace every `port.side!` lookup with a live-derived value from `resolveFlowPortSide` / `resolveThermalPairSides`. Apply D-09/D-10 asymmetric placement via inline `style` offsets. Call `useUpdateNodeInternals(id)` from a `useEffect` keyed on the concatenated resolved-side string per Pattern 2. The anchor glyph already co-renders inside `FlowPortHandle` and consumes the same `side` value, so D-04 is satisfied by construction.

Purpose: This is where the user sees the change — handles flip live during drag, anchor glyphs follow, thermal handles get a defined position (closes the latent Pitfall 6 bug where CAC thermal `<Handle position={sideToPosition[undefined!]}>` rendered at ReactFlow's default).

Output: Patched `StreamNode.tsx` with live autoflip wiring + a Vitest rendered-handle spec covering Examples 1, 3, and 4 from §3.3 plus the CAC thermal latent-bug fix.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/64-connection-routing/64-CONTEXT.md
@.planning/phases/64-connection-routing/64-RESEARCH.md
@.planning/notes/gui-redesign-design-decisions.md
@.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md
@gui/src/components/StreamNode.tsx
@gui/src/lib/autoflip.ts
@gui/src/components/__tests__/StreamNode.test.tsx
@gui/src/components/__tests__/StreamNode.anchor.test.tsx
@gui/src/registry/components.json

<interfaces>
<!-- Contract between StreamNode and the autoflip module (from Plan 01). -->

From `gui/src/lib/autoflip.ts` (Plan 01 produces these):
- `type Side = "left" | "right" | "top" | "bottom"`.
- `type OffsetStyle = { left?: string; top?: string }`.
- `resolveFlowPortSide(nodes, edges, nodeId, portName, defaultSide, getComponent): Side`.
- `resolveAsymmetricOffset(nodes, edges, nodeId, side, portName, defaultSide, getComponent): OffsetStyle | undefined`.
- `resolveThermalPairSides(nodes, edges, nodeId, thisPortName, pairWith, defaultAxis, getComponent): { thisSide: Side; pairSide: Side }`.

From `@xyflow/react`:
- `useUpdateNodeInternals(): (id: string) => void` — call from a `useEffect` after handle position changes.

From `gui/src/registry/components.json` (verified by grep):
- FlowPorts always carry `"side"`. ThermalPorts on CAC (lines 116-117) and HD (lines 917-918) carry `"default_axis"` + `"pair_with"` but NO `"side"` — this is the latent bug Plan 03 fixes.
- Single-port thermal entries (e.g. ConstantTemperature line 891: `{ "name": "thermal", "type": "ThermalPort", "side": "left" }`) carry `"side"` and have no `"pair_with"`. These are NOT pair-handled by `resolveThermalPairSides`; they keep their registry-default side.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: RED — Rendered-handle autoflip tests</name>
  <files>gui/src/components/__tests__/StreamNode.autoflip.test.tsx</files>
  <read_first>
    - gui/src/components/__tests__/StreamNode.test.tsx (rendered-node test template — `@vitest-environment happy-dom` + `<ReactFlowProvider>`)
    - gui/src/components/__tests__/StreamNode.anchor.test.tsx (shows how to render `StreamNode` with full `NodeProps` shape)
    - gui/src/components/StreamNode.tsx (current handle render path: FlowPortHandle, thermal `<Handle>` map, BC `<Handle>` map)
    - .planning/notes/gui-redesign-design-decisions.md §3.3 (Examples 1-4 ground truth)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Pitfall 6 — CAC thermal latent bug; A5 — handle class assertion strategy)
    - gui/src/registry/components.json (Pump, ChannelAndContacts, HeatDiffusion port shapes)
  </read_first>
  <behavior>
    Test groups (one `describe` per scenario):
    - `describe("StreamNode autoflip — FlowPort §3.3 Example 1 X-cross")`:
      - Setup: two Pump nodes at `(0,0)` and `(300,0)`. Edge `pump1.port_out → pump2.port_in`. Reverse edge `pump2.port_out → pump1.port_in`.
      - Test: `pump1.port_out` handle renders with class `react-flow__handle-right` (neighbor is to the right, dx > 0).
      - Test: `pump1.port_in` handle renders with class `react-flow__handle-right` (also flips right because its connection comes from pump2 to the right — same side as port_out).
      - Test (D-09): both ports on right side → inline style includes `top: 25%` (port_in) and `top: 75%` (port_out) — D-10 reading direction for left/right side uses the `top` percentage axis.
      - Test (D-04 anchor co-location): if `pump1` had an anchor on `port_in.P`, the rendered `data-testid="anchor-indicator"` element would carry the `anchorIndicatorStyleFor("right")` offset (i.e. `right: -16`). Assert this via inline style.
    - `describe("StreamNode autoflip — §3.3 Examples 3-4 vertical stack")`:
      - Setup: pump above, channel below.
      - Test: pump's `port_out` resolves to "bottom" (neighbor directly below, |dy| > |dx|).
      - Test: channel's `port_in` resolves to "top".
    - `describe("StreamNode autoflip — D-11 zero-connection default")`:
      - Setup: isolated Pump, no edges.
      - Test: `port_in` renders with class `react-flow__handle-left` (registry default).
      - Test: `port_out` renders with class `react-flow__handle-right` (registry default).
    - `describe("StreamNode autoflip — Pitfall 6 CAC thermal latent bug")`:
      - Setup: isolated ChannelAndContacts, no edges. The registry entry for CAC carries thermal pair with `default_axis: "vertical"` and NO `side` field.
      - Test: `thermal_left` handle renders with class `react-flow__handle-top` (suffix-locked per D-18 with vertical default_axis).
      - Test: `thermal_right` handle renders with class `react-flow__handle-bottom`.
      - Test: every rendered `.react-flow__handle` element on the node has one of the four position classes; none has an undefined position (regression guard for Pitfall 6).
    - `describe("StreamNode autoflip — D-18 thermal axis flip on neighbor")`:
      - Setup: ChannelAndContacts at `(0, 0)`, HeatDiffusion at `(300, 0)` (horizontally adjacent). Edge `cac.thermal_right → hd.thermal_left` (any handle pair).
      - Test: CAC's `thermal_left` flips to spatial "left" (horizontal axis takes over because |dx| > |dy|).
      - Test: CAC's `thermal_right` flips to spatial "right" (suffix-locked, pair opposite).
    - `describe("StreamNode autoflip — useUpdateNodeInternals fires on side change")`:
      - Mock `useUpdateNodeInternals` from `@xyflow/react` via Vitest's `vi.mock`.
      - Test: re-render the StreamNode with a different edge set (causing a flip) → `updateNodeInternals(id)` was called at least once with the node's id.

    Test fixture conventions:
    - Reset `useStore` between tests via `useStore.setState({ nodes: [...], edges: [...], ... })`.
    - Use `container.querySelectorAll(".react-flow__handle")` to list rendered handles; iterate to find one matching `[data-handleid="port_in"]` etc.
    - For Pitfall 6 regression: assert via `Array.from(handles).every(h => /react-flow__handle-(left|right|top|bottom)/.test(h.className))`.
  </behavior>
  <action>
    Create `gui/src/components/__tests__/StreamNode.autoflip.test.tsx` with `@vitest-environment happy-dom`. Use the `renderStreamNode(id, componentId, instanceName)` helper from `StreamNode.anchor.test.tsx` as the template. Add a setup helper that primes `useStore.setState` with nodes (positions) and edges before each render. For the `useUpdateNodeInternals` mock test, use `vi.mock("@xyflow/react", async (importOriginal) => { const m = await importOriginal(); return { ...m, useUpdateNodeInternals: vi.fn(() => mockUpdate) }; })` — read up on the existing mock pattern in `BCEdge.test.tsx` or `StreamNode.test.tsx`; if no exact precedent, do a minimal partial mock. Every `it(...)` must reference its D-ID in a comment. Do NOT modify `StreamNode.tsx` in this task.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/StreamNode.autoflip.test.tsx 2>&amp;1 | grep -E "FAIL|✗" &amp;&amp; echo "RED confirmed"</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: file `gui/src/components/__tests__/StreamNode.autoflip.test.tsx` exists.
    - Source assertion: `grep -c '\bit(' gui/src/components/__tests__/StreamNode.autoflip.test.tsx` returns at least 11.
    - Source assertion: contains the literal string `react-flow__handle-top` AND `react-flow__handle-bottom` AND `react-flow__handle-left` AND `react-flow__handle-right`.
    - Source assertion: contains the string `useUpdateNodeInternals` (mock or assertion).
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/StreamNode.autoflip.test.tsx` exits non-zero — tests fail because `StreamNode.tsx` still consumes `port.side!` directly.
  </acceptance_criteria>
  <done>RED state: all rendered-handle assertions fail; mock of `useUpdateNodeInternals` is in place.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: GREEN — Wire autoflip into FlowPortHandle, thermal Handle map, and useUpdateNodeInternals</name>
  <files>gui/src/components/StreamNode.tsx</files>
  <read_first>
    - gui/src/components/StreamNode.tsx (full file — 315 lines)
    - gui/src/lib/autoflip.ts (Plan 01 — exports we consume)
    - gui/src/components/__tests__/StreamNode.autoflip.test.tsx (Task 1 — drives the implementation)
    - .planning/phases/64-connection-routing/64-RESEARCH.md (Patterns 1, 2; Pitfalls 1, 2, 3, 6)
    - .planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md (D-13 anchor glyph — Phase 64 D-04 consumer)
  </read_first>
  <behavior>
    Changes to `StreamNode.tsx`:

    1. **Imports** (top of file):
       - Add `useEffect` to the existing `useCallback` import from `react`.
       - Add `useUpdateNodeInternals` to the existing `@xyflow/react` import line.
       - Add `import { resolveFlowPortSide, resolveAsymmetricOffset, resolveThermalPairSides, type Side, type OffsetStyle } from "@/lib/autoflip"`.
       - Add `import type { Node, Edge } from "@xyflow/react"` (for selector typing).

    2. **`FlowPortHandle` refactor** (current lines 141-187):
       - Add a primitive-returning Zustand selector for the resolved side:
         `const resolvedSide = useStore(useCallback((s) => resolveFlowPortSide(s.nodes, s.edges, nodeId, port.name, (port.side as Side) ?? "left", getComponent), [nodeId, port.name, port.side]))`. The selector returns a primitive string — Pitfall 3 guarded.
       - Add a primitive-returning selector for the asymmetric offset, but to keep zustand happy (Pitfall 3), encode the offset as a string `"left:25%"` / `"top:75%"` / empty-string-for-none, then parse to an `OffsetStyle` object via a local helper inside the component body. This avoids returning a fresh object from the selector.
       - Pass `resolvedSide` (not `port.side!`) into `sideToPosition[...]`.
       - Merge the parsed `OffsetStyle` into the `<Handle>`'s `style` prop.
       - Pass `resolvedSide` (not `port.side`) into `anchorIndicatorStyleFor(...)` — D-04 anchor co-location follows by construction.

    3. **Thermal `<Handle>` map refactor** (current lines 271-288):
       - For each thermal port, if `port.pair_with` is defined (CAC + HD case):
         - Compute `const { thisSide } = useStore(useCallback((s) => resolveThermalPairSides(s.nodes, s.edges, id, port.name, port.pair_with!, port.default_axis ?? "horizontal", getComponent), [id, port.name, port.pair_with, port.default_axis]))` — but wait, this selector returns an object, which is Pitfall 3. INSTEAD: split into a primitive-returning selector that returns just `thisSide: Side`. Wrap the original helper inline within the selector body and extract the primitive.
       - If `port.pair_with` is undefined (single-port thermal like ConstantTemperature), keep using `port.side` as today (registry default).
       - Replace `position={sideToPosition[port.side!]}` with `position={sideToPosition[resolvedThermalSide]}`.
       - **The `type={port.side === "right" || port.side === "bottom" ? "source" : "target"}` heuristic stays but reads from `resolvedThermalSide` instead** — so handle source/target identity flips with autoflip, matching how edges connect during the spike.

       Note: extracting hooks into per-port sub-components is the cleanest way to keep `useStore`/`useCallback` hooks out of a `.map(...)` loop (React's rules-of-hooks). Create a `ThermalPortHandle({ nodeId, port, dimThermalHandles })` sub-component mirroring `FlowPortHandle`'s structure. Do this; do not pre-iterate sides outside the map.

    4. **`useUpdateNodeInternals` wiring** (in `StreamNode` body, after computing all resolved sides):
       - Each handle sub-component (`FlowPortHandle`, `ThermalPortHandle`) is independent. To call `updateNodeInternals` once per node when ANY port flips, register a Zustand selector that returns a concatenated resolved-side key for all ports of the node — but this is an object/array, violating Pitfall 3.

       SIMPLER PATTERN: each `FlowPortHandle` / `ThermalPortHandle` calls `useUpdateNodeInternals` and registers its own `useEffect` keyed on its single resolved side. Per-handle `useEffect` runs `updateNodeInternals(nodeId)` whenever its side flips. Multiple sub-components each call `updateNodeInternals(nodeId)` redundantly when several ports flip together, which ReactFlow handles idempotently — verified by community docs.

       Use this per-sub-component pattern:
       ```
       const updateNodeInternals = useUpdateNodeInternals();
       useEffect(() => { updateNodeInternals(nodeId); }, [nodeId, resolvedSide, updateNodeInternals]);
       ```
       Document with an inline comment referencing RESEARCH.md Pattern 2 / Pitfall 1.

       **Pitfall 2 (race):** Do NOT add `setTimeout(..., 0)` initially. If the human smoke checkpoint in Plan 64-04 / a follow-up reveals stuck edges on rapid drag, switch to the deferred form. Add a code comment noting this so the next reader sees the planned fallback.

    5. **BC `<Handle>` block (lines 289-312) UNCHANGED.** Phase 64 does not touch BC port routing — that is governed by Phase 63 + 63.1's bidirectional sync, and BC ports carry explicit `side` in the registry. Confirm by leaving the block as-is.

    6. **Remove the `port.side!` non-null assertion** anywhere it appears for FlowPort and pair-thermal cases. Replace with the resolved side (or a sane fallback for single-port thermal: `port.side ?? "left"`).

    Style discipline:
    - Every new selector returns a primitive string. If a tuple is needed, encode as a string like `"top:25%"` and parse inline.
    - Comments referencing D-IDs, Pitfall numbers, and RESEARCH.md Pattern numbers wherever non-obvious decisions are made.
  </behavior>
  <action>
    Refactor `gui/src/components/StreamNode.tsx` per the `<behavior>` block. Add a new `ThermalPortHandle` sub-component analogous to `FlowPortHandle`. In `FlowPortHandle`, add the resolved-side selector + offset-string selector + parse helper, and wire `useUpdateNodeInternals` via `useEffect`. In `ThermalPortHandle`, add the resolved-side selector (single primitive) + `useEffect` + `useUpdateNodeInternals`. The outer `StreamNode` function body iterates `thermalPorts.map((port) => port.pair_with ? <ThermalPortHandle ... /> : <SingleThermalHandle ... />)` — the single-port branch can keep using `port.side ?? "left"` since it carries one in the registry. Anchor glyph styling inside `FlowPortHandle` reads `resolvedSide` (not `port.side`) so D-04 follows automatically. Leave the BC `<Handle>` map untouched.
  </action>
  <verify>
    <automated>cd gui &amp;&amp; pnpm vitest run src/components/__tests__/StreamNode.autoflip.test.tsx src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx</automated>
  </verify>
  <acceptance_criteria>
    - Source assertion: `grep -c "resolveFlowPortSide" gui/src/components/StreamNode.tsx` is at least 1.
    - Source assertion: `grep -c "resolveThermalPairSides" gui/src/components/StreamNode.tsx` is at least 1.
    - Source assertion: `grep -c "useUpdateNodeInternals" gui/src/components/StreamNode.tsx` is at least 1.
    - Source assertion (Pitfall 3 guard — no object/array returns from new selectors): `grep -v '^\s*//' gui/src/components/StreamNode.tsx | grep -E "useStore\(useCallback\(\(s.*=>.*\{ side:|useStore\(useCallback\(\(s.*=>.*\["` returns no matches.
    - Source assertion (Pitfall 6 fix): `grep -c "port\.side!" gui/src/components/StreamNode.tsx` returns 0 (the non-null assertion is gone).
    - Test command: `cd gui && pnpm vitest run src/components/__tests__/StreamNode.autoflip.test.tsx` exits 0.
    - Test command (regression): `cd gui && pnpm vitest run src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx` exits 0.
    - Behavior assertion (D-04): the rendered anchor indicator's `style.right` is `-16` when the resolved FlowPort side is `"right"` (anchor follows handle).
  </acceptance_criteria>
  <done>FlowPort and pair-thermal handles consume live-derived sides; anchor glyphs follow; useUpdateNodeInternals fires on flips; latent CAC thermal undefined bug is closed; all RED tests turn GREEN; sibling tests unchanged.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 3: Smoke checkpoint — visual regression on simple_loop.scp</name>
  <what-built>
    Live autoflip on FlowPorts + thermal pairs in `StreamNode.tsx`. Anchor glyph follows the autoflipped side. Anti-parallel bow on hydraulic edges (from Plan 64-02). `useUpdateNodeInternals` fires on flips so edges re-measure to the new handle position. CAC thermal `<Handle>` no longer renders with an undefined Position (Pitfall 6 closed).
  </what-built>
  <how-to-verify>
    1. Run `pnpm -C gui dev` and open the GUI.
    2. Use File → Open and select `gui/export_examples/simple_loop.scp`.
    3. Expected: pump-CAC-pump loop renders with each FlowPort handle on the side facing its neighbor (no more handles pointing away from connected nodes). The CAC's thermal_left and thermal_right pair is on opposing top/bottom faces (or left/right faces if the neighbor is horizontal) — pre-Phase-64 the CAC thermal handles were rendering at ReactFlow's default position because `side` was undefined.
    4. Drag a node around. Expected: handles flip live during drag as the dominant axis to the neighbor changes; edges follow the handle without sticking (`useUpdateNodeInternals` working). Acceptable: brief 1-pixel flicker exactly at 45° (D-14 strict comparison — documented).
    5. Create a second pump and wire `pump1.port_out → pump2.port_in` and `pump2.port_out → pump1.port_in`. Expected: each hydraulic edge bows ±8px so they no longer overlap on a single midline (Plan 64-02 + §3.3 Example 1 closure).
    6. Switch active layer to Thermal. Expected: hydraulic edges dim but DO NOT re-route. Switch back to Hydraulic. Expected: same edges, same paths — D-05 invariant.
    7. Add an anchor to `pump1.port_in.P` (right-click → set anchor, or via the BCs tab). Expected: the lucide Anchor glyph renders adjacent to the autoflipped handle position, not the registry default. Drag the connected node to flip the handle side and confirm the anchor follows.

    The five `example_*.png` screenshots from §3.3 are referenced in the design doc but not in the repo; rely on §3.3 prose and the listed scenarios as the ground truth. If `gui/export_examples/simple_loop.scp` does not exist yet, build a fresh pump-CAC-pump loop from the toolbox.
  </how-to-verify>
  <resume-signal>
    Type "approved" if all 7 verifications pass.
    Otherwise list which step failed and any observed bugs (sticky edges, undefined positions, anchor decoupling, bow direction wrong, missing axis flip on neighbor move, etc.). Plan 64-04 will close any gap as part of its scope or via a follow-up plan.
  </resume-signal>
</task>

</tasks>

<verification>
- `pnpm -C gui vitest run src/components/__tests__/StreamNode.autoflip.test.tsx` exits 0.
- `pnpm -C gui vitest run src/components/__tests__/StreamNode.test.tsx src/components/__tests__/StreamNode.anchor.test.tsx` exits 0 (no regression).
- `grep -c "port\.side!" gui/src/components/StreamNode.tsx` returns 0 (Pitfall 6 fix permanent).
- Human checkpoint approves visual behavior on `simple_loop.scp`.
</verification>

<success_criteria>
Plan 64-03 complete when:
- [ ] FlowPortHandle and ThermalPortHandle consume `autoflip.ts` exports via primitive-returning selectors.
- [ ] D-04 anchor co-location verified by test + smoke (anchor follows resolved side).
- [ ] D-09 / D-10 asymmetric placement applied via inline `style.left`/`style.top`.
- [ ] `useUpdateNodeInternals` fires on every per-port side flip.
- [ ] Pitfall 6 latent CAC thermal bug closed (every Handle has a defined Position class).
- [ ] All RED tests turn GREEN; no regression in StreamNode.test.tsx or StreamNode.anchor.test.tsx.
- [ ] Human checkpoint approved.
</success_criteria>

<output>
After completion, create `.planning/phases/64-connection-routing/64-03-SUMMARY.md` documenting:
- Diff summary of `StreamNode.tsx`.
- Whether the `useUpdateNodeInternals` race (Pitfall 2) needed the `setTimeout` workaround in practice (record for posterity).
- Confirmation of D-04 / Pitfall 3 / Pitfall 6 closures.
- Human smoke checkpoint result.
</output>

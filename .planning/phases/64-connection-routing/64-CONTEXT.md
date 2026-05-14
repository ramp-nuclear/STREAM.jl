# Phase 64: Connection routing - Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Solve the connection-arrow ugliness verified in `example_*.png` screenshots by introducing per-port autoflip for FlowPorts and axis-flip for thermal-pair ports. Specifically:

- **FlowPort autoflip:** Each `port_in` / `port_out` handle picks the side (left/right/top/bottom) facing its connected neighbor, based on the dominant axis (`|dx|` vs `|dy|`) of the node-center vector.
- **Asymmetric same-side placement:** When both ports of one component flip to the same edge, position `port_in` toward the reading-direction start of that edge and `port_out` toward the end (so they don't overlap).
- **Thermal-pair axis-flip (CAC + HD only):** The pair `thermal_left` / `thermal_right` swings together between left/right and top/bottom based on where thermal neighbors are. Pair stays on opposing faces — never same-side.
- **Anti-parallel offset polish:** Bidirectional pairs (forward + return between same two nodes) get a small constant perpendicular bow so they don't overlap on the midline.

**In scope (this phase only):** the four bullets above + the topology-hint validation chip for the rare crowded-edge case on CAC.

**Out of scope:** Per-component rotation override, manual handle override, edge-routing algorithm changes (smoothstep stays), thermal handle visual restyle (Phase 71 design-system), layer system rework (Phase 68).

</domain>

<decisions>
## Implementation Decisions

### Recomputation & Persistence
- **D-01:** Autoflip recomputes **live during drag**. Every position update re-evaluates handle sides. ReactFlow already re-renders on drag; the marginal cost is the autoflip function itself.
- **D-02:** Resolved side is **pure derivation** — a function of `(connections, node positions)` computed each render. Nothing new added to node data; nothing serialized to `.scp`. Same file always renders identically because positions + connections are already persisted.
- **D-03:** A `useMemo` / Zustand selector cache is allowed as an implementation detail (perf), but the cache is NOT persisted.
- **D-04:** Anchor glyphs (introduced in Phase 63.1) **follow the autoflipped handle side**. When `port_in` flips to bottom, its anchor glyph renders at the bottom too. Anchor and handle never decouple visually.
- **D-05:** Layer dimming is purely visual — autoflip **always** considers ALL connections regardless of `activeLayer`. Switching between Hydraulic and Thermal layers never re-routes edges.

### Anti-Parallel Offset Polish
- **D-06:** Anti-parallel offset for bidirectional pairs **is in scope** for Phase 64 (closes Example-1 X-cross fully). Implemented as a custom-edge tweak — not architectural.
- **D-07:** Offset is a **small constant perpendicular bow of ±8px** on the smoothstep midpoint. No distance-proportional scaling. Not user-tunable in v1.2 (no Settings entry).
- **D-08:** "Bidirectional pair" detection rule: two edges where `(sourceNode, targetNode)` of one == `(targetNode, sourceNode)` of the other. Any port pair counts — port identity does not need to match.

### Asymmetric Placement Geometry
- **D-09:** When both FlowPorts share a side, position them at **25% / 75%** along that side. Scales with node width; uses ReactFlow handle `style.left` / `style.top` percentage offsets.
- **D-10:** "First port toward leading end" follows **reading direction**:
  - Top side: `port_in` left, `port_out` right
  - Bottom side: `port_in` left, `port_out` right
  - Left side: `port_in` top, `port_out` bottom
  - Right side: `port_in` top, `port_out` bottom
  Always reads in→out left-to-right or top-to-bottom — matches §3.3 spec verbatim.
- **D-11:** Default (zero connections): handles render at their **registry-default sides** — no autoflip evaluation at all until at least one connection exists on the port. Per §3.3.
- **D-12:** Asymmetric placement does **NOT** apply to thermal pairs — they are always on opposing faces by construction (per §3.4).

### Edge Cases
- **D-13:** Tie-breaking when `|dx| ≈ |dy|`: **prefer horizontal**. Use `|dx| ≥ |dy| → horizontal, else vertical`. Deterministic; no hysteresis state.
- **D-14:** **No dead zone** for live-drag axis switching — strict comparison. Flicker risk at exactly 45° is a 1-pixel band; unlikely in real drags. If real-world drag turns out to flicker, a 10° dead zone can be added later as a follow-up patch.
- **D-15:** Crowded-edge case (CAC where flow + thermal both want the same axis → 4 handles on 2 edges): **interleave handles AND surface a topology-hint validation chip**.
  - Interleaving: flow at 25%/75% (already locked by D-09); thermal centered at 50% on each face (single handle, no pair-side issue).
  - Validation chip: yellow / non-blocking — "Hydraulic and thermal neighbors on same axis — consider repositioning." Wired into the existing validation panel surface used by Phase 63.1 BC errors. Rare in practice per §3.4 ("not load-bearing").
- **D-16:** Neighbor anchor for the `dx` / `dy` computation is **node center to node center** (`x + width/2, y + height/2`). Cheap, stable, doesn't depend on which handle is involved — avoids the circular dependency of "use handle positions to decide handle positions."

### Claude's Discretion
- Internal data shape of the autoflip selector (Zustand selector vs `useMemo` vs custom hook) — pick whatever fits cleanly with the current `StreamNode.tsx` rendering path.
- Exact name and location of the autoflip function (e.g. `gui/src/lib/autoflip.ts` vs colocation in `StreamNode.tsx`) — planner decides.
- Validation chip wiring details (which Zustand store slice surfaces the topology hint) — follow Phase 63.1 BC-error precedent.
- Test surface: unit tests for the geometric rules + a small set of representative ReactFlow layouts covering the §3.3 examples (Example 1 X-cross, Examples 3-4 vertical stack, Example 2 long return, the CAC crowded-edge case).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design decisions (LOCKED — re-debate not allowed)
- `.planning/notes/gui-redesign-design-decisions.md` §3.3 — FlowPort autoflip + asymmetric same-side placement. Definitive on rule semantics, what gets fixed, what residuals are acceptable, and what was rejected (per-component rotation, multi-side handles).
- `.planning/notes/gui-redesign-design-decisions.md` §3.4 — Thermal port behavior under autoflip: axis-flip only, aggregated `[1:n]` handle per face, independence from flow ports, crowded-edge edge case.

### Project / milestone state
- `.planning/ROADMAP.md` §"Phase 64: Connection routing" — phase goal text, depends-on Phase 62.
- `.planning/STATE.md` — current working branch is `gui-redesign`; v1.2 milestone active.

### Phase 63.1 anchor work (D-04 consumer)
- `.planning/phases/63.1-bc-architecture-rework-unified-bcs-tab/63.1-CONTEXT.md` — anchor glyph behavior introduced in §"Cosmetic + minor sweep" (Wave 8). Phase 64 must keep anchor glyphs co-located with the autoflipped handle.

### Code touchpoints (read before planning)
- `gui/src/components/StreamNode.tsx:212-288` — current handle render path. FlowPort handles are rendered via `FlowPortHandle`; thermal handles via inline `<Handle>`. Both currently consume `port.side` directly from the registry. This is the primary integration point.
- `gui/src/components/StreamNode.tsx:28-32` — `sideToPosition` mapping from string side → ReactFlow `Position` enum. Reused by the autoflip output.
- `gui/src/registry/components.json` — port definitions. FlowPorts carry `"side"`; thermal pairs already carry `"default_axis"` and `"pair_with"` (lines 116-117 for CAC, 917-918 for HD). The thermal schema is ready; FlowPort axis defaults may need to be added to inform the "no connections yet" registry-default behavior (D-11).
- `gui/src/components/HydraulicEdge.tsx` — custom smoothstep edge with arrowhead. Anti-parallel offset (D-06/D-07/D-08) plugs in here.
- `gui/src/components/CanvasPanel.tsx:40-45` — `edgeTypes` registration and `defaultEdgeOptions = { type: "smoothstep" }`. No change needed; autoflip is a node-side concern.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `sideToPosition` map in `StreamNode.tsx:28-32` — keep using it as the final adapter from autoflip output ("bottom") to ReactFlow `Position.Bottom`.
- `FlowPortHandle` component in `StreamNode.tsx:141-…` — minimal-impact integration point. Replace its `port.side` lookup with `autoflip(nodeId, port.name)`.
- Phase 63.1 validation panel infrastructure (BC error surface) — reused for the D-15 topology-hint validation chip. Same Zustand slice + same render path.
- The registry already carries `"default_axis": "horizontal" | "vertical"` and `"pair_with"` on thermal ports (lines 116-117, 917-918). Phase 64 just needs to consume these.

### Established Patterns
- **Single-handle-per-port invariant** is already preserved by current code — `flowPorts.map(...)` renders exactly one `<FlowPortHandle>` per port. Phase 64 keeps the invariant; only the resolved `side` changes.
- **Layer dimming via `dimFlowHandles` / `dimThermalHandles`** is a pure CSS opacity overlay — confirms D-05 that autoflip's underlying data should ignore layer state.
- **Per-component custom edge types** in `CanvasPanel.tsx:40` — anti-parallel offset (D-06) is implemented inside the existing `HydraulicEdge` component, not as a new edge type.
- **Anchor glyphs** are rendered inside `FlowPortHandle` (the 12-px lucide Anchor placement noted in `StreamNode.tsx:122` comment block). They co-render with the handle, so D-04 (anchor follows handle) is naturally satisfied if we drive both off the same resolved side.

### Integration Points
- **Autoflip function input:** node connection edges (from Zustand store), node positions (from Zustand store / ReactFlow node state).
- **Autoflip function output:** for each (nodeId, portName), a resolved side in {"left", "right", "top", "bottom"}.
- **Consumer surfaces:** `FlowPortHandle` (D-04 covers anchor co-location), thermal `<Handle>` block in `StreamNode.tsx:271-288` (thermal pair axis-flip), and `HydraulicEdge` (anti-parallel offset).
- **Validation chip surface:** Phase 63.1 BC-validation panel — extend with a new "topology hint" message kind (yellow, non-blocking).

</code_context>

<specifics>
## Specific Ideas

- `example_1.png` through `example_5.png` are the canonical "is the visual ugliness gone?" reference set. Plans should verify against these specifically.
- §3.3 "what this fixes" list maps Example 1 → bidirectional X-cross resolution, Examples 3-4 → vertical-stack cascade resolution, Example 2 → long-return through diagonal channel. Each must be visibly improved post-implementation.
- Anti-parallel bow of ±8px is a starting constant — tune by eye during implementation if 8px looks wrong, but no Settings entry.

</specifics>

<deferred>
## Deferred Ideas

- **Per-component rotation override** (right-click → Rotate 90°): explicitly rejected for v1.2 per §3.3. If autoflip turns out to make wrong choices too often in real use, this becomes the explicit manual override and is added in a future phase. Not Phase 64.
- **Manual handle override** (user drags a port to a different side): not in v1.2 scope. Phase 64's "pure derivation, no persistence" decision (D-02) keeps the door open — once persistence is added, manual overrides become a small extension.
- **Distance-proportional anti-parallel bow** (rejected by D-07 in favor of constant): defer to a "fit and finish" phase if real users complain about visual inconsistency between short-distance and long-distance pairs.
- **User-tunable bow amount in Settings panel** (rejected by D-07): defer; no Settings entry in v1.2.
- **10° dead zone / hysteresis for axis switching** (rejected by D-14): defer; add only if live-drag flicker is observed in real use.
- **Thermal handle visual restyle** (yellow rotated diamond → cleaner glyph, mentioned in §3.4): belongs in the design-system phase, not Phase 64.
- **Auto-Layout** (full-graph reflow): not in Phase 64. ReactFlow context menu in Phase 65 has a stubbed "Auto-Layout (future)" entry.

### Reviewed Todos (not folded)
None — no pending todos matched Phase 64 scope.

</deferred>

---

*Phase: 64-Connection-routing*
*Context gathered: 2026-05-14*

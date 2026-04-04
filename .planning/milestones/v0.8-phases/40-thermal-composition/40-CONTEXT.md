# Phase 40: Thermal Composition - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can connect thermal components (ChannelAndContacts, HeatDiffusion, ConstantTemperature) using whole-side ThermalPort handles on the canvas. The code generator detects the wiring topology and emits the appropriate STREAM.jl composition helper call (`symmetric_plate`, `plate`, `one_sided_connection`). No per-cell connections — the GUI operates at the assembly level, not the cell level.

Phase 40 covers:
- THERM-01: ThermalPort handle rendering on ChannelAndContacts (thermal_left, thermal_right — one handle per side)
- THERM-02: HeatDiffusion ThermalPort handle rendering and edge connectivity
- THERM-03: Code generation using composition helpers with pattern detection

Phase 41 (next sequential phase) will add the layered canvas (hydraulic/thermal layer toggling).

</domain>

<decisions>
## Implementation Decisions

### ThermalPort Handle Rendering
- **D-01:** Each ThermalPort is rendered as **one handle per side** — not one handle per cell. `thermal_left` and `thermal_right` each appear as a single handle on the node regardless of `n` (for ChannelAndContacts) or `nz` (for HeatDiffusion). The GUI abstracts away the per-cell detail.
- **D-02:** ChannelAndContacts: `thermal_left` handle on top edge, `thermal_right` handle on bottom edge (matching registry `side` values: top/bottom). HeatDiffusion: `thermal_left` handle on left edge, `thermal_right` handle on right edge (matching registry `side` values: left/right). ConstantTemperature: single `thermal` handle on left edge.
- **D-03:** ThermalPort handles are visually distinct from FlowPort handles — amber color (`#f59e0b`, matching the Thermal category color) to distinguish them from FlowPort handles. ThermalPort edges also render in amber.
- **D-04:** The `array: true` field in the registry is used only by the **code generator** to know that helpers are needed. The renderer ignores it for handle count — always one handle per ThermalPort entry.

### Connection Type Enforcement
- **D-05:** ReactFlow `isValidConnection` callback enforces port type matching: FlowPort handles only connect to FlowPort handles, ThermalPort handles only connect to ThermalPort handles. Cross-type connections are blocked at draw time — the edge simply cannot be dropped.
- **D-06:** Port type is derived from the registry `type` field for each port. The handle `data` attribute carries `portType: "FlowPort" | "ThermalPort"` so `isValidConnection` can compare without a registry lookup.

### Code Generation — Pattern Detection
- **D-07:** The code generator detects the thermal wiring topology from the edges array and emits the correct STREAM.jl helper. Detection rules (based on which ThermalPort handles of which component types are connected):
  - **symmetric_plate**: One ChannelAndContacts with BOTH `thermal_left` AND `thermal_right` wired to the same HeatDiffusion's `thermal_right` and `thermal_left` respectively → `symmetric_plate(cac, fuel; name=:assembly)`
  - **plate**: Two ChannelAndContacts each wired to one side of the same HeatDiffusion → `plate(ch_left, ch_right, fuel; name=:assembly)`
  - **one_sided_connection**: One ChannelAndContacts wired to ONE side of a HeatDiffusion → `one_sided_connection(channel, fuel; side=:left/:right, name=:assembly)`
  - **ConstantTemperature**: Wired to any ThermalPort → `connect(ct.thermal, port(cac, :thermal_left, i))` emitted inside the thermal assembly's `eqs` (or inside the helper's equations if applicable)
- **D-08:** When a thermal assembly helper is detected, the generated code structure uses:
  ```julia
  # Thermal assembly (auto-detected: symmetric_plate)
  @named assembly = symmetric_plate(cac_1, fuel_1)

  # Full system
  eqs = [
      connect(pump_1.port_out, assembly.cac_1.port_in),
      pump_1.port_in.P ~ 1.0e5,
  ]
  @named sys = compose_systems(assembly; connections=eqs, name=:sys)
  ssys = mtkcompile(sys)
  ```
  Hydraulic FlowPort `connect()` calls that reference the CAC (which is now a subsystem of `assembly`) use the `assembly.cac_1.port_in` path.
- **D-09:** If no thermal edges exist in the canvas, the code generator falls back to the Phase 36 format: `ODESystem(eqs, t; systems=[...])`. The helper-based format is only emitted when thermal topology is detected.
- **D-10:** If the thermal wiring doesn't match any known helper pattern (partial/ambiguous connections), emit raw `connect(port(...))` calls with a `# TODO: verify thermal wiring` comment, and do NOT emit a helper call.

### Thermal Topology Validation
- **D-11:** No new VALD rules added for ThermalPorts. Unconnected ThermalPorts are valid STREAM.jl (adiabatic default). The Phase 39 VALD checks (FlowPort only) are unchanged.
- **D-12:** ThermalPort connections are NOT included in the Phase 39 VALD-01 "unconnected mandatory FlowPort" check. The `isConnected` check in the topology validator remains FlowPort-scoped.

### Claude's Discretion
- Exact amber shade for ThermalPort handles and edges (should visually harmonize with the amber-500 category border)
- Whether thermal edges have a dashed vs solid style to distinguish from FlowPort edges
- ReactFlow handle shape for ThermalPort (circle vs diamond — both are supported)
- Assembly naming convention when multiple thermal assemblies exist (`assembly_1`, `assembly_2`, or derived from component names)
- Error behavior when `nz` (HeatDiffusion) ≠ `n` (ChannelAndContacts) — code gen can emit a `# NOTE: nz must equal n for this helper` comment

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §"v0.8 Requirements" → THERM-01, THERM-02, THERM-03 — Exact acceptance criteria

### Roadmap
- `.planning/ROADMAP.md` §"Phase 40: Thermal Composition" — Goal, success criteria, depends-on Phase 36 + Phase 34

### STREAM.jl composition helpers (source of truth for emitted code)
- `src/composition/helpers.jl` — `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems` implementations + docstrings; exact Julia function signatures and wiring conventions
- `CLAUDE.md` §"Component authoring conventions" — positional vs keyword argument rules for generated `@named` declarations

### Registry (thermal port definitions)
- `gui/src/registry/components.json` — `ports[]` for ChannelAndContacts (thermal_left/right, array=true, arrayParam=n), HeatDiffusion (thermal_left/right, array=true, arrayParam=nz), ConstantTemperature (thermal, single)
- `gui/src/registry/types.ts` — `Port` interface with `type`, `side`, `array`, `arrayParam` fields

### Existing GUI code (read before editing)
- `gui/src/components/StreamNode.tsx` — Current handle rendering (FlowPort only); add ThermalPort handles here following the same Handle pattern; add `portType` to handle data
- `gui/src/lib/codeGenerator.ts` — Phase 36 code gen; extend with thermal pattern detection and helper emission
- `gui/src/store/useStore.ts` — `edges` array (sourceHandle/targetHandle carry port names); no store changes needed for thermal edges
- `gui/src/components/CanvasPanel.tsx` — `isValidConnection` prop on ReactFlow; add port-type enforcement here

### Prior phase context
- `.planning/phases/36-code-generation/36-CONTEXT.md` — D-04: thermal BCs explicitly deferred to Phase 40; D-06/D-07: existing code gen output format (ODESystem idiom)
- `.planning/phases/34-canvas-node-editor/34-CONTEXT.md` — D-06: directionality enforcement pattern for FlowPorts (same pattern extended to ThermalPort type enforcement)
- `.planning/phases/39-topology-validation/39-CONTEXT.md` — D-10: ThermalPorts explicitly excluded from VALD-01; D-05: error ring pattern (not reused for thermal)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/StreamNode.tsx`: Current `flowPorts.map(port => <Handle .../>)` pattern. Phase 40 adds a parallel `thermalPorts.map(port => <Handle .../>)` section using the same ReactFlow `Handle` component with amber color styling.
- `gui/src/registry/components.json`: ThermalPort entries already present with `array: true` and `arrayParam`. Renderer ignores array/arrayParam (single handle); code gen reads them to know helpers are needed.
- `gui/src/lib/codeGenerator.ts`: Existing `connect()` emission at line ~332 uses `instanceName.portName`. Thermal assembly code gen adds a pre-pass: group thermal edges by HD node, classify topology, emit helper declarations before the hydraulic `eqs = [...]` block.
- `gui/src/components/CanvasPanel.tsx` or wherever `<ReactFlow>` is mounted: `isValidConnection` prop needs to be added. It receives `connection` object with `sourceHandle` and `targetHandle` — check their `portType` data attribute.

### Established Patterns
- Registry-driven rendering: all handle rendering reads registry JSON. ThermalPort handles follow the same pattern — filter `component.ports` by `type === "ThermalPort"`, map to `<Handle>` components.
- Edge source/target directionality: currently `port.name.includes("out")` → source. ThermalPorts are bidirectional (acausal) — both `thermal_left` and `thermal_right` should be `type="source"` on the ReactFlow handle (or use `type="target"` — in practice for acausal ports it doesn't matter; pick one consistently).
- shadcn/ui + Tailwind design tokens: amber-500 (`#f59e0b`) already used as Thermal category color. Reuse this for ThermalPort handle fill color.

### Integration Points
- `StreamNode.tsx`: split `component.ports` into `flowPorts` and `thermalPorts`. Render FlowPorts as before. Render ThermalPorts with amber color.
- `codeGenerator.ts`: add a `detectThermalTopology(nodes, edges)` function that returns a list of thermal assembly descriptors `{ type: "symmetric_plate" | "plate" | "one_sided_connection", components: [...] }`. Main generator uses these descriptors to emit helper declarations and adjust the top-level `compose_systems()` call.
- `CanvasPanel.tsx`: `isValidConnection` — look up handle portType from node data or a lightweight registry lookup. Return false if source portType ≠ target portType.

</code_context>

<specifics>
## Specific Ideas

- "I want this GUI to ONLY allow connecting a whole side of a channel/plate to the whole side of a plate/channel — no per-cell connecting." — Single handle per ThermalPort side, assembly-level abstraction.
- The `n` / `nz` parameter is invisible to the user in the GUI — it lives inside the Julia helper. The helper manages the per-cell loop.
- Layered canvas (hydraulic layer / thermal layer with foreground/background toggling) explicitly deferred to **Phase 41** (next sequential phase). This is a confirmed follow-on, not a maybe.

</specifics>

<deferred>
## Deferred Ideas

- **Layered canvas (Phase 41)** — Hydraulic and thermal layers with visibility toggling; hydraulic components in foreground when working on hydraulics, thermal components in foreground when wiring heat paths. Multi-layer components (ChannelAndContacts) appear in both layers. This is the confirmed next phase after Phase 40.
- **Per-cell ThermalPort connections** — Individual `thermal_left[i]` handles for fine-grained cell-level wiring (e.g., connecting multiple channels to one big plate at different axial positions). Out of scope for Phase 40; revisit if multi-channel-per-plate topologies are needed.

</deferred>

---

*Phase: 40-thermal-composition*
*Context gathered: 2026-04-03*

# Phase 40: Thermal Composition - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-03
**Phase:** 40-thermal-composition
**Areas discussed:** Array port layout, Code gen output structure, Connection type enforcement, Thermal topology validation

---

## Array Port Layout

| Option | Description | Selected |
|--------|-------------|----------|
| n handles per side (per-cell) | One handle per axial cell; n=4 → 4 dots on top, 4 on bottom | |
| One handle per side (whole-side) | Single handle for thermal_left, single for thermal_right | ✓ |

**User's choice:** Whole-side connections only — "I want this GUI to ONLY allow connecting a whole side of a channel/plate to the whole side of a plate/channel. There is no need for per-cell connecting."

**Notes:** The user clarified the physics after seeing the per-cell question: the GUI should abstract at the assembly level, not cell level. `n` and `nz` are invisible to the user — they live inside the Julia helpers. The `array: true` flag in the registry is used by the code generator only. Handle ID format question (underscore vs bracket) became moot with this decision.

---

## Code Gen Output Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Helper calls replace manual connects | Detect topology, emit `symmetric_plate`/`plate`/`one_sided_connection` with `compose_systems()` | ✓ |
| Always raw connect(port(...)) | Verbose per-cell connects in existing eqs=[] block | |

**User's choice:** Helper calls with pattern detection.

**Notes:** When thermal wiring is present, the code gen switches from `ODESystem(eqs, t; systems=[...])` to `compose_systems(assembly; connections=eqs, name=:sys)`. Hydraulic connects that reference CAC nodes use the `assembly.cac_1.inlet` path. Fallback to raw connects with `# TODO` comment when pattern is ambiguous.

---

## Connection Type Enforcement

| Option | Description | Selected |
|--------|-------------|----------|
| Enforce type matching (isValidConnection) | FlowPort ↔ FlowPort only; ThermalPort ↔ ThermalPort only | ✓ |
| No enforcement | Any handle connects to any other | |

**User's choice:** Yes, enforce. Cross-type connections blocked at draw time.

---

## Thermal Topology Validation

| Option | Description | Selected |
|--------|-------------|----------|
| No new VALD rules (ThermalPorts optional) | Unconnected ThermalPorts are adiabatic by default — valid STREAM.jl | ✓ |
| Warn if HeatDiffusion has no thermal connections | Isolated HeatDiffusion is useless | |

**User's choice:** No new validation. ThermalPorts are optional.

---

## Deferred Ideas

- **Layered canvas** — Hydraulic/thermal layer toggling with foreground/background visibility. Promoted to **Phase 41** (next sequential phase after Phase 40). Confirmed follow-on, not a maybe.
- **Per-cell ThermalPort connections** — Individual cell-level handles for multi-channel-per-plate topologies. Deferred indefinitely.

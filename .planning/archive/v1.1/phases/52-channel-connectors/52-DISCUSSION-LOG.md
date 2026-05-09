# Phase 52: Channel Connectors - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in `52-CONTEXT.md` — this log preserves the alternatives considered.

**Date:** 2026-05-05
**Phase:** 52-Channel Connectors
**Areas discussed:** Adiabatic-default mechanism, Q_flow semantics & sign convention, Phase 52 test scaffolding, instream() smoke compose target

---

## Adiabatic-default mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| A — h=0 default in WallPort (spike's approach) | Defaults `h=0`, `T_wall=300`. Channel writes plain `q[i] = h·(T_wall - T[i])`; unconnected port ⇒ h=0 (IC) ⇒ q=0. Simplest. | ✓ |
| B — Channel-side ifelse fallback | `q[i] = ifelse(h>0, h·(T_wall-T[i]), 0)`. Belt-and-suspenders; one ifelse per cell per side. | |
| C — Make h a Stream variable | `[connect = Stream]` for h; unconnected stream uses connector default expression. Cleaner contract but introduces stream semantics where Modelica idiom is across. | |

**User's first response:** Asked if `T_wall=nothing` (sentinel) could be used to detect unconnected ports and set `T_wall = T[i]` in the channel — capturing both factors as zero (h=0 AND T_wall-T[i]=0).

**Clarification given:** MTK connector defaults must be numeric ICs (no `nothing`/sentinel), and there is no compile-time `isconnected()` exposed at the component level — connection determination happens during `compose()` + `mtkcompile()` structural analysis. Closest equivalents: ifelse-on-h (Option B), or an explicit numeric sentinel like `-1e30` in `T_wall` (fragile — any real driver overwrites it). Re-presented options.

**User's choice:** A — Spike's path, rely on h=0 IC alone.

**Notes:** The spike's approach is proven; T_wall stays at IC 300 when unconnected but is multiplied by h=0 in the channel equation, so the value is harmless. Avoids runtime branches.

---

## Q_flow semantics & sign convention

| Option | Description | Selected |
|--------|-------------|----------|
| Match ThermalPort — Q_flow [W], positive = into channel | WallPort.Q_flow and HeatFluxPort.Q_flow per-cell power [W], positive = heat into channel; q_flux on HeatFluxPort is W/m². | ✓ |
| Q_flow as the only semantic on HeatFluxPort (drop q_flux) | Skip q_flux entirely. Loses intensive (W/m²) interface that Python STREAM uses. | |
| Other — different sign or units | E.g., positive = out of channel, kW/m², or split q_flux per side. | |

**User's choice:** Match ThermalPort — Q_flow [W], positive = into channel.

**Notes:** Keeps composition consistent with `ChannelAndContacts`'s legacy `ThermalPort` arrays (CONN-03 unchanged). Anything connected to a `WallPort` or `HeatFluxPort` deposits power into the channel via the same sign convention as legacy thermal-driven components.

---

## Phase 52 test scaffolding

| Option | Description | Selected |
|--------|-------------|----------|
| A — Inline test stubs in test_connectors.jl | Tiny `_StubRecipient` + `_StubWallDriver` (and `_StubFluxDriver`) defined inside the test file, underscore-prefixed, not exported. Matches existing test-file pattern. | ✓ |
| B — Promote spike's ChannelScalar/ScalarWalls into fixtures | Reuse validated spike code as test fixtures. Less work but inherits exploratory structure. | |
| C — Structural-only tests, defer compose+solve to Phase 54 | Phase 52 only asserts variable annotations and MTK metadata; full compose verification waits for real variants in Phase 54. | |
| Other / mix | E.g., A + small dedicated fixture file at `src/test_fixtures/`. | |

**User's choice:** A — Inline test stubs in test_connectors.jl.

**Notes:** Self-contained, no public API surface, no spike-code promotion. Stubs mirror the eventual Channel/ChannelHeatFlux interface so the tests double as a contract for Phase 54.

---

## instream() smoke compose target

| Option | Description | Selected |
|--------|-------------|----------|
| 2 — Tiny pump→stub→pump loop with brief solve | Closed loop: `Pump(mdot0=...)` → `_StubRecipient` (FlowPort + WallPort/HeatFluxPort arrays) → back to pump, pressure anchor; brief `solve_transient`. Asserts no MTK stream-connection warnings AND finite numerics. | ✓ |
| 1 — Structural-only mtkcompile, no solve | Cheaper but doesn't reproduce the spike's integration-time failure mode. | |
| 3 — Substitute stub into a full mini build_loop | Most realistic but pulls in Friction, Resistor, etc. — overkill. | |

**User's choice:** 2 — Tiny pump→stub→pump loop with brief solve.

**Notes:** The spike's vector-form failure surfaced at integration time (raw `sol.u`), not at `mtkcompile`. A structural-only test would have missed it; this smoke test is the regression guard for the array-of-scalar choice.

---

## Claude's Discretion

None — every gray area presented was explicitly resolved by the user.

## Deferred Ideas

- Variant rewrites of `Channel` and `ChannelHeatFlux` against the new connectors → Phase 54
- `_channel_core` extraction & enthalpy-form energy balance → Phase 53
- Composition-helper updates for new connector types → Phase 55
- Cross-validation vs Python STREAM under new convective scheme → Phase 56 (milestone gate)
- Upstream MTK bug report for the vector-form connector mis-integration → out of v1.1 scope; revisit only if it blocks Phase 54

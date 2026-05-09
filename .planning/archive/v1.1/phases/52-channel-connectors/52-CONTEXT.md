# Phase 52: Channel Connectors - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Define and ship two new MTK acausal connector types — `WallPort` (carrying `T_wall`, `h`, `Q_flow`) and `HeatFluxPort` (carrying `q_flux`, `Q_flow`) — used as **arrays of scalar connectors per side per channel** (matching the existing `ChannelAndContacts` `thermal_left[1:n]` / `thermal_right[1:n]` pattern). Plus standalone unit tests that exercise variable annotations, `connect()` behaviour, adiabatic/zero-flux defaults, and `instream()` interplay with `FlowPort`.

This phase ships **connectors only**. The actual variant rewrites of `Channel` and `ChannelHeatFlux` happen in Phase 54; `ChannelAndContacts` keeps its existing `ThermalPort` arrays (CONN-03 — no connector change). The contract established here is what Phase 54 will build against.

</domain>

<decisions>
## Implementation Decisions

### Connector pattern (carry-forward — locked by spike on 2026-05-05)
- **D-01:** Pattern is **array of scalar connectors per side**, NOT vector-form connectors carrying array variables. Vector form was investigated via spike (`/tmp/vec_diagnose3.jl` and earlier iterations) and rejected: vector connectors mis-integrate the first unknown of the vector system whenever scalar-port systems (e.g. `FlowPort`) coexist in the same compiled session, which is unavoidable in any realistic `build_loop`. The bug appears in raw `sol.u`, so it's an integration-level issue, not just symbolic introspection. Array-of-scalar is proven safe in the spike and matches the `ChannelAndContacts` `thermal_left[1:n]` / `thermal_right[1:n]` precedent.

### Connector definitions
- **D-02:** `WallPort` carries three scalar variables: `T_wall(t)` (across, K), `h(t)` (across, W/m²·K), `Q_flow(t)` `[connect = Flow]` (W). Used by `Channel` as arrays `thermal_left[1:n]`, `thermal_right[1:n]` (Phase 54 will rebuild `Channel` against this).
- **D-03:** `HeatFluxPort` carries two scalar variables: `q_flux(t)` (across, W/m²), `Q_flow(t)` `[connect = Flow]` (W). Used by `ChannelHeatFlux` as arrays `thermal_left[1:n]`, `thermal_right[1:n]` (Phase 54).
- **D-04:** Both connectors live in `src/connectors.jl` alongside `FlowPort`/`ThermalPort` and are exported from `src/STREAM.jl` next to those.
- **D-05:** `ChannelAndContacts` keeps its existing `ThermalPort` arrays unchanged (CONN-03). No connector change — only verification that it composes cleanly with the refactored variants in later phases.

### Adiabatic / zero-flux defaults (Area 1)
- **D-06:** Adiabatic-when-unconnected is achieved by **IC defaults alone** — no `ifelse` guard in the channel equations. `WallPort` defaults `h = 0.0`, `T_wall = 300.0`. `HeatFluxPort` defaults `q_flux = 0.0`. `Q_flow = 0.0` (auto-zero'd by MTK's Flow rule when unconnected). Channel-side equations are written plainly:
  - For `Channel` (Phase 54): `port.Q_flow ~ port.h · heated_part · dz · (port.T_wall - T[i])`. Unconnected ⇒ `h = 0` (IC) ⇒ `Q_flow = 0`. `T_wall` stays at IC 300.0 but is multiplied by 0, so harmless.
  - For `ChannelHeatFlux` (Phase 54): `port.Q_flow ~ port.q_flux · heated_part · dz`. Unconnected ⇒ `q_flux = 0` ⇒ `Q_flow = 0`.
- **D-07:** *Why no `ifelse(h>0, ..., 0)` guard*: MTK doesn't expose a compile-time `isconnected()` at the component level, and the spike validated that the IC-default path works without runtime branches. Belt-and-suspenders ifelse adds one branch per cell per side for no observed benefit. Discarded **option B (ifelse-on-h)** and **option C (sentinel `T_wall`)** explicitly.

### `Q_flow` semantics & sign convention (Area 2)
- **D-08:** `Q_flow` matches the existing `ThermalPort` convention exactly:
  - Units: `[W]` (per-cell power, not flux density)
  - Annotation: `[connect = Flow]`
  - Sign: **positive = heat into the channel** from this wall side (= heat leaving the external wall driver)
- **D-09:** `q_flux` on `HeatFluxPort` is in **W/m²** (intensive heat flux density). The `ChannelHeatFlux` energy balance multiplies by `heated_part · dz` to get per-cell power. This is the intensive interface that matches Python STREAM's heat-flux BC.
- **D-10:** Symmetric treatment across the two connectors keeps composition consistent — anything connected to a `WallPort` or `HeatFluxPort` deposits power into the channel via the same sign convention as legacy `ThermalPort`-driven components.

### Test scaffolding (Area 3)
- **D-11:** Phase 52 unit tests live in `test/test_connectors.jl` (existing file, extending the FlowPort/ThermalPort coverage). Exercise the new connectors with **inline test stubs** defined inside the test file, underscore-prefixed and not exported:
  - `_StubRecipient(; n, port_type=:wall)` — has `port_in`/`port_out` `FlowPort`, `WallPort`-or-`HeatFluxPort` arrays `thermal_left[1:n]` / `thermal_right[1:n]`, an `(T(t))[1:n]` state, and a trivial energy balance like `Dt(T[i]) ~ (thermal_left[i].Q_flow + thermal_right[i].Q_flow) / m_cp`. Mirrors the eventual Channel/ChannelHeatFlux interface so the tests double as a contract for Phase 54.
  - `_StubWallDriver(; n, T_w, h_v)` — provides a `WallPort` array and equations `port[i].T_wall ~ T_w[i]`, `port[i].h ~ h_v[i]`. Used to drive both faces in the connected case.
  - `_StubFluxDriver(; n, q_v)` — analog for `HeatFluxPort`: `port[i].q_flux ~ q_v[i]`.
- **D-12:** *Why inline stubs*: matches the existing `test_connectors.jl` pattern (FlowPort/ThermalPort already use inline mini-systems for connect tests); keeps fixtures local to Phase 52 (no public API surface); explicitly does NOT promote the `/tmp/vec_diagnose3.jl` spike scaffolding (exploratory shape, written to a tempdir).
- **D-13:** Test coverage targets the four sub-criteria of CONN-04 explicitly — variable annotations (structural inspection), `connect()` produces well-formed equations (compose two stubs and check), adiabatic/zero-flux default (compose one stub alone, solve, assert state stays put), `instream()` interplay (Area 4 below).

### `instream()` smoke compose target (Area 4)
- **D-14:** Smoke test for success criterion #3 is a **tiny pump→stub→pump closed loop**:
  - `Pump(mdot0=0.5)` (existing fixed-flow Pump)
  - `_StubRecipient` with `n=2` (FlowPort + WallPort or HeatFluxPort arrays present together)
  - `port_out` of stub connected back to `Pump.port_in`
  - Pressure anchor on `pump.port_in.P ~ 1.0e5` (per the multi-branch network rule, even though this is a series loop the anchor doesn't hurt)
  - Brief `solve_transient(t = 0.0..0.1)`
  - Assertions: (a) `mtkcompile` and solve produce **no MTK warnings about unset stream connections** (capture warnings via `Test.@test_logs` or similar); (b) all unknowns finite at the final time; (c) for the unconnected-WallPort variant of the stub, `T[i]` stays adiabatic (matches initial condition).
- **D-15:** *Why an actual solve and not a structural-only test*: the spike's vector-form failure manifested at integration time (raw `sol.u` mis-integrating), not at `mtkcompile`. A structural-only test would have failed to catch the bug the spike found, so the smoke test must reproduce that failure mode if it ever returns. Discarded options 1 (structural-only) and 3 (full mini-build_loop substitution) explicitly — option 1 is too weak, option 3 pulls in `Friction`/`Resistor`/etc. for a connector smoke test.

### Out-of-scope here (deferred to other phases)
- **D-16:** Variant rewrites of `Channel` and `ChannelHeatFlux` against `WallPort` / `HeatFluxPort` belong to Phase 54. Phase 52 only ships connectors and isolated tests.
- **D-17:** No changes to `_channel_base_eqs`, energy-balance scheme, or `_channel_core` extraction in Phase 52 — those are Phase 53 work.
- **D-18:** No changes to `composition/helpers.jl` (`symmetric_plate` / `plate` / `one_sided_connection`) in Phase 52 — these are unchanged because `ChannelAndContacts` (the only consumer of these helpers in v1.1's transition window) keeps its `ThermalPort` arrays. Phase 55 updates the helpers to also accept the new connector types when Phase 54 has rebuilt the variants.
- **D-19:** No commits to `main` during this phase. All work lands on branch `channels-redesign` and ships as a single PR at the milestone close (Phase 56).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 52: Channel Connectors" — phase goal, dependencies, success criteria (4 specific TRUE statements)
- `.planning/REQUIREMENTS.md` §"Connectors" — CONN-01, CONN-02, CONN-03, CONN-04 with the locked decision that connectors are scalar instantiated as arrays per side
- `.planning/PROJECT.md` §"Current Milestone: v1.1 Final Channel-Family Redesign" — milestone goal, target features, constraints

### Prior decisions to honour
- `.planning/STATE.md` §"Key Decisions (carry-forward)" — the v1.1 CONN spike entry (2026-05-05) documenting why vector-form connectors were rejected; v1.1 phasing rationale
- `CLAUDE.md` §"File Structure Standard" — `src/connectors.jl` is the canonical location; exports go in `src/STREAM.jl` only
- `CLAUDE.md` §"Component authoring conventions" — `name` always keyword-only; underscore-prefixed internal helpers; docstrings with `# Arguments` / `# Returns` for every exported symbol
- `CLAUDE.md` §"MTK Patterns" — `@register_symbolic` for opaque fluid functions; `ifelse()` (not `if`/`else`) for any conditional inside MTK equations; `mtkcompile` before solve

### Existing code (read before extending)
- `src/connectors.jl` — current `FlowPort` and `ThermalPort` definitions; the across/flow-variable pattern, descriptions, and IC-default style to mirror exactly
- `src/components/thermal_channel.jl` §`ChannelAndContacts` — current `ThermalPort` array usage (`thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]`) and how `Q_flow ~ h_tc · heated_part · dz · (T_wall - T)` is expressed; this is the precedent for `WallPort` per-cell wiring
- `src/components/thermal_channel.jl` §`ChannelHeatFlux` — current scalar `T_wall_p` parameter and per-cell `q_wall[i]` computation; the `q_flux`-based replacement in Phase 54 will mirror its energy-balance shape
- `src/components/channel.jl` §`Channel` — current scalar `ThermalPort` and `instream(port_in.T)` upstream-temperature selection; this is what the smoke compose target must continue to support without warnings
- `src/composition/helpers.jl` — `symmetric_plate`, `plate`, `one_sided_connection`, `port(sys, face, i)` access pattern for `connect()` of indexed thermal-port arrays; **NOT modified in Phase 52**, but the test fixtures wire stubs in the same array-of-port shape these helpers expect
- `src/STREAM.jl` — current export list and `include()` order; `WallPort` and `HeatFluxPort` are added to the same `export FlowPort, ThermalPort` line (or directly after)

### Test references
- `test/test_connectors.jl` — existing test patterns for FlowPort/ThermalPort that the new connector tests should follow
- `test/runtests.jl` — orchestrator inclusion; no change expected (`test_connectors.jl` already wired in)

### Spike artefacts (read for the rejected vector-form context, not as code to reuse)
- `/tmp/vec_diagnose3.jl` — final spike showing array-of-scalar `ScalarPort`+`ChannelScalar` works while vector-form `VecWallPort`+`ChannelVec` mis-integrates the first unknown when paired with `FlowPort`-style scalar systems. **Treat as referenced only — do NOT promote into the test suite.**

### External reference (validation gate)
- `/home/itayb/projects/STREAM/stream/calculations/channel.py` — Python STREAM channel translation reference. Phase 52 doesn't touch energy balance, but the connector contract is defined so that Phase 53/54's enthalpy-form rewrite can match Python intent without further connector changes.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`@connector function` macro pattern** (`src/connectors.jl`): existing `FlowPort` and `ThermalPort` use this exact form. New connectors copy the structure: keyword-only `name`, scalar `@variables` with IC defaults and `description` metadata, `[connect = Flow]` on the through variable, empty equations vector, `System(Equation[], t, sts, []; name=name)` body. Mirror exactly — do not improvise.
- **Inline test-stub pattern** (`test/test_connectors.jl`): the file already builds tiny ad-hoc systems to test FlowPort/ThermalPort behaviour. New tests follow the same shape — define `_StubRecipient` / `_StubWallDriver` / `_StubFluxDriver` inline, underscore-prefixed, not exported.
- **`port(sys, face, i)` accessor** (`src/composition/helpers.jl:28`): the canonical way to address indexed connector array elements in `connect()` calls. Tests for `_StubRecipient` use this same accessor.
- **`Pump(mdot0=…)` fixed-flow constructor** (`src/components/pump.jl`): used as the FlowPort source in the smoke compose target. Combined with a pressure anchor `pump.port_in.P ~ 1.0e5` it gives a self-contained closed loop without any other component dependencies.

### Established Patterns
- **Scalar across + Flow through, IC-default adiabatic** — the contract pattern from `ThermalPort`. New connectors extend it (more across variables: `T_wall + h` or `q_flux`) but keep one Flow variable (`Q_flow`) per connector.
- **Array of named scalar ports per side** — `[ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]` is how CAC builds dual-face arrays. New `Channel` and `ChannelHeatFlux` (Phase 54) will instantiate `WallPort` / `HeatFluxPort` the same way.
- **`compose(System(...), port_in, port_out, thermal_left..., thermal_right...)`** — the canonical compose call shape for components with port arrays. Stubs in Phase 52 tests follow the same structure.
- **`instream()` for FlowPort upstream temperature** — used in `Channel` and `ChannelHeatFlux` for `T_inlet_fwd = instream(port_in.T)`. The smoke compose target verifies this still works alongside `WallPort` arrays in the same compiled system.

### Integration Points
- **`src/STREAM.jl` includes order** is unchanged: `connectors.jl` is included before any component file, so `WallPort` / `HeatFluxPort` are available to Phase 54's variant rewrites without further plumbing.
- **Export line** in `src/STREAM.jl` adds two names alongside `FlowPort, ThermalPort`. No new export categories.
- **Test file mirroring** (CLAUDE.md test placement rule): connectors → `test_connectors.jl`. New tests append to this file rather than creating a new file.

</code_context>

<specifics>
## Specific Ideas

- The user's instinct on Area 1 was a "T_wall=nothing" sentinel that the channel could detect to set `T_wall = T[i]`. Explicitly discussed and discarded: MTK connector defaults must be numeric ICs (no `nothing`/sentinel), and there is no compile-time `isconnected()` exposed at the component level — connection determination happens during `compose()` + `mtkcompile()` structural analysis. The chosen IC-default mechanism (`h=0` ⇒ `q=0` regardless of `T_wall`) captures the *spirit* of the request without runtime branches or fragile sentinels.
- The smoke compose target was chosen specifically to reproduce the spike's failure mode (integration-time mis-integration of the first vector unknown) at minimum cost, so a regression in the array-of-scalar contract would surface as a test failure rather than silently making it to merge.
- Test stubs are intentionally NOT promoted from the `/tmp/vec_diagnose3.jl` spike code, even though the shape is similar. Spike artifacts are exploratory; production tests deserve clean, minimal stubs written from scratch and named explicitly.

</specifics>

<deferred>
## Deferred Ideas

- **Variant rewrites against the new connectors** — Phase 54 (`Channel` rebuilt as a passive recipient, `ChannelHeatFlux` rebuilt around `q_flux`-driven boundary, `ChannelAndContacts` rebuilt on `_channel_core`).
- **`_channel_core` extraction & enthalpy-form energy balance** — Phase 53.
- **Composition-helper updates** for the new connector types (`symmetric_plate` / `plate` / `one_sided_connection` accepting `WallPort` arrays where today they expect `ThermalPort`) — Phase 55 (along with `test_channel.jl` rewrite and shipped-builder smoke tests).
- **Cross-validation against Python STREAM** under the new convective scheme — Phase 56 (milestone gate).
- **MTK upstream report for the vector-form connector bug** — out of v1.1 scope; the spike write-up in `STATE.md` is sufficient for now. If the bug becomes a blocker for any Phase 54 design tension, file with MTK at that point.

</deferred>

---

*Phase: 52-Channel Connectors*
*Context gathered: 2026-05-05*

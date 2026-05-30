# Phase 52: Channel Connectors - Research

**Researched:** 2026-05-05
**Domain:** ModelingToolkit v11 acausal connectors for thermal-hydraulic systems (STREAM.jl)
**Confidence:** HIGH (all critical claims verified against in-tree code; spike artifact + STATE.md decisions are authoritative)

## Summary

Phase 52 ships **two new MTK acausal connector types** — `WallPort` (carrying `T_wall`, `h`, `Q_flow`) and `HeatFluxPort` (carrying `q_flux`, `Q_flow`) — used as **arrays of scalar connectors per side per channel** matching the existing `ChannelAndContacts` `thermal_left[1:n]`/`thermal_right[1:n]` pattern. Both connectors live in `src/connectors.jl` next to `FlowPort`/`ThermalPort`, are exported from `src/STREAM.jl`, and rely on **IC-default adiabatic semantics alone** (`h=0` ⇒ `Q_flow=0` even with `T_wall=300`; `q_flux=0` ⇒ `Q_flow=0`) — no `ifelse` guards, no compile-time `isconnected()` probes, no sentinel values.

Tests live in `test/test_connectors.jl` and follow the existing inline-stub idiom — no new fixture file, no exported helpers, just three underscore-prefixed local recipients/drivers (`_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`) that mirror the eventual `Channel`/`ChannelHeatFlux` interface. The phase is **connectors-only**: no `Channel`/`ChannelHeatFlux` rewrites (those are Phase 54), no `_channel_core` extraction (Phase 53), no helper updates (Phase 55).

The single highest-risk landmine is the rejected vector-form path: a focused spike (`/tmp/vec_diagnose3.jl`) showed that vector-carrying connectors mis-integrate the **first unknown** of the vector system whenever any `FlowPort`-style scalar-port system coexists in the same compiled session — which is unavoidable in any realistic loop. Phase 52's smoke-compose target (D-14: tiny pump→stub→pump closed loop with brief `solve_transient`) exists specifically to catch that failure mode at integration time, since the bug appears in raw `sol.u` and a structural-only test would miss it.

**Primary recommendation:** Mirror `ThermalPort`'s body almost verbatim, swapping the variable list. Default `T_wall=300.0`, `h=0.0`, `q_flux=0.0`, `Q_flow=0.0` numerically. Keep `name` keyword-only. Export alongside `FlowPort, ThermalPort` on line 28 of `src/STREAM.jl`. Use the `_StubRecipient`-driven smoke loop as the integration-time canary.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Connector pattern (carry-forward — locked by spike on 2026-05-05)
- **D-01:** Pattern is **array of scalar connectors per side**, NOT vector-form connectors carrying array variables. Vector form was investigated via spike (`/tmp/vec_diagnose3.jl` and earlier iterations) and rejected: vector connectors mis-integrate the first unknown of the vector system whenever scalar-port systems (e.g. `FlowPort`) coexist in the same compiled session, which is unavoidable in any realistic `build_loop`. The bug appears in raw `sol.u`, so it's an integration-level issue, not just symbolic introspection. Array-of-scalar is proven safe in the spike and matches the `ChannelAndContacts` `thermal_left[1:n]` / `thermal_right[1:n]` precedent.

#### Connector definitions
- **D-02:** `WallPort` carries three scalar variables: `T_wall(t)` (across, K), `h(t)` (across, W/m²·K), `Q_flow(t)` `[connect = Flow]` (W). Used by `Channel` as arrays `thermal_left[1:n]`, `thermal_right[1:n]` (Phase 54 will rebuild `Channel` against this).
- **D-03:** `HeatFluxPort` carries two scalar variables: `q_flux(t)` (across, W/m²), `Q_flow(t)` `[connect = Flow]` (W). Used by `ChannelHeatFlux` as arrays `thermal_left[1:n]`, `thermal_right[1:n]` (Phase 54).
- **D-04:** Both connectors live in `src/connectors.jl` alongside `FlowPort`/`ThermalPort` and are exported from `src/STREAM.jl` next to those.
- **D-05:** `ChannelAndContacts` keeps its existing `ThermalPort` arrays unchanged (CONN-03). No connector change — only verification that it composes cleanly with the refactored variants in later phases.

#### Adiabatic / zero-flux defaults (Area 1)
- **D-06:** Adiabatic-when-unconnected is achieved by **IC defaults alone** — no `ifelse` guard in the channel equations. `WallPort` defaults `h = 0.0`, `T_wall = 300.0`. `HeatFluxPort` defaults `q_flux = 0.0`. `Q_flow = 0.0` (auto-zero'd by MTK's Flow rule when unconnected). Channel-side equations are written plainly:
  - For `Channel` (Phase 54): `port.Q_flow ~ port.h · heated_part · dz · (port.T_wall - T[i])`. Unconnected ⇒ `h = 0` (IC) ⇒ `Q_flow = 0`. `T_wall` stays at IC 300.0 but is multiplied by 0, so harmless.
  - For `ChannelHeatFlux` (Phase 54): `port.Q_flow ~ port.q_flux · heated_part · dz`. Unconnected ⇒ `q_flux = 0` ⇒ `Q_flow = 0`.
- **D-07:** *Why no `ifelse(h>0, ..., 0)` guard*: MTK doesn't expose a compile-time `isconnected()` at the component level, and the spike validated that the IC-default path works without runtime branches. Belt-and-suspenders ifelse adds one branch per cell per side for no observed benefit. Discarded **option B (ifelse-on-h)** and **option C (sentinel `T_wall`)** explicitly.

#### `Q_flow` semantics & sign convention (Area 2)
- **D-08:** `Q_flow` matches the existing `ThermalPort` convention exactly: units `[W]` (per-cell power, not flux density); annotation `[connect = Flow]`; sign **positive = heat into the channel** from this wall side.
- **D-09:** `q_flux` on `HeatFluxPort` is in **W/m²** (intensive heat flux density). The `ChannelHeatFlux` energy balance multiplies by `heated_part · dz` to get per-cell power.
- **D-10:** Symmetric treatment across the two connectors keeps composition consistent.

#### Test scaffolding (Area 3)
- **D-11:** Unit tests live in `test/test_connectors.jl`. Inline stubs (underscore-prefixed, not exported): `_StubRecipient(; n, port_type=:wall)`, `_StubWallDriver(; n, T_w, h_v)`, `_StubFluxDriver(; n, q_v)`.
- **D-12:** Inline stubs (do NOT promote `/tmp/vec_diagnose3.jl` scaffolding).
- **D-13:** Test the four CONN-04 sub-criteria explicitly — variable annotations, `connect()` well-formedness, adiabatic/zero-flux default, `instream()` interplay.

#### `instream()` smoke compose target (Area 4)
- **D-14:** Tiny pump→stub→pump closed loop: `Pump(mdot0=0.5)` + `_StubRecipient(n=2)` + pressure anchor `pump.port_in.P ~ 1.0e5` + `solve_transient(t = 0.0..0.1)`. Assertions: (a) no MTK warnings about unset stream connections; (b) all unknowns finite at final time; (c) for the unconnected-WallPort variant, `T[i]` stays adiabatic.
- **D-15:** Smoke must do an actual solve, not structural-only — spike's failure mode is integration-time mis-integration of `sol.u`, not a `mtkcompile` error.

#### Out-of-scope here
- **D-16:** Variant rewrites of `Channel` and `ChannelHeatFlux` belong to Phase 54.
- **D-17:** No `_channel_base_eqs` / energy-balance / `_channel_core` work in Phase 52.
- **D-18:** No `composition/helpers.jl` changes in Phase 52.
- **D-19:** No commits to `main`. Branch `channels-redesign`.

### Claude's Discretion

The locked decisions cover the design space. Claude's discretion in this phase is limited to:
- The exact wording of docstrings (must include `# Arguments` + `# Returns` per CLAUDE.md).
- The grouping/order of `@testset` blocks within `test_connectors.jl` — tests just need to cover the four CONN-04 sub-criteria; ordering is implementation detail.
- Whether the smoke test uses `@test_logs min_level=Logging.Warn` vs. `@test_nowarn` to assert "no MTK warnings" — both achieve D-14's intent; pick whichever produces the cleanest failure message.

### Deferred Ideas (OUT OF SCOPE)

- Variant rewrites of `Channel` / `ChannelHeatFlux` against new connectors → **Phase 54**
- `_channel_core` extraction & enthalpy-form energy balance → **Phase 53**
- Composition-helper updates (`symmetric_plate` / `plate` / `one_sided_connection` accepting `WallPort` arrays) → **Phase 55**
- Cross-validation against Python STREAM under the new convective scheme → **Phase 56**
- MTK upstream report for the vector-form connector bug → out of v1.1 scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **CONN-01** | New scalar MTK acausal connector type `WallPort` carrying `T_wall`, `h`, and `Q_flow` (`[connect = Flow]`). Used by `Channel` as arrays `thermal_left[1:n]`, `thermal_right[1:n]`. Adiabatic when unconnected. | Mirror `ThermalPort` body (`src/connectors.jl:17-24`); add two more `@variables` rows for `T_wall(t) = 300.0` (across) and `h(t) = 0.0` (across). Adiabatic-when-unconnected proven via spike's array-of-scalar success path; verified by D-14 smoke test (`T[i]` stays at IC over 0.1s). |
| **CONN-02** | New scalar MTK acausal connector type `HeatFluxPort` carrying `q_flux` and `Q_flow` (`[connect = Flow]`). Used by `ChannelHeatFlux` as arrays `thermal_left[1:n]`, `thermal_right[1:n]`. Zero-flux when unconnected. | Mirror `ThermalPort` body, swap `T(t)` for `q_flux(t) = 0.0` (across, W/m²). Zero-flux default → `Q_flow=0` because the Phase-54 channel equation will be `port.Q_flow ~ port.q_flux · heated_part · dz`, and `0 · anything = 0`. |
| **CONN-03** | `ChannelAndContacts` continues to expose per-cell, per-side `T_wall` via existing `ThermalPort` arrays — no connector change. Verify it composes cleanly with refactored variants. | Existing `ThermalPort` (`src/connectors.jl:17-24`) is unchanged; `ChannelAndContacts` (`src/components/thermal_channel.jl:48-241`) already wires `thermal_left[1:n]` / `thermal_right[1:n]`. CONN-03 is a **non-change** verified by ensuring the existing test suite still passes after Phase 52's additions to `test_connectors.jl`. |
| **CONN-04** | All new connectors honor MTK acausal semantics: `connect()` works idiomatically, composition helpers can wire array-of-scalar ports per cell via existing patterns, no special-case wiring tricks. | Verified by the four `@testset` groups in Phase 52: variable annotations (Symbolics getmetadata), `connect()` well-formedness (compose two stubs, count equations), adiabatic default (compose unconnected stub, solve, assert state holds), and `instream()` interplay (D-14 smoke loop with no warnings). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

| Directive | Source line | Phase 52 implication |
|-----------|-------------|----------------------|
| `src/connectors.jl` is canonical for connector definitions | "File Structure Standard" | Both new connectors go in `src/connectors.jl` (D-04 already enforces this). |
| Exports declared **only** in `src/STREAM.jl` — never inside component files | "Exports" section | Add `WallPort`, `HeatFluxPort` to existing `export FlowPort, ThermalPort` line (line 28). |
| `name` kwarg is **always** keyword-only | "Component authoring conventions" | `@connector function WallPort(; name, …)` and `@connector function HeatFluxPort(; name, …)` — never positional. |
| Underscore-prefixed names are internal helpers, not exported | "Component authoring conventions" | Test stubs `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver` are local-only; never `export`ed; live inside `test_connectors.jl`. |
| Every exported name has a docstring with `# Arguments` and `# Returns` | "Component authoring conventions" | Both new connectors need the structured docstring. Must document each across variable's units and the Flow-variable sign convention. |
| Use `ifelse()` (not `if`/`else`) inside MTK equations | "MTK Patterns" | N/A in Phase 52 — no equations are written inside the new connectors. Relevant only when Phase 54 writes the channel-side equations. |
| `mtkcompile(sys)` before solve | "MTK Patterns" | The smoke-test stub composition must `mtkcompile` before `solve_transient`. |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Connector type definition | `src/connectors.jl` (acausal-port library) | — | All MTK connectors live here per CLAUDE.md File Structure Standard; this is the only correct location. |
| Public export | `src/STREAM.jl` (module entry point) | — | Project rule: exports declared only in module entry. |
| Test scaffolding (stubs, drivers) | `test/test_connectors.jl` (inline, file-local) | — | D-11 + CLAUDE.md test-file-mirrors-src rule (`connectors.jl` → `test_connectors.jl`). |
| Smoke compose target | `test/test_connectors.jl` (test-only) | `src/components/pump.jl` (consumed) | Smoke uses existing fixed-flow `Pump(; name, mdot0=…)` (`src/components/pump.jl:72-84`). No new shipped builders needed. |
| Channel-side equation using port (e.g., `port.Q_flow ~ port.h · ... · (port.T_wall − T[i])`) | **Out of scope (Phase 54)** | — | D-16, D-17 lock this out of Phase 52. |
| Composition helpers consuming new connectors | **Out of scope (Phase 55)** | — | D-18 locks out helper changes; existing `port(sys, face, i)` accessor (`src/composition/helpers.jl:28`) is sufficient for the test-stub `connect()` calls without modification. |

## Existing Patterns to Mirror

### `@connector function` syntax (`src/connectors.jl`)

The full file is 25 lines and contains both reference connectors:

```julia
# src/connectors.jl, lines 1-24
using ModelingToolkit
using ModelingToolkit: t_nounits as t

@connector function FlowPort(; name, P=1.0e5, mdot=0.0, T=300.0)
    sts = @variables begin
        P(t) = P, [description = "Pressure (Pa), across variable"]
        mdot(t) = mdot,
        [connect = Flow, description = "Mass flow rate (kg/s), positive = into port"]
        T(t) = T, [connect = Stream, description = "Temperature (K), stream variable"]
    end
    System(Equation[], t, sts, []; name=name)
end

@connector function ThermalPort(; name, T=300.0, Q_flow=0.0)
    sts = @variables begin
        T(t) = T, [description = "Temperature (K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into component"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

**Pattern observations** (verified by reading `src/connectors.jl:1-24`):
- One-line `using ModelingToolkit` + the alias `t_nounits as t` is already in scope (line 5).
- Body shape: `@connector function X(; name, <kwargs with numeric defaults>)` → `@variables begin ... end` → `System(Equation[], t, sts, []; name=name)`.
- **Across variables** carry only `[description = "..."]` (no `connect = ...` metadata).
- **Flow variables** carry `[connect = Flow, description = "..."]`.
- **Stream variables** carry `[connect = Stream, description = "..."]`.
- Variable IC default goes in the `=` clause: `P(t) = P` (where the right-hand `P` is the kwarg).
- Empty equations vector `Equation[]`, empty parameters `[]`.

### Required new connector bodies (CONN-01, CONN-02)

Following the exact `ThermalPort` template with one extra across var for `WallPort`:

```julia
@connector function WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)
    sts = @variables begin
        T_wall(t) = T_wall, [description = "Wall temperature (K), across variable"]
        h(t) = h,           [description = "Heat transfer coefficient (W/m^2·K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end

@connector function HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)
    sts = @variables begin
        q_flux(t) = q_flux, [description = "Heat flux density (W/m^2), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

[VERIFIED: in-tree `src/connectors.jl:17-24` — pattern verbatim from `ThermalPort`]
[CITED: ModelingToolkit v11.25.0 — `Manifest.toml`]

### Export line in `src/STREAM.jl`

Current line 28 (verified):

```julia
export FlowPort, ThermalPort
```

After Phase 52:

```julia
export FlowPort, ThermalPort, WallPort, HeatFluxPort
```

No change to `include` order — `connectors.jl` is included on line 7 (`src/STREAM.jl:7`) before any component file, so both new connectors are visible to Phase 54's variant rewrites and to all currently shipped builders without further plumbing.

[VERIFIED: `src/STREAM.jl:7,28` lines read directly]

## Stream-Variable / `instream()` Interplay

### How `FlowPort` declares `T` as a Stream variable

`FlowPort` (`src/connectors.jl:7-15`) marks `T(t)` with `[connect = Stream, description = ...]`. In MTK v11, Stream variables behave specially under `connect()` — they don't sum (Flow) or equate (potential/across); instead, MTK generates `instream(...)` accessor expressions for upstream-side selection in branched topologies. The current Channel (`src/components/channel.jl:66-67`) uses this:

```julia
T_inlet_fwd = instream(port_in.T)
T_inlet_rev = instream(port_out.T)
```

### Whether new connectors need `[connect = Stream]` markers

**No.** [VERIFIED: D-02, D-03 explicitly enumerate the variable types]

- `WallPort`: `T_wall` and `h` are plain across (no `connect` metadata) — they propagate as equality across `connect()`-joined ports. `Q_flow` is Flow.
- `HeatFluxPort`: `q_flux` is plain across; `Q_flow` is Flow.

**Why this is correct:** Stream semantics are for variables that need upstream-direction selection at junctions (temperature in a fluid network with possible flow reversal). Wall temperature, heat transfer coefficient, and heat flux are **boundary potentials** — they should equate at the connection point, which is the across rule. The Flow rule on `Q_flow` ensures conservation (total heat flow into the junction sums to zero), which is exactly what we want for thermal coupling.

The smoke-compose target (D-14) is what verifies that `FlowPort` Stream semantics and `WallPort`/`HeatFluxPort` plain-across semantics coexist in the **same compiled system** without warnings — the array-of-scalar pattern was proven safe in the spike, but only the smoke test exercises the `instream()` ↔ new-connector coexistence on a system that integrates over time.

### Known MTK warning patterns and how to capture them

- **`circular instream`** — appears when a closed hydraulics-only loop has no thermal anchor breaking the cycle. Fix: pin one or two ports' `T` (see `test/test_pump.jl:119-127` for the canonical two-anchor pattern). The Phase-52 smoke loop avoids this by **not closing a thermal loop** through the stub — the stub has its own internal `T[i]` state; `port_out.T` and `port_in.T` of the stub are bound to the cell-end temperatures (mirroring how `Channel` does it on `src/components/channel.jl:115-116`).
- **`unset stream connection`** — generally indicates an orphan stream variable. Avoided by composing both the `Pump` (whose `port_in.T`/`port_out.T` are stream) and the stub (which mirrors `Channel`'s `port_in.T ~ T[1]` / `port_out.T ~ T[n]` binding) in the same system.

### Asserting "no warnings" in tests

The codebase already uses two idioms:

1. **`@test_nowarn expr`** — most common; appears 16 times across the test suite (e.g., `test_channel.jl:23`, `test_pump.jl:18`). Asserts `expr` runs and emits no warnings. Use for the `mtkcompile` step of the smoke loop:
   ```julia
   ssys = @test_nowarn mtkcompile(sys)
   ```

2. **`@test_logs (:warn, regex) expr`** — narrower; appears in `test_correlations.jl:488` for asserting a *specific* warning. Less useful here since we want the absence of *any* warning.

For the integration-time check (assertion (b) of D-14), the cleanest path is `@test_nowarn` around both `mtkcompile` and `solve_transient`:

```julia
ssys = @test_nowarn mtkcompile(sys)
sol  = @test_nowarn solve_transient(ssys, op, range(0.0, 0.1, length=20))
```

Anything emitted by MTK or the solver during these calls causes the test to fail.

[VERIFIED: 16 `@test_nowarn` usages in test/, grep on 2026-05-05]

## Test Scaffolding Patterns in `test_connectors.jl`

### Existing inline-stub idiom

`test/test_connectors.jl` (currently 83 lines, 6 `@testset`s) follows this shape (verified):

1. Construct a tiny system **inline** in the test body — `@named fp = FlowPort()` or `@named tp = ThermalPort()`.
2. Inspect via MTK introspection — `unknowns(fp)`, `Symbolics.getmetadata(...)`.
3. Assert variable counts / annotations (lines 17-48 for FlowPort, 53-82 for ThermalPort).

The file already imports `ModelingToolkit`, `STREAM`, `import STREAM: Channel` (line 4 — to disambiguate from `Base.Channel`), and `const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase` (line 5 — the introspection helper for `getmetadata`).

### Adding stubs without polluting module exports

Per D-11/D-12, define `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver` at the **top of `test_connectors.jl`**, after the imports but before the `@testset` blocks. These are file-local Julia functions — no `export`, no need to live in `src/`. Underscore prefix signals private-ness per CLAUDE.md.

Sketch (mirrors the spike's `ChannelScalar` and `ScalarWalls` shapes from `/tmp/vec_diagnose3.jl:27-71`, but rewritten clean per D-12):

```julia
# In test/test_connectors.jl, after the `using` lines

# Recipient mirrors the eventual Channel / ChannelHeatFlux interface.
# port_type = :wall  -> WallPort arrays
# port_type = :flux  -> HeatFluxPort arrays
function _StubRecipient(; name, n::Int, port_type::Symbol=:wall)
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    PortType = port_type === :wall ? WallPort : HeatFluxPort
    thermal_left  = [PortType(; name=Symbol(:thermal_left, i))  for i in 1:n]
    thermal_right = [PortType(; name=Symbol(:thermal_right, i)) for i in 1:n]
    @variables (T(t))[1:n] = fill(300.0, n)
    Dt = Differential(t)
    m_cp = 1.0    # any positive constant — value doesn't matter for adiabatic check
    eqs = Equation[]
    for i in 1:n
        push!(eqs, Dt(T[i]) ~ (thermal_left[i].Q_flow + thermal_right[i].Q_flow) / m_cp)
    end
    # Hydraulic plumbing: pass-through, mirrors Channel's port wiring shape
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ T[1])
    sys = System(eqs, t, [collect(T)...], []; name=name)
    return compose(sys, port_in, port_out, thermal_left..., thermal_right...)
end

function _StubWallDriver(; name, n::Int, T_w::Vector{Float64}, h_v::Vector{Float64})
    ports = [WallPort(; name=Symbol(:port, i)) for i in 1:n]
    eqs = Equation[]
    for i in 1:n
        push!(eqs, ports[i].T_wall ~ T_w[i])
        push!(eqs, ports[i].h      ~ h_v[i])
    end
    sys = System(eqs, t; name=name)
    return compose(sys, ports...)
end

function _StubFluxDriver(; name, n::Int, q_v::Vector{Float64})
    ports = [HeatFluxPort(; name=Symbol(:port, i)) for i in 1:n]
    eqs = Equation[]
    for i in 1:n
        push!(eqs, ports[i].q_flux ~ q_v[i])
    end
    sys = System(eqs, t; name=name)
    return compose(sys, ports...)
end
```

**Three subtleties worth flagging to the planner:**
1. The recipient stub adds `port_out.T ~ T[n]` / `port_in.T ~ T[1]` so the Pump's `instream()` calls have a defined upstream value — without these, the closed-loop hydraulic system has no thermal anchor and MTK warns about unset stream connections (the same pitfall called out at `test/test_pump.jl:119-128`).
2. The stub does NOT need a `Dt(port_in.mdot)` momentum ODE; for the smoke loop the `Pump(mdot0=0.5)` *is* the momentum source, and a passive recipient just needs `port_in.mdot + port_out.mdot ~ 0`.
3. Each `WallPort` needs an *external* equation pinning `T_wall` for the connected case — this is what `_StubWallDriver` provides. The unconnected case relies entirely on the IC default `T_wall = 300.0`.

### `port(sys, face, i)` accessor

`src/composition/helpers.jl:28` defines:

```julia
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
```

This is the canonical (and only correct) way to address indexed port-array elements in `connect()` calls on a composed system. It builds the symbol `:thermal_left2` (etc.) and calls `getproperty`. Phase 52 stubs use it the same way — but the stubs themselves construct ports as `Symbol(:thermal_left, i)` (matching `src/components/thermal_channel.jl:97-98`) so the accessor naming aligns.

**The stubs do NOT modify `helpers.jl`** (D-18) — they consume the existing `port` function unchanged.

[VERIFIED: `src/composition/helpers.jl:28` read directly; `src/components/thermal_channel.jl:97-98` uses `Symbol(:thermal_left, i)`]

## Adiabatic-Default Verification

### What the test asserts

Compose a **single** `_StubRecipient(n=2, port_type=:wall)` with no `_StubWallDriver` connected. Apply hydraulic boundary conditions (a `Pump` with `mdot0=0.5` looped back) so the system is well-posed. Solve `solve_transient` over a tiny tspan (e.g., `0.0..0.1`).

Assertions:
- `sol.retcode == ReturnCode.Success` (system actually integrates)
- For each cell `i`, `sol[stub.T[i], end] ≈ sol[stub.T[i], 1]` within rtol — temperature does not drift because the IC default `h=0` ⇒ `Q_flow=0` per cell per side, so the energy-balance ODE has `Dt(T[i]) ~ 0/m_cp ~ 0`.
- Optionally inspect `sol[stub.thermal_left1.Q_flow, :]` is identically zero across the time grid.

### Numerical tolerance

A passive recipient with zero heat input and zero thermal advection (the recipient stub doesn't include cp·mdot·dT terms — it's a heat-only test) drifts only via solver round-off. Tolerance `rtol=1e-8` (or even `atol=1e-6`) is appropriate for `Tsit5` over 0.1 s.

If the recipient stub *does* include the convective term (matching the eventual `Channel` shape), then with `mdot=0.5`, `cp_water(300)≈4180`, and `T_inlet=300=T[1]=T[2]=T_init`, advection contributes nothing because there is no temperature gradient at IC. So the same tight tolerance applies.

[VERIFIED: locked by D-06; the equation `port.Q_flow ~ port.h · ... · (port.T_wall − T[i])` evaluates to `0 · heated_part · dz · (300 − 300) = 0` at IC, and stays at zero because `h(t)=0` is the IC default with no driver setting it otherwise.]

## `instream()` Smoke Compose Target (D-14)

### Topology

```
         port_out          port_in (mdot in)
   ┌────────────────────┐
   │       Pump          │←──────────────────────┐
   │   (mdot0=0.5)       │                       │
   └────────┬────────────┘                       │
            │ port_out                            │
            ▼                                     │ port_out
   ┌────────────────────┐                        │
   │  _StubRecipient    │────────────────────────┘
   │  (n=2,             │  port_out
   │  port_type=:wall)  │
   │   thermal_left[i]  ← UNCONNECTED (adiabatic by IC)
   │   thermal_right[i] ← UNCONNECTED
   └────────────────────┘
```

Plus the pressure anchor `pump.port_in.P ~ 1.0e5`.

### Exact assertions

```julia
@named pump = Pump(; mdot0=0.5)
@named stub = _StubRecipient(; n=2, port_type=:wall)
conns = [
    connect(pump.port_out, stub.port_in),
    connect(stub.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
]
@named sys = compose(System(conns, t; name=:smoke), pump, stub)
ssys = @test_nowarn mtkcompile(sys)
sol  = @test_nowarn solve_transient(ssys, [], range(0.0, 0.1, length=20))

@test sol.retcode == ReturnCode.Success
@test all(isfinite, sol[ssys.stub.T[1], :])
@test all(isfinite, sol[ssys.stub.T[2], :])
@test isapprox(sol[ssys.stub.T[1], end], sol[ssys.stub.T[1], 1]; rtol=1e-8)
@test isapprox(sol[ssys.stub.T[2], end], sol[ssys.stub.T[2], 1]; rtol=1e-8)
```

Repeat with `port_type=:flux` for `HeatFluxPort` coverage.

### Why this catches the spike's failure mode

The spike (`/tmp/vec_diagnose3.jl:73-129`) showed that vector-form connectors **mis-integrate the first unknown** — i.e., raw `sol.u` after one solver step puts wrong values in the wrong slots. A structural-only test (`mtkcompile` succeeds; equation count matches expectation) misses this because the bug is in **how the integrator wires u-vector positions to symbolic variables**, not in equation generation. The bug appeared even with tiny tspans (`(0.0, 0.001)` in the spike; line 79).

By forcing the smoke test to actually `solve` and then assert on `sol[ssys.stub.T[i], :]` (the **named symbolic accessor**, not raw `sol.u`), the test would detect:
- Misaligned u-vector slots (regression of the spike's failure mode)
- Spurious heat input from a non-zero IC sneaking through the `Q_flow` connection rule
- Any new MTK warning at compile or integration time

This is exactly what D-15 demands ("an actual solve and not a structural-only test"), and it's the cheapest path that catches the regression class — much cheaper than wiring a full `build_loop`-equivalent (option 3 from CONTEXT.md, explicitly discarded).

[VERIFIED: `/tmp/vec_diagnose3.jl:97-130` shows `sol_v.u[end]` and `sol_v(0.001; idxs=ch_v.T[i])` diverging when scalar+vector coexist; structural inspection alone would not surface that.]

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` (standard `@test` / `@testset`) [VERIFIED: `test/test_connectors.jl:1` `using Test`] |
| Config file | `test/runtests.jl` (orchestrator, 21 lines, includes `test_connectors.jl` on line 4) |
| Quick run command | `julia --project=. test/runtests.jl` (or with `--sysimage stream.so` if built locally) |
| Full suite command | Same — single orchestrator covers everything |
| Phase 52 alone | `julia --project=. -e 'using Test; include("test/test_connectors.jl")'` for fast iteration on connectors only |

### Phase Requirements → Test Map

CONN-04 has four sub-criteria. The mapping below covers all four for **both** `WallPort` and `HeatFluxPort`, plus the CONN-03 non-regression check for `ThermalPort`. Test names follow the existing `CONN-XX:` style (`test_connectors.jl:17,26,31,...`).

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CONN-01 | `WallPort` instantiation with `@named` succeeds, exposes T_wall, h, Q_flow | existence/structural | `julia --project=. test/runtests.jl` (testset "CONN-01: WallPort instantiation") | ❌ Wave 0 (new testset to add) |
| CONN-01 | `WallPort` variable count == 3 | structural | testset "CONN-01: WallPort variable count" | ❌ Wave 0 |
| CONN-01 | `WallPort.Q_flow` is `connect = Flow` | structural | testset "CONN-01: WallPort Q_flow is Flow" | ❌ Wave 0 |
| CONN-01 | `WallPort.T_wall` and `WallPort.h` are across (no connect metadata) | structural | testset "CONN-01: WallPort across-variable annotations" | ❌ Wave 0 |
| CONN-01 | `_StubRecipient(n=2, :wall)` mtkcompiles cleanly with no warnings | integration | testset "CONN-01: stub mtkcompile" | ❌ Wave 0 |
| CONN-01 | Adiabatic default: solve smoke loop, T[i] does not drift (rtol 1e-8) | behavioural | testset "CONN-01: adiabatic when unconnected" | ❌ Wave 0 |
| CONN-01 | Connected case: `_StubWallDriver(T_w=350, h=3000)` drives T[i] toward T_w | behavioural | testset "CONN-01: driven case heats stub" | ❌ Wave 0 |
| CONN-02 | `HeatFluxPort` instantiation succeeds, exposes q_flux, Q_flow | existence/structural | testset "CONN-02: HeatFluxPort instantiation" | ❌ Wave 0 |
| CONN-02 | `HeatFluxPort` variable count == 2 | structural | testset "CONN-02: HeatFluxPort variable count" | ❌ Wave 0 |
| CONN-02 | `HeatFluxPort.Q_flow` is `connect = Flow` | structural | testset "CONN-02: HeatFluxPort Q_flow is Flow" | ❌ Wave 0 |
| CONN-02 | `HeatFluxPort.q_flux` is across (no connect metadata) | structural | testset "CONN-02: HeatFluxPort q_flux is across" | ❌ Wave 0 |
| CONN-02 | Zero-flux default: solve smoke loop, T[i] does not drift | behavioural | testset "CONN-02: zero-flux when unconnected" | ❌ Wave 0 |
| CONN-02 | Connected case: `_StubFluxDriver(q_v=1e5)` drives T[i] upward | behavioural | testset "CONN-02: driven case heats stub" | ❌ Wave 0 |
| CONN-03 | Existing `ThermalPort` testsets still pass (no regression) | regression | testset "CONN-02: ThermalPort instantiation" (existing, lines 53-82) | ✅ exists |
| CONN-03 | `ChannelAndContacts` mtkcompiles unchanged (no Phase-52 regression) | regression | Existing `test_channel.jl` / `test_composition.jl` testsets | ✅ exists |
| CONN-04 | `connect()` produces well-formed equations (compose recipient + driver, count equations) | structural | testset "CONN-04: connect() equation count" | ❌ Wave 0 |
| CONN-04 | `instream()` interplay: smoke loop with FlowPort + WallPort coexists, no warnings | integration | testset "CONN-04: instream smoke (WallPort)" | ❌ Wave 0 |
| CONN-04 | `instream()` interplay: smoke loop with FlowPort + HeatFluxPort coexists, no warnings | integration | testset "CONN-04: instream smoke (HeatFluxPort)" | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project=. -e 'using Test; include("test/test_connectors.jl")'` (~10s including TTFX after sysimage)
- **Per wave merge:** `julia --project=. test/runtests.jl` (full suite — ensures CONN-03 non-regression of `ChannelAndContacts` / `Channel` / composition helpers / examples)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/test_connectors.jl` — append stubs `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver` (top of file, after imports) and ~14 new testsets per the table above
- [ ] No new test file needed (D-11 keeps everything in `test_connectors.jl`)
- [ ] No conftest / shared fixtures needed (Julia `Test` doesn't have conftest; stubs are file-local)
- [ ] No framework install — `Test` is stdlib

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Compile-time `isconnected()` probe to enable adiabatic branch | Custom MTK introspection or wrapper macro | IC defaults `h=0` / `q_flux=0` (D-06) | MTK doesn't expose component-level `isconnected()` at compile time; the IC-default mechanism is already the project-blessed pattern (matches `ThermalPort` behavior in `ChannelAndContacts` since v0.3). Spike validated it works without runtime branches. |
| Sentinel `T_wall = nothing` to detect unconnected ports | Special-case Julia `nothing` handling | Numeric default `T_wall = 300.0` (D-06, D-07) | MTK connector defaults must be numeric ICs — `nothing` won't propagate through MTK's symbolic system, and any code path that compares to `nothing` at runtime would be a Julia-level branch outside MTK's view, breaking JIT specialization. |
| Vector-form connectors carrying `(T_wall(t))[1:n]` arrays | `@variables (T_wall(t))[1:n]` inside `@connector` | Array-of-scalar `[WallPort(; name=Symbol(:thermal_left, i)) for i in 1:n]` (D-01) | Vector form **mis-integrates the first unknown** when paired with any scalar-port system in the same compiled session — proven by spike `/tmp/vec_diagnose3.jl`. Bug appears in raw `sol.u`, not just symbolic accessors. Unsafe in any realistic `build_loop`. |
| Custom warning capture | Manual `Logging.with_logger` wrapping | `@test_nowarn` (used 16x in test suite) | Stdlib idiom; matches existing tests (`test_channel.jl:23`, `test_pump.jl:18`, etc.); failure messages already include the warning text. |
| Custom test stubs with named-tuple state | Bespoke fixture framework | Inline functions inside `test_connectors.jl` (D-11) | Matches existing FlowPort/ThermalPort test pattern (`test_connectors.jl:17-82`); zero new public API surface. |
| Promoting `/tmp/vec_diagnose3.jl` scaffolding into the test suite | Copy-paste from `/tmp` | Clean, minimally-named stubs written from scratch (D-12) | Spike artefacts are exploratory — production tests deserve clean stubs. The spike's `ChannelScalar` / `VecWallPort` shapes inform the design but are not the production code. |

**Key insight:** Phase 52 is a *protocol-establishment* phase, not a feature-build phase. The discipline is to copy the existing `ThermalPort` shape with surgical precision, not to invent novel patterns.

## Common Pitfalls

### Pitfall 1: Restoring vector-form connectors during planning
**What goes wrong:** Planner sees the array-of-scalar pattern and thinks it's verbose; proposes vector-form for ergonomics.
**Why it happens:** Array-of-scalar requires a `for i in 1:n` loop in callers, which looks repetitive vs. a single `@variables (T_wall(t))[1:n]` declaration in the connector.
**How to avoid:** D-01 locks the array-of-scalar pattern. Ergonomics are abstracted by composition helpers (`symmetric_plate`, `plate`, `one_sided_connection` — `src/composition/helpers.jl:174-277`), not by the connector definition itself.
**Warning signs:** Any plan task that proposes `@variables (T_wall(t))[1:n]` inside `@connector function`.

### Pitfall 2: Adding `ifelse(h > 0, ...)` belt-and-suspenders
**What goes wrong:** Planner adds a defensive `ifelse` guard "just in case" the IC-default mechanism doesn't catch unconnected ports.
**Why it happens:** Defensive programming instinct; misunderstanding of MTK's Flow rule (which auto-zeros disconnected Flow variables anyway).
**How to avoid:** D-06, D-07 explicitly discard option B (ifelse-on-h). Trust the IC default; the smoke test is the regression check.
**Warning signs:** Any plan equation containing `ifelse(h, ...)` or `ifelse(T_wall != ..., ...)` for the new connectors.

### Pitfall 3: Forgetting `name` keyword-only
**What goes wrong:** Author writes `@connector function WallPort(name; ...)` with `name` positional.
**Why it happens:** Other Julia macros allow positional first arg.
**How to avoid:** CLAUDE.md "Component authoring conventions" — `name` is **always** keyword-only because the `@named` macro injects `name=:varname` as a kwarg. Mirror `FlowPort`/`ThermalPort` exactly: `@connector function X(; name, ...)`.
**Warning signs:** `function WallPort(name;` (positional) or any caller that passes `name` positionally.

### Pitfall 4: Numeric-string defaults vs. numeric defaults
**What goes wrong:** Author writes `T_wall = 300` (Int) instead of `T_wall = 300.0` (Float64).
**Why it happens:** Julia auto-promotes in arithmetic, so the bug is silent until MTK's type inference picks the wrong path.
**How to avoid:** Always Float64 literals in connector defaults. `FlowPort` uses `P=1.0e5, mdot=0.0, T=300.0` (`src/connectors.jl:7`); `ThermalPort` uses `T=300.0, Q_flow=0.0` (line 17). Mirror exactly.
**Warning signs:** Any `= 300` (no `.0`) or `= 0` in the new connectors.

### Pitfall 5: Forgetting to add to `src/STREAM.jl` export line
**What goes wrong:** Connectors compile inside the module but `using STREAM; @named wp = WallPort()` errors with `WallPort not defined`.
**Why it happens:** STREAM project policy: exports go in `STREAM.jl` only, never in component files.
**How to avoid:** Modify line 28 of `src/STREAM.jl` from `export FlowPort, ThermalPort` to `export FlowPort, ThermalPort, WallPort, HeatFluxPort`. Verified by the existence test `@named wp = WallPort()` at the REPL succeeding.
**Warning signs:** Test failure at the very first `@named wp = WallPort()` line.

### Pitfall 6: Stub-recipient missing `port_in.T ~ T[1]` / `port_out.T ~ T[n]`
**What goes wrong:** Smoke test composes pump + stub, but `mtkcompile` warns about unset stream connections, or solve fails on circular instream.
**Why it happens:** A pump-loop has `port_in.T = instream(port_out.T)` and `port_out.T = instream(port_in.T)` (`src/components/pump.jl:80-81`); without a thermal anchor on the stub side, the resulting equation chain is circular.
**How to avoid:** Stub-recipient must bind its FlowPort temperatures to its internal cell temperatures, mirroring `Channel`'s `src/components/channel.jl:115-116`:
```julia
push!(eqs, port_out.T ~ T[n])
push!(eqs, port_in.T  ~ T[1])
```
**Warning signs:** `circular instream` warning or `singular DAE` error during `mtkcompile`.

### Pitfall 7: Using `mkdir -p` or creating new dirs
**What goes wrong:** Plan task includes `mkdir -p src/connectors/` to "scope" the new files.
**Why it happens:** Some authors organize components into directories.
**How to avoid:** CLAUDE.md File Structure Standard explicitly puts connectors in the **single file** `src/connectors.jl`, mirroring the existing `connectors.jl` / `resistors.jl` / `misc.jl` (multiple-related-components-per-file) pattern. No new dirs needed in Phase 52.
**Warning signs:** Any plan task that creates a directory or mentions `src/connectors/`.

### Pitfall 8: Adding exports inside `src/connectors.jl`
**What goes wrong:** Author adds `export WallPort, HeatFluxPort` inside `src/connectors.jl`.
**Why it happens:** Looks natural to colocate export with definition.
**How to avoid:** CLAUDE.md "Exports" rule — all public exports declared in `src/STREAM.jl` only. The audit value of a single export list outweighs colocation convenience.
**Warning signs:** Any plan task that touches export statements outside `src/STREAM.jl`.

## Code Examples

### CONN-01 / CONN-02: Connector definitions (verified template)

```julia
# Source: src/connectors.jl (mirroring lines 17-24 ThermalPort verbatim)
@connector function WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)
    sts = @variables begin
        T_wall(t) = T_wall, [description = "Wall temperature (K), across variable"]
        h(t) = h,           [description = "Heat transfer coefficient (W/m^2·K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end

@connector function HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)
    sts = @variables begin
        q_flux(t) = q_flux, [description = "Heat flux density (W/m^2), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

### Variable-annotation introspection (CONN-04 structural test)

```julia
# Source: test/test_connectors.jl:31-48 (mirroring FlowPort/ThermalPort tests)
@testset "CONN-01: WallPort Q_flow is a Flow variable" begin
    @named wp = WallPort()
    q_var = only(filter(v -> ModelingToolkit.getname(v) == :Q_flow, unknowns(wp)))
    connect_type = Symbolics.getmetadata(
        q_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type == ModelingToolkit.Flow
end

@testset "CONN-01: WallPort T_wall is across (no connect metadata)" begin
    @named wp = WallPort()
    T_wall_var = only(filter(v -> ModelingToolkit.getname(v) == :T_wall, unknowns(wp)))
    connect_type = Symbolics.getmetadata(
        T_wall_var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type === nothing
end
```

### Smoke compose target (D-14)

```julia
# Source: test/test_connectors.jl (new testset for CONN-04 instream smoke)
@testset "CONN-04: instream smoke (WallPort + FlowPort coexistence)" begin
    @named pump = Pump(; mdot0=0.5)
    @named stub = _StubRecipient(; n=2, port_type=:wall)
    conns = Equation[
        connect(pump.port_out, stub.port_in),
        connect(stub.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:smoke_wall), pump, stub)
    ssys = @test_nowarn mtkcompile(sys)
    sol  = @test_nowarn solve_transient(ssys, [], range(0.0, 0.1, length=20))

    @test sol.retcode == ReturnCode.Success
    @test all(isfinite, sol[ssys.stub.T[1], :])
    @test all(isfinite, sol[ssys.stub.T[2], :])
    @test isapprox(sol[ssys.stub.T[1], end], sol[ssys.stub.T[1], 1]; rtol=1e-8)
    @test isapprox(sol[ssys.stub.T[2], end], sol[ssys.stub.T[2], 1]; rtol=1e-8)
end
```

### Driven adiabatic-vs-heated comparison (CONN-04 behavioural test)

```julia
@testset "CONN-04: WallPort driven case heats stub above adiabatic" begin
    @named pump = Pump(; mdot0=0.5)
    @named stub = _StubRecipient(; n=2, port_type=:wall)
    @named drv  = _StubWallDriver(; n=2, T_w=fill(400.0, 2), h_v=fill(3000.0, 2))
    conns = Equation[
        connect(pump.port_out, stub.port_in),
        connect(stub.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        connect(stub.thermal_left1,  drv.port1),
        connect(stub.thermal_left2,  drv.port2),
    ]
    @named sys = compose(System(conns, t; name=:smoke_wall_driven), pump, stub, drv)
    ssys = @test_nowarn mtkcompile(sys)
    sol  = @test_nowarn solve_transient(ssys, [], range(0.0, 0.1, length=20))

    @test sol.retcode == ReturnCode.Success
    # Driven case: T[i] should rise (driver T_w=400 > IC 300), so final > initial
    @test sol[ssys.stub.T[1], end] > sol[ssys.stub.T[1], 1]
end
```

## Pitfalls & Landmines

### The vector-form trap (D-01) — concrete signature

The spike (`/tmp/vec_diagnose3.jl`, 135 lines) compared:
- **`ScalarPort`** (lines 13-18): `@connector function ScalarPort(; name)` with `T_wall(t)`, `h(t)`, `Q(t) [connect = Flow]` as scalars; instantiated as `[ScalarPort(; name=Symbol(:port, i)) for i in 1:n]`. **Works correctly.**
- **`VecWallPort`** (lines 20-25): `@connector function VecWallPort(; name, n)` with `(T_wall(t))[1:n]`, `(h(t))[1:n]`, `(Q(t))[1:n] [connect = Flow]` as vectors; instantiated as a single `@named port = VecWallPort(; n=n)`. **Mis-integrates.**

The bug surfaces as: when both a `VecWallPort`-using system and a `ScalarPort`-using system (or `FlowPort` from STREAM) are compiled in the same Julia session, the **first unknown** of the vector system gets clamped to the connected `T_wall` value at integration time. Symptom: `sol_v.u` shows `[T_w[5], 302.0, 303.0, 304.0, 301.0]` (the IC `301.0` and target `T_w[1]=400` swapped into wrong positions), while `sol_s` shows correct values.

**Why it's an integration-level bug**: `mtkcompile` succeeds, equation count is correct, equations look right under introspection — but the integrator's u-vector position-to-symbolic mapping is broken **only when scalar+vector connectors coexist**. Pure-vector compilation in isolation works. This makes structural-only tests useless for detecting it.

**Document this so it's never re-attempted:** Phase 52's RESEARCH.md, Phase 52's CONTEXT.md (D-01), STATE.md "Key Decisions" `[v1.1 CONN spike, 2026-05-05]` entry, and (per D-15) the smoke-compose test that would re-detect a regression.

### `name` kwarg must remain keyword-only

```julia
# CORRECT (matches FlowPort/ThermalPort)
@connector function WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)

# WRONG — breaks @named macro
@connector function WallPort(name; T_wall=300.0, h=0.0, Q_flow=0.0)
```

The `@named wp = WallPort()` macro expands roughly to `wp = WallPort(; name=:wp)`. Positional `name` would require `WallPort(:wp)` and break every caller. CLAUDE.md "Component authoring conventions" calls this out explicitly: "The `name` kwarg is **always keyword-only** (provided by `@named` macro, never positional)."

### Q_flow = 0 by IC + `[connect = Flow]` rule

MTK's `connect = Flow` semantics: at a junction, the sum of all connected Flow variables equals zero. **For a singly-connected (or unconnected) Flow variable, this means the variable is zero**. So `Q_flow = 0.0` IC default is doubly-correct: (a) numeric default at t=0; (b) MTK's structural rule keeps it zero throughout integration if no other component sources non-zero Flow into the same junction. This is why the smoke test's adiabatic assertion holds without any explicit equation constraining `Q_flow`.

### No new dirs

`src/connectors.jl` is the single file for all MTK connectors (CLAUDE.md File Structure Standard). Plan tasks should NOT propose `mkdir -p src/connectors/` or similar.

### Export rule — single source of truth

`src/STREAM.jl` line 28 (`export FlowPort, ThermalPort`) is the **only** location for export statements. Plan must not add `export` inside `src/connectors.jl`.

### Numeric defaults required

Defaults must be numeric Float64: `T_wall=300.0`, `h=0.0`, `q_flux=0.0`, `Q_flow=0.0`. The sentinel approach (`T_wall=nothing`, detect at compile time) was already discarded (D-07) — MTK doesn't propagate `nothing` through its symbolic IR.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single scalar `ThermalPort` for `Channel` (`thermal::ThermalPort`) | Per-cell array of scalar `WallPort`s for `Channel` (`thermal_left[1:n]`, `thermal_right[1:n]`) | Phase 52 (this phase) defines the connector; Phase 54 rewrites `Channel` to use it | Enables conjugate heat transfer per cell per side; matches `ChannelAndContacts` precedent. |
| Scalar `T_wall` parameter for `ChannelHeatFlux` (`T_wall_p`) | Per-cell array of scalar `HeatFluxPort`s consumed by `ChannelHeatFlux` | Phase 52 defines the connector; Phase 54 rewrites the variant | Allows externally-driven heat flux distributions, including spatially varying boundary conditions from coupled solvers. |
| Vector-form connector spike (rejected) | Array-of-scalar pattern (locked) | 2026-05-05 spike | Avoids first-unknown mis-integration MTK bug; ergonomics handled by `composition/helpers.jl` (Phase 55). |
| Custom `isconnected` probe (discussed, rejected) | IC-default `h=0` / `q_flux=0` adiabatic mechanism | D-06/D-07 (Phase 52 context) | No runtime branches; equations stay plain; Flow rule auto-zeros `Q_flow`. |
| MTK v10 `ODESystem`/`structural_simplify` | MTK v11 `System`/`mtkcompile` | Migrated pre-v0.6 (no Phase 52 impact, just confirming current version) | All test/code uses `mtkcompile`; `System` is the v11 base type. |

**Deprecated/outdated:**
- **Vector-form connectors carrying array variables**: do not re-attempt. Document with the spike write-up; if the bug becomes a Phase-54 design tension, file with MTK upstream at that point (out of v1.1 scope).

[VERIFIED: ModelingToolkit v11.25.0 from Manifest.toml]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| (none) | All claims verified against in-tree code (`src/connectors.jl`, `src/components/`, `test/test_connectors.jl`, `src/STREAM.jl`), the spike artefact at `/tmp/vec_diagnose3.jl`, or CONTEXT.md/STATE.md/CLAUDE.md (project-locked decisions). | — | — |

**No `[ASSUMED]` claims** — Phase 52's design is entirely fixed by D-01..D-19 and the existing codebase. Research is verification of the locked design, not exploration.

## Open Questions (RESOLVED)

None — Phase 52 scope is fully defined. Two minor implementation-detail micro-questions that the planner resolved without further research:

1. **Test grouping order**: RESOLVED — append new testsets *after* the existing CONN-01 (FlowPort) / CONN-02 (ThermalPort) testsets, with disambiguating names ("CONN-01: WallPort instantiation", "CONN-02: HeatFluxPort instantiation", "CONN-04: connect() + smoke"). The existing testset labels are **legacy from earlier project phases** and do **not** match the v1.1 CONN-XX requirement IDs; the planner adds a clarifying comment to the file noting the legacy numbering carries forward.

2. **`_StubRecipient` `m_cp` value**: RESOLVED — `m_cp = 1.0` chosen and used consistently across both adiabatic and driven testsets. Adiabatic case: any positive value works since the RHS evaluates to zero. Driven case: `m_cp=1.0` keeps a `Q_flow` of order 1e5 producing visible drift over the 0.1 s tspan, which the rtol assertion can detect cleanly.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All test/code | ✓ | 1.12.6 (per STATE.md `[v1.1 env, 2026-05-05]`) | — |
| ModelingToolkit | Both new connectors | ✓ | 11.25.0 (Manifest.toml) | — |
| ModelingToolkit `t_nounits` symbol | Connector definitions | ✓ | included in MTK v11 | — |
| `@connector function` macro | New connectors | ✓ | MTK v11 | — |
| `connect = Flow`, `connect = Stream` metadata | Variable annotations | ✓ | MTK v11 | — |
| `OrdinaryDiffEq` (Tsit5) | Smoke test solve | ✓ | already a project dep (Manifest.toml) | — |
| `Symbolics.getmetadata` + `ModelingToolkitBase.VariableConnectType` | Variable-annotation introspection | ✓ | already used in `test_connectors.jl:35-37` | — |
| stdlib `Test` (`@test`, `@testset`, `@test_nowarn`) | All test infrastructure | ✓ | stdlib | — |
| `STREAM.Pump(; mdot0=…)` | Smoke test fixed-flow source | ✓ | `src/components/pump.jl:72-84` | — |
| Pre-built sysimage `stream.so` | Fast iteration only (optional) | depends on host | optional | use `julia --project=. test/runtests.jl` without `--sysimage`; per CLAUDE.md, sysimage may not build on Julia 1.12 + WSL2 anyway |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None — sysimage is optional per CLAUDE.md "Performance — Sysimage" section (Note: PackageCompiler crashes on Julia 1.12 + WSL2; persistent REPL workflow recommended instead).

## Sources

### Primary (HIGH confidence)
- `/home/itayb/projects/STREAM.jl/src/connectors.jl` (24 lines) — exact `@connector function` template for FlowPort and ThermalPort
- `/home/itayb/projects/STREAM.jl/src/STREAM.jl` (96 lines) — module entry point, export list (line 28), include order (line 7)
- `/home/itayb/projects/STREAM.jl/src/components/thermal_channel.jl:48-241` — `ChannelAndContacts` per-cell ThermalPort array pattern; energy-balance shape that Phase 54 will mirror; Q_flow sign convention (D-08)
- `/home/itayb/projects/STREAM.jl/src/components/channel.jl:60-145` — current `Channel` with scalar `ThermalPort` and `instream(port_in.T)` usage
- `/home/itayb/projects/STREAM.jl/src/components/pump.jl:72-84` — `Pump(; name, mdot0=…)` fixed-flow constructor used in smoke target
- `/home/itayb/projects/STREAM.jl/src/composition/helpers.jl:28` — `port(sys, face, i)` accessor
- `/home/itayb/projects/STREAM.jl/test/test_connectors.jl` (83 lines) — existing FlowPort/ThermalPort testset pattern to extend
- `/home/itayb/projects/STREAM.jl/test/test_pump.jl:119-128` — circular-instream pattern with two thermal anchors (relevant landmine)
- `/home/itayb/projects/STREAM.jl/test/runtests.jl:4` — orchestrator confirms `test_connectors.jl` is wired into the suite
- `/home/itayb/projects/STREAM.jl/.planning/phases/52-channel-connectors/52-CONTEXT.md` (149 lines) — D-01..D-19 locked decisions
- `/home/itayb/projects/STREAM.jl/.planning/REQUIREMENTS.md` — CONN-01..04 requirement text
- `/home/itayb/projects/STREAM.jl/.planning/STATE.md` — v1.1 CONN spike entry (2026-05-05) for spike-rejected vector-form context
- `/home/itayb/projects/STREAM.jl/CLAUDE.md` — File Structure Standard, Component authoring conventions, Exports rule, MTK Patterns
- `/tmp/vec_diagnose3.jl` (135 lines) — referenced spike artefact; confirms array-of-scalar success path (lines 13-18, 27-38, 81-90) and vector-form failure mode (lines 20-25, 40-50, 91-95, 100-130)
- `/home/itayb/projects/STREAM.jl/Manifest.toml` — ModelingToolkit version (11.25.0)

### Secondary (MEDIUM confidence)
- `/home/itayb/projects/STREAM.jl/test/` — full test directory grep for `@test_nowarn`, `@test_logs` showing 16+ usages; pattern is project-blessed

### Tertiary (LOW confidence)
- None. All claims are verified against in-tree code, locked CONTEXT.md decisions, or the spike artefact.

## Metadata

**Confidence breakdown:**
- Connector definitions: **HIGH** — directly mirror existing in-tree `ThermalPort` template; numeric defaults locked by D-06/D-07; export location locked by CLAUDE.md
- Architecture (file placement, exports): **HIGH** — CLAUDE.md File Structure Standard is unambiguous; `src/connectors.jl` already canonical; line numbers verified
- Pitfalls (vector-form regression): **HIGH** — verified by spike `/tmp/vec_diagnose3.jl` and STATE.md entry
- Test scaffolding: **HIGH** — existing `test_connectors.jl` already uses inline-stub idiom (lines 17-82); D-11/D-12 lock the approach
- Smoke target design: **HIGH** — D-14/D-15 explicit; pattern matches `test_pump.jl:105-170` closed-loop precedent
- Adiabatic numerical tolerance: **HIGH** — IC default + Flow rule make `Q_flow=0` exact; only solver round-off contributes drift, well within `rtol=1e-8`
- ModelingToolkit version compatibility: **HIGH** — MTK 11.25.0 confirmed; `@connector` macro and `connect = Flow/Stream` metadata are stable v11 API

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days for stable API; would need re-verification only if MTK v12 is released and adopted before Phase 52 lands)

## RESEARCH COMPLETE

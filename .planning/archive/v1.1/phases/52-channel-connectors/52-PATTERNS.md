# Phase 52: Channel Connectors - Pattern Map

**Mapped:** 2026-05-05
**Files analyzed:** 3 (all modified, none created)
**Analogs found:** 3 / 3 (all exact, in-tree)

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `src/connectors.jl` | connector library (MTK acausal port definitions) | event-driven (compile-time topology) | `src/connectors.jl:17-24` (`ThermalPort`) | exact (same file, same macro, same body shape) |
| `src/STREAM.jl` | module entry point (export list) | n/a (declarative) | `src/STREAM.jl:28` (`export FlowPort, ThermalPort`) | exact (same file, same line) |
| `test/test_connectors.jl` | test (structural + integration) | request-response (instantiate → introspect → assert) | `test/test_connectors.jl:17-82` (existing FlowPort/ThermalPort testsets) | exact (same file, same idioms) |

**No new files. No new directories.** All three files already exist; Phase 52 is append-only on `src/connectors.jl` and `test/test_connectors.jl`, and a single-line edit on `src/STREAM.jl`.

## Pattern Assignments

### `src/connectors.jl` — append `WallPort` and `HeatFluxPort` (CONN-01, CONN-02)

**Analog:** `src/connectors.jl:17-24` (`ThermalPort`)

**Anchor for insertion:** end of file (line 24, after `ThermalPort`'s `end`). New code is appended, not interleaved.

**Imports already in scope** (lines 1-5, do NOT re-add):
```julia
using ModelingToolkit
using ModelingToolkit: t_nounits as t
```
Both `@connector` macro and `t` symbol resolve from these existing lines. No new `using` needed.

**Verbatim template — `ThermalPort`** (`src/connectors.jl:17-24`):
```julia
@connector function ThermalPort(; name, T=300.0, Q_flow=0.0)
    sts = @variables begin
        T(t) = T, [description = "Temperature (K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into component"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

**What to copy verbatim** (do NOT improvise on any of these):
1. `@connector function NAME(; name, …)` — `name` is **always keyword-only** (CLAUDE.md "Component authoring conventions"). Never positional.
2. Numeric Float64 IC defaults in the kwarg list (e.g. `T=300.0`, never `T=300`).
3. `sts = @variables begin … end` block.
4. Across-variable form: `VAR(t) = VAR, [description = "..."]` (no `connect = …` metadata for across).
5. Flow-variable form: `VAR(t) = VAR,\n    [connect = Flow, description = "..."]` (note `Q_flow` already uses a multi-line form — preserve it).
6. Body terminator: `System(Equation[], t, sts, []; name=name)` — exact arg order and the empty `Equation[]` / empty parameter `[]` are non-negotiable.

**Output to write — `WallPort`** (CONN-01):
```julia
@connector function WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)
    sts = @variables begin
        T_wall(t) = T_wall, [description = "Wall temperature (K), across variable"]
        h(t) = h, [description = "Heat transfer coefficient (W/m^2·K), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

**Output to write — `HeatFluxPort`** (CONN-02):
```julia
@connector function HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)
    sts = @variables begin
        q_flux(t) = q_flux, [description = "Heat flux density (W/m^2), across variable"]
        Q_flow(t) = Q_flow,
        [connect = Flow, description = "Heat flow rate (W), positive = into channel"]
    end
    System(Equation[], t, sts, []; name=name)
end
```

**Sign convention text** in `Q_flow` description must match `ThermalPort`'s "positive = into component" semantics (D-08, D-10) — using "positive = into channel" wording aligns with the consumer (Phase 54 `Channel`/`ChannelHeatFlux`), and is the same direction.

**Docstrings:** CLAUDE.md "Component authoring conventions" requires `# Arguments` and `# Returns` sections for every exported name. `FlowPort` and `ThermalPort` themselves do **not** currently have docstrings — but they predate the rule. New connectors MUST have them, e.g.:
```julia
"""
    WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)

MTK acausal connector for convective wall coupling: carries wall temperature and
heat-transfer coefficient as across variables, and per-cell heat flow as a Flow variable.
Adiabatic when unconnected (`h=0` IC ⇒ `Q_flow=0` regardless of `T_wall`).

# Arguments
- `name`: connector name (Symbol; keyword-only, supplied by `@named`)
- `T_wall`: wall temperature IC (K, default 300.0)
- `h`: heat transfer coefficient IC (W/m²·K, default 0.0 — adiabatic)
- `Q_flow`: heat flow rate IC (W, default 0.0; positive = into channel)

# Returns
Uncompiled connector `System`. Used as arrays per side per channel:
`[WallPort(; name=Symbol(:thermal_left, i)) for i in 1:n]`.
"""
```
The `HeatFluxPort` docstring follows the same shape with `q_flux` (W/m²) replacing `T_wall`+`h`.

---

### `src/STREAM.jl` — extend export line (D-04 plumbing)

**Analog:** `src/STREAM.jl:28` (current state)

**Current line** (verified by direct read on 2026-05-05):
```julia
export FlowPort, ThermalPort
```

**Replace with**:
```julia
export FlowPort, ThermalPort, WallPort, HeatFluxPort
```

**Plumbing constraints (do NOT touch):**
- Line 7: `include("connectors.jl")` — runs before any component file, so new connectors are visible to all downstream consumers without reordering.
- No `export` statement is added inside `src/connectors.jl` — CLAUDE.md "Exports" rule: all public exports declared in `STREAM.jl` only.
- Lines 27, 29-94 (other `export` lines) are unchanged.

---

### `test/test_connectors.jl` — append stubs + ~14 testsets (CONN-01, CONN-02, CONN-04 coverage)

**Analog A (existing testset shape):** `test/test_connectors.jl:17-82` (FlowPort/ThermalPort testsets — 6 testsets following an identical structural-introspection pattern)

**Analog B (port-array construction inside a stub):** `src/components/thermal_channel.jl:97-98` (`ChannelAndContacts`'s `thermal_left[1:n]`/`thermal_right[1:n]` arrays):
```julia
thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]
thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]
```
Verbatim template for the recipient stub's `WallPort`/`HeatFluxPort` arrays (just swap `ThermalPort` for the new type).

**Analog C (thermal anchors to avoid `circular instream`):** `src/components/channel.jl:115-116`:
```julia
push!(eqs, port_out.T ~ T[n])
push!(eqs, port_in.T  ~ T[1])
```
The recipient stub MUST mirror this verbatim or the smoke compose target will warn (Pitfall 6 in RESEARCH.md). `test/test_pump.jl:121-128` is the alternative anchor pattern (`pump.port_in.T ~ 313.15`, `ine.port_out.T ~ 313.15`); the channel-style internal anchor is cleaner here because the stub *has* internal state `T[i]` to bind to.

**Analog D (smoke-loop closed topology):** `test/test_pump.jl:105-170` (`PUMP-03: Callable pump ramp`) — closed loop with `Pump`, pressure anchor on `pump.port_in.P`, `mtkcompile(sys; …)`, `solve_transient`. Phase 52 mirrors the structure but uses `Pump(; mdot0=0.5)` (fixed-flow) and `_StubRecipient` instead of `Inertia`+`Resistor`.

**Analog E (`Pump` fixed-flow constructor):** `src/components/pump.jl:72-84`:
```julia
function Pump(; name, mdot0)
    pars = @parameters mdot0 = mdot0
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.mdot ~ mdot0,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
```
Used as the FlowPort source in the smoke loop. Constructor consumed via `@named pump = Pump(; mdot0=0.5)`.

**Analog F (`port` accessor, NOT modified):** `src/composition/helpers.jl:28`:
```julia
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
```
Tests that wire `connect(stub.thermal_left1, drv.port1)` use this implicitly via `getproperty`-style names. Stubs construct ports as `Symbol(:thermal_left, i)` so the names align.

**Imports already in scope** (lines 1-5 of `test/test_connectors.jl`, do NOT duplicate):
```julia
using Test
using ModelingToolkit
using STREAM
import STREAM: Channel  # resolve Base.Channel ambiguity
const ModelingToolkitBase = ModelingToolkit.ModelingToolkitBase
```

The new code may need additionally (insert immediately after line 5):
- `using ModelingToolkit: t_nounits as t` — required by stub functions that build `Equation[]` with `Dt = Differential(t)`.
- `using OrdinaryDiffEq: ReturnCode` — required by smoke testset's `@test sol.retcode == ReturnCode.Success`.

(Both are transitively available through `using STREAM` for some symbols, but explicit imports prevent surprises.)

**Variable-annotation introspection idiom** (verbatim from `test/test_connectors.jl:31-48` / `65-82`):
```julia
@testset "CONN-XX: <Connector> <Var> is <kind>" begin
    @named cp = <Connector>()
    var = only(filter(v -> ModelingToolkit.getname(v) == :<varname>, unknowns(cp)))
    connect_type = Symbolics.getmetadata(
        var, ModelingToolkitBase.VariableConnectType, nothing
    )
    @test connect_type == ModelingToolkit.Flow      # for Flow vars
    # OR @test connect_type === nothing             # for across vars (no metadata)
    # OR @test connect_type == ModelingToolkit.Stream  # for Stream vars (FlowPort.T only)
end
```

**Existence/instantiation idiom** (verbatim from `test/test_connectors.jl:17-29` / `53-63`):
```julia
@testset "CONN-XX: <Connector> instantiation" begin
    @named cp = <Connector>()
    var_names = Symbol.(ModelingToolkit.getname.(unknowns(cp)))
    @test :<var1> in var_names
    @test :<var2> in var_names
    # ...
end

@testset "CONN-XX: <Connector> variable count" begin
    @named cp = <Connector>()
    @test length(unknowns(cp)) == <N>
end
```
For `WallPort`: `N=3` (T_wall, h, Q_flow). For `HeatFluxPort`: `N=2` (q_flux, Q_flow).

**Inline stubs to append** (file-local, underscore-prefixed, no `export` — D-11/D-12):

```julia
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
    m_cp = 1.0   # any positive constant — value is irrelevant for adiabatic test
    eqs = Equation[]
    for i in 1:n
        push!(eqs, Dt(T[i]) ~ (thermal_left[i].Q_flow + thermal_right[i].Q_flow) / m_cp)
    end
    # Hydraulic plumbing: pass-through, mirrors src/components/channel.jl:111-116
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

**Smoke testset (CONN-04 instream coexistence)** — based on D-14 + Analog D:
```julia
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

Repeat with `port_type=:flux` for the `HeatFluxPort` smoke (and matching driven variant in the planner's CONN-04 `connect()` testset using `_StubFluxDriver(; n=2, q_v=fill(1e5, 2))`).

**Test-set coverage map (from RESEARCH.md "Phase Requirements → Test Map" — ~14 new testsets):**

| Testset name | Type | What it asserts |
|---|---|---|
| `CONN-01: WallPort instantiation` | structural | `:T_wall`, `:h`, `:Q_flow` present in `unknowns(wp)` |
| `CONN-01: WallPort variable count` | structural | `length(unknowns(wp)) == 3` |
| `CONN-01: WallPort Q_flow is Flow` | structural | `getmetadata(...) == ModelingToolkit.Flow` |
| `CONN-01: WallPort T_wall is across` | structural | `getmetadata(...) === nothing` |
| `CONN-01: WallPort h is across` | structural | `getmetadata(...) === nothing` |
| `CONN-01: stub mtkcompile` | integration | `_StubRecipient(n=2, :wall)` + smoke loop compiles via `@test_nowarn` |
| `CONN-01: adiabatic when unconnected` | behavioural | smoke loop `T[i]` stays at IC (`rtol=1e-8`) |
| `CONN-01: driven case heats stub` | behavioural | `_StubWallDriver(T_w=400, h_v=3000)` raises `T[i]` |
| `CONN-02: HeatFluxPort instantiation` | structural | `:q_flux`, `:Q_flow` present |
| `CONN-02: HeatFluxPort variable count` | structural | `length(unknowns(hfp)) == 2` |
| `CONN-02: HeatFluxPort Q_flow is Flow` | structural | `getmetadata(...) == ModelingToolkit.Flow` |
| `CONN-02: HeatFluxPort q_flux is across` | structural | `getmetadata(...) === nothing` |
| `CONN-02: zero-flux when unconnected` | behavioural | smoke loop with `:flux` stub: `T[i]` stays at IC |
| `CONN-02: driven case heats stub` | behavioural | `_StubFluxDriver(q_v=1e5)` raises `T[i]` |
| `CONN-04: connect() equation count` | structural | recipient + driver compose, equation count > base |
| `CONN-04: instream smoke (WallPort)` | integration | full smoke per D-14 with `port_type=:wall` |
| `CONN-04: instream smoke (HeatFluxPort)` | integration | full smoke per D-14 with `port_type=:flux` |

(The legacy testset names `CONN-01: FlowPort` / `CONN-02: ThermalPort` at lines 17-82 are pre-v1.1 and reuse the same numeric IDs by historical accident — keep them unchanged for CONN-03 non-regression. New testsets distinguish themselves with explicit connector names in the strings.)

**Note on testset numbering collision:** The existing file uses `CONN-01: FlowPort …` and `CONN-02: ThermalPort …` (legacy). Phase 52 introduces new requirement IDs `CONN-01: WallPort …` and `CONN-02: HeatFluxPort …`. Resolution per RESEARCH.md "Open Questions §1": just append the new sections; the differing connector names in the test strings make them unambiguous in test output. The planner may add a clarifying section comment like `# v1.1 CONN-01 (WallPort) below; legacy CONN-01 (FlowPort) above predates the v1.1 requirement IDs`.

---

## Shared Patterns

### Connector definition macro (`@connector function`)

**Source:** `src/connectors.jl:7-15` (`FlowPort`) and `src/connectors.jl:17-24` (`ThermalPort`).

**Apply to:** Both `WallPort` and `HeatFluxPort`.

**The five non-negotiable structural elements** (verified by reading both existing connectors):
```julia
@connector function NAME(; name, KW1=DEFAULT1, KW2=DEFAULT2, …)   # 1. name kwarg-only
    sts = @variables begin
        VAR(t) = VAR, [description = "..."]                        # 2. across var form
        FLOW_VAR(t) = FLOW_VAR,
        [connect = Flow, description = "..."]                      # 3. flow var form (multi-line)
    end                                                            # 4. @variables block
    System(Equation[], t, sts, []; name=name)                      # 5. exact body
end
```

### Numeric Float64 IC defaults

**Source:** `src/connectors.jl:7,17` (`P=1.0e5`, `mdot=0.0`, `T=300.0`, `Q_flow=0.0`)

**Apply to:** All connector kwarg defaults and `@variables` IC defaults.

**Why:** RESEARCH.md Pitfall 4 — `T=300` (Int) silently breaks MTK type inference. `Q_flow=0.0`, `T_wall=300.0`, `h=0.0`, `q_flux=0.0` — never integer literals.

### Test introspection (Symbolics getmetadata)

**Source:** `test/test_connectors.jl:31-48` and `65-82`

**Apply to:** All structural testsets for the new connectors. Use `Symbolics.getmetadata(var, ModelingToolkitBase.VariableConnectType, nothing)`:
- Across var → returns `nothing`
- Flow var → returns `ModelingToolkit.Flow`
- Stream var → returns `ModelingToolkit.Stream` (used by `FlowPort.T` only — not relevant for new connectors).

### Inline test-stub idiom (file-local, no exports)

**Source:** `test/test_connectors.jl` overall structure (no helpers leak outside the file)

**Apply to:** `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`. Place them between the imports (line 5) and the first existing testset (line 10). Prefix `_` per CLAUDE.md "Component authoring conventions"; do NOT add `export` statements.

### Closed-loop smoke compose with `@test_nowarn`

**Source:** `test/test_pump.jl:105-170` (`PUMP-03`) — closed loop with pressure anchor; `test/test_channel.jl:23` and 16 other call sites in the test suite for `@test_nowarn`.

**Apply to:** Both CONN-04 smoke testsets (`WallPort` and `HeatFluxPort` variants).

**Pattern:**
```julia
ssys = @test_nowarn mtkcompile(sys)
sol  = @test_nowarn solve_transient(ssys, op, range(0.0, T_end, length=N))
@test sol.retcode == ReturnCode.Success
@test all(isfinite, sol[ssys.<state>, :])
```

`@test_nowarn` is the project-blessed idiom for asserting "no MTK warnings emitted" — it captures both `circular instream` and `unset stream connection` regressions implicitly.

### Thermal-anchor pattern in stub recipient

**Source:** `src/components/channel.jl:115-116`:
```julia
push!(eqs, port_out.T ~ T[n])
push!(eqs, port_in.T  ~ T[1])
```

**Apply to:** `_StubRecipient`'s equation list. **Required** — without these two equations the smoke loop's `Pump` ↔ `_StubRecipient` closed cycle has no thermal anchor, and `mtkcompile` will warn `circular instream`. RESEARCH.md Pitfall 6 documents this as the highest-probability landmine.

### Indexed port-array construction

**Source:** `src/components/thermal_channel.jl:97-98`:
```julia
thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]
thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]
```

**Apply to:** `_StubRecipient` (with `WallPort` / `HeatFluxPort` swapped in) and `_StubWallDriver` / `_StubFluxDriver` (using `Symbol(:port, i)` as in the RESEARCH.md sketch).

The naming convention `Symbol(:thermal_left, i)` produces `:thermal_left1`, `:thermal_left2`, … which are exactly the property names `port(sys, :thermal_left, i)` returns (see `src/composition/helpers.jl:28`). Stubs that connect to these via `connect(stub.thermal_left1, drv.port1)` will resolve cleanly.

---

## No Analog Found

None. Every Phase-52 modification has a verified, in-tree analog (`ThermalPort` for connectors, existing CONN-01/02 testsets for structural tests, `PUMP-03` for the closed-loop smoke pattern, `Channel`/`ChannelAndContacts` for stub-recipient wiring).

---

## Metadata

**Analog search scope:** `src/connectors.jl`, `src/STREAM.jl`, `src/components/{channel,thermal_channel,pump}.jl`, `src/composition/helpers.jl`, `test/{test_connectors,test_pump,runtests}.jl`.

**Files scanned:** 8 (all in-tree). Read with non-overlapping ranges per CLAUDE.md instruction.

**Pattern extraction date:** 2026-05-05

**Confidence:** HIGH — all extracted excerpts are verbatim from in-tree code; no reconstruction or paraphrasing.

**Spike artefact:** `/tmp/vec_diagnose3.jl` is referenced by RESEARCH.md as the source of D-01's vector-form rejection but is **not** an analog — it is exploratory code that documents the failure mode the smoke test must catch. Do not promote into the test suite (D-12).

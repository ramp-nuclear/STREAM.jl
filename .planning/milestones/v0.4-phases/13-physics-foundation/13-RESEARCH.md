# Phase 13: Physics Foundation - Research

**Researched:** 2026-03-14
**Domain:** Julia struct redesign (PipeGeometry), MTK equation construction (Pump dual-mode), test migration and reference constant regeneration
**Confidence:** HIGH

## Summary

Phase 13 has two tightly scoped changes: (1) replace the sentinel-kwargs `PipeGeometry` constructor with a redesigned struct that stores `wet_perimeter` and derives `Dh = 4A/wet_perimeter`, adding factory constructors mirroring Python's `EffectivePipe`; and (2) extend `Pump` to accept a `mdot0` kwarg that constrains mass flow instead of pressure.

The Dh fix is a breaking geometry change. The current test code passes `Dh=0.01` (a 10 mm circular value) to all VAL-01/02/03 MTR scenarios. After the fix, the correct rectangular Dh for the MTR channel (edge1=0.07 m, edge2=0.00127 m) is ~2.495 mm — a factor of 4 smaller. This shifts Re, Nu, h_tc, and the resulting outlet temperatures and mass flows. All VAL-01/02/03 reference constants must be regenerated from Python STREAM using `EffectivePipe.rectangular(length=0.6, edge1=0.07, edge2=0.00127, heated_edge=0.07)` after the struct change is in place.

The Pump change is purely additive. The existing `dP_pump` path is unchanged; the new `mdot0` path adds one MTK equation (`port_in.mdot ~ mdot0`), removes the pressure equation, and requires the test loop to supply a separate pressure anchor (e.g., an `HeatExchanger` or a pressure node).

**Primary recommendation:** Implement PipeGeometry redesign first (Plan 01), then Pump dual-mode + reference constant regeneration (Plan 02). The two are separable but regenerating reference constants requires the new struct to be in place.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**PipeGeometry struct fields**
- Store `heated_perimeter`, `wet_perimeter`, `area`, `heated_parts`, `Dh`, `L` as struct fields
- `Dh` is always derived: `4 * area / wet_perimeter` — never caller-provided
- Old sentinel-kwargs constructor `PipeGeometry(; L, D=nothing, Dh=nothing, A=nothing, y=nothing)` is DELETED

**Factory constructors**
- `PipeGeometry.rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)`:
  - `area = edge1 * edge2`
  - `wet_perimeter = 2*(edge1 + edge2)`
  - `Dh = 4*area / wet_perimeter`
  - `heated_parts`: `one_sided=nothing` → `(heated_edge, heated_edge)`, `one_sided=:left` → `(heated_edge, 0.0)`, `one_sided=:right` → `(0.0, heated_edge)`
  - `heated_perimeter`: `2*heated_edge` (two-sided) or `heated_edge` (one-sided)
- `PipeGeometry.circular(L, D)`:
  - `area = π*D²/4`, `wet_perimeter = π*D`, `heated_perimeter = π*D`, `Dh = D`
- Exact Julia idiom (submodule, standalone functions, or inner constructors) is **Claude's discretion**

**Call site migration**
- All ~20 existing uses of `PipeGeometry(; L, D=...)` → `PipeGeometry.circular(L, D)` (or equivalent idiom)
- All uses of `PipeGeometry(; L, Dh, A, y)` → `PipeGeometry.rectangular(L, edge1, edge2, heated_edge)` with correct physical dims
- No backward-compatibility shims

**MTR reference constant update**
- After Dh fix, VAL-01/02/03 reference constants shift
- Strategy: regenerate from Python STREAM with correct MTR geometry; hardcode updated values in Julia tests (rtol=1%)
- Same approach as v0.3

**Pump dual-mode**
- `Pump(; name, dP_pump=nothing, mdot0=nothing)` — sentinel dispatch
- Fixed-pressure mode (`dP_pump !== nothing`): existing behavior unchanged
- Fixed-flow mode (`mdot0 !== nothing`): adds `port_in.mdot ~ mdot0`; does NOT add pressure equation — caller provides pressure anchor
- Error if both or neither provided
- Test: after solve, `sol[pump.port_in.mdot] ≈ mdot0` (rtol=1e-4)

### Claude's Discretion

- Exact Julia idiom for factory constructors (submodule, standalone functions, inner constructors)
- Whether to store `heated_diameter` as a field (defer unless needed)
- `width` and `depth` fields — omit (out of scope v0.4)

### Deferred Ideas (OUT OF SCOPE)

- `heated_diameter` as a separate field (4A/heated_perimeter)
- `width` and `depth` fields (Sudo-Kaminaga CHF, Elenbaas correlation)
- `one_sided` geometry used in `one_sided_connection` assembly — Phase 15
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PHY-01 | PipeGeometry has `wet_perimeter` field; `Dh = 4A / wet_perimeter`; rectangular constructor computes `wet_perimeter = 2*(edge1 + edge2)` | Fully specified in CONTEXT.md; Python `EffectivePipe.rectangular` is the reference implementation; exact field layout and constructor semantics are locked |
| PHY-05 | `Pump(mdot0=...)` fixed-flow mode adds constraint `port_in.mdot ~ mdot0` instead of fixed-pressure equation | Additive change to existing `Pump`; sentinel-kwargs pattern already established in codebase; only one new MTK equation needed |
</phase_requirements>

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | (project version) | MTK System/equation construction for Pump | Already the project's equation-building framework |
| Julia structs | built-in | `PipeGeometry` is a plain `struct` — no MTK involvement | Geometry is pure data; MTK sees it only at component-construction time |

### Established Project Patterns

| Pattern | Where Used | Apply In Phase 13 |
|---------|-----------|-------------------|
| Sentinel-kwargs dispatch | `PipeGeometry` old constructor, to be deleted; pattern carries to `Pump` dual-mode | `Pump(; dP_pump=nothing, mdot0=nothing)` with `if/elseif/else` branch |
| `@named` components + `compose()` | All channel/pump constructors | Pump unchanged; no compose() change needed |
| `build_initializeprob=false` | Coupled HeatDiffusion+CAC | Unchanged; carry forward |
| Reference constants from Python STREAM | VAL-01/02/03 | Regenerate after Dh fix |

### No New Dependencies

Phase 13 introduces no new Julia packages. All changes are in `src/components.jl` and `test/runtests.jl`.

---

## Architecture Patterns

### Recommended Project Structure

No directory changes. All changes land in:
```
src/
└── components.jl    # PipeGeometry struct + factory constructors + Pump dual-mode

test/
├── runtests.jl      # migrate all PipeGeometry call sites; update VAL reference constants
└── generate_mtr_reference.py   # update to use EffectivePipe.rectangular; re-run to get new constants
```

### Pattern 1: Julia Factory Constructor Idiom

**What:** Julia cannot have classmethods on a struct. The closest idiomatic options are:

**Option A — Standalone functions (simplest, most idiomatic):**
```julia
# Naming: PipeGeometry_rectangular / PipeGeometry_circular
function PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)
    area          = edge1 * edge2
    wet_perimeter = 2 * (edge1 + edge2)
    Dh            = 4 * area / wet_perimeter
    heated_perimeter, heated_parts = if one_sided === nothing
        (2*heated_edge, (heated_edge, heated_edge))
    elseif one_sided === :left
        (heated_edge, (heated_edge, 0.0))
    elseif one_sided === :right
        (heated_edge, (0.0, heated_edge))
    else
        error("one_sided must be :left, :right, or nothing")
    end
    PipeGeometry(Float64(L), Dh, Float64(area), heated_perimeter, wet_perimeter, heated_parts)
end
```

**Option B — Submodule trick (matches Python's `PipeGeometry.rectangular(...)` call syntax):**
```julia
# Inner module provides .rectangular / .circular as fields of a module named PipeGeometry
# This is unusual Julia style and adds confusion; not recommended.
```

**Option C — Inner constructors with type-tag dispatch:**
```julia
# Not viable: Julia inner constructors cannot be named differently from the type.
```

**Recommendation:** Option A (standalone functions `PipeGeometry_rectangular` / `PipeGeometry_circular`) is the most idiomatic Julia. The call site reads clearly. CONTEXT.md explicitly says "Planner decides the exact Julia idiom — the semantics above are fixed", so the planner should pick Option A unless they have a specific reason for Option B.

**When to use:** All new call sites use `PipeGeometry_rectangular(...)` or `PipeGeometry_circular(...)`. Old `PipeGeometry(; L, D=...)` calls are deleted.

### Pattern 2: New PipeGeometry Struct Layout

The struct gains two new fields (`heated_perimeter`, `wet_perimeter`) and `Dh` moves from caller-provided to derived:

```julia
struct PipeGeometry
    L                ::Float64
    Dh               ::Float64                # derived: 4*area / wet_perimeter
    A                ::Float64
    heated_perimeter ::Float64                # new
    wet_perimeter    ::Float64                # new (PHY-01 requirement)
    heated_parts     ::NTuple{2,Float64}
end
```

**Key constraint:** All existing channel constructors access `geometry.Dh`, `geometry.A`, `geometry.L`, `geometry.heated_parts`. They do NOT access `wet_perimeter` or `heated_perimeter` directly — those are only needed for the Dh computation and for future use. No changes to `Channel`, `ChannelAndContacts`, `ChannelHeatFlux`, `_channel_base_eqs`.

### Pattern 3: Pump Dual-Mode Sentinel Dispatch

```julia
function Pump(; name, dP_pump=nothing, mdot0=nothing)
    if dP_pump !== nothing && mdot0 === nothing
        # existing fixed-pressure path — unchanged
        pars = @parameters dP_pump = dP_pump
        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        eqs = Equation[
            port_in.mdot + port_out.mdot ~ 0,
            port_out.P - port_in.P ~ dP_pump,
            port_out.T ~ instream(port_in.T),
            port_in.T  ~ instream(port_out.T),
        ]
        compose(System(eqs, t, [], pars; name=name), port_in, port_out)
    elseif mdot0 !== nothing && dP_pump === nothing
        # new fixed-flow path
        pars = @parameters mdot0 = mdot0
        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        eqs = Equation[
            port_in.mdot + port_out.mdot ~ 0,
            port_in.mdot ~ mdot0,              # fixes mass flow; no pressure equation
            port_out.T ~ instream(port_in.T),
            port_in.T  ~ instream(port_out.T),
        ]
        compose(System(eqs, t, [], pars; name=name), port_in, port_out)
    else
        error("Pump: provide exactly one of `dP_pump` or `mdot0`")
    end
end
```

**Pressure anchor requirement:** The fixed-flow Pump provides no pressure reference. A loop using `Pump(mdot0=...)` needs an `HeatExchanger` (which has `port_in.P - port_out.P ~ 0`) or an explicit pressure node to close the system. The simplest test topology is: `Pump(mdot0=0.6)` → `HeatExchanger(T_bc=313.15)` → `Channel(...)` → (back to pump), where the HeatExchanger provides `P_out.P - port_in.P ~ 0` and the overall loop pressure is anchored by a reference `P_abs` parameter in the channel (matching the existing `solve_steady` pattern).

Actually, examining `build_loop` in `solvers.jl` will clarify what reference pressure anchor is needed. The key point: `Pump(dP_pump)` drives dP but the loop needs an absolute pressure reference elsewhere; same architecture applies to `Pump(mdot0)`.

### Pattern 4: Existing Call Site Count and Migration Map

Grep results show these `PipeGeometry(...)` call sites to migrate:

| Location | Current Call | Migrate To |
|----------|-------------|------------|
| `COMP-01` tests (×3) | `PipeGeometry(L=1.0, D=0.01)` | `PipeGeometry_circular(1.0, 0.01)` |
| `THERM-01` tests (×3) | `PipeGeometry(L=1.0, D=0.01)` | `PipeGeometry_circular(1.0, 0.01)` |
| `THERM-02` test | `PipeGeometry(L=1.0, D=0.01)` | `PipeGeometry_circular(1.0, 0.01)` |
| `THERM-03` tests (×2) | `PipeGeometry(L=L_ch, D=D_ch, A=A_ch)` | `PipeGeometry_circular(L_ch, D_ch)` — note A is dropped (derived from D) |
| `CHAN-01` tests (×2) | `PipeGeometry(L=1.0, D=0.01)` | `PipeGeometry_circular(1.0, 0.01)` |
| VAL-01 test | `PipeGeometry(L=0.6, Dh=0.01, A=7.85e-5, y=0.07)` | `PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)` |
| VAL-02 test | same as VAL-01 (×2) | same migration (×2) |
| VAL-03 test | same as VAL-01 | same migration |

**Note on `D_ch` tests with explicit `A=A_ch`:** The old constructor accepted an optional `A` override for circular geometry. The new `PipeGeometry_circular` derives `A = π*D²/4` automatically. For tests where `A_ch = 7.85e-5` was manually specified to match `π*(0.01)²/4 ≈ 7.854e-5`, the computed value will match within floating-point tolerance — no behavior change. One test uses `D_cac = 0.02` with `A_ch = 7.85e-5` (deliberate mismatch — old non-circular area with `D=0.02`). This call must be reviewed: the test may have been intentionally using a geometry inconsistency, or it may need a dedicated rectangular call. The planner should flag this for inspection.

### Anti-Patterns to Avoid

- **Do not add `heated_diameter` field:** Deferred. Only `wet_perimeter` is required for PHY-01.
- **Do not add a backward-compatibility shim for the old constructor:** Clean break per locked decision. Any missed call site will produce a clean Julia `MethodError`.
- **Do not make Pump(mdot0) add a pressure equation:** The fixed-flow Pump provides only the mdot constraint. Adding a pressure equation would overdetermine the system.
- **Do not change `_channel_base_eqs` or channel constructors:** They read `geometry.Dh`, which remains a field. No changes needed there.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dh derivation | Custom formula inline in struct | Standard `4A/wet_perimeter` computed once at construction | Formula is the hydraulic diameter definition; derive once, store as field |
| Reference constant generation | Manually compute expected T_out/mdot | Run `generate_mtr_reference.py` with updated `EffectivePipe.rectangular` geometry | Python STREAM is the authoritative reference; manual calculation risks mistakes |
| Pressure closure in mdot0 test | Custom pressure anchor component | Reuse existing `HeatExchanger` (P drop = 0) or `build_loop` pattern | Existing infrastructure already closes pressure loops correctly |

---

## Common Pitfalls

### Pitfall 1: Misidentifying edge1/edge2 for MTR rectangular geometry

**What goes wrong:** The test code currently uses `Dh=0.01` for the MTR channel, which was a circular approximation. The correct rectangular geometry uses `edge1=0.07` (plate width) and `edge2=0.00127` (gap = Lx from HeatDiffusion). If the wrong edges are used, `Dh` will be wrong.

**Why it happens:** The gap dimension `0.00127` = `Lx` appears in HeatDiffusion constructor as `Lx=0.00127` but is not explicitly stated as the channel gap in older tests. The connection is: the fuel plate thickness `Lx` = the gap between plate surfaces = channel gap `edge2`.

**How to avoid:** Use `edge1=0.07, edge2=0.00127` consistently. Verify: `Dh = 4*(0.07*0.00127)/(2*(0.07+0.00127)) = 0.002495 m ≈ 2.495 mm`.

**Warning signs:** If computed `Dh ≈ 0.01` after the fix, something is wrong.

### Pitfall 2: Reference constant shift breaks existing tests before regeneration

**What goes wrong:** If the PipeGeometry struct is changed (Plan 01) but VAL-01/02/03 reference constants are not yet updated, all three VAL tests will fail. This is expected during the Plan 01 → Plan 02 transition.

**Why it happens:** The new `Dh ≈ 2.5 mm` vs old `Dh = 10 mm` changes Re by ~4x, Nu significantly, h_tc, and therefore T_out and mdot.

**How to avoid:** Plan 01 updates the struct and migrates call sites. Plan 02 regenerates reference constants and updates test assertions. The split is intentional — Plan 01 "breaks" VAL tests knowingly; Plan 02 repairs them with correct values.

### Pitfall 3: Circular geometry A override in THERM-03 test

**What goes wrong:** One test uses `PipeGeometry(L=L_ch, D=D_cac, A=A_ch)` where `D_cac=0.02` but `A_ch=7.85e-5` (area of a D=0.01 circle). This was a deliberate geometry inconsistency test. The new `PipeGeometry_circular` derives A automatically, so `A = π*(0.02)²/4 = 3.14e-4 m²` — very different.

**How to avoid:** Read the test intent carefully before migrating. If the test is testing specific behavior with a non-standard A, it may need `PipeGeometry_rectangular` with explicit edge dimensions, or the test assertion should be updated. The planner must inspect this call specifically.

### Pitfall 4: Pump(mdot0) test needs a pressure anchor

**What goes wrong:** A loop with only `Pump(mdot0=...)` has no absolute pressure reference. MTK will fail to compile (singular system) or produce degenerate pressure values.

**Why it happens:** The fixed-flow Pump provides `port_in.mdot ~ mdot0` but removes the `port_out.P - port_in.P ~ dP_pump` equation. There is now one fewer pressure constraint in the loop.

**How to avoid:** Include an `HeatExchanger` (which has `port_in.P - port_out.P ~ 0`) in the test loop with `funcs={..., p_abs=1e5}` or equivalent. The `solve_steady` call should pass an absolute pressure condition via the `p_abs` parameter on the channel. This is the same pattern already used in all existing loop tests.

### Pitfall 5: `heated_parts` sum check

**What goes wrong:** Python `EffectivePipe` asserts `sum(heated_parts) == heated_perimeter`. Julia does not enforce this unless explicitly added. For two-sided: `sum((heated_edge, heated_edge)) = 2*heated_edge = heated_perimeter` ✓. For one-sided: `sum((heated_edge, 0.0)) = heated_edge = heated_perimeter` ✓. No runtime assertion is strictly needed, but the planner may choose to add a @assert in the factory constructor.

---

## Code Examples

### Correct Dh Computation for MTR Rectangular Channel

```julia
# Source: Python EffectivePipe.rectangular (pipe_geometry.py lines 91-132)
# MTR geometry: plate width 70mm, gap 1.27mm
edge1 = 0.07     # m (plate width = heated_edge)
edge2 = 0.00127  # m (channel gap = Lx from HeatDiffusion)

wet_perimeter    = 2 * (edge1 + edge2)    # = 0.14254 m
area             = edge1 * edge2           # = 8.89e-5 m²
Dh               = 4 * area / wet_perimeter  # = 0.002495 m (2.495 mm)
heated_perimeter = 2 * 0.07               # = 0.14 m (two-sided)
```

### PipeGeometry_rectangular factory constructor (skeleton)

```julia
function PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)
    area          = Float64(edge1) * Float64(edge2)
    wet_perimeter = 2.0 * (Float64(edge1) + Float64(edge2))
    Dh            = 4.0 * area / wet_perimeter
    if one_sided === nothing
        heated_perimeter = 2.0 * Float64(heated_edge)
        heated_parts     = (Float64(heated_edge), Float64(heated_edge))
    elseif one_sided === :left
        heated_perimeter = Float64(heated_edge)
        heated_parts     = (Float64(heated_edge), 0.0)
    elseif one_sided === :right
        heated_perimeter = Float64(heated_edge)
        heated_parts     = (0.0, Float64(heated_edge))
    else
        error("one_sided must be :left, :right, or nothing; got $one_sided")
    end
    PipeGeometry(Float64(L), Dh, area, heated_perimeter, wet_perimeter, heated_parts)
end
```

### PipeGeometry_circular factory constructor (skeleton)

```julia
function PipeGeometry_circular(L, D)
    _D               = Float64(D)
    area             = π * _D^2 / 4
    perimeter        = π * _D
    PipeGeometry(Float64(L), _D, area, perimeter, perimeter, (perimeter/2, perimeter/2))
    # Note: Dh = D for circular (4*(π*D²/4)/(π*D) = D); heated_parts mirrors Python EffectivePipe.circular
end
```

**Attention:** Python `EffectivePipe.circular` sets `heated_parts = (perimeter, 0.0)` (all heat on one side by convention). The existing Julia `PipeGeometry(D=...)` sets `heated_parts = (π*D/2, π*D/2)` (split evenly). CONTEXT.md says circular should have `heated_perimeter=π*D`. The planner must decide which `heated_parts` to use for circular. The existing Channel and ChannelAndContacts use `sum(geometry.heated_parts)` and `geometry.heated_parts[1]`/`[2]` respectively. For circular with single ThermalPort (`Channel`), the sum is what matters (`π*D`). For `ChannelAndContacts` which has separate left/right ports, `(π*D/2, π*D/2)` is more natural. Python uses `(perimeter, 0.0)` but that asymmetry would break `ChannelAndContacts` semantics. Recommend keeping the existing split `(π*D/2, π*D/2)` for Julia circular.

### Pump dual-mode test topology (fixed-flow)

```julia
# Test: fixed-flow pump, loop with HeatExchanger as pressure anchor
@named pump = Pump(mdot0=0.6)
@named bc   = HeatExchanger(T_bc=313.15)
@named ch   = Channel(n=5, geometry=PipeGeometry_circular(0.6, 0.01))
conns = [
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out,   ch.port_in),
    connect(ch.port_out,   pump.port_in),
]
@named sys = System(conns, t, systems=[pump, bc, ch])
ssys = mtkcompile(sys)
# solve_steady needs p_abs; mdot initial guess should be mdot0
prob = ODEProblem(ssys, [ch.T => fill(313.15, 5)], (0.0, 1e6), [])
sol  = solve(prob, ...)
@test isapprox(sol[ssys.pump.port_in.mdot], 0.6; rtol=1e-4)
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `PipeGeometry(; L, D=nothing, Dh=nothing, ...)` sentinel kwargs | `PipeGeometry_rectangular(...)` / `PipeGeometry_circular(...)` factory functions | Phase 13 | All ~20 call sites migrate; clean break |
| `Dh` caller-provided (`Dh=0.01` for MTR) | `Dh` derived: `4*area/wet_perimeter` ≈ 2.495 mm for MTR | Phase 13 | Re drops ~4x; Nu and h_tc shift; VAL reference constants change |
| `Pump(; name, dP_pump)` only | `Pump(; name, dP_pump=nothing, mdot0=nothing)` sentinel dispatch | Phase 13 | Fixed-flow capability added; existing tests unaffected |

**Deprecated after Phase 13:**
- `PipeGeometry(; L, D, ...)` constructor: deleted, no shim
- `PipeGeometry(; L, Dh, A, y)` constructor: deleted, no shim

---

## Open Questions

1. **THERM-03 geometry inconsistency test (`D_cac=0.02, A=7.85e-5`)**
   - What we know: current test at line ~572 uses `D_cac=0.02` but `A_ch=7.85e-5` (area of D=0.01 circle) — intentional inconsistency to test Dh-independent behavior
   - What's unclear: is this test intentionally testing with a non-physical geometry, or was it a copy-paste error?
   - Recommendation: planner reads the test's intent and decides: either use `PipeGeometry_circular(L_ch, D_cac)` (A becomes 3.14e-4) and update expected T_out assertion, or replace with a rectangular call. Do not silently keep the old inconsistency.

2. **Python `EffectivePipe.circular` uses `heated_parts=(perimeter, 0.0)` but Julia uses `(π*D/2, π*D/2)`**
   - What we know: Python puts all heat on "left" side by convention; Julia splits evenly; both give same total `heated_perimeter = π*D`
   - What's unclear: does any future phase code rely on left/right split of circular?
   - Recommendation: keep Julia's existing split `(π*D/2, π*D/2)` — it matches `ChannelAndContacts` symmetry expectations. Document the deviation from Python.

3. **Pressure anchor idiom for `Pump(mdot0)` integration test**
   - What we know: fixed-flow Pump removes the dP equation; needs absolute pressure closure
   - What's unclear: whether `solve_steady` helper or raw `ODEProblem` is better for this test
   - Recommendation: use same `solve_steady` + `build_loop` pattern as existing tests; pass `p_abs` via funcs dict

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + Test.jl (project standard) |
| Config file | none — single `test/runtests.jl` |
| Quick run command | `julia --project=. -e "using Pkg; Pkg.test()"` |
| Full suite command | `julia --project=. -e "using Pkg; Pkg.test()"` (same — single file) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PHY-01 | `PipeGeometry_rectangular(0.6, 0.07, 0.00127, 0.07)` computes `Dh ≈ 0.002495 m`; `wet_perimeter ≈ 0.14254 m`; field readable | unit | `julia --project=. -e "using Pkg; Pkg.test()"` filtered to PHY-01 testset | ❌ Wave 0 — new testset |
| PHY-01 | `PipeGeometry_circular(0.6, 0.01)` gives `Dh = 0.01`; `wet_perimeter = π*0.01` | unit | same | ❌ Wave 0 — new testset |
| PHY-01 | All existing COMP-01/THERM-01/THERM-02/CHAN-01 tests still pass after call site migration | regression | same | ✅ exists (migrate call sites only) |
| PHY-01 | VAL-01/02/03 quantitative assertions pass with regenerated reference constants | integration | same | ✅ exists (update constants only) |
| PHY-05 | `Pump(mdot0=0.6)` assembles and compiles | unit | same | ❌ Wave 0 — new testset |
| PHY-05 | Loop with `Pump(mdot0=0.6)` solves; `sol[pump.port_in.mdot] ≈ 0.6` (rtol=1e-4) | integration | same | ❌ Wave 0 — new testset |
| PHY-05 | `Pump(dP_pump=1e5)` still works (regression) | regression | same | ✅ exists (unchanged) |
| PHY-05 | `Pump(dP_pump=1e5, mdot0=0.6)` errors; `Pump()` errors | unit | same | ❌ Wave 0 — new testset |

### Sampling Rate
- **Per task commit:** `julia --project=. -e "using Pkg; Pkg.test()"`
- **Per wave merge:** same (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — add `@testset "PHY-01: PipeGeometry_rectangular geometry"` block
- [ ] `test/runtests.jl` — add `@testset "PHY-01: PipeGeometry_circular geometry"` block
- [ ] `test/runtests.jl` — add `@testset "PHY-05: Pump fixed-flow mode"` block
- [ ] `test/runtests.jl` — add `@testset "PHY-05: Pump error cases"` block
- [ ] `test/generate_mtr_reference.py` — update `pipe_ch` from `EffectivePipe(...)` manual to `EffectivePipe.rectangular(0.6, 0.07, 0.00127, 0.07)` and re-run to capture new reference constants

---

## Sources

### Primary (HIGH confidence)
- `/home/itay/projects/Julia-STREAM/src/components.jl` — existing `PipeGeometry` struct and all channel constructors; exact fields, `_channel_base_eqs` interface
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — all existing `PipeGeometry(...)` call sites; VAL-01/02/03 reference constants and test structure
- `/home/itay/projects/STREAM/stream/pipe_geometry.py` — Python `EffectivePipe` class; authoritative definition of `rectangular()` and `circular()` classmethods; field semantics
- `.planning/phases/13-physics-foundation/13-CONTEXT.md` — locked decisions for all Phase 13 behavior

### Secondary (MEDIUM confidence)
- Manual Dh calculation verified: `4*(0.07*0.00127)/(2*(0.07+0.00127)) = 0.002495 m` ✓
- `heated_parts` for circular: deviation from Python (`(perimeter, 0.0)`) versus Julia existing (`(π*D/2, π*D/2)`) documented above

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all patterns from existing codebase
- Architecture: HIGH — struct layout and factory constructors directly from Python reference + CONTEXT.md locked decisions
- Pitfalls: HIGH — confirmed from reading actual test code and computing geometry values directly
- Reference constant magnitude: HIGH — computed numerically (`Dh ≈ 2.495 mm` vs old `10 mm`)

**Research date:** 2026-03-14
**Valid until:** 90 days (stable domain; only internal codebase changes)

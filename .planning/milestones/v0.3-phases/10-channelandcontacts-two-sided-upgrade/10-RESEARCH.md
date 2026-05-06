# Phase 10: ChannelAndContacts Two-Sided Upgrade - Research

**Researched:** 2026-03-14
**Domain:** ModelingToolkit v11 acausal thermal ports, Julia component refactoring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Energy balance formula (two-sided):**
- Use explicit h_tc formula per side: `h_tc[i] * (π*Dh/2) * dz * (thermal_left[i].T - T[i]) + h_tc[i] * (π*Dh/2) * dz * (thermal_right[i].T - T[i])`
- Heated perimeter split: symmetric, each side gets `π*Dh/2` (hardcoded for Phase 10; full geometry refactor deferred to Phase 10.5)
- `q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow` (total per cell)
- `Q_wall_total ~ sum(q_wall[i])` — unchanged semantics, now sums both sides

**Observables:**
- `q_wall[i]`: total per-cell heat (left + right combined) — no per-side observable arrays
- Per-side Q_flow accessible directly via port if needed: `sys.ch.thermal_left[i].Q_flow`

**Port naming convention:**
- New arrays: `thermal_left = [ThermalPort(name=Symbol(:thermal_left, i)) for i in 1:n]` and `thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]`
- MTK subsystem names: `thermal_left1, thermal_left2, ..., thermal_leftN` and `thermal_right1, ..., thermal_rightN`
- `thermal_ports` (old name) removed completely from codebase — no alias, no backward compat shim
- `compose(...)` call splats both arrays: `compose(sys, inlet, outlet, thermal_left..., thermal_right...)`

**THERM-01 test update:**
- Replace `Symbol(:thermal, i) in subsys_names` with `Symbol(:thermal_left, i)` and `Symbol(:thermal_right, i)` checks
- Old thermal1..N assertions removed entirely

**THERM-03 rewrite:**
- Replace current ChannelHeatFlux-vs-Channel comparison with: one-sided ChannelAndContacts (thermal_left connected to `T_wall`, thermal_right unconnected/adiabatic) compared against ChannelHeatFlux
- To equalize heated perimeters: set `D_cac = 2 * D_chf` so `π*D_cac/2 = π*D_chf` (one-sided cac heats at the same rate as chf)
- Tolerance: 0.1% match on T_outlet
- Boundary condition: `ConstantTemperature` component pins `thermal_left[i].T = T_wall` for each cell
- Phase 10 adds `ConstantTemperature` to components.jl if it doesn't already exist (trivial: `thermal.T ~ T_bc`, single ThermalPort)
- This test also implicitly validates CHAN-03 (adiabatic default): `thermal_right[i].Q_flow == 0` at steady state

**Tech debt cleanup:**
- DEBT-01: Remove `t_inlet` parameter from `_channel_base_eqs` signature; `T_inlet = instream(inlet.T)` is computed at call site, not passed as argument; update all call sites
- DEBT-02: THERM-03 now directly tests ChannelAndContacts (see above)
- DEBT-03: Fix cosmetic doc issue in `09-01-SUMMARY.md`

### Claude's Discretion

- Exact MTK compose() call order for the two port arrays
- Whether to add `ConstantTemperature` to the public exports in STREAM.jl
- Test parameter values for the new THERM-03 loop (L, D, n, T_inlet, T_wall, dP_pump)

### Deferred Ideas (OUT OF SCOPE)

- **Phase 10.5: PipeGeometry struct** — introduce a `PipeGeometry` struct (analogous to Python STREAM's `EffectivePipe`) with fields `L, Dh, A, heated_perimeter, heated_parts::NTuple{2,Float64}` and factory functions `PipeGeometry.rectangular(L, depth, width)` / `PipeGeometry.circular(L, D)`. Full constructor API refactor for all channel components.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DEBT-01 | `_channel_base_eqs` callable without `t_inlet` argument; all call sites updated | Current signature at line 204-207 in components.jl includes `t_inlet` kwarg; it is passed in at lines 282-283 and 346-348 — two call sites to update |
| DEBT-02 | THERM-03 directly tests ChannelAndContacts behavioral output | Current THERM-03 (lines 511-543) compares ChannelHeatFlux vs Channel; must be replaced with CAC vs ChannelHeatFlux one-sided test |
| DEBT-03 | Cosmetic doc fix in `09-01-SUMMARY.md` | No code impact; trivial edit |
| CHAN-01 | ChannelAndContacts exposes `thermal_left[1:n]` + `thermal_right[1:n]`; old `thermal_ports` gone | Current CAC at lines 274+302 uses `thermal_ports` with `Symbol(:thermal, i)` naming; full replacement required |
| CHAN-02 | `q_wall[i]` equals `thermal_left[i].Q_flow + thermal_right[i].Q_flow` | Current `q_wall[i] ~ thermal_ports[i].Q_flow` (line 293); replace with two-port sum |
| CHAN-03 | Unconnected side defaults to adiabatic (Q_flow=0); verified by test | MTK Flow variable semantics: unconnected Flow variable defaults to 0 — adiabatic is automatic, but must be verified by explicit test asserting `thermal_right[i].Q_flow == 0` |
</phase_requirements>

---

## Summary

Phase 10 is a targeted refactoring of `ChannelAndContacts` with three tightly coupled work streams: (1) replace the single `thermal_ports[1:n]` array with dual `thermal_left[1:n]` + `thermal_right[1:n]` arrays and update the energy balance for symmetric two-sided heating, (2) clear three items of v0.2 tech debt, and (3) rewrite THERM-03 to test ChannelAndContacts directly using a new `ConstantTemperature` boundary component.

The codebase is well-prepared for this change. The `ThermalPort` connector requires no modification — it already carries `T` (across) and `Q_flow` (Flow). The port-array pattern (`[ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]`) and splat-compose pattern (`compose(sys, ..., ports...)`) are proven in Phase 9 and simply need to be applied twice with new names. The MTK semantics for unconnected Flow variables defaulting to zero make CHAN-03 (adiabatic default) automatic — the test's job is to verify it, not force it.

The most careful step is THERM-03 rewrite: connecting `n` individual `ConstantTemperature` instances to `thermal_left[1]..thermal_left[n]` requires wiring `n` `connect()` statements. The diameter relationship `D_cac = 2 * D_chf` is the key to making one-sided CAC match ChannelHeatFlux: `π * D_cac / 2 = π * D_chf` ensures identical heated perimeters.

**Primary recommendation:** Implement in two waves — Wave 1: CAC component rewrite + DEBT-01 + DEBT-03; Wave 2: ConstantTemperature + THERM-01/THERM-03 rewrites + CHAN-03 adiabatic test.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11 | Acausal component system, port arrays, connect(), compose() | Already in use throughout project |
| Symbolics | 5/6/7 | Symbolic expression building, @variables | MTK dependency, already in use |
| DifferentialEquations | 7 | ODE/DAE solvers for test validation | Already in use |

### No New Dependencies

Phase 10 adds zero new Julia packages. All functionality is achieved by rearranging existing MTK primitives.

---

## Architecture Patterns

### Pattern 1: Dual Port Array Creation

The proven Phase 9 pattern extended to two arrays:

```julia
# Source: existing components.jl line 274 — same pattern, new names
thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:n]
thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]
```

MTK subsystem names produced: `thermal_left1, thermal_left2, ..., thermal_leftN` and `thermal_right1, ..., thermal_rightN`.

### Pattern 2: Two-Sided Energy Balance

```julia
# Source: CONTEXT.md locked decision + Python STREAM channel.py line 164
# Python: heat_transfer = dz * (q_left * pipe.heated_parts[0] + q_right * pipe.heated_parts[1])
# Julia equivalent (π*Dh/2 = heated_parts[i] for circular pipe, Phase 10 hardcodes this):
for i in 1:n
    T_up = (i == 1) ? T_inlet : T[i-1]
    push!(eqs,
        Dt(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
                   + h_tc[i] * (π * Dh / 2) * dz * (thermal_left[i].T  - T[i])
                   + h_tc[i] * (π * Dh / 2) * dz * (thermal_right[i].T - T[i]))
                  / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
    )
    push!(eqs, q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow)
end
push!(eqs, Q_wall_total ~ sum(q_wall[i] for i in 1:n))
```

Note: `π * Dh / 2` replaces the previous `π * Dh` because the total heated perimeter is split symmetrically between two sides. The sum of both sides recovers `π * Dh`.

### Pattern 3: compose() with Two Splatted Arrays

```julia
# Source: CONTEXT.md locked decision
compose(System(eqs, t, all_vars, pars; name=name),
        inlet, outlet, thermal_left..., thermal_right...)
```

MTK accepts any number of positional subsystem arguments in compose(); splatting two separate arrays is equivalent to listing all ports individually.

### Pattern 4: DEBT-01 — Remove `t_inlet` from `_channel_base_eqs`

Current signature (line 204-207 in components.jl):
```julia
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    inlet, outlet,
    Dh, A, L, g_acc, dz, t_inlet)   # <-- t_inlet: dead parameter
```

`t_inlet` was originally intended for use inside the helper but is never referenced in its body (confirmed by reading lines 209-231). It is only passed by the two call sites (ChannelAndContacts line 282-283, ChannelHeatFlux line 346-348) but not consumed.

New signature:
```julia
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    inlet, outlet,
    Dh, A, L, g_acc, dz)
```

Both call sites drop `t_inlet=T_inlet` from their keyword argument lists.

### Pattern 5: ConstantTemperature Component

```julia
# Source: CONTEXT.md specifics section
function ConstantTemperature(; name, T)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
```

This is a one-equation component: pins the port's across variable (T) to a parameter. MTK acausal semantics then solve for Q_flow from the thermal balance of connected components. Used to connect n cells in THERM-03: `connect(ct[i], cac.thermal_left[i])` for each `i in 1:n`.

### Pattern 6: THERM-03 Rewrite Structure

```julia
# New THERM-03: one-sided CAC vs ChannelHeatFlux
# Key geometry: D_cac = 2 * D_chf so that π*D_cac/2 = π*D_chf
D_chf = 0.01; D_cac = 2 * D_chf   # equalize heated perimeters

# Wire n ConstantTemperature sources to thermal_left[1:n]
ct = [ConstantTemperature(name=Symbol(:ct, i), T=T_wall) for i in 1:n]
connections = [
    connect(pump.outlet, bc.inlet),
    connect(bc.outlet,   cac.inlet),
    connect(cac.outlet,  pump.inlet),
    [connect(ct[i].thermal, cac.thermal_left[i]) for i in 1:n]...,
    pump.inlet.P ~ 1.0e5,
    cac.inlet.T  ~ T_inlet,
]
@named sys_cac = compose(System(connections, t; name=:sys_cac),
                          pump, bc, cac, ct...)
ssys_cac = mtkcompile(sys_cac)
```

thermal_right ports remain unconnected — MTK Flow semantics give them Q_flow = 0 automatically.

### Pattern 7: THERM-01 Port Name Assertions

```julia
# Updated THERM-01 assertion (replaces Symbol(:thermal, i) check):
subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
for i in 1:n
    @test Symbol(:thermal_left, i)  in subsys_names
    @test Symbol(:thermal_right, i) in subsys_names
end
# Assert old names are GONE:
@test !(Symbol(:thermal, 1) in subsys_names)
```

### Pattern 8: CHAN-03 Adiabatic Verification Test

After solving a one-sided CAC system at steady state:
```julia
# Verify unconnected right side has zero Q_flow for all cells
sol = solve_steady(ssys_cac, op)
for i in 1:n
    @test isapprox(sol[ssys_cac.cac.thermal_right[i].Q_flow], 0.0; atol=1e-8)
end
```

This can be embedded in the THERM-03 testset since the one-sided THERM-03 setup naturally satisfies this condition.

### Anti-Patterns to Avoid

- **Don't use `thermal_ports` as an alias:** The context locks the removal as complete — no backward compat shim. Any test checking `Symbol(:thermal, i)` must be removed, not just supplemented.
- **Don't halve q_wall:** Current code has `q_wall[i] ~ thermal_ports[i].Q_flow` (1:1, not /n). Keep this 1:1 relationship — `q_wall[i]` is now the SUM of both sides' Q_flow, not a divided value.
- **Don't use `π * Dh` (full perimeter) in two-sided mode:** Each side uses `π * Dh / 2`. Using the full perimeter for both would double-count.
- **Don't build a ConstantTemperature array and try to connect it as one unit:** Must connect each `ct[i].thermal` to `cac.thermal_left[i]` individually.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Adiabatic boundary (unconnected port) | Custom zero-heat-flux equation | MTK Flow variable semantics | Flow variables default to 0 when unconnected — this is the acausal contract |
| Fixed-temperature thermal BC | Custom port-wiring equations inline | `ConstantTemperature` component | Reusable, clean, matches HeatExchanger pattern for fixed T_bc |
| Port subsystem name extraction | String matching on equations | `ModelingToolkit.get_systems(sys)` | Authoritative MTK API, already used in THERM-01 |

**Key insight:** MTK's acausal `connect = Flow` metadata on Q_flow is the entire mechanism for adiabatic defaults — no custom equations needed for the unconnected port case.

---

## Common Pitfalls

### Pitfall 1: Per-Side Heated Perimeter Factor

**What goes wrong:** Using `π * Dh` (total perimeter) for each side instead of `π * Dh / 2` in the two-sided energy balance. This doubles the heat input, making the two-sided CAC give 2x the heating of a one-sided CAC with the same T_wall.

**Why it happens:** The original single-port formula used `π * Dh` for the full perimeter. When splitting into two ports, each side should use half.

**How to avoid:** The Python STREAM reference confirms: `heat_transfer = dz * (q_left * heated_parts[0] + q_right * heated_parts[1])` where `heated_parts = (π*Dh/2, π*Dh/2)` for a circular pipe. Each term multiplies by `π*Dh/2`, not `π*Dh`.

**Warning signs:** THERM-03 T_outlet mismatch by factor of ~2 if both sides are connected to the same T_wall.

### Pitfall 2: THERM-03 Diameter Relationship

**What goes wrong:** Setting `D_cac = D_chf` (same diameter) when doing one-sided comparison. One-sided CAC with `D_cac = D_chf` uses `π*D_cac/2` = `π*D_chf/2`, which is half the heated perimeter of ChannelHeatFlux (which uses `π*D_chf`). T_outlet will not match.

**Why it happens:** Intuition says "same pipe, same diameter." But the test goal is to verify equivalent heat transfer with one side active.

**How to avoid:** Use `D_cac = 2 * D_chf`. Then `π * D_cac / 2 = π * D_chf`. Confirmed in CONTEXT.md specifics.

**Warning signs:** THERM-03 systematic T_outlet undershoot by ~50% after rewrite.

### Pitfall 3: MTK Array Port Access Syntax

**What goes wrong:** Assuming `cac.thermal_left[i]` works in all MTK 11 contexts (solve indexing, connect statements). The STATE.md explicitly flags this: "MTK array port access syntax for `thermal_left[i]` must be confirmed with a smoke test early in Phase 10 before writing all tests against it."

**Why it happens:** MTK patch releases have changed how indexed port sub-components are accessed. The `get_systems()` + subsystem name approach is known to work; direct indexing may need verification.

**How to avoid:** Wave 0 (or first task in Wave 1) should include a minimal smoke test: instantiate CAC with n=2 and check that `Symbol(:thermal_left, 1) in Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))` before writing full test suite.

**Warning signs:** `KeyError` or `MethodError` when accessing `ssys.cac.thermal_left[i]` in solution indexing.

### Pitfall 4: `t_inlet` Removal — Both Call Sites

**What goes wrong:** Removing `t_inlet` from `_channel_base_eqs` signature but forgetting to update one of the two call sites (ChannelAndContacts at line 282-283, ChannelHeatFlux at line 346-348).

**Why it happens:** Two separate call sites are easy to miss.

**How to avoid:** Grep for `t_inlet` in components.jl after the change — should find zero matches.

**Warning signs:** `UndefKeywordError: keyword argument t_inlet not assigned` at function call site.

### Pitfall 5: compose() Argument Order

**What goes wrong:** compose() with `thermal_left..., thermal_right...` vs `thermal_right..., thermal_left...` — different orderings produce different subsystem indexing but both are valid. The issue is consistency with test assertions.

**Why it happens:** compose() accepts subsystems positionally; order affects `get_systems()` output.

**How to avoid:** Always use `inlet, outlet, thermal_left..., thermal_right...` ordering and write tests accordingly. Since tests check by name (not position), ordering does not affect correctness.

---

## Code Examples

### Complete ChannelAndContacts Skeleton (Two-Sided)

```julia
# Source: CONTEXT.md locked decisions + existing components.jl structure
function ChannelAndContacts(; name, n::Int, L, D, A, g = 0.0)
    Dh = D
    Dt = Differential(t)

    pars = @parameters begin
        L     = L
        D_h   = Dh
        A     = A
        g_acc = g
    end

    vars = @variables begin
        (T(t))[1:n]         = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t)            = 600.0
        dP(t)
        Q_wall_total(t)
    end

    @named inlet  = FlowPort()
    @named outlet = FlowPort()
    thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:n]
    thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]

    dz      = L / n
    eqs     = Equation[]
    T_inlet = instream(inlet.T)

    # DEBT-01: no t_inlet argument
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      inlet, outlet, Dh, A, L, g_acc=g, dz)

    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (π * Dh / 2) * dz * (thermal_left[i].T  - T[i])
                       + h_tc[i] * (π * Dh / 2) * dz * (thermal_right[i].T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow)
    end
    push!(eqs, Q_wall_total ~ sum(q_wall[i] for i in 1:n))

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); T_out; dP; Q_wall_total]

    compose(System(eqs, t, all_vars, pars; name=name),
            inlet, outlet, thermal_left..., thermal_right...)
end
```

### ConstantTemperature Component

```julia
# Source: CONTEXT.md specifics
function ConstantTemperature(; name, T)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
```

### Updated _channel_base_eqs Signature

```julia
# Source: DEBT-01, components.jl line 204
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    inlet, outlet,
    Dh, A, L, g_acc, dz)
    # body unchanged — t_inlet was never used in the body
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single `thermal_ports[1:n]` (one side) | Dual `thermal_left[1:n]` + `thermal_right[1:n]` | Phase 10 | Enables HeatDiffusion coupling in Phase 11 |
| THERM-03 validates ChannelHeatFlux vs Channel | THERM-03 validates ChannelAndContacts vs ChannelHeatFlux | Phase 10 | DEBT-02 cleared; CAC is now directly integration-tested |
| `_channel_base_eqs` has dead `t_inlet` param | `t_inlet` removed | Phase 10 | DEBT-01 cleared; cleaner internal API |

---

## Open Questions

1. **MTK array port access syntax for `thermal_left[i]` in solution indexing**
   - What we know: `compose(sys, thermal_left...)` works (proven in Phase 9 with `thermal_ports...`); `get_systems()` name check works
   - What's unclear: Whether `sol[ssys.cac.thermal_left[i].Q_flow]` (array indexing on a solution) works in MTK 11 without additional ceremony
   - Recommendation: Add a smoke test as the very first task — instantiate CAC with n=2, solve trivially, and check `sol[ssys.cac.thermal_left[1].Q_flow]` syntax. If it fails, use `sol[ssys.cac.thermal_left1.Q_flow]` (string-like subsystem access) as fallback.

2. **`ConstantTemperature` export decision (Claude's Discretion)**
   - What we know: `HeatExchanger` is exported (STREAM.jl line 14); it sets port temperature as a BC
   - What's unclear: Whether `ConstantTemperature` will be needed by end users or only in tests
   - Recommendation: Export it. It mirrors `HeatExchanger` conceptually (thermal BC vs hydraulic BC) and Phase 11 (HeatDiffusion) will need it for validation tests.

3. **Test parameter values for new THERM-03 (Claude's Discretion)**
   - What we know: D_chf = 0.01 (current test), D_cac = 0.02; L, n, T_inlet, T_wall, dP_pump from current THERM-03 can be reused
   - Recommendation: Reuse current THERM-03 values: `n=10, L_ch=0.6, D_chf=0.01, D_cac=0.02, A_ch=7.85e-5, T_inlet=313.15, T_wall=373.15, dP_pump=3.0e4`. The A_ch value (based on D_chf = 0.01) should remain the same for CAC since A affects flow area and is independent of heated perimeter.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (built-in) |
| Config file | none — invoked via `Pkg.test()` or `julia --project test/runtests.jl` |
| Quick run command | `julia --project -e 'include("test/runtests.jl")'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEBT-01 | `_channel_base_eqs` callable without `t_inlet` | unit (compilation) | `julia --project -e 'include("test/runtests.jl")'` | Updates to existing `runtests.jl` |
| DEBT-02 | THERM-03 asserts CAC behavioral output directly | integration | same | Updates to existing `runtests.jl` |
| DEBT-03 | Doc fix in `09-01-SUMMARY.md` | manual | N/A — cosmetic text change | File already exists |
| CHAN-01 | CAC has `thermal_left1..N` and `thermal_right1..N` subsystems; no `thermal1..N` | unit (structure) | same | Updates to existing `runtests.jl` |
| CHAN-02 | `q_wall[i] == thermal_left[i].Q_flow + thermal_right[i].Q_flow` at steady state | integration | same | Updates to existing `runtests.jl` |
| CHAN-03 | Unconnected right side has Q_flow == 0 at steady state | integration | same | Updates to existing `runtests.jl` |

### Sampling Rate

- **Per task commit:** `julia --project -e 'include("test/runtests.jl")'`
- **Per wave merge:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all phase requirements. All new tests are additions/updates to `test/runtests.jl`.

---

## Sources

### Primary (HIGH confidence)

- `/home/itay/projects/Julia-STREAM/src/components.jl` — full current source; `_channel_base_eqs` (lines 204-231), `ChannelAndContacts` (lines 248-303), `ChannelHeatFlux` (lines 315-365), existing port-array pattern
- `/home/itay/projects/Julia-STREAM/src/connectors.jl` — `ThermalPort` connector definition; `Q_flow` is `connect = Flow`
- `/home/itay/projects/Julia-STREAM/test/runtests.jl` — THERM-01 (lines 477-493), THERM-03 (lines 511-543); exact test structure to modify
- `/home/itay/projects/Julia-STREAM/.planning/phases/10-channelandcontacts-two-sided-upgrade/10-CONTEXT.md` — all locked decisions
- `/home/itay/projects/STREAM/stream/calculations/channel.py` — Python STREAM reference: `coolant_first_order_upwind_dTdt` (line 116-167); `heat_transfer = dz * (q_left * pipe.heated_parts[0] + q_right * pipe.heated_parts[1])` confirms per-side `heated_parts` split
- `/home/itay/projects/STREAM/stream/pipe_geometry.py` — `EffectivePipe`: `heated_parts = (heated_perimeter/2, heated_perimeter/2)` default for circular pipe; sum validates to `heated_perimeter`

### Secondary (MEDIUM confidence)

- ModelingToolkit v11 acausal semantics: Flow variables default to 0 when unconnected. Verified by analogy with existing tests (THERM-01 uses `mtkcompile(ch; fully_determined=false)` for isolated CAC with unconnected ports — no explicit zero-flow equation needed).

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all existing infrastructure
- Architecture: HIGH — patterns directly derived from reading current source + CONTEXT.md locked decisions + Python reference
- Pitfalls: HIGH — derived from direct code analysis (DEBT-01 confirmed no `t_inlet` usage in helper body; perimeter factor confirmed against Python reference); MTK array access flagged as MEDIUM per STATE.md

**Research date:** 2026-03-14
**Valid until:** 2026-04-14 (stable domain; MTK 11 API)

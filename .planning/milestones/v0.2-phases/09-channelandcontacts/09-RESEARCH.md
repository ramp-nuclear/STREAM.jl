# Phase 9: ChannelAndContacts - Research

**Researched:** 2026-03-13
**Domain:** MTK v11 array connectors, per-cell ThermalPort coupling, Julia parameter arrays
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- `ChannelAndContacts` — n ThermalPorts (one per axial cell), for proper HeatDiffusion coupling (THERM-01)
- `ChannelHeatFlux` — T_wall as parameter (scalar or per-cell array), for testing and simple simulations; no ThermalPorts
- `_channel_base_eqs` — private shared helper called by both; holds the ~5 equations common to all channel variants (pressure drop, velocity, Re, Nu, HTC, upwind energy balance skeleton)
- `Channel` stays completely untouched (THERM-02)
- Semantic split: Channel = unheated, ChannelAndContacts = heated cell-by-cell, ChannelHeatFlux = testing shorthand
- One `thermal[i]` ThermalPort per axial cell (not left+right per cell)
- Left/right wall distinction deferred to v0.3
- `thermal[i].Q_flow` = per-cell heat flow in watts (positive = into component)
- Expose `Q_wall_total` observable: `Q_wall_total ~ sum(thermal[i].Q_flow for i in 1:n)`
- `ChannelHeatFlux(; name, n, L, D, A, g=0.0, T_wall)` — same shape as Channel
- T_wall can be scalar (all cells) or per-cell array of length n
- THERM-03 validation test uses `ChannelHeatFlux(T_wall=T_uniform)` — cleaner than wiring n HeatExchanger instances
- Tests use inline `connect()`/`compose()` — no `build_loop_contacts` helper
- Implementation pattern: `_channel_base_eqs` as private function called by both new components
- TDD: RED stubs first, then GREEN implementation

### Claude's Discretion
- Exact signature of `_channel_base_eqs` (what it accepts/returns)
- Whether `T_wall` array is a Julia parameter array or a vector of MTK parameters
- ODE solver and time span for any transient validation tests

### Deferred Ideas (OUT OF SCOPE)
- Left/right ThermalPort distinction per cell (thermal_left[i] + thermal_right[i]) — deferred to v0.3 when HeatDiffusion geometry drives the requirement
- ChannelHeatFlux with per-cell h_wall (not just T_wall) — deferred; not needed until contact resistance modeling
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| THERM-01 | ChannelAndContacts component: n ThermalPorts (one per axial cell), per-cell wall temperature in energy balance: `h_tc[i] * (π*Dh) * dz * (thermal[i].T - T[i])` | MTK array-of-ThermalPorts pattern verified working; per-element indexing `thermal_array[i].T` confirmed |
| THERM-02 | Existing Channel (single ThermalPort) remains unchanged and all v0.1 tests continue to pass | Channel untouched by design; new components added alongside; regression test = run existing testset |
| THERM-03 | ChannelAndContacts steady-state result matches Channel result when all n ThermalPorts are driven by uniform wall temperature (within 0.1%) | ChannelHeatFlux with scalar T_wall parameter confirmed working in MTK; cross-validation test pattern derived from Python STREAM semantic split |
</phase_requirements>

---

## Summary

Phase 9 implements three items: `ChannelAndContacts` (n per-cell ThermalPorts), `ChannelHeatFlux` (T_wall as parameter), and `_channel_base_eqs` (shared helper). The critical new capability is the array-of-ThermalPorts pattern, which has been verified to work in MTK v11.15.0. The pattern `[ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]` creates n independent connector systems, each with `T` and `Q_flow` variables, that compose correctly and compile with `mtkcompile`.

The `Channel` component's design note (lines 3-8 of components.jl) explicitly anticipated this refactor: the `q_wall` indirection was built so that the energy balance loop body (`Dt(T[i]) ~ ...`) transplants directly to `ChannelAndContacts` with only the `thermal.T` reference changed to `thermal_array[i].T`. The common equations (pressure drop, velocity, Re, Nu, HTC) are candidates for extraction into `_channel_base_eqs`.

For `ChannelHeatFlux`, both scalar and per-cell T_wall work as MTK parameters. The cleanest implementation decision is two separate function signatures: `ChannelHeatFlux(; name, n, L, D, A, g=0.0, T_wall::Real)` for scalar and `ChannelHeatFlux(; name, n, L, D, A, g=0.0, T_wall::AbstractVector)` for per-cell, using Julia multiple dispatch to select which MTK parameter declaration to use.

**Primary recommendation:** Use the array-of-named-ThermalPorts pattern (not MTK's native array connector syntax), extract `_channel_base_eqs` returning a `Vector{Equation}`, and use scalar MTK parameter for `T_wall` in `ChannelHeatFlux` (simplest; per-cell can broadcast).

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11.15.0 | Component modeling, symbolic equations | Already in use across all phases |
| Symbolics | 7.15.3 | Symbolic variable/parameter declarations | Required by MTK |
| DifferentialEquations | 7.17.0 | Solver infrastructure | Already in use |
| Sundials (KINSOL) | 5.1.0 | Steady-state solve | Already in use |

### No New Dependencies

Phase 9 requires no new package dependencies. All patterns work within the existing MTK v11 API.

---

## Architecture Patterns

### Pattern 1: Array of Named ThermalPorts (VERIFIED)

**What:** Create n independent ThermalPort connector systems, each with a unique name. Compose them all into the System via splat.

**When to use:** Any component needing per-cell thermal connections.

**Example (verified in MTK v11.15.0):**

```julia
# In ChannelAndContacts constructor body
n = 5  # or from kwarg
thermal_ports = [ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]

# Reference individual port variables in equations:
# thermal_ports[i].T  -- across variable (wall temperature)
# thermal_ports[i].Q_flow  -- flow variable (heat into component)

# Compose with splat:
compose(System(eqs, t, all_vars, pars; name=name),
        inlet, outlet, thermal_ports...)
```

**Confirmed outputs:**
- `compose` accepts the splat: `compose(sys, inlet, outlet, thermal_ports...)`
- `mtkcompile(sys; fully_determined=false)` succeeds
- Per-element access: `thermal_ports[i].T` and `thermal_ports[i].Q_flow` are valid Symbolics.Num expressions

### Pattern 2: _channel_base_eqs Helper Function

**What:** Extract the 5n + scalar equations common to both Channel variants into a private function that appends to a pre-allocated `Vector{Equation}`.

**When to use:** Called by both `ChannelAndContacts` and `ChannelHeatFlux` before each appends its thermal coupling equations.

**Recommended signature:**

```julia
function _channel_base_eqs(;
    eqs::Vector{Equation},   # mutated in-place (append to it)
    n::Int,
    T,           # per-cell temperature vars (T(t))[1:n]
    Re, Nu, h_tc, v,         # per-cell observable vars
    T_out, dP,               # scalar observable vars
    inlet, outlet,       # FlowPort connectors
    Dh, A, L,                # geometry (already concrete floats or MTK pars)
    g_acc,                   # gravity par
    dz,                      # cell height = L/n
    t_inlet,                 # instream(inlet.T)
)
```

The function appends equations for: velocity, Re, Nu, h_tc (per cell); pressure drop dP; T_out; port wiring (4 equations). It does NOT append energy balance equations — those are what differs between variants.

**Alternative:** Return a `Vector{Equation}` and concatenate. Either works; in-place is idiomatic for performance but mutable state is also fine for a build-time function.

### Pattern 3: Energy Balance with Per-Cell ThermalPort

**What:** The energy balance in `ChannelAndContacts` replaces `thermal.T` with `thermal_ports[i].T` and `thermal.Q_flow / n` with `thermal_ports[i].Q_flow`.

```julia
# ChannelAndContacts energy balance (per cell i):
push!(eqs,
    Dt(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
               + h_tc[i] * (π * Dh) * dz * (thermal_ports[i].T - T[i]))
              / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
)
# q_wall[i] directly from port:
push!(eqs, q_wall[i] ~ thermal_ports[i].Q_flow)
```

Note: `q_wall[i] ~ thermal_ports[i].Q_flow` (not `/ n`) because each port now owns exactly one cell.

**Q_wall_total observable:**
```julia
push!(eqs, Q_wall_total ~ sum(thermal_ports[i].Q_flow for i in 1:n))
```

### Pattern 4: ChannelHeatFlux Parameter Handling

**What:** T_wall as a scalar MTK parameter, broadcast to all n cells. Simplest approach.

```julia
function ChannelHeatFlux(; name, n::Int, L, D, A, g = 0.0, T_wall)
    Dh = D
    Dt = Differential(t)
    pars = @parameters begin
        L     = L
        D_h   = Dh
        A     = A
        g_acc = g
        T_wall_par = T_wall   # single scalar parameter
    end
    # In energy balance: use T_wall_par for all i
    # h_tc[i] * (π * Dh) * dz * (T_wall_par - T[i])
```

For per-cell T_wall array, use `@parameters T_wall_par[1:n] = fill(T_wall, n)` and `collect()`:

```julia
# Per-cell variant (when T_wall isa AbstractVector):
p_tw = @parameters T_wall_par[1:n] = T_wall
T_wall_vec = collect(p_tw[1])
# Then: T_wall_vec[i] in each cell's energy balance
```

Julia multiple dispatch on `T_wall` type selects which branch. Alternatively: always use scalar parameter (caller passes same value for all cells) — sufficient for THERM-03.

**Simplest decision for THERM-03:** Use scalar T_wall parameter only. Per-cell array support can be added if needed, but THERM-03 only requires uniform T_wall.

### Pattern 5: THERM-03 Cross-Validation Test

**What:** Steady-state `ChannelHeatFlux` result must match `Channel` result within 0.1%.

```julia
# Both need a closed loop — wire with Pump + HeatExchanger (TempBC)
# Channel uses: ch.thermal.T ~ T_uniform (external pin equation)
# ChannelHeatFlux uses: T_wall=T_uniform parameter (internal to component)

# Reference: build_loop() from solvers.jl (Channel variant)
# New: build_loop with ChannelHeatFlux substituted, no thermal port wiring

# Assertion:
@test isapprox(T_out_chf, T_out_ch; rtol=1e-3)   # 0.1% tolerance
```

**Key insight:** `Channel` uses `thermal.T ~ T_wall` as an external equation pinning the wall temperature. `ChannelHeatFlux` bakes T_wall into the parameter — the energy balance is algebraically equivalent when T_wall is uniform. Steady-state results should match to floating-point accuracy, making 0.1% tolerance very comfortable.

### Recommended Project Structure (no change needed)

```
src/
├── connectors.jl    # ThermalPort unchanged
├── components.jl    # add ChannelAndContacts, ChannelHeatFlux, _channel_base_eqs
├── solvers.jl       # unchanged
└── STREAM.jl        # export ChannelAndContacts, ChannelHeatFlux
test/
└── runtests.jl      # add Phase 9 testset
```

### Anti-Patterns to Avoid

- **Re-implementing Channel's equations from scratch:** The energy balance loop body is identical to Channel's. Extract or copy-then-adapt — do not rethink the physics.
- **Wiring n HeatExchanger instances for THERM-03 test:** The context explicitly says to use `ChannelHeatFlux(T_wall=T_uniform)` instead — it's cleaner and already decided.
- **Using MTK's native array connector syntax (`@connector [1:n]`):** No evidence this exists in MTK v11. The manual named-array pattern `[ThermalPort(name=Symbol(:thermal,i)) for i in 1:n]` is verified working.
- **Adding q_wall[i] ~ thermal_ports[i].Q_flow / n:** In `ChannelAndContacts`, each `thermal_ports[i]` owns exactly one cell, so the split is 1:1, not 1:n.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Connector array semantics | Custom struct wrapping n ports | Julia array of named ThermalPort systems + compose splat | MTK handles connect() semantics correctly per element; verified |
| Per-cell heat balance | New physics | `Channel` energy balance with `thermal.T` → `thermal_ports[i].T` | Physics is identical; only the T_wall source changes |
| Steady-state solve for THERM-03 | New solver or loop builder | `solve_steady()` from solvers.jl with inline connections | Already battle-tested across all prior phases |

---

## Common Pitfalls

### Pitfall 1: q_wall split factor
**What goes wrong:** Writing `q_wall[i] ~ thermal_ports[i].Q_flow / n` (copying Channel pattern verbatim).
**Why it happens:** Channel divides by n because one ThermalPort carries total Q; ChannelAndContacts has one port per cell so no division needed.
**How to avoid:** `q_wall[i] ~ thermal_ports[i].Q_flow` (1:1).
**Warning signs:** Q_wall_total is n times too large; THERM-03 fails by factor of n.

### Pitfall 2: compose() variable list for array ports
**What goes wrong:** Forgetting to splat the thermal_ports array: `compose(..., thermal_ports)` passes a Vector, not individual connectors.
**Why it happens:** Julia doesn't auto-splat.
**How to avoid:** `compose(..., thermal_ports...)` with trailing `...`.
**Warning signs:** MTK error about unrecognized subsystem or missing port connections.

### Pitfall 3: T_wall pin equation still needed for ChannelAndContacts standalone test
**What goes wrong:** Building a standalone `ChannelAndContacts` system without pinning `thermal_ports[i].T` — the system is underdetermined.
**Why it happens:** Unlike `Channel` (where caller writes `ch.thermal.T ~ T_wall`), ChannelAndContacts has n ports each needing a T pin.
**How to avoid:** In the THERM-01 standalone test, add `[ch.thermal_ports[i].T ~ T_wall for i in 1:n]` to connections, or use `mtkcompile(sys; fully_determined=false)` for the stub test that only checks compilability.
**Warning signs:** `mtkcompile` fails with over/under-determination error on ChannelAndContacts standalone.

### Pitfall 4: ChannelHeatFlux skipping outlet.T wiring
**What goes wrong:** Omitting `outlet.T ~ T[n]` from `ChannelHeatFlux` because it "doesn't have ThermalPorts."
**Why it happens:** Superficially, ChannelHeatFlux looks simpler — but it still needs all FlowPort wiring equations identical to Channel.
**How to avoid:** `_channel_base_eqs` includes port wiring; ChannelHeatFlux calls it and only adds the T_wall thermal coupling loop.

### Pitfall 5: THERM-03 numerical precision
**What goes wrong:** Channel uses `thermal.T` evaluated symbolically; ChannelHeatFlux uses a parameter. MTK may simplify differently.
**Why it happens:** Symbolic substitution vs parameter evaluation paths in MTK.
**How to avoid:** 0.1% tolerance is very lenient — physics is identical, so numerical differences should be O(1e-10). If test fails, check that the same n, L, D, A, T_wall, T_inlet, dP_pump values are used in both branches.

---

## Code Examples

### ChannelAndContacts skeleton (verified MTK patterns)

```julia
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
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t)    = 600.0
        dP(t)
        Q_wall_total(t)
    end

    @named inlet  = FlowPort()
    @named outlet = FlowPort()
    # Per-cell ThermalPorts (verified pattern):
    thermal_ports = [ThermalPort(name=Symbol(:thermal, i)) for i in 1:n]

    dz = L / n
    eqs = Equation[]
    T_inlet = instream(inlet.T)

    # _channel_base_eqs handles: v, Re, Nu, h_tc, dP, T_out, port wiring
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      inlet, outlet, Dh, A, L, g_acc=pars[4], dz, t_inlet=T_inlet)

    # ChannelAndContacts-specific: energy balance + per-cell thermal
    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (π * Dh) * dz * (thermal_ports[i].T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ thermal_ports[i].Q_flow)  # 1:1, no /n
    end

    push!(eqs, Q_wall_total ~ sum(thermal_ports[i].Q_flow for i in 1:n))

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); T_out; dP; Q_wall_total]

    compose(System(eqs, t, all_vars, pars; name=name),
            inlet, outlet, thermal_ports...)  # splat array
end
```

### ChannelHeatFlux skeleton

```julia
function ChannelHeatFlux(; name, n::Int, L, D, A, g = 0.0, T_wall)
    Dh = D
    Dt = Differential(t)

    pars = @parameters begin
        L        = L
        D_h      = Dh
        A        = A
        g_acc    = g
        T_wall_p = T_wall   # scalar parameter; same for all cells
    end

    vars = @variables begin
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t)    = 600.0
        dP(t)
    end

    @named inlet  = FlowPort()
    @named outlet = FlowPort()

    dz = L / n
    eqs = Equation[]
    T_inlet = instream(inlet.T)

    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      inlet, outlet, Dh, A, L, g_acc=pars[4], dz, t_inlet=T_inlet)

    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (inlet.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (π * Dh) * dz * (T_wall_p - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ h_tc[i] * (π * Dh) * dz * (T_wall_p - T[i]))
    end

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); T_out; dP]

    compose(System(eqs, t, all_vars, pars; name=name), inlet, outlet)
end
```

### THERM-01 standalone test

```julia
@testset "THERM-01: ChannelAndContacts mtkcompile" begin
    @named ch = ChannelAndContacts(n=5, L=1.0, D=0.01, A=7.85e-5)
    @test ch isa ModelingToolkit.System
    @test_nowarn mtkcompile(ch; fully_determined=false)
end

@testset "THERM-01: ChannelAndContacts has n ThermalPorts" begin
    @named ch = ChannelAndContacts(n=5, L=1.0, D=0.01, A=7.85e-5)
    # Check subsystem names include thermal1..thermal5
    subsys_names = Symbol.(ModelingToolkit.getname.(ModelingToolkit.get_systems(ch)))
    for i in 1:5
        @test Symbol(:thermal, i) in subsys_names
    end
end
```

### THERM-03 cross-validation test

```julia
@testset "THERM-03: ChannelHeatFlux matches Channel within 0.1%" begin
    n = 10; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; A_ch = 7.85e-5; dP_pump = 3.0e4

    # --- Channel reference (existing build_loop) ---
    ssys_ch = build_loop(; n, L_ch, D_ch, A_ch, dP_pump, T_inlet, T_wall)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op_ch = [ssys_ch.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_ch, ssys_ch.ch.inlet.mdot => 0.490)
    sol_ch = solve_steady(ssys_ch, op_ch)
    T_out_ch = sol_ch[ssys_ch.ch.T_out]

    # --- ChannelHeatFlux loop (inline wiring, no build_loop helper) ---
    @named pump = Pump(dP_pump=dP_pump)
    @named chf  = ChannelHeatFlux(n=n, L=L_ch, D=D_ch, A=A_ch, T_wall=T_wall)
    @named bc   = HeatExchanger(T_bc=T_inlet)
    connections = [
        connect(pump.outlet, bc.inlet),
        connect(bc.outlet,   chf.inlet),
        connect(chf.outlet,  pump.inlet),
        pump.inlet.P ~ 1.0e5,
        chf.inlet.T  ~ T_inlet,
    ]
    @named sys_chf = compose(System(connections, t; name=:sys_chf), pump, bc, chf)
    ssys_chf = mtkcompile(sys_chf)
    op_chf = [ssys_chf.chf.T[i] => T_guess[i] for i in 1:n]
    push!(op_chf, ssys_chf.chf.inlet.mdot => 0.490)
    sol_chf = solve_steady(ssys_chf, op_chf)
    T_out_chf = sol_chf[ssys_chf.chf.T_out]

    @test isapprox(T_out_chf, T_out_ch; rtol=1e-3)  # 0.1%
end
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (no external framework) |
| Config file | none — runs via `Pkg.test()` or `julia --project=. test/runtests.jl` |
| Quick run command | `julia --project=. test/runtests.jl` |
| Full suite command | `julia --project=. -e "import Pkg; Pkg.test()"` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| THERM-01 | ChannelAndContacts builds, compiles, has n ThermalPorts in subsystems | unit | `julia --project=. test/runtests.jl` — Phase 9 testset | ❌ Wave 0 |
| THERM-01 | ChannelAndContacts energy balance uses per-cell `thermal[i].T` | unit (equation inspection) | same | ❌ Wave 0 |
| THERM-02 | All v0.1 tests pass unchanged (Channel unmodified) | regression | `julia --project=. test/runtests.jl` — existing testsets | ✅ exists |
| THERM-03 | ChannelHeatFlux steady-state matches Channel within 0.1% | integration/cross-validation | `julia --project=. test/runtests.jl` — Phase 9 testset | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project=. test/runtests.jl` (full suite — ~2 min, acceptable for coarse granularity)
- **Per wave merge:** `julia --project=. -e "import Pkg; Pkg.test()"`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/runtests.jl` — add `@testset "STREAM Phase 9 Tests"` block with THERM-01, THERM-02 (regression implicit), THERM-03
- [ ] `src/components.jl` — add stubs for `ChannelAndContacts`, `ChannelHeatFlux`, `_channel_base_eqs`
- [ ] `src/STREAM.jl` — add exports `ChannelAndContacts`, `ChannelHeatFlux`

---

## Open Questions

1. **`_channel_base_eqs` signature — mutate-in-place vs return**
   - What we know: Both patterns are idiomatic Julia; in-place avoids allocation
   - What's unclear: How many arguments the helper needs (pars vs concrete values)
   - Recommendation: Mutate-in-place; accept vars and pars as positional keyword args; planner should decide final signature

2. **ChannelAndContacts standalone test for energy balance**
   - What we know: `fully_determined=false` allows underdetermined compile; but verifying the energy balance equation body requires pinning `thermal[i].T`
   - What's unclear: How complex the standalone test setup should be
   - Recommendation: THERM-01 has two sub-tests: (a) struct+compile with `fully_determined=false`, (b) pin all thermal[i].T and run `solve_steady` for a simple case to verify per-cell physics

3. **ChannelHeatFlux q_wall observable**
   - What we know: Channel uses `q_wall[i] ~ thermal.Q_flow / n`; ChannelHeatFlux has no ThermalPort
   - What's unclear: Whether q_wall should be the computed heat transfer rate or just left as observable
   - Recommendation: `q_wall[i] ~ h_tc[i] * (π * Dh) * dz * (T_wall_p - T[i])` — directly computed, no port needed

---

## Sources

### Primary (HIGH confidence)
- MTK v11.15.0 live REPL verification — array-of-ThermalPorts pattern, compose splat, per-element indexing, scalar/array parameters (all verified above)
- `src/components.jl` — Channel implementation, design note on q_wall indirection (lines 1-8), energy balance structure
- `src/connectors.jl` — ThermalPort definition (T across, Q_flow Flow)
- `.planning/phases/09-channelandcontacts/09-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence)
- Python STREAM `stream/calculations/channel.py` lines 452-707 — ChannelAndContacts Python reference; confirms semantic split and h_left/h_right per-cell HTC structure (not directly ported but confirms design intent)
- Python STREAM SKILL.md — variable table confirms ChannelAndContacts exports h_left/h_right per cell; Julia analog is h_tc[i] per-cell from ThermalPort

### Tertiary (LOW confidence — not needed)
- None required

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all MTK patterns live-verified
- Architecture: HIGH — array-of-ThermalPorts pattern compiled and ran successfully in MTK v11.15.0
- Pitfalls: HIGH — derived from direct code analysis (q_wall split factor, compose splat, standalone test underdetermination)
- Test wiring: HIGH — consistent with prior phase patterns (build_loop, solve_steady, mtkcompile)

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (MTK v11 is stable; no breaking changes expected at patch level)

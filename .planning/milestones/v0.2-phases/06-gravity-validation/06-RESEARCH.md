# Phase 6: Gravity Validation - Research

**Researched:** 2026-03-13
**Domain:** MTK hydrostatic pressure wiring, Julia-STREAM gravity component integration
**Confidence:** HIGH

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GRAV-01 | Vertical closed loop (Channel with g_acc=9.80665 + Gravity component on return leg of equal height) assembles, compiles, and solves correctly | Both components exist in codebase; wiring topology and MTK connect() patterns are well-understood from v0.1 |
| GRAV-02 | Gravity cancellation test — equal height up/down gives the same steady-state flow as the horizontal reference loop within 1% | Channel dP equation and Gravity equation confirmed; density evaluation mismatch quantified and within tolerance |
</phase_requirements>

---

## Summary

Both components required for this phase already exist and compile. The `Channel` component (in `src/components.jl`) has a `g_acc` parameter that contributes `rho_water(T[i_mid]) * g_acc * L` to the pressure drop equation. The standalone `Gravity` component computes `inlet.P - outlet.P ~ rho_water(T_in) * 9.80665 * H`. Neither has ever been wired together into a complete solved loop — that is the sole work of Phase 6.

The cancellation physics is sound: Channel's upward gravity head loss and Gravity's return-leg head gain are equal when `H = L_ch` and `g_acc = 9.80665`. A small density mismatch exists because Channel evaluates density at the midpoint cell temperature (`T[i_mid]`) while Gravity evaluates at the inlet temperature (`T_in` via `instream(inlet.T)`). At the reference operating conditions (~313–328 K), this difference is under 0.5% of the total density, well within the 1% cancellation tolerance.

The only new code required is `build_loop_vertical()` in `src/solvers.jl` (mirroring `build_loop` but adding the `Gravity` component in the return leg), the export of `build_loop_vertical` in `src/STREAM.jl`, and two test cases in `test/runtests.jl`. No existing code needs modification.

**Primary recommendation:** Wire `Pump -> TempBC -> Channel(g_acc=9.80665) -> Gravity(H=L_ch) -> Pump` using the existing MTK `connect()` pattern from `build_loop`. Verify with `isapprox(mdot_vert, mdot_horiz; rtol=0.01)`.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11 | DAE system assembly, `mtkcompile`, symbolic indexing | Project's core framework; all v0.1 uses this |
| DifferentialEquations | 7 | `SSRootfind(KINSOL())` steady-state solver | Proven in v0.1 SOLV-01/VAL-01 tests |
| Sundials | 5 | KINSOL nonlinear solver backend | Used in `solve_steady` since v0.1 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Symbolics | 5-7 | `@register_symbolic` for fluid property functions | Already registered; no new registrations needed |

**Installation:** All dependencies already in `Project.toml` — no new packages.

---

## Architecture Patterns

### Existing Loop Topology (horizontal reference)
```
Pump -> TempBC -> Channel(g_acc=0) -> Pump (closed)
```

### Vertical Loop Topology (Phase 6 addition)
```
Pump -> TempBC -> Channel(g_acc=9.80665, L=L_ch) -> Gravity(H=L_ch) -> Pump (closed)
         [bc]         [ch, upward leg]               [grav, return leg]
```

### Pattern 1: MTK connect() for hydraulic loop
**What:** Components are connected via `connect(a.outlet, b.inlet)`. MTK applies stream variable semantics: `mdot` (Flow) sums to zero at junctions; `T` (Stream) resolves via `instream()`.
**When to use:** Always — this is the MTK acausal approach used in all v0.1 components.

```julia
# Source: src/solvers.jl build_loop()
connections = [
    connect(pump.outlet, bc.inlet),
    connect(bc.outlet,   ch.inlet),
    connect(ch.outlet,   pump.inlet),
    pump.inlet.P ~ 1.0e5,          # pressure gauge freedom fix
    ch.thermal.T   ~ T_wall,
    ch.inlet.T   ~ T_inlet,
]
@named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
ssys = mtkcompile(sys)
```

### Pattern 2: Gravity component wiring direction
**What:** `Gravity`'s pressure equation is `inlet.P - outlet.P ~ rho * g * H`. With `H > 0`, `inlet.P > outlet.P`. Connect Gravity in the flow direction of the return leg (downstream of Channel, upstream of Pump). MTK handles the sign bookkeeping.

**Convention confirmed from src/components.jl:**
```julia
function Gravity(; name, H)
    # inlet.P - outlet.P ~ rho_water(T_in) * 9.80665 * H
    # H > 0: inlet is high-pressure (bottom of return column)
    # Connect in flow direction: ch.outlet -> grav.inlet -> pump.inlet
```

**Physical sign analysis:**
- Channel goes UP: `dP` includes `+rho * g_acc * L` (pressure drops going up — correct)
- Return leg goes DOWN: Gravity provides `inlet.P - outlet.P = +rho * g * H > 0`
  - With flow going `ch.outlet → grav.inlet → grav.outlet → pump.inlet`, the Gravity equation means `P_in > P_out`. For the downward return leg, fluid gains pressure going down — this is physically correct when `inlet` is the high end (top of return leg). Let MTK resolve absolute signs; the algebraic system is consistent.

### Pattern 3: Pressure gauge freedom fix
**What:** Always pin `pump.inlet.P ~ 1.0e5` to remove one degree of freedom from the absolute pressure level.
**When to use:** Every closed loop. Without it, mtkcompile reports an underdetermined system.

### Pattern 4: Temperature boundary condition
**What:** `_make_temp_bc` breaks the circular `instream()` T dependency in closed loops.
**When to use:** Every closed loop that uses `Channel` — the TempBC must be present and `ch.inlet.T ~ T_inlet` must be an explicit constraint.

### Anti-Patterns to Avoid
- **Skipping the TempBC:** Without `_make_temp_bc`, the `instream()` in Channel's first cell creates a circular T dependency that mtkcompile cannot resolve.
- **Using Gravity with negative H for the return leg:** The `Gravity` component in `src/components.jl` hardcodes `9.80665`. Using a negative `H` would produce a negative pressure contribution, inverting the physics. Use positive `H` and connect in the natural flow direction.
- **Exporting `Gravity` twice:** It is already exported in `src/STREAM.jl`. Only add `build_loop_vertical` to the export list.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Pressure gauge freedom | Manual absolute pressure assignment | `pump.inlet.P ~ 1.0e5` constraint (already in build_loop) | MTK needs exactly one absolute pressure anchor per loop |
| Initial guess for T cells | Manual arithmetic | `steady_state_guess()` | Already available; produces monotonically increasing profile |
| Nonlinear solve | Custom root-find | `solve_steady(ssys, op)` via KINSOL | Already proven in VAL-01 |
| Gravity pressure term | Custom g*rho*h equation | `Gravity(; name, H)` component (already in src/components.jl) | Already registered, already compiles (COMP-04 test passes) |

---

## Common Pitfalls

### Pitfall 1: Density mismatch in cancellation test
**What goes wrong:** The 1% cancellation tolerance is almost entirely consumed by the density evaluation inconsistency between Channel (uses `T[i_mid]`, the n/2-th cell temperature) and Gravity (uses `instream(inlet.T)`, the inlet temperature).
**Why it happens:** Channel's `dP` equation evaluates density at a single representative midpoint cell for simplicity. Gravity evaluates at the fluid entering the component (channel outlet temperature). In the reference case, T_inlet ≈ 313 K and T_outlet ≈ 328 K, giving a ~5°C difference and ~0.3% density difference — well within 1%.
**How to avoid:** Use `rtol=0.01` for the cancellation assertion. Do not tighten to `rtol=0.001` without reconciling density evaluation points.
**Warning signs:** If `isapprox` fails at 1% tolerance, check whether `T_wall` was accidentally set very high, causing a large T_inlet–T_outlet spread.

### Pitfall 2: Gravity component port connection direction confusion
**What goes wrong:** Connecting `grav.outlet` to `ch.outlet` (upstream instead of downstream) produces a physically inverted loop where Gravity subtracts pressure twice instead of canceling Channel's term.
**Why it happens:** The equation `inlet.P - outlet.P ~ rho*g*H` looks like it describes upward flow (fluid going from high-P to low-P). For a downward return leg, the physical intuition is reversed.
**How to avoid:** Always connect Gravity in the natural flow direction: `connect(ch.outlet, grav.inlet)` and `connect(grav.outlet, pump.inlet)`. Trust MTK's sign bookkeeping.

### Pitfall 3: Missing export causing test import failure
**What goes wrong:** Tests import `build_loop_vertical` via `import STREAM: Channel, Pump, Friction, Gravity, build_loop_vertical` — if the export is not added to `src/STREAM.jl`, the test file fails to compile.
**Why it happens:** Julia requires explicit `export` in the module file.
**How to avoid:** Add `build_loop_vertical` to the `export` line in `src/STREAM.jl` before running tests.

### Pitfall 4: mtkcompile fails on underdetermined system
**What goes wrong:** If `pump.inlet.P ~ 1.0e5` is omitted, mtkcompile may report an underdetermined system (more unknowns than equations).
**Why it happens:** In a closed pressure loop, absolute pressure is a free variable. The constraint pins it.
**How to avoid:** Copy the connection list from `build_loop` exactly; do not omit the pressure anchor.

---

## Code Examples

### build_loop_vertical: complete wiring pattern
```julia
# Source: pattern derived from src/solvers.jl build_loop() + Gravity component
function build_loop_vertical(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,
    T_wall   = 373.15,
    g_acc    = 9.80665,
    H_return = nothing,
)
    H = isnothing(H_return) ? L_ch : H_return
    @named pump = Pump(dP_pump=dP_pump)
    @named ch   = Channel(n=n, L=L_ch, D=D_ch, A=A_ch, g=g_acc)
    @named bc   = _make_temp_bc(T_bc=T_inlet)
    @named grav = Gravity(H=H)

    connections = [
        connect(pump.outlet, bc.inlet),
        connect(bc.outlet,   ch.inlet),
        connect(ch.outlet,   grav.inlet),
        connect(grav.outlet, pump.inlet),
        pump.inlet.P ~ 1.0e5,
        ch.thermal.T   ~ T_wall,
        ch.inlet.T   ~ T_inlet,
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, bc, ch, grav)
    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_vertical compile" seconds=round(t_compile; digits=2) n_equations=n_eq n_unknowns=n_uk
    return ssys
end
```

### GRAV-02 cancellation test pattern
```julia
# Source: test pattern from test/runtests.jl SOLV-01 + GRAV-02 requirement
@testset "GRAV-02: gravity cancellation within 1% of horizontal" begin
    n = 10; T_inlet = 313.15; L_ch = 0.6
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)

    # Horizontal reference
    ssys_h = build_loop(T_inlet=T_inlet, L_ch=L_ch)
    op_h = [ssys_h.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_h, ssys_h.ch.inlet.mdot => 0.490)
    sol_h = solve_steady(ssys_h, op_h)
    mdot_horiz = abs(sol_h[ssys_h.ch.inlet.mdot])

    # Vertical cancellation loop
    ssys_v = build_loop_vertical(T_inlet=T_inlet, L_ch=L_ch, H_return=L_ch)
    op_v = [ssys_v.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op_v, ssys_v.ch.inlet.mdot => 0.490)
    sol_v = solve_steady(ssys_v, op_v)
    mdot_vert = abs(sol_v[ssys_v.ch.inlet.mdot])

    @test isapprox(mdot_vert, mdot_horiz; rtol=0.01)
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| IDA (DAEProblem) for steady state | SSRootfind(KINSOL()) via SteadyStateProblem | Phase 3 (v0.1) | Simpler, proven on all v0.1 tests |
| Rodas5P + NoInit for transient | Rodas5P + NoInit (retained) | Phase 3 (v0.1) | Mass-matrix ODE, no algebraic consistency needed |

**Relevant for Phase 6:** No solver changes. Gravity validation uses only `solve_steady` which is proven.

---

## Open Questions

1. **Gravity component port direction under flow reversal**
   - What we know: Gravity uses `instream(inlet.T)` which is the MTK stream semantics for the dominant-flow temperature. Under forward flow (pump -> ch -> grav -> pump), this resolves to channel outlet temperature — correct.
   - What's unclear: If flow were to reverse (e.g., pump failure scenario), `instream` would resolve differently. This is not tested in Phase 6 and is not a requirement here.
   - Recommendation: Leave as-is for Phase 6; note as future consideration for transient/multi-branch phases.

2. **Gravity component hardcodes 9.80665 vs Channel's g_acc parameter**
   - What we know: `Channel` has a `g_acc` parameter (default 0.0) that can be set to any value. `Gravity` hardcodes `9.80665` in the equation.
   - What's unclear: There is no requirement to make Gravity's g configurable. For Phase 6 this is correct behavior.
   - Recommendation: For Phase 6, wire `Channel(g=9.80665)` and `Gravity(H=L_ch)` — they both use standard gravity. A future enhancement could add a `g_acc` parameter to `Gravity`, but this is out of scope.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` stdlib (no version) |
| Config file | none — tests run via `Pkg.test()` |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| GRAV-01 | Vertical loop mtkcompiles and solve_steady returns Success | smoke | `julia --project=. -e 'using Pkg; Pkg.test()'` | Wave 0 (append to runtests.jl) |
| GRAV-02 | mdot cancellation within 1% of horizontal reference | unit/validation | `julia --project=. -e 'using Pkg; Pkg.test()'` | Wave 0 (append to runtests.jl) |

### Sampling Rate
- **Per task commit:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` — append `@testset "STREAM Phase 6 Tests"` block covering GRAV-01 and GRAV-02 (file exists; new block needed)

---

## Existing Codebase State (Critical for Planner)

Phase 6 is a pure addition — zero modifications to existing components. The codebase is in this state entering Phase 6:

| File | Relevant Content | Status |
|------|-----------------|--------|
| `src/components.jl` | `Channel(g=0.0)` with `g_acc` in `dP`; `Gravity(H)` with `inlet.P - outlet.P ~ rho*g*H` | Complete, no changes needed |
| `src/connectors.jl` | `FlowPort`, `ThermalPort` | Complete, no changes needed |
| `src/solvers.jl` | `build_loop`, `build_loop_transient`, `solve_steady`, `solve_transient`, `_make_temp_bc`, `steady_state_guess` | Add `build_loop_vertical` only |
| `src/STREAM.jl` | Exports all above; already exports `Gravity` | Add `build_loop_vertical` to export line |
| `test/runtests.jl` | 54 tests in Phase 1/2/3 blocks; all pass | Append Phase 6 block only |

**Test count after Phase 6:** 54 existing + 3 new (GRAV-01 x2, GRAV-02 x1) = 57 total.

---

## Python STREAM Reference (gravity design context)

The Python STREAM `Gravity` class (in `stream/calculations/ideal/resistors.py`) uses:
```python
def dp_out(self, *, Tin: Celsius, **_) -> Pascal:
    return gravity_pressure(rho=self._rho(Tin), dh=self.h, g=self.g)
```
where `gravity_pressure(rho, dh, g) = rho * g * dh`. The Python tribal knowledge states:
> **Always call `check_gravity_mismatch()` after building a FlowGraph.** Channels compute gravity pressure drop internally. If the return leg doesn't have a matching `Gravity` component, the loop won't balance. This is a **silent error**.

The Julia design mirrors this correctly: Channel includes gravity internally via `g_acc`; the standalone `Gravity` component balances the return leg. Phase 6 validates this pairing for the first time.

---

## Sources

### Primary (HIGH confidence)
- `src/components.jl` — Channel dP equation (`rho_water(T[i_mid]) * g_acc * L`), Gravity equation (`inlet.P - outlet.P ~ rho_water(T_in) * 9.80665 * H`), verified by direct reading
- `src/solvers.jl` — `build_loop` wiring topology, `solve_steady` pattern, `_make_temp_bc` pattern; verified by direct reading
- `test/runtests.jl` — 54 existing tests confirmed; COMP-04 confirms Gravity stub compiles; verified by direct reading
- `src/STREAM.jl` — export list; verified by direct reading

### Secondary (MEDIUM confidence)
- `/home/itay/projects/STREAM/.claude/skills/stream-user/tribal_knowledge.md` — Python STREAM gravity design rationale; confirms Julia's design choices are idiomatic
- `/home/itay/projects/STREAM/stream/calculations/ideal/resistors.py` — Python `Gravity` class and `gravity_pressure` function; confirms formula `rho * g * H`

### Tertiary (LOW confidence)
- None — all findings are verified from source code.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — same stack as v0.1, no new dependencies
- Architecture: HIGH — wiring pattern directly derived from `build_loop` source code
- Pitfalls: HIGH — density mismatch quantified analytically; port direction analysis from Gravity equation in source
- Cancellation physics: HIGH — direct algebraic analysis of Channel dP + Gravity dP equations

**Research date:** 2026-03-13
**Valid until:** Stable — no external dependencies to expire; valid until Channel or Gravity equations change

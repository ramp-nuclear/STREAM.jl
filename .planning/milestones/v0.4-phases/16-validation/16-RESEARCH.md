# Phase 16: Validation - Research

**Researched:** 2026-03-15
**Domain:** Julia/MTK quantitative validation — transient ODE solve, two-plate topology, analytical assertions
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**VAL-01: Transient scenario**
- Pure plate test, no fluid — only HeatDiffusion + ConstantTemperature BCs on both faces; no hydraulic loop
- Both faces prescribed at T_wall — thermal_left[i] and thermal_right[i] all set to T_wall via ConstantTemperature BCs
- No internal power — power=0; plate starts uniform at T0 ≠ T_wall and relaxes toward T_wall (pure diffusion)
- Assert at multiple time points: t = {0.5τ, 1τ, 2τ, 5τ} where τ = Lx²/(π²α), α = k_s/(ρ_s·cp_s)
- Aluminum MTR plate parameters: rho_s=2700, cp_s=900, k_s=200 — same as existing VAL tests; nz=10, nx=5, Lx=0.00127m
- τ ≈ 0.002 s (2 ms); 5τ ≈ 10 ms total; fast ODE solve

**VAL-01: Fourier series analytical reference**
- Formula (symmetric BCs, both faces at T_wall, uniform initial T0, no power, center at x=Lx/2):
  T(x,t) = T_wall + (4/π)(T0 - T_wall) Σ_{n odd} (1/n) sin(nπx/Lx) exp(-α(nπ/Lx)²t)
  Assertions use x = Lx/2 → sin(nπ/2) = ±1 for odd n; series converges rapidly for t > 0.1τ
- 50 Fourier terms summed in the analytical reference
- rtol=0.01 (1%) — consistent with all other validation tests in this codebase
- Time span: (0, 5τ); compare at t = 0.5τ, 1τ, 2τ, 5τ (4 assertion points)

**VAL-02: Two HeatDiffusion to one ChannelAndContacts topology**
- Topology: One ChannelAndContacts with BOTH faces simultaneously active:
  - thermal_left[i] → HeatDiffusion_1 (plate1) left face
  - thermal_right[i] → HeatDiffusion_2 (plate2) left face (so plate2 is also on the right of the channel)
- Assembly: Manual connect() wiring — no composition helpers
- Symmetric setup: Both plates identical power, material, geometry (MTR parameters)
- Assertions (all four required):
  1. sol.retcode == ReturnCode.Success
  2. Energy balance: T_rise ≈ (P1 + P2) / (mdot * cp) (both plates heat the single channel, rtol=0.05)
  3. Each plate T_center > T_fluid at midaxial row
  4. Q_flow < 0 on connected faces for each plate

**VAL-03: One-sided T_max analytical assertion**
- "T_center" = hottest point = adiabatic face: sol[ssys.hd.T[nz÷2, nx]]
  - j=nx is the rightmost lateral cell (the adiabatic face) — maximum T for one-sided coupling
- Analytical formula (uniform volumetric generation, left face at T_wall, right face adiabatic, steady state):
  T_max = T_wall_avg + q * Lx / (2 * k_s * A)
  where A = y * Lz (face area of the plate)
- T_wall_avg = mean of sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T] for i in 1:nz
- Integration: Add the assertion to the EXISTING Phase 12 VAL-03 test; do NOT create a new test
- Update the NOTE comment in that test: change "T_plate_center quantitative assertion omitted" to document formula
- Tolerance: rtol=0.01
- Expected values: A = 0.042 m²; ΔT ≈ 0.756 K above T_wall_avg (very small for aluminum)

### Claude's Discretion

- Exact time points for Fourier comparison (can adjust 0.5τ, 1τ, 2τ, 5τ to convenient round numbers in seconds)
- Whether to use solve_transient or raw solve() for the VAL-01 transient test
- How to wire ConstantTemperature BCs to all nz thermal ports (loop vs. vectorized comprehension)
- Exact T0 and T_wall values for the transient test (e.g., T0=400K, T_wall=300K for clear signal)
- Number of cells for VAL-02 (can reuse nz=10, nx=3 for consistency)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| VAL-01 | User can validate HeatDiffusion transient behavior against analytical 1D slab diffusion solution (T_plate_center vs time within tolerance) | Raw ODEProblem/Rodas5P pattern confirmed; ConstantTemperature BC exists; Fourier formula derived and verified; τ computed |
| VAL-02 | User can assemble and solve a system with two HeatDiffusion plates connected to one ChannelAndContacts (both thermal_left and thermal_right active simultaneously) | Manual connect() pattern confirmed from VAL-03; symmetric setup with energy balance assertion; Q_flow sign convention confirmed |
| VAL-03 | One-sided connection test has a quantitative T_plate_center assertion derived from analytical energy balance | Existing test at runtests.jl:1068 identified; T_max formula derived; adiabatic face index confirmed (j=nx); T_wall_avg access pattern confirmed |
</phase_requirements>

---

## Summary

Phase 16 is a pure validation phase — no new components, no new APIs. It adds three quantitative test assertions that prove HeatDiffusion transient behavior and two-plate coupling physics are correct.

**VAL-01** builds a standalone isolated-plate transient: HeatDiffusion with ConstantTemperature BCs on both faces, zero power, initial condition T0 ≠ T_wall, and asserts that the numerical solution matches the analytical 1D Fourier series at four time points. The key insight is that `solve_transient` in solvers.jl is tightly coupled to `build_loop_transient` (Channel-based, step-change callback), so VAL-01 should use a raw `ODEProblem` + `Rodas5P()` with `SciMLBase.NoInit()`. `ConstantTemperature` already exists in components.jl (line 541) and exposes a `.thermal` port; it connects to HeatDiffusion thermal_left/right ports directly.

**VAL-02** tests the Phase 10 two-sided upgrade end-to-end: both thermal_left AND thermal_right of one CAC connected to separate HeatDiffusion plates simultaneously. This is the first test exercising this topology. Uses manual `connect()` (not composition helpers) to keep physics test isolated. The energy balance assertion (T_rise ≈ (P1+P2)/(mdot*cp)) with rtol=0.05 is the key quantitative claim.

**VAL-03** is a minimal in-place addition to the existing Phase 12 test (runtests.jl:1068). Only two things change: (1) a T_max assertion at `j=nx` (adiabatic face) using the formula `T_wall_avg + q*Lx/(2*k_s*A)`, and (2) the NOTE comment is updated to document the formula and the Python discrepancy.

**Primary recommendation:** Split into two tasks — Task 1: VAL-01 (new standalone transient test) + VAL-03 (inline addition to existing test); Task 2: VAL-02 (new two-plate system test). VAL-03 is a few lines appended to an existing test block and naturally groups with VAL-01 as lower-risk modifications.

---

## Standard Stack

### Core (confirmed in this codebase)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | project-installed | System composition, mtkcompile, symbolic indexing | All tests use this |
| OrdinaryDiffEq.jl | project-installed | Rodas5P() stiff ODE solver for transient | Used in existing SOLV-02 test |
| SciMLBase.jl | project-installed | NoInit, ReturnCode.Success, ODEProblem | Used throughout |
| SteadyStateDiffEq.jl | project-installed | solve_steady / KINSOL for VAL-02/03 | Used in all existing VAL tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Test.jl | stdlib | @testset, @test, isapprox | All tests |

### Existing project API for this phase
| Function/Component | Location | Purpose |
|-------------------|----------|---------|
| `HeatDiffusion(...)` | src/components.jl:617 | Plate with T[nz,nx] state, thermal_left/right port arrays |
| `ConstantTemperature(; name, T)` | src/components.jl:541 | Pins `.thermal` ThermalPort to fixed T_bc parameter |
| `ChannelAndContacts(n=...)` | src/components.jl | CAC with thermal_left[i]/thermal_right[i] active |
| `solve_steady(ssys, op)` | src/solvers.jl:99 | KINSOL steady-state solve |
| `Rodas5P()` + `NoInit` | OrdinaryDiffEq + SciMLBase | Stiff ODE with mass matrix, no initialization |

---

## Architecture Patterns

### Pattern 1: Raw Transient Solve for Isolated HeatDiffusion (VAL-01)

**What:** Build an `ODEProblem` directly from the compiled `ssys`, run with `Rodas5P()` and `SciMLBase.NoInit()`. Do NOT use `solve_transient` (it's bound to `build_loop_transient` channel topology).

**When to use:** Any HeatDiffusion transient without a hydraulic loop.

**Pattern (derived from SOLV-02 and solvers.jl:259-272):**
```julia
# Source: src/solvers.jl:259-272 (Rodas5P + NoInit pattern)
prob = ODEProblem(ssys, op_ic, tspan; warn_initialize_determined=false)
sol = solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit(),
            saveat=t_checkpoints)
@test sol.retcode == ReturnCode.Success
# Access: sol[ssys.hd.T[nz÷2, (nx+1)÷2], :]  — time series at center cell
```

**Key: `build_initializeprob=false` applies to `SteadyStateProblem`; for `ODEProblem` the equivalent is `initializealg=SciMLBase.NoInit()`.** Both skip MTK's automatic initialization that corrupts consistent ICs.

### Pattern 2: ConstantTemperature BC Wiring (VAL-01)

**What:** Array of ConstantTemperature components connecting to HeatDiffusion thermal ports.

**Confirmed pattern (from PHY-02/03 tests, runtests.jl:1239-1246):**
```julia
# Source: runtests.jl:1239-1246 (ConstantTemperature array wiring)
ct_l = [ConstantTemperature(name=Symbol(:ct_l_, i), T=T_wall) for i in 1:nz]
ct_r = [ConstantTemperature(name=Symbol(:ct_r_, i), T=T_wall) for i in 1:nz]
conns = [
    [connect(ct_l[i].thermal, getproperty(hd, Symbol(:thermal_left,  i))) for i in 1:nz]...,
    [connect(ct_r[i].thermal, getproperty(hd, Symbol(:thermal_right, i))) for i in 1:nz]...,
]
@named sys = compose(System(conns, t; name=:val01), ct_l..., ct_r..., hd)
ssys = mtkcompile(sys; fully_determined=false)
```

Note: `fully_determined=false` is required for HeatDiffusion systems (confirmed from VAL-03 at runtests.jl:1096).

### Pattern 3: Initial Condition for Transient ODE (VAL-01)

**What:** Set all plate temperatures to T0 (uniform initial condition) in the `op` vector.

```julia
# Source: consistent with existing op patterns in runtests.jl
T0 = 400.0; T_wall = 300.0
op_ic = [ssys.hd.T[i, j] => T0 for i in 1:nz for j in 1:nx]
# No mdot needed — pure thermal system, no flow
```

### Pattern 4: Analytical Fourier Reference (VAL-01)

**Formula (symmetric BC, uniform IC, no power, center x=Lx/2):**
```
T_center(t) = T_wall + (4/π)(T0 - T_wall) * Σ_{n=1,3,5,...,N} ((-1)^((n-1)/2) / n) * exp(-α*(nπ/Lx)²*t)
```
Note: at x=Lx/2, sin(nπ/2) = (-1)^((n-1)/2) for odd n. Sign alternates: +1, -1, +1, -1, ...

**Julia implementation:**
```julia
# Source: derived from standard 1D heat equation Fourier solution
function fourier_T_center(t; T_wall, T0, alpha, Lx, N=50)
    result = T_wall
    for k in 0:(N-1)
        n = 2k + 1   # odd terms only
        coeff = (4/π) * (T0 - T_wall) * ((-1)^k / n)
        result += coeff * exp(-alpha * (n*π/Lx)^2 * t)
    end
    return result
end
alpha = k_s / (rho_s * cp_s)   # = 200/(2700*900) ≈ 8.23e-5 m²/s
tau = Lx^2 / (π^2 * alpha)     # ≈ 0.002 s for MTR aluminum
```

### Pattern 5: Two-Plate Manual Wiring (VAL-02)

**What:** One CAC with thermal_left wired to hd1, thermal_right wired to hd2.

**Pattern (derived from VAL-03 wiring, confirmed from CONTEXT.md topology):**
```julia
# Source: derived from runtests.jl:1092-1093 wiring pattern
conns = [
    # hydraulic loop
    connect(pump.port_out, hx.port_in),
    connect(hx.port_out, cac.port_in),
    connect(cac.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
    cac.port_in.T  ~ T_in,
    # plate 1 → left face
    [connect(getproperty(hd1, Symbol(:thermal_left,  i)),
             getproperty(cac,  Symbol(:thermal_left,  i))) for i in 1:nz]...,
    # plate 2 → right face
    [connect(getproperty(hd2, Symbol(:thermal_left,  i)),
             getproperty(cac,  Symbol(:thermal_right, i))) for i in 1:nz]...,
]
@named sys = compose(System(conns, t; name=:val02), pump, hx, cac, hd1, hd2)
ssys = mtkcompile(sys; fully_determined=false)
```

Note: hd2's `thermal_left[i]` connects to cac's `thermal_right[i]` — the plate's left face faces the channel's right face.

### Pattern 6: Energy Balance Assertion (VAL-02)

```julia
# Source: derived from VAL-03 energy balance at runtests.jl:1133-1134
mdot = sol[ssys.cac.port_in.mdot]
cp_approx = cp_water(T_in)
T_rise_expected = (P1 + P2) / (mdot * cp_approx)
@test isapprox(sol[ssys.cac.T_out] - T_in, T_rise_expected; rtol=0.05)
```

### Pattern 7: T_max Analytical Assertion (VAL-03)

```julia
# Source: CONTEXT.md formula
# Hottest point is adiabatic (right) face, j=nx column
T_max_numerical = sol[ssys.hd.T[nz÷2, nx]]

# T_wall_avg from connected left-face thermal ports
T_wall_vals = [sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T] for i in 1:nz]
T_wall_avg = sum(T_wall_vals) / nz

# Analytical: uniform q, one-sided slab, steady-state
q_total = 1e4          # W
A = y * Lz             # m² = 0.07 * 0.6 = 0.042 m²
q_vol = q_total / (Lx * A)   # W/m³ (but formula uses total flux)
# Direct form: T_max = T_wall_avg + q_total * Lx / (2 * k_s * A)
T_max_analytical = T_wall_avg + q_total * Lx / (2 * k_s * A)
@test isapprox(T_max_numerical, T_max_analytical; rtol=0.01)
```

### Recommended Project Structure for New Tests

New test blocks are appended to the single `runtests.jl` file following the existing phase-section pattern:

```
test/runtests.jl
├── [existing Phase 12 VAL-03 @testset, lines 1068-1141]  ← VAL-03 assertion added inline here
├── [existing Phase 14/15 tests]
└── # Phase 16: Validation [NEW SECTION at end of file]
    ├── @testset "VAL-01: HeatDiffusion transient — Fourier series validation"
    └── @testset "VAL-02: Two-plate one-channel topology — both faces active"
```

### Anti-Patterns to Avoid

- **Using `solve_transient` for VAL-01:** `solve_transient` is coupled to `build_loop_transient` (Channel-based step-change callback). For a pure plate transient, use raw `ODEProblem` + `Rodas5P()`.
- **Using `build_initializeprob=false` kwarg on ODEProblem:** That kwarg belongs to `SteadyStateProblem`. For `ODEProblem`, use `initializealg=SciMLBase.NoInit()`.
- **Omitting `fully_determined=false` in mtkcompile:** HeatDiffusion systems require this (established precedent from VAL-03).
- **T_center at j=(nx+1)÷2 for VAL-03 T_max:** The new assertion uses j=nx (adiabatic face = hottest point for one-sided cooling), not the lateral midpoint.
- **Creating a new @testset for VAL-03:** The decision is to append to the EXISTING Phase 12 VAL-03 @testset, not create a new one.
- **Using sys.hd.thermal_left[i] in connect():** Must use `getproperty(sys.hd, Symbol(:thermal_left, i))` — direct indexed port access fails in connect() context.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Fourier series convergence | Custom convergence logic | Sum 50 terms (N=50 per CONTEXT.md) | For t ≥ 0.5τ, n=50 gives negligible residual; simpler than adaptive sum |
| Analytical T_wall access | Manual parameter extraction | `sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T]` | MTK symbolic indexing works on observed ports after steady solve |
| Transient time-point access | Interpolation code | `sol(t_checkpoint)[ssys.hd.T[i,j]]` or `saveat=` kwarg | ODE solution supports arbitrary-time interpolation or fixed save points |

---

## Common Pitfalls

### Pitfall 1: HeatDiffusion Initialization
**What goes wrong:** mtkcompile or solve fails with initialization errors.
**Why it happens:** MTK's auto-initialization tries to solve for consistent ICs and corrupts the user-provided guess.
**How to avoid:** Always `fully_determined=false` for mtkcompile; always `SciMLBase.NoInit()` for ODEProblem or `build_initializeprob=false` for SteadyStateProblem.
**Warning signs:** Solver returns retcode != Success on first run; T values jump to unrealistic numbers.

### Pitfall 2: VAL-01 Time Points vs. tspan
**What goes wrong:** Fourier assertions at t=0.5τ, 1τ, 2τ, 5τ fail if `tspan` doesn't extend to 5τ or if `saveat` checkpoints aren't inside tspan.
**Why it happens:** tspan must be at least (0.0, 5τ) ≈ (0.0, 0.01). Checkpoints must be within tspan.
**How to avoid:** Compute τ first, set `tspan=(0.0, 5τ)`, pass checkpoints via `saveat=[0.5τ, τ, 2τ, 5τ]`.
**Warning signs:** Interpolation error or index out of bounds when accessing sol at a checkpoint.

### Pitfall 3: VAL-01 Power Must Be Zero
**What goes wrong:** Fourier series formula assumes no internal heat generation. If power != 0, numerical solution diverges from reference.
**Why it happens:** HeatDiffusion defaults to `power=1e6`. Must explicitly set `power=0.0`.
**How to avoid:** Set `power=0.0` in HeatDiffusion constructor for VAL-01.
**Warning signs:** Series never converges to T_wall; T drifts above or below expected bounds.

### Pitfall 4: VAL-02 Two-Plate Q_flow Sign
**What goes wrong:** Q_flow assertion fails or passes vacuously.
**Why it happens:** MTK convention: Q_flow positive = into component. When plate hotter than fluid: Q_flow < 0 on plate's port. But the assertion checks Q_flow at the plate's thermal_left port, which is the heat leaving the plate.
**How to avoid:** Assert `sol[getproperty(ssys.hd1, Symbol(:thermal_left, i)).Q_flow] < 0` for all i.
**Warning signs:** Q_flow tests pass even at wrong sign if `abs()` is accidentally used.

### Pitfall 5: VAL-03 T_wall_avg Access After mtkcompile
**What goes wrong:** `getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T` fails or returns wrong values.
**Why it happens:** After mtkcompile, subsystem namespacing may differ. Must use ssys-qualified path.
**How to avoid:** Use the same pattern as the existing VAL-03 right_syms access at runtests.jl:1137: `getproperty(ssys.hd, Symbol(:thermal_right, i))`. Apply same pattern to cac_l thermal ports.
**Warning signs:** MethodError or KeyError when accessing port temperature.

### Pitfall 6: VAL-02 mdot Initial Guess
**What goes wrong:** KINSOL fails to converge for two-plate setup.
**Why it happens:** mdot guess matters; established project value is +0.250 for rectangular MTR geometry at 30 kPa.
**How to avoid:** Use `mdot_guess = +0.250` and set T_plate guess to a value between T_in and expected T_out.
**Warning signs:** retcode != Success; residual stays large.

---

## Code Examples

### Example 1: Reading mid-plate T from transient solution
```julia
# Source: runtests.jl:310 pattern — symbolic time-series access
T_center_series = sol[ssys.hd.T[nz÷2, (nx+1)÷2], :]   # all time points
# OR with saveat=[t1,t2,...]: sol.u[k] gives state at kth checkpoint
# Simpler: interpolate at specific time
T_at_tau = sol(tau)[ssys.hd.T[nz÷2, (nx+1)÷2]]  # not standard MTK symbolic
# Recommended: use saveat=t_checkpoints, then sol[sym, :][k]
```

### Example 2: Accessing T_wall on CAC thermal port (VAL-03)
```julia
# Source: runtests.jl:1137 (existing right_syms pattern)
left_syms = [getproperty(ssys.cac_l, Symbol(:thermal_left, i)) for i in 1:nz]
T_wall_vals = [sol[left_syms[i].T] for i in 1:nz]
T_wall_avg = sum(T_wall_vals) / nz
```

### Example 3: Phase 15 COMP test end-of-file location (insertion point for VAL-01/02)
```
runtests.jl line 1585: end  (last line of COMP-04 @testset)
# Phase 16 VAL-01 and VAL-02 @testset blocks go after this line
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Python STREAM one_sided_connection for T_out reference | Julia energy balance as truth | Phase 12 (STATE.md decision) | VAL-03 T_out assertion omitted; energy balance used instead |
| Python T_center reference | Analytical formula | Phase 16 (this phase) | Removes dependence on Python STREAM bug |

---

## Open Questions

1. **VAL-01: saveat vs. interpolation for time-point access**
   - What we know: `ODEProblem` + `Rodas5P()` returns an `ODESolution` supporting symbolic indexing
   - What's unclear: Whether `sol[sym, :]` with `saveat=checkpoints` is the cleanest pattern, vs. `sol(t)[sym]` interpolation syntax
   - Recommendation: Use `saveat=[t1, t2, t3, t4]` and `sol[ssys.hd.T[nz÷2, (nx+1)÷2], :][k]` — matches SOLV-02 pattern `sol[ssys.ch.T_out, :]`

2. **VAL-02: nx for HeatDiffusion plates**
   - What we know: CONTEXT.md says "can reuse nz=10, nx=3 for consistency"
   - What's unclear: Whether the T_center assertion `sol[hd1.T[nz÷2, (nx+1)÷2]]` needs nx odd for the midpoint to be an integer index
   - Recommendation: Use nx=3 (odd) so `(nx+1)÷2 = 2` is well-defined; consistent with existing VAL tests

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test.jl (stdlib) |
| Config file | none — single runtests.jl |
| Quick run command | `julia --project test/runtests.jl` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | HeatDiffusion transient T_center(t) matches Fourier series within 1% at 4 time points | integration | `julia --project test/runtests.jl` | Wave 0: new @testset in runtests.jl |
| VAL-02 | Two-plate one-CAC topology assembles and solves; energy balance + T ordering + Q_flow sign all pass | integration | `julia --project test/runtests.jl` | Wave 0: new @testset in runtests.jl |
| VAL-03 | T_max at adiabatic face matches T_wall_avg + q*Lx/(2*k_s*A) within 1% | unit-level assertion | `julia --project test/runtests.jl` | inline addition to existing runtests.jl:1068 |

### Sampling Rate
- **Per task commit:** `julia --project test/runtests.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New `@testset "VAL-01: HeatDiffusion transient — Fourier series validation"` block in `test/runtests.jl` after line 1585
- [ ] New `@testset "VAL-02: Two-plate one-channel topology — both faces active"` block in `test/runtests.jl` after VAL-01
- [ ] Inline T_max assertion + NOTE comment update at `test/runtests.jl:1124-1126` (within existing VAL-03 @testset)

No new source files needed — all implementation is test assertions only.

---

## Sources

### Primary (HIGH confidence)
- `test/runtests.jl` lines 1068-1141 — VAL-03 existing test structure, port access patterns, op format
- `test/runtests.jl` lines 287-313 — SOLV-02 ODEProblem/Rodas5P/NoInit transient pattern
- `src/components.jl` lines 538-545 — ConstantTemperature component confirmed present
- `src/components.jl` lines 562-655 — HeatDiffusion structure, boundary conditions, port naming
- `src/solvers.jl` lines 99-110, 251-273 — solve_steady and solve_transient signatures
- `test/runtests.jl` lines 1239-1251 — ConstantTemperature array wiring pattern (PHY-02 test)
- `.planning/phases/16-validation/16-CONTEXT.md` — locked implementation decisions

### Secondary (MEDIUM confidence)
- CONTEXT.md computed values (τ ≈ 0.002s, ΔT_VAL03 ≈ 0.756K) — cross-checked against formula by inspection

### Tertiary (LOW confidence)
- None — all claims grounded in direct source code inspection

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — confirmed by direct code inspection of runtests.jl, solvers.jl, components.jl
- Architecture: HIGH — all patterns are verified from existing test code in this project
- Pitfalls: HIGH — derived from STATE.md decisions and confirmed MTK behavioral patterns in codebase
- Analytical formulas: HIGH — standard 1D heat equation; confirmed sign convention from CONTEXT.md

**Research date:** 2026-03-15
**Valid until:** Until MTK version upgrade (stable for this project's dependency lock)

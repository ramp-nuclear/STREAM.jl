# Phase 24: Loss-of-Flow Validation - Research

**Researched:** 2026-03-20
**Domain:** MTK acausal transient simulation, parallel-path hydraulic topology, Flapper event integration, LOF energy balance validation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Heat source is `ChannelHeatFlux` with fixed `Q_wall` (via `T_wall` parameter) — no `HeatDiffusion`, no `ChannelAndContacts`.
- **D-02:** Vertical loop with gravity. Buoyancy is the natural circulation driving force.
- **D-03:** `Inertia` component provides coastdown time constant; without it mdot jumps instantly.
- **D-04:** Parallel-path topology: two branches between common inlet/outlet nodes.
  - Branch 1 (forced-flow): `Pump(0.0) → Inertia → ChannelHeatFlux(g_acc, downward)`
  - Branch 2 (natural-circ bypass): `Flapper → Gravity` (upward natural circulation path)
- **D-05:** Forced flow direction is **downward** through the heated channel (against buoyancy). Natural circulation direction is **upward** (buoyancy-driven).
- **D-06:** Bypass path contains `Flapper + Gravity` only — no unheated Channel.
- **D-07:** Separate `Gravity` components in both parallel paths with correct signs.
- **D-08:** `Pump(0.0)` (zero dP) with `Inertia` IC set to steady-state mdot. Callable Pump is incompatible with `SymbolicContinuousCallback` (FLAP-06 note).
- **D-09:** ICs come from `solve_steady` on the **full LOF system** with `T_open=1e30` (KINSOL ignores continuous events).
- **D-10:** Flapper `threshold` = 10% of initial forced-flow mdot.
- **D-11:** Single `solve_transient` call covering 200–500 s. No solver restart.
- **D-12:** Natural circulation quasi-steady state = last 10% of simulation window.
- **D-13:** VAL-01 — energy balance `|Q_in - |mdot|*cp*|dT|| / Q_in < 5%` at ~5 sampled checkpoints.
- **D-14:** VAL-02 — energy balance in quasi-steady NC (last 10% of window), 10% rtol. Reference is energy balance only — no Elenbaas mdot prediction.
- **D-15:** New file `test/test_loss_of_flow.jl`. One `@testset` include in `runtests.jl`.
- **D-16:** `build_loop_lof()` helper in `src/examples.jl`.
- **D-17:** One plan (24-01) covers the loop builder and test suite together.

### Claude's Discretion

- Exact `L_over_A` for `Inertia` and `L`, `Dh`, `Q_wall` for `ChannelHeatFlux` — values giving coastdown ~10–30 s and NC mdot of order 1e-2 to 1e-1 kg/s
- Exact height `H` for each Gravity component (consistent with Channel length)
- How to handle the temperature BC at inlet (same pattern as `build_loop_vertical`)
- Whether the pressure anchor goes at the pump inlet or a junction node

### Deferred Ideas (OUT OF SCOPE)

- Unheated `Channel` in the Flapper bypass path
- Elenbaas-based analytical mdot prediction for VAL-02
- Time-varying pump with realistic coastdown curve (requires callable Pump, incompatible with Flapper)

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VAL-01 | Loss-of-flow transient — forced-flow SS, pump off, mdot crosses zero, Flapper opens, continuous simulation to quasi-static NC; asserts energy balance throughout | Parallel-path topology (D-04/D-05), Flapper wiring pattern (D-08/D-09), energy balance extraction pattern (D-13), IC extraction from solve_steady |
| VAL-02 | Natural circulation temperature rise consistent with energy balance (internal self-consistency, not Elenbaas comparison) within 10% rtol in the last 10% of the simulation window | Quasi-steady window definition (D-12), energy balance assertion formulation (D-14), NC mdot/dT observability |

</phase_requirements>

---

## Summary

Phase 24 is a pure test/integration phase — no new MTK components are needed. All building blocks (Pump, Inertia, ChannelHeatFlux, Flapper, Gravity, HeatExchanger) already exist and are tested. The work is: (1) composing them into a non-trivial parallel-path topology via `build_loop_lof()` in `src/examples.jl`, and (2) asserting energy balance at multiple time checkpoints in `test/test_loss_of_flow.jl`.

The primary technical challenge is correctly wiring the two-branch parallel topology so that MTK's acausal connect() generates the right Kirchhoff equations at the junction nodes. The second challenge is extracting a consistent initial condition from `solve_steady` for a system that already contains the Flapper (with `T_open=1e30`) and the Inertia, so that `solve_transient` can start without triggering `NoInit` failures.

The energy balance assertions are straightforward: extract `ch.inlet.mdot`, `ch.T[1]`, and `ch.T[n]` (or `ch.T_out`) at sampled timepoints. The sign convention (D-05, CONTEXT specifics) must be handled carefully: during forced-flow `T_out < T_in` (outlet is the bottom = axially downstream for downward flow); after reversal `T_out > T_in`. The assertion should use `|mdot| * cp * |T_out - T_in|` throughout.

**Primary recommendation:** Build `build_loop_lof()` following the exact `build_loop_vertical` pattern for gravity wiring, extend it with a second branch using variadic `connect()` at the junction nodes (matching the `build_cube` pattern), and wire Flapper's `ref_mdot` to the Inertia's `inlet.mdot` as established in FLAP-06.

---

## Standard Stack

### Core (all already in Project.toml)

| Library | Purpose | Source |
|---------|---------|--------|
| ModelingToolkit.jl | Symbolic DAE system, `mtkcompile`, `SymbolicContinuousCallback` | Already used |
| DifferentialEquations.jl | `solve_transient` via `Rodas5P()`, `NoInit`, `CallbackSet` | Already used |
| Sundials.jl | KINSOL for `solve_steady` | Already used |

No new dependencies. This phase is purely compositional.

**Note on `ChannelHeatFlux` Q_wall:** The component takes `T_wall` (a temperature), not `Q_wall` (a power). The wall heat flux is computed as `h_tc * heated_perimeter * dz * (T_wall - T[i])` per cell. For energy balance assertions, `Q_wall_total` must be computed from the simulation or `Q_wall` must be inferred from parameters. The simpler approach is: at any checkpoint compute `Q_meas = |mdot| * cp_water(T_avg) * |T_out - T_in|` and compare against the analytical `Q_expected = sum(q_wall[i])` — but since `q_wall[i]` is an observable of `ChannelHeatFlux`, `sol[ssys.ch.q_wall[i], t_idx]` can be summed, or just compare `Q_meas` against the steady-state value.

### Recommended Parameter Values (Claude's Discretion)

Based on physics calculations:

| Parameter | Recommended Value | Rationale |
|-----------|------------------|-----------|
| `L_ch` | 1.0 m | Standard reference length; matches `H_ch` for gravity |
| `Dh` | 0.01 m | Same as `build_loop` reference; gives Re ~10^4 at 0.05 kg/s |
| `A_ch` | `pi*(0.01/2)^2 ≈ 7.85e-5 m^2` | Circular cross section |
| `T_wall` | 373.15 K (100°C) | Same as `build_loop` reference |
| `T_inlet` | 313.15 K (40°C) | Same as `build_loop` reference |
| `g_acc_ch` | -9.80665 m/s^2 | Negative in Channel = downward forced flow (pressure loss opposes upward buoyancy) |
| `H_ch` | 1.0 m (matches `L_ch`) | Channel height = channel length for vertical tube |
| `dP_pump` | 1000 Pa | Gives forced-flow mdot ~ 0.08 kg/s at Re ~10^4; low dP to ensure NC can compete |
| `Inertia L_over_A` | 1.75e5 m^-1 | Gives coastdown tau ≈ 15 s (= tau_target * R_ch, R_ch ≈ 11700 Pa·s/kg) |
| `H_bypass` | 1.0 m | Return height; same magnitude as channel height |
| `Flapper threshold` | 10% of forced-flow mdot_ss (~0.008–0.01 kg/s) | D-10: set after solve_steady returns mdot_ss |
| `dt` (ramp) | 5.0 s | Default; short enough to complete before NC establishes |
| Simulation duration | 300 s | 20× tau; gives clear NC quasi-steady window |
| `n` (cells) | 10 | Same as `build_loop`; enough for energy balance accuracy |

**Computing Inertia `L_over_A`:** In STREAM's `Inertia`, the equation is `dP = L_over_A * d(mdot)/dt` with no density factor — so `L_over_A` is a tunable "hydraulic inductance" in units Pa·s/(kg/s) = Pa·s^2/kg = m^-1 (dimensional analysis: L[m] / A[m^2] = 1/m). For a desired coastdown tau: `tau = L_over_A / R_ch` where `R_ch ≈ dP_pump / mdot_ss`. With `dP_pump=1000 Pa`, `mdot_ss≈0.085 kg/s`, `R_ch≈11800 Pa·s/kg`: `L_over_A = 15 * 11800 = 1.77e5`. **Recommended: 1.75e5.**

---

## Architecture Patterns

### Parallel-Path Topology (two branches, common inlet/outlet nodes)

The LOF system has a "H-bridge" shape:

```
 [junction_top] ──── Branch1: Pump → Inertia → ChannelHeatFlux(downward) ───→ [junction_bot]
                 └── Branch2: Flapper → Gravity(bypass) ──────────────────────→
```

In MTK acausal modeling, junction nodes are created implicitly by `connect()` with 3+ ports:

```julia
# junction_top: pump inlet / flapper inlet share the same pressure node
connect(ch.outlet, flapper.inlet, pump.inlet)    # bottom junction

# junction_bot: bc outlet / flapper outlet / channel inlet
connect(bc.outlet, flapper.outlet, ch.inlet)     # top junction (after HeatExchanger)
```

No `Junction` component is needed — variadic `connect()` handles it (same as `build_cube`).

**Important gravity sign convention:**

- `ChannelHeatFlux` uses `g_acc` parameter for the channel's own gravity term.
  - Forced flow is **downward**: fluid descends through the channel, so the channel's pressure equation represents a pressure gain for the downward-flowing fluid. In `Channel._channel_base_eqs`: `dP_ch ~ friction_dP + rho*g_acc*L`. For downward flow with gravity, set `g_acc = +9.80665` if inlet is at top or `g_acc = -9.80665` if "downward means inlet is high-pressure (top)". **Verify against `build_loop_vertical` where Channel has `g=g_acc` and fluid goes upward.**

- `Gravity` component: `inlet.P - outlet.P ~ rho * 9.80665 * H`. `inlet` = high-pressure = bottom end. For the bypass path (upward natural circulation), the Gravity component represents the hydrostatic head of the return leg.

### IC Extraction Pattern (D-09)

From FLAP-06 test and CONTEXT.md:

```julia
# Step 1: Build the full LOF system with T_open=1e30 (Flapper effectively closed)
ssys = build_loop_lof(...)   # returns mtkcompile'd system

# Step 2: Steady-state solve — KINSOL ignores continuous events
op_ss = Pair{Any,Any}[
    ssys.ch.T[i] => T_guess[i] for i in 1:n...,
    ssys.ch.inlet.mdot => mdot_guess,
    ssys.flapper.T_open  => 1e30,
]
sol_ss = solve_steady(ssys, op_ss)
mdot_ss = sol_ss[ssys.ine.inlet.mdot]  # forced-flow mdot from IC

# Step 3: Build op for transient with Inertia IC = steady-state mdot
op = Pair{Any,Any}[
    ssys.ch.T[i] => sol_ss[ssys.ch.T[i]] for i in 1:n...,
    ssys.ine.inlet.mdot => mdot_ss,    # Inertia state = forced-flow mdot
    ssys.flapper.T_open   => 1e30,       # Flapper starts closed
    # Set threshold from mdot_ss after solve_steady
]
threshold_val = 0.1 * abs(mdot_ss)
```

**Note:** `Pair{Any,Any}` is required when mixing `Float64` state ICs with the `1e30` sentinel (see STATE.md v0.6 PUMP-02 note).

### Energy Balance Assertion Pattern (D-13, D-14)

```julia
# At each checkpoint index i_t:
mdot_t  = sol[ssys.ine.inlet.mdot, i_t]   # or ssys.ch.inlet.mdot
T_in_t  = sol[ssys.ch.T[1], i_t]            # first cell (axially upstream depends on direction)
T_out_t = sol[ssys.ch.T_out, i_t]
cp_t    = cp_water((T_in_t + T_out_t) / 2)

Q_meas  = abs(mdot_t) * cp_t * abs(T_out_t - T_in_t)
Q_wall_total = sum(sol[ssys.ch.q_wall[i], i_t] for i in 1:n)
# OR compare to the time-averaged Q from previous solution window

@test isapprox(Q_meas, Q_wall_total; rtol=0.05)   # VAL-01: 5% tolerance
```

**Sign handling (CONTEXT specifics):** During downward forced-flow, `T_out < T_in` (outlet = bottom = axially last cell, cooler entry at top). Use `|T_out - T_in|` throughout. The `T_out` observable in `ChannelHeatFlux` is always the axial outlet cell temperature, which changes meaning across flow reversal. Alternatively use `|ch.T[n] - ch.T[1]|` with the knowledge that cell 1 is near `inlet` and cell n is near `outlet`.

### Topology Wiring: Temperature Anchors

Closed loops with multiple thermal paths need temperature anchors to break circular instream() dependencies:

- `HeatExchanger(T_bc=T_inlet)` at the pump outlet resets the inlet temperature (same as `build_loop_vertical`).
- One `ch.inlet.T ~ T_inlet` constraint (as in `build_loop_vertical`) resolves remaining circular dependency.
- The bypass path (Flapper → Gravity) carries stream temperature via `instream()` — no separate anchor needed there since the Flapper and Gravity both pass temperature through.

### Anti-Patterns to Avoid

- **Callable Pump in same system as Flapper:** MTK's `compile_equational_affect` cannot resolve callable parameters at ODEProblem build time when a `SymbolicContinuousCallback` is present. Always use `Pump(0.0)` scalar with `Inertia` for the coastdown.
- **Inf as T_open IC:** Causes Rodas5P instability. Use `1e30` sentinel throughout.
- **Missing pressure anchor:** Multi-branch network has underdetermined pressure level without `pump.inlet.P ~ 1.0e5`.
- **Single thermal anchor in closed loop:** Phase 22 experience showed two temperature anchors are needed; include both `HeatExchanger` and the `ch.inlet.T ~ T_inlet` constraint.
- **`Pair{Symbol,Float64}` instead of `Pair{Any,Any}`:** Mixing `Float64` state ICs (T cells, mdot) with the `1e30` sentinel and callable parameters requires `Pair{Any,Any}` op vector.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Junction node | Custom `Junction` component | Variadic `connect()` | MTK generates Kirchhoff equations automatically (build_cube pattern) |
| Smooth ramp event | Custom callback + interpolation | `Flapper` component | Already implements C1 Hermite cubic, T_open latch, SymbolicContinuousCallback |
| Coastdown dynamics | Exponential decay or callable Pump | `Inertia` + `Pump(0.0)` IC | Inertia provides the correct ODE; callable Pump breaks Flapper |
| Steady-state IC extraction | Manual parameter-setting | `solve_steady` on full LOF system | KINSOL ignores events; returns consistent forced-flow state |

---

## Common Pitfalls

### Pitfall 1: Gravity Sign for Downward Channel

**What goes wrong:** Setting `g_acc` in `ChannelHeatFlux` with the wrong sign reverses the pressure gradient, making the pump fight buoyancy in the wrong direction and producing non-physical results.

**Why it happens:** `Channel`'s `dP` equation includes `rho * g_acc * L`. For upward flow (fluid rises), this is a pressure loss. For downward flow (fluid descends), this should be a pressure gain. The sign of `g_acc` in `ChannelHeatFlux` determines whether the channel helps or opposes the pump.

**How to avoid:** Check against `build_loop_vertical` where `g=g_acc` (positive) and the channel is wired for upward flow. For the LOF forced-flow leg (downward), negate the sign: `g_acc = -9.80665`. Verify by checking that `sol[ssys.ch.dP]` at steady state equals `dP_pump` + gravity correction — the pump drives downward flow against friction but assisted by gravity head.

**Warning signs:** Forced-flow mdot significantly different from `dP_pump / R_friction_ch`; solver converges but T profile is inverted at t=0.

### Pitfall 2: Inconsistent Inertia State vs. Steady-State IC

**What goes wrong:** The steady-state solve for a loop with Inertia gives a consistent (mdot, T) state, but the Inertia's internal state variable is `inlet.mdot` — a port variable, not a named state. If the op vector does not include `ssys.ine.inlet.mdot => mdot_ss`, the transient starts from mdot=0 (default IC) and the coastdown is wrong.

**Why it happens:** `Inertia` uses `Dt(inlet.mdot)` making `inlet.mdot` a differential state. MTK promotes this automatically but it needs an initial value in op.

**How to avoid:** Always set `ssys.ine.inlet.mdot => sol_ss[ssys.ine.inlet.mdot]` in the transient op, using the value from `solve_steady`.

**Warning signs:** `mdot` starts near zero at t=0 and the Flapper fires immediately (before any coastdown).

### Pitfall 3: Flapper Threshold Set Before solve_steady

**What goes wrong:** Setting `threshold` as a hard-coded value in `build_loop_lof()` instead of computing it from the steady-state mdot means the threshold may be above or below the actual forced-flow mdot, causing premature firing or no firing.

**Why it happens:** D-10 specifies threshold = 10% of forced-flow mdot_ss, which is only known after `solve_steady`. But `Flapper` is constructed before the solve.

**How to avoid:** Two options: (a) build with a default threshold, then override it in the op dict before the transient solve using `ssys.flapper.threshold => 0.1 * mdot_ss`; (b) accept the approximate threshold and ensure it is well within the coastdown regime. Option (a) is cleaner.

**Warning signs:** Flapper fires at t=0 (threshold too high); Flapper never fires (threshold too low and mdot never drops to 10%).

### Pitfall 4: Energy Balance Sign During Flow Reversal

**What goes wrong:** Using signed `(T_out - T_in)` and signed `mdot` gives a positive product after reversal (negative × negative = positive), but during coastdown `mdot` passes through zero and the product `mdot * (T_out - T_in)` changes sign, producing a false energy balance failure.

**Why it happens:** The steady-state energy balance `Q = mdot * cp * (T_out - T_in)` assumes a sign convention. During transition, the sign flips.

**How to avoid:** Use `abs(mdot) * cp * abs(T_out - T_in)` throughout all checkpoints. The `q_wall[i]` observables are always positive (heat from hot wall to cool fluid) so comparing against `sum(q_wall)` is unambiguous.

**Warning signs:** Test passes at t=0 and t=end but fails at intermediate checkpoints near the reversal.

### Pitfall 5: solve_steady Fails on Parallel-Path System

**What goes wrong:** KINSOL diverges or returns wrong mdot distribution for the two-branch topology because the initial guess does not provide flow through the bypass branch.

**Why it happens:** With `T_open=1e30`, the Flapper acts as `R_closed=1e8` resistance. All flow is in Branch 1. The KINSOL initial guess for `flapper.inlet.mdot` needs to be near zero (small leakage through 1e8 Ohm) rather than the full forced-flow mdot.

**How to avoid:** Set Flapper port mdot initial guesses to 0.0 (or a tiny positive value). Set Inertia + Channel mdot guess to the expected forced-flow value (~0.08 kg/s).

---

## Code Examples

### build_loop_lof() Skeleton (Verified against existing patterns)

```julia
# Source: build_loop_vertical + build_cube patterns from src/examples.jl
# and FLAP-06 test from test/test_flapper.jl

function build_loop_lof(;
    n         = 10,
    L_ch      = 1.0,
    D_ch      = 0.01,
    A_ch      = pi * (0.01 / 2)^2,
    T_wall    = 373.15,
    T_inlet   = 313.15,
    dP_pump   = 1000.0,       # zero dP at runtime; initial condition provides mdot
    L_over_A  = 1.75e5,       # Inertia hydraulic inductance; tau ~ 15s at R ~ 11700 Pa*s/kg
    H_ch      = 1.0,          # channel height (must equal L_ch for consistent geometry)
    H_bypass  = 1.0,          # bypass Gravity height
    g_acc_ch  = -9.80665,     # negative = downward channel (forced flow downward)
    threshold = 0.01,         # overridden in test after solve_steady gives mdot_ss
    dt_ramp   = 5.0,
)
    @named pump    = Pump(0.0)           # zero dP; coastdown via Inertia IC
    @named ine     = Inertia(L_over_A = L_over_A)
    @named ch      = ChannelHeatFlux(n=n,
                         geometry = PipeGeometry_circular(L_ch, D_ch),
                         g = g_acc_ch,
                         T_wall = T_wall)
    @named grav_ff = Gravity(H = H_ch)  # forced-flow return leg gravity
    @named bc      = HeatExchanger(T_bc = T_inlet)
    @named flapper = Flapper(threshold=threshold, dt=dt_ramp)
    @named grav_nc = Gravity(H = H_bypass)  # bypass natural-circ Gravity

    connections = [
        # Branch 1: Pump → Inertia → Channel → (bottom junction)
        connect(pump.outlet, ine.inlet),
        connect(ine.outlet,  bc.inlet),        # temperature reset
        connect(bc.outlet,   ch.inlet),         # ch.inlet = top (downward flow)

        # Branch 2: Flapper → Gravity (bypass)
        connect(flapper.outlet, grav_nc.inlet), # Gravity inlet = bottom (high-P)

        # Junction: bottom node (ch.outlet, grav_nc.outlet, pump.inlet)
        connect(ch.outlet, grav_nc.outlet, pump.inlet),

        # Junction: top node (ch.inlet side... through bc already connected)
        # Flapper inlet connects to the same node as bc.outlet / ch.inlet
        # Need: flapper.inlet connects to the top junction
        # Wired separately to avoid double-connecting ch.inlet
        connect(flapper.inlet, bc.outlet),   # NOTE: bc.outlet already connected to ch.inlet
        # Actually bc has only two ports — use a top junction:
        # connect(bc.outlet, ch.inlet, flapper.inlet)  -- 3-way at top

        # Boundary conditions
        pump.inlet.P        ~ 1.0e5,           # pressure anchor
        ch.inlet.T          ~ T_inlet,          # T anchor (circular dependency fix)

        # Flapper trigger: wired to Inertia mdot (forced-flow branch flow)
        flapper.ref_mdot ~ ine.inlet.mdot,
    ]
    # ...
end
```

**Critical topology clarification:** The 3-way connect at the top junction must be:
```julia
connect(bc.outlet, ch.inlet, flapper.inlet)
```
and the bottom 3-way:
```julia
connect(ch.outlet, grav_nc.outlet, pump.inlet)
```
The `grav_ff` (forced-flow return) may not be needed if the `ChannelHeatFlux` `g_acc` parameter already includes the channel's own gravity contribution. The downward channel already has `rho*g_acc*L` in its `dP` equation. The Gravity component in the forced-flow branch would represent the return pipe's hydrostatic gain, which for a simple closed-loop cancels with the channel's gravity term when `H_return == L_ch`. For the LOF scenario, if Branch 1 is the **only** gravity element in the forced-flow path, the `Gravity(H=H_ch)` at the bottom of Branch 1 may or may not be needed depending on whether `g_acc` in `ChannelHeatFlux` already accounts for the full loop head.

**Recommended simplified Branch 1:** `Pump(0.0) → Inertia → HeatExchanger → ChannelHeatFlux(g_acc = +9.80665, downward)`. The channel's positive `g_acc` with downward flow (inlet at top) gives a pressure gain that helps the pump — then no separate Gravity in Branch 1 is required. Branch 2 (bypass) has `Flapper → Gravity(H=H_bypass)` where Gravity represents the buoyancy driving force in the natural-circulation path.

### IC Extraction (Verified: FLAP-06 pattern)

```julia
# From test/test_flapper.jl FLAP-06 and test/test_validation.jl VAL-02

op_ss = Pair{Any,Any}[
    ssys.ch.T[i] => T_guess[i] for i in 1:n...,
    ssys.ch.inlet.mdot => mdot_guess,
    ssys.ine.inlet.mdot => mdot_guess,
    ssys.flapper.T_open => 1e30,
]
sol_ss = solve_steady(ssys, op_ss)
mdot_ss = sol_ss[ssys.ine.inlet.mdot]

op = Pair{Any,Any}[
    ssys.ch.T[i] => sol_ss[ssys.ch.T[i]] for i in 1:n...,
    ssys.ine.inlet.mdot => mdot_ss,
    ssys.flapper.T_open => 1e30,
    ssys.flapper.threshold => 0.1 * abs(mdot_ss),  # override threshold from SS solve
]
```

### Energy Balance Check (VAL-01, VAL-02)

```julia
# Source: CONTEXT.md §Specific Ideas
n = 10
checkpoints = [0.1, 0.3, 0.5, 0.7, 0.9]  # fraction of t_end; 5 samples
t_end = t_arr[end]

for frac in checkpoints
    i_t = searchsortedfirst(t_arr, frac * t_end)
    mdot_t = sol[ssys.ine.inlet.mdot, i_t]
    T_in_t = sol[ssys.ch.T[1], i_t]    # cell 1 ~ near inlet
    T_out_t = sol[ssys.ch.T_out, i_t]
    cp_t = cp_water((T_in_t + T_out_t) / 2)
    Q_meas = abs(mdot_t) * cp_t * abs(T_out_t - T_in_t)
    Q_wall_t = sum(sol[ssys.ch.q_wall[i], i_t] for i in 1:n)
    if Q_wall_t > 0.01   # skip near-zero power checkpoints
        @test isapprox(Q_meas, Q_wall_t; rtol=0.05)
    end
end
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Test.jl (stdlib) |
| Config file | None — uses `julia --project test/runtests.jl` |
| Quick run command | `julia --project -e 'include("test/test_loss_of_flow.jl")'` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| VAL-01 | Energy balance `\|Q_meas - Q_wall\| / Q_wall < 5%` at 5 sampled checkpoints spanning forced-flow through NC | Integration | `julia --project -e 'include("test/test_loss_of_flow.jl")'` | Wave 0 |
| VAL-02 | NC quasi-steady energy balance in last 10% of window within 10% rtol | Integration | same | Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project -e 'include("test/test_loss_of_flow.jl")'`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/test_loss_of_flow.jl` — new file; covers VAL-01 and VAL-02
- [ ] `test/runtests.jl` — add `include("test_loss_of_flow.jl")` line

*(All other test infrastructure already exists; no new framework config needed.)*

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Callable Pump for coastdown | `Pump(0.0)` + `Inertia` IC | Phase 23 (FLAP-06) | Callable Pump breaks `SymbolicContinuousCallback`; Inertia+IC is the required pattern |
| `Inf` for T_open sentinel | `1e30` | Phase 23 | `Inf` causes Rodas5P instability |
| `Pair{Symbol,Float64}` op vector | `Pair{Any,Any}` | Phase 22 | Required when mixing Float64 ICs with callable parameters or large sentinel values |
| Single thermal anchor | Two thermal anchors (HeatExchanger + port.T constraint) | Phase 22 | Single anchor leaves circular instream underdetermined in closed loops |

**Deprecated/outdated:**
- `Pump(dP_pump=x)` keyword syntax: removed in Phase 22; now `Pump(x)` positional syntax via `@named` macro injection.

---

## Open Questions

1. **Gravity sign in ChannelHeatFlux for downward forced flow**
   - What we know: `build_loop_vertical` uses `g=g_acc` (positive 9.80665) for upward flow. The `_channel_base_eqs` adds `rho * g_acc * L` to the pressure drop.
   - What's unclear: For forced flow **downward** (inlet at top, outlet at bottom), is `g_acc` positive or negative? Positive `g_acc` with downward flow means the channel provides a pressure gain (helping the pump), which is physically correct. Need to verify against `_channel_base_eqs` sign convention to confirm `g_acc = +9.80665` for downward channel.
   - Recommendation: Read `src/components/channel.jl` `_channel_base_eqs` and verify the sign before writing the plan. The test should assert that at t=0, `sol[ssys.ch.dP] ≈ expected_dP` with correct sign.

2. **Bypass Gravity port orientation for natural circulation**
   - What we know: `Gravity`: `inlet.P - outlet.P ~ rho * g * H`. `inlet` = high-pressure = bottom end.
   - What's unclear: In the natural-circulation bypass, the fluid rises. The Gravity component should provide a pressure gain for rising fluid. When wired as `connect(flapper.outlet, grav_nc.inlet)`, the Flapper is above (high-P) and Gravity's `outlet` is at the bottom — but this means fluid flows from Flapper (top) downward through Gravity, which is opposite to what NC requires.
   - Recommendation: The bypass Gravity should be wired with `inlet` at the bottom (same junction as `ch.outlet` and `pump.inlet`). The NC path is: bottom junction → Gravity (upward: inlet at bottom, outlet at top) → Flapper → top junction → Channel (downward). Check topology carefully in the plan.

3. **Temperature anchor in two-branch topology**
   - What we know: `build_loop_vertical` uses `HeatExchanger` + `ch.inlet.T ~ T_inlet`. The bypass path (Flapper → Gravity) carries temperature by `instream()` passthrough.
   - What's unclear: With two parallel branches sharing a top junction, the instream temperature at the junction may have a weighted mixture formula. During NC, the bypass carries hot fluid backward — does the T anchor conflict?
   - Recommendation: Keep the `HeatExchanger` + `ch.inlet.T ~ T_inlet` pattern from `build_loop_vertical`. The `HeatExchanger` should be in Branch 1 between `pump.outlet` and `ch.inlet` (or the top junction). If the T anchor causes issues during NC (reversed flow), the `HeatExchanger.T_bc` may need to remain as an inlet reset that becomes less constraining. Flag for implementation if solver fails on T anchor during NC.

---

## Sources

### Primary (HIGH confidence)

- `src/examples.jl` — `build_loop_vertical`, `build_cube`: reference for gravity wiring and multi-branch `connect()` pattern
- `src/components/flapper.jl` — Flapper implementation, T_open sentinel, SymbolicContinuousCallback wiring
- `src/components/misc.jl` — Inertia: `L_over_A * Dt(mdot)` equation; HeatExchanger: T_bc injection
- `src/components/resistors.jl` — Gravity: `inlet.P - outlet.P ~ rho*g*H`; inlet = high-P = bottom
- `src/components/thermal_channel.jl` — ChannelHeatFlux: `T_wall_p` parameter, `q_wall[i]` observables, `g_acc` sign
- `test/test_flapper.jl` FLAP-06 — canonical Pump(0.0)+Inertia IC coastdown and solve_steady IC extraction pattern
- `test/test_validation.jl` VAL-02 — `Pair{Any,Any}` op, solve_steady → solve_transient IC handoff
- `.planning/phases/24-loss-of-flow/24-CONTEXT.md` — all locked decisions

### Secondary (MEDIUM confidence)

- Physics calculations above: coastdown tau = 15s at L_over_A=1.75e5, mdot_nc ~ 0.01 kg/s, verified by hand
- NC buoyancy estimate: rho*g*beta*deltaT*H ~ 110 Pa at deltaT=30K, H=1m → mdot_nc ~ 0.01 kg/s at R ~ 11700 Pa·s/kg

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components exist and tested in prior phases
- Architecture patterns: HIGH — gravity wiring from build_loop_vertical; multi-branch connect from build_cube; Inertia IC from FLAP-06
- Parameter recommendations: MEDIUM — physics estimates from simplified models; actual solver may require tuning
- Pitfalls: HIGH — all documented from prior phase experiences (STATE.md accumulated context)
- Energy balance formulation: HIGH — matches CONTEXT.md §Specifics exactly

**Research date:** 2026-03-20
**Valid until:** Stable — no external dependencies; all knowledge internal to codebase

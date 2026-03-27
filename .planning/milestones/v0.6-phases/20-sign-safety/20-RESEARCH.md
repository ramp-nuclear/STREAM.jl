# Phase 20: Sign Safety - Research

**Researched:** 2026-03-17
**Domain:** MTK stream connector semantics, first-order upwind finite-volume energy balance, `ifelse()` flow-direction switching
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Upwinding strategy**
- Use `ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)` per-cell — same `ifelse()` idiom as `regime_dependent` and the dP formula
- Forward upstream: `T_up_fwd = (i == 1) ? instream(port_in.T) : T[i-1]`
- Reverse upstream: `T_up_rev = (i == n) ? instream(port_out.T) : T[i+1]`
- `instream(port_out.T)` is the correct MTK idiom for the reverse-flow boundary inlet
- No tanh blend: introduces tuning parameter and non-physical diffusion near mdot = 0
- No event-based switching: belongs in Phase 23 (Flapper)

**Port stream variable fix**
- `port_in.T ~ T[1]` replaces `port_in.T ~ instream(port_out.T)` in ALL three channel variants
- `port_out.T ~ T[n]` unchanged
- Fix in `_channel_base_eqs` propagates to ChannelAndContacts and ChannelHeatFlux automatically
- Channel (channel.jl:91) has its own copy and also needs the fix

**T_out convention**
- `T_out ~ T[n]` stays as-is — positional alias, no direction-dependent ifelse

**Velocity observable sign**
- `v[i]` stays signed: `port_in.mdot / (rho * A)`
- `velocity[i]` changed to unsigned: `abs(port_in.mdot) / (rho * A)` — speed magnitude
- `Re[i]` and `Pe[i]` already use `abs(mdot)` — no change needed

**Test structure (SIGN-04)**
- New file: `test/test_sign_safety.jl`
- Three `@testset` blocks: one per channel variant
- Each testset runs a minimal closed loop with `mdot < 0`
- Assertions per testset:
  1. Reversed temperature profile: `T[1] < T[2] < ... < T[n]`
  2. All `Re[i] > 0` for all cells
  3. Energy balance: `Q_wall ≈ abs(mdot) * cp_water(T_mean) * abs(T[n] - T[1])` within 1% rtol
- Add `include("test_sign_safety.jl")` to `runtests.jl`

### Claude's Discretion
- Exact test loop topology (can reuse existing loop builders with negated mdot, or construct a minimal ChannelHeatFlux-based system)
- Whether to add `test_sign_safety.jl` as a standalone test or as part of an `@testset "Sign Safety"` umbrella
- Whether to split Plan 20-01 (code fixes) and Plan 20-02 (tests) or combine

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SIGN-01 | Channel handles negative `mdot` — Re uses `abs(mdot)`, friction dP flips sign, temperature advection upwinds correctly | Upwind fix in Channel energy loop (channel.jl:62-68) + port_in.T fix (channel.jl:91); dP formula already sign-correct via `mdot * abs(mdot)` |
| SIGN-02 | ChannelAndContacts handles negative `mdot` — same guarantees as SIGN-01; all `@observed` variables (Re, Nu, velocity, Pe) remain physically meaningful | Upwind fix in ChannelAndContacts energy loop (thermal_channel.jl:95-108); `velocity[i]` obs changed to `abs(mdot)/(rho*A)`; Re/Pe already use `abs(mdot)` |
| SIGN-03 | ChannelHeatFlux handles negative `mdot` | Upwind fix in ChannelHeatFlux energy loop (thermal_channel.jl:208-213); port_in.T fix propagates via `_channel_base_eqs` |
| SIGN-04 | Test suite asserts correct reversed temperature profile and positive Re for all three channel types run with `mdot < 0` | New `test/test_sign_safety.jl`; negative mdot via `Pump(mdot0=-X)` pattern |
</phase_requirements>

---

## Summary

Phase 20 is a targeted bug-fix and test phase. There are exactly two defects to correct: a wrong port stream equation (`port_in.T ~ instream(port_out.T)` should be `port_in.T ~ T[1]`) and a forward-only upwind formula that produces incorrect temperature profiles under reverse flow. Both defects are in the energy balance and port-wiring sections of channel.jl and thermal_channel.jl. No new components, no new exports, no solver changes.

The fix strategy uses the project's established `ifelse()` idiom, already present in the dP formula (`mdot * abs(mdot)`) and the `regime_dependent` correlation switcher. Adding a second `instream(port_out.T)` call alongside the existing `instream(port_in.T)` provides the reverse-flow boundary temperature; per-cell upwinding then selects forward or reverse upstream temperature based on the sign of `port_in.mdot`. The `_channel_base_eqs` helper is the single fix point for the port_in.T equation — it propagates to both ChannelAndContacts and ChannelHeatFlux automatically; Channel's constructor has its own copy.

The test strategy uses `Pump(mdot0=-X)` to force a negative mass flow in a minimal closed loop. The existing `HeatExchanger` (temperature boundary reset at port_in side) provides the inlet temperature for the reversed-flow inlet via `instream(port_out.T)`. Three testsets — one per channel variant — each assert a monotonically reversed temperature profile, positive Re, and energy balance closure to 1% rtol.

**Primary recommendation:** Two-plan split — Plan 20-01 fixes all three source files, Plan 20-02 adds the test file and wires it into runtests.jl.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | project's current version | `ifelse()`, `instream()`, `connect = Stream` semantics | Already in use throughout codebase |
| DifferentialEquations.jl | project's current version | `SSRootfind(KINSOL())` for steady-state solve in tests | Already used in all test files |

No new dependencies. All required tools are already present in the project.

### Supporting

None needed beyond what is already imported in `test/test_channel.jl`.

**Installation:** No new packages.

---

## Architecture Patterns

### Files to Modify

```
src/components/channel.jl        # Channel constructor + _channel_base_eqs
src/components/thermal_channel.jl # ChannelAndContacts + ChannelHeatFlux
test/test_sign_safety.jl         # NEW — sign safety test suite (SIGN-04)
test/runtests.jl                 # ADD include("test_sign_safety.jl")
```

### Pattern 1: Per-Cell Upwind Switch with `ifelse()`

**What:** Replace `T_up = (i == 1) ? T_inlet : T[i-1]` with a symbolic conditional that selects upstream cell based on flow direction.

**When to use:** Any per-cell energy balance where upstream temperature changes with flow direction.

**How to set up:** Declare both boundary temperatures before the loop, then compute `T_up` per cell.

```julia
# Before the energy balance loop (in all three channel constructors):
T_inlet_fwd = instream(port_in.T)   # already present (was T_inlet)
T_inlet_rev = instream(port_out.T)  # NEW — reverse-flow boundary inlet

for i in 1:n
    T_up_fwd = (i == 1) ? T_inlet_fwd : T[i-1]
    T_up_rev = (i == n) ? T_inlet_rev : T[i+1]
    T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
    # T_up now used in energy balance equation
end
```

Note: `T_inlet_fwd` is the renamed form of the existing `T_inlet` variable — it is safe to rename in place.

### Pattern 2: Port Stream Variable Fix

**What:** Replace `port_in.T ~ instream(port_out.T)` with `port_in.T ~ T[1]`.

**Why:** MTK stream semantics: `port.T` is the *outflow* temperature from this component through that port. Under reverse flow, fluid exits through port_in at the temperature of the first cell, T[1]. The old equation was wrong but silent because under forward flow, port_in.T gets zero weight in `instream()` computations (max(-mdot, 0) = 0 when mdot > 0).

**Location in `_channel_base_eqs` (channel.jl:156):**
```julia
# OLD (wrong):
push!(eqs, port_in.T ~ instream(port_out.T))

# NEW (correct):
push!(eqs, port_in.T ~ T[1])
```

**Location in Channel constructor (channel.jl:91) — identical fix:**
```julia
# OLD:
push!(eqs, port_in.T  ~ instream(port_out.T))

# NEW:
push!(eqs, port_in.T  ~ T[1])
```

### Pattern 3: Unsigned velocity Observable in ChannelAndContacts

**What:** Change `velocity[i]` observed equation from signed to unsigned.

**Location (thermal_channel.jl:121):**
```julia
# OLD:
push!(obs, velocity[i] ~ port_in.mdot / (rho_water(T[i]) * A))

# NEW:
push!(obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))
```

`v[i]` (the signed alias) stays unchanged at line 120.

### Pattern 4: Negative-mdot Loop for Tests

**What:** Use `Pump(mdot0=-X)` in place of `Pump(dP_pump=X)` to force a predetermined negative mass flow. This is the simplest way to exercise reversed flow without needing a full loss-of-flow transient.

**Why this works:** `Pump(mdot0=-X)` injects `port_in.mdot ~ -X` into the system. The channel will see a negative mdot at port_in throughout the steady-state solve. The `HeatExchanger` (or a bare T pin) on the reverse-flow inlet side sets the temperature entering through port_out via `instream(port_out.T)`.

**Topology for Channel test:**
```julia
# Pump -> HeatExchanger -> Channel -> back to Pump
# But flow direction is reversed: fluid enters Channel at port_out
@named pump = Pump(mdot0 = -0.490)   # negative mdot
@named ch   = Channel(n=n, geometry=..., ...)
@named bc   = HeatExchanger(T_bc=T_inlet)

connections = [
    connect(pump.port_out, bc.port_in),
    connect(bc.port_out, ch.port_in),
    connect(ch.port_out, pump.port_in),
    pump.port_in.P ~ 1.0e5,
    ch.thermal.T   ~ T_wall,
    ch.port_in.T   ~ T_inlet,   # still needed for mtk symmetry
]
```

Under negative mdot the physical inlet is port_out (connected to pump.port_in via bc). The `instream(port_out.T)` call in the upwind formula will return the temperature from the upstream junction.

**Assertions after solve:**
```julia
T_vals = [sol[ssys.ch.T[i]] for i in 1:n]
# Under reverse heating: fluid enters hot end (port_out side = T[n]),
# cools toward T[1]. But if heating is applied (T_wall > T_inlet),
# and flow enters cold (T_inlet < T_wall) through port_out...
# T[n] is the reverse inlet (cold), T[1] is the reverse outlet (warm).
# With wall heating: T[1] > T[2] > ... > T[n]  (decreasing axially)
# OR equivalently: temperature profile is inverted compared to forward flow.
```

Wait — the CONTEXT.md test assertion is `T[1] < T[2] < ... < T[n]`. This means the temperature *increases* from cell 1 to cell n even under reversed flow. This is physically correct when the reverse-flow inlet (through port_out) is at the *cold* temperature `T_inlet`: fluid enters cold at cell n, is heated by the wall as it flows toward cell 1, so T[n] < T[n-1] < ... < T[1]. The assertion `T[1] < T[2]` would be WRONG in that case. Let me re-read the CONTEXT.md assertion carefully.

CONTEXT.md says: `T[1] < T[2] < ... < T[n]` with the label "temperature decreases axially under reverse heating". This is a contradiction in notation — if T[1] < T[n], temperature *increases* axially. The physical meaning is: reverse heating warms the fluid as it moves from inlet (port_out, cell n) to outlet (port_in, cell 1), so T increases from n toward 1 (i.e., T[n] < T[n-1] < ... < T[1]). The CONTEXT.md notation `T[1] < T[2] < ... < T[n]` would mean the profile is increasing left-to-right, which is the SAME as forward flow with T_wall > T_inlet.

**Planner note:** Clarify this assertion in the plan. The most unambiguous test is to assert the profile is monotone *opposite* to the forward-flow case. Concretely:
- Forward flow (mdot > 0, T_wall > T_inlet): T[1] < T[2] < ... < T[n] (T increases axially, outlet is hottest)
- Reverse flow (mdot < 0, T_wall > T_inlet): T[1] > T[2] > ... > T[n] (T decreases axially from cell 1 to cell n, because cell 1 is now the outlet and cell n is the inlet receiving cold fluid from T_inlet boundary)

The safe formulation: under `mdot < 0` with `T_wall > T_inlet`, assert `T[1] > T[n]` (temperature at cell 1 exceeds temperature at cell n) and that the profile is monotone decreasing. This is the reversed profile — it mirrors forward flow reflected about the channel midpoint.

### Anti-Patterns to Avoid

- **Modifying `_channel_base_eqs` energy balance:** `_channel_base_eqs` does NOT contain energy balance equations — it handles dP, T_out, and port wiring only. The upwinding fix belongs in the per-cell loops inside Channel, ChannelAndContacts, and ChannelHeatFlux constructors.
- **Adding a `T_up_rev` parameter to `_channel_base_eqs`:** The function does not need to know about T_up — that is the caller's responsibility. Only the `port_in.T ~ T[1]` fix goes into `_channel_base_eqs`.
- **Using Julia `if/else` instead of `ifelse()`:** Julia's `if/else` on a symbolic `Num` evaluates at trace time and collapses to one branch permanently. Only `ifelse()` emits a symbolic conditional node the solver evaluates per timestep.
- **Adding `velocity[i]` to solver unknowns:** `velocity[i]` is `@observed` in ChannelAndContacts — it lives in the `obs` vector, not in `all_vars`. Changing it to unsigned only requires updating the `obs` push at thermal_channel.jl:121.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Flow direction switching | Custom if/else or tanh blend | `ifelse()` (MTK built-in) | tanh introduces artificial diffusion; if/else collapses at trace time |
| Junction temperature mixing under reverse flow | Manual T-mixing equations | MTK `connect()` + `instream()` | MTK generates the correct flow-weighted mixing formula automatically |
| Negative mdot forcing in tests | Artificial mdot state variable | `Pump(mdot0=-X)` | Already supported by Pump's mdot0 mode; no new components needed |

---

## Common Pitfalls

### Pitfall 1: Applying the Upwind Fix in the Wrong Function

**What goes wrong:** Modifying `_channel_base_eqs` energy balance when there is none there; or missing the ChannelHeatFlux loop at thermal_channel.jl:208-213 which is a separate energy loop not called through `_channel_base_eqs`.

**Why it happens:** `_channel_base_eqs` has a `for i in 1:n` loop for h_tc/v/Re/Nu, making it look like the energy balance location.

**How to avoid:** `_channel_base_eqs` contains ONLY: per-cell h_tc/v/Re/Nu equations (or inlined h_tc in observed_mode), scalar dP/T_out, and port wiring. Energy balance loops are always in the *calling* constructor. Verify by searching for `Dt(T[i])` — it never appears in `_channel_base_eqs`.

**Warning signs:** If the upwinding change is placed in `_channel_base_eqs`, ChannelAndContacts will still use the old forward-only loop in thermal_channel.jl:95-108.

### Pitfall 2: The `port_in.T ~ T[1]` Fix Not Applied to Channel's Own Copy

**What goes wrong:** Fixing `_channel_base_eqs` line 156 but forgetting Channel's own copy at channel.jl:91. Channel does NOT call `_channel_base_eqs` — it builds its own equations inline.

**Why it happens:** `_channel_base_eqs` comment says "Port wiring (4 equations — identical across all channel variants)" which implies it is used by all three, but Channel predates the helper and has its own copy.

**How to avoid:** Fix both locations: channel.jl:91 AND _channel_base_eqs line 156.

### Pitfall 3: Confusion About Which Temperature Is the Reverse-Flow Inlet

**What goes wrong:** Incorrect boundary condition for the reversed-flow test — `instream(port_in.T)` is used for both forward and reverse, so the cold inlet temperature is wrong.

**Why it happens:** `T_inlet = instream(port_in.T)` was the only boundary call before the fix.

**How to avoid:** Explicitly declare `T_inlet_rev = instream(port_out.T)` alongside `T_inlet_fwd = instream(port_in.T)` before the loop. Use `T_inlet_rev` only in the `T_up_rev` branch of the i==n boundary condition.

### Pitfall 4: `velocity[i]` is Observed, Not an Unknown

**What goes wrong:** `velocity[i]` is in the `obs` vector, not `all_vars`. Accidentally adding it to `all_vars` or searching for it in `eqs` will find nothing.

**How to avoid:** The unsigned fix (`abs(...)`) applies to the `push!(obs, velocity[i] ~ ...)` call at thermal_channel.jl:121, not to any equation in `eqs`.

### Pitfall 5: Reverse-Flow Test Assertion Direction

**What goes wrong:** Testing `T[1] < T[2] < ... < T[n]` under reverse flow — this is the FORWARD-flow profile, not reversed. Both could produce this ordering if the logic is symmetric.

**How to avoid:** Under `mdot < 0` with `T_wall > T_inlet` and reverse-flow inlet at `T_inlet` (cold):
- Physical flow direction: port_out side → port_in side (cell n → cell 1)
- Cell 1 is the *outlet* (hot end), cell n is the *inlet* (cold end)
- Correct assertion: `T[1] > T[n]` and profile monotone decreasing from cell 1 to cell n
- Equivalently: `all(T[i] > T[i+1] for i in 1:n-1)`

---

## Code Examples

### Energy Balance Loop with Upwind Fix (Channel pattern)

```julia
# Source: channel.jl energy loop (to be modified)
T_inlet_fwd = instream(port_in.T)   # renamed from T_inlet
T_inlet_rev = instream(port_out.T)  # NEW

for i in 1:n
    T_up_fwd = (i == 1) ? T_inlet_fwd : T[i-1]
    T_up_rev = (i == n) ? T_inlet_rev : T[i+1]
    T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
    push!(eqs,
        Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                   + h_tc[i] * sum(geometry.heated_parts) * dz * (thermal.T - T[i]))
                  / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
    )
    # ... other per-cell eqs unchanged
end
```

### Port Wiring Fix (in _channel_base_eqs)

```julia
# Source: channel.jl _channel_base_eqs port wiring section (line 152-156)
push!(eqs, port_in.mdot + port_out.mdot ~ 0)
push!(eqs, port_out.P - port_in.P       ~ -dP)
push!(eqs, port_out.T                   ~ T[n])
push!(eqs, port_in.T                    ~ T[1])   # WAS: instream(port_out.T)
```

### Velocity Observable Fix (ChannelAndContacts obs loop)

```julia
# Source: thermal_channel.jl obs loop (line 120-121)
push!(obs, v[i]        ~ port_in.mdot / (rho_water(T[i]) * A))        # signed, unchanged
push!(obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))   # unsigned, CHANGED
```

### Minimal Negative-mdot Test Loop (Channel variant)

```julia
# Source: test/test_sign_safety.jl pattern
@testset "SIGN-01/04: Channel reversed flow" begin
    n = 5; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; mdot_neg = -0.490

    @named pump = Pump(mdot0 = mdot_neg)
    @named ch   = Channel(n=n, geometry=PipeGeometry_circular(L_ch, D_ch))
    @named bc   = HeatExchanger(T_bc=T_inlet)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, ch.port_in),
        connect(ch.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        ch.thermal.T   ~ T_wall,
        ch.port_in.T   ~ T_inlet,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, ch)
    ssys = mtkcompile(sys)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=abs(mdot_neg), n=n)
    op = [ssys.ch.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.ch.port_in.mdot => mdot_neg)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    T_vals = [sol[ssys.ch.T[i]] for i in 1:n]
    # Reversed profile: T[1] > T[n] (outlet hot, inlet cold at cell n)
    @test T_vals[1] > T_vals[n]
    @test all(T_vals[i] > T_vals[i+1] for i in 1:n-1)
    # All Re positive
    Re_vals = [sol[ssys.ch.Re[i]] for i in 1:n]
    @test all(Re_vals[i] > 0 for i in 1:n)
    # Energy balance
    T_mean = (T_vals[1] + T_vals[n]) / 2
    Q_actual = abs(mdot_neg) * cp_water(T_mean) * abs(T_vals[1] - T_vals[n])
    Q_wall_val = sum(sol[ssys.ch.q_wall[i]] for i in 1:n)
    @test isapprox(Q_wall_val, Q_actual; rtol=0.01)
end
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `port_in.T ~ instream(port_out.T)` (silent bug) | `port_in.T ~ T[1]` (correct outflow equation) | Phase 20 | Enables correct junction mixing under reverse flow |
| Forward-only upwind: `T_up = T[i-1]` or `T_inlet` | `ifelse(mdot >= 0, T_up_fwd, T_up_rev)` | Phase 20 | Correct temperature advection for negative mdot |
| `velocity[i] ~ port_in.mdot / (rho * A)` (signed) | `velocity[i] ~ abs(port_in.mdot) / (rho * A)` (unsigned speed) | Phase 20 | Satisfies SIGN-02 "physically meaningful" |

---

## Open Questions

1. **Reverse-flow test assertion direction in CONTEXT.md**
   - What we know: CONTEXT.md says `T[1] < T[2] < ... < T[n]` under "reverse heating" but labels this as "temperature decreases axially"
   - What's unclear: The notation conflicts — `T[1] < T[n]` means T increases from cell 1 to cell n (same direction as forward flow), but physically under reversed flow with cold inlet at cell n, T should decrease from cell 1 to cell n (`T[1] > T[n]`)
   - Recommendation: Use `T[1] > T[n]` and `all(T[i] > T[i+1] for i in 1:n-1)` as the assertion (temperature decreases from cell 1 to cell n under reverse heating). This is the physically correct reversed profile. If CONTEXT.md meant the opposite topology (hot inlet at cell n under reverse flow), then T[1] < T[n] would be correct, but that requires T_inlet > T_wall rather than T_wall > T_inlet. Use the natural test setup: T_wall > T_inlet, mdot < 0, infer assertion from physics.

2. **ChannelHeatFlux energy balance loop exact line numbers**
   - What we know: thermal_channel.jl lines 208-213 contain the ChannelHeatFlux energy loop; `T_inlet = instream(port_in.T)` at line 200
   - What's unclear: No ambiguity — reading the source confirmed this
   - Recommendation: Confirmed: ChannelHeatFlux has `T_inlet = instream(port_in.T)` at line 200 and energy loop at lines 208-215. Same fix pattern applies.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`@testset`, `@test`) |
| Config file | none — driven by `test/runtests.jl` include chain |
| Quick run command | `julia --project test/test_sign_safety.jl` (after adding `using Test, STREAM, ...` header) |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SIGN-01 | Channel reversed temperature profile + positive Re | integration | `julia --project test/test_sign_safety.jl` | No — Wave 0 |
| SIGN-02 | ChannelAndContacts observed variables non-negative under mdot < 0 | integration | `julia --project test/test_sign_safety.jl` | No — Wave 0 |
| SIGN-03 | ChannelHeatFlux energy balance under mdot < 0 | integration | `julia --project test/test_sign_safety.jl` | No — Wave 0 |
| SIGN-04 | All three variants pass sign-safety assertions | integration | `julia --project test/test_sign_safety.jl` | No — Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project test/test_sign_safety.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/test_sign_safety.jl` — covers SIGN-01, SIGN-02, SIGN-03, SIGN-04

---

## Sources

### Primary (HIGH confidence)

- Direct source code reading: `src/components/channel.jl` — exact line numbers for both port_in.T bug locations (line 91 in Channel, line 156 in `_channel_base_eqs`) and energy balance loop (lines 61-76)
- Direct source code reading: `src/components/thermal_channel.jl` — ChannelAndContacts energy loop (lines 95-108), obs loop (lines 115-129), ChannelHeatFlux energy loop (lines 208-215)
- Direct source code reading: `src/connectors.jl` — FlowPort T variable carries `[connect = Stream]` annotation, confirming `instream()` / outflow T semantics
- Direct source code reading: `src/components/pump.jl` — `Pump(mdot0=-X)` pattern confirmed valid for negative mdot forcing
- Direct source code reading: `test/test_channel.jl` — existing test patterns (loop topology, op dict construction, `solve_steady` usage)
- CONTEXT.md — all locked decisions are verbatim from the context session (HIGH confidence — authored by this project)

### Secondary (MEDIUM confidence)

- CLAUDE.md `ifelse()` documentation: "Julia's `if/else` on a symbolic `Num` expression would evaluate the branch condition at trace time... `ifelse()` emits a symbolic conditional node that the solver evaluates at each timestep" — confirms the correct idiom

---

## Metadata

**Confidence breakdown:**
- Fix locations: HIGH — all line numbers verified against source
- Fix correctness (`port_in.T ~ T[1]`): HIGH — stream semantics confirmed via connectors.jl + MTK documentation in CLAUDE.md
- Upwinding fix pattern: HIGH — `ifelse()` pattern already used in project (dP formula, regime_dependent)
- Test approach: HIGH — `Pump(mdot0=-X)` confirmed by pump.jl source; loop topology confirmed by existing test_channel.jl
- Test assertion direction: MEDIUM — CONTEXT.md notation has an ambiguity; physics analysis provided; planner should confirm before codifying

**Research date:** 2026-03-17
**Valid until:** This research is based directly on source code, not library docs — valid until the source files change.

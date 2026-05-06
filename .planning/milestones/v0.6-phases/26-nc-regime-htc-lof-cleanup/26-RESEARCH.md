# Phase 26: NC Regime HTC + LOF Cleanup - Research

**Researched:** 2026-03-26
**Domain:** ModelingToolkit correlation extension, natural convection regime switching, Julia observable patterns
**Confidence:** HIGH

## Summary

Phase 26 closes two remaining v0.6 requirements (NATCONV-01 and VAL-02) by wiring Grashof-based natural convection detection into the existing `regime_dependent` factory, applying it to `build_loop_lof_bypass`, and validating the NC temperature rise against an Elenbaas-based analytical estimate. The phase also removes the dead `build_loop_lof` function and fixes three stale docstrings.

All implementation assets already exist in the codebase: `elenbaas_htc` produces the correct 4-arg closure, `Gr()` is a plain Julia function safe for use inside MTK-traced closures, and the `@observed` pattern for adding Gr_over_Re2 to `ChannelAndContacts` is established. The work is additive and backward-compatible — the only destructive change is deleting `build_loop_lof` and its export.

The VAL-02 testset already runs the 300-second LOF transient and computes NC-phase statistics; the ΔT assertion simply slots in after the existing mdot assertion. The key analytical formula is an energy balance: `ΔT_analytical = q_total / (mdot_nc * cp)` where `q_total` is the Elenbaas-predicted wall heat transfer, or equivalently the effectiveness formula `ΔT = (T_wall - T_inlet) * (1 - exp(-h * A / (mdot * cp)))` using the Elenbaas Nu at the NC operating point.

**Primary recommendation:** Follow the locked decisions in CONTEXT.md precisely. All patterns (ifelse NC switching, @observed addition, 4-arg closure forwarding) are established; no new MTK idioms are needed.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** Add three optional kwargs to `regime_dependent`: `htc_natural=nothing`, `Dh=nothing`, `g=nothing`. When all three are provided, the returned HTC closure becomes `ifelse(Gr_val / Re^2 > 1, htc_natural(Re, Pr, T_bulk, T_wall), htc_forced(Re, Pr, T_bulk, T_wall))` — wrapping the existing lam/turb switching as `htc_forced`.

**D-02:** Backward compat: when `htc_natural===nothing`, the returned closures are identical to today — zero overhead, no behavior change. All existing call sites need no update.

**D-03:** Construction-time `@warn` when `Dh` and `g` are provided but `htc_natural===nothing`: `"regime_dependent: Dh and g supplied but htc_natural not provided — NC regime will not be detected."` This fires at construction, not at solve time.

**D-04:** If `htc_natural` is provided but `Dh` or `g` is missing → `ArgumentError` at construction time. Partial NC args are always a mistake.

**D-05:** Gr computed inside the closure using existing `Gr(beta, g, dT, L, nu)` utility — same pattern as `elenbaas_htc` today. No need to `@register_symbolic` Gr.

**D-06:** NC criterion is `Gr_val / Re^2 > 1` (equivalent to `Gr_val > Re^2`), matching Python STREAM convention. No transition blending (v0.7+ concern).

**D-07:** Add `Gr_over_Re2[i]` as `@observed` to `ChannelAndContacts` and `ChannelHeatFlux`. Computed from existing T_wall access: `Gr(beta_water(T[i]), g, T_wall[i] - T[i], Dh, mu_water(T[i])/rho_water(T[i])) / Re[i]^2`.

**D-08:** Do NOT add Gr observable to vanilla `Channel` — T_wall = T_fluid there (adiabatic), so Gr = 0 always, which is meaningless.

**D-09:** Where T_wall[i] = T_fluid[i] at dT=0, Gr_over_Re2 = 0. Correct physical result.

**D-10:** Only `ch` (ChannelHeatFlux) gets NC wiring in `build_loop_lof_bypass`. Wire `regime_dependent` with `htc_natural = elenbaas_htc(b=D_ch, L=L_ch, Dh=D_ch, g=g_acc)`, `Dh=D_ch`, `g=g_acc`, plus `htc_laminar = constant_Nusselt(Nu=8.235)`, `htc_turbulent = dittus_boelter`, `friction_laminar = laminar_friction(1.0)` (circular, aspect_ratio=1), `friction_turbulent = blasius_friction`.

**D-11:** `ret` stays with pure lam/turb `regime_dependent` (no NC args). T_wall = T_fluid in ret → Gr = 0 → NC never activates.

**D-12:** `b` for `elenbaas_htc` in `build_loop_lof_bypass` = `D_ch`.

**D-13:** Physics-driven scoping (NC only in heated ch) preferred over mechanical compliance with SC2 wording.

**D-14:** Add temperature-rise assertion to existing VAL-02 testset. ΔT_analytical via energy balance. Tolerance: 30% rtol.

**D-15:** NC temperature rise measured as `T_nc_max - T_inlet` from simulation vs analytical estimate from Elenbaas Nu at NC operating point.

**D-16:** Delete `build_loop_lof` function body from `src/examples.jl` entirely. No backward-compat shim.

**D-17:** Remove `build_loop_lof` from the `export` line in `src/STREAM.jl`.

**D-18:** Update `Channel`, `ChannelAndContacts`, and `ChannelHeatFlux` docstrings: change `htc_correlation: HTC function (Re, Pr) -> Nu` to `htc_correlation: HTC function (Re, Pr, T_bulk, T_wall) -> Nu`.

**D-19:** Rewrite `24.1-VERIFICATION.md` to reflect actual HEAD state after Phase 26: SC1 PASS (channel inertia via Inertia component), SC2 PASS (4-node bypass topology), SC5/VAL-02 PASS (NC mdot + temperature rise).

**D-20:** No "R_ext not used" stale note exists in current `build_loop_lof_bypass` docstring — already fixed. No action needed.

### Claude's Discretion

- Exact wording of the construction-time `@warn` in `regime_dependent`
- Whether to add both `Gr[i]` and `Gr_over_Re2[i]` as separate observables or just `Gr_over_Re2[i]`
- Exact formula used for VAL-02 ΔT analytical estimate (energy balance approach confirmed; exact algebraic form left to planner)
- Whether to expose `htc_natural`/`Dh`/`g` as additional optional kwargs to `build_loop_lof_bypass`

### Deferred Ideas (OUT OF SCOPE)

- Adding both `Gr[i]` and `Gr_over_Re2[i]` as separate named observables — minimum requirement is `Gr_over_Re2[i]`
- Wiring NC detection into `ret` — physics-driven scoping preferred
- Transition blending between laminar/NC/turbulent regimes — deferred to v0.7+
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NATCONV-01 | `elenbaas_nusselt(Ra, b, L)` usable as pluggable HTC in Channel/ChannelAndContacts | `elenbaas_htc` already produces the 4-arg closure; NATCONV-01 is satisfied when `regime_dependent` can wrap it as `htc_natural` |
| VAL-02 | Natural circulation temperature rise matches analytical estimate using Elenbaas HTC within reasonable tolerance | Extend the existing VAL-02 testset with ΔT assertion after the mdot assertion; use 30% rtol per D-14/D-15 |
</phase_requirements>

---

## Standard Stack

### Core (no new dependencies)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | existing | Symbolic DAE IR, `@observed`, `ifelse` | Already in Project.toml; all patterns established |
| DifferentialEquations.jl | existing | ODE solver for LOF transient | Already used in test_loss_of_flow.jl |

No new packages are needed. Phase 26 is purely additive Julia code using patterns already in the codebase.

**Installation:** none required.

## Architecture Patterns

### Pattern 1: Optional NC kwargs in `regime_dependent` (D-01 through D-06)

**What:** Extend the existing factory function with three keyword args that are `nothing` by default.
**When to use:** When NC regime switching is needed (heated vertical channels).

Current signature (line 138 of `correlations.jl`):
```julia
function regime_dependent(;
    htc_laminar, htc_turbulent,
    friction_laminar, friction_turbulent,
    Re_transition = 2300)
```

Extended signature pattern:
```julia
function regime_dependent(;
    htc_laminar, htc_turbulent,
    friction_laminar, friction_turbulent,
    Re_transition  = 2300,
    htc_natural    = nothing,   # D-01: NC HTC closure (Re,Pr,T_bulk,T_wall)->Nu
    Dh             = nothing,   # D-01: hydraulic diameter for Gr computation [m]
    g              = nothing)   # D-01: gravitational acceleration [m/s^2]
```

Construction-time guard logic (D-03, D-04):
```julia
# D-04: partial NC args → ArgumentError
if !isnothing(htc_natural) && (isnothing(Dh) || isnothing(g))
    throw(ArgumentError("regime_dependent: htc_natural provided but Dh or g is missing — all three (htc_natural, Dh, g) must be supplied together."))
end
# D-03: Dh and g provided but htc_natural missing → warn
if isnothing(htc_natural) && (!isnothing(Dh) || !isnothing(g))
    @warn "regime_dependent: Dh and g supplied but htc_natural not provided — NC regime will not be detected."
end
```

NC-extended HTC closure (D-05, D-06):
```julia
if !isnothing(htc_natural)
    Dh_val = Float64(Dh)
    g_val  = Float64(g)
    # htc_forced wraps the lam/turb ifelse (the existing closure)
    htc_forced_fn = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr,
        htc_laminar(Re, Pr, T_bulk, T_wall),
        htc_turbulent(Re, Pr, T_bulk, T_wall))
    htc_fn = (Re, Pr, T_bulk, T_wall) -> begin
        beta_v = beta_water(T_bulk)
        nu_v   = mu_water(T_bulk) / rho_water(T_bulk)
        Gr_val = Gr(beta_v, g_val, T_wall - T_bulk, Dh_val, nu_v)
        ifelse(Gr_val / Re^2 > 1,
            htc_natural(Re, Pr, T_bulk, T_wall),
            htc_forced_fn(Re, Pr, T_bulk, T_wall))
    end
else
    htc_fn = (Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr,
        htc_laminar(Re, Pr, T_bulk, T_wall),
        htc_turbulent(Re, Pr, T_bulk, T_wall))
end
```

**Key insight:** `Re` inside the closure is a Symbolics.Num when MTK traces equations. `ifelse(Gr_val / Re^2 > 1, ...)` creates a symbolic conditional node — identical to the flow-reversal `ifelse` pattern already used throughout the codebase. `Gr_val` depends on `T_bulk` (also symbolic) via `beta_water` and `mu_water`/`rho_water`, all of which are `@register_symbolic` functions and therefore return symbolic expressions. The `Gr / Re^2` expression traces correctly.

### Pattern 2: `@observed` addition in `ChannelAndContacts` (D-07)

**What:** Add `Gr_over_Re2[i]` to the `obs` block in `ChannelAndContacts`.
**When to use:** Post-solve diagnostic — never referenced on RHS of any equation; qualifies as `@observed` per CLAUDE.md.

`ChannelAndContacts` has an existing `obs = Equation[]` block at line 120 with 11 observed variables. Pattern for adding `Gr_over_Re2`:

1. Add to `@variables` block: `(Gr_over_Re2(t))[1:n]  # observed — Gr/Re² NC criterion`
2. Inside the per-cell obs loop, append:
```julia
Re_i   = abs(inlet.mdot) * Dh / (A * mu_water(T[i]))
nu_i   = mu_water(T[i]) / rho_water(T[i])
Gr_i   = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
push!(obs, Gr_over_Re2[i] ~ Gr_i / Re_i^2)
```

**Important:** `Gr_over_Re2[i]` must NOT appear in `all_vars` (the `eqs`-side variables). It is added only to `obs` and to the declared `@variables` block. The `g_acc` parameter is already declared in `ChannelAndContacts` (`pars` block, line 54).

### Pattern 3: `Gr_over_Re2` in `ChannelHeatFlux` (D-07)

`ChannelHeatFlux` does not use `@observed` mode — Re, Nu, v are plain unknowns. To add `Gr_over_Re2`:

1. Add to `@variables` block: `(Gr_over_Re2(t))[1:n]`
2. Add to `all_vars`: `collect(Gr_over_Re2)`
3. Add to equations (per cell):
```julia
nu_i = mu_water(T[i]) / rho_water(T[i])
push!(eqs, Gr_over_Re2[i] ~ Gr(beta_water(T[i]), g_acc, T_wall_p - T[i], Dh, nu_i) / Re[i]^2)
```

Note: In `ChannelHeatFlux`, T_wall is `T_wall_p` (parameter). The `g_acc` parameter is declared at line 188. In the adiabatic case (`T_wall_p == T[i]`), Gr_over_Re2 = 0, which is correct per D-09.

### Pattern 4: `build_loop_lof_bypass` NC wiring (D-10)

Current `ch` construction (line 439 of examples.jl):
```julia
@named ch = ChannelHeatFlux(n=n, geometry=geom, g=-g_acc, T_wall=T_wall)
```

New construction:
```julia
rd_ch = regime_dependent(
    htc_laminar        = constant_Nusselt(Nu=8.235),
    htc_turbulent      = dittus_boelter,
    friction_laminar   = laminar_friction(1.0),    # circular: aspect_ratio=1 per D-10
    friction_turbulent = blasius_friction,
    htc_natural        = elenbaas_htc(b=D_ch, L=L_ch, Dh=D_ch, g=g_acc),
    Dh                 = D_ch,
    g                  = g_acc,
)
@named ch = ChannelHeatFlux(n=n, geometry=geom, g=-g_acc, T_wall=T_wall,
                             htc_correlation      = rd_ch.htc,
                             friction_correlation = rd_ch.friction)
```

The `ret` channel (line 440) stays unchanged:
```julia
@named ret = Channel(n=n, geometry=geom, g=g_acc)
```

**Note on g sign convention in regime_dependent:** `g_acc` passed to `regime_dependent` is the magnitude (positive, 9.80665). Inside the closure, `Gr(beta, g_val, T_wall - T_bulk, Dh, nu)` uses this positive `g` for Grashof computation. The channel's own gravity sign (`g=-g_acc`) only affects the pressure drop equation — it is a separate parameter internal to the Channel/ChannelHeatFlux component, not related to the HTC closure's Gr computation. Do not negate `g` when passing to `regime_dependent`.

### Pattern 5: VAL-02 ΔT analytical estimate (D-14, D-15)

The existing VAL-02 testset (lines 233-264 of test_loss_of_flow.jl) runs 300 seconds and averages over indices 2701:3001. The ΔT assertion appends after the existing mdot assertion at line 263.

**Analytical formula (energy balance approach):**

```
ΔT_sim        = T_nc_max - T_inlet    (simulation: max ch temp in NC phase)
h_nc          = Nu_elenbaas * k_water(T_inlet) / Dh   (Elenbaas HTC at NC operating point)
A_heated      = π * Dh * L_ch         (heated perimeter × length for circular geometry)
ΔT_analytical = (T_wall - T_inlet) * (1 - exp(-h_nc * A_heated / (mdot_nc * cp_water(T_inlet))))
```

Where `Nu_elenbaas` is computed from `elenbaas_nusselt` at the NC operating point:
```julia
T_bulk_nc = (BYPASS_T_INLET + T_nc_max) / 2
htc_fn    = elenbaas_htc(b=BYPASS_D_CH, L=BYPASS_L_CH, Dh=BYPASS_D_CH, g=BYPASS_G_ACC)
Nu_nc     = htc_fn(0.0, cp_water(T_bulk_nc)*mu_water(T_bulk_nc)/k_water(T_bulk_nc),
                   T_bulk_nc, BYPASS_T_WALL)
h_nc      = Nu_nc * k_water(T_bulk_nc) / BYPASS_D_CH
A_heated  = π * BYPASS_D_CH * BYPASS_L_CH
ΔT_analytical = (BYPASS_T_WALL - BYPASS_T_INLET) *
                (1 - exp(-h_nc * A_heated / (mdot_nc * cp_water(BYPASS_T_INLET))))
@test isapprox(T_nc_max - BYPASS_T_INLET, ΔT_analytical; rtol=0.30)
```

**Note on `T_nc_max` variable:** The existing VAL-02 already computes `T_max_nc` (line 245) over the NC phase — use this directly. The variable is already the max temperature averaged over NC indices, which equals `T_nc_max` in D-15.

### Anti-Patterns to Avoid

- **`@register_symbolic` on Gr inside the closure:** `Gr` is a plain Julia function; it traces correctly through symbolic args. Do not register it.
- **Using Julia `if/else` instead of `ifelse()`:** At MTK trace time, `if Gr_val / Re^2 > 1` would evaluate the symbolic comparison as a Bool, collapsing to a single branch permanently. Must use `ifelse()`.
- **Adding Gr_over_Re2 to `eqs` instead of `obs`:** Gr_over_Re2 is never referenced in any other equation — it is diagnostic-only. It belongs in `obs` for `ChannelAndContacts` (which uses the `observed=obs` System constructor). For `ChannelHeatFlux` (no observed mode), add to `all_vars` and `eqs` as a plain unknown.
- **Negating `g` for the Gr computation:** The `g` passed to `regime_dependent`'s NC kwargs is the gravitational magnitude for Grashof. The channel's directional sign (`g=-g_acc` in ChannelHeatFlux) is a separate physics concern.
- **Leaving `build_loop_lof` body as a stub:** D-16 requires full deletion, not commenting out or wrapping in a deprecation shim.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| NC HTC computation | Custom Gr/Ra/Nu pipeline in regime_dependent | `elenbaas_htc(b, L, Dh, g)` closure | Already implements the 4-arg interface; validated against Python STREAM |
| Regime switching | Custom if/else dispatch | `ifelse()` in closure body | Established pattern; MTK requires symbolic conditionals |
| Gr computation | Inline formula in closure | `Gr(beta, g, dT, L, nu)` utility | Already exported; tested in NATCONV-02 |
| beta, nu computations | Inline fluid property calls | `beta_water(T)`, `mu_water(T)`, `rho_water(T)` | All `@register_symbolic`; trace correctly |
| VAL-02 test infrastructure | New transient solve | Extend existing `_lof_bypass_ic()` and `solve_transient` call | NC-phase statistics already computed; ΔT assertion is additive |

## Common Pitfalls

### Pitfall 1: `ChannelHeatFlux` lacks `@observed` mode — Gr_over_Re2 goes to `eqs`/`all_vars`

**What goes wrong:** Planner puts Gr_over_Re2 in `obs` block for ChannelHeatFlux like it does for ChannelAndContacts. ChannelHeatFlux does not pass `observed=obs` to `System`; only `ChannelAndContacts` uses that constructor argument.

**Why it happens:** The two channel variants have different observable strategies. ChannelAndContacts uses `observed_mode=true` in `_channel_base_eqs` and passes `observed=obs` to `System`. ChannelHeatFlux does not; its Re/Nu/v are plain unknowns in `eqs`/`all_vars`.

**How to avoid:** For ChannelHeatFlux, add Gr_over_Re2 to `eqs` and `all_vars`. For ChannelAndContacts, add to the `obs` vector only (and to `@variables` for the symbol declaration).

**Warning signs:** MTK "variable not found in equations" error or "observed variable declared but no equation" warning.

### Pitfall 2: `Gr_val / Re^2` division-by-zero at Re=0 (adiabatic or zero-flow cells)

**What goes wrong:** During NC phase when `mdot ≈ 0` transiently, `Re ≈ 0`, causing `Gr / Re^2 → ∞`. The `ifelse` will select `htc_natural` which is correct behavior (NC dominates at Re=0), but if the solver evaluates at Re=0 exactly, NaN propagation can occur.

**Why it happens:** `Gr_val / Re^2` is symbolic; at solve time, transitional mdot values near 0 can produce numerically large or indeterminate values.

**How to avoid:** The `ifelse(Gr_val / Re^2 > 1, ...)` formulation already handles this correctly: when Re → 0, Gr/Re² → ∞ > 1, so NC branch is selected. The solver sees finite NC HTC from `elenbaas_htc` even at Re=0 (since elenbaas only uses T_bulk and T_wall). No special guard is needed, but be aware during debugging.

**Warning signs:** NaN in solution at flow reversal transition. If observed, use `Gr_val > Re^2` (mathematically equivalent, avoids explicit division) at the planner's discretion.

### Pitfall 3: `laminar_friction(1.0)` for circular geometry

**What goes wrong:** Planner uses `laminar_friction(0.0)` (thin gap limit) or `laminar_friction(aspect_ratio)` from the rectangular geometry instead of `laminar_friction(1.0)` for the circular channel in `build_loop_lof_bypass`.

**Why it happens:** `laminar_friction` was designed for rectangular ducts. For circular geometry, `aspect_ratio=1.0` gives `K_R ≈ 1.1246`, which yields `f ≈ 56.9/Re` — close to but not exactly `64/Re` (circular). D-10 specifies `laminar_friction(1.0)` explicitly.

**How to avoid:** Follow D-10 literally: `friction_laminar = laminar_friction(1.0)`. Alternatively, use a raw lambda `(Re) -> 64.0 / Re` for true circular. The distinction is minor for the transient test, but follow the decision.

### Pitfall 4: `ChannelHeatFlux` has `T_wall_p` parameter, not `thermal_left[i].T`

**What goes wrong:** Planner tries to use `thermal_left[i].T` for Gr_over_Re2 computation in ChannelHeatFlux, copying the ChannelAndContacts pattern.

**Why it happens:** ChannelAndContacts has ThermalPort arrays; ChannelHeatFlux has a scalar `T_wall_p` parameter baked into the energy balance. There are no thermal ports in ChannelHeatFlux.

**How to avoid:** In ChannelHeatFlux: `Gr_over_Re2[i] ~ Gr(beta_water(T[i]), g_acc, T_wall_p - T[i], Dh, nu_i) / Re[i]^2`. In ChannelAndContacts: use `thermal_left[i].T` (the existing `T_wall_left[i]` pattern already mirrors this).

### Pitfall 5: `24.1-VERIFICATION.md` SC1 rewrite requires understanding of what "PASS" means

**What goes wrong:** Planner writes SC1 as PASS unconditionally without explaining the resolution: the Inertia component (standalone) provides hydraulic inductance, satisfying the physical intent of SC1 even though `_channel_base_eqs` has no `Dt(mdot)` term.

**Why it happens:** The VERIFICATION.md says SC1 failed because "channel.jl has no Dt(inlet.mdot)." D-19 says rewrite to PASS, but the physical justification must be stated.

**How to avoid:** Rewrite SC1 as PASS with note: "Channel momentum inertia is provided by the standalone `Inertia(L_over_A)` component in series with the loop (present in `build_loop_lof_bypass`); direct Dt term in Channel was reverted (commit a8dab81) due to MTK over-determination at parallel junctions. Inertia component achieves the same physics effect."

## Code Examples

### How `elenbaas_htc` is called as `htc_natural` (from existing correlations.jl:196)

```julia
# Source: src/physical_models/correlations.jl lines 196-204
function elenbaas_htc(; b, L, Dh, g = 9.81)
    return (Re, Pr, T_bulk, T_wall) -> begin
        beta   = beta_water(T_bulk)
        nu     = mu_water(T_bulk) / rho_water(T_bulk)
        Gr_val = Gr(beta, g, T_wall - T_bulk, Dh, nu)
        Ra_val = Ra(Gr_val, Pr)
        elenbaas_nusselt(Ra_val, b, L)
    end
end
```

The returned closure already matches the 4-arg interface `(Re, Pr, T_bulk, T_wall) -> Nu`. Pass directly as `htc_natural=elenbaas_htc(b=D_ch, L=L_ch, Dh=D_ch, g=g_acc)`.

### Existing @observed pattern in ChannelAndContacts (from thermal_channel.jl lines 120-135)

```julia
obs = Equation[]
for i in 1:n
    Re_i = abs(inlet.mdot) * Dh / (A * mu_water(T[i]))
    Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
    push!(obs, Re[i]       ~ Re_i)
    push!(obs, Nu[i]       ~ htc_correlation(Re_i, Pr_i, T[i], thermal_left[i].T))
    push!(obs, v[i]        ~ inlet.mdot / (rho_water(T[i]) * A))
    # ... 8 more observed variables
end
```

Add `Gr_over_Re2[i]` by appending inside this loop using `Re_i` already computed.

### Export line to edit (STREAM.jl line 28)

```julia
# Current (line 28):
export build_loop, build_loop_vertical, build_loop_transient, build_cube, build_loop_lof, build_loop_lof_bypass, solve_steady, solve_transient, steady_state_guess, check_gravity_mismatch, port
# After D-17: remove build_loop_lof
export build_loop, build_loop_vertical, build_loop_transient, build_cube, build_loop_lof_bypass, solve_steady, solve_transient, steady_state_guess, check_gravity_mismatch, port
```

### VAL-02 ΔT assertion location

The VAL-02 testset ends at line 264. The assertion inserts after line 263:
```julia
@test isapprox(mdot_nc, mdot_analytical; rtol=0.30)
# NEW: ΔT temperature rise assertion (D-14, D-15)
# ... (analytical formula as described in Pattern 5 above)
@test isapprox(T_max_nc - BYPASS_T_INLET, DeltaT_analytical; rtol=0.30)
```

Note: `T_max_nc` is already computed on line 245. `mdot_nc` is already computed on line 243.

## State of the Art

| Old State | Current State After Phase 26 | Impact |
|-----------|------------------------------|--------|
| `regime_dependent` switches only lam/turb | `regime_dependent` also switches NC via Gr/Re² | NC-correct HTC in LOF transient |
| `build_loop_lof` (dead, series topology) + `build_loop_lof_bypass` (parallel) | Only `build_loop_lof_bypass` | Clean public API |
| VAL-02 validates only mdot (gravity-friction balance) | VAL-02 validates mdot + ΔT temperature rise | Full NC validation per REQUIREMENTS.md |
| Docstrings say `(Re, Pr) -> Nu` interface | Docstrings say `(Re, Pr, T_bulk, T_wall) -> Nu` | Correct API documentation |
| 24.1-VERIFICATION.md shows 3/5 SC | 24.1-VERIFICATION.md shows 5/5 SC PASS | Gap closure complete |

## Open Questions

1. **Gr_over_Re2 with negative dT in ChannelHeatFlux (T[i] > T_wall_p transiently)**
   - What we know: `elenbaas_htc` is designed for T_wall > T_bulk. If T[i] > T_wall_p, dT < 0, and `Gr(beta, g, negative_dT, ...)` gives a negative Gr. `Gr / Re^2 < 0 < 1`, so forced-conv branch is selected by `ifelse` — physically correct.
   - What's unclear: Whether the symbolic expression `Gr / Re^2 > 1` with negative Gr causes solver issues.
   - Recommendation: No guard needed; the `ifelse` semantics handle negative Gr correctly by selecting the forced-conv branch.

2. **Whether to hardcode elenbaas params in `build_loop_lof_bypass` or expose as kwargs (Claude's Discretion)**
   - What we know: D-10 specifies the values; Claude's Discretion allows exposing as optional kwargs.
   - Recommendation: Hardcode in the function body to minimize LOF example API surface. The LOF bypass example is a demonstration, not a general utility. If future tests need different geometry, they can construct `regime_dependent` directly.

## Environment Availability

Step 2.6: SKIPPED — Phase 26 is purely code/config changes with no external dependencies beyond the existing Julia project environment.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (`using Test`) |
| Config file | none — runtests.jl orchestrates via `include()` |
| Quick run command | `julia --project=. -e 'include("test/test_correlations.jl")'` |
| Full suite command | `julia --project=. test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NATCONV-01 | `regime_dependent` with NC kwargs selects `htc_natural` when Gr/Re²>1 | unit | `julia --project=. -e 'include("test/test_correlations.jl")'` | ✅ (extend PHY-04 testset) |
| NATCONV-01 | `regime_dependent` without NC kwargs is unchanged (backward compat) | unit | same | ✅ (existing PHY-04 tests verify) |
| NATCONV-01 | Construction-time `@warn`/`ArgumentError` for partial NC kwargs | unit | same | ✅ (new test in PHY-04) |
| VAL-02 | NC equilibrium ΔT matches Elenbaas estimate within 30% rtol | integration | `julia --project=. -e 'include("test/test_loss_of_flow.jl")'` | ✅ (extend VAL-02 testset at line 263) |
| NATCONV-01 | `Gr_over_Re2[i]` accessible post-solve from ChannelAndContacts and ChannelHeatFlux | integration | `julia --project=. -e 'include("test/test_channel.jl")'` | ❓ Wave 0: may need new test in test_channel.jl |

### Sampling Rate

- **Per task commit:** `julia --project=. -e 'include("test/test_correlations.jl")'` (fast: no transient solve)
- **Per wave merge:** `julia --project=. test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] New test for `regime_dependent` NC kwargs (NATCONV-01 unit) — add inside existing `@testset "PHY-04: regime_dependent switching"` in `test/test_correlations.jl`; no new file needed
- [ ] New test for `Gr_over_Re2` observable access in `ChannelAndContacts` — consider adding to `test/test_channel.jl` or `test/test_correlations.jl` integration section; file exists but specific test is new

## Sources

### Primary (HIGH confidence)

- Direct code read of `src/physical_models/correlations.jl` — `regime_dependent` current interface (line 138), `elenbaas_htc` (line 196), `Gr` utility
- Direct code read of `src/components/thermal_channel.jl` — ChannelAndContacts `@observed` block (line 118-135), ChannelHeatFlux structure
- Direct code read of `src/components/channel.jl` — Channel docstring location, `_channel_base_eqs` helper
- Direct code read of `test/test_loss_of_flow.jl` — VAL-02 testset (lines 233-264), `T_max_nc` variable (line 245), assertion insertion point
- Direct code read of `src/examples.jl` — `build_loop_lof` (lines 314-383), `build_loop_lof_bypass` (lines 385-476)
- Direct code read of `src/STREAM.jl` — export line (line 28)
- Direct code read of `.planning/phases/24.1-bypass-lof-topology/24.1-VERIFICATION.md` — SC1/SC2/SC5 gap context
- `26-CONTEXT.md` — all implementation decisions D-01 through D-20

### Secondary (MEDIUM confidence)

- MTK `ifelse()` for symbolic conditionals — established project pattern, documented in CLAUDE.md §"MTK Patterns"
- `@observed` vs plain unknowns — CLAUDE.md §"MTK Patterns", used extensively in ChannelAndContacts
- `@register_symbolic` semantics — CLAUDE.md §"MTK Patterns", explains why Gr does not need it

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all patterns already in codebase
- Architecture: HIGH — exact code structure read from source; patterns verified
- Pitfalls: HIGH — identified from direct code inspection of both channel variants
- VAL-02 formula: MEDIUM — energy balance formula is standard thermal engineering; exact variable names confirmed from test file; 30% rtol matches existing mdot assertion

**Research date:** 2026-03-26
**Valid until:** 2026-04-26 (stable Julia/MTK codebase; no external API dependencies)

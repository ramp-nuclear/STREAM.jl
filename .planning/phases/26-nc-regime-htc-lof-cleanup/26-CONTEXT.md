# Phase 26: NC Regime HTC + LOF Cleanup - Context

**Gathered:** 2026-03-26
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire natural convection detection (Gr/Re²>1 criterion, matching Python STREAM) into `regime_dependent`; use it in `build_loop_lof_bypass` so the NC phase of a LOF transient uses Elenbaas HTC; validate NC temperature rise against Elenbaas prediction; add Gr/Re² as @observed to ChannelAndContacts and ChannelHeatFlux; remove dead `build_loop_lof`; fix all stale docs from v0.6 audit.
</domain>

<decisions>
## Implementation Decisions

### regime_dependent NC Extension

- **D-01:** Add three optional kwargs: `htc_natural=nothing`, `Dh=nothing`, `g=nothing`. When all three are provided, the returned HTC closure becomes `ifelse(Gr_val / Re^2 > 1, htc_natural(Re, Pr, T_bulk, T_wall), htc_forced(Re, Pr, T_bulk, T_wall))` — wrapping the existing lam/turb switching as `htc_forced`.
- **D-02:** Backward compat: when `htc_natural===nothing`, the returned closures are identical to what `regime_dependent` returns today — zero overhead, no behavior change. All existing call sites need no update.
- **D-03:** Construction-time `@warn` when `Dh` and `g` are provided but `htc_natural===nothing`: `"regime_dependent: Dh and g supplied but htc_natural not provided — NC regime will not be detected."` This fires at construction, not at solve time (MTK symbolic tracing makes runtime warnings in closures impossible).
- **D-04:** If `htc_natural` is provided but `Dh` or `g` is missing → `ArgumentError` at construction time. Partial NC args are always a mistake.
- **D-05:** Gr computed inside the closure using existing `Gr(beta, g, dT, L, nu)` utility — same pattern as `elenbaas_htc` today. No need to `@register_symbolic` Gr.
- **D-06:** NC criterion is `Gr_val / Re^2 > 1` (equivalent to `Gr_val > Re^2`), matching Python STREAM convention. Agreed in memory; no transition blending (v0.7+ concern).

### Gr/Re² Observable in Channel Components

- **D-07:** Add `Gr_over_Re2[i]` as `@observed` to `ChannelAndContacts` and `ChannelHeatFlux`. Computed from existing T_wall access in each component: `Gr(beta_water(T[i]), g, T_wall[i] - T[i], Dh, mu_water(T[i])/rho_water(T[i])) / Re[i]^2`. Users can inspect NC regime post-solve via `sol[sys.ch.Gr_over_Re2, :]`.
- **D-08:** Do NOT add Gr observable to vanilla `Channel` — T_wall = T_fluid there (adiabatic), so Gr = 0 always, which is meaningless and misleading.
- **D-09:** Where T_wall[i] = T_fluid[i] at dT=0, Gr_over_Re2 = 0 (no NC drive). This is the correct physical result for adiabatic or matched-temperature cells.

### build_loop_lof_bypass Wiring

- **D-10:** Only `ch` (ChannelHeatFlux) gets NC wiring. Wire `regime_dependent` with `htc_natural = elenbaas_htc(b=..., L=L_ch, Dh=D_ch, g=g_acc)`, `Dh=D_ch`, `g=g_acc`, plus `htc_laminar = constant_Nusselt(Nu=8.235)`, `htc_turbulent = dittus_boelter`, `friction_laminar = laminar_friction(1.0)` (circular, aspect_ratio=1), `friction_turbulent = blasius_friction`.
- **D-11:** `ret` (unheated return Channel) stays with pure lam/turb `regime_dependent` (no NC args). Reason: ret has T_wall = T_fluid (no ThermalPort) → Gr = 0 → NC would never activate anyway.
- **D-12:** `b` (gap between plates) for `elenbaas_htc` in `build_loop_lof_bypass` = `D_ch` (the circular channel diameter, used as characteristic gap). Consistent with how `Dh = D_ch` for circular geometry.
- **D-13:** Slight deviation from ROADMAP SC2 ("for both ch and ret") — user-confirmed that physics-driven scoping (NC only in heated ch) is preferred over mechanical compliance with SC2 wording.

### VAL-02 Temperature Rise Test

- **D-14:** Add a temperature-rise assertion to the existing VAL-02 testset. Analytical formula: `ΔT_analytical = (T_wall - T_inlet) * (1 - exp(-h_tc * A_heated / (mdot_nc * cp)))` ≈ `q_wall_total / (mdot_nc * cp_water(T_inlet))` where `q_wall_total = T_wall - T_nc_avg_bulk` times the effective conductance. Simplified to energy balance: `ΔT_sim = T_nc_max - T_inlet`, `ΔT_analytical = (T_wall - T_inlet) * (1 - exp(-Nu * k * π * Dh * n / (mdot_nc * cp * Dh)))`. Tolerance: 30% rtol — consistent with the existing mdot assertion.
- **D-15:** NC temperature rise is measured as `T_nc_max - T_inlet` from the simulation (max channel temperature at NC equilibrium) vs the analytical estimate computed from Elenbaas Nu at the NC operating point.

### Dead Code Removal

- **D-16:** Delete `build_loop_lof` function body from `src/examples.jl` entirely (lines ~315–383). No backward-compat shim.
- **D-17:** Remove `build_loop_lof` from the `export` line in `src/STREAM.jl`.

### Stale Doc Fixes

- **D-18:** Update `Channel`, `ChannelAndContacts`, and `ChannelHeatFlux` docstrings: change `htc_correlation: HTC function (Re, Pr) -> Nu` to `htc_correlation: HTC function (Re, Pr, T_bulk, T_wall) -> Nu`. Three files affected: `src/components/channel.jl`, `src/components/thermal_channel.jl` (covers both CAC and CHF).
- **D-19:** Rewrite `24.1-VERIFICATION.md` to reflect actual HEAD state after Phase 26: SC1 (channel inertia via Inertia component in D-series branch) PASS, SC2 (4-node bypass topology) PASS, SC5/VAL-02 (NC mdot + temperature rise) PASS.
- **D-20:** No "R_ext not used" stale note exists in the current `build_loop_lof_bypass` docstring — already fixed. No action needed on that specific item.

### Claude's Discretion

- Exact wording of the construction-time `@warn` in `regime_dependent`
- Whether to add both `Gr[i]` and `Gr_over_Re2[i]` as separate observables or just `Gr_over_Re2[i]` (the useful one for NC detection)
- Exact formula used for VAL-02 ΔT analytical estimate (energy balance approach confirmed; exact algebraic form left to planner)
- Whether to expose `htc_natural`/`Dh`/`g` as additional optional kwargs to `build_loop_lof_bypass` (so callers can tune NC wiring), or hardcode elenbaas_htc in the function body
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### NC correlation and regime switching
- `src/physical_models/correlations.jl` — `regime_dependent` (current interface to extend), `elenbaas_htc`, `elenbaas_nusselt`, `Gr()`, `Ra()`, `beta_water()`
- `src/physical_models/correlations.jl:138` — `regime_dependent` function definition; new optional kwargs go here

### Channel components (Gr observable + docstring fixes)
- `src/components/channel.jl` — `Channel` component; stale `(Re, Pr) -> Nu` docstring at line ~16
- `src/components/thermal_channel.jl` — `ChannelAndContacts` (stale docstring line ~32) and `ChannelHeatFlux` (same issue); Gr_over_Re2 observable goes into the `@observed` block of ChannelAndContacts (~line 118) and ChannelHeatFlux

### LOF example
- `src/examples.jl` — `build_loop_lof` (delete, lines ~315–383) and `build_loop_lof_bypass` (wire NC for ch)
- `src/STREAM.jl:28` — export line; remove `build_loop_lof`

### Validation test
- `test/test_loss_of_flow.jl` — VAL-02 testset (lines ~233–264); extend with ΔT assertion
- `test/test_loss_of_flow.jl:1–50` — `_lof_bypass_ic()` helper and BYPASS_* constants (geometry for analytical estimate)

### Verification doc to rewrite
- `.planning/phases/24.1-bypass-lof-topology/24.1-VERIFICATION.md` — rewrite SC1/SC2/SC5 to PASS after Phase 26 work is complete

### Project-level rules
- `CLAUDE.md` §"MTK Patterns" → `@observed` vs plain unknowns — Gr_over_Re2 is post-solve diagnostic, qualifies as @observed
- Memory: `project_htc_regime_future_work.md` — NC detection Gr/Re²>1 agreed; transition blending deferred to v0.7+
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `elenbaas_htc(; b, L, Dh, g=9.81)` in `correlations.jl:196` — already implements the 4-arg closure interface; used directly as `htc_natural` in `regime_dependent`
- `regime_dependent(; htc_laminar, htc_turbulent, friction_laminar, friction_turbulent, Re_transition=2300)` in `correlations.jl:138` — receives new optional NC kwargs without changing the existing required kwargs
- `Gr(beta, g, dT, L, nu)` in `correlations.jl` — plain Julia function; already used inside `elenbaas_htc`; safe for use inside regime_dependent closure
- Existing `@observed` block in `ChannelAndContacts` (`thermal_channel.jl:118`) — 10 variables already (Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right); Gr_over_Re2[i] is a natural addition
- VAL-02 testset already sets up `_lof_bypass_ic()`, runs 300s transient, computes NC-phase statistics — ΔT assertion slots in after existing mdot assertion

### Established Patterns
- `ifelse()` for regime switching (not Julia `if/else`) — critical for MTK symbolic tracing; established in both `regime_dependent` and `Channel` flow reversal
- `@observed` for diagnostic-only variables never referenced on RHS of other equations — Gr_over_Re2 is diagnostic-only, correct usage
- Construction-time `@warn` pattern: used elsewhere in codebase (e.g. `check_gravity_mismatch`); acceptable for surface-level guidance without breaking solve

### Integration Points
- `build_loop_lof_bypass` in `examples.jl:422` creates `ChannelHeatFlux` with no correlation overrides — this is where `regime_dependent` gets wired
- `src/STREAM.jl:28` single export line — both `build_loop_lof` removal and `regime_dependent` (already exported) live here
- `test_correlations.jl` — should have a test for the new NC detection path in `regime_dependent`
</code_context>

<specifics>
## Specific Ideas

- Gr_over_Re2 is the *ratio* the user wants to inspect post-solve (not raw Gr) — name it `Gr_over_Re2` to make the NC criterion transparent at the REPL
- Construction-time warning is sufficient for the "user forgot htc_natural" case; no runtime warning mechanism is possible inside MTK-traced closures
- VAL-02 uses 30% rtol for both mdot and ΔT — consistent tolerance policy across all NC validation assertions
</specifics>

<deferred>
## Deferred Ideas

- Adding both `Gr[i]` and `Gr_over_Re2[i]` as separate named observables — planner may decide to add both for completeness, but minimum requirement is `Gr_over_Re2[i]`
- Wiring NC detection into `ret` (return Channel) in `build_loop_lof_bypass` — user confirmed physics-driven scoping is preferred (NC never activates in adiabatic ret); can be revisited if multi-material or heated-return scenarios arise
- Transition blending between laminar/NC/turbulent regimes — deferred to v0.7+ per agreed architecture in memory
</deferred>

---

*Phase: 26-nc-regime-htc-lof-cleanup*
*Context gathered: 2026-03-26*

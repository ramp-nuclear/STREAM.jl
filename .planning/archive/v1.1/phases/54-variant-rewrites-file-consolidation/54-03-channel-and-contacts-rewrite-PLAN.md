---
phase: 54
plan: 03
type: execute
wave: 3
depends_on: [54-01, 54-02]
files_modified:
  - src/components/channels.jl
autonomous: true
requirements: [VAR-03]
must_haves:
  truths:
    - "ChannelAndContacts(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction, scb_correction=nothing) constructs and mtkcompiles"
    - "ChannelAndContacts uses ThermalPort arrays per side (CONN-03 carry-forward, no connector change)"
    - "ChannelAndContacts computes h_tc[i] internally via correlation (single-phase) or correlation+SCB (two-phase) — matches legacy logic structurally"
    - "Optional scb_correction kwarg augments h_tc[i] without flag plumbing in core"
    - "ChannelAndContacts feeds q_left_expr/q_right_expr (= h_tc * heated_parts * dz * (T_wall - T)) into _channel_core"
    - "ChannelAndContacts retains legacy variant-internal observables: h_tc_left, h_tc_right, T_wall_left, T_wall_right, Gr_over_Re2, Q_wall_total, Nu"
    - "HeatDiffusion connection point preserved — symmetric_plate(cac, fuel) wiring still works (CAC is the only variant that wires to HD)"
  artifacts:
    - path: "src/components/channels.jl"
      provides: "Adds new ChannelAndContacts constructor"
      contains: "function ChannelAndContacts(;"
  key_links:
    - from: "src/components/channels.jl ChannelAndContacts"
      to: "src/components/channels.jl _channel_core"
      via: "core = _channel_core(; ...; q_left_expr, q_right_expr, ...)"
      pattern: "_channel_core\\(;\\s*n"
    - from: "src/components/channels.jl ChannelAndContacts"
      to: "src/connectors.jl ThermalPort"
      via: "thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]"
      pattern: "ThermalPort\\(;\\s*name=Symbol\\(:thermal_left"
---

<objective>
Add the new `ChannelAndContacts` constructor to `src/components/channels.jl`, built on top of `_channel_core`. CAC keeps its existing `ThermalPort` array shape (CONN-03 carry-forward) and its existing variant-internal `h_tc[i]` correlation logic (with optional SCB augmentation), but delegates energy balance / friction / port wiring / observable boilerplate to `_channel_core`. Implements decision D-08, D-09.

Purpose: VAR-03 — `ChannelAndContacts` rebuilt on `_channel_core` with no behavioral change at the API surface (constructor signature, `ThermalPort` arrays, observable surface) and no flag plumbing for SCB. Internal `h_tc[i]` equations migrate verbatim from the legacy CAC body (`src/components/thermal_channel.jl` lines 105-165). Only the surrounding scaffolding (energy balance loop at 167-194, port wiring at 132-136, observable loops at 200-229) is replaced by `_channel_core`.

Output: New `ChannelAndContacts` block appended to `src/components/channels.jl` after the new `ChannelHeatFlux`. Method-overwriting warnings on `using STREAM` are expected (legacy CAC at thermal_channel.jl:48-246 is shadowed). 54-04 deletes the legacy file.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md
@.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md
@CLAUDE.md
@src/components/channels.jl
@src/components/thermal_channel.jl
@src/connectors.jl
@src/composition/helpers.jl

<interfaces>
<!-- Reference: legacy CAC at src/components/thermal_channel.jl lines 48-246. The h_tc and SCB blocks
     (lines 105-165) migrate verbatim into the new CAC. Everything else is replaced by _channel_core. -->

From src/components/channels.jl after 54-01/54-02:
```julia
function _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
    friction_correlation, q_left_expr, q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right,
    T_out, dP)::NamedTuple{(:eqs, :obs)}
```

D-08 constructor signature (unchanged from legacy):
```julia
ChannelAndContacts(;
    name, n::Int, geometry::PipeGeometry, g=0.0,
    htc_correlation = dittus_boelter,
    friction_correlation = blasius_friction,
    scb_correction = nothing,
)
```

D-09 q-expression construction (per cell):
```julia
q_left_expr[i]  = h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
q_right_expr[i] = h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
```
Plus channel-side Q_flow eqns:
```julia
thermal_left[i].Q_flow  ~ q_left_expr[i]
thermal_right[i].Q_flow ~ q_right_expr[i]
```

Variant-internal observables (D-09 — kept from legacy CAC):
- `h_tc[i]` — unknown (correlation-driven, with optional SCB ifelse)
- `Nu[i]` — observed (htc_correlation output)
- `h_tc_left[i] ~ h_tc[i]` — observed alias
- `h_tc_right[i] ~ h_tc[i]` — observed alias
- `T_wall_left[i] ~ thermal_left[i].T` — observed alias
- `T_wall_right[i] ~ thermal_right[i].T` — observed alias
- `Gr_over_Re2[i]` — observed (Gr-over-Re² for natural-convection criterion)
- `velocity[i]` — observed (legacy alias)
- `Q_wall_total ~ sum(q_wall[i])` — observed scalar
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add new ChannelAndContacts to src/components/channels.jl</name>
  <files>src/components/channels.jl</files>
  <read_first>
    - src/components/channels.jl (full file, post-54-01 and post-54-02 — read to see Channel and CHF and where to append CAC)
    - src/components/thermal_channel.jl (lines 1-246 — legacy CAC with full h_tc + SCB + observables; the h_tc / SCB blocks at 105-165 migrate verbatim, observables at 200-229 migrate as variant-internal obs)
    - .planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md (D-08, D-09)
    - .planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md (D-02, D-03, D-08, D-09, D-10, D-14 — _channel_core API contract, observable ownership rules, Q_wall_total decision)
    - CLAUDE.md (Component authoring conventions; MTK Patterns — `ifelse()` for SCB switching, `@register_symbolic` boundary, `@observed` discipline)
    - src/composition/helpers.jl (symmetric_plate, plate, one_sided_connection, port — used by HeatDiffusion connection)
  </read_first>
  <action>
    Append a new `ChannelAndContacts` block to `src/components/channels.jl` after the new `ChannelHeatFlux`. Use D-08 signature unchanged from legacy:

    ```julia
    """
        ChannelAndContacts(; name, n, geometry, g=0.0,
                           htc_correlation=dittus_boelter,
                           friction_correlation=blasius_friction,
                           scb_correction=nothing) -> ODESystem

    Convective channel with per-cell `ThermalPort` arrays on both sides for conjugate heat
    transfer (the variant that connects to `HeatDiffusion`). Internal HTC correlation
    (single-phase or correlation+SCB-enhanced) drives per-cell `h_tc[i]`; q is computed
    inside the variant as `h_tc[i] * heated_parts * dz * (T_wall - T[i])` and fed into
    `_channel_core` for the energy balance and the rest of the channel physics.

    # Arguments
    - `name`: system name (Symbol)
    - `n`: number of axial cells (Int)
    - `geometry`: pipe geometry descriptor (PipeGeometry)
    - `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
    - `htc_correlation`: HTC function `(Re, Pr, T_bulk, T_wall) -> Nu`, default `dittus_boelter`
    - `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`
    - `scb_correction`: optional SCB heat flux closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]`,
      e.g. from `regime_dependent_q_scb(pressure=...)`. When provided, `h_tc[i]` is enhanced
      by the Bergles-Rohsenow partial boiling factor when `T_wall[i] >= T_ONB[i]`.
      Default `nothing` (pure single-phase).

    # Ports
    - `port_in`, `port_out` -- `FlowPort`
    - `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell, per side)

    # Returns
    Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
    """
    function ChannelAndContacts(;
        name,
        n::Int,
        geometry::PipeGeometry,
        g=0.0,
        htc_correlation=dittus_boelter,
        friction_correlation=blasius_friction,
        scb_correction=nothing,
    )
        Dh = geometry.Dh
        A  = geometry.A
        L  = geometry.L
        Dt = Differential(t)

        pars = @parameters begin
            L = L
            D_h = Dh
            A = A
            g_acc = g
        end

        # ----------------------------------------------------------------
        # Variables — variant declares ALL @variables that _channel_core references
        # by symbol (Phase 53 D-10), PLUS variant-specific observables (Phase 53 D-09):
        # h_tc[i] (UNKNOWN — needed for SCB convergence per ISCB-01), Nu, h_tc_left/right,
        # T_wall_left/right, Gr_over_Re2, velocity, Q_wall_total.
        # h_tc default IC 5000.0 (ISCB-01: prevents MTK cyclic guesses init error in SCB).
        # ----------------------------------------------------------------
        vars = @variables begin
            (T(t))[1:n] = fill(600.0, n)
            (dp(t))[1:n] = fill(100.0, n)
            (h_tc(t))[1:n] = fill(5000.0, n)
            (Re(t))[1:n]
            (Pe(t))[1:n]
            (v(t))[1:n]
            (P(t))[1:n]
            (T_sat(t))[1:n]
            (T_ONB(t))[1:n]
            (q_wall(t))[1:n]
            (q_wall_left(t))[1:n]
            (q_wall_right(t))[1:n]
            (Nu(t))[1:n]
            (h_tc_left(t))[1:n]
            (h_tc_right(t))[1:n]
            (T_wall_left(t))[1:n]
            (T_wall_right(t))[1:n]
            (Gr_over_Re2(t))[1:n]
            (velocity(t))[1:n]
            T_out(t) = 600.0
            dP(t)
            Q_wall_total(t)
        end

        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        thermal_left  = [ThermalPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
        thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]

        dz = L / n

        # ----------------------------------------------------------------
        # h_tc[i] equation — single-phase OR correlation + SCB.
        # MIGRATED VERBATIM from legacy CAC (thermal_channel.jl lines 111-117 single-phase
        # branch and 141-164 SCB branch). Only the surrounding scaffolding changes.
        # All expressions are inlined (no observed-to-observed chains; ISCB-01 + Pitfall 7).
        # ----------------------------------------------------------------
        variant_eqs = Equation[]
        if scb_correction === nothing
            for i in 1:n
                Re_i  = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
                Pr_i  = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
                T_w_i = thermal_left[i].T
                push!(variant_eqs, h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh)
            end
        else
            for i in 1:n
                Re_i  = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
                Pr_i  = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
                T_w_i = thermal_left[i].T
                h_spl_i = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh

                # Inline P[i] (NOT the P[i] symbol) — Pitfall 7 (avoid observed-to-observed chain)
                P_i = port_in.P - sum(dp[j] for j in 1:i) -
                      (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
                T_sat_i = sat_temperature(P_i)
                # max(q_spl, 0) guards _bergles_rohsenow_dT_ONB against DomainError
                # (SCB-01 / v0.7 retrospective).
                q_spl_i = max(h_spl_i * (T_w_i - T[i]), 0.0)

                q_scb_i     = scb_correction(T_w_i, T_sat_i, Re_i)
                T_ONB_i     = T_sat_i + _bergles_rohsenow_dT_ONB(P_i, q_spl_i)
                q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i)
                factor_i    = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

                push!(variant_eqs, h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i))
            end
        end

        # ----------------------------------------------------------------
        # D-09 q-expression construction (per cell). Uses h_tc[i] (the unknown) — core
        # consumes the symbol by reference. Channel-side Q_flow eqns close ThermalPort.
        # When the wall port dangles (no HD connection on that face), MTK's Flow rule
        # auto-zeros Q_flow ⇒ either thermal_*[i].T = T[i] (adiabatic) or h_tc=0 (which
        # cannot happen since h_tc has its own equation) — so unconnected sides settle
        # to the equilibrium where q_*_expr[i] = 0 ⇒ T_wall[i] = T[i]. Adiabatic ✓.
        # ----------------------------------------------------------------
        q_left_expr  = Vector{Num}(undef, n)
        q_right_expr = Vector{Num}(undef, n)
        for i in 1:n
            q_left_expr[i]  = h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
            q_right_expr[i] = h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
            push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
            push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
        end

        # ----------------------------------------------------------------
        # Q_wall_total — Phase 53 D-14 — kept as CAC-side observable for backward compat.
        # ----------------------------------------------------------------
        push!(variant_eqs, Q_wall_total ~ sum(q_wall[i] for i in 1:n))

        # ----------------------------------------------------------------
        # Hand off to _channel_core (Phase 53 D-01 / D-03).
        # ----------------------------------------------------------------
        core = _channel_core(;
            n, T, dp, port_in, port_out, geometry,
            g_acc=g, friction_correlation,
            q_left_expr, q_right_expr,
            Re, Pe, v, P, T_sat, T_ONB,
            q_wall, q_wall_left, q_wall_right,
            T_out, dP,
        )

        # ----------------------------------------------------------------
        # Variant-internal observables (Phase 53 D-09):
        # Nu[i] (correlation output, not in core), h_tc_left/right (aliases of h_tc),
        # T_wall_left/right (aliases of thermal_*[i].T), Gr_over_Re2 (NC criterion;
        # references variant-specific T_w − T[i] which core doesn't see),
        # velocity (legacy alias). All inlined so no observed-to-observed chains.
        # ----------------------------------------------------------------
        variant_obs = Equation[]
        for i in 1:n
            Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
            push!(variant_obs, Nu[i] ~ htc_correlation(Re_i, Pr_i, T[i], thermal_left[i].T))
            push!(variant_obs, h_tc_left[i]  ~ h_tc[i])
            push!(variant_obs, h_tc_right[i] ~ h_tc[i])
            push!(variant_obs, T_wall_left[i]  ~ thermal_left[i].T)
            push!(variant_obs, T_wall_right[i] ~ thermal_right[i].T)
            push!(variant_obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))
            nu_i = mu_water(T[i]) / rho_water(T[i])
            Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
            push!(variant_obs, Gr_over_Re2[i] ~ Gr_i / Re_i^2)
        end

        eqs = [variant_eqs; core.eqs]
        obs = [core.obs; variant_obs]

        all_vars = [
            collect(T); collect(dp); collect(h_tc);
            collect(Re); collect(Pe); collect(v);
            collect(P); collect(T_sat); collect(T_ONB);
            collect(q_wall); collect(q_wall_left); collect(q_wall_right);
            collect(Nu); collect(h_tc_left); collect(h_tc_right);
            collect(T_wall_left); collect(T_wall_right);
            collect(Gr_over_Re2); collect(velocity);
            T_out; dP; Q_wall_total
        ]

        compose(
            System(eqs, t, all_vars, pars; observed=obs, name=name),
            port_in, port_out, thermal_left..., thermal_right...,
        )
    end
    ```

    Notes:
    - **`h_tc[i]` stays as an unknown, not observed.** The legacy CAC at thermal_channel.jl:73 declares `h_tc` with `fill(5000.0, n)` IC for SCB convergence (per STATE.md "v0.7 ISCB-01"). Preserve this exactly. Single-phase `h_tc[i] ~ correlation*k/Dh` is technically a closed-form expression that could be observed, but ISCB-01 documents that promoting it to observed broke initialization in v0.7 — keep as unknown.
    - **`Nu`, `h_tc_left`, `h_tc_right`, `T_wall_left`, `T_wall_right`, `velocity`, `Gr_over_Re2`** are observables. They are pure expressions of unknowns / port across-vars (no observed-to-observed chains).
    - **Why no `q_wall[i]` re-declaration:** core already emits `q_wall[i] ~ q_left_expr[i] + q_right_expr[i]` as an observable. CAC's `Q_wall_total ~ sum(q_wall[i])` reads from core's `q_wall[i]` symbol — that's why CAC declares `q_wall(t)[1:n]` in its `@variables` block (so the symbol exists for the LHS of core's observable and the RHS of CAC's `Q_wall_total` eqn).
    - **`Q_wall_total` placement:** added to `variant_eqs` (not `variant_obs`) because the legacy code declared it as an unknown and pushed `Q_wall_total ~ sum(q_wall[i])` to `eqs` (thermal_channel.jl:91, 196). Preserve that shape — `Q_wall_total(t)` is in the `@variables` block (no `[1:n]`) and the equation is in eqs. (Phase 53 D-14 confirms this is fine.)
    - **The legacy `ChannelAndContacts` in `src/components/thermal_channel.jl`** continues to exist after this plan. Method-overwriting warning expected. 54-04 deletes the legacy file.
  </action>
  <verify>
    <automated>bin/jl -e 'using STREAM; cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); ssys = mtkcompile(cac); @info "compiled" n_eqs=length(equations(ssys)) n_unk=length(unknowns(ssys))'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q "function ChannelAndContacts(;" src/components/channels.jl`
    - `grep -q "scb_correction=nothing" src/components/channels.jl`
    - `grep -q "thermal_left  = \\[ThermalPort(; name=Symbol(:thermal_left" src/components/channels.jl` (CAC retains ThermalPort, NOT WallPort)
    - `grep -q "h_tc\\[i\\] \\* geometry.heated_parts\\[1\\] \\* dz \\* (thermal_left\\[i\\].T  - T\\[i\\])" src/components/channels.jl`
    - `grep -q "thermal_left\\[i\\].Q_flow  ~ q_left_expr\\[i\\]" src/components/channels.jl`
    - `grep -q "Q_wall_total ~ sum(q_wall\\[i\\] for i in 1:n)" src/components/channels.jl`
    - `grep -q "Gr_over_Re2\\[i\\] ~ Gr_i / Re_i\\^2" src/components/channels.jl`
    - `grep -q "ifelse(T_w_i >= T_ONB_i, h_spl_i \\* factor_i, h_spl_i)" src/components/channels.jl` (SCB branch present)
    - `bin/jl -e 'using STREAM; cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); mtkcompile(cac)'` exits 0
    - `bin/jl -e 'using STREAM; cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01), scb_correction=regime_dependent_q_scb(pressure=1.0e5)); mtkcompile(cac)'` exits 0 (SCB path compiles)
  </acceptance_criteria>
  <done>
    `ChannelAndContacts` constructor in `src/components/channels.jl` with D-08 signature unchanged from legacy. ThermalPort arrays per side. Single-phase and SCB-corrected `h_tc[i]` equations migrated verbatim from legacy CAC. q construction per D-09. `Q_wall_total ~ sum(q_wall[i])` retained. Variant observables (Nu, h_tc_left/right, T_wall_left/right, Gr_over_Re2, velocity) in place. Constructs and `mtkcompile`s on both single-phase and SCB-enabled paths.
  </done>
</task>

</tasks>

<verification>
- `bin/jl -e 'using STREAM; cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); ssys = mtkcompile(cac)'` exits 0.
- `bin/jl -e 'using STREAM; cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01), scb_correction=regime_dependent_q_scb(pressure=1.0e5)); ssys = mtkcompile(cac)'` exits 0 (SCB compiles).
- The new CAC body has `ThermalPort` arrays (NOT WallPort), `h_tc[i]` as unknown with `fill(5000.0, n)` IC, both single-phase and SCB-corrected branches, and all CAC-only observables (Nu, h_tc_left/right, T_wall_left/right, Gr_over_Re2, velocity, Q_wall_total).
- Method-overwriting warning is acceptable.
</verification>

<success_criteria>
1. `ChannelAndContacts` constructor in `channels.jl` with D-08 signature unchanged from legacy (kwarg names, defaults, `scb_correction` shape).
2. Uses `ThermalPort` arrays per side per cell (CONN-03 carry-forward, NOT WallPort, NOT HeatFluxPort).
3. `h_tc[i]` is a per-cell unknown with `fill(5000.0, n)` IC and a single-phase OR SCB-corrected equation (migrated verbatim from legacy CAC, lines 111-117 / 141-164).
4. q construction per D-09: `q_*_expr[i] = h_tc[i] × heated_parts × dz × (T_wall - T[i])`.
5. Channel-side Q_flow eqns emitted per side per cell.
6. Variant-internal observables retained: `Nu[i]`, `h_tc_left[i]`, `h_tc_right[i]`, `T_wall_left[i]`, `T_wall_right[i]`, `Gr_over_Re2[i]`, `velocity[i]`, `Q_wall_total`.
7. All energy balance / friction / momentum / port wiring delegated to `_channel_core`.
8. Constructs and `mtkcompile`s on a 4-cell unit smoke without error, both single-phase and SCB-enabled.
</success_criteria>

<output>
After completion, create `.planning/phases/54-variant-rewrites-file-consolidation/54-03-SUMMARY.md` documenting:
- New ChannelAndContacts placement in channels.jl (line range)
- Both single-phase and SCB-enabled `mtkcompile` sizes (n_eq, n_unknowns)
- Whether method-overwriting warnings surfaced and their content
- Any deviation from D-08 signature or D-09 q construction (none expected)
- Confirmation that `h_tc[i]` is still an unknown with `fill(5000.0, n)` IC (ISCB-01)
</output>

# channels.jl — Channel, ChannelHeatFlux, ChannelAndContacts variants
# and shared `_channel_core` for STREAM.jl.
#

# Declare Channel as a new generic function independent of Base.Channel{T}
# (Base.Channel is Julia stdlib's task-communication channel; STREAM.Channel is unrelated)
function Channel end


"""
    _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
                  friction_correlation=blasius_friction,
                  q_left_expr, q_right_expr,
                  Re, Pe, v, P, T_sat, T_ONB,
                  q_wall, q_wall_left, q_wall_right,
                  T_out, dP)::NamedTuple

Shared private helper for STREAM channel-family components. Single source of truth
for energy balance (enthalpy form with face-averaged cp), mass conservation,
momentum ODE `(L/A)*Dt(mdot)`, per-cell friction (algebraic dp[i]), port wiring,
and observables.

Returns `(; eqs, obs)` — variant splices `eqs = [variant_specific_eqs; core.eqs]`,
`obs = [core.obs; variant_specific_obs]`. Variant declares all `@variables`
(unknowns AND observables that core references); core builds equations referencing
those symbols.

# Arguments
- `n::Int`                                          : number of axial cells
- `T`, `dp`                                         : variant-declared `@variables (T(t))[1:n]`, `(dp(t))[1:n]`
- `port_in`, `port_out`                             : variant-created `FlowPort`s
- `geometry::PipeGeometry`                          : pipe geometry descriptor
- `g_acc::Real`                                     : gravitational acceleration [m/s^2]
- `friction_correlation`                            : friction closure `(Re) -> f`
- `q_left_expr`, `q_right_expr`                     : length-n `Vector{Num}`, per-cell heat flow inputs (W) — variant builds these
- `Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right` : variant-declared observable LHS symbols
- `T_out, dP`                                       : variant-declared scalar observable LHS symbols

# Returns
NamedTuple `(; eqs::Vector{Equation}, obs::Vector{Equation})` — the variant
splices these into its own equation lists before building the `System`.

# Energy balance per cell (enthalpy form, face-averaged cp)

    cp_face = (cp_water(T_up) + cp_water(T[i])) / 2
    Dt(T[i]) ~ (|mdot|*cp_face*(T_up - T[i]) + q_left_expr[i] + q_right_expr[i])
              / (rho_water(T[i]) * cp_water(T[i]) * A * dz)

"""
function _channel_core(;
    n::Int,
    T,
    dp,
    port_in,
    port_out,
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr,
    q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB,
    q_wall, q_wall_left, q_wall_right,
    T_out, dP,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n
    Dt = Differential(t)

    eqs = Equation[]
    obs = Equation[]

    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    for i in 1:n
        # Flow-reversal upwind selection — single ifelse (D-07, NRG-04).
        # The (i == 1)/(i == n) ternaries collapse at trace time (Julia ?:),
        # so cell 1 forward / cell n reverse correctly use the boundary face.
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)

        # Face-averaged cp — boundary face uses same averaging as interior (D-05).
        # Both branches of T_up run through cp_water; @register_symbolic ensures
        # cp_water is opaque to Symbolics and faithfully transports the ifelse
        # selection at runtime (D-07, NRG-04). NO second ifelse for cp.
        cp_face = (cp_water(T_up) + cp_water(T[i])) / 2     # NRG-01, NRG-02

        # Energy balance — enthalpy form (D-06).
        # Numerator: cp_face (face-averaged); denominator: cp_water(T[i]) (local).
        # The two cp values do NOT cancel (NRG-03) — they coincide only in the
        # constant-cp limit (T_up == T[i]).
        push!(eqs,
            Dt(T[i]) ~ (
                abs(port_in.mdot) * cp_face * (T_up - T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )

        # Per-cell friction dp[i] — algebraic (Pitfall 5: inline Re for friction
        # because Re[i] is observed, not unknown, in the new core).
        Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        f_i = friction_correlation(Re_i_for_friction)
        push!(eqs,
            dp[i] ~ f_i * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) * (dz / Dh)
                  + rho_water(T[i]) * g_acc * dz
        )

        # q-agnostic observables (D-08).
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(obs, Re[i] ~ Re_i_for_friction)         # reuse the inlined Re_i (NOT Re[i] symbol)
        push!(obs, Pe[i] ~ Re_i_for_friction * Pr_i)  # Re*Pr (Peclet)
        push!(obs, v[i]  ~ port_in.mdot / (rho_water(T[i]) * A))  # canonical form (CAC line 202)

        # Per-cell absolute pressure (distributed inertia correction; CAC pattern).
        # P_i is a Julia local expression (NOT the P[i] symbol) to avoid an
        # observed-to-observed chain when used inside T_sat[i] / T_ONB[i] (Pitfall 7).
        P_i = port_in.P - sum(dp[j] for j in 1:i) -
              (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
        push!(obs, P[i]    ~ P_i)
        push!(obs, T_sat[i] ~ sat_temperature(P_i))

        # q-derived observables (D-08).
        # T_ONB[i] inlines q-density from q_left_expr/q_right_expr (Julia locals)
        # rather than referencing the q_wall[i] observable symbol — avoids
        # observed-to-observed chain (Pitfall 7).
        q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
        push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i))

        push!(obs, q_wall_left[i]  ~ q_left_expr[i])
        push!(obs, q_wall_right[i] ~ q_right_expr[i])
        push!(obs, q_wall[i]       ~ q_left_expr[i] + q_right_expr[i])
    end

    # Scalar equations — port wiring (identical across all variants; PATTERNS.md lines 104-115)
    push!(eqs, T_out ~ T[n])
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n))
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ T[1])
    push!(obs, dP ~ port_in.P - port_out.P)

    return (; eqs, obs)
end


"""
    Channel(; name, n, geometry, g=0.0, h_left=0.0, h_right=0.0,
            friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells. External-input
recipient: per-cell wall temperature arrives via channel-level `@variables`
`T_wall_left(t)[1:n]` / `T_wall_right(t)[1:n]` (no port — these are plain
unknowns the user closes via binding eqns or a `WallTemperature` source).
`h_left` / `h_right` are constructor kwargs (each `Real | AbstractVector |
Function`, default `0.0`). Adiabatic when `h_*=0.0` (default).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `h_left`, `h_right`: per-side convective HTC [W/(m^2·K)]; `Real` (broadcast to all n cells),
  `AbstractVector{<:Real}` of length n (per-cell static profile), or `Function` (time-varying via
  MTK callable parameter pattern; user must pass `ch.h_left_fn => fn` in solve `op` dict);
  default `0.0` per-side ⇒ adiabatic.
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# External-input variables (Phase 55 D-01)
- `T_wall_left(t)[1:n]`: per-cell left-face wall temperature [K]
- `T_wall_right(t)[1:n]`: per-cell right-face wall temperature [K]

These have no internal equation. Close them via either of:
```julia
# Style 1 — direct binding eqns at compose time (args.funcs idiom; D-05):
connections = [
    ...,
    [ch.T_wall_left[i] ~ T_wall_value for i in 1:n]...,
]

# Style 2 — value-source component:
@named wt = WallTemperature(; n=n, T_wall=T_wall_value)
connections = [
    ...,
    [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...,
]
```

# Ports
- `port_in`, `port_out` -- `FlowPort` (mass + momentum + stream T)
  *No thermal ports — see external-input variables above.*

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Channel(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    friction_correlation=blasius_friction,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    # ----------------------------------------------------------------
    # Base parameters: geometry + gravity. h_left/h_right resolution is
    # unchanged from Phase 54 D-02 — only the q-expression *consumer*
    # changed (T_wall_left[i] @variable in place of thermal_left[i].T port var).
    # ----------------------------------------------------------------
    pars_base = @parameters begin
        L = L
        D_h = Dh
        A = A
        g_acc = g
    end

    extra_pars = Any[]
    if h_left isa Real
        hL_per_cell = fill(Num(h_left), n)
    elseif h_left isa AbstractVector
        length(h_left) == n ||
            error("Channel: h_left vector length $(length(h_left)) ≠ n=$n")
        hL_per_cell = Num.(h_left)
    else  # Function / callable — MTK callable-parameter pattern (RESEARCH.md §1)
        FType_L = typeof(h_left)
        pL = @parameters (h_left_fn::FType_L)(..)
        hL_call = pL[1](t)
        hL_per_cell = fill(hL_call, n)
        append!(extra_pars, pL)
    end

    if h_right isa Real
        hR_per_cell = fill(Num(h_right), n)
    elseif h_right isa AbstractVector
        length(h_right) == n ||
            error("Channel: h_right vector length $(length(h_right)) ≠ n=$n")
        hR_per_cell = Num.(h_right)
    else  # Function / callable
        FType_R = typeof(h_right)
        pR = @parameters (h_right_fn::FType_R)(..)
        hR_call = pR[1](t)
        hR_per_cell = fill(hR_call, n)
        append!(extra_pars, pR)
    end

    pars = Any[pars_base...; extra_pars...]

    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (dp(t))[1:n] = fill(100.0, n)
        (T_wall_left(t))[1:n]
        (T_wall_right(t))[1:n]
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz = L / n

    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = hL_per_cell[i] * geometry.heated_parts[1] * dz * (T_wall_left[i]  - T[i])
        q_right_expr[i] = hR_per_cell[i] * geometry.heated_parts[2] * dz * (T_wall_right[i] - T[i])
    end

    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q_flow closure
    obs = core.obs

    all_vars = [
        collect(T); collect(dp);
        collect(T_wall_left); collect(T_wall_right);
        collect(Re); collect(Pe); collect(v);
        collect(P); collect(T_sat); collect(T_ONB);
        collect(q_wall); collect(q_wall_left); collect(q_wall_right);
        T_out; dP
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0,
                    friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells. External-input
recipient of prescribed heat flux: per-cell flux density [W/m^2] arrives via
channel-level `@variables` `q_left(t)[1:n]` / `q_right(t)[1:n]` (no port — these
are plain unknowns the user closes via binding eqns or a `HeatFluxSource` source).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# External-input variables (Phase 55 D-03)
- `q_left(t)[1:n]`: per-cell left-face heat flux density [W/m^2]
- `q_right(t)[1:n]`: per-cell right-face heat flux density [W/m^2]

These have no internal equation. Close them via either of:
```julia
# Style 1 — direct binding eqns at compose time:
connections = [
    ...,
    [chf.q_left[i] ~ q_value for i in 1:n]...,
]

# Style 2 — value-source component:
@named hfs = HeatFluxSource(; n=n, q=q_value)
connections = [
    ...,
    [chf.q_left[i] ~ hfs.q_out[i] for i in 1:n]...,
]
```

# Ports
- `port_in`, `port_out` -- `FlowPort` (mass + momentum + stream T)
  *No heat-flux ports — see external-input variables above.*

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ChannelHeatFlux(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    friction_correlation=blasius_friction,
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

    # NEW IN PHASE 55 (D-03): q_left[1:n] and q_right[1:n] are plain external-input
    # variables — no equation, no default, user closes them.
    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (dp(t))[1:n] = fill(100.0, n)
        (q_left(t))[1:n]
        (q_right(t))[1:n]
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz = L / n

    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = q_left[i]  * geometry.heated_parts[1] * dz
        q_right_expr[i] = q_right[i] * geometry.heated_parts[2] * dz
    end

    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q_flow closure
    obs = core.obs

    all_vars = [
        collect(T); collect(dp);
        collect(q_left); collect(q_right);
        collect(Re); collect(Pe); collect(v);
        collect(P); collect(T_sat); collect(T_ONB);
        collect(q_wall); collect(q_wall_left); collect(q_wall_right);
        T_out; dP
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end


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
        (h_tc_left(t))[1:n] = fill(5000.0, n)   # Phase 56-resume per-side h: break MTK cyclic-guess (mirrors h_tc default)
        (h_tc_right(t))[1:n] = fill(5000.0, n)  # Phase 56-resume per-side h: same
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

    variant_eqs = Equation[]
    if scb_correction === nothing
        for i in 1:n
            T_left_w   = thermal_left[i].T
            T_film_l   = (T[i] + T_left_w) / 2
            Re_l       = abs(port_in.mdot) * Dh / (A * mu_water(T_film_l))
            Pr_l       = cp_water(T_film_l) * mu_water(T_film_l) / k_water(T_film_l)
            push!(variant_eqs, h_tc_left[i]  ~ htc_correlation(Re_l, Pr_l, T[i], T_left_w) * k_water(T_film_l) / Dh)

            T_right_w  = thermal_right[i].T
            T_film_r   = (T[i] + T_right_w) / 2
            Re_r       = abs(port_in.mdot) * Dh / (A * mu_water(T_film_r))
            Pr_r       = cp_water(T_film_r) * mu_water(T_film_r) / k_water(T_film_r)
            push!(variant_eqs, h_tc_right[i] ~ htc_correlation(Re_r, Pr_r, T[i], T_right_w) * k_water(T_film_r) / Dh)

        end
    else
        for i in 1:n
            # Phase 56-resume: SCB branch keeps single-h_tc semantics. SCB tests
            # pin both walls to the same T (symmetric); asymmetric SCB is out of
            # v1.1 scope. h_tc_left[i] / h_tc_right[i] alias h_tc[i] here so the
            # variable structure stays uniform across the SCB / non-SCB paths.
            T_w_i    = thermal_left[i].T
            T_film_i = (T[i] + T_w_i) / 2
            Re_i     = abs(port_in.mdot) * Dh / (A * mu_water(T_film_i))
            Pr_i     = cp_water(T_film_i) * mu_water(T_film_i) / k_water(T_film_i)
            h_spl_i  = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T_film_i) / Dh

            # Inline P[i] (NOT the P[i] symbol) — Pitfall 7 (avoid observed-to-observed chain)
            P_i = port_in.P - sum(dp[j] for j in 1:i) -
                  (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
            T_sat_i = sat_temperature(P_i)
            # max(q_spl, 0) guards _bergles_rohsenow_dT_ONB against DomainError
            # (SCB-01 / v0.7 retrospective).
            q_spl_i = max(h_spl_i * (T_w_i - T[i]), 0.0)

            # D-03 invariant: scb_correction's Re argument stays at bulk T
            # (separate from the film-T Re_i feeding htc_correlation above).
            # Pre-Phase-57 this was bulk; the SCB closure uses Re only as a
            # regime/laminar gate, which is a bulk-flow phenomenon.
            Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            q_scb_i     = scb_correction(T_w_i, T_sat_i, Re_i_bulk)
            T_ONB_i     = T_sat_i + _bergles_rohsenow_dT_ONB(P_i, q_spl_i)
            q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i_bulk)
            factor_i    = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

            push!(variant_eqs, h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i))
            push!(variant_eqs, h_tc_left[i]  ~ h_tc[i])
            push!(variant_eqs, h_tc_right[i] ~ h_tc[i])
        end
    end

    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = h_tc_left[i]  * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
        q_right_expr[i] = h_tc_right[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
        push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
        push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
    end

    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    variant_obs = Equation[]
    for i in 1:n
        T_w_obs_i    = thermal_left[i].T
        T_film_obs_i = (T[i] + T_w_obs_i) / 2
        Re_i_film    = abs(port_in.mdot) * Dh / (A * mu_water(T_film_obs_i))
        Pr_i_film    = cp_water(T_film_obs_i) * mu_water(T_film_obs_i) / k_water(T_film_obs_i)
        push!(variant_obs, Nu[i] ~ htc_correlation(Re_i_film, Pr_i_film, T[i], T_w_obs_i))
        push!(variant_obs, T_wall_left[i]  ~ thermal_left[i].T)
        push!(variant_obs, T_wall_right[i] ~ thermal_right[i].T)
        push!(variant_obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))
        Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        nu_i = mu_water(T[i]) / rho_water(T[i])
        Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
        push!(variant_obs, Gr_over_Re2[i] ~ Gr_i / Re_i_bulk^2)
    end
    push!(variant_obs, Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n))

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

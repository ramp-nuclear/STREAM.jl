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
momentum ODE `(L/A)*D(mdot)`, per-cell friction (algebraic dp[i]), port wiring,
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
    D(T[i]) ~ (|mdot|*cp_face*(T_up - T[i]) + q_left_expr[i] + q_right_expr[i])
              / (rho_water(T[i]) * cp_water(T[i]) * A * dz)

"""
function _channel_core(;
    n::Int,
    port_in,
    port_out,
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr, q_right_expr,
    vars,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n

    eqs = Equation[]
    obs = Equation[]

    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    for i in 1:n
        T_up_fwd = (i == 1) ? T_inlet_fwd : vars.T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : vars.T[i + 1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)

        cp_face = (cp_water(T_up) + cp_water(vars.T[i])) / 2

        # Energy balance — enthalpy form
        push!(eqs,
            D(vars.T[i]) ~ (
                abs(port_in.mdot) * cp_face * (T_up - vars.T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (rho_water(vars.T[i]) * cp_water(vars.T[i]) * A * dz)
        )

        # Using Reynolds directly and not the variable because it may only be observable
        Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(vars.T[i]))
        f_i = friction_correlation(Re_i_for_friction)
        push!(eqs,
            vars.dp[i] ~ f_i * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(vars.T[i]) * A^2)) * (dz / Dh)
                  + rho_water(vars.T[i]) * g_acc * dz
        )

        Pr_i = cp_water(vars.T[i]) * mu_water(vars.T[i]) / k_water(vars.T[i])
        push!(obs, vars.Re[i] ~ Re_i_for_friction)
        push!(obs, vars.Pe[i] ~ Re_i_for_friction * Pr_i)
        push!(obs, vars.v[i]  ~ port_in.mdot / (rho_water(vars.T[i]) * A))

        P_i = port_in.P - sum(vars.dp[j] for j in 1:i) + vars.dp[i] / 2
        push!(obs, vars.P[i]     ~ P_i)
        push!(obs, vars.T_sat[i] ~ sat_temperature(P_i))

        q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
        push!(obs, vars.T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i))

        push!(obs, vars.q_wall_left[i]  ~ q_left_expr[i])
        push!(obs, vars.q_wall_right[i] ~ q_right_expr[i])
        push!(obs, vars.q_wall[i]       ~ q_left_expr[i] + q_right_expr[i])
    end

    push!(obs, vars.T_out ~ ifelse(port_in.mdot >=0, vars.T[n], vars.T[1]))
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, (L / A) * D(port_in.mdot) ~ (port_in.P - port_out.P) - sum(vars.dp[i] for i in 1:n))
    push!(eqs, port_out.T ~ vars.T[n])
    push!(eqs, port_in.T  ~ vars.T[1])
    push!(obs, vars.dP ~ port_in.P - port_out.P)

    return (; eqs, obs)
end


function _setup(geometry, g, n)
    pars = @parameters begin
        L = geometry.L
        D_h = geometry.Dh
        A = geometry.A
        g_acc = g
    end

    @variables begin
        (T(t))[1:n]
        (dp(t))[1:n]
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
        T_out(t)
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    varstruct = (;
        T, dp, T_wall_left, T_wall_right, Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right, T_out, dP,
    )

    return pars, varstruct, port_in, port_out
end

function _vcollect(vars)
    [
        collect(vars.T); collect(vars.dp);
        collect(vars.T_wall_left); collect(vars.T_wall_right);
        collect(vars.Re); collect(vars.Pe); collect(vars.v);
        collect(vars.P); collect(vars.T_sat); collect(vars.T_ONB);
        collect(vars.q_wall); collect(vars.q_wall_left); collect(vars.q_wall_right);
        vars.T_out; vars.dP
    ]
end


"""
    Channel(; name, n, geometry, g=0.0, h_left=0.0, h_right=0.0,
            friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells. 
`Heat flux is defined by external temperature (required closure post process) and 
`prescribed heat transfer coefficient.
A `WallTemperature` source can be used as a closure, for example.

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
    pars_base, varstruct, port_in, port_out = _setup(geometry, g, n)

    extra_pars = Any[]
    if h_left isa Real
        hL_per_cell = fill(Num(h_left), n)
    elseif h_left isa AbstractVector
        length(h_left) == n ||
            throw(DimensionMismatch("h_left has length $(length(h_left)), expected n=$n"))
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
            throw(DimensionMismatch("h_right has length $(length(h_right)), expected n=$n"))
        hR_per_cell = Num.(h_right)
    else  # Function / callable
        FType_R = typeof(h_right)
        pR = @parameters (h_right_fn::FType_R)(..)
        hR_call = pR[1](t)
        hR_per_cell = fill(hR_call, n)
        append!(extra_pars, pR)
    end

    pars = Any[pars_base...; extra_pars...]

    dz = geometry.L / n

    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = hL_per_cell[i] * geometry.heated_parts[1] * dz * (varstruct.T_wall_left[i]  - varstruct.T[i])
        q_right_expr[i] = hR_per_cell[i] * geometry.heated_parts[2] * dz * (varstruct.T_wall_right[i] - varstruct.T[i])
    end

    core = _channel_core(;
        n=n, 
        port_in=port_in, 
        port_out=port_out, 
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=varstruct,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q_flow closure
    obs = core.obs

    all_vars = _vcollect(varstruct)

    return compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0,
                    friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells.
Heat flux is either a user prescribed closure or bindings with a `HeatFluxSource` source).

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
    pars, varstruct, port_in, port_out = _setup(geometry, g, n)
    dz = geometry.L / n

    exvars = @variables begin
        (q_left(t))[1:n]
        (q_right(t))[1:n]
    end

    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = q_left[i]  * geometry.heated_parts[1] * dz
        q_right_expr[i] = q_right[i] * geometry.heated_parts[2] * dz
    end

    core = _channel_core(;
        n=n, 
        port_in=port_in, 
        port_out=port_out, 
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=varstruct,
    )

    eqs = core.eqs
    obs = core.obs
    all_vars = [_vcollect(varstruct); [collect(v) for v in exvars]...]

    return compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end


function _nu_film(T_film::Real, mdot::Real, Dh::Real, A::Real, nu_f::Function)
    Re = abs(mdot) * Dh / (A * mu_water(T_film))
    Pr = cp_water(T_film) * mu_water(T_film) / k_water(T_film)
    return nu_f(Re, Pr)
end

function _nu_film(T_w::Real, T::Real, mdot::Real, Dh::Real, A::Real, nu_f::Function)
    T_film   = (T_w + T) / 2
    nupartial(Re, Pr) = nu_f(Re, Pr, T_w, T)
    return _nu_film(T_film, mdot, Dh, A, nupartial)
end

function _h_spl(T_w::Real, T::Real, mdot::Real, Dh::Real, A::Real, nu_f::Function)
    T_film   = (T_w + T) / 2
    # Route through the (T_w, T)-aware `_nu_film` so strict 4-arg correlations
    # (e.g. `regime_dependent` with NC switching) receive `(Re, Pr, T_w, T)`.
    # Simple `(Re, Pr, args...)` correlations absorb the extra temps unchanged.
    return _nu_film(T_w, T, mdot, Dh, A, nu_f) * k_water(T_film) / Dh
end


function _h_eq_nocor(Tw::Real, T::Real, mdot::Real, Dh::Real, A::Real, htc, nu_f::Function)
    return htc ~ _h_spl(Tw, T, mdot, Dh, A, nu_f)
end


function _h_eq_scb_cor(T_w::Real, T::Real, cumdp::Real, dp::Real, htc, mdot::Real, 
                       P_in::Real, Dh::Real, A::Real, nu_f::Function, scb_f::Function)
    h_spl = _h_spl(T_w, T, mdot, Dh, A, nu_f)
    q_spl = max(h_spl * (T_w - T), 0.0)
    P = P_in - cumdp + dp/2
    T_sat = sat_temperature(P)
    Re = abs(mdot) * Dh / (A * mu_water(T))
    q_scb  = scb_f(T_w, T_sat, Re)
    T_ONB  = T_sat + _bergles_rohsenow_dT_ONB(P, q_spl)
    q_scb_inc  = scb_f(T_ONB, T_sat, Re)
    factor     = partial_SCB_correction(q_spl, q_scb, q_scb_inc)

    return htc ~ ifelse(T_w >= T_ONB, h_spl * factor, h_spl)
end


"""
    ChannelAndContacts(; name, n, geometry, g=0.0,
                       htc_correlation=dittus_boelter,
                       friction_correlation=blasius_friction,
                       scb_correction=nothing) -> ODESystem

Convective channel with per-cell `ThermalPort` arrays on both sides for conjugate heat
transfer (the variant that connects to `HeatDiffusion`). Internal HTC correlation
(single-phase or correlation+SCB-enhanced) drives per-cell `h_tc[i]`; 
Heat flux is computed as `h_tc[i] * heated_parts * dz * (T_wall - T[i])` 
The wall temperature is connected through thermal port arrays.

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
    
    pars, vars, port_in, port_out = _setup(geometry, g, n)
    thermal_left  = [ThermalPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
    thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]

    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n
    exvars = @variables begin
        # Default 5000.0 seeds the nonlinear initialization solve. h_tc[i] ~ Nu*k/Dh
        # with Nu evaluated at T_film makes h_tc a tearing variable whose init
        # guess-map is self-referential without a numeric seed (MTK "Cyclic guesses").
        # Restored from the v1.1 baseline, where it was dropped in the refactor.
        (h_tc_left(t))[1:n] = fill(5000.0, n)
        (h_tc_right(t))[1:n] = fill(5000.0, n)
        (Nu_left(t))[1:n]
        (Nu_right(t))[1:n]
        (velocity(t))[1:n]
        (Gr_over_Re2_left(t))[1:n]
        (Gr_over_Re2_right(t))[1:n]
        Q_wall_total(t)
    end

    if scb_correction === nothing
        variant_eqs = [
            [_h_eq_nocor(thermal_left[i].T,  vars.T[i], port_in.mdot, Dh, A, h_tc_left[i], htc_correlation) 
             for i in 1:n]...;
            [_h_eq_nocor(thermal_right[i].T, vars.T[i], port_in.mdot, Dh, A, h_tc_right[i], htc_correlation) 
             for i in 1:n]...
        ]
    else
        variant_eqs = [
            [_h_eq_scb_cor(thermal_left[i].T,  vars.T[i], sum(vars.dp[j] for j in 1:i), 
                           vars.dp[i], h_tc_left[i],  port_in.mdot, port_in.P, Dh, A, htc_correlation, scb_correction) 
                           for i in 1:n]...;
            [_h_eq_scb_cor(thermal_right[i].T, vars.T[i], sum(vars.dp[j] for j in 1:i), 
                           vars.dp[i], h_tc_right[i], port_in.mdot, port_in.P, Dh, A, htc_correlation, scb_correction) 
                           for i in 1:n]...;
        ]
    end

    q_left_expr =  [h_tc_left[i]  * geometry.heated_parts[1] * dz * (thermal_left[i].T   - vars.T[i]) for i in 1:n]
    q_right_expr = [h_tc_right[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T  - vars.T[i]) for i in 1:n]
    variant_eqs = [variant_eqs...; 
                   [thermal_left[i].Q_flow  ~ q_left_expr[i]  for i in 1:n]...;
                   [thermal_right[i].Q_flow ~ q_right_expr[i] for i in 1:n]...;
                   ]

    core = _channel_core(;
        n=n, 
        port_in=port_in, 
        port_out=port_out, 
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=vars,
    )

    Re_bulk = [abs(port_in.mdot) * Dh / (A * mu_water(vars.T[i])) for i in 1:n]
    Gr_left  = [Gr(rho_water(vars.T[i]), mu_water(vars.T[i]), beta_water(vars.T[i]), thermal_left[i].T ,  vars.T[i], Dh, g) for i in 1:n]
    Gr_right = [Gr(rho_water(vars.T[i]), mu_water(vars.T[i]), beta_water(vars.T[i]), thermal_right[i].T , vars.T[i], Dh, g) for i in 1:n]
    variant_obs = [
        [Nu_left[i]  ~ _nu_film(thermal_left[i].T,  vars.T[i], port_in.mdot, Dh, A, htc_correlation) 
         for i in 1:n]...;
        [Nu_right[i] ~ _nu_film(thermal_right[i].T, vars.T[i], port_in.mdot, Dh, A, htc_correlation) 
         for i in 1:n]...;
        [vars.T_wall_left[i] ~ thermal_left[i].T for i in 1:n]...;
        [vars.T_wall_right[i] ~ thermal_right[i].T for i in 1:n]...;
        [velocity[i] ~ abs(vars.v[i]) for i in 1:n]...;
        [Gr_over_Re2_left[i]  ~ Gr_left[i]  / Re_bulk[i]^2 for i in 1:n]...;
        [Gr_over_Re2_right[i] ~ Gr_right[i] / Re_bulk[i]^2 for i in 1:n]...;
        Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n);
    ]

    eqs = [core.eqs...; variant_eqs...]
    obs = [core.obs...; variant_obs...]

    all_vars = [
        _vcollect(vars)...;
        [collect(v) for v in exvars]...
    ]

    return compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out, thermal_left..., thermal_right...,
    )
end

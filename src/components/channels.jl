# channels.jl -- Channel, ChannelHeatFlux, ChannelAndContacts variants
# and shared `_channel_core`.
#

# Declare Channel as a new generic function independent of Base.Channel{T}
# (Base.Channel is Julia stdlib's task-communication channel; STREAM.Channel is unrelated)
function Channel end

"""
    _channel_core(; n, T, dp, inlet, outlet, geometry, g_acc,
                  friction_correlation=blasius_friction,
                  q_left_expr, q_right_expr,
                  Re, Pe, v, P, T_sat, T_ONB,
                  q_wall, q_wall_left, q_wall_right,
                  T_out, dP)::NamedTuple

Shared private helper for STREAM channel-family components. Single source of truth
for energy balance (enthalpy form with face-averaged cp), mass conservation,
momentum ODE `(L/A)*D(ṁ)`, per-cell friction (algebraic dp[i]), port wiring,
and observables.

Returns `(; eqs, obs)` — variant splices `eqs = [variant_specific_eqs; core.eqs]`,
`obs = [core.obs; variant_specific_obs]`. Variant declares all `@variables`
(unknowns AND observables that core references); core builds equations referencing
those symbols.

# Arguments
- `n::Int`                                          : number of axial cells
- `T`, `dp`                                         : variant-declared `@variables (T(t))[1:n]`, `(dp(t))[1:n]`
- `inlet`, `outlet`                             : variant-created `FlowPort`s
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
    D(T[i]) ~ (|ṁ|*cp_face*(T_up - T[i]) + q_left_expr[i] + q_right_expr[i])
              / (rho_water(T[i]) * cp_water(T[i]) * A * dz)

"""
function _channel_core(;
    n::Int,
    inlet,
    outlet,
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr, q_right_expr,
    vars,
    fluid::AbstractFluid=Water(),
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n

    T_inlet_fwd = instream(inlet.T)
    T_inlet_rev = instream(outlet.T)

    cells = map(1:n) do i
        T_up_fwd = (i == 1) ? T_inlet_fwd : vars.T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : vars.T[i + 1]
        T_up = ifelse(inlet.ṁ >= 0, T_up_fwd, T_up_rev)

        cp_face = (specific_heat(fluid, T_up) + specific_heat(fluid, vars.T[i])) / 2

        # Use Reynolds directly, not the observable variable, since it may only be observable.
        Re_i = Re(inlet.ṁ, A, Dh, viscosity(fluid, vars.T[i]))
        f_i = friction_correlation(Re_i)
        Pr_i = Pr(specific_heat(fluid, vars.T[i]), viscosity(fluid, vars.T[i]), conductivity(fluid, vars.T[i]))
        P_i = inlet.p - sum(vars.dp[j] for j in 1:i) + vars.dp[i] / 2
        q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)

        cell_eqs = Equation[
            # Energy balance — enthalpy form
            D(vars.T[i]) ~ (
            abs(inlet.ṁ) * cp_face * (T_up - vars.T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (density(fluid, vars.T[i]) * specific_heat(fluid, vars.T[i]) * A * dz),
            vars.dp[i] ~ f_i * (inlet.ṁ * abs(inlet.ṁ) / (2 * density(fluid, vars.T[i]) * A^2)) * (dz / Dh)
                  + density(fluid, vars.T[i]) * g_acc * dz,
        ]
        cell_obs = Equation[
            vars.Re[i] ~ Re_i,
            vars.Pe[i] ~ Re_i * Pr_i,
            vars.v[i] ~ inlet.ṁ / (density(fluid, vars.T[i]) * A),
            vars.P[i]     ~ P_i,
            vars.T_sat[i] ~ sat_temperature(P_i),
            vars.T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i),
            vars.q_wall_left[i]  ~ q_left_expr[i],
            vars.q_wall_right[i] ~ q_right_expr[i],
            vars.q_wall[i]       ~ q_left_expr[i] + q_right_expr[i],
        ]
        (eqs=cell_eqs, obs=cell_obs)
    end

    eqs = vcat(
        reduce(vcat, (c.eqs for c in cells)),
        Equation[
            inlet.ṁ + outlet.ṁ ~ 0,
            (L / A) * D(inlet.ṁ) ~ (inlet.p - outlet.p) - sum(vars.dp[i] for i in 1:n),
            outlet.T ~ vars.T[n],
            inlet.T ~ vars.T[1],
        ],
    )
    obs = vcat(
        reduce(vcat, (c.obs for c in cells)),
        Equation[
            vars.T_out ~ ifelse(inlet.ṁ >= 0, vars.T[n], vars.T[1]),
            vars.dP ~ inlet.p - outlet.p,
        ],
    )

    return (; eqs, obs)
end


function _setup(geometry, g, n)
    # No geometry parameters are declared: L, Dh, and A enter the equations inline from
    # `geometry` (see `_channel_core` and the variants). When a dimension is a design knob,
    # that inline value is the knob expression, so `remake` scans it. g_acc is declared as
    # a parameter only so `check_gravity_mismatch` can find which channels carry gravity;
    # the equations use the inline `g` value, not this symbol.
    pars = @parameters g_acc = g

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

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    varstruct = (;
        T, dp, T_wall_left, T_wall_right, Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right, T_out, dP,
    )

    return pars, varstruct, inlet, outlet
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
            friction_correlation=blasius_friction) -> System

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
- `fluid`: coolant property set (`AbstractFluid`), default `Water()`. Pass a `ConstantFluid`
  to drive the energy balance, friction, and dimensionless observables with fixed properties.

# External-input variables
- `T_wall_left(t)[1:n]`: per-cell left-face wall temperature [K]
- `T_wall_right(t)[1:n]`: per-cell right-face wall temperature [K]

These have no internal equation. Close them via either of:
```julia
# Style 1 — direct binding eqns at compose time (args.funcs idiom):
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
- `inlet`, `outlet` -- `FlowPort` (mass + momentum + stream T)
  *No thermal ports — see external-input variables above.*
"""
function Channel(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    friction_correlation=blasius_friction,
    fluid::AbstractFluid=Water(),
)
    pars_base, varstruct, inlet, outlet = _setup(geometry, g, n)

    extra_pars = Any[]
    if h_left isa Real
        hL_per_cell = fill(Num(h_left), n)
    elseif h_left isa AbstractVector
        length(h_left) == n ||
            throw(DimensionMismatch("h_left has length $(length(h_left)), expected n=$n"))
        hL_per_cell = Num.(h_left)
    else  # Function / callable — MTK callable-parameter pattern
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
        inlet=inlet,
        outlet=outlet,
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=varstruct,
        fluid=fluid,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q closure
    obs = core.obs

    all_vars = _vcollect(varstruct)

    return compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        inlet,
        outlet,
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0,
                    friction_correlation=blasius_friction) -> System

Single-phase convective channel with `n` axial finite-volume cells.
Heat flux is either a user prescribed closure or bindings with a `HeatFluxSource` source).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`
- `fluid`: coolant property set (`AbstractFluid`), default `Water()`.

# External-input variables
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
- `inlet`, `outlet` -- `FlowPort` (mass + momentum + stream T)
  *No heat-flux ports — see external-input variables above.*
"""
function ChannelHeatFlux(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    friction_correlation=blasius_friction,
    fluid::AbstractFluid=Water(),
)
    pars, varstruct, inlet, outlet = _setup(geometry, g, n)
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
        inlet=inlet,
        outlet=outlet,
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=varstruct,
        fluid=fluid,
    )

    eqs = core.eqs
    obs = core.obs
    all_vars = [_vcollect(varstruct); [collect(v) for v in exvars]...]

    return compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        inlet,
        outlet,
    )
end


function _nu_film(T_film::Real, ṁ::Real, Dh::Real, A::Real, nu_f::Function)
    Re = STREAM.Re(ṁ, A, Dh, mu_water(T_film))
    Pr = STREAM.Pr(cp_water(T_film), mu_water(T_film), k_water(T_film))
    return nu_f(Re, Pr)
end

function _nu_film(T_w::Real, T::Real, ṁ::Real, Dh::Real, A::Real, nu_f::Function)
    T_film   = (T_w + T) / 2
    nupartial(Re, Pr) = nu_f(Re, Pr, T_w, T)
    return _nu_film(T_film, ṁ, Dh, A, nupartial)
end

function _h_spl(T_w::Real, T::Real, ṁ::Real, Dh::Real, A::Real, nu_f::Function)
    T_film   = (T_w + T) / 2
    # Route through the (T_w, T)-aware `_nu_film` so strict 4-arg correlations
    # (e.g. `regime_dependent` with NC switching) receive `(Re, Pr, T_w, T)`.
    # Simple `(Re, Pr, args...)` correlations absorb the extra temps unchanged.
    return _nu_film(T_w, T, ṁ, Dh, A, nu_f) * k_water(T_film) / Dh
end


function _h_eq_nocor(Tw::Real, T::Real, ṁ::Real, Dh::Real, A::Real, htc, nu_f::Function)
    return htc ~ _h_spl(Tw, T, ṁ, Dh, A, nu_f)
end


function _h_eq_scb_cor(
    T_w::Real,
    T::Real,
    cumdp::Real,
    dp::Real,
    htc,
    ṁ::Real,
                       P_in::Real, Dh::Real, A::Real, nu_f::Function, scb_f::Function)
    h_spl = _h_spl(T_w, T, ṁ, Dh, A, nu_f)
    q_spl = max(h_spl * (T_w - T), 0.0)
    P = P_in - cumdp + dp/2
    T_sat = sat_temperature(P)
    Re = STREAM.Re(ṁ, A, Dh, mu_water(T))
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
                       scb_correction=nothing) -> System

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
- `fluid`: coolant property set (`AbstractFluid`), default `Water()`. It drives the energy
  balance, friction, and dimensionless observables; the HTC correlation and Grashof term
  stay water-based.

# Ports
- `inlet`, `outlet` -- `FlowPort`
- `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell, per side)
"""
function ChannelAndContacts(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    htc_correlation=dittus_boelter,
    friction_correlation=blasius_friction,
    scb_correction=nothing,
    fluid::AbstractFluid=Water(),
)

    pars, vars, inlet, outlet = _setup(geometry, g, n)
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
            [
                _h_eq_nocor(
                    thermal_left[i].T,
                    vars.T[i],
                    inlet.ṁ,
                    Dh,
                    A,
                    h_tc_left[i],
                    htc_correlation,
                )
             for i in 1:n]...;
            [
                _h_eq_nocor(
                    thermal_right[i].T,
                    vars.T[i],
                    inlet.ṁ,
                    Dh,
                    A,
                    h_tc_right[i],
                    htc_correlation,
                )
             for i in 1:n]...
        ]
    else
        variant_eqs = [
            [_h_eq_scb_cor(thermal_left[i].T,  vars.T[i], sum(vars.dp[j] for j in 1:i),
                    vars.dp[i],
                    h_tc_left[i],
                    inlet.ṁ,
                    inlet.p,
                    Dh,
                    A,
                    htc_correlation,
                    scb_correction,
                )
                           for i in 1:n]...;
            [_h_eq_scb_cor(thermal_right[i].T, vars.T[i], sum(vars.dp[j] for j in 1:i),
                    vars.dp[i],
                    h_tc_right[i],
                    inlet.ṁ,
                    inlet.p,
                    Dh,
                    A,
                    htc_correlation,
                    scb_correction,
                )
                           for i in 1:n]...;
        ]
    end

    q_left_expr =  [h_tc_left[i]  * geometry.heated_parts[1] * dz * (thermal_left[i].T   - vars.T[i]) for i in 1:n]
    q_right_expr = [h_tc_right[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T  - vars.T[i]) for i in 1:n]
    variant_eqs = [variant_eqs...;
        [thermal_left[i].Q ~ q_left_expr[i] for i in 1:n]...
        [thermal_right[i].Q ~ q_right_expr[i] for i in 1:n]...
                   ]

    core = _channel_core(;
        n=n,
        inlet=inlet,
        outlet=outlet,
        geometry=geometry,
        g_acc=g, friction_correlation=friction_correlation,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        vars=vars,
        fluid=fluid,
    )

    Re_bulk = [Re(inlet.ṁ, A, Dh, mu_water(vars.T[i])) for i in 1:n]
    Gr_left  = [Gr(rho_water(vars.T[i]), mu_water(vars.T[i]), beta_water(vars.T[i]), thermal_left[i].T ,  vars.T[i], Dh, g) for i in 1:n]
    Gr_right = [Gr(rho_water(vars.T[i]), mu_water(vars.T[i]), beta_water(vars.T[i]), thermal_right[i].T , vars.T[i], Dh, g) for i in 1:n]
    variant_obs = [
        [
            Nu_left[i] ~ _nu_film(
                thermal_left[i].T, vars.T[i], inlet.ṁ, Dh, A, htc_correlation
            )
         for i in 1:n]...;
        [
            Nu_right[i] ~ _nu_film(
                thermal_right[i].T, vars.T[i], inlet.ṁ, Dh, A, htc_correlation
            )
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
        inlet,
        outlet,
        thermal_left...,
        thermal_right...,
    )
end

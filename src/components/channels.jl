# channels.jl -- Channel, ChannelHeatFlux, ChannelAndContacts variants
# and shared `_channel_core`.
#

# Declare Channel as a new generic function independent of Base.Channel{T}
# (Base.Channel is Julia stdlib's task-communication channel; STREAM.Channel is unrelated)
function Channel end

"""
    _channel_core(; n, T, dp, inlet, outlet, geometry, g_acc,
                  darcy::DarcyFactor=BlasiusFriction(),
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
- `darcy`                                           : wall friction model ([`DarcyFactor`](@ref))
- `T_wall`                                          : length-n wall temperature, or `nothing` when the
                                                      variant has no wall of its own
- `q_left_expr`, `q_right_expr`                     : length-n `Vector{Num}`, per-cell heat flow inputs (W) — variant builds these
- `Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right` : variant-declared observable LHS symbols
- `T_out, dP`                                       : variant-declared scalar observable LHS symbols

# Returns
NamedTuple `(; eqs::Vector{Equation}, obs::Vector{Equation})` — the variant
splices these into its own equation lists before building the `System`.

# Energy balance per cell (enthalpy form, face-averaged cp)

    cp_face = (cₚ(liquid, T_up) + cₚ(liquid, T[i])) / 2
    D(T[i]) ~ (|ṁ|*cp_face*(T_up - T[i]) + q_left_expr[i] + q_right_expr[i])
              / (ρ(liquid, T[i]) * cₚ(liquid, T[i]) * A * dz)

"""
function _channel_core(;
    n::Int,
    inlet,
    outlet,
    geometry::PipeGeometry,
    g_acc::Real,
    darcy::DarcyFactor=BlasiusFriction(),
    q_left_expr, q_right_expr,
    vars,
    liquid::AbstractLiquid=H2O,
    T_wall=nothing,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n

    T  = collect(vars.T)
    dp = collect(vars.dp)
    # A variant with no wall of its own hands the friction model the bulk temperature, which
    # makes the wall-to-bulk viscosity ratio exactly 1 and the correction a no-op.
    T_wall_c = T_wall === nothing ? T : collect(T_wall)

    T_inlet_fwd = instream(inlet.T)
    T_inlet_rev = instream(outlet.T)

    # Density and specific heat are named because several equations below reuse them; the
    # rest of the properties are reached through the dimensionless numbers that want them.
    ρ_c  = ρ.(liquid, T)
    cp_c = cₚ.(liquid, T)

    Re_c = Re.(liquid, T, inlet.ṁ, A, Dh)
    Pr_c = Pr.(liquid, T)
    # Cell-centre pressure: inlet minus the drop accumulated up to this cell, plus back
    # half a cell to land at the centre rather than the outlet face.
    P_c = inlet.p .- cumsum(dp) .+ dp ./ 2
    q_density_c = (q_left_expr .+ q_right_expr) ./ (sum(geometry.heated_parts) * dz)

    cells = map(1:n) do i
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(inlet.ṁ >= 0, T_up_fwd, T_up_rev)

        cp_face = (cₚ(liquid, T_up) + cp_c[i]) / 2
        f_i = darcy(T[i], T_wall_c[i], inlet.ṁ, liquid, geometry)

        cell_eqs = Equation[
            # Energy balance, enthalpy form
            D(T[i]) ~ (
            abs(inlet.ṁ) * cp_face * (T_up - T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (ρ_c[i] * cp_c[i] * A * dz),
            # Darcy-Weisbach friction over the cell, plus its hydrostatic head
            dp[i] ~ darcy_weisbach_dp(inlet.ṁ, ρ_c[i], f_i, dz, Dh, A)
                  + ρ_c[i] * g_acc * dz,
        ]
        cell_obs = Equation[
            vars.Re[i] ~ Re_c[i],
            vars.Pe[i] ~ Re_c[i] * Pr_c[i],
            vars.v[i] ~ inlet.ṁ / (ρ_c[i] * A),
            vars.P[i]     ~ P_c[i],
            vars.T_sat[i] ~ Tsat(liquid, P_c[i]),
            vars.T_ONB[i] ~ Tsat(liquid, P_c[i]) + _bergles_rohsenow_dT_ONB(P_c[i], q_density_c[i]),
            vars.q_wall_left[i]  ~ q_left_expr[i],
            vars.q_wall_right[i] ~ q_right_expr[i],
            vars.q_wall[i]       ~ q_left_expr[i] + q_right_expr[i],
        ]
        (eqs=cell_eqs, obs=cell_obs)
    end

    eqs = vcat(
        reduce(vcat, (c.eqs for c in cells)),
        Equation[
            inlet.ṁ + outlet.ṁ ~ 0,
            (L / A) * D(inlet.ṁ) ~ (inlet.p - outlet.p) - sum(dp),
            outlet.T ~ T[n],
            inlet.T ~ T[1],
        ],
    )
    obs = vcat(
        reduce(vcat, (c.obs for c in cells)),
        Equation[
            vars.T_out ~ ifelse(inlet.ṁ >= 0, T[n], T[1]),
            vars.dP ~ inlet.p - outlet.p,
        ],
    )

    return (; eqs, obs)
end


# Python's channel hands its friction model the mean of the two wall
# temperatures; so do we.
_face_mean_wall(vars) =
    (collect(vars.T_wall_left) .+ collect(vars.T_wall_right)) ./ 2

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
    _channel_system(; name, n, geometry, g, darcy, liquid, vars, pars,
                    inlet, outlet, q_left_expr, q_right_expr,
                    extra_vars=(), extra_eqs=Equation[], extra_obs=Equation[],
                    extra_ports=()) -> System

Build the composed `System` for a channel variant. Every variant states its own heat-input
expressions and whatever extra variables, equations, observables, and ports it adds, then
hands them here; the shared core equations and the `compose` call live in one place.
"""
function _channel_system(;
    name, n::Int, geometry::PipeGeometry, g, darcy, liquid,
    vars, pars, inlet, outlet, q_left_expr, q_right_expr, T_wall=nothing,
    extra_vars=(), extra_eqs=Equation[], extra_obs=Equation[], extra_ports=(),
)
    core = _channel_core(;
        n=n,
        inlet=inlet,
        outlet=outlet,
        geometry=geometry,
        g_acc=g,
        darcy=darcy,
        q_left_expr=q_left_expr,
        q_right_expr=q_right_expr,
        vars=vars,
        liquid=liquid,
        T_wall=T_wall,
    )
    all_vars = [_vcollect(vars); reduce(vcat, (collect(v) for v in extra_vars); init=Num[])]
    return compose(
        System(
            [core.eqs; extra_eqs], t, all_vars, pars;
            observed=[core.obs; extra_obs], name=name,
        ),
        inlet,
        outlet,
        extra_ports...,
    )
end

"""
    Channel(; name, n, geometry, g=0.0, h_left=0.0, h_right=0.0,
            darcy=BlasiusFriction()) -> System

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
- `darcy`: wall friction model ([`DarcyFactor`](@ref)), default [`BlasiusFriction`](@ref).
  Handed `(T_bulk, T_wall, ṁ, liquid, geometry)` per cell. Regime switching and the heated-wall
  viscosity correction are [`RegimeDependentFriction`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref). Pass a [`Liquid`](@ref) to
  drive the energy balance, friction, and dimensionless observables with fixed properties.

# External-input variables
- `T_wall_left(t)[1:n]`: per-cell left-face wall temperature [°C]
- `T_wall_right(t)[1:n]`: per-cell right-face wall temperature [°C]

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
    darcy::DarcyFactor=BlasiusFriction(),
    liquid::AbstractLiquid=H2O,
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

    return _channel_system(;
        name=name, n=n, geometry=geometry, g=g,
        darcy=darcy, liquid=liquid,
        vars=varstruct, pars=pars, inlet=inlet, outlet=outlet,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        T_wall=_face_mean_wall(varstruct),
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0,
                    darcy=BlasiusFriction()) -> System

Single-phase convective channel with `n` axial finite-volume cells.
Heat flux is either a user prescribed closure or bindings with a `HeatFluxSource` source).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `darcy`: wall friction model ([`DarcyFactor`](@ref)), default [`BlasiusFriction`](@ref).
  Handed `(T_bulk, T_wall, ṁ, liquid, geometry)` per cell. Regime switching and the heated-wall
  viscosity correction are [`RegimeDependentFriction`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref).

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
    darcy::DarcyFactor=BlasiusFriction(),
    liquid::AbstractLiquid=H2O,
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

    return _channel_system(;
        name=name, n=n, geometry=geometry, g=g,
        darcy=darcy, liquid=liquid,
        vars=varstruct, pars=pars, inlet=inlet, outlet=outlet,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        extra_vars=exvars,
    )
end



"""
    ChannelAndContacts(; name, n, geometry, g=0.0,
                       htc=DittusBoelter(),
                       darcy::DarcyFactor=BlasiusFriction(),
                       liquid=H2O) -> System

Convective channel with per-cell `ThermalPort` arrays on both sides for conjugate heat
transfer (the variant that connects to `HeatDiffusion`). The `htc` model gives each cell its
`h_tc[i]`, the wall temperature arrives through the thermal ports, and the heat into the cell
is `h_tc[i] * heated_parts * dz * (T_wall - T[i])`.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (PipeGeometry)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `htc`: wall heat transfer model ([`HTC`](@ref)), default [`DittusBoelter`](@ref). It is
  handed `(T_wall, T_bulk, ṁ, Dh, A, liquid, P)` per cell and returns `h`. Subcooled boiling
  is a model like any other: wrap one in [`SubcooledBoilingHTC`](@ref). Regime switching is
  [`RegimeDependentHTC`](@ref).
- `darcy`: wall friction model ([`DarcyFactor`](@ref)), default [`BlasiusFriction`](@ref).
  Handed `(T_bulk, T_wall, ṁ, liquid, geometry)` per cell. Regime switching and the heated-wall
  viscosity correction are [`RegimeDependentFriction`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref). It drives the energy balance,
  friction, the HTC model, and the dimensionless observables.

# Ports
- `inlet`, `outlet` -- `FlowPort`
- `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell, per side)
"""
function ChannelAndContacts(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    htc::HTC=DittusBoelter(),
    darcy::DarcyFactor=BlasiusFriction(),
    liquid::AbstractLiquid=H2O,
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

    # The two faces differ only in which thermal port, HTC, Nusselt, and heated perimeter
    # they carry. Gathering that into a pair and looping keeps one copy of the wall physics
    # instead of a left block and a near-identical right block.
    faces = (
        (port=thermal_left, h=h_tc_left, Nu=Nu_left, T_wall=vars.T_wall_left,
         Gr_over_Re2=Gr_over_Re2_left, perimeter=geometry.heated_parts[1]),
        (port=thermal_right, h=h_tc_right, Nu=Nu_right, T_wall=vars.T_wall_right,
         Gr_over_Re2=Gr_over_Re2_right, perimeter=geometry.heated_parts[2]),
    )

    T = collect(vars.T)
    # Cell-centre pressure, which the subcooled-boiling HTC needs for T_sat and the ONB
    # superheat. Same expression `_channel_core` uses for its P observable.
    P_cell = inlet.p .- cumsum(collect(vars.dp)) .+ collect(vars.dp) ./ 2
    wall_T(face) = [port.T for port in face.port]
    q_wall(face) = collect(face.h) .* face.perimeter .* dz .* (wall_T(face) .- T)

    # Every model takes the local pressure; only one that boils looks at it.
    wall_htc(face, i) = htc(face.port[i].T, T[i], inlet.ṁ, Dh, A, liquid, P_cell[i])

    q_left_expr, q_right_expr = q_wall.(faces)

    variant_eqs = Equation[]
    for face in faces
        append!(variant_eqs, [face.h[i] ~ wall_htc(face, i) for i in 1:n])
    end
    for (face, q) in zip(faces, (q_left_expr, q_right_expr))
        append!(variant_eqs, [face.port[i].Q ~ q[i] for i in 1:n])
    end

    Re_bulk = Re.(liquid, T, inlet.ṁ, A, Dh)

    variant_obs = Equation[]
    for face in faces
        T_wall = wall_T(face)
        Gr_face = Gr.(liquid, T, T_wall, Dh, g)
        # Nu implied by the h in use, rather than by re-running a correlation the model
        # may not have: Nu = h·Dh/κ at the film temperature.
        append!(variant_obs, collect(face.Nu) .~
            Nu.(collect(face.h), Dh, κ.(liquid, film_temperature.(T_wall, T))))
        append!(variant_obs, collect(face.T_wall) .~ T_wall)
        append!(variant_obs, collect(face.Gr_over_Re2) .~ Gr_face ./ Re_bulk .^ 2)
    end
    append!(variant_obs, collect(velocity) .~ abs.(collect(vars.v)))
    push!(variant_obs, Q_wall_total ~ sum(q_left_expr .+ q_right_expr))

    return _channel_system(;
        name=name, n=n, geometry=geometry, g=g,
        darcy=darcy, liquid=liquid,
        vars=vars, pars=pars, inlet=inlet, outlet=outlet,
        q_left_expr=q_left_expr, q_right_expr=q_right_expr,
        # Straight off the ports, not off the T_wall observables: an observable must not
        # appear on the RHS of the momentum equation.
        T_wall=(wall_T(faces[1]) .+ wall_T(faces[2])) ./ 2,
        extra_vars=exvars, extra_eqs=variant_eqs, extra_obs=variant_obs,
        extra_ports=(thermal_left..., thermal_right...),
    )
end

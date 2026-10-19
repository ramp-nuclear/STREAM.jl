"""
    Channel

Single-phase convective channel with `n` axial finite-volume cells, heated through a given
convective coefficient. See the constructor method below for arguments and ports.

Unrelated to `Base.Channel`, Julia's task-communication channel. `using STREAM.Components`
leaves the name ambiguous between the two, so import it explicitly with
`using STREAM.Components: Channel` or write `Components.Channel`.
"""
function Channel end

"""
    _static_pressure(p_inlet, dp, ṁ, ρ, A) -> Vector

The static pressure at each cell's outlet-side face, the pressure saturation depends on.

The pressure a `FlowPort` carries is the total pressure, static plus the dynamic head
`ρv²/2`. So the static pressure at a face is the inlet's pressure, less the drop `dp` through
every cell up to that face, less the head at the local density:

    p_static[i] = p_inlet - (dp[1] + ... + dp[i]) - ṁ² / (2ρ[i]A²)
"""
_static_pressure(p_inlet, dp, ṁ, ρ, A) = p_inlet .- cumsum(dp) .- ṁ^2 ./ (2 .* ρ .* A^2)

"""
    _GravityKey

The metadata key a channel stores its gravitational acceleration along the flow under [m/s²],
for `check_gravity_mismatch` to read.
"""
struct _GravityKey end

"""
    _faces(geometry) -> Tuple{Vararg{Symbol}}

The faces of a channel on `geometry`: one per heated wall of its duct, named after the wall.
"""
_faces(geometry::Duct) = keys(geometry.heated)

"""
    _per_face(prefix, faces, n; default=nothing) -> NamedTuple

One length-`n` array variable per face, named `<prefix><face>`, such as `T_wall_left`.
"""
function _per_face(prefix, faces, n; default=nothing)
    vars = map(faces) do f
        name = Symbol(prefix, f)
        default === nothing ? only(@variables $name(t)[1:n]) :
                              only(@variables $name(t)[1:n] = fill(default, n))
    end
    return NamedTuple{faces}(vars)
end

"""
    _channel_core(; n, inlet, outlet, geometry, g_acc, darcy, q_face, vars, liquid,
                  T_wall=nothing) -> NamedTuple

The equations every channel shares: the energy balance in enthalpy form with a face-averaged
cp, mass conservation, the momentum ODE `(L/A)·D(ṁ)`, per-cell friction and hydrostatic head,
port wiring, and the observables. A variant declares the variables, states how heat reaches
each face, and splices what this returns into its own lists.

# Arguments
- `n`: number of axial cells
- `inlet`, `outlet`: the variant's `FlowPort`s
- `geometry`: the channel's [`Duct`](@ref)
- `g_acc`: gravitational acceleration [m/s²]
- `darcy`: wall friction model ([`AbstractDarcyFactor`](@ref))
- `q_face`: per face, the heat flow into each cell [W], a length-`n` vector
- `vars`: the variables from `_setup`
- `liquid`: the coolant
- `T_wall`: the length-`n` wall temperature the friction model reads, or `nothing` to hand
  it the bulk

# Returns
`(; eqs, obs)`, the equations and observables.

# Energy balance per cell

    cp_face = (cₚ(liquid, T_up) + cₚ(liquid, T[i])) / 2
    D(T[i]) ~ (|ṁ| cp_face (T_up - T[i]) + Σ_faces q_face[i]) / (ρ(T[i]) cₚ(T[i]) A dz)
"""
function _channel_core(;
    n::Int,
    inlet,
    outlet,
    geometry::Duct,
    g_acc::Real,
    darcy::AbstractDarcyFactor=Blasius(),
    q_face::NamedTuple,
    vars,
    liquid::AbstractLiquid=H2O,
    T_wall=nothing,
)
    Dh = hydraulic_diameter(geometry)
    A  = flow_area(geometry)
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
    P_c = _static_pressure(inlet.p, dp, inlet.ṁ, ρ_c, A)
    q_c = isempty(q_face) ? zeros(Num, n) : reduce(.+, values(q_face))
    # An unheated duct has no heated perimeter to divide by, and no flux.
    q_density_c = isempty(q_face) ? q_c : q_c ./ (heated_perimeter(geometry) * dz)

    cells = map(1:n) do i
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(inlet.ṁ >= 0, T_up_fwd, T_up_rev)

        cp_face = (cₚ(liquid, T_up) + cp_c[i]) / 2
        f_i = darcy(T_wall_c[i], T[i], inlet.ṁ, liquid, geometry)

        cell_eqs = Equation[
            # Energy balance, enthalpy form
            D(T[i]) ~ (abs(inlet.ṁ) * cp_face * (T_up - T[i]) + q_c[i]) /
                      (ρ_c[i] * cp_c[i] * A * dz),
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
            # A wall cooler than the coolant has no onset to reach, and the correlation's
            # fractional power is NaN for a negative flux, so such a cell reports saturation.
            vars.T_ONB[i] ~ Tsat(liquid, P_c[i]) +
                            _bergles_rohsenow_dT_ONB(P_c[i], max(q_density_c[i], 0.0)),
            (vars.q_face[f][i] ~ q_face[f][i] for f in keys(q_face))...,
            vars.q_wall[i] ~ q_c[i],
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
            # An equation, not an observable: it reads instream, which ModelingToolkit only
            # resolves inside equations.
            vars.T_in ~ ifelse(inlet.ṁ >= 0, T_inlet_fwd, T_inlet_rev),
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

"""
    _mean_wall(walls) -> Union{Vector,Nothing}

The per-cell mean of the faces' wall temperatures, which the friction model reads, or
`nothing` for a channel with no face. Python's channel hands its friction model the mean of
its two walls.
"""
_mean_wall(walls::NamedTuple) =
    isempty(walls) ? nothing : reduce(.+, map(collect, values(walls))) ./ length(walls)

"""
    _setup(geometry, n) -> (pars, vars, inlet, outlet)

The parameters, variables and ports every channel declares. Each face of the duct gets its
own `T_wall_<face>` and `q_wall_<face>`, gathered under `vars.T_wall` and `vars.q_face`.
"""
function _setup(geometry, n)
    # No geometry parameters are declared: L, Dh, and A enter the equations inline from
    # `geometry` (see `_channel_core` and the variants). When a dimension is a design knob,
    # that inline value is the knob expression, so `remake` scans it.
    pars = []

    @variables begin
        (T(t))[1:n] = fill(T_ROOM, n)
        (dp(t))[1:n]
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        T_in(t)
        T_out(t)
        dP(t)
    end
    faces = _faces(geometry)
    T_wall = _per_face(:T_wall_, faces, n)
    q_face = _per_face(:q_wall_, faces, n)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    vars = (; T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall, T_in, T_out, dP, T_wall, q_face)
    return pars, vars, inlet, outlet
end

"""
    _vcollect(vars) -> Vector

Every variable `_setup` declared, flattened into one list for the `System`.
"""
function _vcollect(vars)
    arrays = (vars.T, vars.dp, values(vars.T_wall)..., vars.Re, vars.Pe, vars.v, vars.P,
              vars.T_sat, vars.T_ONB, vars.q_wall, values(vars.q_face)...)
    return [reduce(vcat, map(collect, arrays)); vars.T_in; vars.T_out; vars.dP]
end

"""
    _channel_system(; name, n, geometry, g, darcy, liquid, vars, pars, inlet, outlet,
                    q_face, T_wall=nothing, extra_vars=(), extra_eqs=Equation[],
                    extra_obs=Equation[], extra_ports=()) -> System

Build the composed `System` for a channel variant. Every variant states the heat flow into
each face and whatever extra variables, equations, observables, and ports it adds, then hands
them here; the shared core equations and the `compose` call live in one place. The system
carries `geometry`, for [`duct`](@ref) to read back, and `g`, for `check_gravity_mismatch`.
"""
function _channel_system(;
    name, n::Int, geometry::Duct, g, darcy, liquid,
    vars, pars, inlet, outlet, q_face, T_wall=nothing,
    extra_vars=(), extra_eqs=Equation[], extra_obs=Equation[], extra_ports=(),
)
    core = _channel_core(;
        n, inlet, outlet, geometry, g_acc=g, darcy, q_face, vars, liquid, T_wall,
    )
    all_vars = [_vcollect(vars); reduce(vcat, (collect(v) for v in extra_vars); init=Num[])]
    sys = compose(
        System(
            [core.eqs; extra_eqs], t, all_vars, pars;
            observed=[core.obs; extra_obs], name=name,
        ),
        inlet,
        outlet,
        extra_ports...,
    )
    return ModelingToolkit.setmetadata(_with_duct(sys, geometry), _GravityKey, g)
end

"""
    _h_cells(h, n, name) -> (cells, pars)

A face's convective coefficient as one value per cell: a number for every cell, a length-`n`
profile, or a callable of time, which becomes the callable parameter `name`.
"""
_h_cells(h::Real, n, name) = (fill(Num(h), n), [])

function _h_cells(h::AbstractVector{<:Real}, n, name)
    length(h) == n ||
        throw(DimensionMismatch("h has length $(length(h)), expected n=$n"))
    return (Num.(h), [])
end

function _h_cells(h, n, name)
    FType = typeof(h)
    p = only(@parameters ($name::FType)(..))
    return (fill(p(t), n), [p])
end

"""
    Channel(; name, n, geometry, g=0.0, h=0.0, darcy=Blasius(), liquid=H2O) -> System

Single-phase convective channel with `n` axial finite-volume cells, heated through a given
convective coefficient against a wall temperature the caller binds.

The channel has one face per heated wall of its duct, named after the wall: `left` and
`right` for a rectangle, `outer` for a circle. Each face passes `h · heated · dz · (T_wall - T)`
into a cell, `heated` being the face's heated width.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: the channel's [`Duct`](@ref)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `h`: convective coefficient [W/(m^2·K)], for every face or per face as a named tuple such
  as `(left=5000.0,)`, where a face left out gets 0, adiabatic. Each value is a number, a
  length-`n` profile, or a function of time. A function becomes a callable parameter that
  the operating point must give: `ch.h_fn => fn` for one function on every face, or
  `ch.h_left_fn => fn` for one given by face. Default 0.0, adiabatic.
- `darcy`: wall friction model ([`AbstractDarcyFactor`](@ref)), default [`Blasius`](@ref).
  Handed `(T_wall, T_bulk, ṁ, liquid, geometry)` per cell, with the mean of the faces' wall
  temperatures. Regime switching and the heated-wall viscosity correction are
  [`Friction.RegimeDependent`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref). Pass a [`Liquid`](@ref STREAM.Substances.Liquid) to
  drive the energy balance, friction, and dimensionless observables with fixed properties.

# External-input variables
- `T_wall_<face>(t)[1:n]`: the face's per-cell wall temperature [°C], such as `T_wall_left`

These have no internal equation. A face with a nonzero `h` needs its wall closed, and so does
any wall a friction model reads, such as [`Friction.RegimeDependent`](@ref) with a `viscosity`
correction. A face with `h = 0` under a friction model that ignores the wall, the default,
needs nothing: its wall temperature appears in no equation. Close a wall in the connection
list, as in `ch.T_wall_left .~ 100.0`, with a number, a length-`n` profile, a parameter or any
expression in `t`. See [Bind a wall temperature or heat flux](@ref).

# Ports
- `inlet`, `outlet` -- `FlowPort` (mass + momentum + stream T)
  *No thermal ports: see the external-input variables above.*
"""
function Channel(;
    name,
    n::Int,
    geometry::Duct,
    g=0.0,
    h=0.0,
    darcy::AbstractDarcyFactor=Blasius(),
    liquid::AbstractLiquid=H2O,
)
    pars, vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    dz = geometry.L / n

    pars = Any[pars...]
    h_face = if h isa NamedTuple
        for f in keys(h)
            f in faces || throw(ArgumentError(
                "h names face :$f, but the channel's faces are $(join(repr.(faces), ", "))"))
        end
        map(faces) do f
            cells, p = _h_cells(get(h, f, 0.0), n, Symbol(:h_, f, :_fn))
            append!(pars, p)
            cells
        end
    else
        cells, p = _h_cells(h, n, :h_fn)
        append!(pars, p)
        map(_ -> cells, faces)
    end

    q_face = map(faces, h_face) do f, h_cells
        h_cells .* geometry.heated[f] .* dz .* (collect(vars.T_wall[f]) .- collect(vars.T))
    end

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, pars, inlet, outlet,
        q_face=NamedTuple{faces}(q_face), T_wall=_mean_wall(vars.T_wall),
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0, darcy=Blasius(), liquid=H2O) -> System

Single-phase convective channel with `n` axial finite-volume cells, with the heat flux on each
face prescribed per cell by the caller.

The channel has one face per heated wall of its duct, named after the wall, as for
[`Channel`](@ref).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: the channel's [`Duct`](@ref)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `darcy`: wall friction model ([`AbstractDarcyFactor`](@ref)), default [`Blasius`](@ref).
  Handed `(T_bulk, T_bulk, ṁ, liquid, geometry)` per cell, having no wall temperature of
  its own. Regime switching is [`Friction.RegimeDependent`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref).

# External-input variables
- `q_<face>(t)[1:n]`: the face's per-cell heat flux density [W/m^2], such as `q_left`

These have no internal equation. Close them in the connection list:
```julia
connections = [
    ...,
    chf.q_left .~ q_value,
    chf.q_right .~ 0.0,
]
```

# Ports
- `inlet`, `outlet` -- `FlowPort` (mass + momentum + stream T)
  *No heat-flux ports: see the external-input variables above.*
"""
function ChannelHeatFlux(;
    name,
    n::Int,
    geometry::Duct,
    g=0.0,
    darcy::AbstractDarcyFactor=Blasius(),
    liquid::AbstractLiquid=H2O,
)
    pars, vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    dz = geometry.L / n

    flux = _per_face(:q_, faces, n)
    q_face = map(f -> collect(flux[f]) .* geometry.heated[f] .* dz, faces)

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, pars, inlet, outlet,
        q_face=NamedTuple{faces}(q_face), extra_vars=values(flux),
    )
end



"""
    ChannelAndContacts(; name, n, geometry, g=0.0, htc=DittusBoelter(), darcy=Blasius(),
                       liquid=H2O) -> System

Convective channel with a per-cell `ThermalPort` array on each face, for conjugate heat
transfer (the variant that connects to `HeatDiffusion`). The channel has one face per heated
wall of its duct, named after the wall, as for [`Channel`](@ref). The `htc` model gives each
cell of each face its `h_tc`, the wall temperature arrives through the thermal ports, and the
heat into the cell is `h_tc[i] * heated * dz * (T_wall - T[i])`, `heated` being the face's
heated width.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: the channel's [`Duct`](@ref)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `htc`: wall heat transfer model ([`HTC`](@ref)), default [`DittusBoelter`](@ref). It is
  handed `(T_wall, T_bulk, ṁ, liquid, geometry, P)` per cell and returns `h`. Subcooled boiling
  is a model like any other: wrap one in [`SubcooledBoiling`](@ref). Regime switching is
  [`HTC.RegimeDependent`](@ref).
- `darcy`: wall friction model ([`AbstractDarcyFactor`](@ref)), default [`Blasius`](@ref).
  Handed `(T_wall, T_bulk, ṁ, liquid, geometry)` per cell, with the mean of the faces' wall
  temperatures. Regime switching and the heated-wall viscosity correction are
  [`Friction.RegimeDependent`](@ref).
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref). It drives the energy balance,
  friction, the HTC model, and the dimensionless observables.

# Ports
- `inlet`, `outlet` -- `FlowPort`
- `thermal_<face>[1:n]` -- a `ThermalPort` array per face, one port per axial cell, such as
  `thermal_left`
"""
function ChannelAndContacts(;
    name,
    n::Int,
    geometry::Duct,
    g=0.0,
    htc::AbstractHTC=DittusBoelter(),
    darcy::AbstractDarcyFactor=Blasius(),
    liquid::AbstractLiquid=H2O,
)
    pars, vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    Dh = hydraulic_diameter(geometry)
    A  = flow_area(geometry)
    dz = geometry.L / n

    ports = NamedTuple{faces}(map(faces) do f
        [ThermalPort(; name=Symbol(:thermal_, f, i)) for i in 1:n]
    end)
    # Default 5000.0 seeds the nonlinear initialization solve. h_tc[i] ~ Nu*k/Dh with Nu
    # evaluated at T_film makes h_tc a tearing variable whose init guess-map is
    # self-referential without a numeric seed (MTK "Cyclic guesses").
    h_tc = _per_face(:h_tc_, faces, n; default=5000.0)
    Nu_face = _per_face(:Nu_, faces, n)
    Gr_over_Re2 = _per_face(:Gr_over_Re2_, faces, n)
    exvars = @variables begin
        (velocity(t))[1:n]
        Q_wall_total(t)
    end

    T = collect(vars.T)
    # The pressure subcooled boiling reads saturation at, the same as the P observable.
    P_cell = _static_pressure(inlet.p, collect(vars.dp), inlet.ṁ, ρ.(liquid, T), A)
    # Straight off the ports, not off the T_wall observables: an observable must not appear
    # on the RHS of another equation.
    wall_T = NamedTuple{faces}(map(f -> [port.T for port in ports[f]], faces))
    q_face = NamedTuple{faces}(map(faces) do f
        collect(h_tc[f]) .* geometry.heated[f] .* dz .* (wall_T[f] .- T)
    end)

    # Every model takes the local pressure; only one that boils looks at it.
    variant_eqs = Equation[
        [h_tc[f][i] ~ htc(wall_T[f][i], T[i], inlet.ṁ, liquid, geometry, P_cell[i])
         for f in faces for i in 1:n];
        [ports[f][i].Q ~ q_face[f][i] for f in faces for i in 1:n]
    ]

    Re_bulk = Re.(liquid, T, inlet.ṁ, geometry)
    variant_obs = Equation[]
    for f in faces
        Gr_face = Gr.(liquid, T, wall_T[f], Dh, g)
        # Nu implied by the h in use, rather than by re-running a correlation the model
        # may not have: Nu = h·Dh/κ at the film temperature.
        append!(variant_obs, collect(Nu_face[f]) .~
            Nu.(collect(h_tc[f]), Dh, κ.(liquid, film_temperature.(wall_T[f], T))))
        append!(variant_obs, collect(vars.T_wall[f]) .~ wall_T[f])
        append!(variant_obs, collect(Gr_over_Re2[f]) .~ Gr_face ./ Re_bulk .^ 2)
    end
    append!(variant_obs, collect(velocity) .~ abs.(collect(vars.v)))
    q_total = isempty(faces) ? 0.0 : sum(sum, values(q_face))
    push!(variant_obs, Q_wall_total ~ q_total)

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, pars, inlet, outlet, q_face,
        T_wall=_mean_wall(wall_T),
        extra_vars=(values(h_tc)..., values(Nu_face)..., exvars[1], values(Gr_over_Re2)...,
                    exvars[2]),
        extra_eqs=variant_eqs, extra_obs=variant_obs,
        extra_ports=Iterators.flatten(values(ports)),
    )
end

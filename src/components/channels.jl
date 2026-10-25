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
    _faces(geometry) -> Tuple{Vararg{Symbol}}

The faces of a channel on `geometry`: one per heated wall of its duct, named after the wall.
"""
_faces(geometry::Duct) = keys(geometry.heated)

"""
    _by_face(f, faces) -> NamedTuple

`f` applied to each face, keyed by face name.
"""
_by_face(f, faces) = NamedTuple{faces}(map(f, faces))

"""
    _per_face(prefix, faces, n; default=nothing) -> NamedTuple

One length-`n` array variable per face, named `<prefix><face>`, such as `T_wall_left`, each
as a `Vector{Num}` of its cells.
"""
function _per_face(prefix, faces, n; default=nothing)
    return _by_face(faces) do f
        name = Symbol(prefix, f)
        scalarize(default === nothing ? only(@variables $name(t)[1:n]) :
                                        only(@variables $name(t)[1:n] = fill(default, n)))
    end
end

"""
    _channel_core(; n, inlet, outlet, geometry, g, darcy, q_face, vars, liquid,
                  T_wall=nothing) -> NamedTuple

The equations every channel shares: the energy balance in enthalpy form with a face-averaged
cp, mass conservation, the momentum ODE `(L/A)·D(ṁ)`, per-cell friction and hydrostatic head,
port wiring, and the observables. A variant declares the variables, states how heat reaches
each face, and splices what this returns into its own lists.

# Arguments
- `n`: number of axial cells
- `inlet`, `outlet`: the variant's `FlowPort`s
- `geometry`: the channel's [`Duct`](@ref)
- `g`: gravitational acceleration along the flow [m/s²]
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
    g::Real,
    darcy::AbstractDarcyFactor,
    q_face::NamedTuple,
    vars,
    liquid::AbstractLiquid,
    T_wall=nothing,
)
    Dh = hydraulic_diameter(geometry)
    A  = flow_area(geometry)
    L  = geometry.L
    dz = L / n

    T, dp = vars.T, vars.dp
    # A variant with no wall of its own hands the friction model the bulk temperature, which
    # makes the wall-to-bulk viscosity ratio exactly 1 and the correction a no-op.
    T_wall_c = something(T_wall, T)

    ṁ = inlet.ṁ
    T_inlet_fwd = instream(inlet.T)
    T_inlet_rev = instream(outlet.T)

    # Density and specific heat are named because several equations below reuse them; the
    # rest of the properties are reached through the dimensionless numbers that want them.
    ρ_c  = ρ.(liquid, T)
    cp_c = cₚ.(liquid, T)

    Re_c = Re.(liquid, T, ṁ, A, Dh)
    Pr_c = Pr.(liquid, T)
    P_c = _static_pressure(inlet.p, dp, ṁ, ρ_c, A)
    q_c = sum(values(q_face); init=zeros(Num, n))
    # An unheated duct has no heated perimeter to divide by, and no flux.
    q_density_c = isempty(q_face) ? q_c : q_c ./ (heated_perimeter(geometry) * dz)

    T_up = ifelse.(ṁ >= 0, [T_inlet_fwd; T[1:(end - 1)]], [T[2:end]; T_inlet_rev])
    cp_face = (cₚ.(liquid, T_up) .+ cp_c) ./ 2
    f_c = darcy.(T_wall_c, T, ṁ, liquid, geometry)
    T_sat_c = Tsat.(liquid, P_c)

    eqs = _flat(
        # Energy balance, enthalpy form
        D.(T) .~ (abs(ṁ) .* cp_face .* (T_up .- T) .+ q_c) ./ (ρ_c .* cp_c .* A .* dz),
        # Darcy-Weisbach friction over the cell, plus its hydrostatic head
        dp .~ darcy_weisbach_dp.(ṁ, ρ_c, f_c, dz, Dh, A) .+ ρ_c .* g .* dz,
        ṁ + outlet.ṁ ~ 0,
        (L / A) * D(ṁ) ~ (inlet.p - outlet.p) - sum(dp),
        outlet.T ~ T[n],
        inlet.T ~ T[1],
        # An equation, not an observable: it reads instream, which ModelingToolkit only
        # resolves inside equations.
        vars.T_in ~ ifelse(ṁ >= 0, T_inlet_fwd, T_inlet_rev),
    )
    obs = _flat(
        vars.Re .~ Re_c,
        vars.Pe .~ Re_c .* Pr_c,
        vars.v .~ ṁ ./ (ρ_c .* A),
        vars.P .~ P_c,
        vars.T_sat .~ T_sat_c,
        # A wall cooler than the coolant has no onset to reach, and the correlation's
        # fractional power is NaN for a negative flux, so such a cell reports saturation.
        vars.T_ONB .~ T_sat_c .+ _bergles_rohsenow_dT_ONB.(P_c, max.(q_density_c, 0.0)),
        map(f -> vars.q_face[f] .~ q_face[f], keys(q_face)),
        vars.q_wall .~ q_c,
        vars.T_out ~ ifelse(ṁ >= 0, T[n], T[1]),
        vars.dP ~ inlet.p - outlet.p,
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
    isempty(walls) ? nothing : reduce(.+, values(walls)) ./ length(walls)

"""
    _setup(geometry, n) -> (vars, inlet, outlet)

The variables and ports every channel declares. Each array variable comes
scalarized, as a `Vector{Num}` of its cells, since a broadcast over a symbolic array stays one
array expression where the equations want one per cell. Each face of the duct gets its own
`T_wall_<face>` and `q_wall_<face>`, gathered under `vars.T_wall` and `vars.q_face`.
"""
function _setup(geometry, n)
    # No geometry parameters are declared: L, Dh, and A enter the equations inline from
    # `geometry` (see `_channel_core` and the variants). When a dimension is a design knob,
    # that inline value is the knob expression, so `remake` scans it.
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
    @named outlet = FlowPort(; ṁ=-FLOW_START)

    cells = map(scalarize, (; T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall))
    vars = (; cells..., T_in, T_out, dP, T_wall, q_face)
    return vars, inlet, outlet
end

"""
    _all_variables(vars) -> Vector{Num}

Every variable `_setup` declared, in one list for the `System`.
"""
_all_variables(vars) =
    vcat(vars.T, vars.dp, values(vars.T_wall)..., vars.Re, vars.Pe, vars.v, vars.P, vars.T_sat,
         vars.T_ONB, vars.q_wall, values(vars.q_face)..., vars.T_in, vars.T_out, vars.dP)

"""
    _channel_system(; name, n, geometry, g, darcy, liquid, vars, inlet, outlet, q_face,
                    pars=[], T_wall=nothing, extra_vars=(), extra_eqs=Equation[],
                    extra_obs=Equation[], extra_ports=()) -> System

Build the composed `System` for a channel variant. Every variant states the heat flow into
each face and whatever extra variables, equations, observables, and ports it adds, then hands
them here; the shared core equations and the `compose` call live in one place. The system
carries `geometry`, for [`duct`](@ref) to read back.
"""
function _channel_system(;
    name, n::Int, geometry::Duct, g, darcy, liquid,
    vars, inlet, outlet, q_face, pars=[], T_wall=nothing,
    extra_vars=(), extra_eqs=Equation[], extra_obs=Equation[], extra_ports=(),
)
    core = _channel_core(;
        n, inlet, outlet, geometry, g, darcy, q_face, vars, liquid, T_wall,
    )
    all_vars = vcat(_all_variables(vars), extra_vars...)
    sys = compose(
        System(_flat(core.eqs, extra_eqs), t, all_vars, pars;
               observed=_flat(core.obs, extra_obs), name,
               metadata=(_CoolantKey => liquid,)),
        inlet,
        outlet,
        extra_ports...,
    )
    return _with_duct(sys, geometry)
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
    Channel(; name, n, geometry, g=0.0, h=0.0, darcy=Blasius(),
            liquid=default_coolant()) -> System

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
- `liquid`: coolant (`AbstractLiquid`), default [`default_coolant()`](@ref
  STREAM.Substances.default_coolant). Pass a [`Liquid`](@ref STREAM.Substances.Liquid) to
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
    liquid::AbstractLiquid=default_coolant(),
)
    vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    dz = geometry.L / n

    pars = []
    function cells(value, fn_name)
        h_cells, p = _h_cells(value, n, fn_name)
        append!(pars, p)
        return h_cells
    end
    h_face = if h isa NamedTuple
        issubset(keys(h), faces) ||
            throw(ArgumentError("h names faces $(keys(h)), but the channel's faces are $faces"))
        _by_face(f -> cells(get(h, f, 0.0), Symbol(:h_, f, :_fn)), faces)
    else
        shared = cells(h, :h_fn)
        _by_face(_ -> shared, faces)
    end
    q_face = _by_face(f -> h_face[f] .* geometry.heated[f] .* dz .* (vars.T_wall[f] .- vars.T),
                      faces)

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, pars, inlet, outlet, q_face,
        T_wall=_mean_wall(vars.T_wall),
    )
end


"""
    ChannelHeatFlux(; name, n, geometry, g=0.0, darcy=Blasius(),
                    liquid=default_coolant()) -> System

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
- `liquid`: coolant (`AbstractLiquid`), default
  [`default_coolant()`](@ref STREAM.Substances.default_coolant).

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
    liquid::AbstractLiquid=default_coolant(),
)
    vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    flux = _per_face(:q_, faces, n)
    q_face = _by_face(f -> flux[f] .* geometry.heated[f] .* (geometry.L / n), faces)

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, inlet, outlet, q_face,
        extra_vars=values(flux),
    )
end



"""
    ChannelAndContacts(; name, n, geometry, g=0.0, htc=DittusBoelter(), darcy=Blasius(),
                       liquid=default_coolant()) -> System

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
- `liquid`: coolant (`AbstractLiquid`), default [`default_coolant()`](@ref
  STREAM.Substances.default_coolant). It drives the energy balance,
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
    liquid::AbstractLiquid=default_coolant(),
)
    vars, inlet, outlet = _setup(geometry, n)
    faces = _faces(geometry)
    Dh = hydraulic_diameter(geometry)
    A  = flow_area(geometry)
    dz = geometry.L / n

    ports = _by_face(f -> [ThermalPort(; name=Symbol(:thermal_, f, i)) for i in 1:n], faces)
    # Default 5000.0 seeds the nonlinear initialization solve. h_tc[i] ~ Nu*k/Dh with Nu
    # evaluated at T_film makes h_tc a tearing variable whose init guess-map is
    # self-referential without a numeric seed (MTK "Cyclic guesses").
    h_tc = _per_face(:h_tc_, faces, n; default=5000.0)
    Nu_face = _per_face(:Nu_, faces, n)
    Gr_over_Re2 = _per_face(:Gr_over_Re2_, faces, n)
    velocity = scalarize(only(@variables velocity(t)[1:n]))
    @variables Q_wall_total(t)

    T = vars.T
    # The pressure subcooled boiling reads saturation at, the same as the P observable.
    P_cell = _static_pressure(inlet.p, vars.dp, inlet.ṁ, ρ.(liquid, T), A)
    # Straight off the ports, not off the T_wall observables: an observable must not appear
    # on the RHS of another equation.
    wall_T = _by_face(f -> port(ports[f], :T), faces)
    q_face = _by_face(f -> h_tc[f] .* geometry.heated[f] .* dz .* (wall_T[f] .- T), faces)

    Re_bulk = Re.(liquid, T, inlet.ṁ, geometry)
    # Every model takes the local pressure; only one that boils looks at it.
    face_eqs(f) = (
        h_tc[f] .~ htc.(wall_T[f], T, inlet.ṁ, liquid, geometry, P_cell),
        port(ports[f], :Q) .~ q_face[f],
    )
    face_obs(f) = (
        # Nu implied by the h in use, rather than by re-running a correlation the model
        # may not have: Nu = h·Dh/κ at the film temperature.
        Nu_face[f] .~ Nu.(h_tc[f], Dh, κ.(liquid, film_temperature.(wall_T[f], T))),
        vars.T_wall[f] .~ wall_T[f],
        Gr_over_Re2[f] .~ Gr.(liquid, T, wall_T[f], Dh, g) ./ Re_bulk .^ 2,
    )
    variant_eqs = _flat(map(face_eqs, faces))
    variant_obs = _flat(
        map(face_obs, faces),
        velocity .~ abs.(vars.v),
        Q_wall_total ~ sum(sum, values(q_face); init=0.0),
    )

    return _channel_system(;
        name, n, geometry, g, darcy, liquid, vars, inlet, outlet, q_face,
        T_wall=_mean_wall(wall_T),
        extra_vars=(values(h_tc)..., values(Nu_face)..., velocity, values(Gr_over_Re2)...,
                    Q_wall_total),
        extra_eqs=variant_eqs, extra_obs=variant_obs,
        extra_ports=Iterators.flatten(values(ports)),
    )
end

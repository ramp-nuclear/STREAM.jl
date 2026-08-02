# resistors.jl -- Friction, Gravity, Resistor components

"""
    Friction(; name, L, D, A, darcy=BlasiusFriction(), liquid=H2O, scale=1.0) -> System
    Friction(; name, geometry, darcy=BlasiusFriction(), liquid=H2O, scale=1.0) -> System

Frictional pressure drop element, `ΔP = scale · f · ṁ|ṁ| / (2ρA²) · (L/Dh)`.

The friction factor comes from `darcy`, a [`DarcyFactor`](@ref). Passing
[`RegimeDependentFriction`](@ref) makes this the regime-switching friction resistor, with the
laminar/turbulent blend and, if asked for, the heated-wall viscosity correction.

Give it a [`PipeGeometry`](@ref) when the friction model needs the heated and wet perimeters,
which the viscosity correction does. The `L`/`D`/`A` form builds an equivalent circular
geometry, where those two perimeters coincide.

# Arguments
- `name`: system name (Symbol)
- `L`: pipe length [m]
- `D`: hydraulic diameter [m]
- `A`: flow area [m^2]
- `geometry`: pipe geometry descriptor ([`PipeGeometry`](@ref)), in place of `L`/`D`/`A`
- `darcy`: wall friction model ([`DarcyFactor`](@ref)), default [`BlasiusFriction`](@ref)
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref)
- `scale`: multiplies the pressure drop, default 1.0. See [`Resistor`](@ref).

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Friction(;
    name,
    geometry::Union{PipeGeometry,Nothing}=nothing,
    L=nothing, D=nothing, A=nothing,
    darcy::DarcyFactor=BlasiusFriction(),
    liquid::AbstractLiquid=H2O,
    scale::Real=1.0,
)
    geom = _friction_geometry(geometry, L, D, A)
    pars = @parameters scale = scale
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    Ax, Dh, Lx = geom.A, geom.Dh, geom.L
    eqs = Equation[
        Re ~ STREAM.Re(liquid, T_in, inlet.ṁ, Ax, Dh),
        # The resistor has no wall of its own, so the friction model reads the stream
        # temperature for both. A viscosity correction is then exactly 1.
        f ~ darcy(T_in, inlet.ṁ, liquid, geom),
        inlet.p - outlet.p ~
            scale * darcy_weisbach_dp(inlet.ṁ, ρ(liquid, T_in), f, Lx, Dh, Ax),
    ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars)
end

_friction_geometry(geom::PipeGeometry, ::Nothing, ::Nothing, ::Nothing) = geom

function _friction_geometry(::Nothing, L, D, A)
    if L === nothing || D === nothing || A === nothing
        throw(ArgumentError(
            "Friction needs either `geometry`, or all three of `L`, `D` and `A`."))
    end
    # An equivalent circular duct: heated and wet perimeter coincide, so a viscosity
    # correction weights them 1:1.
    perimeter = 4 * A / D
    return PipeGeometry(
        Float64(L), Float64(D), Float64(A), perimeter, perimeter,
        (perimeter / 2, perimeter / 2), Float64(D), Float64(D),
    )
end

function _friction_geometry(::PipeGeometry, L, D, A)
    throw(ArgumentError("Friction takes `geometry` or `L`/`D`/`A`, not both."))
end

"""
    Gravity(H; name) -> System

Hydrostatic pressure change for a vertical elevation change.

# Arguments
- `H`: elevation change [m], positive = upward
- `g`: gravitational acceleration [m/s^2]
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref)
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Gravity(H, g=G_EARTH; name, liquid::AbstractLiquid=H2O)
    pars = @parameters H = H
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    eqs = Equation[inlet.p - outlet.p ~ ρ(liquid, T_in) * g * H]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    Resistor(R; name) -> System

Generic flow resistance with a fixed resistance coefficient.

# Arguments
- `R`: resistance coefficient [Pa/(kg/s)]
- `name`: system name (Symbol)
- `scale`: multiplies the pressure drop, default 1.0. It is the composition knob: `scale=3`
  is three of this resistor in series, `scale=1/3` is three of it in parallel, and a
  calibrated resistor can be trimmed without touching the coefficient it was fitted with.
  Being a parameter, it is reachable from `remake`.

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Resistor(R; name, scale::Real=1.0)
    pars = @parameters R = R scale = scale
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.p - outlet.p ~ scale * R * inlet.ṁ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    VolumetricFlowResistor(; name, k, klow=0.0, density=nothing, liquid=H2O) -> System

Resistor quadratic in volumetric flow: `ΔP = k·Q·|Q| + klow·Q`, where `Q = ṁ/ρ` is the
volumetric flow rate. The `Q·|Q|` form keeps the drop direction-correct under flow reversal.

A **time-dependent** resistance (the "transistor" pattern — a branch whose resistance
collapses or grows over time) is expressed by passing `k` as a callable `(t) -> k`; the user
then supplies `vfr.k_fn => fn` in the solve `op` dict (the MTK callable-parameter idiom, the
same one `Channel`'s `h_left` uses).

# Arguments
- `name`: system name (Symbol)
- `k`: quadratic resistance coefficient [kg/m^7]; `Real` (fixed) or `Function` (time-varying
  via `k_fn` callable parameter)
- `klow`: linear (low-flow) coefficient [kg/(m^4·s)], default `0.0`
- `density`: overrides the coolant density [kg/m^3]; `Real` (constant) or `Function` `(T) -> rho`
  evaluated at the inlet stream temperature. Default `nothing` takes the density from `liquid`.
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref)
- `scale`: multiplies the pressure drop, default 1.0. See [`Resistor`](@ref).

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function VolumetricFlowResistor(;
    name,
    k::Union{Real,Function},
    klow::Real=0.0,
    density::Union{Real,Function,Nothing}=nothing,
    liquid::AbstractLiquid=H2O,
    scale::Real=1.0,
)
    pars = @parameters klow = klow scale = scale
    if k isa Real
        kpars = @parameters k = k
        k_expr = kpars[1]
    else  # Function / callable — MTK callable-parameter pattern (time-varying resistance)
        FType = typeof(k)
        kpars = @parameters (k_fn::FType)(..)
        k_expr = kpars[1](t)
    end
    pars = Any[pars...; kpars...]
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    rho = if density isa Real
        Num(density)
    elseif density isa Function
        density(T_in)
    else
        ρ(liquid, T_in)
    end
    q = inlet.ṁ / rho
    eqs = Equation[inlet.p - outlet.p ~ scale * (k_expr * q * abs(q) + klow * q)]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    LocalPressureDrop(; name, A1, A2, liquid=H2O) -> System

Minor (local) pressure loss across a sudden area change `A1 -> A2`, after Idelchik tables
4.2 (expansion) and 4.10 (contraction). The loss is `ΔP = K·ṁ·|ṁ| / (2·ρ·A_min²)`,
where the coefficient `K` depends on the area ratio and Reynolds number and on the flow
direction — forward flow sees an expansion when `A2 ≥ A1` and a contraction otherwise, with
the roles swapped under reversal. The `ṁ·|ṁ|` form keeps the drop direction-correct.

# Arguments
- `name`: system name (Symbol)
- `A1`: upstream flow area [m^2]
- `A2`: downstream flow area [m^2]
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref), supplying the density and
  viscosity at the inlet stream temperature
- `scale`: multiplies the pressure drop, default 1.0. See [`Resistor`](@ref).

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function LocalPressureDrop(; name, A1, A2, liquid::AbstractLiquid=H2O, scale::Real=1.0)
    pars = @parameters scale = scale
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    A = min(A1, A2)
    f = _local_loss_factor(inlet.ṁ, A1, A2, μ(liquid, T_in))
    rho = ρ(liquid, T_in)
    Δp₋ = inlet.p - outlet.p
    eqs = Equation[Δp₋ ~ scale * local_dp(inlet.ṁ, rho, f, A)]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    FrictionResistor(; name, geometry, darcy=Blasius(), liquid=H2O) -> System

Frictional pressure drop element, `ΔP = f · ṁ|ṁ| / (2ρA²) · (L/Dh)`.

The friction factor comes from `darcy`, a [`AbstractDarcyFactor`](@ref). Passing
[`RegimeDependent`](@ref) makes this the regime-switching friction resistor, with the
laminar/turbulent blend and, if asked for, the heated-wall viscosity correction.

# Arguments
- `name`: system name (Symbol)
- `geometry`: pipe geometry descriptor ([`PipeGeometry`](@ref))
- `darcy`: wall friction model ([`AbstractDarcyFactor`](@ref)), default [`Blasius`](@ref)
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function FrictionResistor(;
    name,
    geometry::PipeGeometry,
    darcy::AbstractDarcyFactor=Blasius(),
    liquid::AbstractLiquid=H2O,
)
    geom = geometry
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
        f ~ darcy(T_in, inlet.ṁ, liquid, geom),
        inlet.p - outlet.p ~ darcy_weisbach_dp(inlet.ṁ, ρ(liquid, T_in), f, Lx, Dh, Ax),
    ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars)
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

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Resistor(R; name)
    pars = @parameters R = R
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    eqs = Equation[inlet.p - outlet.p ~ R * inlet.ṁ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    VolumetricFlowResistor(; name, k, klow=0.0, density=(T -> ρ(H2O, T))) -> System

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
- `density`: the density [kg/m^3] used to turn mass flow into volumetric flow; `Real` for a
  constant, or `Function` `(T) -> rho` evaluated at the inlet stream temperature. Defaults to
  light water at the inlet temperature.

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function VolumetricFlowResistor(;
    name,
    k::Union{Real,Function},
    klow::Real=0.0,
    density::Union{Real,Function}=(T -> ρ(H2O, T)),
)
    pars = @parameters klow = klow
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
    else
        density(T_in)
    end
    q = inlet.ṁ / rho
    eqs = Equation[inlet.p - outlet.p ~ (k_expr * q * abs(q) + klow * q)]
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

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function LocalPressureDrop(; name, A1, A2, liquid::AbstractLiquid=H2O)
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    A = min(A1, A2)
    f = LocalLoss.factor(inlet.ṁ, A1, A2, μ(liquid, T_in))
    eqs = Equation[inlet.p - outlet.p ~ dp(inlet.ṁ, ρ(liquid, T_in), f, A)]
    return HydraulicTwoPort(; name, inlet, outlet, eqs)
end

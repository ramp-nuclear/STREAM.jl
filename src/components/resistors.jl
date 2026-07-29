# resistors.jl -- Friction, Gravity, Resistor components

"""
    Friction(; name, L, D, A) -> System

Frictional pressure drop element using Darcy-Weisbach correlation.

# Arguments
- `name`: system name (Symbol)
- `L`: pipe length [m]
- `D`: hydraulic diameter [m]
- `A`: flow area [m^2]

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Friction(; name, L, D, A)
    pars = @parameters begin
        L = L
        A = A
    end
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    re = STREAM.Re(inlet.ṁ, A, D, mu_water(T_in))
    eqs = Equation[
        Re ~ re,
        f ~ blasius_friction(Re),
        inlet.p - outlet.p ~ f * (inlet.ṁ * abs(inlet.ṁ) / (2 * rho_water(
            T_in
        ) * A^2)) * (L / D),
    ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars)
end

"""
    Gravity(H; name) -> System

Hydrostatic pressure change for a vertical elevation change.

# Arguments
- `H`: elevation change [m], positive = upward
- `g`: gravitational acceleration
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function Gravity(H, g=G_EARTH; name)
    pars = @parameters H = H
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    eqs = Equation[inlet.p - outlet.p ~ rho_water(T_in) * g * H]
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
    eqs = Equation[inlet.p - outlet.p ~ R * inlet.ṁ]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    VolumetricFlowResistor(; name, k, klow=0.0, density=rho_water) -> System

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
- `density`: coolant density [kg/m^3]; `Real` (constant) or `Function` `(T) -> ρ`
  (default `rho_water`, evaluated at the inlet stream temperature)

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function VolumetricFlowResistor(;
    name,
    k::Union{Real,Function},
    klow::Real=0.0,
    density::Union{Real,Function}=rho_water,
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
    rho = density isa Real ? Num(density) : density(T_in)
    q = inlet.ṁ / rho
    eqs = Equation[inlet.p - outlet.p ~ k_expr * q * abs(q) + klow * q]
    return HydraulicTwoPort(; name, inlet, outlet, eqs, pars=pars)
end

"""
    LocalPressureDrop(; name, A1, A2, fluid=Water()) -> System

Minor (local) pressure loss across a sudden area change `A1 -> A2`, after Idelchik tables
4.2 (expansion) and 4.10 (contraction). The loss is `ΔP = K·ṁ·|ṁ| / (2·ρ·A_min²)`,
where the coefficient `K` depends on the area ratio and Reynolds number and on the flow
direction — forward flow sees an expansion when `A2 ≥ A1` and a contraction otherwise, with
the roles swapped under reversal. The `ṁ·|ṁ|` form keeps the drop direction-correct.

# Arguments
- `name`: system name (Symbol)
- `A1`: upstream flow area [m^2]
- `A2`: downstream flow area [m^2]
- `fluid`: coolant property set (`AbstractFluid`), default `Water()` — supplies density and
  viscosity at the inlet stream temperature

# Ports
- `inlet`, `outlet` -- `FlowPort` (pressure, mass flow, temperature)
"""
function LocalPressureDrop(; name, A1, A2, fluid::AbstractFluid=Water())
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    T_in = instream(inlet.T)
    A = min(A1, A2)
    f = _local_loss_factor(inlet.ṁ, A1, A2, viscosity(fluid, T_in))
    ρ = density(fluid, T_in)
    Δp₋ = inlet.p - outlet.p
    eqs = Equation[Δp₋ ~ f * inlet.ṁ * abs(inlet.ṁ) / (2ρ * A^2)]
    return HydraulicTwoPort(; name, inlet, outlet, eqs)
end

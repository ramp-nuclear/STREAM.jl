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
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
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
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        Re ~ abs(port_in.mdot) * D / (A * mu_water(T_in)),
        f ~ 0.3164 * Re^(-0.25),
        port_in.P - port_out.P ~ f * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(
            T_in
        ) * A^2)) * (L / D),
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
end

"""
    Gravity(H; name) -> System

Hydrostatic pressure change for a vertical elevation change.

# Arguments
- `H`: elevation change [m], positive = upward
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function Gravity(H; name)
    pars = @parameters H = H
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    Resistor(R; name) -> System

Generic flow resistance with a fixed resistance coefficient.

# Arguments
- `R`: resistance coefficient [Pa/(kg/s)]
- `name`: system name (Symbol)

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function Resistor(R; name)
    pars = @parameters R = R
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ R * port_in.mdot,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    VolumetricFlowResistor(; name, k, klow=0.0, density=rho_water) -> System

Resistor quadratic in volumetric flow: `ΔP = k·Q·|Q| + klow·Q`, where `Q = mdot/ρ` is the
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
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function VolumetricFlowResistor(;
    name,
    k::Union{Real,Function},
    klow::Real=0.0,
    density::Union{Real,Function}=rho_water,
)
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    rho = density isa Real ? Num(density) : density(T_in)
    q = port_in.mdot / rho

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

    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ k_expr * q * abs(q) + klow * q,
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

"""
    LocalPressureDrop(; name, A1, A2, fluid=Water()) -> System

Minor (local) pressure loss across a sudden area change `A1 -> A2`, after Idelchik tables
4.2 (expansion) and 4.10 (contraction). The loss is `ΔP = K·mdot·|mdot| / (2·ρ·A_min²)`,
where the coefficient `K` depends on the area ratio and Reynolds number and on the flow
direction — forward flow sees an expansion when `A2 ≥ A1` and a contraction otherwise, with
the roles swapped under reversal. The `mdot·|mdot|` form keeps the drop direction-correct.

# Arguments
- `name`: system name (Symbol)
- `A1`: upstream flow area [m^2]
- `A2`: downstream flow area [m^2]
- `fluid`: coolant property set (`AbstractFluid`), default `Water()` — supplies density and
  viscosity at the inlet stream temperature

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. Call `mtkcompile(sys)` before solving.
"""
function LocalPressureDrop(; name, A1, A2, fluid::AbstractFluid=Water())
    @named port_in = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    A = min(A1, A2)
    f = _local_loss_factor(port_in.mdot, A1, A2, viscosity(fluid, T_in))
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ f * port_in.mdot * abs(port_in.mdot) / (2 * density(fluid, T_in) * A^2),
        port_out.T ~ instream(port_in.T),
        port_in.T ~ instream(port_out.T),
    ]
    return compose(System(eqs, t, [], []; name=name), port_in, port_out)
end

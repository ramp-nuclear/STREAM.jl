"""
    Tank(; name, area, L0, ports, liquid=H2O, p_surface=ATM, T0=T_ROOM,
         fixed_temperature=false, volume=nothing, Q_ext=0.0, g=G_EARTH) -> System

A body of liquid with a free surface: a pool, or a tank with a cover gas. It holds an inventory
whose level `L` and mixed temperature `T` are states, and it sits in a loop as a node with any
number of connections, each at its own elevation.

Each connection's pressure is the surface pressure plus the head of liquid above it,

    port.p = p_surface + ρ(T)·g·(L − z)

so a leg's driving head falls as the tank drains, reaches zero when the surface comes down to
the connection, and goes negative once it is above the surface. Liquid leaves through every
port at the tank's temperature.

The level follows the net inflow, `ρ·A(L)·dL/dt = Σ ṁ`, with each port's `ṁ` positive into the
tank. The temperature follows the enthalpy the inflows bring,

    ρ·V(L)·cₚ·dT/dt = Σ max(ṁ, 0)·cₚ·(T_in − T) + Q_ext

Outflow leaves at `T`, so it adds nothing. A port's `instream` temperature is what arrives if
liquid flows in, whichever way it is flowing, so the balance picks the inflowing ports itself.

# The steady solve

A level is the integral of the net flow, so on its own a steady state leaves it undetermined.
While the parameter `pinned` is `true`, the default, the level is instead held at `L0`, which is
what a steady solve needs. Release it for the transient:

```julia
sol_ss = solve_steady(ssys, guess)
sol = solve_transient(ssys, sol_ss, times; overrides=[ssys.pool.pinned => false])
```

A pinned tank still sets a temperature from its inflows, so a tank that only drains has nothing
to set `T` in the steady solve. Give it `fixed_temperature=true`.

# Events

Reaching a level is a [`StateMachine`](@ref) transition on `L`, such as
`(:INTACT => :UNCOVERED, pool.L < z_core_top, "core uncovered")` with `:UNCOVERED` among the
machine's `abort_states` to stop the run there.

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `area`: free-surface area [m²], a number or a function of level. A function needs `volume`.
- `L0`: initial level, and the level held while pinned [m]
- `ports`: connection elevations [m], in the datum of `L`, as a `NamedTuple` such as
  `(suction=0.0, return=0.5)`. Each becomes a `FlowPort` of that name.
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref)
- `p_surface`: pressure above the liquid [Pa], a number or a function of time (default
  [`ATM`](@ref))
- `T0`: initial temperature, and the held temperature with `fixed_temperature` [°C]
- `fixed_temperature`: hold `T` at `T0` instead of following the energy balance (default
  `false`)
- `volume`: liquid volume as a function of level [m³]. Required with a level-dependent `area`;
  a constant area gives `area·L`.
- `Q_ext`: heat into the liquid from outside the loop [W] (default 0)
- `g`: gravitational acceleration [m/s²] (default [`G_EARTH`](@ref))

# Ports
One `FlowPort` per entry of `ports`, named as in it.

# Returns
Uncompiled `System` with the level `L`, the temperature `T`, the inventory `M = ρ·V(L)` [kg],
and the parameter `pinned`.

# Throws
- `ArgumentError`: for a level-dependent `area` with no `volume`, or no ports
"""
function Tank(; name, area, L0, ports::NamedTuple, liquid::AbstractLiquid=H2O, p_surface=ATM,
              T0=T_ROOM, fixed_temperature::Bool=false, volume=nothing, Q_ext=0.0,
              g=G_EARTH)
    isempty(ports) && throw(ArgumentError("a Tank needs at least one port"))
    area isa Function && volume === nothing && throw(ArgumentError(
        "a level-dependent area needs `volume`, the liquid volume as a function of level, " *
        "for the energy balance",
    ))
    A_of(L) = area isa Function ? area(L) : area
    V_of(L) = volume === nothing ? area * L : volume(L)
    # Numbers, not the parameters below: a state whose default names a parameter is bound
    # to it, and a transient that starts the state elsewhere then conflicts with the binding.
    L_start, T_start = Float64(L0), Float64(T0)

    pars = @parameters begin
        pinned::Bool = true
        L0 = L0
        T0 = T0
        Q_ext = Q_ext
    end
    p_s = if p_surface isa Real
        ps = @parameters p_surface = p_surface
        append!(pars, ps)
        ps[1]
    else
        FType = typeof(p_surface)
        ps = @parameters (p_surface_fn::FType)(..) = p_surface
        append!(pars, ps)
        ps[1](t)
    end
    vars = @variables L(t) = L_start T(t) = T_start M(t)

    port_sys = [FlowPort(; name=k) for k in keys(ports)]
    rho = ρ(liquid, T)
    net_inflow = sum(port.ṁ for port in port_sys)

    eqs = Equation[
        # Pinned, the steady condition is L = L0. The rate only matters to a transient run
        # with the tank still pinned, which holds the level there.
        D(L) ~ ifelse(pinned, (L0 - L) / _TANK_PIN_TIME, net_inflow / (rho * A_of(L))),
        M ~ rho * V_of(L),
    ]
    for (port, z) in zip(port_sys, values(ports))
        push!(eqs, port.p ~ p_s + rho * g * (L - z))
        push!(eqs, port.T ~ T)
    end
    if fixed_temperature
        push!(eqs, T ~ T0)
    else
        cp = cₚ(liquid, T)
        inflow_heat = sum(
            ifelse(port.ṁ > 0, port.ṁ, 0.0) * cp * (instream(port.T) - T) for port in port_sys
        )
        # Solved for D(T): left multiplying it, the T-dependent ρ·cₚ makes MTK carry D(T) as
        # an extra unknown that needs a start value.
        push!(eqs, D(T) ~ (inflow_heat + Q_ext) / (rho * V_of(L) * cp))
    end
    return compose(System(eqs, t, vars, pars; name=name), port_sys...)
end

"""
    _TANK_PIN_TIME

Time constant [s] with which a pinned [`Tank`](@ref) returns to `L0`. A steady solve only sees
that the level sits at `L0`; the value matters only to a transient run with the tank pinned.
"""
const _TANK_PIN_TIME = 1.0

"""
    Environment(; name, p=ATM, T=T_ROOM) -> System

The ambient a loop discharges into: a dead end held at a known pressure. Liquid leaving through
it is gone. Liquid drawn back in arrives at temperature `T`.

A break discharges into one of these through an [`Orifice`](@ref).

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `p`: ambient pressure [Pa] (default [`ATM`](@ref))
- `T`: temperature of anything drawn back in [°C] (default [`T_ROOM`](@ref))

# Ports
- `port`: `FlowPort`

# Returns
Uncompiled `System`.
"""
function Environment(; name, p=ATM, T=T_ROOM)
    pars = @parameters p_env = p T_env = T
    @named port = FlowPort()
    eqs = Equation[port.p ~ p_env, port.T ~ T_env]
    return compose(System(eqs, t, [], pars; name=name), port)
end

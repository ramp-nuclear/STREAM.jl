"""
    Tank(; name, area, L0, ports, liquid=H2O, p_surface=ATM, T0=T_ROOM,
         fixed_temperature=true, volume=nothing, Q_ext=0.0, g=G_EARTH) -> System

A body of liquid with a free surface: a pool, or a tank with a cover gas. It holds an inventory
whose level `L` is a state, and it sits in a loop as a node with any number of connections,
each at its own elevation.

Each connection's pressure is the surface pressure plus the head of liquid above it,

    port.p = p_surface + ρ(T)·g·(L − z)

so a leg's driving head falls as the tank drains, reaches zero when the surface comes down to
the connection, and goes negative once it is above the surface. Liquid leaves through every
port at the tank's temperature. A port the surface has fallen below keeps passing liquid
under that negative head: the tank does not shut it. To stop the flow there, put an
[`Orifice`](@ref) on the line with a transition that shuts it when `L` passes the port.

The level follows the net inflow, `ρ·A(L)·dL/dt = Σ ṁ`, with each port's `ṁ` positive into the
tank.

# Temperature

By default the temperature is held at `T0`, before and during the transient. The tank then
takes in whatever heat the loop brings it without warming, which suits a pool whose heat-up is
of no interest. With `fixed_temperature=false`, `T` follows the enthalpy the inflows bring,

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

[`solve_transient`](@ref) warns about a tank left pinned.

With the energy balance on, the steady temperature is the mix of the inflows, so a tank with
no inflow in the steady state has nothing to set it, and [`solve_steady`](@ref) throws. Start
such a run from the declared state instead,
`solve_transient(ssys, [ssys.pool.pinned => false], times)`.

# Events

Reaching a level is a [`StateMachine`](@ref) transition on `L`, such as
`(:INTACT => :CORE_UNCOVERED, pool.L < z_core_top, "core uncovered")` with `:CORE_UNCOVERED`
among the machine's `abort_states` to stop the run there.

# Arguments
- `name`: system name (Symbol), injected by `@named`
- `area`: free-surface area [m²], a number or a function of level `L -> A`. A function needs
  `volume`.
- `L0`: initial level, and the level held while pinned [m]
- `ports`: connection elevations [m], in the datum of `L`, as a `NamedTuple` such as
  `(suction=0.0, return=0.5)`. Each becomes a `FlowPort` of that name.
- `liquid`: coolant ([`AbstractLiquid`](@ref)), default [`H2O`](@ref)
- `p_surface`: pressure above the liquid [Pa] (default [`ATM`](@ref))
- `T0`: the held temperature, or the initial one with `fixed_temperature=false` [°C]
- `fixed_temperature`: hold `T` at `T0` (default `true`). `false` makes `T` follow the energy
  balance.
- `volume`: liquid volume as a function of level `L -> V` [m³], consistent with `area`
  (`dV/dL = A`). Required with a level-dependent `area`; a constant area gives `area·L`.
- `Q_ext`: heat into the liquid from outside the loop [W] (default 0). It only acts with
  `fixed_temperature=false`.
- `g`: gravitational acceleration [m/s²] (default [`G_EARTH`](@ref))

# Ports
One `FlowPort` per entry of `ports`, named as in it.

# Returns
Uncompiled `System` with the level `L`, the temperature `T`, the inventory `M = ρ·V(L)` [kg],
and the parameter `pinned`. With `fixed_temperature=false` it also has `inflow` [kg/s], the
sum of the flows coming in.

# Throws
- `ArgumentError`: for a tank with no ports, or a level-dependent `area` with no `volume`
"""
function Tank(; name, area, L0, ports::NamedTuple, liquid::AbstractLiquid=H2O, p_surface=ATM,
              T0=T_ROOM, fixed_temperature::Bool=true, volume=nothing, Q_ext=0.0,
              g=G_EARTH)
    isempty(ports) && throw(ArgumentError("a Tank needs at least one port"))
    area isa Function && volume === nothing && throw(ArgumentError(
        "a level-dependent area needs `volume`, the liquid volume as a function of level",
    ))
    # Numbers, not the parameters below: a state whose default names a parameter is bound
    # to it, and a transient that starts the state elsewhere then conflicts with the binding.
    L_start, T_start = Float64(L0), Float64(T0)

    pars = @parameters begin
        pinned::Bool = true
        L0 = L0
        T0 = T0
        p_surface = p_surface
        Q_ext = Q_ext
    end
    # A constant area is a parameter, so `remake` can change it; a function of level is
    # traced into the equations.
    A_of, V_of = if area isa Function
        area, volume
    else
        As = @parameters area = area
        append!(pars, As)
        (_ -> As[1]), (L -> As[1] * L)
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
        push!(eqs, port.p ~ p_surface + rho * g * (L - z))
        push!(eqs, port.T ~ T)
    end
    if fixed_temperature
        push!(eqs, T ~ T0)
    else
        cp = cₚ(liquid, T)
        inflow_heat = sum(
            ifelse(port.ṁ > 0, port.ṁ, 0.0) * cp * (instream(port.T) - T) for port in port_sys
        )
        inflow_vars = @variables inflow(t)
        append!(vars, inflow_vars)
        push!(eqs, inflow_vars[1] ~ sum(ifelse(port.ṁ > 0, port.ṁ, 0.0) for port in port_sys))
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

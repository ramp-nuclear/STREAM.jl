# A capacity rate below this counts as no flow. It keeps NTU = UA / C_min finite.
const _C_FLOOR = 1.0e-6   # [W/K]

@doc raw"""
    HeatExchanger(T_bc; UA=nothing, liquid=default_coolant(), name) -> System

A heat exchanger to a sink held at `T_bc`: the cooling a loop gets from something outside the
model, such as a cooling tower, a pond or the air.

With no `UA`, the default, the exchanger is ideal. Liquid leaves at `T_bc` whatever arrives,
in either flow direction, so the sink takes any heat the loop brings it.

With a `UA`, the sink is still at a fixed temperature but the exchange is finite. The
liquid's capacity rate ``C = |\dot m| c_p(T_{in})`` [W/K] is the heat it carries per kelvin
of temperature change. The sink's capacity rate is unbounded, since it stays at `T_bc`
however much heat it takes, so `C` is the smaller of the two and the effectiveness is
``1 - e^{-UA/C}``:

```math
T_{out} = T_{in} + (1 - e^{-UA / C}) (T_{bc} - T_{in})
```

As `UA` grows this tends to the ideal exchanger, `T_out = T_bc`. As the flow stops, `C` goes to zero and so does the heat removed, `Q = C (T_out - T_in)`.
Use the two-stream method to model the sink's own flow. Both forms have no pressure drop: put
a resistor in series for one. See [Heat exchangers and the heat sink](@ref).

# Arguments
- `T_bc`: sink temperature [°C], the parameter `T_bc`
- `UA`: overall conductance [W/K]. `nothing` gives the ideal exchanger. A number is held as
  the parameter `UA`. A function `(ṁ) -> UA` of the mass flow makes it the unknown `UA_eff`.
- `liquid`: the coolant, for its specific heat, default
  [`default_coolant()`](@ref STREAM.Substances.default_coolant); unused when ideal
- `name`: system name (Symbol)

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `System`. With a `UA` it has the observed `Q`, the heat the liquid takes up [W],
negative when the sink cools it.
"""
function HeatExchanger(T_bc; UA=nothing, liquid::AbstractLiquid=default_coolant(), name)
    pars = @parameters T_bc = T_bc
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    if UA === nothing
        eqs = Equation[
            inlet.ṁ + outlet.ṁ ~ 0,
            inlet.p - outlet.p ~ 0,
            outlet.T ~ T_bc,
            inlet.T ~ T_bc,
        ]
        return compose(System(eqs, t, [], pars; name=name), inlet, outlet)
    end
    vars = @variables T_in(t) C(t) ΔT(t) Q(t)
    UA_val, ua_pars, ua_vars, ua_eqs = _conductance(UA, inlet.ṁ)
    eqs = Equation[
        _side_equations(inlet, outlet, T_in, C, ΔT, liquid)...,
        ua_eqs...,
        ΔT ~ (1 - exp(-UA_val / max(C, _C_FLOOR))) * (T_bc - T_in),
        Q ~ C * ΔT,
    ]
    return compose(System(eqs, t, [vars..., ua_vars...], [pars..., ua_pars...]; name=name),
                   inlet, outlet)
end

@doc raw"""
    HeatExchanger(; UA, arrangement=HTC.Counterflow(), primary_liquid=default_coolant(),
                  secondary_liquid=default_coolant(), name) -> System

A heat exchanger between two flowing streams, the primary and the secondary, solved by the
effectiveness-NTU method. Each side is a two-port with no pressure drop, reached as
`hx.primary` and `hx.secondary`, so it sits in a loop like any other component:
`inseries(pump, hx.primary, core)`.

The exchanger stores no heat: the outlets follow the inlets at once. With capacity rates
``C = |\dot m| c_p(T_{in})`` on each side, the heat each stream carries per kelvin,

```math
Q = ε C_{min} (T_{s,in} - T_{p,in}), \qquad ε = ε(NTU, C_r), \quad NTU = UA / C_{min}, \quad C_r = C_{min} / C_{max}
```

where `Q` is the heat into the primary, and each outlet is its inlet plus `Q` over its own
capacity rate. [`HTC.effectiveness`](@ref STREAM.HTC.effectiveness) gives ε for the
arrangement. When exactly one side flows backwards, a counterflow unit runs as parallel flow and
the reverse, and the model switches formulas to match. A side that stops flowing has
``C \to 0``, so `Q` goes to zero: a loss of heat sink. See
[Heat exchangers and the heat sink](@ref).

# Arguments
- `UA`: overall conductance [W/K]. A number is held as the parameter `UA`, which `remake` can
  change. A function `(ṁp, ṁs) -> UA` of the two mass flows, such as
  [`HTC.flow_scaled_UA`](@ref STREAM.HTC.flow_scaled_UA), makes it the unknown `UA_eff`.
- `arrangement`: [`HTC.Counterflow()`](@ref STREAM.HTC.Counterflow) or
  [`HTC.ParallelFlow()`](@ref STREAM.HTC.ParallelFlow), for forward flow on both sides
- `primary_liquid`, `secondary_liquid`: the coolant on each side, default
  [`default_coolant()`](@ref STREAM.Substances.default_coolant)
- `name`: system name (Symbol)

# Ports
- `primary.inlet`, `primary.outlet`, `secondary.inlet`, `secondary.outlet`: `FlowPort`s

# Returns
Uncompiled `System`. The observed `Q` is the heat into the primary [W], negative when the
primary is the hot side. Each side has `T_in` (the temperature arriving, whichever way it
flows), `C` and `ΔT`, the rise from its inlet to its outlet.
"""
function HeatExchanger(; UA, arrangement::HTC.AbstractArrangement=HTC.Counterflow(),
                       primary_liquid::AbstractLiquid=default_coolant(),
                       secondary_liquid::AbstractLiquid=default_coolant(), name)
    primary = _ExchangerSide(; liquid=primary_liquid, name=:primary)
    secondary = _ExchangerSide(; liquid=secondary_liquid, name=:secondary)
    vars = @variables Q(t)
    ṁp, ṁs = primary.inlet.ṁ, secondary.inlet.ṁ
    UA_val, ua_pars, ua_vars, ua_eqs = _conductance(UA, ṁp, ṁs)

    Cp, Cs = primary.C, secondary.C
    C_min = max(min(Cp, Cs), _C_FLOOR)
    C_max = max(max(Cp, Cs), _C_FLOOR)
    NTU, Cr = UA_val / C_min, C_min / C_max
    ε = ifelse(ṁp * ṁs >= 0,
               HTC.effectiveness(arrangement, NTU, Cr),
               HTC.effectiveness(HTC._reversed(arrangement), NTU, Cr))
    dT = secondary.T_in - primary.T_in
    eqs = Equation[
        ua_eqs...,
        Q ~ ε * C_min * dT,
        # Q / C on each side, written so that nothing divides by a flow that can be zero
        primary.ΔT ~ ε * C_min / max(Cp, _C_FLOOR) * dT,
        secondary.ΔT ~ -ε * C_min / max(Cs, _C_FLOOR) * dT,
    ]
    sys = System(eqs, t, [vars..., ua_vars...], ua_pars; name=name)
    return compose(sys, primary, secondary)
end

"""
    _ExchangerSide(; liquid, name) -> System

One side of the two-stream [`HeatExchanger`](@ref): a two-port that passes its flow through
with no pressure drop and raises its temperature by the unknown `ΔT`, which the exchanger sets.
"""
function _ExchangerSide(; liquid, name)
    @named inlet = FlowPort()
    @named outlet = FlowPort()
    vars = @variables T_in(t) C(t) ΔT(t)
    eqs = _side_equations(inlet, outlet, vars..., liquid)
    return compose(System(eqs, t, collect(vars), []; name=name), inlet, outlet)
end

@doc raw"""
    _side_equations(inlet, outlet, T_in, C, ΔT, liquid) -> Vector{Equation}

The equations of one stream through a heat exchanger. Mass passes through, pressure is
unchanged, `T_in` is the temperature arriving in the current flow direction,
``C = |\dot m| c_p(T_{in})``, and the liquid leaves `ΔT` warmer than it arrived. As in
[`HydraulicTwoPort`](@ref), both directions are written and `instream` picks the live one.
"""
function _side_equations(inlet, outlet, T_in, C, ΔT, liquid)
    return Equation[
        inlet.ṁ + outlet.ṁ ~ 0,
        inlet.p ~ outlet.p,
        T_in ~ ifelse(inlet.ṁ >= 0, instream(inlet.T), instream(outlet.T)),
        C ~ abs(inlet.ṁ) * cₚ(liquid, T_in),
        outlet.T ~ instream(inlet.T) + ΔT,
        inlet.T ~ instream(outlet.T) + ΔT,
    ]
end

"""
    _conductance(UA, ṁ...) -> (value, pars, vars, eqs)

The overall conductance of a [`HeatExchanger`](@ref) and what it adds to the system. A number
becomes the parameter `UA`. A function of the mass flows becomes the unknown `UA_eff` with the
equation `UA_eff ~ UA(ṁ...)`.
"""
function _conductance(UA::Real, ṁ...)
    pars = @parameters UA = UA
    return UA, pars, [], Equation[]
end

function _conductance(UA::Function, ṁ...)
    vars = @variables UA_eff(t)
    return UA_eff, [], vars, Equation[UA_eff ~ UA(ṁ...)]
end

"""
    ConvectiveBoundary(; name, area) -> System

One-way convective heat sink at a single wall cell: imposes
`thermal.Q ~ h * area * (thermal.T - T_fluid)`. The conductance `h` and fluid
temperature `T_fluid` are unbound input variables — supply them with binding equations
to a channel's live `h_tc[i]` and coolant `T[i]`. The heat absorbed leaves through this
element and is never returned to whatever supplies `h`/`T_fluid`, so the coupling is
one-way.

This is the far-face element of `single_channel`: it cools a fuel plate's
unconnected face using an adjacent channel's conditions without modelling a second
channel (the equivalent-twin reduction). Used per axial cell; not a standalone loop
component.

# Arguments
- `name`: system name (Symbol; supplied by `@named`).
- `area`: heat-transfer area for the cell [m^2], e.g. `heated_parts[side] * dz`.

# Ports
- `thermal` -- `ThermalPort`; connect to the fuel cell's far-face port.

# Input variables (bind externally)
- `h(t)`: convective conductance [W/(m^2·K)].
- `T_fluid(t)`: bulk fluid temperature [°C].
"""
function ConvectiveBoundary(; name, area)
    pars = @parameters area = area
    @named thermal = ThermalPort()
    vars = @variables h(t) T_fluid(t)
    eqs = Equation[thermal.Q ~ h * area * (thermal.T - T_fluid)]
    return compose(System(eqs, t, collect(vars), pars; name=name), thermal)
end

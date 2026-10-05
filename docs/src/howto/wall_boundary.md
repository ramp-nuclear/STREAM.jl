# Bind a wall temperature or heat flux

A [`Channel`](@ref STREAM.Components.Channel) is heated through its walls, and leaves their
temperatures for you to set. A [`ChannelHeatFlux`](@ref STREAM.Components.ChannelHeatFlux)
leaves the heat flux instead. Either way the value is an equation in the connection list.

```@example wall
using STREAM
using STREAM.Components: Pump, HeatExchanger, Channel, ChannelHeatFlux
using STREAM.Assemblies: inseries
using STREAM.Utilities: cosine_T_wall_profile
using ModelingToolkit: @named, mtkcompile, @parameters, t_nounits as t

n = 10
geometry = PipeGeometry_circular(0.6, 0.01)
nothing # hide
```

## A fixed temperature, uniform or per cell

Broadcast the equation over the cells with `.~`. The right side is a number, a vector of
length `n`, or any expression:

```@example wall
@named pump = Pump(3.0e4)
@named hx = HeatExchanger(40.0)
@named ch = Channel(; n, geometry, h_left=5000.0)
T_profile = 60.0 .+ 40.0 .* cosine_T_wall_profile(n)    # 60 °C at the ends, 100 °C mid
connections = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.T_wall_left .~ T_profile,
]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)
sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5])
sol[sys.ch.T_out]
```

Only a face with a nonzero heat transfer coefficient needs its wall bound. Here `h_right` is
left at 0, so the right wall appears in no equation and needs nothing. A friction model that
reads the wall temperature, such as [`Friction.RegimeDependent`](@ref) with a viscosity
correction, needs both walls bound, whatever the coefficients.

## A temperature you can change without recompiling

Bind the wall to a parameter. Its value then goes in the operating point of each solve:

```@example wall
@parameters T_wall = 100.0
@named pump = Pump(3.0e4)
@named hx = HeatExchanger(40.0)
@named ch = Channel(; n, geometry, h_left=5000.0)
connections = [inseries(pump, hx, ch, pump), pump.inlet.p ~ 1.0e5, ch.T_wall_left .~ T_wall]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)
[round(solve_steady(sys, [sys.ch.inlet.ṁ => 0.5, T_wall => Tw])[sys.ch.T_out]; digits=2)
 for Tw in (80.0, 100.0, 120.0)]
```

## A temperature that changes in time

The right side can be any expression in the time variable `t`, here a wall heating up from
60 °C towards 100 °C with a 10 s time constant:

```@example wall
@named pump = Pump(3.0e4)
@named hx = HeatExchanger(40.0)
@named ch = Channel(; n, geometry, h_left=5000.0)
connections = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.T_wall_left .~ 60.0 + 40.0 * (1 - exp(-t / 10)),
]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)
sol = solve_transient(sys, [sys.ch.inlet.ṁ => 0.6, sys.ch.T => fill(40.0, n)], 0.0:1.0:60.0)
sol[sys.ch.T_out, end]
```

For a temperature read from data, interpolate it into a function and use that function the
same way, or see [Drive an input from a function of time](time_inputs.md).

## A heat flux instead of a temperature

`ChannelHeatFlux` takes the flux of each face per cell, in W/m², as `q_left` and `q_right`.
Bind both, even a face with no heated perimeter, whose flux multiplies zero:

```@example wall
@named pump = Pump(3.0e4)
@named hx = HeatExchanger(40.0)
@named ch = ChannelHeatFlux(; n, geometry)
connections = [
    inseries(pump, hx, ch, pump),
    pump.inlet.p ~ 1.0e5,
    ch.q_left .~ 2.0e5,
    ch.q_right .~ 0.0,
]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)
sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5])
sol[sys.ch.T_out]
```

A `ChannelHeatFlux` has no wall temperature, so the threshold analysis, which needs one,
does not apply to it. To check limits, use a [`Channel`](@ref STREAM.Components.Channel) or a
[`ChannelAndContacts`](@ref STREAM.Components.ChannelAndContacts).

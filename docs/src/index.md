# STREAM.jl

STREAM.jl simulates the cooling systems of research reactors: pumps, pipes, valves, coolant
channels, fuel plates, and the reactor kinetics that set the power. You build a model out of
components, connect them as the plant is connected, and solve it for a steady state or a
transient. Afterwards you check the solution against the thermal-hydraulic safety limits:
onset of boiling, flow instability and critical heat flux.

It is a Julia port of the Python STREAM package and is checked against it. Models are written
with [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/), which compiles the
equations symbolically before handing them to a numerical solver.

## Installation

STREAM.jl needs Julia 1.12 or later.

```julia
using Pkg
Pkg.add(url="https://github.com/ramp-nuclear/STREAM.jl")
```

## A first model

A pump pushes water through a heat exchanger, which sets the water temperature to 40 °C, and
then through a heated pipe whose wall is held at 100 °C:

```@example index
using STREAM
using STREAM.Components: Pump, HeatExchanger, Channel
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile

@named pump = Pump(3.0e4)                 # pressure rise [Pa]
@named hx = HeatExchanger(40.0)           # outlet temperature [°C]
@named ch = Channel(; n=10, geometry=PipeGeometry_circular(0.6, 0.01), h_left=5000.0)

connections = [
    inseries(pump, hx, ch, pump),         # a closed loop
    pump.inlet.p ~ 1.0e5,                 # one absolute pressure fixes the level [Pa]
    ch.T_wall_left .~ 100.0,              # wall temperature [°C]
]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)

sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5])
(ṁ=sol[sys.ch.inlet.ṁ], T_out=sol[sys.ch.T_out])
```

The flow (kg/s) is where the pump head balances the pipe's friction, and the outlet
temperature is where the heat taken from the wall balances what the flow carries away.
[First loop](tutorials/01_first_loop.md) walks through the same model step by step.

## Where to look

The documentation has four parts, each written for a different need:

| You want to | Read |
|:---|:---|
| learn the package from scratch | the [Tutorials](tutorials/index.md), in order |
| get a specific job done | the [How-to guides](howto/index.md) |
| understand the physics and the choices behind it | the [Explanation](explanation/index.md) pages |
| look up a function, its arguments and units | the [Reference](reference/index.md) |

## Conventions

These hold on every page:

- **Units** are SI, except temperatures, which are in °C everywhere: arguments, connector
  variables and solution values. Per-degree units such as J/(kg·K) are unaffected, since a
  degree Celsius and a kelvin are the same size. Pressures are absolute, in Pa.
- **Mass flow** ``\dot m`` is positive from a component's `inlet` to its `outlet`. A negative
  value is reversed flow, which every component handles.
- **Gravity** on a channel is the signed acceleration `g` along its flow direction:
  ``g = -g_0`` for a channel whose inlet is at the top (downward flow is helped by gravity),
  ``g = +g_0`` for one whose inlet is at the bottom, and ``0`` for a horizontal one.

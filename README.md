[![CI](https://github.com/ramp-nuclear/STREAM.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ramp-nuclear/STREAM.jl/actions/workflows/ci.yml) [![Docs](https://img.shields.io/badge/docs-dev-blue.svg)](https://ramp-nuclear.github.io/STREAM.jl/dev/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# STREAM.jl

Thermal-hydraulics and reactor kinetics for research reactor cooling systems, in Julia.

STREAM.jl builds a model of a cooling system out of components (pumps, pipes, valves, coolant
channels, fuel plates, point kinetics) connected as the plant is, and solves it for a steady
state or a transient: a pump trip, a reactivity insertion, a loss of flow into natural
circulation. It then checks the solution against the thermal-hydraulic limits: onset of
boiling, flow instability and critical heat flux.

It is a Julia port of [Python STREAM](https://github.com/ramp-nuclear/STREAM), checked against
it, and built on [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/).

**[Read the documentation](https://ramp-nuclear.github.io/STREAM.jl/dev/)**: tutorials,
how-to guides, the physics behind the models, and the API reference.

## Installation

STREAM.jl needs Julia 1.12 or later.

```julia
using Pkg
Pkg.add(url="https://github.com/ramp-nuclear/STREAM.jl")
```

## A first model

A pump pushes water through a heat exchanger, which sets it to 40 °C, and then through a pipe
whose wall is held at 100 °C:

```julia
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
sol[sys.ch.inlet.ṁ], sol[sys.ch.T_out]    # about 0.6 kg/s, leaving at about 42 °C
```

[A first loop](https://ramp-nuclear.github.io/STREAM.jl/dev/tutorials/01_first_loop/) walks
through it step by step.

## Development

```bash
julia --project=. test/runtests.jl                          # the test suite
julia --project=docs docs/make.jl                           # the documentation
```

`VALIDATION.md` tracks the comparison with Python STREAM, and `GAPS.md` what STREAM.jl does not
have yet.

## License

MIT. See [LICENSE](LICENSE).

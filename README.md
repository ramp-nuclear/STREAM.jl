[![CI](https://github.com/ramp-nuclear/STREAM.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/ramp-nuclear/STREAM.jl/actions/workflows/ci.yml) [![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](https://ramp-nuclear.github.io/STREAM.jl/stable/) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# STREAM.jl

Thermal-hydraulics and reactor kinetics for research reactor cooling systems, in Julia.

STREAM.jl builds a model of a cooling system out of components (pumps, pipes, valves, coolant
channels, fuel plates, point kinetics) connected as the plant is, and solves it for a steady
state or a transient: a pump trip, a reactivity insertion, a loss of flow into natural
circulation. It then checks the solution against the thermal-hydraulic limits: onset of
boiling, flow instability and critical heat flux.

It is a Julia port of [Python STREAM](https://github.com/ramp-nuclear/STREAM), checked against
it, and built on [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/).

**[Read the documentation](https://ramp-nuclear.github.io/STREAM.jl/stable/)**: tutorials,
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

[A first loop](https://ramp-nuclear.github.io/STREAM.jl/stable/tutorials/01_first_loop/) walks
through it step by step.

## Development

Clone the repository and install what it depends on:

```bash
git clone https://github.com/ramp-nuclear/STREAM.jl
cd STREAM.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

Loading STREAM takes about a minute in a fresh session, and the first `mtkcompile` of a model
adds a little more. Later calls in the same session are fast, so work in one REPL rather
than rerunning scripts, with [Revise](https://timholy.github.io/Revise.jl/stable/) to pick up
changes to `src/` without restarting.

### Where things are

The package is a stack of submodules, each using only the ones below it:

| Module | Holds |
|:--|:--|
| `Substances` | coolant properties (light and heavy water) and solid materials |
| `HTC`, `Friction`, `LocalLoss` | wall heat transfer, wall friction, and local pressure losses |
| `Thresholds` | the thermal-hydraulic limits: boiling onset, flow instability, critical heat flux |
| `Components` | pumps, valves, pipes, tanks, coolant channels, fuel, point kinetics, state machines |
| `DecayHeat` | decay heat after shutdown |
| `Assemblies` | wiring components together: `inseries`, `inparallel`, fuel assemblies |

`src/STREAM.jl` declares them and everything they export, and the
[reference](https://ramp-nuclear.github.io/STREAM.jl/stable/reference/) lists each one. Code
style is in `JULIA.md`. `VALIDATION.md` tracks the comparison with Python STREAM, and
`GAPS.md` what STREAM.jl does not have yet.

### Tests

Each source file has a test file of the same name, so `src/components/tank.jl` is tested in
`test/test_tank.jl`. Run one file while you work, and the whole suite before a pull request:

```bash
julia --project=. test/test_tank.jl       # one file
julia --project=. test/runtests.jl        # everything, about twenty minutes
```

Short examples in docstrings are doctests, checked by `test/test_doctests.jl`.

### Documentation

The site lives in `docs/`: tutorials as runnable scripts in `docs/literate/`, and the how-to
guides, explanation pages and reference in `docs/src/`. Building it runs every example, so a
tutorial whose numbers go wrong fails the build.

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'   # once
julia --project=docs docs/make.jl                         # full build, several minutes
DRAFT=1 julia --project=docs docs/make.jl                 # skip running code, for prose
python3 -m http.server -d docs/build 8000                 # view at localhost:8000
```

### Pull requests

Open a pull request into `main`. CI runs the tests and builds the documentation, and both
must pass. Pull requests are squash-merged, so the pull request's title and description
become the commit on `main`.

## License

MIT. See [LICENSE](LICENSE).

[![CI](https://github.com/itaybnv/STREAM.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/itaybnv/STREAM.jl/actions/workflows/ci.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

# STREAM.jl

A Julia library for thermal-hydraulics simulation of research reactor cooling systems, built on ModelingToolkit.jl.

## What STREAM.jl Models

STREAM.jl models pressurized light-water research reactor cooling loops under forced convection, natural convection, and flow reversal conditions. Given a loop topology (pump, channels, heat sources), it builds and solves the governing thermal-hydraulics equations: energy balance along each coolant channel, Dittus-Boelter heat transfer, Darcy-Weisbach friction with Blasius/Colebrook-White factors, and hydrostatic pressure contributions from vertical legs.

Beyond steady-state operation, STREAM.jl supports transient analysis: pump trip, loss-of-flow with Flapper check-valve opening, and natural circulation establishment. Each scenario is formulated as a differential-algebraic system — the same model that converges to steady-state under Newton iteration runs as a transient under Sundials IDA without modification.

For MTR (Materials Testing Reactor) plate-fuel assemblies, STREAM.jl includes a 2D finite-difference fuel plate (`HeatDiffusion`) that couples to coolant channels on both sides via `ThermalPort` arrays. Coupled to `PointKinetics` — a six-group delayed-neutron reactor kinetics model with temperature feedback — the library covers the full plate-fuel safety analysis workflow: heat generation, heat diffusion, coolant heating, subcooled boiling onset, and SCRAM transients. The underlying engine is Julia's ModelingToolkit.jl, which compiles the equation system symbolically before solving it numerically.

## Quick Start

### Installation

```bash
# Install Julia 1.10+ from https://julialang.org/downloads/
# Clone and activate:
git clone https://github.com/itaybnv/STREAM.jl
cd STREAM.jl
julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

### Steady-State Loop

```julia
using STREAM
using DifferentialEquations

# Build a simple forced-convection loop
# Pump -> HeatExchanger (T_inlet reset) -> Channel -> back to Pump
ssys = build_loop(
    T_inlet = 313.15,   # K (40 C) coolant inlet
    T_wall  = 373.15,   # K (100 C) wall temperature
    dP_pump = 3.0e4,    # Pa pump pressure rise
)

# Steady-state initial guess and solve
op  = [ssys.ch.port_in.mdot => 0.490]
sol = solve_steady(ssys, op)

println("T_outlet = ", round(sol[ssys.ch.T_out] - 273.15, digits=2), " C")
println("mdot     = ", round(abs(sol[ssys.ch.port_in.mdot]), digits=4), " kg/s")
# T_outlet ~= 54.6 C  (validated against Python STREAM)
```

## Component Catalog

| Component | Models | Key Parameters |
|-----------|--------|----------------|
| `Channel` | Single-phase coolant channel with axial FD discretization | `n` (cells), `geometry` (PipeGeometry), `g` (gravity) |
| `Pump` | Pressure-rise source; supports callable `dP(t)` for pump trips | `dP_pump` or `mdot_pump` |
| `HeatDiffusion` | 2D finite-difference solid fuel plate with lateral and axial conduction | `nz`, `nx`, `power_shape`, `k_s`, `rho_s`, `cp_s` |
| `PointKinetics` | Six-group delayed-neutron reactor kinetics with SCRAM support | `beta_k`, `lambda_k`, callable `rho_c_fn` |
| `ChannelAndContacts` | Coolant channel with bilateral `ThermalPort` arrays for plate coupling | `n`, `geometry` |
| `HeatExchanger` | Constant-temperature heat sink (sets coolant inlet temperature) | `T_bc` |

Full API reference is available via Julia's built-in help system: `?Channel`, `?build_loop`, etc.

## Validation

STREAM.jl results are validated within 1% of Python STREAM across three benchmark categories:

- **Steady-state** — T_outlet and mass flow rate in forced-convection loops (see `test/test_validation.jl` VAL-01)
- **Transient** — Outlet temperature response to wall temperature steps (VAL-02)
- **Point kinetics** — Prompt-jump power response and reactivity insertion scenarios (Phase 47/48 validation)
- **HeatDiffusion** — 1D Fourier series validation of axial plate temperature decay (VAL-01 Fourier)

## Installation

```julia
# From the Julia REPL:
using Pkg
Pkg.develop(path="/path/to/STREAM.jl")

# Or clone and use directly:
# git clone https://github.com/itaybnv/STREAM.jl
# cd STREAM.jl
# julia --project=. -e 'using Pkg; Pkg.instantiate()'
```

## Examples

- `examples/simple_loop.jl` — Minimal forced-convection loop: build, solve, plot T_out
- `examples/mtr_assembly.jl` — HeatDiffusion + ChannelAndContacts thermal coupling (MTR plate-fuel)
- `examples/lof_transient.jl` — Loss-of-flow transient: pump trip, flapper event, natural circulation establishment

Run with: `julia --project=. examples/simple_loop.jl`

## Relationship to Python STREAM

STREAM.jl is a Julia reimplementation of the Python STREAM thermal-hydraulics library, an internal research tool developed for nuclear safety analysis of plate-fuel research reactors.

The motivation for a Julia reimplementation was architectural: Python STREAM uses a manually assembled ODE system (Aggregator pattern) that becomes unwieldy as the model grows. Julia's ModelingToolkit.jl enables symbolic-numeric DAE compilation, automatic Jacobian sparsity detection, and equation-level composition via `connect()`/`compose()` — making it practical to model full MTR assemblies (hundreds of equations) without hand-coding the system matrix. The sparser Jacobian from symbolic analysis also improves solver convergence for stiff transients.

The physics models match Python STREAM exactly: Dittus-Boelter heat transfer coefficient, Blasius friction factor, MTR rectangular plate-channel geometry with correct hydraulic diameter (Dh = 4A/wet_perimeter), six-group delayed-neutron point kinetics with U-235 parameters, and Bergles-Rohsenow subcooled boiling onset.

Validation shows less than 1% deviation from Python STREAM across all benchmark cases (steady-state loop, wall temperature step transient, prompt-jump point kinetics). Python STREAM is an internal tool; STREAM.jl is the open-source implementation.

## License

MIT License — see [LICENSE](LICENSE) for details.

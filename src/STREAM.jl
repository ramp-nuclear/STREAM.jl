"""
    STREAM

Thermal-hydraulic and neutronic modelling for research reactors, built on
ModelingToolkit. A model is assembled from acausal components, compiled with
`mtkcompile`, and solved through [`solve_steady`](@ref) or [`solve_transient`](@ref).

# The submodule stack

Each submodule reaches only downward, so the dependency order is also the reading order:

```
Substances -> Dimensionless -> {HTC, Friction, LocalLoss, Thresholds}
           -> Components -> Assemblies -> {Solvers, Examples}
```

| Module | What lives there |
|:---|:---|
| [`Substances`](@ref) | coolants and their property correlations |
| [`HTC`](@ref) | wall heat transfer models and Nusselt correlations |
| [`Friction`](@ref) | Darcy friction factor models and correlations |
| [`LocalLoss`](@ref) | Idelchik minor losses for sudden area changes |
| [`Thresholds`](@ref) | safety limits and the post-solve analysis that applies them |
| [`Components`](@ref) | the MTK components a model is built from |
| [`Assemblies`](@ref) | wiring verbs and named arrangements of components |
| [`Utilities`](@ref) | grid resampling and axial profile helpers |
| `Examples` | worked builders, compiled with the package but never exported |

# Units

We use SI units everywhere, but for temperetures we use Celsius.
"""
module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using QuadGK
using SteadyStateDiffEq

include("constants.jl")

"""
    STREAM.Substances

Coolants and the property correlations behind them.

A coolant is a singleton type such as `LightWater` (aliased [`H2O`](@ref)) answering nine
property queries. Components take one as a keyword argument, so swapping coolants is a matter of
passing a different value. [`Liquid`](@ref) holds fixed property values and is itself an
`AbstractLiquid`, for a coolant frozen at one state point.

Each property has an alias naming the same function, so `ρ === density`.

A new coolant implements the nine [`AbstractLiquid`](@ref) methods. 
"""
module Substances
using ModelingToolkit
using ..STREAM: ATM
include("substances/liquid.jl")
include("substances/light_water.jl")
include("substances/heavy_water.jl")
export AbstractLiquid, Liquid, LightWater, HeavyWater, H2O, D2O
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
end
using .Substances

include("knobs.jl")
include("geometry.jl")
include("dimensionless.jl")

"""
    STREAM.HTC

The heat transfer coefficient a channel wall sees.

An [`AbstractHTC`](@ref) is the handle a channel is handed, and it answers one question:

    htc(T_wall, T_bulk, ṁ, Dh, A, liquid) -> h  [W/(m²·K)]

Anything else a correlation needs (geometry, gravity, a transition band, a development
length) it captures when constructed. A user-defined model is a struct plus that one method;
[`FromFunction`](@ref) covers the one-off case.

Two layers. The Nusselt correlations (`dittus_boelter`, `elenbaas_nusselt`, the laminar forms)
are dimensionless, taking `(Re, Pr, T_wall, T_bulk)` and returning Nu. The models
([`DittusBoelter`](@ref), [`RegimeDependent`](@ref), [`SubcooledBoiling`](@ref)) return an `h`,
and [`FromNusselt`](@ref) lifts a correlation into a model. [`PropertyBasis`](@ref) selects the
temperature a model reads coolant properties at, film or bulk.

Every correlation is plain arithmetic that MTK traces through, and guards use `ifelse`.
Geometry-dependent factories take a `PipeGeometry` first and capture what they need at
construction, so the closure sees only symbolic `Re` and `Pr`.
"""
module HTC
using ModelingToolkit
using ..STREAM: AbstractLiquid, PipeGeometry, G_EARTH
using ..STREAM: ρ, cₚ, μ, κ, σ, β, Tsat
using ..STREAM: Re, Pr, Gr, Ra, flow_regime_blend
include("htc/correlations.jl")
include("htc/subcooled_boiling.jl")
include("htc/htc.jl")
export dittus_boelter, constant_Nusselt, elenbaas_nusselt, marco_han_nusselt
export fully_developed_laminar_nusselt, developing_laminar_nusselt, film_temperature
export mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux
export partial_SCB_correction, regime_dependent_q_scb
export AbstractHTC, FromFunction, FromNusselt, PropertyBasis, AtFilm, AtBulk, property_temperature
export DittusBoelter, ConstantNusselt, FullyDevelopedLaminar, DevelopingLaminar
export Elenbaas, RegimeDependent, Maximal, SubcooledBoiling
end

"""
    STREAM.Friction

The wall friction factor a channel or a resistor is handed.

An [`AbstractDarcyFactor`](@ref) answers one question:

    darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f  [dimensionless]

The wall temperature and the pipe carry the two corrections a heated channel needs: `k_R`, the
geometric correction on the Reynolds fed to each branch, and `k_H`, the viscosity correction,
which compares wall against bulk viscosity weighted by the heated and wet perimeters.

Two layers, as in [`HTC`](@ref). The correlations (`laminar`, `turbulent`, `blasius`,
`rectangular_laminar`) take a Reynolds number and nothing else. The models
([`Blasius`](@ref), [`RegimeDependent`](@ref)) add the property reads and the corrections, and
[`FromReynolds`](@ref) lifts a correlation into a model.

`darcy_weisbach_dp` turns a factor into a pressure drop over a length of duct. For a fitting,
which has no length, use [`LocalLoss`](@ref).
"""
module Friction
using ModelingToolkit
using ..STREAM: AbstractLiquid, PipeGeometry
using ..STREAM: μ, Re, flow_regime_blend
include("friction/correlations.jl")
include("friction/darcy.jl")
export blasius, laminar, turbulent
export rectangular_laminar, rectangular_correction, viscosity_correction
export darcy_weisbach_dp
export AbstractDarcyFactor, FromFunction, FromReynolds, Blasius, Laminar
export Turbulent, RectangularLaminar, RegimeDependent
end

"""
    STREAM.LocalLoss

Minor (local) pressure losses across a sudden area change, after Idelchik.

`factor(ṁ, A1, A2, mu)` gives the dimensionless loss coefficient `K`, and [`dp`](@ref) turns it
into a pressure in Pa. `K` comes from Idelchik tables 4.2 (expansion) and 4.10 (contraction),
indexed by area ratio and Reynolds number, with analytic closed forms above the tabulated
Reynolds range and extrapolation below it. `factor` is `@register_symbolic`, so it can sit
inside an MTK equation.

The drop has the same quadratic form as `Friction.darcy_weisbach_dp` without the `L/Dh` factor.
[`LocalPressureDrop`](@ref) is the component wrapping it.
"""
module LocalLoss
using ModelingToolkit
include("local_loss.jl")
export dp, sudden_expansion_factor, sudden_contraction_factor
end

"""
    STREAM.Thresholds

Safety limits, and the post-solve machinery that applies them to a solved channel.

The correlations (`q_CHF_mirshak`, `q_CHF_sudo_kaminaga`, `q_CHF_fabrega`,
`q_OFI_whittle_forgan`, `q_OSV_saha_zuber`, `q_boiling_onset`, `bergles_rohsenow_t_onb`,
[`twall_limit`](@ref)) run after a solve, on numbers rather than symbolics, and each takes
either its raw arguments or a [`ChannelState`](@ref).

[`ChannelState`](@ref) reads one channel's fields out of a `NonlinearSolution` or an
`ODESolution`. [`threshold_analysis`](@ref) builds one and applies the functions you name;
[`chfr`](@ref) builds a CHF-ratio closure with face selection and a zero-flux guard.

Analysis needs a channel carrying a wall temperature, so `Channel` or `ChannelAndContacts`, not
`ChannelHeatFlux`.
"""
module Thresholds
using ModelingToolkit
using QuadGK
using ..STREAM: AbstractLiquid, Liquid, PipeGeometry, H2O
using ..STREAM: ρ, cₚ, μ, κ, Tsat
using ..STREAM: Re, Pr, Pe
using ..HTC: _bergles_rohsenow_dT_ONB   # the ONB superheat, private to HTC
include("thresholds/thresholds.jl")
include("thresholds/analysis.jl")
export bergles_rohsenow_t_onb, q_boiling_onset, q_OFI_whittle_forgan, q_OSV_saha_zuber
export q_CHF_sudo_kaminaga, q_CHF_mirshak, q_CHF_fabrega, twall_limit
export ChannelState, threshold_analysis, chfr
end

"""
    STREAM.Components

The acausal MTK components a model is built from.

Every component is a function returning an uncompiled `System` and taking `name` as a keyword.
Components state equations and consume their physics from [`HTC`](@ref), [`Friction`](@ref) and
[`LocalLoss`](@ref).

- **Connectors.** [`FlowPort`](@ref) carries pressure, mass flow and stream temperature;
  [`ThermalPort`](@ref) carries a wall temperature and a heat flow. `HydraulicTwoPort` is the
  shared shell behind every one-inlet, one-outlet component.
- **Channels.** [`Channel`](@ref), [`ChannelHeatFlux`](@ref) and
  [`ChannelAndContacts`](@ref) share a finite-volume core and differ in how heat arrives: a
  given coefficient, a prescribed flux, or per-cell thermal ports.
- **Hydraulics.** [`Pump`](@ref), [`Flapper`](@ref), [`FrictionResistor`](@ref),
  [`Resistor`](@ref), [`VolumetricFlowResistor`](@ref), [`LocalPressureDrop`](@ref),
  [`Gravity`](@ref), [`Inertia`](@ref).
- **Solid heat.** [`HeatDiffusion`](@ref), a 2D finite-difference plate.
- **Neutronics.** [`PointKinetics`](@ref) with any delayed group count, plus
  [`ReactivityController`](@ref) and the SCRAM callbacks.
- **Boundary conditions and value sources.** [`HeatExchanger`](@ref),
  [`ConstantTemperature`](@ref), [`WallTemperature`](@ref), [`HeatFluxSource`](@ref),
  [`ConvectiveBoundary`](@ref).

`Base.Channel` also exists, so `using STREAM.Components` leaves `Channel` ambiguous. Import it
explicitly with `using STREAM.Components: Channel`, or qualify it.
"""
module Components
using ModelingToolkit
using OrdinaryDiffEq
using ModelingToolkit: t_nounits as t, D_nounits as D
using ModelingToolkit: ⋅
using ..STREAM: AbstractLiquid, PipeGeometry, G_EARTH, ATM
using ..STREAM: ρ, cₚ, μ, κ, Tsat
using ..STREAM: Re, Pr, Nu, Gr, Ra
using ..HTC
using ..HTC: _bergles_rohsenow_dT_ONB   # the ONB superheat, private to HTC
using ..Friction
using ..LocalLoss
using ..STREAM
include("components/connectors.jl")
include("components/twoports.jl")
include("components/pump.jl")
include("components/flapper.jl")
include("components/resistors.jl")
include("components/ideal.jl")
include("components/sources.jl")
include("components/channels.jl")
include("components/heat_diffusion.jl")
include("components/point_kinetics.jl")
export FlowPort, ThermalPort
export Channel, Pump, Flapper, FrictionResistor, Gravity, Resistor, VolumetricFlowResistor
export LocalPressureDrop, Inertia, HeatExchanger, bilinear_inertia
export ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, WallTemperature
export HeatFluxSource, ConvectiveBoundary, HeatDiffusion
export PointKinetics, point_kinetics_steady_state, U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
export ReactivityController, worth, change_state
export SCRAMCondition, SCRAM_at_power, scram_callback, flapper_callback, watch_flow
end

"""
    STREAM.Assemblies

Joining components that already exist, and the named arrangements built out of those joins.

[`Connect`](@ref) holds the wiring verbs: [`inseries`](@ref) and [`inparallel`](@ref) for
hydraulic chains, [`face`](@ref) and [`faces`](@ref) for per-cell thermal contact,
[`temperature_feedback`](@ref) for the point-kinetics bindings. Each returns a
`Vector{Equation}` to splice into a connection list.

`Assemblies` holds the arrangements: [`symmetric_plate`](@ref), [`plate`](@ref),
[`one_sided`](@ref), [`single_channel`](@ref) and [`fuel_assembly`](@ref) return an uncompiled
`System` already wired, leaving the caller to add boundary conditions and compile.
[`compose_systems`](@ref) is the general form. [`check_gravity_mismatch`](@ref) reports whether a
loop's channels agree about which way is up.

[`port`](@ref) indexes one element of an indexed connector array.
"""
module Assemblies
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ..STREAM: PipeGeometry
    using ..Components
include("assemblies/port.jl")
    """
        STREAM.Assemblies.Connect

    The wiring verbs. Each takes components and returns the `Vector{Equation}` that joins them
    rather than a composed system, so results concatenate into one connection list.
    """
module Connect
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ...Components
import ..port
include("assemblies/connections.jl")
export inseries, inparallel, face, faces, temperature_feedback
end
using .Connect
using .Connect: var_length   # the arrangements below count ports with it

include("assemblies/assemblies.jl")
export Connect
export inseries, inparallel, face, faces, port, temperature_feedback
export check_gravity_mismatch, compose_systems
export symmetric_plate, plate, one_sided, single_channel, fuel_assembly
end

"""
    STREAM.Utilities

Grid resampling and axial profile helpers, for moving per-cell data between meshes that do not
line up.

[`rebin_extensive`](@ref) resamples amounts (power per cell, mass per cell) and preserves the
total. [`rebin_intensive`](@ref) resamples per-cell values (temperature, heat flux) and preserves
the value. Both treat the field as piecewise-constant over each source cell and integrate its
overlap with each target cell.

[`cosine_power_shape`](@ref) and [`cosine_T_wall_profile`](@ref) build axial input shapes.

None of these validate or normalize their inputs; negatives, zeros and NaNs pass through.
"""
module Utilities
include("utilities.jl")
export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile
end

include("initial_conditions.jl")
include("solvers.jl")

"""
    STREAM.Examples

Worked builders that assemble a complete, solvable model in one call.

The module is not exported. Reach a builder as `STREAM.Examples.build_loop`, or bring them in
with `using STREAM.Examples`.

Most builders return a compiled `System`. `build_loop_pk` returns `(ssys, ic)`, the compiled
system together with a matching operating point ready for `solve_transient`.
"""
module Examples
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ..STREAM
using ..Components
# Explicit, because an implicit `using` cannot resolve Channel against Base.Channel.
using ..Components: Channel
using ..Assemblies
using ..HTC
using ..Friction
include("examples.jl")
export build_loop, build_loop_vertical, build_loop_transient, build_cube
export build_loop_lof_bypass, build_loop_pk
end

# The public surface. Everything not listed here is reached through its module.

# Submodules
export Substances, HTC, Friction, LocalLoss, Thresholds, Components, Assemblies, Utilities

# Coolant properties, their aliases, and the two coolants
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
export H2O, D2O

# Dimensionless numbers
export Re, Re_vel, Pr, Nu, Pe, Gr, Ra, flow_regime_blend

# Geometry
export PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular

# Solve entry points and the operating-point guess
export solve_steady, solve_transient, steady_state_guess

# Physical constants
export G_EARTH, ATM

# Design knobs
export knob_defaults, @design_knob

end  # module STREAM

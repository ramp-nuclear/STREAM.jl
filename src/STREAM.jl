"""
    STREAM

Thermal-hydraulic and neutronic modelling for research reactors, built on
ModelingToolkit. A model is assembled from acausal components, compiled with
`mtkcompile`, and solved through [`solve_steady`](@ref) or [`solve_transient`](@ref).

# The submodule stack

Each submodule reaches only downward, so the dependency order is also the reading order:

```
Substances -> Dimensionless -> {HTC, Friction, LocalLoss, Thresholds}
           -> Components -> {DecayHeat, Assemblies} -> Solvers
```

| Module | What lives there |
|:---|:---|
| [`Substances`](@ref) | coolants and their property correlations |
| [`HTC`](@ref) | wall heat transfer models and Nusselt correlations |
| [`Friction`](@ref) | Darcy friction factor models and correlations |
| [`LocalLoss`](@ref) | Idelchik minor losses for sudden area changes, and discharge coefficients |
| [`Thresholds`](@ref) | safety limits and the post-solve analysis that applies them |
| [`Components`](@ref) | the MTK components a model is built from |
| [`DecayHeat`](@ref) | decay heat contributions and the standards behind them |
| [`Assemblies`](@ref) | wiring verbs and named arrangements of components |
| [`Utilities`](@ref) | grid resampling and axial profile helpers |

[`assembly`](@ref) composes components with a list of connections, and [`port`](@ref) reaches
one cell of a per-cell connector array. Every submodule can use both.

# Units

SI units everywhere, except temperatures, which are in °C.
"""
module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ModelingToolkit: SymbolicUtils
using OrdinaryDiffEq
using OrdinaryDiffEqNonlinearSolve: BrownFullBasicInit
using QuadGK
using SteadyStateDiffEq

include("constants.jl")

"""
    STREAM.Substances

Coolants and the property correlations behind them.

A coolant is a singleton type such as `LightWater` (aliased [`H2O`](@ref)) answering nine
property queries. Components take one as a keyword argument, or a model names its coolant
once with [`@coolant`](@ref) and leaves the keyword out. [`coolant`](@ref) returns the
coolant in effect, or the one a channel was built with.
[`Liquid`](@ref) holds fixed property values and is itself an `AbstractLiquid`, for a coolant
frozen at one state point.

Each property has an alias naming the same function, so `ρ === density`.

[`Solid`](@ref) holds the constant density, specific heat and conductivity of a solid, read
through the same `density`, `specific_heat` and `conductivity` functions.

A new coolant implements the nine [`AbstractLiquid`](@ref) methods. 
"""
module Substances
using ModelingToolkit
using Base: ScopedValues
using ..STREAM: ATM
include("substances/liquid.jl")
include("substances/light_water.jl")
include("substances/heavy_water.jl")
include("substances/coolant_scope.jl")
include("substances/solid.jl")
export AbstractLiquid, Liquid, LightWater, HeavyWater, H2O, D2O, Solid
export coolant, @coolant
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
end
using .Substances

include("knobs.jl")
include("geometry.jl")
include("dimensionless.jl")
# Composition helpers every module uses. The files sit with Assemblies, the module that
# builds on them, but load here, before Components needs them.
include("assemblies/port.jl")
include("assemblies/assembly.jl")

"""
    STREAM.HTC

The heat transfer coefficient a channel wall sees.

An [`AbstractHTC`](@ref) is the handle a channel is handed, and it answers one question:

    htc(T_wall, T_bulk, ṁ, liquid, duct) -> h  [W/(m²·K)]

The duct is handed over on every call, so one model serves channels of any geometry. Anything
else a correlation needs (gravity, a transition band, a development length) it captures when
constructed. A user-defined model is a struct plus that one method;
[`FromFunction`](@ref) covers the one-off case.

Two layers. The Nusselt correlations (`dittus_boelter`, `elenbaas_nusselt`, the laminar forms)
are dimensionless, taking `(Re, Pr, T_wall, T_bulk)` and returning Nu. The models
([`DittusBoelter`](@ref), [`RegimeDependent`](@ref), [`SubcooledBoiling`](@ref)) return an `h`,
and [`FromNusselt`](@ref) lifts a correlation into a model. [`PropertyBasis`](@ref) selects the
temperature a model reads coolant properties at, film or bulk.

Every correlation is plain arithmetic that MTK traces through, and guards use `ifelse`. A
correlation that only holds for one shape, such as the laminar plate Nusselt numbers or
Elenbaas, dispatches on `Duct{<:Rectangular}`.

The heat exchanger relations live here too: [`effectiveness`](@ref) for a
[`Counterflow`](@ref) or [`ParallelFlow`](@ref) arrangement, and [`flow_scaled_UA`](@ref), a UA
that follows the flows on both sides.
"""
module HTC
using ModelingToolkit
using ..STREAM: AbstractLiquid, Liquid, G_EARTH
using ..STREAM: Duct, Rectangular, flow_area, hydraulic_diameter, aspect_ratio
using ..STREAM: ρ, cₚ, μ, κ, σ, β, Tsat
using ..STREAM: Re, Pr, Gr, Ra, flow_regime_blend, _correlation_name
include("htc/correlations.jl")
include("htc/subcooled_boiling.jl")
include("htc/htc.jl")
include("htc/exchangers.jl")
export dittus_boelter, constant_Nusselt, elenbaas_nusselt, marco_han_nusselt
export fully_developed_laminar_nusselt, developing_laminar_nusselt, film_temperature
export mcadams_scb_heat_flux, rohsenow_scb_heat_flux
export partial_SCB_correction, regime_dependent_q_scb
export AbstractHTC, FromFunction, FromNusselt, PropertyBasis, AtFilm, AtBulk, property_temperature
export DittusBoelter, ConstantNusselt, FullyDevelopedLaminar, DevelopingLaminar
export Elenbaas, RegimeDependent, Maximal, SubcooledBoiling
export AbstractArrangement, Counterflow, ParallelFlow, effectiveness, flow_scaled_UA
end

"""
    STREAM.Friction

The wall friction factor a channel or a resistor is handed.

An [`AbstractDarcyFactor`](@ref) answers one question:

    darcy(T_wall, T_bulk, ṁ, liquid, duct) -> f  [dimensionless]

The same arguments, in the same order, as an [`HTC`](@ref) model takes. The wall temperature
and the duct carry the two corrections a heated channel needs: `k_R`, the geometric correction
on the Reynolds fed to each branch, and `k_H`, the viscosity correction, which compares wall
against bulk viscosity weighted by the heated and wet perimeters.

Two layers, as in [`HTC`](@ref). The correlations (`laminar`, `turbulent`, `blasius`) take a
Reynolds number and nothing else, and `rectangular_laminar` the aspect ratio too. The models
([`Blasius`](@ref), [`RegimeDependent`](@ref)) add the property reads and the corrections, and
[`FromReynolds`](@ref) lifts a correlation into a model.

`darcy_weisbach_dp` turns a factor into a pressure drop over a length of duct. For a fitting,
which has no length, use [`LocalLoss`](@ref).
"""
module Friction
using ModelingToolkit
using ..STREAM: AbstractLiquid
using ..STREAM: Duct, Rectangular, Circular, flow_area, hydraulic_diameter, aspect_ratio
using ..STREAM: heated_perimeter, wetted_perimeter
using ..STREAM: μ, Re, flow_regime_blend, _correlation_name
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
[`LocalPressureDrop`](@ref STREAM.Components.LocalPressureDrop) is the component wrapping it.

The discharge coefficient of a hole, which an [`Orifice`](@ref STREAM.Components.Orifice) is
given, lives here too: [`discharge_cd`](@ref) by geometry, and [`lichtarowicz_cd`](@ref) at
finite Reynolds number.
"""
module LocalLoss
using ModelingToolkit
include("local_loss.jl")
export dp, sudden_expansion_factor, sudden_contraction_factor
export discharge_cd, lichtarowicz_cd
end

"""
    STREAM.Thresholds

Safety limits, and the post-solve machinery that applies them to a solved channel.

The correlations (`q_CHF_mirshak`, `q_CHF_sudo_kaminaga`, `q_CHF_fabrega`,
`q_OFI_whittle_forgan`, `q_OSV_saha_zuber`, `q_boiling_onset`, `bergles_rohsenow_t_onb`,
[`twall_limit`](@ref)) run after a solve, on numbers rather than symbolics, and each takes
either its raw arguments or a [`ChannelState`](@ref).

[`ChannelState`](@ref) reads one channel's fields at one instant out of a
`NonlinearSolution` or an `ODESolution`. [`threshold_analysis`](@ref) builds one, at every
saved time for a transient, and applies the functions you name. [`chfr`](@ref) builds a
CHF-ratio closure with face selection and a zero-flux guard, and [`worst_case`](@ref) finds
the smallest margin and where and when it occurs. [`cavitation`](@ref) names the orifice
throats that reached saturation during a run.

Analysis needs a channel carrying a wall temperature, so `Channel` or `ChannelAndContacts`, not
`ChannelHeatFlux`.
"""
module Thresholds
using ModelingToolkit
using QuadGK
using ..STREAM: AbstractLiquid, Liquid, G_EARTH, coolant
using ..STREAM: Duct, Rectangular, Circular, Annular, flow_area, hydraulic_diameter
using ..STREAM: heated_perimeter, duct
using ..STREAM: ρ, cₚ, μ, κ, Tsat
using ..STREAM: Re, Pr, Pe
using ..HTC: _bergles_rohsenow_dT_ONB   # the ONB superheat, private to HTC
include("thresholds/thresholds.jl")
include("thresholds/analysis.jl")
export bergles_rohsenow_t_onb, q_boiling_onset, q_OFI_whittle_forgan, q_OSV_saha_zuber
export q_CHF_sudo_kaminaga, q_CHF_mirshak, q_CHF_fabrega, twall_limit
export ChannelState, threshold_analysis, chfr, worst_case, cavitation
end

"""
    STREAM.Components

The acausal MTK components a model is built from.

Every component is a function returning an uncompiled `System` and taking `name` as a keyword.
Components state equations and consume their physics from [`HTC`](@ref STREAM.HTC), [`Friction`](@ref STREAM.Friction) and
[`LocalLoss`](@ref).

- **Connectors.** [`FlowPort`](@ref) carries pressure, mass flow and stream temperature;
  [`ThermalPort`](@ref) carries a wall temperature and a heat flow. [`HydraulicTwoPort`](@ref)
  is the shared shell behind every one-inlet, one-outlet component, and
  [`flow_relation`](@ref) builds a new one from its relation between pressure rise and flow.
- **Channels.** [`Channel`](@ref), [`ChannelHeatFlux`](@ref) and
  [`ChannelAndContacts`](@ref) share a finite-volume core and differ in how heat arrives: a
  given coefficient, a prescribed flux, or per-cell thermal ports.
- **Hydraulics.** [`Pump`](@ref), [`Flapper`](@ref), [`FrictionResistor`](@ref),
  [`Resistor`](@ref), [`VolumetricFlowResistor`](@ref), [`LocalPressureDrop`](@ref),
  [`Gravity`](@ref), [`Inertia`](@ref).
- **Solid heat.** [`HeatDiffusion`](@ref), a 2D finite-volume plate ([`Slab`](@ref)) or rod
  ([`Cylinder`](@ref)) with per-cell materials, contact conductances and optional axial
  conduction.
- **Neutronics.** [`PointKinetics`](@ref) with any delayed group count, plus
  [`ReactivityController`](@ref) and the SCRAM callbacks.
- **Boundary conditions.** [`HeatExchanger`](@ref), [`ConstantTemperature`](@ref),
  [`ConvectiveBoundary`](@ref). `HeatExchanger(T)` holds a loop at `T`; given a `UA` it
  exchanges a finite amount of heat with a sink at `T`, and with a `UA` alone it couples two
  loops. A `Channel` wall or a `ChannelHeatFlux` flux needs no component: bind it in the
  connection list, `ch.T_wall_left .~ T`.
- **Loss of coolant.** [`Tank`](@ref), a free-surface inventory whose level sets the pressure
  at each connection; [`Environment`](@ref), the ambient a break discharges into; and
  [`Orifice`](@ref), the break itself, sealed until its machine opens it.

`Base.Channel` also exists, so `using STREAM.Components` leaves `Channel` ambiguous. Import it
explicitly with `using STREAM.Components: Channel`, or qualify it.
"""
module Components
using ModelingToolkit
using OrdinaryDiffEq
using ModelingToolkit: t_nounits as t, D_nounits as D
using LinearAlgebra: ⋅
using ModelingToolkit: Symbolics, SymbolicUtils
using SymbolicIndexingInterface: getsym, ProblemState
using ..STREAM: AbstractLiquid, Duct, G_EARTH, ATM, T_ROOM, H2O, coolant
using ..STREAM: flow_area, hydraulic_diameter, heated_perimeter, _DuctKey
using ..STREAM: ρ, cₚ, μ, κ, Tsat
using ..STREAM: Re, Pr, Nu, Gr, Ra
using ..STREAM: assembly, port, _flat
using ..Substances: _CoolantKey
using ..HTC
using ..HTC: _bergles_rohsenow_dT_ONB   # the ONB superheat, private to HTC
using ..Friction
using ..LocalLoss
using ..STREAM
include("components/state_machine.jl")
include("components/connectors.jl")
include("components/twoports.jl")
include("components/pump.jl")
include("components/valves.jl")
include("components/tank.jl")
include("components/resistors.jl")
include("components/ideal.jl")
include("components/heat_exchanger.jl")
include("components/sources.jl")
include("components/channels.jl")
include("components/heat_diffusion.jl")
include("components/point_kinetics.jl")
export FlowPort, ThermalPort, HydraulicTwoPort, flow_relation
export Channel, Pump, Flapper, FrictionResistor, Gravity, Resistor, VolumetricFlowResistor
export LocalPressureDrop, Inertia, HeatExchanger, bilinear_inertia
export ResistorFromKnownPoint
export ChannelAndContacts, ChannelHeatFlux, ConstantTemperature
export ConvectiveBoundary, HeatDiffusion, Slab, Cylinder
export PointKinetics, point_kinetics_steady_state, U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
export ReactivityController
export StateMachine, StateSchedule, trip!, reset!, machine_callbacks
export Tank, Environment, Orifice
end

"""
    STREAM.DecayHeat

Sources of power that outlive the fission that caused them, and the profile of the fissions
themselves once the reactor is shut down.

Every contribution is a callable [`AbstractDecayHeat`](@ref), evaluated as
`model(t, T)` for `t` seconds after shutdown and `T` seconds of operation before it, and
returning MeV per fission event. [`FissionProducts`](@ref) is the largest of them,
[`U238CaptureChain`](@ref) covers the U239 and Np239 left by capture in U238,
[`Activation`](@ref) and [`DoubleDecay`](@ref) cover activated structural material, and
[`Fissions`](@ref) is the prompt profile from a point-kinetics solve. That last one
interpolates its samples logarithmically, unlike Python STREAM, since the quantity is a
sum of decaying exponentials; pass [`Linear`](@ref) for the Python behaviour.

Contributions add, so `sum([fp, act])` is the total, and `Q * model` weights one by an
energy per event or by a fission rate.

The tables behind [`FissionProducts`](@ref) are published standards that this package does
not distribute. Point [`standards_dir!`](@ref) at a directory holding them, or pass `dir=`
to [`read_standard`](@ref).

[`DecayHeatSource`](@ref) is how a contribution reaches a model, as the `power_input` of a
`PointKinetics`. See [Add decay heat to a transient](@ref).
"""
module DecayHeat
using DelimitedFiles
using ModelingToolkit
using OrdinaryDiffEq
using ..Components: PointKinetics, point_kinetics_steady_state, ReactivityController
using ..Components: StateMachine, _entry_at   # the log lookup, private to Components
using ..Components: U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
using ..STREAM
include("decay_heat/decay_heat.jl")
include("decay_heat/activation.jl")
include("decay_heat/actinides.jl")
include("decay_heat/fission_products.jl")
include("decay_heat/fissions.jl")
include("decay_heat/source.jl")
export AbstractDecayHeat, Sum
export Activation, DoubleDecay, U238CaptureChain, FissionProducts, Fissions
export ProfileInterpolation, LogLinear, Linear
export Standard, ANS14, ANS73, JAERI91
export Source, U235, U235_beta, U235_gamma, U238, U238_gamma
export STANDARDS_DIR, standards_dir, standards_dir!, read_standard
export DecayHeatSource, decay_time
end

"""
    STREAM.Assemblies

Joining components that already exist, and the named arrangements built out of those joins.

[`Connect`](@ref) holds the wiring verbs: [`inseries`](@ref) and [`inparallel`](@ref) for
hydraulic chains, [`face`](@ref) and [`faces`](@ref) for per-cell thermal contact,
[`temperature_feedback`](@ref) for the point-kinetics bindings. Each returns a
`Vector{Equation}` that goes into a connection list as is.

`Assemblies` holds the arrangements: [`symmetric_plate`](@ref), [`plate`](@ref),
[`one_sided`](@ref), [`single_channel`](@ref) and [`fuel_assembly`](@ref) return an uncompiled
`System` already wired, leaving the caller to add boundary conditions and compile.
[`assembly`](@ref) is the general form: it composes any components with any list of
connections.

[`assembly`](@ref), [`port`](@ref) and [`var_length`](@ref) are defined at the top level,
since components use them too, and re-exported here.
"""
module Assemblies
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ..STREAM: Duct, duct
using ..Components
using ..STREAM: assembly, port, var_length
    """
        STREAM.Assemblies.Connect

    The wiring verbs. Each takes components and returns the `Vector{Equation}` that joins them
    rather than a composed system, so results concatenate into one connection list.
    """
module Connect
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ...Components
using ...Components: _row_major   # a feedback group's cell order, private to Components
using ...STREAM: port, var_length, _flat
include("assemblies/connections.jl")
export inseries, inparallel, weighted, face, faces, temperature_feedback
end
using .Connect

include("assemblies/concrete_assemblies.jl")
export Connect
export inseries, inparallel, weighted, face, faces, port, temperature_feedback
export symmetric_plate, plate, one_sided, single_channel, fuel_assembly
export assembly
end

"""
    STREAM.Utilities

Grid resampling and axial profile helpers, for moving per-cell data between meshes that do not
line up.

[`rebin_extensive`](@ref) resamples amounts (power per cell, mass per cell) and preserves the
total. [`rebin_intensive`](@ref) resamples per-cell values (temperature, heat flux) and preserves
the value. Both treat the field as piecewise-constant over each source cell and integrate its
overlap with each target cell.

[`cosine_shape`](@ref) builds an axial power shape.
[`x_boundaries`](@ref) builds the cell boundaries across a clad plate.

None of these validate or normalize their inputs; negatives, zeros and NaNs pass through.
"""
module Utilities
include("utilities.jl")
export rebin_extensive, rebin_intensive, cosine_shape, x_boundaries
end

include("initial_conditions.jl")
include("solvers.jl")

# The public surface. Everything not listed here is reached through its module.

# Submodules
export Substances, HTC, Friction, LocalLoss, Thresholds, Components, DecayHeat
export Assemblies, Utilities

# Coolant and solid properties, their aliases, the two coolants, and Solid
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
export H2O, D2O, Solid, @coolant

# Dimensionless numbers
export Re, Re_vel, Pr, Nu, Pe, Gr, Ra, flow_regime_blend

# Geometry
export Duct, Rectangular, Circular, Annular, Effective, AbstractShape, walls
export flow_area, hydraulic_diameter, wetted_perimeter, heated_perimeter, aspect_ratio, duct

# Solve entry points and the operating-point guess
export solve_steady, solve_transient, steady_state_guess, uniform

# Physical constants
export G_EARTH, ATM, T_ROOM

# Design knobs
export knob_defaults, @design_knob

# Composing components
export assembly, port, var_length
end  # module STREAM

module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using QuadGK
using SteadyStateDiffEq

# ---------------------------------------------------------------------------------------
# Layout
#
# The package is a stack of submodules, each one a layer that only ever reaches downward:
#
#   Substances -> Dimensionless -> {HTC, Friction, LocalLoss, Thresholds}
#              -> Components -> Assemblies -> {Solvers, Examples}
#
# Names that every layer needs (the coolant properties, the dimensionless numbers, the
# geometry, the constants) are defined at this level and pulled into the submodules that
# want them. Everything else lives in its module and is reached through it.
# ---------------------------------------------------------------------------------------

include("constants.jl")

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

module LocalLoss
using ModelingToolkit
include("local_loss.jl")
export dp, factor, sudden_expansion_factor, sudden_contraction_factor
end

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
using ..LocalLoss: factor  # the Idelchik factor, private to LocalLoss
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

module Assemblies
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ..STREAM: PipeGeometry
using ..Components

# A getter, not a verb, and Connect below leans on it.
include("assemblies/port.jl")

# The wiring verbs. Reading `Connect.face(cts, cac, :thermal_left)` beats
# `connect_face(...)`: the module already said "connect", so the name need not.
module Connect
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ...Components
import ..port
include("assemblies/connections.jl")
export inseries, inparallel, face, faces, temperature_feedback
end
using .Connect
using .Connect: _infer_n   # the arrangements below count ports with it

include("assemblies/assemblies.jl")
export Connect
export inseries, inparallel, face, faces, port, temperature_feedback
export check_gravity_mismatch, compose_systems
export symmetric_plate, plate, one_sided, single_channel, fuel_assembly
end

module Utilities
include("utilities.jl")
export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile
end

include("initial_conditions.jl")
include("solvers.jl")

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

# ---------------------------------------------------------------------------------------
# The public surface.
#
# A name reaches the top level only by being listed here, which is deliberate: everything
# else is reached through its module. The rule for what earns a place is "written in almost
# every script" -- the coolant properties, the dimensionless numbers, the geometry, the
# solve entry points.
#
# Two ways to reach anything else:
#
#     using STREAM              -> Components.Channel(...), HTC.DittusBoelter()
#     using STREAM.Components   -> Channel(...)
#
# Note that a blanket `using .HTC, .Friction` here would not work: both define
# RegimeDependent, and that is the point of having modules. Names arrive by explicit list.
# ---------------------------------------------------------------------------------------

export Substances, HTC, Friction, LocalLoss, Thresholds, Components, Assemblies, Utilities

# Coolant properties, spelled out and in the usual notation. Substances holds the types
# (AbstractLiquid, Liquid, LightWater, HeavyWater); the two liquids themselves are used
# often enough to sit here.
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
export H2O, D2O

export Re, Re_vel, Pr, Nu, Pe, Gr, Ra, flow_regime_blend
export PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular
export solve_steady, solve_transient, steady_state_guess
export G_EARTH, ATM
export knob_defaults, @design_knob

end  # module STREAM

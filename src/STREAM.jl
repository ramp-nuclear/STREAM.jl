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
export fully_developed_laminar_h_spl, developing_laminar_h_spl, film_temperature
export mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux
export partial_SCB_correction, regime_dependent_q_scb
export AbstractHTC, FunctionHTC, NusseltHTC, PropertyBasis, AtFilm, AtBulk, property_temperature
export DittusBoelter, ConstantNusselt, FullyDevelopedLaminar, DevelopingLaminar
export Elenbaas, RegimeDependentHTC, MaximalHTC, SubcooledBoilingHTC
end
using .HTC

module Friction
using ModelingToolkit
using ..STREAM: AbstractLiquid, PipeGeometry
using ..STREAM: μ, Re, flow_regime_blend
include("friction/correlations.jl")
include("friction/darcy.jl")
export blasius_friction, laminar_friction, turbulent_friction
export laminar_friction_rectangular, rectangular_laminar_correction, viscosity_correction
export darcy_weisbach_dp
export DarcyFactor, FunctionDarcy, ReynoldsFactor, BlasiusFriction, LaminarFriction
export TurbulentFriction, RectangularLaminarFriction, RegimeDependentFriction
end
using .Friction

module LocalLoss
using ModelingToolkit
include("local_loss.jl")
export local_dp
end
using .LocalLoss

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
using .Thresholds

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
using ..LocalLoss: _local_loss_factor  # the Idelchik factor, private to LocalLoss
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
using .Components
# Explicit, because an implicit `using` cannot resolve Channel against Base.Channel.
using .Components: Channel

module Assemblies
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using ..STREAM: PipeGeometry
using ..Components
include("assemblies/connections.jl")
include("assemblies/assemblies.jl")
export inseries, inparallel, connect_face, connect_faces, port
export check_gravity_mismatch, compose_systems, connect_temperature_feedback
export symmetric_plate, plate, one_sided_connection, single_channel_connection, fuel_assembly
end
using .Assemblies

module Utilities
include("utilities.jl")
export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile
end
using .Utilities

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

export AbstractLiquid, Liquid, LightWater, HeavyWater, H2O, D2O, ATM
export density, vapor_density, specific_heat, viscosity, conductivity
export surface_tension, latent_heat, thermal_expansion, sat_temperature
export ρ, ρᵥ, cₚ, μ, κ, σ, hfg, β, Tsat
export FlowPort, ThermalPort
export Channel, Pump, Flapper, FrictionResistor, Gravity, Resistor, VolumetricFlowResistor
export LocalPressureDrop, Inertia, HeatExchanger
export ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, WallTemperature
export HeatFluxSource, ConvectiveBoundary, HeatDiffusion, PipeGeometry, PipeGeometry_rectangular
export PipeGeometry_circular
export knob_defaults, @design_knob
export bilinear_inertia
export dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction_rectangular
export rectangular_laminar_correction, elenbaas_nusselt, marco_han_nusselt
export turbulent_friction, laminar_friction, viscosity_correction
export darcy_weisbach_dp, local_dp
export DarcyFactor, FunctionDarcy, ReynoldsFactor, BlasiusFriction, LaminarFriction
export TurbulentFriction, RectangularLaminarFriction, RegimeDependentFriction
export fully_developed_laminar_h_spl, developing_laminar_h_spl, film_temperature
export AbstractHTC, FunctionHTC, NusseltHTC, PropertyBasis, AtFilm, AtBulk, property_temperature
export DittusBoelter, ConstantNusselt, FullyDevelopedLaminar, DevelopingLaminar
export Elenbaas, RegimeDependentHTC, MaximalHTC, SubcooledBoilingHTC
export mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux
export partial_SCB_correction, regime_dependent_q_scb
export bergles_rohsenow_t_onb, q_boiling_onset, q_OFI_whittle_forgan, q_OSV_saha_zuber
export q_CHF_sudo_kaminaga, q_CHF_mirshak, q_CHF_fabrega, twall_limit
export ChannelState, threshold_analysis, chfr
export Gr, Ra, Re_vel, Pe, flow_regime_blend, Re, Pr, Nu
export G_EARTH
export solve_steady,
    solve_transient,
    steady_state_guess,
    check_gravity_mismatch,
    port,
    connect_face,
    connect_faces
export symmetric_plate, plate, one_sided_connection, single_channel_connection, inseries, inparallel
export compose_systems, fuel_assembly
export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile
export PointKinetics, point_kinetics_steady_state, U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
export ReactivityController, worth, change_state
export SCRAMCondition, SCRAM_at_power, scram_callback, flapper_callback, watch_flow
export connect_temperature_feedback

end  # module STREAM

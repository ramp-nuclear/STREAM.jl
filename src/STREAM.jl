module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using QuadGK
using SteadyStateDiffEq

# Alias used to label HTC-closure arguments at call sites (documentation only, not enforced).
# Declared before the includes so the correlation files can reference it at parse time.
const HTCCorrelation = Function

include("fluids.jl")
include("connectors.jl")
include("knobs.jl")
include("geometry.jl")
include("physical_models/htc/correlations.jl")
include("physical_models/friction/correlations.jl")
include("physical_models/subcooled_boiling.jl")
include("physical_models/threshold_analysis.jl")
include("physical_models/dimensionless.jl")
include("physical_models/local_pressure.jl")
include("components/pump.jl")
include("components/flapper.jl")
include("components/resistors.jl")
include("components/misc.jl")
include("components/sources.jl")
include("components/channels.jl")
include("components/heat_diffusion.jl")
include("components/point_kinetics.jl")
include("composition/helpers.jl")
include("solvers.jl")
include("analysis.jl")
include("examples.jl")
include("utilities.jl")

export rho_water, cp_water, mu_water, k_water, beta_water, sat_temperature
export AbstractFluid, Water, ConstantFluid
export density, specific_heat, viscosity, conductivity, thermal_expansion
export FlowPort, ThermalPort
export Channel, Pump, Flapper, Friction, Gravity, Resistor, VolumetricFlowResistor
export LocalPressureDrop, Inertia, HeatExchanger
export ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, WallTemperature
export HeatFluxSource, ConvectiveBoundary, HeatDiffusion, PipeGeometry, PipeGeometry_rectangular
export PipeGeometry_circular
export knob_defaults, @design_knob
export dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction_rectangular
export rectangular_laminar_correction, regime_dependent, elenbaas_nusselt, elenbaas_htc
export marco_han_nusselt, turbulent_friction, viscosity_correction, maximal_htc
export fully_developed_laminar_h_spl, developing_laminar_h_spl, HTCCorrelation
export mcadams_scb_heat_flux, bergles_rohsenow_scb_heat_flux
export partial_SCB_correction, regime_dependent_q_scb
export bergles_rohsenow_t_onb, q_boiling_onset, q_OFI_whittle_forgan, q_OSV_saha_zuber
export q_CHF_sudo_kaminaga, q_CHF_mirshak, q_CHF_fabrega, twall_limit
export ChannelState, threshold_analysis, chfr, onb_temperature, boiling_onset_power
export OFI_power, OSV_flux, sudo_kaminaga_chf, mirshak_chf, fabrega_chf
export Gr, Ra, Re_vel, Pe
export build_loop, build_loop_vertical, build_loop_transient, build_cube
export build_loop_lof_bypass, build_loop_pk
export solve_steady, solve_transient, steady_state_guess, check_gravity_mismatch, port
export symmetric_plate, plate, one_sided_connection, single_channel_connection
export compose_systems, fuel_assembly
export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile
export PointKinetics, point_kinetics_steady_state, U235_LAMBDA, U235_BETA_K, U235_LAMBDA_K
export ReactivityController, worth, change_state
export SCRAMCondition, SCRAM_at_power, scram_callback, flapper_callback, watch_flow
export connect_temperature_feedback

end  # module STREAM

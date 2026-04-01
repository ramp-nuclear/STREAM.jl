module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Symbolics: @register_symbolic

include("fluids.jl")
include("connectors.jl")
include("geometry.jl")
include("physical_models/htc/correlations.jl")
include("physical_models/friction/correlations.jl")
include("physical_models/subcooled_boiling.jl")
include("physical_models/threshold_analysis.jl")
include("physical_models/dimensionless.jl")
include("components/channel.jl")
include("components/pump.jl")
include("components/flapper.jl")
include("components/resistors.jl")
include("components/misc.jl")
include("components/thermal_channel.jl")
include("components/heat_diffusion.jl")
include("composition/helpers.jl")
include("solvers.jl")
include("analysis.jl")
include("examples.jl")

export rho_water, cp_water, mu_water, k_water, beta_water, sat_temperature
export FlowPort, ThermalPort
export Channel, Pump, Flapper, Friction, Gravity, Resistor, Inertia, HeatExchanger, ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, HeatDiffusion, PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular
export dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction, rectangular_laminar_correction, regime_dependent, elenbaas_nusselt, elenbaas_htc, Marco_Han_Nusselt, turbulent_friction, viscosity_correction, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc
export McAdams_SCB_heat_flux, Bergles_Rohsenow_SCB_heat_flux, partial_SCB_correction, regime_dependent_q_scb
export Bergles_Rohsenow_T_ONB, q_boiling_onset, q_OFI_whittle_forgan, q_OSV_saha_zuber, q_CHF_sudo_kaminaga, q_CHF_mirshak, q_CHF_fabrega, twall_limit
export ChannelState, threshold_analysis, chfr, ONB_temperature, boiling_onset_power, OFI_power, OSV_flux, Sudo_Kaminaga_CHF, Mirshak_CHF, Fabrega_CHF
export Gr, Ra, Re_vel, Pe
export build_loop, build_loop_vertical, build_loop_transient, build_cube, build_loop_lof_bypass, solve_steady, solve_transient, steady_state_guess, check_gravity_mismatch, port
export symmetric_plate, plate, one_sided_connection, compose_systems

end  # module STREAM

module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Symbolics: @register_symbolic

include("fluids.jl")
include("connectors.jl")
include("correlations.jl")
include("components.jl")
include("helpers.jl")
include("solvers.jl")

export rho_water, cp_water, mu_water, k_water
export FlowPort, ThermalPort
export Channel, Pump, Friction, Gravity, Resistor, Inertia, HeatExchanger, ChannelAndContacts, ChannelHeatFlux, ConstantTemperature, HeatDiffusion, PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular
export dittus_boelter, blasius_friction, constant_Nusselt, laminar_friction, rectangular_laminar_correction, regime_dependent
export build_loop, build_loop_vertical, build_loop_transient, build_cube, solve_steady, solve_transient, steady_state_guess, check_gravity_mismatch, port
export symmetric_plate, plate, one_sided_connection, compose_systems

end  # module STREAM

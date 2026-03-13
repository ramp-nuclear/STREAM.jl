module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Symbolics: @register_symbolic

include("fluids.jl")
include("connectors.jl")
include("components.jl")
include("solvers.jl")

export rho_water, cp_water, mu_water, k_water
export FlowPort, ThermalPort
export Channel, Pump, Friction, Gravity, Resistor
export build_loop, build_loop_vertical, build_loop_transient, solve_steady, solve_transient, steady_state_guess

end  # module STREAM

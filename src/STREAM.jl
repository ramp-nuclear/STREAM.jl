module STREAM

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using Symbolics: @register_symbolic

include("fluids.jl")
include("connectors.jl")
include("components.jl")

export rho_water, cp_water, mu_water, k_water
export FlowPort, ThermalPort
export Channel, Pump, Friction, Gravity

end  # module STREAM

# components.jl — Thermal-hydraulic components for STREAM.jl
#
# Design note (q_wall indirection):
# Channel uses a single ThermalPort carrying total Q_wall (W), then splits
# internally: q_wall[i] = thermal.Q_flow / n per cell. This indirection
# exists so that a future refactor to per-cell ThermalPorts only changes
# the port declaration and q_wall binding — the energy balance loop
# D(T[i]) ~ ... is untouched.
#
# Note: `Channel` is declared as a new generic function here to avoid
# conflict with Base.Channel (Julia's built-in concurrency channel type).

# Declare as new generic functions independent of Base
function Channel end
function Channel(; name, n::Int, L, D, A)
    error("Channel not yet implemented")
end

function Pump(; name, dP)
    error("Pump not yet implemented")
end

function Friction(; name, L, D, A)
    error("Friction not yet implemented")
end

function Gravity(; name, H, A)
    error("Gravity not yet implemented")
end

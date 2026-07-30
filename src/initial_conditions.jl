# initial_conditions.jl -- building the operating point a solve starts from.
#
# Separate from solvers.jl on purpose: choosing where to start is not solving. A guess can be
# analytic (steady_state_guess) or lifted from an earlier solution (_state_snapshot), and
# either way it is just a `unknown => value` map handed to a problem constructor.

"""
    steady_state_guess(; T_inlet, Q_wall, ṁ_guess, n) -> Vector{Float64}

Generate a linear temperature guess for steady-state initialization.

# Arguments
- `T_inlet`: inlet temperature [°C]
- `Q_wall`: total wall heat input [W]
- `ṁ_guess`: estimated mass flow rate [kg/s]
- `n`: number of axial cells (Int)

# Returns
Vector of length `n` with linearly interpolated temperatures from `T_inlet` to estimated
`T_outlet` as `Float64`.
"""
function steady_state_guess(;
    T_inlet::Float64,
    Q_wall::Float64,
    ṁ_guess::Float64,
    n::Int,
    liquid::AbstractLiquid=H2O,
)
    cp = cₚ(liquid, T_inlet)
    return [T_inlet + i * Q_wall / (n * ṁ_guess * cp) for i in 1:n]
end


# Internal helper. Capture every state of a compiled system from a solved point as a symbolic
# initial-condition map (`unknown => value` for each entry of `unknowns(ssys)`). MTK problem
# constructors require a symbolic map, not a raw state vector or a bare solution. `unknowns(ssys)`
# is the complete, non-redundant state (observed variables are recomputed from it), so this seeds a
# transient from a solved state without guessing which variables MTK kept. Used by the
# `solve_transient(ssys, sol_ss, t; ...)` method below; not part of the public API.
_state_snapshot(ssys, sol) = [u => sol[u] for u in unknowns(ssys)]

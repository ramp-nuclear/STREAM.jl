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

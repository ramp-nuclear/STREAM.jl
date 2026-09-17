"""
    uniform(systems, value, variables...) -> Vector{Pair}

Give each of `variables` the same `value` in every one of `systems`, for an operating point.
An array variable gets `value` in every element, and a system without one of the variables is
skipped for it.

# Arguments
- `systems`: subsystems of a compiled system, such as `ssys.riser`
- `value`: the value to give
- `variables`: `Symbol`s naming the variables

# Returns
A vector of `variable => value` pairs to splice into an operating point.

# Example
```julia
op = [ssys.pump.inlet.ṁ => 16.2, uniform([ssys.riser, ssys.core.ch], 35.0, :T)...]
```
"""
function uniform(systems, value, variables::Symbol...)
    pairs = Pair[]
    for sys in systems, var in variables
        hasproperty(sys, var) || continue
        x = getproperty(sys, var)
        push!(pairs, x => (x isa AbstractArray ? fill(value, size(x)) : value))
    end
    return pairs
end

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

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
    uniform(ssys::System, value, variables...) -> Vector{Pair}

Give `value` to every unknown of the compiled system `ssys` whose own name is one of
`variables`, in whichever component it sits.

`uniform(ssys, 20.0, :T)` starts every temperature in a loop at 20 °C: each cell, and each
port and contact temperature `mtkcompile` kept, whichever member of a connection set that
is.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `value`: the value to give
- `variables`: `Symbol`s naming the variables, without their namespace

# Returns
A vector of `unknown => value` pairs to splice into an operating point.
"""
function uniform(ssys::ModelingToolkit.AbstractSystem, value, variables::Symbol...)
    path(u) = split(string(ModelingToolkit.getname(u)), ModelingToolkit.NAMESPACE_SEPARATOR)
    return [u => value for u in unknowns(ssys) if Symbol(last(path(u))) in variables]
end

"""
    steady_state_guess(; T_inlet, Q_wall, ṁ_guess, n, liquid=H2O) -> Vector{Float64}

Generate a linear temperature guess for steady-state initialization.

# Arguments
- `T_inlet`: inlet temperature [°C]
- `Q_wall`: total wall heat input [W]
- `ṁ_guess`: estimated mass flow rate [kg/s]
- `n`: number of axial cells (Int)
- `liquid`: coolant (`AbstractLiquid`), default [`H2O`](@ref), whose `cₚ` at `T_inlet` is used

# Returns
Vector of length `n` with linearly interpolated temperatures from `T_inlet` to estimated
`T_outlet` as `Float64`.
"""
function steady_state_guess(;
    T_inlet::Real,
    Q_wall::Real,
    ṁ_guess::Real,
    n::Int,
    liquid::AbstractLiquid=H2O,
)
    cp = cₚ(liquid, T_inlet)
    return collect(T_inlet .+ (1:n) .* Q_wall ./ (n * ṁ_guess * cp))
end

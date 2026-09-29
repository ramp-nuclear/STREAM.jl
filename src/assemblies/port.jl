"""
    port(sys, face, i::Int)
    port(sys, face, var::Symbol)

Reach one element of an indexed connector array, or one variable across all of its elements.

Per-cell thermal faces are separate subsystems named `thermal_left1 … thermal_leftn`, so
reaching cell `i` means building the name. [`face`](@ref) and [`faces`](@ref) are built on this.

# Arguments
- `sys`: MTK system instance
- `face`: connector array name (Symbol), such as `:thermal_left`
- `i`: 1-based cell index (Int)
- `var`: connector variable name (Symbol), such as `:T` or `:Q`

# Returns
With `i`, the namespaced connector subsystem (for example `sys.thermal_left3`), ready to pass
to `connect`. With `var`, a vector holding that variable of every cell, in cell order, ready
for broadcast equations and for indexing a solution.

# Example
```julia
connect(port(cac, :thermal_right, 3), port(fuel, :thermal_left, 3))
port(cac, :thermal_left, :T) .~ cac.T      # pin every left wall to the coolant
sol[port(cac, :thermal_right, :T), end]    # wall temperatures at the last time
```
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
port(sys, face::Symbol, var::Symbol) =
    [getproperty(port(sys, face, i), var) for i in 1:var_length(sys, face)]

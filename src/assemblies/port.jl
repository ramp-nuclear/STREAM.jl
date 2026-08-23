"""
    port(sys, face, i)

Reach one element of an indexed connector array.

Per-cell thermal faces are separate subsystems named `thermal_left1 … thermal_leftn`, so
reaching cell `i` means building the name. [`face`](@ref) and [`faces`](@ref) are built on this.

# Arguments
- `sys`: MTK system instance
- `face`: connector array name (Symbol), such as `:thermal_left`
- `i`: 1-based cell index (Int)

# Returns
The namespaced connector subsystem (for example `sys.thermal_left3`), ready to pass to
`connect`.

# Example
```julia
connect(port(cac, :thermal_right, 3), port(fuel, :thermal_left, 3))
```
"""
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))

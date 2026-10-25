"""
    _COOLANT

What [`default_coolant`](@ref) returns: `H2O`, or the liquid of the enclosing
[`with_coolant`](@ref) block.
"""
const _COOLANT = ScopedValues.ScopedValue{AbstractLiquid}(H2O)

"""
    _CoolantKey

The metadata key a channel's `System` holds its coolant under, for [`coolant`](@ref) to read.
"""
struct _CoolantKey end

"""
    default_coolant() -> AbstractLiquid

The coolant a component takes when its `liquid` keyword is left out: [`H2O`](@ref) outside
any [`with_coolant`](@ref) block, and the block's coolant inside one.

# Examples
```jldoctest
julia> Substances.default_coolant()
H2O

julia> with_coolant(Substances.default_coolant, D2O)
D2O
```
"""
default_coolant() = _COOLANT[]

"""
    coolant(sys) -> AbstractLiquid

The coolant the channel `sys` was built with.

# Arguments
- `sys`: a channel's `System`, before or after compilation

# Returns
The coolant recorded when the channel was built.

# Throws
- `ArgumentError`: for a system that is not a STREAM channel
"""
function coolant(sys::ModelingToolkit.AbstractSystem)
    liquid = ModelingToolkit.getmetadata(sys, _CoolantKey, nothing)
    liquid === nothing && throw(ArgumentError(
        "$(nameof(sys)) carries no coolant: only a channel built by STREAM does",
    ))
    return liquid
end

"""
    with_coolant(f, liquid)
    with_coolant(liquid) do ... end

Run `f()` with [`default_coolant`](@ref) returning `liquid`, so every `liquid` keyword left
out inside the block takes it:

```julia
using STREAM.Components: Channel, Gravity

geom = Duct(0.6, Circular(0.01))
ch, rise = with_coolant(D2O) do
    @named ch = Channel(; n=10, geometry=geom)
    @named rise = Gravity(2.0)
    ch, rise
end
```

An explicit keyword wins over the block, the block over `H2O`. A block nested inside
another shadows it until it ends, and the outer coolant is back once the block returns or
throws. A channel built inside the block records the block's coolant, which
[`coolant`](@ref) reads back.

# Arguments
- `f`: the code to run, a function of no arguments
- `liquid`: the coolant ([`AbstractLiquid`](@ref)) for the block

# Returns
Whatever `f` returns.
"""
with_coolant(f, liquid::AbstractLiquid) = ScopedValues.with(f, _COOLANT => liquid)

"""
    _COOLANT

What [`coolant`](@ref) returns: `H2O`, or the liquid of the enclosing [`with_coolant`](@ref)
block.
"""
const _COOLANT = ScopedValues.ScopedValue{AbstractLiquid}(H2O)

"""
    coolant() -> AbstractLiquid

The coolant a component takes when its `liquid` keyword is left out: [`H2O`](@ref) outside
any [`with_coolant`](@ref) block, and the block's coolant inside one.

# Returns
The current coolant.

# Examples
```jldoctest
julia> Substances.coolant()
H2O

julia> with_coolant(Substances.coolant, D2O)
D2O
```
"""
coolant() = _COOLANT[]

"""
    with_coolant(f, liquid)
    with_coolant(liquid) do ... end

Run `f()` with [`coolant`](@ref) returning `liquid`, so every `liquid` keyword left out
inside the block takes it:

```julia
using STREAM.Components: Channel, Gravity

geom = PipeGeometry_circular(0.6, 0.01)
ch, rise = with_coolant(D2O) do
    @named ch = Channel(; n=10, geometry=geom)
    @named rise = Gravity(2.0)
    ch, rise
end
```

An explicit keyword wins over the block, the block over `H2O`. A block nested inside
another shadows it until it ends, and the outer coolant is back once the block returns or
throws.

# Arguments
- `f`: the code to run, a function of no arguments
- `liquid`: the coolant ([`AbstractLiquid`](@ref)) for the block

# Returns
Whatever `f` returns.
"""
with_coolant(f, liquid::AbstractLiquid) = ScopedValues.with(f, _COOLANT => liquid)

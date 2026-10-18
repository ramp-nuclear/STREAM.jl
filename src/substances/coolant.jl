"""
    _COOLANT

What [`coolant`](@ref) returns: `H2O`, or the liquid of the enclosing [`with_coolant`](@ref)
block.
"""
const _COOLANT = ScopedValues.ScopedValue{AbstractLiquid}(H2O)

"""
    CoolantKey

The metadata key under which a channel's `System` holds the coolant it was built with.
[`coolant`](@ref) reads it back.
"""
struct CoolantKey end

"""
    coolant() -> AbstractLiquid
    coolant(sys) -> AbstractLiquid

`coolant()` is the coolant a component takes when its `liquid` keyword is left out:
[`H2O`](@ref) outside any [`with_coolant`](@ref) block, and the block's coolant inside one.

`coolant(sys)` is the coolant the channel `sys` was built with, read from the metadata
`CoolantKey` names, which `compose` and `mtkcompile` keep.

# Arguments
- `sys`: a channel's `System`, before or after compilation

# Returns
The current coolant, or the one `sys` was built with.

# Throws
- `ArgumentError`: when `sys` records no coolant, which only a channel does

# Examples
```jldoctest
julia> Substances.coolant()
H2O

julia> with_coolant(Substances.coolant, D2O)
D2O
```
"""
coolant() = _COOLANT[]

function coolant(sys::ModelingToolkit.AbstractSystem)
    liquid = ModelingToolkit.getmetadata(sys, CoolantKey, nothing)
    liquid === nothing && throw(ArgumentError(
        "$(nameof(sys)) was built without a coolant; only a channel records one",
    ))
    return liquid
end

"""
    _coolant_metadata(liquid) -> Tuple

The `metadata` a channel's `System` is built with so [`coolant`](@ref) returns `liquid`.
"""
_coolant_metadata(liquid::AbstractLiquid) = (CoolantKey => liquid,)

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

Every channel records the coolant it was built with, and a `ChannelState` reads it from there,
so threshold analysis needs no block. [`steady_state_guess`](@ref STREAM.steady_state_guess)
runs before any model exists and reads the default when it is called.

# Arguments
- `f`: the code to run, a function of no arguments
- `liquid`: the coolant ([`AbstractLiquid`](@ref)) for the block

# Returns
Whatever `f` returns.
"""
with_coolant(f, liquid::AbstractLiquid) = ScopedValues.with(f, _COOLANT => liquid)

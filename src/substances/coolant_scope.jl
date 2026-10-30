"""
    _COOLANT

The coolant of the enclosing [`@coolant`](@ref) block, or `nothing` outside any block.
"""
const _COOLANT = ScopedValues.ScopedValue{Union{AbstractLiquid,Nothing}}(nothing)

"""
    _GLOBAL_COOLANT

The coolant outside any [`@coolant`](@ref) block: `H2O` until `@coolant liquid` sets it.
"""
const _GLOBAL_COOLANT = Ref{AbstractLiquid}(H2O)

"""
    _CoolantKey

The metadata key a channel's `System` holds its coolant under, for [`coolant`](@ref) to read.
"""
struct _CoolantKey end

"""
    @coolant liquid
    @coolant liquid begin ... end

Name the coolant every `liquid` keyword left out takes. The first form sets it for the rest
of the session, the second only while the block runs:

```julia
using STREAM.Components: Channel, Gravity

@coolant D2O begin
    @named ch = Channel(; n=10, geometry=Duct(0.6, Circular(0.01)))
    @named rise = Gravity(2.0)
end
```

Names assigned inside the block, `ch` and `rise` here, stay defined after it. An explicit
keyword wins over a block, a block over the session coolant, which starts as [`H2O`](@ref).
A block nested inside another shadows it until it ends, and the outer coolant is back once
the block returns or throws. A channel records the coolant it was built with, which
[`coolant`](@ref) reads back.

# Arguments
- `liquid`: the coolant ([`AbstractLiquid`](@ref))
- `begin ... end`: the code it applies to, or a single expression

# Returns
The block's last value, or `liquid` for the session form.
"""
macro coolant(liquid)
    return :(_GLOBAL_COOLANT[] = $(esc(liquid)))
end

macro coolant(liquid, block)
    return :(ScopedValues.@with _COOLANT => $(esc(liquid)) $(esc(block)))
end

"""
    coolant() -> AbstractLiquid
    coolant(sys) -> AbstractLiquid

The coolant in effect where it is called, which a component takes when its `liquid` keyword
is left out, or the coolant the channel `sys` was built with.

# Arguments
- `sys`: a channel's `System`, before or after compilation

# Returns
The coolant in effect, or the one recorded when `sys` was built.

# Throws
- `ArgumentError`: for a system that is not a STREAM channel

# Examples
```jldoctest
julia> Substances.coolant()
H2O

julia> @coolant D2O Substances.coolant()
D2O
```
"""
coolant() = something(_COOLANT[], _GLOBAL_COOLANT[])

function coolant(sys::ModelingToolkit.AbstractSystem)
    liquid = ModelingToolkit.getmetadata(sys, _CoolantKey, nothing)
    liquid === nothing && throw(ArgumentError(
        "$(nameof(sys)) carries no coolant: only a channel built by STREAM does",
    ))
    return liquid
end

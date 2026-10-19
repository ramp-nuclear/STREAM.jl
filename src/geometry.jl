"""
    AbstractShape

The cross-section of a [`Duct`](@ref): [`Rectangular`](@ref), [`Circular`](@ref), or
[`Effective`](@ref) for one known only by its area and perimeter.

A new shape defines [`flow_area`](@ref) and [`wetted_perimeter`](@ref). Correlations that only
hold for one shape dispatch on it, as `Duct{<:Rectangular}`.
"""
abstract type AbstractShape end

"""
    _lengths(xs...) -> Tuple

Coerce lengths to one element type: `Float64` for a fixed geometry, or `Num` as soon as one of
them is a design knob, so the geometry derives symbolically.
"""
_lengths(xs...) = any(x -> x isa Num, xs) ? map(Num, xs) : map(Float64, xs)

"""
    Rectangular(edge1, edge2) <: AbstractShape

A rectangular cross-section, such as the gap between two fuel plates. The edges go in either
order: `width` is the longer and `depth` the shorter. Either may be a design knob.

# Arguments
- `edge1`, `edge2`: the two edges [m]

# Returns
A `Rectangular` with fields `width` and `depth`.

# Examples
```jldoctest
julia> Rectangular(0.00127, 0.07)
Rectangular(0.07, 0.00127)
```
"""
struct Rectangular{T<:Real} <: AbstractShape
    width::T
    depth::T
    function Rectangular(edge1::Real, edge2::Real)
        a, b = _lengths(edge1, edge2)
        # ifelse rather than max/min, so a knob-driven edge orders correctly at any value.
        return new{typeof(a)}(ifelse(a >= b, a, b), ifelse(a >= b, b, a))
    end
end

"""
    Circular(D) <: AbstractShape

A circular cross-section of diameter `D` [m], which may be a design knob.

# Examples
```jldoctest
julia> flow_area(Circular(0.01))
7.853981633974483e-5
```
"""
struct Circular{T<:Real} <: AbstractShape
    D::T
    Circular(D::Real) = (d = only(_lengths(D)); new{typeof(d)}(d))
end

"""
    Effective(; area, wetted_perimeter) <: AbstractShape

A cross-section known only by its flow area [m²] and wetted perimeter [m], as Python STREAM's
`EffectivePipe` takes them. Correlations that need a shape's edges do not accept it.

# Examples
```jldoctest
julia> hydraulic_diameter(Effective(; area=1.0, wetted_perimeter=1.0))
4.0
```
"""
struct Effective{T<:Real} <: AbstractShape
    area::T
    wetted_perimeter::T
    function Effective(; area::Real, wetted_perimeter::Real)
        a, p = _lengths(area, wetted_perimeter)
        return new{typeof(a)}(a, p)
    end
end

@doc raw"""
    Duct(L, shape; heated)

A straight duct of length `L` and constant cross-section, heated over part of its perimeter.

The heated perimeter is split between two faces, left and right, which a channel heats
separately. A rectangular duct is heated across the width of its two long faces by default,
and a circular one around its whole perimeter, counted as the left face. An
[`Effective`](@ref) one has no default.

```math
D_h = 4A / P_{wet}
```

Any length may be a design knob (see [`@design_knob`](@ref)).

# Arguments
- `L`: length [m]
- `shape`: the cross-section, an [`AbstractShape`](@ref)
- `heated`: heated width of each face [m]. A number heats both faces, and a tuple
  `(left, right)` sets them apart, so `(w, 0)` heats only the left one.

# Returns
A `Duct` with fields `L`, `shape` and `heated`. [`flow_area`](@ref),
[`hydraulic_diameter`](@ref), [`wetted_perimeter`](@ref) and [`heated_perimeter`](@ref) give
the rest.

# Examples
A 70 mm by 1.27 mm MTR channel, 0.6 m long:
```jldoctest
julia> d = Duct(0.6, Rectangular(0.07, 0.00127))
Duct, 0.6 m long, Rectangular(0.07, 0.00127)
  flow area           8.89e-5 m^2
  hydraulic diameter  0.0024947 m
  heated              0.07 m left, 0.07 m right

julia> hydraulic_diameter(d)
0.0024947383190683323
```
"""
struct Duct{S<:AbstractShape,T<:Real}
    L::T
    shape::S
    heated::NTuple{2,T}
end

function Duct(L::Real, shape::AbstractShape; heated=_default_heated(shape))
    left, right = heated isa Tuple ? heated : (heated, heated)
    L, left, right = _lengths(L, left, right)
    return Duct(L, shape, (left, right))
end

_default_heated(s::Rectangular) = s.width
_default_heated(s::Circular) = (wetted_perimeter(s), 0)
_default_heated(s::AbstractShape) =
    throw(ArgumentError("a duct of shape $(nameof(typeof(s))) needs `heated`"))

"""
    flow_area(x) -> m^2

The flow area of a [`Duct`](@ref) or of its shape.
"""
flow_area(s::Rectangular) = s.width * s.depth
flow_area(s::Circular) = π * s.D^2 / 4
flow_area(s::Effective) = s.area
flow_area(d::Duct) = flow_area(d.shape)

"""
    wetted_perimeter(x) -> m

The perimeter the coolant wets, of a [`Duct`](@ref) or of its shape.
"""
wetted_perimeter(s::Rectangular) = 2 * (s.width + s.depth)
wetted_perimeter(s::Circular) = π * s.D
wetted_perimeter(s::Effective) = s.wetted_perimeter
wetted_perimeter(d::Duct) = wetted_perimeter(d.shape)

"""
    hydraulic_diameter(x) -> m

`4A / P_wet`, of a [`Duct`](@ref) or of its shape. A circle's is its diameter.
"""
hydraulic_diameter(s::AbstractShape) = 4 * flow_area(s) / wetted_perimeter(s)
hydraulic_diameter(s::Circular) = s.D
hydraulic_diameter(d::Duct) = hydraulic_diameter(d.shape)

"""
    heated_perimeter(d::Duct) -> m

The heated width of both faces together.
"""
heated_perimeter(d::Duct) = sum(d.heated)

"""
    aspect_ratio(x) -> Float64

`depth / width` of a rectangular [`Duct`](@ref) or shape, in (0, 1]. Only rectangles have one.

# Examples
```jldoctest
julia> round(aspect_ratio(Rectangular(0.07, 0.0014)); digits=6)
0.02
```
"""
aspect_ratio(s::Rectangular) = s.depth / s.width
aspect_ratio(d::Duct) = aspect_ratio(d.shape)

"""
    duct(channel) -> Duct

The [`Duct`](@ref) a channel was built with. Every STREAM channel carries its own, compiled
or not, so analysis reads the geometry off the channel rather than being handed it again.

# Arguments
- `channel`: a channel system, such as `ssys.cell.ch`

# Returns
The channel's `Duct`.

# Throws
- `ArgumentError`: for a system that is not a STREAM channel

# Example
```julia
@named ch = Components.Channel(; n=10, geometry=Duct(0.6, Circular(0.01)))
duct(ch)   # Duct, 0.6 m long, Circular(0.01)
```
"""
function duct(sys::ModelingToolkit.AbstractSystem)
    d = ModelingToolkit.getmetadata(sys, _DuctKey, nothing)
    d === nothing && throw(ArgumentError(
        "$(nameof(sys)) carries no duct: only a channel built by STREAM does"))
    return d
end

"""
    _DuctKey

The metadata key a channel stores its [`Duct`](@ref) under, read back by [`duct`](@ref).
"""
struct _DuctKey end

_with_duct(sys, d::Duct) = ModelingToolkit.setmetadata(sys, _DuctKey, d)

# A duct is one value in a broadcast, as a coolant is.
Base.broadcastable(d::Duct) = Ref(d)

Base.show(io::IO, s::Rectangular) = print(io, "Rectangular(", s.width, ", ", s.depth, ")")
Base.show(io::IO, s::Circular) = print(io, "Circular(", s.D, ")")
Base.show(io::IO, s::Effective) =
    print(io, "Effective(; area=", s.area, ", wetted_perimeter=", s.wetted_perimeter, ")")

function Base.show(io::IO, ::MIME"text/plain", d::Duct)
    r(x) = x isa Real && !(x isa Num) ? round(x; sigdigits=5) : x
    print(io, "Duct, ", r(d.L), " m long, ", d.shape)
    print(io, "\n  flow area           ", r(flow_area(d)), " m^2")
    print(io, "\n  hydraulic diameter  ", r(hydraulic_diameter(d)), " m")
    print(io, "\n  heated              ", r(d.heated[1]), " m left, ", r(d.heated[2]), " m right")
end

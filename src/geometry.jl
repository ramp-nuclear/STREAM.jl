"""
    AbstractShape

The cross-section of a [`Duct`](@ref): [`Rectangular`](@ref), [`Circular`](@ref),
[`Annular`](@ref), or [`Effective`](@ref) for one known only by its area and perimeter.

A new shape defines [`flow_area`](@ref), [`wetted_perimeter`](@ref) and [`walls`](@ref).
Correlations that only hold for one shape dispatch on it, as `Duct{<:Rectangular}`.
"""
abstract type AbstractShape end

"""
    _lengths(xs...) -> Tuple

Coerce lengths to one element type: `Float64` for a fixed geometry, or `Num` as soon as one of
them is a design knob, so the geometry derives symbolically.
"""
_lengths(xs...) = any(x -> x isa Num, xs) ? map(Num, xs) : map(Float64, xs)

"""
    _ordered(a, b) -> (larger, smaller)

Two lengths, larger first. `ifelse` rather than `max` and `min`, so a knob-driven length
orders correctly at whatever value the knob takes.
"""
_ordered(a, b) = (ifelse(a >= b, a, b), ifelse(a >= b, b, a))

"""
    Rectangular(edge1, edge2) <: AbstractShape

A rectangular cross-section, such as the gap between two fuel plates. The edges go in either
order: `width` is the longer and `depth` the shorter. Either may be a design knob.

Its heatable walls are the two long ones, `left` and `right`.

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
        width, depth = _ordered(_lengths(edge1, edge2)...)
        return new{typeof(width)}(width, depth)
    end
end

"""
    Circular(D) <: AbstractShape

A circular cross-section of diameter `D` [m], which may be a design knob. Its one wall is
`outer`.

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
    Annular(D1, D2) <: AbstractShape

The ring between two concentric circles, such as the coolant gap around a fuel rod in a tube.
The diameters go in either order: `D_in` is the smaller and `D_out` the larger. Either may be
a design knob. Its walls are `inner` and `outer`.

# Arguments
- `D1`, `D2`: the two diameters [m]

# Returns
An `Annular` with fields `D_in` and `D_out`.

# Examples
```jldoctest
julia> hydraulic_diameter(Annular(0.016, 0.010))
0.006
```
"""
struct Annular{T<:Real} <: AbstractShape
    D_in::T
    D_out::T
    function Annular(D1::Real, D2::Real)
        D_out, D_in = _ordered(_lengths(D1, D2)...)
        return new{typeof(D_in)}(D_in, D_out)
    end
end

"""
    Effective(; area, wetted_perimeter) <: AbstractShape

A cross-section known only by its flow area [m²] and wetted perimeter [m], as Python STREAM's
`EffectivePipe` takes them. Its walls are whatever its duct names as heated. Correlations that
need a shape's edges do not accept it.

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

"""
    walls(shape) -> NamedTuple

The walls of a shape that can be heated, by name, with each one's width [m].
[`Effective`](@ref) has no fixed walls and returns `nothing`.

# Examples
```jldoctest
julia> walls(Annular(0.010, 0.016))
(inner = 0.031415926535897934, outer = 0.05026548245743669)
```
"""
walls(s::Rectangular) = (left=s.width, right=s.width)
walls(s::Circular) = (outer=π * s.D,)
walls(s::Annular) = (inner=π * s.D_in, outer=π * s.D_out)
walls(::Effective) = nothing

@doc raw"""
    Duct(L, shape; heated)

A straight duct of length `L` and constant cross-section, heated over some of its walls.

Each heated wall is one face of a channel built on the duct, with its own wall temperature
and heat flow, named after the wall: `left` and `right` for a rectangle, `outer` for a
circle, `inner` and `outer` for an annulus. A wall left out of `heated` is not heated, and
the channel gives it no face. The defaults heat both long walls of a rectangle across their
width, a circle's whole wall, and an annulus's inner wall, the rod. An [`Effective`](@ref)
duct has no default.

```math
D_h = 4A / P_{wet}
```

Any length may be a design knob (see [`@design_knob`](@ref)).

# Arguments
- `L`: length [m]
- `shape`: the cross-section, an [`AbstractShape`](@ref)
- `heated`: the heated width of each heated wall [m], as a named tuple such as
  `(left=0.063, right=0.063)`. A number gives every default wall that width.

# Returns
A `Duct` with fields `L`, `shape` and `heated`. [`flow_area`](@ref),
[`hydraulic_diameter`](@ref), [`wetted_perimeter`](@ref) and [`heated_perimeter`](@ref) give
the rest.

# Throws
- `ArgumentError`: for a wall the shape does not have, or a heated width that is not
  positive or is wider than its wall

# Examples
A 70 mm by 1.27 mm MTR channel, 0.6 m long, and the same channel heated on one side:
```jldoctest
julia> d = Duct(0.6, Rectangular(0.07, 0.00127))
Duct, 0.6 m long, Rectangular(0.07, 0.00127)
  flow area           8.89e-5 m^2
  hydraulic diameter  0.0024947 m
  heated              0.07 m left, 0.07 m right

julia> Duct(0.6, Rectangular(0.07, 0.00127); heated=(left=0.063,)).heated
(left = 0.063,)
```
"""
struct Duct{S<:AbstractShape,T<:Real,H<:NamedTuple}
    L::T
    shape::S
    heated::H
end

function Duct(L::Real, shape::AbstractShape; heated=_default_heated(shape))
    faces = heated isa Real ? map(_ -> heated, _default_heated(shape)) : heated
    faces isa NamedTuple ||
        throw(ArgumentError("`heated` is a named tuple of widths, such as (left=0.063,)"))
    _check_heated(shape, faces)
    L, widths... = _lengths(L, values(faces)...)
    return Duct(L, shape, NamedTuple{keys(faces)}(widths))
end

_default_heated(s::AbstractShape) = walls(s)
_default_heated(s::Annular) = (inner=π * s.D_in,)
_default_heated(s::Effective) =
    throw(ArgumentError("an Effective duct needs `heated`, naming its heated walls"))

"""
    _check_heated(shape, heated)

Throw an `ArgumentError` for a heated wall the shape does not have, or a fixed heated width
that is not positive or is wider than its wall. A knob-driven width is not checked.
"""
function _check_heated(shape, heated)
    available = walls(shape)
    for (wall, width) in pairs(heated)
        if available !== nothing && !haskey(available, wall)
            throw(ArgumentError("$(nameof(typeof(shape))) has no wall :$wall to heat; " *
                                "its walls are $(join(repr.(keys(available)), ", "))"))
        end
        (width isa Num || available isa Nothing || available[wall] isa Num) && continue
        0 < width <= available[wall] * (1 + 1e-12) || throw(ArgumentError(
            "heated width $width of wall :$wall is outside (0, $(available[wall])]"))
    end
end

"""
    flow_area(x) -> m^2

The flow area of a [`Duct`](@ref) or of its shape.
"""
flow_area(s::Rectangular) = s.width * s.depth
flow_area(s::Circular) = π * s.D^2 / 4
flow_area(s::Annular) = π * (s.D_out^2 - s.D_in^2) / 4
flow_area(s::Effective) = s.area
flow_area(d::Duct) = flow_area(d.shape)

"""
    wetted_perimeter(x) -> m

The perimeter the coolant wets, of a [`Duct`](@ref) or of its shape.
"""
wetted_perimeter(s::Rectangular) = 2 * (s.width + s.depth)
wetted_perimeter(s::Circular) = π * s.D
wetted_perimeter(s::Annular) = π * (s.D_out + s.D_in)
wetted_perimeter(s::Effective) = s.wetted_perimeter
wetted_perimeter(d::Duct) = wetted_perimeter(d.shape)

"""
    hydraulic_diameter(x) -> m

`4A / P_wet`, of a [`Duct`](@ref) or of its shape. A circle's is its diameter, and an
annulus's the difference of its two.
"""
hydraulic_diameter(s::AbstractShape) = 4 * flow_area(s) / wetted_perimeter(s)
hydraulic_diameter(s::Circular) = s.D
hydraulic_diameter(s::Annular) = s.D_out - s.D_in
hydraulic_diameter(d::Duct) = hydraulic_diameter(d.shape)

"""
    heated_perimeter(d::Duct) -> m

The heated width of every heated wall together.
"""
heated_perimeter(d::Duct) = sum(values(d.heated); init=zero(d.L))

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
Base.show(io::IO, s::Annular) = print(io, "Annular(", s.D_in, ", ", s.D_out, ")")
Base.show(io::IO, s::Effective) =
    print(io, "Effective(; area=", s.area, ", wetted_perimeter=", s.wetted_perimeter, ")")

function Base.show(io::IO, ::MIME"text/plain", d::Duct)
    r(x) = x isa Real && !(x isa Num) ? round(x; sigdigits=5) : x
    print(io, "Duct, ", r(d.L), " m long, ", d.shape)
    print(io, "\n  flow area           ", r(flow_area(d)), " m^2")
    print(io, "\n  hydraulic diameter  ", r(hydraulic_diameter(d)), " m")
    faces = ["$(r(w)) m $f" for (f, w) in pairs(d.heated)]
    print(io, "\n  heated              ", isempty(faces) ? "nowhere" : join(faces, ", "))
end

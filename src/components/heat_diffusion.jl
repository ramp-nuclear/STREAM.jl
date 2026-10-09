"""
    Slab(; x, z, y, material, x_contacts=Inf, z_contacts=Inf)

A plate for [`HeatDiffusion`](@ref): its mesh, its material and the contacts inside it. `x` runs
into the plate, through its thickness, and `z` runs along it, in the direction of the flow.
`y` is the third direction, across which nothing is told apart: temperature, power and the
coolant beside the plate are all single valued along it. For an MTR plate with 1D flow, `y`
is the plate width spanning the channel.

# Arguments
- `x`: the `nx + 1` cell boundaries through the plate [m]. A uniform mesh is
  `Lx .* (0:nx) ./ nx`, which stays symbolic for a design knob.
- `z`: the `nz + 1` cell boundaries along the plate [m]
- `y`: length of the plate along `y` [m], Python's `y_length`
- `material`: a [`Solid`](@ref), or an `nz × nx` matrix of them for a clad plate
- `x_contacts`: contact conductance [W/(m²K)] on the faces normal to `x`, anything that
  broadcasts to `nz × (nx+1)`. `Inf` is perfect contact. A row such as `[Inf 5e3 Inf Inf]`
  puts a gap on one interface along the whole length.
- `z_contacts`: the same for the faces normal to `z`, broadcasting to `(nz+1) × nx`

# Returns
A `Slab`.

# Throws
`DimensionMismatch` when a material matrix does not have one entry per cell.
"""
struct Slab{X<:AbstractVector,Z<:AbstractVector,Y<:Real,M,CX,CZ}
    x::X
    z::Z
    y::Y
    material::M
    x_contacts::CX
    z_contacts::CZ
end

Slab(; x::AbstractVector, z::AbstractVector, y::Real, material, x_contacts=Inf, z_contacts=Inf) =
    Slab(x, z, y, _materials(material, x, z), x_contacts, z_contacts)

"""
    Cylinder(; r, z, material, r_contacts=Inf, z_contacts=Inf)

A rod or an annulus for [`HeatDiffusion`](@ref), with azimuthal symmetry: its mesh, its
material and the contacts inside it. Radii starting at `r = 0` make a solid rod, anything else
an annulus.

# Arguments
- `r`: the `nr + 1` cell boundaries along the radius [m]
- `z`: the `nz + 1` cell boundaries along the axis [m]
- `material`: a [`Solid`](@ref), or an `nz × nr` matrix of them, such as pellet and cladding
- `r_contacts`: contact conductance [W/(m²K)] on the faces normal to `r`, anything that
  broadcasts to `nz × (nr+1)`, such as a pellet-clad gap. `Inf` is perfect contact.
- `z_contacts`: the same for the faces normal to `z`, broadcasting to `(nz+1) × nr`

# Returns
A `Cylinder`.

# Throws
`DimensionMismatch` when a material matrix does not have one entry per cell.
"""
struct Cylinder{R<:AbstractVector,Z<:AbstractVector,M,CR,CZ}
    r::R
    z::Z
    material::M
    r_contacts::CR
    z_contacts::CZ
end

Cylinder(; r::AbstractVector, z::AbstractVector, material, r_contacts=Inf, z_contacts=Inf) =
    Cylinder(r, z, _materials(material, r, z), r_contacts, z_contacts)

"""
    _materials(material, x, z) -> Matrix{<:Solid}

`material` as one `Solid` per cell of the mesh with boundaries `x` and `z`.
"""
function _materials(material, x, z)
    cells = (length(z) - 1, length(x) - 1)
    material isa Solid && return fill(material, cells)
    size(material) == cells ||
        throw(DimensionMismatch("material is $(size(material)), the mesh has $cells cells"))
    return material
end

"""
    _mesh(body) -> (x, z)

The cell boundaries of a body, with the radius as `x` for a [`Cylinder`](@ref).
"""
_mesh(b::Slab) = (b.x, b.z)
_mesh(b::Cylinder) = (b.r, b.z)

"""
    _contacts(body) -> (x_contacts, z_contacts)

The contact conductances of a body, with the radial ones as `x_contacts` for a
[`Cylinder`](@ref).
"""
_contacts(b::Slab) = (b.x_contacts, b.z_contacts)
_contacts(b::Cylinder) = (b.r_contacts, b.z_contacts)

"""
    _areas_volumes(body) -> (Ax, Az, V)

Face areas and cell volumes: `Ax` is `nz × (nx+1)`, one per face normal to `x`, `Az` is
`(nz+1) × nx`, and `V` is `nz × nx`. These are Python's `x_diffusion` and
`cylindrical_areas_volumes`.
"""
function _areas_volumes(b::Slab)
    dx = permutedims(diff(b.x))
    return b.y .* diff(b.z) .* one.(permutedims(b.x)), b.y .* one.(b.z) .* dx,
           b.y .* diff(b.z) .* dx
end

function _areas_volumes(b::Cylinder)
    ring = π .* permutedims(diff(b.r .^ 2))
    return 2π .* diff(b.z) .* permutedims(b.r), one.(b.z) .* ring, diff(b.z) .* ring
end

"""
    _has_inner_wall(body) -> Bool

Whether the `x[1]` side is a surface. The axis of a solid rod is not: it has no area, so a port
there would carry no heat and leave its temperature undetermined.
"""
_has_inner_wall(::Slab) = true
_has_inner_wall(b::Cylinder) = !isequal(first(b.r), 0)

@doc raw"""
    HeatDiffusion(body; name, axial=false, power_shape=nothing, power=nothing,
                  T0=T_ROOM) -> System

Heat conduction in a [`Slab`](@ref) or a [`Cylinder`](@ref) on its 2D finite-volume mesh. This
is Python STREAM's `Fuel`.

Each cell balances its heat content against conduction through its faces and its share of
the power:

```math
ρ c_p V dT/dt = \sum_f A_f (T_f - T) / R_f + P s
```

where `T_f` is the temperature on the far side of face `f` and `R_f` the resistance per unit
area between the two: half of each cell's width over its conductivity, plus the face's
contact resistance `1/h`. An outer face conducts to the temperature on its port over half a
cell. Conduction across `x` is always on, and along `z` with `axial=true`.

# Arguments
- `body`: a [`Slab`](@ref) or a [`Cylinder`](@ref)
- `name`: system name (Symbol)
- `axial`: conduct along `z` as well (default `false`, each axial slice independent)
- `power_shape`: `s`, the fraction of `power` in each cell, an `nz × nx` matrix used as given,
  so cladding cells hold zero. The default `nothing` is a uniform power density, each cell's
  share being its volume over the body's.
- `power`: `P`, the total power [W]. A number makes it the parameter `power`, which `remake`
  can change. `nothing` (the default) makes it an unknown the caller binds, such as
  `rods.fuel.power ~ pk.P * power_scale` for a plate driven by point kinetics.
- `T0`: initial temperature of every cell [°C]

# Ports
- `thermal_left[1:nz]` at `x[1]`, absent for a solid rod, and `thermal_right[1:nz]` at `x[end]`
- with `axial=true`, `thermal_top[1:nx]` at `z[1]` and `thermal_bottom[1:nx]` at `z[end]`

A port left unconnected is adiabatic.

# Returns
Uncompiled `System` with the cell temperatures `T[1:nz, 1:nx]`.
"""
function HeatDiffusion(body::Union{Slab,Cylinder}; name, axial::Bool=false, power_shape=nothing,
                       power=nothing, T0=T_ROOM)
    (x, z), (x_contacts, z_contacts) = _mesh(body), _contacts(body)
    nx, nz = length(x) - 1, length(z) - 1
    Ax, Az, V = _areas_volumes(body)
    power_shape === nothing && (power_shape = V ./ sum(V))

    @variables (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
    # The @variables / @parameters below rebind `power` to the symbol of that name.
    power_given = power
    power_given isa Union{Real,Nothing} ||
        throw(ArgumentError("power must be a number or nothing, got $(typeof(power_given))"))
    if power_given === nothing
        @variables power(t)
    else
        @parameters power = power_given
    end

    ports(side, n) = [ThermalPort(; name=Symbol(:thermal_, side, i)) for i in 1:n]
    κs = κ.(body.material)
    # (dims, ports at the start, ports at the end, face areas, cell widths along dims, contacts)
    across = (2, ports(:left, _has_inner_wall(body) ? nz : 0), ports(:right, nz), Ax,
              permutedims(diff(x)), x_contacts)
    along = (1, ports(:top, nx), ports(:bottom, nx), Az, diff(z), z_contacts)
    directions = axial ? (across, along) : (across,)

    T = collect(T)
    eqs, net = Equation[], zeros(nz, nx)
    for (dims, lo, hi, A, Δ, contacts) in directions
        q, port_eqs = _conduction(T, lo, hi, A, Δ ./ 2κs, contacts, dims)
        append!(eqs, port_eqs)
        net = net .+ diff(q; dims)
    end
    C = ρ.(body.material) .* cₚ.(body.material) .* V
    append!(eqs, vec(D.(T) .~ (net .+ power .* power_shape) ./ C))
    walls = reduce(vcat, [[lo; hi] for (_, lo, hi) in directions])
    return assembly(eqs, walls...; name=name)
end

"""
    _conduction(T, lo, hi, A, R_cell, contacts, dims) -> (q, eqs)

Heat flow [W] through every face along dimension `dims` of the cell temperatures `T`, the two
outer faces included, and the equations for the heat the ports `lo` (at the start of `dims`)
and `hi` (at its end) pass in. `A` holds the face areas and `R_cell` each cell's
centre-to-face resistance per unit area.

With no `lo` ports, as on a solid rod's axis, the first cell stands in for the wall, so that
face carries no heat. "cylinder given heat production and wall temperature" in
`test_heat_diffusion.jl` covers it.
"""
function _conduction(T, lo, hi, A, R_cell, contacts, dims)
    edge = size(selectdim(T, dims, 1:1))
    T_lo = isempty(lo) ? selectdim(T, dims, 1:1) : reshape(port(lo, :T), edge)
    T_hi = reshape(port(hi, :T), edge)
    # Python's flux sign: positive where heat runs toward the lower index.
    q = A .* diff(cat(T_lo, T, T_hi; dims); dims) ./ _face_resistances(R_cell, contacts, dims)
    eqs = port(hi, :Q) .~ vec(selectdim(q, dims, size(q, dims)))
    isempty(lo) || append!(eqs, port(lo, :Q) .~ -vec(selectdim(q, dims, 1)))
    return q, eqs
end

"""
    _face_resistances(R_cell, contacts, dims) -> Array

Resistance per unit area [m²K/W] of every face along dimension `dims`, the two outer ones
included. A face sums `R_cell`, the centre-to-face resistance, of the cells on either side,
one at an outer face, and adds `1 ./ contacts`, so perfect contact adds nothing. This is
Python's `_resistances`.
"""
function _face_resistances(R_cell, contacts, dims)
    outside = zero(selectdim(R_cell, dims, 1:1))
    R = cat(outside, R_cell, outside; dims)
    n = size(R, dims)
    return selectdim(R, dims, 1:(n - 1)) .+ selectdim(R, dims, 2:n) .+ inv.(contacts)
end

"""
    Slab(depth)

Cartesian geometry for [`HeatDiffusion`](@ref): `x` crosses the plate, `z` runs along it, and
the plate is uniform over `depth` [m] in the third direction.

# Arguments
- `depth`: extent of the plate in the direction neither mesh axis covers [m]

# Returns
A `Slab`, passed as `HeatDiffusion(; geometry=Slab(depth), ...)`.
"""
struct Slab{T}
    depth::T
end

"""
    Cylinder()

Cylindrical geometry for [`HeatDiffusion`](@ref) with azimuthal symmetry: `x` is the radius and
`z` the axial position. Boundaries starting at `x = 0` make a solid rod, anything else an
annulus.

# Returns
A `Cylinder`, passed as `HeatDiffusion(; geometry=Cylinder(), ...)`.
"""
struct Cylinder end

"""
    _areas_volumes(geometry, x, z) -> (Ax, Az, V)

Face areas and cell volumes for the mesh with boundaries `x` and `z`: `Ax` is `nz × (nx+1)`,
one per face normal to `x`, `Az` is `(nz+1) × nx`, and `V` is `nz × nx`. These are Python's
`x_diffusion` and `cylindrical_areas_volumes`.
"""
function _areas_volumes(g::Slab, x, z)
    dx = permutedims(diff(x))
    return g.depth .* diff(z) .* one.(permutedims(x)), g.depth .* one.(z) .* dx,
           g.depth .* diff(z) .* dx
end

function _areas_volumes(::Cylinder, r, z)
    ring = π .* permutedims(diff(r .^ 2))
    return 2π .* diff(z) .* permutedims(r), one.(z) .* ring, diff(z) .* ring
end

"""
    _has_inner_wall(geometry, x) -> Bool

Whether the `x[1]` side is a surface. The axis of a solid rod is not: it has no area, so a port
there would carry no heat and leave its temperature undetermined.
"""
_has_inner_wall(::Slab, x) = true
_has_inner_wall(::Cylinder, r) = !isequal(first(r), 0)

"""
    _face_resistances(half, contacts, dims) -> Matrix

Thermal resistance per unit area [m²K/W] across every face along dimension `dims`, the outer
two included. `half` holds each cell's half-width over its conductivity. An inner face sums
the halves of the cells either side, an outer face takes one, and every face adds
`1 ./ contacts`, so an infinite contact conductance adds nothing. This is Python's
`_resistances`.
"""
function _face_resistances(half, contacts, dims)
    pad = zero(selectdim(half, dims, 1:1))
    padded = cat(pad, half, pad; dims=dims)
    n = size(padded, dims)
    return selectdim(padded, dims, 1:(n - 1)) .+ selectdim(padded, dims, 2:n) .+ inv.(contacts)
end

"""
    HeatDiffusion(; name, x, z, material, geometry=Slab(1.0), axial=false,
                  x_contacts=Inf, z_contacts=Inf, power_shape=nothing, power=nothing,
                  T0=T_ROOM) -> System

Heat conduction in a solid on a 2D finite-volume mesh: a plate or a rod, uniform in the third
direction. This is Python STREAM's `Fuel`.

Each cell's energy balance is

    ρ cₚ V dT/dt = Σ A (T_neighbour - T) / R + power * power_shape

over its faces, where `R` is the resistance between the two cell centres: half of each cell's
width over its conductivity, plus the contact resistance `1/h` of the face between them. An
outer face conducts to the temperature on its port in the same way, over half a cell. Lateral
conduction across `x` is always on; axial conduction along `z` is on with `axial=true`.

# Arguments
- `name`: system name (Symbol)
- `x`: the `nx + 1` cell boundaries across the plate, or the radii for a [`Cylinder`](@ref)
  [m]. A uniform mesh is `Lx .* (0:nx) ./ nx`, which stays symbolic for a design knob.
- `z`: the `nz + 1` cell boundaries along the plate [m]
- `material`: a [`Solid`](@ref), or an `nz × nx` matrix of them for a clad plate
- `geometry`: [`Slab`](@ref) (default, depth 1 m) or [`Cylinder`](@ref)
- `axial`: conduct along `z` as well (default `false`, each axial slice independent)
- `x_contacts`: contact conductance [W/(m²K)] on the faces normal to `x`, anything that
  broadcasts to `nz × (nx+1)`. The default `Inf` is perfect contact. A row such as
  `[Inf 5e3 Inf Inf]` puts a gap on one interface along the whole length.
- `z_contacts`: the same for faces normal to `z`, broadcasting to `(nz+1) × nx`
- `power_shape`: fraction of `power` in each cell, an `nz × nx` matrix used as given, so
  cladding cells hold zero. The default `nothing` spreads it evenly over every cell.
- `power`: total power [W]. A number makes it the parameter `power`, which `remake` can
  change. `nothing` (the default) makes it an unknown the caller binds, such as
  `rods.fuel.power ~ pk.P * power_scale` for a plate driven by point kinetics.
- `T0`: initial temperature of every cell [°C]

# Ports
- `thermal_left[1:nz]` at `x[1]`, absent for a solid rod, and `thermal_right[1:nz]` at `x[end]`
- with `axial=true`, `thermal_top[1:nx]` at `z[1]` and `thermal_bottom[1:nx]` at `z[end]`

A port left unconnected is adiabatic.

# Returns
Uncompiled `System` with the cell temperatures `T[1:nz, 1:nx]`.
"""
function HeatDiffusion(;
    name,
    x,
    z,
    material,
    geometry=Slab(1.0),
    axial::Bool=false,
    x_contacts=Inf,
    z_contacts=Inf,
    power_shape=nothing,
    power=nothing,
    T0=T_ROOM,
)
    nx, nz = length(x) - 1, length(z) - 1
    Ax, Az, V = _areas_volumes(geometry, x, z)
    material isa Solid && (material = fill(material, nz, nx))
    power_shape === nothing && (power_shape = fill(1 / (nz * nx), nz, nx))

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
    thermal_left = _has_inner_wall(geometry, x) ? ports(:left, nz) : nothing
    thermal_right = ports(:right, nz)
    walls = thermal_left === nothing ? thermal_right : [thermal_left; thermal_right]
    T = collect(T)
    κs = κ.(material)

    # Python's flux sign: positive where heat runs toward the lower index.
    T_left = thermal_left === nothing ? T[:, 1] : port(thermal_left, :T)
    qx = Ax .* diff(hcat(T_left, T, port(thermal_right, :T)); dims=2) ./
         _face_resistances(permutedims(diff(x)) ./ 2κs, x_contacts, 2)
    eqs = [
        port(thermal_right, :Q) .~ qx[:, end]
        thermal_left === nothing ? Equation[] : port(thermal_left, :Q) .~ -qx[:, 1]
    ]
    net = diff(qx; dims=2)

    if axial
        thermal_top, thermal_bottom = ports(:top, nx), ports(:bottom, nx)
        T_ends = permutedims.((port(thermal_top, :T), port(thermal_bottom, :T)))
        qz = Az .* diff(vcat(T_ends[1], T, T_ends[2]); dims=1) ./
             _face_resistances(diff(z) ./ 2κs, z_contacts, 1)
        append!(eqs, [port(thermal_top, :Q) .~ -qz[1, :]; port(thermal_bottom, :Q) .~ qz[end, :]])
        walls = [walls; thermal_top; thermal_bottom]
        net = net .+ diff(qz; dims=1)
    end

    C = ρ.(material) .* cₚ.(material) .* V
    append!(eqs, vec(D.(T) .~ (net .+ power .* power_shape) ./ C))
    return assembly(eqs, walls...; name=name)
end

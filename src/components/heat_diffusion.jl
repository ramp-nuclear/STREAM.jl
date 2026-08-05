# heat_diffusion.jl — conduction in a solid, on a mesh.
#
# The component states one equation per cell, built by walking the mesh's face lists. Each
# face contributes a term to the two cells it separates, so a cell's equation has as many
# terms as it has neighbours and no more, whatever the mesh looks like.
#
# Boundary faces group by tag, one thermal port per (tag, axial layer). The port's heat
# flow is the sum over its group, which is the reduction that lets a boundary of any shape
# meet a channel carrying a single wall temperature per axial cell.

# Accumulate the flux terms per cell, then emit one equation each. Summing a vector at the
# end gives Symbolics a flat `+` node instead of a chain nested as deep as the neighbour
# count.
function _mesh_eqs(; T, mesh, materials, ports, power, power_shape)
    nz = nlayers(mesh)
    nc = ncross(mesh)
    cross = mesh.cross
    terms = [Num[] for _ in 1:nz, _ in 1:nc]

    for iz in 1:nz
        for f in cross.faces
            g = interior_conductance(mesh, materials, f, iz)
            push!(terms[iz, f.c1], g * (T[iz, f.c2] - T[iz, f.c1]))
            push!(terms[iz, f.c2], g * (T[iz, f.c1] - T[iz, f.c2]))
        end
        for b in cross.boundary
            g = boundary_conductance(mesh, materials, b, iz)
            push!(terms[iz, b.c], g * (ports[b.tag][iz].T - T[iz, b.c]))
        end
    end

    if mesh.axial
        for iz in 1:(nz - 1), ic in 1:nc
            g = axial_conductance(mesh, materials, ic, iz)
            push!(terms[iz, ic], g * (T[iz + 1, ic] - T[iz, ic]))
            push!(terms[iz + 1, ic], g * (T[iz, ic] - T[iz + 1, ic]))
        end
    end

    eqs = Equation[]
    groups = boundary_groups(cross)
    for (tag, idxs) in groups, iz in 1:nz
        port = ports[tag][iz]
        flow = [boundary_conductance(mesh, materials, cross.boundary[i], iz) *
                (port.T - T[iz, cross.boundary[i].c]) for i in idxs]
        push!(eqs, port.Q ~ sum(flow))
    end
    for iz in 1:nz, ic in 1:nc
        rhs = (sum(terms[iz, ic]) + power * power_shape[iz, ic]) /
              heat_capacity(mesh, materials, iz, ic)
        push!(eqs, D(T[iz, ic]) ~ rhs)
    end
    return eqs
end

function _heat_diffusion(mesh, materials, power_shape, power_init, T0, name)
    nz = nlayers(mesh)
    nc = ncross(mesh)
    size(power_shape) == (nz, nc) || throw(ArgumentError(
        "power_shape must be $(nz)x$(nc) to match the mesh, got $(size(power_shape))"))
    maximum(mesh.cross.material) <= length(materials) || throw(ArgumentError(
        "the mesh uses material index $(maximum(mesh.cross.material)) but only " *
        "$(length(materials)) materials were given"))

    vars = @variables begin
        (T(t))[1:nz, 1:nc] = fill(T0, nz, nc)
        power(t) = power_init
    end
    T_var, power_var = vars

    ports = Dict(tag => [ThermalPort(; name=Symbol(:thermal_, tag, iz)) for iz in 1:nz]
                 for tag in tags(mesh))

    eqs = _mesh_eqs(; T=T_var, mesh=mesh, materials=materials, ports=ports,
                    power=power_var, power_shape=power_shape)
    all_vars = vcat(vec(collect(T_var)), [power_var])
    flat = reduce(vcat, [ports[tag] for tag in tags(mesh)]; init=System[])
    return compose(System(eqs, t, all_vars, []; name=name), flat...)
end

"""
    HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape,
                  power=1e6, T0=326.85, axial=false) -> System

Conduction in a flat plate, `nz` axial cells by `nx` lateral cells, cooled on both lateral
faces.

# Arguments
- `name`: system name (Symbol)
- `nz`: number of axial cells (Int)
- `nx`: number of lateral cells (Int)
- `Lz`: axial length [m]
- `Lx`: lateral thickness [m]
- `y`: plate depth [m] (into-page dimension)
- `rho_s`: solid density [kg/m^3]
- `cp_s`: solid specific heat [J/(kg*K)]
- `k_s`: thermal conductivity [W/(m*K)]
- `power_shape`: `(nz, nx)` matrix giving each cell's share of `power`, not normalized
  internally
- `power`: total power into the plate [W], an MTK variable that must be constrained by a
  connection equation (`fuel.power ~ 1e4`, or `rods.fuel.power ~ pk.P * scale`)
- `T0`: initial temperature [°C], default 326.85 (600 K)
- `axial`: whether heat conducts between axial layers. Off by default, which leaves the
  layers thermally independent and matches what this component has always done.

# Ports
- `thermal_left[1:nz]`, `thermal_right[1:nz]` — `ThermalPort` arrays (no FlowPorts)

# Returns
Uncompiled `System`.
"""
function HeatDiffusion(; name, nz::Int, nx::Int, Lz, Lx, y, rho_s, cp_s, k_s,
                       power_shape, power=1e6, T0=326.85, axial::Bool=false)
    dx = Lx / nx
    dz = Lz / nz
    # Built term by term rather than with `range`, which cannot take a symbolic endpoint
    # and so would break the design-knob path.
    cross = slab_cross_section([(j - 1) * dx for j in 1:(nx + 1)], y)
    mesh = extrude(cross, [(i - 1) * dz for i in 1:(nz + 1)]; axial=axial)
    return _heat_diffusion(mesh, [SolidMaterial(rho_s, cp_s, k_s)], power_shape,
                           power, T0, name)
end

"""
    HeatDiffusion(mesh::SolidMesh; name, materials, power_shape, power=1e6,
                  T0=326.85) -> System

Conduction on any mesh, with three-dimensional heat flow: in-plane within each axial layer,
and between layers when the mesh carries axial faces.

Dispatch is on the positional `mesh` because two keyword-only methods would be the same
method, silently overwriting each other.

# Arguments
- `mesh`: a [`SolidMesh`](@ref), from `extrude` of a cross-section
- `name`: system name (Symbol)
- `materials`: `Vector{SolidMaterial}` indexed by the mesh's per-cell material index
- `power_shape`: `(nlayers, ncross)` matrix giving each cell's share of `power`. Free to
  vary both in-plane and axially, so an axial cosine and a radial profile compose.
- `power`: total power into the solid [W], an MTK variable the caller must constrain
- `T0`: initial temperature [°C]

# Ports
One `ThermalPort` per boundary tag per axial layer, named `thermal_<tag><i>`. The port's
heat flow is the sum over every mesh face in that group, so a boundary of any shape meets a
channel that carries one wall temperature per axial cell.

Refining the mesh in-plane therefore buys interior detail, not peak-wall-temperature
detail: the model reports a face-averaged wall temperature per tag, because the channel it
talks to has only one bulk temperature.

# Returns
Uncompiled `System`.
"""
function HeatDiffusion(mesh::SolidMesh; name, materials::AbstractVector{<:SolidMaterial},
                       power_shape, power=1e6, T0=326.85)
    return _heat_diffusion(mesh, materials, power_shape, power, T0, name)
end

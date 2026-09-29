"""
    _diffusion_eqs(; T, thermal_left, thermal_right, nz, nx, k_s, rho_s, cp_s,
                   dx, dz, y, power, power_shape) -> Vector{Equation}

The finite-difference stencil behind [`HeatDiffusion`](@ref), as a flat list of equations over an
`nz × nx` grid of solid cells.

Four groups, in build order. Two give the heat flow through each `ThermalPort`, over a half-cell
conduction distance `dx/2` from port to first cell centre. Two give the boundary columns their
energy balance, conducting to one interior neighbour and to the port. The last is the three-point
interior stencil.

Volumetric heating is `power * power_shape` spread over a cell's mass. `power_shape` is not
normalized here.

There is no axial conduction: the plate conducts across its thickness and each axial slice is
independent.
"""
function _diffusion_eqs(;
    T,
    thermal_left,
    thermal_right,
    nz,
    nx,
    k_s,
    rho_s,
    cp_s,
    dx,
    dz,
    y,
    power,
    power_shape,
)
    q_vol = power .* power_shape / (rho_s * cp_s * y * dz * dx)

    return [
        [
            thermal_left[i].Q ~
                k_s * (y * dz) * (thermal_left[i].T - T[i, 1]) / (dx / 2) for i in 1:nz
        ]...  # Left heat flux
        [
            thermal_right[i].Q ~
                k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2) for i in 1:nz
        ]...  # Right heat flux
        [
            D(T[i, 1]) ~
                (
                    k_s * (T[i, 2] - T[i, 1]) / dx  # Left cell temperature equation
                    -
                    k_s * (T[i, 1] - thermal_left[i].T) / (dx / 2)
                ) / (rho_s * cp_s * dx) + q_vol[i, 1] for i in 1:nz
        ]...
        [
            D(T[i, nx]) ~
                (
                    k_s * (T[i, nx - 1] - T[i, nx]) / dx  # Right cell temperature equation
                    -
                    k_s * (T[i, nx] - thermal_right[i].T) / (dx / 2)
                ) / (rho_s * cp_s * dx) + q_vol[i, nx] for i in 1:nz
        ]...
        [
            D(T[i, j]) ~
                k_s * (T[i, j + 1] - 2 * T[i, j] + T[i, j - 1]) / (dx^2 * rho_s * cp_s) +
                q_vol[i, j] for i in 1:nz for j in 2:(nx - 1)
        ]...
    ]
end

"""
    HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s,
                  power_shape=uniform, power=nothing, T0=T_ROOM) -> System

2D finite-difference heat diffusion plate with axial (`nz`) and lateral (`nx`) cells.

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
- `power_shape`: fraction of the power in each cell, an `(nz, nx)` matrix used as given
  (default uniform, `1/(nz*nx)` everywhere)
- `power`: total power into the plate [W]. A number makes it the parameter `power`, which
  `remake` can change. `nothing` (the default) makes it an unknown the caller binds, such as
  `rods.fuel.power ~ pk.P * power_scale` for a plate driven by point kinetics.
- `T0`: initial temperature of every cell [°C]

# Ports
- `thermal_left[1:nz]`, `thermal_right[1:nz]` -- `ThermalPort` arrays (no FlowPorts)

# Returns
Uncompiled `System`.
"""
function HeatDiffusion(;
    name,
    nz::Int,
    nx::Int,
    Lz,
    Lx,
    y,
    rho_s,
    cp_s,
    k_s,
    power_shape=fill(1.0 / (nz * nx), nz, nx),
    power=nothing,
    T0=T_ROOM,
)
    dx = Lx / nx
    dz = Lz / nz

    @variables (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
    # The @variables / @parameters below rebind `power` to the symbol of that name.
    power_given = power
    power_given isa Union{Real,Nothing} ||
        throw(ArgumentError("power must be a number or nothing, got $(typeof(power_given))"))
    if power_given === nothing
        @variables power(t)
        vars, pars = [vec(collect(T)); power], []
    else
        @parameters power = power_given
        vars, pars = vec(collect(T)), [power]
    end

    thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:nz]
    thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:nz]

    eqs = _diffusion_eqs(;
        T=T,
        thermal_left=thermal_left,
        thermal_right=thermal_right,
        nz=nz,
        nx=nx,
        k_s=k_s,
        rho_s=rho_s,
        cp_s=cp_s,
        dx=dx,
        dz=dz,
        y=y,
        power=power,
        power_shape=power_shape,
    )
    return compose(
        System(eqs, t, vars, pars; name=name), thermal_left..., thermal_right...
    )
end

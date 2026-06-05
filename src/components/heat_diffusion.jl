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
            thermal_left[i].Q_flow ~
                k_s * (y * dz) * (thermal_left[i].T - T[i, 1]) / (dx / 2) for i in 1:nz
        ]...  # Left heat flux
        [
            thermal_right[i].Q_flow ~
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
    HeatDiffusion(; name, nz, nx, Lz, Lx, y, rho_s, cp_s, k_s, power_shape, power=1e6, T0=600.0) -> ODESystem

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
- `power_shape`: axial-lateral power shape matrix of size `(nz, nx)` (not normalized internally)
- `power`: total power into plate [W], MTK variable — must be constrained via a connection equation
  (e.g. `fuel.power ~ 1e4` for standalone use, or `rods.fuel.power ~ pk.P * scale` for PK-coupled use)
- `T0`: initial temperature [K], default 600.0

# Ports
- `thermal_left[1:nz]`, `thermal_right[1:nz]` -- `ThermalPort` arrays (no FlowPorts)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
#! format: off
function HeatDiffusion(; name,
                         nz::Int, nx::Int,
                         Lz, Lx, y,
                         rho_s, cp_s, k_s,
                         power_shape,
                         power  = 1e6,
                         T0     = 600.0)
#! format: on
    power_init = power
    dx = Lx / nx
    dz = Lz / nz

    vars = @variables begin
        (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
        power(t) = power_init
    end

    thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:nz]
    thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:nz]

    T_var, power_var = vars
    #! format: off
    eqs = _diffusion_eqs(;
        T             = T_var,
        thermal_left  = thermal_left,
        thermal_right = thermal_right,
        nz            = nz,
        nx            = nx,
        k_s           = k_s,
        rho_s         = rho_s,
        cp_s          = cp_s,
        dx            = dx,
        dz            = dz,
        y             = y,
        power         = power_var,
        power_shape   = power_shape)

    #! format: on
    all_vars = vcat(vec(collect(T_var)), [power_var])
    return compose(
        System(eqs, t, all_vars, []; name=name), thermal_left..., thermal_right...
    )
end

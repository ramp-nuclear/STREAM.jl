# heat_diffusion.jl — _diffusion_eqs helper and HeatDiffusion component for STREAM.jl

# ─── Phase 11: HeatDiffusion helper and constructor ───────────────────────────
#
# _diffusion_eqs: appends FD heat diffusion equations for a 2D solid fuel plate.
# Called by HeatDiffusion before assembling the MTK System.
#
# Appends (per axial cell i in 1:nz):
#   thermal_left[i].Q_flow  — heat flux INTO hd at left face (positive = into hd; negative for heated plate)
#   thermal_right[i].Q_flow — heat flux INTO hd at right face (positive = into hd; negative for heated plate)
# Appends (per cell [i,j] in 1:nz × 1:nx):
#   Dt(T[i,j]) — temperature ODE with x-direction FD diffusion + volumetric source
#
# No z-diffusion terms — top/bottom adiabatic by omission.
# power_shape[i,j] is NOT normalised internally.
#
# v0.4 note: add dz, kz arguments here for axial (z) diffusion (DIFF-01).
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
    Dt,
)
    q_vol = power .* power_shape / (rho_s * cp_s * y * dz * dx)

    return [
        collect([thermal_left[i].Q_flow ~ k_s * (y * dz) * (thermal_left[i].T - T[i, 1]) / (dx / 2) for i in 1:nz])  # Left heat flux 
        collect([thermal_right[i].Q_flow ~ k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2) for i in 1:nz])  # Right heat flux
        collect([Dt(T[i, 1]) ~ (k_s * (T[i, 2] - T[i, 1]) / dx  # Left cell temperature equation
                -
                k_s * (T[i, 1] - thermal_left[i].T) / (dx / 2)) /
                (rho_s * cp_s * dx) + q_vol[i, 1] for i in 1:nz])
        collect([Dt(T[i, 1]) ~ (k_s * (T[i, 2] - T[i, 1]) / dx  # Right cell temperature equation
                -
                k_s * (T[i, nx] - thermal_right[i].T) / (dx / 2)) /
                (rho_s * cp_s * dx) + q_vol[i, nx] for i in 1:nz])
        collect([Dt(T[i, j]) ~ k_s * (T[i, j+1] - 2 * T[i, j] + T[i, j-1]) / (dx^2 * rho_s * cp_s) + q_vol[i, j] for i in 1:nz for j in 2:nx-1])
    ]
end

# HeatDiffusion: 2D finite-difference solid fuel plate with x-direction diffusion only (v0.3).
# State T(t)[1:nz, 1:nx]: row i = axial cell (index 1 = inlet/top), col j = lateral cell.
# thermal_left[1:nz], thermal_right[1:nz]: ThermalPort arrays for coupling to coolant channels.
# Material properties (rho_s, cp_s, k_s) are plain Float64 — not MTK parameters (v0.3).
# power: MTK @parameters (tunable via remake()), total watts into the plate.
# power_shape[nz, nx]: user-supplied spatial distribution — NOT normalized internally.
# Top/bottom boundaries are adiabatic by omission of z-diffusion equations.
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
    Dt = Differential(t)
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
        power_shape   = power_shape,
        Dt            = Dt)

    #!format: on
    all_vars = vcat(vec(collect(T_var)), [power_var])
    compose(System(eqs, t, all_vars, []; name=name),
            thermal_left..., thermal_right...)
end

# components.jl — Thermal-hydraulic components for STREAM.jl
#
# Design note (q_wall indirection):
# Channel uses a single ThermalPort carrying total Q_wall (W), then splits
# internally: q_wall[i] = thermal.Q_flow / n per cell. This indirection
# exists so that a future refactor to per-cell ThermalPorts only changes
# the port declaration and q_wall binding — the energy balance loop
# D(T[i]) ~ ... is untouched.
#
# Note: `Channel` is declared as a new generic function here to avoid
# conflict with Base.Channel (Julia's built-in concurrency channel type).

"""
    PipeGeometry

Geometry descriptor for a heated channel or pipe.

Fields:
- `L`                — channel length [m]
- `Dh`               — hydraulic diameter [m]: 4*area/wet_perimeter; drives Re, Nu, h_tc, Darcy-Weisbach dP
- `A`                — flow cross-section area [m²]
- `heated_perimeter` — total heated perimeter [m]: sum of both face contributions
- `wet_perimeter`    — total wetted perimeter [m]: used to derive Dh
- `heated_parts`     — heated perimeter per face [m]: (left_face, right_face)

Factory functions (preferred constructors):
- `PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)` — rectangular channel
- `PipeGeometry_circular(L, D)` — circular pipe

Do NOT call the inner positional constructor directly.
"""
struct PipeGeometry
    L                ::Float64                   # channel length [m]
    Dh               ::Float64                   # hydraulic diameter [m]: 4*area/wet_perimeter
    A                ::Float64                   # flow cross-section area [m²]
    heated_perimeter ::Float64                   # total heated perimeter [m]
    wet_perimeter    ::Float64                   # total wetted perimeter [m]
    heated_parts     ::NTuple{2,Float64}         # heated perimeter per face [m]: (left, right)
end

"""
    PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)

Construct a `PipeGeometry` for a rectangular channel.

- `L`            — channel length [m]
- `edge1`        — first cross-section edge [m] (e.g. plate width)
- `edge2`        — second cross-section edge [m] (e.g. channel gap)
- `heated_edge`  — width of each heated face [m]
- `one_sided`    — `:left`, `:right`, or `nothing` (default, both sides heated)

Dh = 4*area/wet_perimeter where area = edge1*edge2 and wet_perimeter = 2*(edge1+edge2).
"""
function PipeGeometry_rectangular(L, edge1, edge2, heated_edge; one_sided=nothing)
    _L    = Float64(L)
    _e1   = Float64(edge1)
    _e2   = Float64(edge2)
    _he   = Float64(heated_edge)
    area          = _e1 * _e2
    wet_perimeter = 2.0 * (_e1 + _e2)
    Dh            = 4.0 * area / wet_perimeter
    if one_sided === nothing
        heated_perimeter = 2.0 * _he
        heated_parts     = (_he, _he)
    elseif one_sided === :left
        heated_perimeter = _he
        heated_parts     = (_he, 0.0)
    elseif one_sided === :right
        heated_perimeter = _he
        heated_parts     = (0.0, _he)
    else
        error("one_sided must be :left, :right, or nothing; got $one_sided")
    end
    PipeGeometry(_L, Dh, area, heated_perimeter, wet_perimeter, heated_parts)
end

"""
    PipeGeometry_circular(L, D)

Construct a `PipeGeometry` for a circular pipe.

- `L` — channel length [m]
- `D` — pipe diameter [m]

Dh = D (exact for circular cross-section). heated_parts = (π*D/2, π*D/2) (symmetric split).
"""
function PipeGeometry_circular(L, D)
    _L         = Float64(L)
    _D         = Float64(D)
    area       = π * _D^2 / 4
    perimeter  = π * _D
    heated_parts = (perimeter / 2, perimeter / 2)
    # Dh = 4*(π*D²/4)/(π*D) = D — exact
    PipeGeometry(_L, _D, area, perimeter, perimeter, heated_parts)
end

# Declare as new generic functions independent of Base
function Channel end
function Channel(; name, n::Int, geometry::PipeGeometry, g = 0.0)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)  # explicit Differential operator

    pars = @parameters begin
        L     = L
        D_h   = Dh
        A     = A
        g_acc = g    # gravitational acceleration (m/s²); 0 for horizontal, 9.80665 for vertical
    end

    vars = @variables begin
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    @named thermal  = ThermalPort()

    dz = L / n

    eqs = Equation[]
    T_inlet = instream(port_in.T)

    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        # Energy balance (first-order upwind FV)
        push!(eqs,
            Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * sum(geometry.heated_parts) * dz * (thermal.T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        # Observables
        push!(eqs, q_wall[i] ~ thermal.Q_flow / n)
        push!(eqs, v[i]      ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i]     ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
        push!(eqs, Nu[i]     ~ 0.023 * Re[i]^0.8 *
                                (cp_water(T[i]) * mu_water(T[i]) / k_water(T[i]))^0.4)
        push!(eqs, h_tc[i]  ~ Nu[i] * k_water(T[i]) / Dh)
    end

    # Scalar observables
    i_mid = max(1, n ÷ 2)   # middle cell for mean-property dP
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = 0.3164 * Re_mean^(-0.25)
    push!(eqs, T_out ~ T[n])
    push!(eqs, dP    ~ f_ch * (port_in.mdot * abs(port_in.mdot) /
                                (2 * rho_water(T[i_mid]) * A^2)) * (L / Dh)
                      + rho_water(T[i_mid]) * g_acc * L)

    # Port wiring
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_out.P - port_in.P ~ -dP)
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ instream(port_out.T))

    all_vars = [collect(T); collect(Re); collect(Nu);
                collect(h_tc); collect(v); collect(q_wall);
                T_out; dP]

    compose(System(eqs, t, all_vars, pars; name=name), port_in, port_out, thermal)
end

function Pump(; name, dP_pump)
    pars = @parameters begin
        dP_pump = dP_pump
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_out.P - port_in.P ~ dP_pump,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

function Friction(; name, L, D, A)
    pars = @parameters begin
        L   = L
        D_h = D
        A   = A
    end
    vars = @variables begin
        Re(t)
        f(t)
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        Re ~ abs(port_in.mdot) * D / (A * mu_water(T_in)),
        f  ~ 0.3164 * Re^(-0.25),
        port_in.P - port_out.P ~ f * (port_in.mdot * abs(port_in.mdot) /
                                       (2 * rho_water(T_in) * A^2)) * (L / D),
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, vars, pars; name=name), port_in, port_out)
end

function Gravity(; name, H)
    pars = @parameters H = H
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

function Resistor(; name, R)
    pars = @parameters R = R
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ R * port_in.mdot,
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# Inertia (COMP-01): fluid inertia as ODE pressure-drop term
# Equation: port_in.P - port_out.P ~ L_over_A * D(mdot)
# L_over_A = L/A [m/m² = m⁻¹] — user pre-computes from geometry
# No explicit mdot state variable needed — MTK auto-promotes port_in.mdot
# as a differential state because it appears inside Dt(port_in.mdot).
function Inertia(; name, L_over_A)
    Dt   = Differential(t)           # same operator used in Channel energy balance
    pars = @parameters L_over_A = L_over_A
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ L_over_A * Dt(port_in.mdot),   # ODE pressure eq
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# HeatExchanger (COMP-02): temperature boundary condition as a public component.
# Injects a fixed outlet temperature T_bc into the downstream stream, breaking
# the circular thermal dependency in closed loops (where instream() would
# otherwise resolve to the previous component's outlet T).
# 4-equation structure: mass conservation, no pressure drop, T_bc outlet, adiabatic inlet.
function HeatExchanger(; name, T_bc)
    pars = @parameters T_bc = T_bc
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,    # mass conservation
        port_in.P   - port_out.P    ~ 0,     # no pressure drop
        port_out.T  ~ T_bc,                   # inject fixed outlet temperature
        port_in.T   ~ instream(port_out.T),   # backward stream (adiabatic)
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# ─── Phase 9: shared base equations helper ────────────────────────────────────
#
# _channel_base_eqs: appends ~4n + 6 equations common to all heated channel
# variants. Called by ChannelAndContacts and ChannelHeatFlux before each
# appends its own thermal coupling loop.
#
# Appends (per-cell, i in 1:n):
#   v[i], Re[i], Nu[i], h_tc[i]
# Appends (scalar):
#   T_out ~ T[n], dP (Darcy-Weisbach + gravity)
# Appends (port wiring):
#   mass conservation, pressure drop, port_out.T, port_in.T
#
# Does NOT append energy balance equations — those differ per variant.
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    port_in, port_out,
    Dh, A, L, g_acc, dz)

    for i in 1:n
        push!(eqs, v[i]    ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i]   ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
        push!(eqs, Nu[i]   ~ 0.023 * Re[i]^0.8 *
                              (cp_water(T[i]) * mu_water(T[i]) / k_water(T[i]))^0.4)
        push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / Dh)
    end

    # Scalar: pressure drop and T_out
    i_mid   = max(1, n ÷ 2)
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = 0.3164 * Re_mean^(-0.25)
    push!(eqs, T_out ~ T[n])
    push!(eqs, dP    ~ f_ch * (port_in.mdot * abs(port_in.mdot) /
                                (2 * rho_water(T[i_mid]) * A^2)) * (L / Dh)
                      + rho_water(T[i_mid]) * g_acc * L)

    # Port wiring (4 equations — identical across all channel variants)
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_out.P - port_in.P       ~ -dP)
    push!(eqs, port_out.T                   ~ T[n])
    push!(eqs, port_in.T                    ~ instream(port_out.T))
end

# ChannelAndContacts (THERM-01/CHAN-01/CHAN-02): heated channel with dual per-cell ThermalPort arrays.
# Each thermal_left[i] and thermal_right[i] carry wall temperature and heat flow for cell i.
# Two-sided heating models both fuel plate faces: geometry.heated_parts[1] (left), geometry.heated_parts[2] (right).
# This is the interface that HeatDiffusion (v0.3) will connect to.
#
# Port layout:
#   port_in, port_out        — FlowPorts (hydraulic)
#   thermal_left1..N         — ThermalPorts (left wall face, one per axial cell)
#   thermal_right1..N        — ThermalPorts (right wall face, one per axial cell)
#
# Energy balance (cell i):
#   Dt(T[i]) ~ (mdot * cp * (T_up - T[i])
#               + h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
#               + h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i]))
#              / (rho * cp * A * dz)
#
# Observables:
#   q_wall[i]    — per-cell total heat transfer rate (W); q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow
#   Q_wall_total — total heat transfer rate (W); sum over all cells
function ChannelAndContacts(; name, n::Int, geometry::PipeGeometry, g = 0.0)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    pars = @parameters begin
        L     = L
        D_h   = Dh
        A     = A
        g_acc = g
    end

    vars = @variables begin
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t)         = 600.0
        dP(t)
        Q_wall_total(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    # Dual per-cell ThermalPort arrays — Phase 10 two-sided interface
    thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:n]
    thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]

    dz      = L / n
    eqs     = Equation[]
    T_inlet = instream(port_in.T)

    # Common equations: v, Re, Nu, h_tc, dP, T_out, port wiring
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      port_in, port_out, Dh, A, L, g_acc=g, dz)

    # Per-cell energy balance: two-sided heating (geometry.heated_parts[1]/[2] per face)
    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
                       + h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        # Port heat flow equations: Q_flow INTO channel from each wall face
        # When unconnected (adiabatic), T_wall = T[i] => Q_flow = 0
        push!(eqs, thermal_left[i].Q_flow  ~ h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i]))
        push!(eqs, thermal_right[i].Q_flow ~ h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i]))
        push!(eqs, q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow)
    end

    push!(eqs, Q_wall_total ~ sum(q_wall[i] for i in 1:n))

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); T_out; dP; Q_wall_total]

    compose(System(eqs, t, all_vars, pars; name=name),
            port_in, port_out, thermal_left..., thermal_right...)
end

# ChannelHeatFlux (THERM-03): heated channel with T_wall as a scalar parameter.
# No ThermalPorts — T_wall is baked into the energy balance equations.
# Intended for testing and simple simulations where T_wall is known a priori.
# For HeatDiffusion coupling, use ChannelAndContacts instead.
#
# T_wall (scalar): uniform wall temperature applied to all n cells.
# q_wall[i]: per-cell heat transfer rate computed directly (no port).
#
# When T_wall is uniform, ChannelHeatFlux is algebraically equivalent to
# Channel with thermal.T pinned to T_wall. THERM-03 validates this within 0.1%.
function ChannelHeatFlux(; name, n::Int, geometry::PipeGeometry, g = 0.0, T_wall)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    pars = @parameters begin
        L        = L
        D_h      = Dh
        A        = A
        g_acc    = g
        T_wall_p = T_wall   # scalar wall temperature parameter (K)
    end

    vars = @variables begin
        (T(t))[1:n]      = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        T_out(t)         = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz      = L / n
    eqs     = Equation[]
    T_inlet = instream(port_in.T)

    # Common equations: v, Re, Nu, h_tc, dP, T_out, port wiring
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      port_in, port_out, Dh, A, L, g_acc=g, dz)

    # Per-cell energy balance using T_wall_p parameter
    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * sum(geometry.heated_parts) * dz * (T_wall_p - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ h_tc[i] * sum(geometry.heated_parts) * dz * (T_wall_p - T[i]))
    end

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); T_out; dP]

    compose(System(eqs, t, all_vars, pars; name=name), port_in, port_out)
end

# ConstantTemperature: pins a ThermalPort's temperature to a fixed parameter.
# Used as a thermal boundary condition in tests and simple simulations.
# MTK acausal semantics solve for Q_flow from the connected component's balance.
function ConstantTemperature(; name, T)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end

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
function _diffusion_eqs(eqs::Vector{Equation};
    T, thermal_left, thermal_right,
    nz, nx, k_s, rho_s, cp_s, dx, dz, y, power, power_shape, Dt)

    for i in 1:nz
        # Left boundary Q_flow: heat flux INTO hd at left face (positive = into component).
        # When plate is hotter than boundary: Q_flow_left < 0 (heat leaving plate).
        # Formula: k * (T_bc - T_plate) / (dx/2), negative when T_plate > T_bc.
        push!(eqs, thermal_left[i].Q_flow ~
            k_s * (y * dz) * (thermal_left[i].T - T[i, 1]) / (dx / 2))

        # Right boundary Q_flow: heat flux INTO hd at right face (positive = into component).
        # When plate is hotter than boundary: Q_flow_right < 0 (heat leaving plate).
        # Formula: k * (T_bc - T_plate) / (dx/2), negative when T_plate > T_bc.
        push!(eqs, thermal_right[i].Q_flow ~
            k_s * (y * dz) * (thermal_right[i].T - T[i, nx]) / (dx / 2))
    end

    for i in 1:nz
        for j in 1:nx
            # Volumetric heat source (W/m³ → K/s after dividing by rho*cp*volume)
            # Volume of cell [i,j] = y * dz * dx (depth * axial * lateral)
            q_vol = power * power_shape[i, j] / (rho_s * cp_s * y * dz * dx)

            if j == 1
                # Left boundary cell: left neighbor is virtual at thermal_left[i].T,
                # half a dx away from cell centre. Right flux over full dx.
                push!(eqs, Dt(T[i, 1]) ~
                    (k_s * (T[i, 2] - T[i, 1]) / dx
                     - k_s * (T[i, 1] - thermal_left[i].T) / (dx / 2)) /
                    (rho_s * cp_s * dx) + q_vol)
            elseif j == nx
                # Right boundary cell: right neighbor is virtual at thermal_right[i].T,
                # half a dx away from cell centre. Left flux over full dx.
                push!(eqs, Dt(T[i, nx]) ~
                    (k_s * (thermal_right[i].T - T[i, nx]) / (dx / 2)
                     - k_s * (T[i, nx] - T[i, nx-1]) / dx) /
                    (rho_s * cp_s * dx) + q_vol)
            else
                # Interior cells: standard second-order FD stencil (LOCKED)
                push!(eqs, Dt(T[i, j]) ~
                    k_s * (T[i, j+1] - 2*T[i, j] + T[i, j-1]) / (dx^2 * rho_s * cp_s)
                    + q_vol)
            end
        end
    end
end

# HeatDiffusion: 2D finite-difference solid fuel plate with x-direction diffusion only (v0.3).
# State T(t)[1:nz, 1:nx]: row i = axial cell (index 1 = inlet/top), col j = lateral cell.
# thermal_left[1:nz], thermal_right[1:nz]: ThermalPort arrays for coupling to coolant channels.
# Material properties (rho_s, cp_s, k_s) are plain Float64 — not MTK parameters (v0.3).
# power: MTK @parameters (tunable via remake()), total watts into the plate.
# power_shape[nz, nx]: user-supplied spatial distribution — NOT normalized internally.
# Top/bottom boundaries are adiabatic by omission of z-diffusion equations.
function HeatDiffusion(; name,
                         nz::Int, nx::Int,
                         Lz, Lx, y,
                         rho_s, cp_s, k_s,
                         power_shape,
                         power  = 1e6,
                         T0     = 600.0)
    Dt = Differential(t)
    dx = Lx / nx
    dz = Lz / nz

    pars = @parameters begin
        power = power
    end

    vars = @variables begin
        (T(t))[1:nz, 1:nx] = fill(T0, nz, nx)
    end

    thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:nz]
    thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:nz]

    eqs = Equation[]
    _diffusion_eqs(eqs;
        T            = T,
        thermal_left  = thermal_left,
        thermal_right = thermal_right,
        nz = nz, nx = nx,
        k_s = k_s, rho_s = rho_s, cp_s = cp_s,
        dx = dx, dz = dz, y = y,
        power        = only(pars),
        power_shape  = power_shape,
        Dt           = Dt)

    all_vars = vec(collect(T))

    compose(System(eqs, t, all_vars, pars; name=name),
            thermal_left..., thermal_right...)
end

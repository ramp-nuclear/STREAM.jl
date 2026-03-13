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

# Declare as new generic functions independent of Base
function Channel end
function Channel(; name, n::Int, L, D, A, g = 0.0)
    # Rename plain-Julia D to Dh so it doesn't shadow Differential(t) operator
    Dh = D
    Dt = Differential(t)  # explicit Differential operator (avoids shadowing by D kwarg)

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
                       + h_tc[i] * (π * Dh) * dz * (thermal.T - T[i]))
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
# Two-sided heating models both fuel plate faces symmetrically (π*Dh/2 each side).
# This is the interface that HeatDiffusion (v0.3) will connect to.
#
# Port layout:
#   port_in, port_out        — FlowPorts (hydraulic)
#   thermal_left1..N         — ThermalPorts (left wall face, one per axial cell)
#   thermal_right1..N        — ThermalPorts (right wall face, one per axial cell)
#
# Energy balance (cell i):
#   Dt(T[i]) ~ (mdot * cp * (T_up - T[i])
#               + h_tc[i] * (π * Dh / 2) * dz * (thermal_left[i].T  - T[i])
#               + h_tc[i] * (π * Dh / 2) * dz * (thermal_right[i].T - T[i]))
#              / (rho * cp * A * dz)
#
# Observables:
#   q_wall[i]    — per-cell total heat transfer rate (W); q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow
#   Q_wall_total — total heat transfer rate (W); sum over all cells
function ChannelAndContacts(; name, n::Int, L, D, A, g = 0.0)
    Dh = D
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

    # Per-cell energy balance: two-sided heating (π*Dh/2 per side)
    for i in 1:n
        T_up = (i == 1) ? T_inlet : T[i-1]
        push!(eqs,
            Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * (π * Dh / 2) * dz * (thermal_left[i].T  - T[i])
                       + h_tc[i] * (π * Dh / 2) * dz * (thermal_right[i].T - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        # Port heat flow equations: Q_flow INTO channel from each wall face
        # When unconnected (adiabatic), T_wall = T[i] => Q_flow = 0
        push!(eqs, thermal_left[i].Q_flow  ~ h_tc[i] * (π * Dh / 2) * dz * (thermal_left[i].T  - T[i]))
        push!(eqs, thermal_right[i].Q_flow ~ h_tc[i] * (π * Dh / 2) * dz * (thermal_right[i].T - T[i]))
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
function ChannelHeatFlux(; name, n::Int, L, D, A, g = 0.0, T_wall)
    Dh = D
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
                       + h_tc[i] * (π * Dh) * dz * (T_wall_p - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ h_tc[i] * (π * Dh) * dz * (T_wall_p - T[i]))
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

# thermal_channel.jl — ChannelAndContacts and ChannelHeatFlux components for STREAM.jl

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
function ChannelAndContacts(; name, n::Int, geometry::PipeGeometry, g = 0.0,
                              htc_correlation      = dittus_boelter,
                              friction_correlation = blasius_friction)
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
        (T(t))[1:n]           = fill(600.0, n)
        (Re(t))[1:n]          # observed — hydraulic Reynolds number
        (Nu(t))[1:n]          # observed — Nusselt number
        (h_tc(t))[1:n]        # unknown  — HTC (referenced in energy balance)
        (v(t))[1:n]           # observed — alias for velocity
        (velocity(t))[1:n]    # observed — fluid velocity [m/s]
        (Pe(t))[1:n]          # observed — Peclet number
        (h_tc_left(t))[1:n]   # observed — HTC at left wall face
        (h_tc_right(t))[1:n]  # observed — HTC at right wall face
        (T_wall_left(t))[1:n]  # observed — alias for thermal_left[i].T
        (T_wall_right(t))[1:n] # observed — alias for thermal_right[i].T
        (q_wall_left(t))[1:n]  # observed — Q_flow from left face
        (q_wall_right(t))[1:n] # observed — Q_flow from right face
        (q_wall(t))[1:n]      # unknown  — per-cell total heat (referenced in Q_wall_total)
        T_out(t)              = 600.0
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

    # Common equations: h_tc (inlined, no Nu MTK symbol), dP, T_out, port wiring
    # observed_mode=true: Re/Nu/v equations are NOT pushed to eqs here
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dP,
                      port_in, port_out, Dh, A, L, g_acc=g, dz,
                      htc_correlation, friction_correlation,
                      observed_mode=true)

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

    # Build observed equations: Re, Nu, v, velocity, Pe, h_tc_left/right, T_wall_left/right,
    # q_wall_left/right — all expressed as Julia expressions of MTK unknowns.
    obs = Equation[]
    for i in 1:n
        Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(obs, Re[i]            ~ Re_i)
        push!(obs, Nu[i]            ~ htc_correlation(Re_i, Pr_i))
        push!(obs, v[i]             ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(obs, velocity[i]      ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(obs, Pe[i]            ~ Re_i * Pr_i)
        push!(obs, h_tc_left[i]    ~ h_tc[i])
        push!(obs, h_tc_right[i]   ~ h_tc[i])
        push!(obs, T_wall_left[i]  ~ thermal_left[i].T)
        push!(obs, T_wall_right[i] ~ thermal_right[i].T)
        push!(obs, q_wall_left[i]  ~ thermal_left[i].Q_flow)
        push!(obs, q_wall_right[i] ~ thermal_right[i].Q_flow)
    end

    # Re, Nu, v are now observed (not solver unknowns)
    all_vars = [collect(T); collect(h_tc); collect(q_wall); T_out; dP; Q_wall_total]

    compose(System(eqs, t, all_vars, pars; observed=obs, name=name),
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
function ChannelHeatFlux(; name, n::Int, geometry::PipeGeometry, g = 0.0, T_wall,
                           htc_correlation      = dittus_boelter,
                           friction_correlation = blasius_friction)
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
                      port_in, port_out, Dh, A, L, g_acc=g, dz,
                      htc_correlation, friction_correlation)

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

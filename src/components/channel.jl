# channel.jl — Channel component and _channel_base_eqs helper for STREAM.jl

# Declare as new generic functions independent of Base
function Channel end
function Channel(; name, n::Int, geometry::PipeGeometry, g = 0.0,
                   htc_correlation      = dittus_boelter,
                   friction_correlation = blasius_friction)
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
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(eqs, Nu[i]     ~ htc_correlation(Re[i], Pr_i))
        push!(eqs, h_tc[i]  ~ Nu[i] * k_water(T[i]) / Dh)
    end

    # Scalar observables
    i_mid = max(1, n ÷ 2)   # middle cell for mean-property dP
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = friction_correlation(Re_mean)
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
#
# Phase 15 note: When called from ChannelAndContacts, Re/Nu/v are NOT pushed
# to eqs here (they become observed variables instead). h_tc is still an
# unknown but with an inlined expression that does not reference Nu as MTK symbol.
# The `observed_mode` flag controls this behavior.
function _channel_base_eqs(eqs::Vector{Equation};
    n, T, Re, Nu, h_tc, v, T_out, dP,
    port_in, port_out,
    Dh, A, L, g_acc, dz,
    htc_correlation      = dittus_boelter,
    friction_correlation = blasius_friction,
    observed_mode        = false)

    for i in 1:n
        if observed_mode
            # Re, Nu, v become observed variables (not solver unknowns).
            # h_tc stays as unknown but uses inlined expression (avoids MTK observed-chain).
            Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
            push!(eqs, h_tc[i] ~ htc_correlation(Re_i, Pr_i) * k_water(T[i]) / Dh)
        else
            push!(eqs, v[i]    ~ port_in.mdot / (rho_water(T[i]) * A))
            push!(eqs, Re[i]   ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
            Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
            push!(eqs, Nu[i]   ~ htc_correlation(Re[i], Pr_i))
            push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / Dh)
        end
    end

    # Scalar: pressure drop and T_out
    i_mid   = max(1, n ÷ 2)
    Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))
    f_ch    = friction_correlation(Re_mean)
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

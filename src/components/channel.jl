# channel.jl — Channel component and _channel_base_eqs helper for STREAM.jl

# Declare as new generic functions independent of Base
function Channel end

"""
    Channel(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (PipeGeometry)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `htc_correlation`: HTC function `(Re, Pr, T_bulk, T_wall) -> Nu`, default `dittus_boelter`
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)
- `thermal` -- `ThermalPort` (single scalar wall temperature BC)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Channel(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    htc_correlation=dittus_boelter,
    friction_correlation=blasius_friction,
)
    Dh = geometry.Dh
    A = geometry.A
    L = geometry.L
    Dt = Differential(t)

    pars = @parameters begin
        L = L
        D_h = Dh
        A = A
        g_acc = g    # gravitational acceleration (m/s^2); 0 for horizontal, 9.80665 for vertical
    end

    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        (dp(t))[1:n] = fill(100.0, n)
        (P(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in = FlowPort()
    @named port_out = FlowPort()
    @named thermal = ThermalPort()

    dz = L / n

    eqs = Equation[]
    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    for i in 1:n
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
        # Energy balance (first-order upwind FV)
        # abs(port_in.mdot) ensures correct sign under reversed flow (mdot < 0):
        # the upwind temperature T_up is already selected for the correct direction,
        # so the advective flux is always |mdot|*cp*(T_upstream - T[i]).
        push!(
            eqs,
            Dt(T[i]) ~
            (
                abs(port_in.mdot) * cp_water(T[i]) * (T_up - T[i]) +
                h_tc[i] * sum(geometry.heated_parts) * dz * (thermal.T - T[i])
            ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz),
        )
        # Observables
        push!(eqs, q_wall[i] ~ thermal.Q_flow / n)
        push!(eqs, v[i] ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(eqs, Re[i] ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i, T[i], T[i]))
        push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / Dh)
    end

    # Per-cell pressure drop (D-02): friction + gravity, each using dz = L/n
    # Momentum inertia is handled by the momentum ODE below; dp[i] is algebraic (friction + gravity only).
    for i in 1:n
        Re_i_val = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        f_i = friction_correlation(Re_i_val)
        push!(
            eqs,
            dp[i] ~
            f_i *
            (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) *
            (dz / Dh) + rho_water(T[i]) * g_acc * dz,
        )
    end

    push!(eqs, T_out ~ T[n])

    # Port wiring
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(
        eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n)
    )
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T ~ T[1])

    # Observed equations: P[i] absolute pressure and dP alias (D-04, D-05, D-06)
    # P[i] includes distributed inertia correction: (i/n) * ((P_in - P_out) - sum_all_dp)
    # At steady state Dt(mdot)=0, the correction term vanishes and P[i] = P_in - cumsum(dp[1:i]).
    obs = Equation[]
    for i in 1:n
        P_i =
            port_in.P - sum(dp[j] for j in 1:i) -
            (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
        push!(obs, P[i] ~ P_i)
    end
    push!(obs, dP ~ port_in.P - port_out.P)

    all_vars = [
        collect(T);
        collect(Re);
        collect(Nu);
        collect(h_tc);
        collect(v);
        collect(q_wall);
        collect(dp);
        T_out
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name), port_in, port_out, thermal
    )
end

# --- Phase 9: shared base equations helper ---
#
# _channel_base_eqs: appends ~4n + 4 equations common to all heated channel
# variants. Called by ChannelAndContacts and ChannelHeatFlux before each
# appends its own thermal coupling loop.
#
# Appends (per-cell, i in 1:n):
#   v[i], Re[i], Nu[i], h_tc[i]  (when observed_mode=false)
#   h_tc[i] only                  (when observed_mode=true; Re/Nu/v become observed)
# Appends (per-cell):
#   dp[i] -- per-cell pressure drop (friction + gravity only)
# Appends (scalar):
#   T_out ~ T[n]
# Appends (port wiring):
#   mass conservation, momentum ODE (L/A)*Dt(mdot), port_out.T, port_in.T
#
# Does NOT append energy balance equations -- those differ per variant.
# The dP observed alias is NOT pushed here -- each caller builds its own obs list.
#
# Phase 15 note: When called from ChannelAndContacts, Re/Nu/v are NOT pushed
# to eqs here (they become observed variables instead). h_tc is still an
# unknown but with an inlined expression that does not reference Nu as MTK symbol.
# The `observed_mode` flag controls this behavior.
#
# Phase 27 note: When observed_mode=true, per-cell friction uses inlined Re_i
# expression (not Re[i] symbol) to avoid referencing an observed variable.
function _channel_base_eqs(
    eqs::Vector{Equation};
    n,
    T,
    Re,
    Nu,
    h_tc,
    v,
    T_out,
    dp,
    port_in,
    port_out,
    Dh,
    A,
    L,
    g_acc,
    dz,
    htc_correlation=dittus_boelter,
    friction_correlation=blasius_friction,
    observed_mode=false,
    T_wall_cells=nothing,
    skip_htc=false,
)
    for i in 1:n
        if observed_mode
            # Re, Nu, v become observed variables (not solver unknowns).
            # h_tc stays as unknown but uses inlined expression (avoids MTK observed-chain).
            # When skip_htc=true, h_tc[i] equations are NOT pushed here — caller provides them
            # (e.g. ChannelAndContacts with SCB correction pushes its own h_tc[i] equations).
            if !skip_htc
                Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
                Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
                T_w_i = T_wall_cells === nothing ? T[i] : T_wall_cells[i]
                push!(
                    eqs,
                    h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh,
                )
            end
        else
            push!(eqs, v[i] ~ port_in.mdot / (rho_water(T[i]) * A))
            push!(eqs, Re[i] ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i])))
            Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
            T_w_i = T_wall_cells === nothing ? T[i] : T_wall_cells[i]
            push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i, T[i], T_w_i))
            push!(eqs, h_tc[i] ~ Nu[i] * k_water(T[i]) / Dh)
        end
    end

    # Per-cell pressure drop (D-02, D-14): friction + gravity per cell
    # Momentum inertia is handled by the momentum ODE below; dp[i] is algebraic (friction + gravity only).
    for i in 1:n
        if observed_mode
            # In observed_mode, Re[i] is observed -- inline Re for friction (Pitfall 5)
            Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            f_i = friction_correlation(Re_i_for_friction)
        else
            f_i = friction_correlation(Re[i])
        end
        push!(
            eqs,
            dp[i] ~
            f_i *
            (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) *
            (dz / Dh) + rho_water(T[i]) * g_acc * dz,
        )
    end

    push!(eqs, T_out ~ T[n])

    # Port wiring (4 equations -- identical across all channel variants)
    Dt = Differential(t)
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(
        eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n)
    )
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T ~ T[1])
end

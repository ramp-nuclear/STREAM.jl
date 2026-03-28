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
#   P[i]         — per-cell absolute pressure (requires pressure anchor in loop)
#   T_sat[i]     — saturation temperature at P[i]
#   T_ONB[i]     — onset of nucleate boiling temperature at P[i]
"""
    ChannelAndContacts(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction, scb_correction=nothing) -> ODESystem

Convective channel with per-cell thermal contact arrays on both sides for conjugate heat transfer.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (PipeGeometry)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `htc_correlation`: HTC function `(Re, Pr, T_bulk, T_wall) -> Nu`, default `dittus_boelter`
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`
- `scb_correction`: optional SCB heat flux closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]`,
  e.g. from `regime_dependent_q_scb(pressure=...)`. When provided, h_tc[i] is enhanced by the
  Bergles-Rohsenow partial boiling factor when T_wall[i] >= T_ONB[i]. Default `nothing` (pure single-phase).

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)
- `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ChannelAndContacts(; name, n::Int, geometry::PipeGeometry, g = 0.0,
                              htc_correlation      = dittus_boelter,
                              friction_correlation = blasius_friction,
                              scb_correction       = nothing)
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
        (Re(t))[1:n]          # observed -- hydraulic Reynolds number
        (Nu(t))[1:n]          # observed -- Nusselt number
        (h_tc(t))[1:n]        # unknown  -- HTC (referenced in energy balance)
        (v(t))[1:n]           # observed -- alias for velocity
        (velocity(t))[1:n]    # observed -- fluid velocity [m/s]
        (Pe(t))[1:n]          # observed -- Peclet number
        (h_tc_left(t))[1:n]   # observed -- HTC at left wall face
        (h_tc_right(t))[1:n]  # observed -- HTC at right wall face
        (T_wall_left(t))[1:n]  # observed -- alias for thermal_left[i].T
        (T_wall_right(t))[1:n] # observed -- alias for thermal_right[i].T
        (q_wall_left(t))[1:n]  # observed -- Q_flow from left face
        (q_wall_right(t))[1:n] # observed -- Q_flow from right face
        (Gr_over_Re2(t))[1:n]  # observed -- Gr/Re^2 NC criterion
        (q_wall(t))[1:n]      # unknown  -- per-cell total heat (referenced in Q_wall_total)
        (dp(t))[1:n]          = fill(100.0, n)  # unknown  -- per-cell pressure drop
        (P(t))[1:n]           # observed -- per-cell absolute pressure
        (T_sat(t))[1:n]       # observed -- saturation temperature at P[i]
        (T_ONB(t))[1:n]       # observed -- onset of nucleate boiling temperature
        T_out(t)              = 600.0
        dP(t)                 # observed -- total pressure drop alias
        Q_wall_total(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    # Dual per-cell ThermalPort arrays -- Phase 10 two-sided interface
    thermal_left  = [ThermalPort(name=Symbol(:thermal_left, i))  for i in 1:n]
    thermal_right = [ThermalPort(name=Symbol(:thermal_right, i)) for i in 1:n]

    dz          = L / n
    eqs         = Equation[]
    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    # Common equations: h_tc (inlined, no Nu MTK symbol), dp[i], T_out, port wiring
    # observed_mode=true: Re/Nu/v equations are NOT pushed to eqs here
    # Build T_wall_cells from thermal_left ports for HTC computation
    _T_wall_cells = [thermal_left[i].T for i in 1:n]
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dp,
                      port_in, port_out, Dh, A, L, g_acc=g, dz,
                      htc_correlation, friction_correlation,
                      observed_mode=true,
                      T_wall_cells=_T_wall_cells,
                      skip_htc=(scb_correction !== nothing))

    # SCB-corrected h_tc[i] equations (ISCB-01): when scb_correction is provided,
    # h_tc[i] = ifelse(T_wall >= T_ONB, h_spl * partial_factor, h_spl).
    # All expressions are inlined (no observed-to-observed chains).
    if scb_correction !== nothing
        for i in 1:n
            Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
            T_w_i = thermal_left[i].T
            h_spl_i = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T[i]) / Dh

            # Inline P[i] expression (not the observed symbol) to avoid observed-to-observed chain
            P_i = port_in.P - sum(dp[j] for j in 1:i) - (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
            T_sat_i = sat_temperature(P_i)
            # max(q_spl, 0) guards _bergles_rohsenow_dT_ONB against DomainError:
            # during solver iteration q_spl can temporarily go negative, and
            # (negative)^(non-integer exponent) produces a DomainError.
            q_spl_i = max(h_spl_i * (T_w_i - T[i]), 0.0)

            q_scb_i = scb_correction(T_w_i, T_sat_i, Re_i)
            T_ONB_i = T_sat_i + _bergles_rohsenow_dT_ONB(P_i, q_spl_i)
            q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i)
            factor_i = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

            push!(eqs, h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i))
        end
    end

    # Per-cell energy balance: two-sided heating (geometry.heated_parts[1]/[2] per face)
    for i in 1:n
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i-1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i+1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
        push!(eqs,
            Dt(T[i]) ~ (abs(port_in.mdot) * cp_water(T[i]) * (T_up - T[i])
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
    # q_wall_left/right, Gr_over_Re2, P[i], T_sat[i], T_ONB[i], dP
    # All expressed as Julia expressions of MTK unknowns (no observed-to-observed chains).
    obs = Equation[]
    for i in 1:n
        Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(obs, Re[i]            ~ Re_i)
        push!(obs, Nu[i]            ~ htc_correlation(Re_i, Pr_i, T[i], thermal_left[i].T))
        push!(obs, v[i]             ~ port_in.mdot / (rho_water(T[i]) * A))
        push!(obs, velocity[i]      ~ abs(port_in.mdot) / (rho_water(T[i]) * A))
        push!(obs, Pe[i]            ~ Re_i * Pr_i)
        push!(obs, h_tc_left[i]    ~ h_tc[i])
        push!(obs, h_tc_right[i]   ~ h_tc[i])
        push!(obs, T_wall_left[i]  ~ thermal_left[i].T)
        push!(obs, T_wall_right[i] ~ thermal_right[i].T)
        push!(obs, q_wall_left[i]  ~ thermal_left[i].Q_flow)
        push!(obs, q_wall_right[i] ~ thermal_right[i].Q_flow)
        nu_i = mu_water(T[i]) / rho_water(T[i])
        Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
        push!(obs, Gr_over_Re2[i] ~ Gr_i / Re_i^2)
        # Per-cell absolute pressure, T_sat, T_ONB (D-05, D-06, D-11, D-12)
        # CRITICAL: Use P_i expression (not P[i] symbol) to avoid observed-to-observed chain
        P_i = port_in.P - sum(dp[j] for j in 1:i)
        push!(obs, P[i] ~ P_i)
        push!(obs, T_sat[i] ~ sat_temperature(P_i))
        q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)
        push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_spl_i))
    end
    # dP observed alias (D-04)
    push!(obs, dP ~ sum(dp[i] for i in 1:n))

    # Re, Nu, v are now observed (not solver unknowns)
    # dP, P[i], T_sat[i], T_ONB[i] are also observed
    all_vars = [collect(T); collect(h_tc); collect(q_wall); collect(dp); T_out; Q_wall_total]

    compose(System(eqs, t, all_vars, pars; observed=obs, name=name),
            port_in, port_out, thermal_left..., thermal_right...)
end

# ChannelHeatFlux (THERM-03): heated channel with T_wall as a scalar parameter.
# No ThermalPorts -- T_wall is baked into the energy balance equations.
# Intended for testing and simple simulations where T_wall is known a priori.
# For HeatDiffusion coupling, use ChannelAndContacts instead.
#
# T_wall (scalar): uniform wall temperature applied to all n cells.
# q_wall[i]: per-cell heat transfer rate computed directly (no port).
#
# When T_wall is uniform, ChannelHeatFlux is algebraically equivalent to
# Channel with thermal.T pinned to T_wall. THERM-03 validates this within 0.1%.
"""
    ChannelHeatFlux(; name, n, geometry, g=0.0, T_wall, htc_correlation=dittus_boelter, friction_correlation=blasius_friction) -> ODESystem

Convective channel with a fixed wall temperature applied uniformly to all cells.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (PipeGeometry)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `T_wall`: wall temperature [K]
- `htc_correlation`: HTC function `(Re, Pr, T_bulk, T_wall) -> Nu`, default `dittus_boelter`
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# Ports
- `port_in`, `port_out` -- `FlowPort` (pressure, mass flow, temperature)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
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
        (T(t))[1:n]           = fill(600.0, n)
        (Re(t))[1:n]
        (Nu(t))[1:n]
        (h_tc(t))[1:n]
        (v(t))[1:n]
        (q_wall(t))[1:n]
        (Gr_over_Re2(t))[1:n]
        (dp(t))[1:n]          = fill(100.0, n)  # unknown -- per-cell pressure drop
        (P(t))[1:n]           # observed -- per-cell absolute pressure
        (T_sat(t))[1:n]       # observed -- saturation temperature at P[i]
        (T_ONB(t))[1:n]       # observed -- onset of nucleate boiling temperature
        T_out(t)              = 600.0
        dP(t)                 # observed -- total pressure drop alias
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz          = L / n
    eqs         = Equation[]
    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    # Common equations: v, Re, Nu, h_tc, dp[i], T_out, port wiring
    # Pass T_wall_p as T_wall_cells so the htc_correlation receives the actual wall
    # temperature (needed for NC regime detection in regime_dependent: Gr/Re^2>1 check).
    _channel_base_eqs(eqs; n, T, Re, Nu, h_tc, v, T_out, dp,
                      port_in, port_out, Dh, A, L, g_acc=g, dz,
                      htc_correlation, friction_correlation,
                      T_wall_cells = fill(T_wall_p, n))

    # Per-cell energy balance using T_wall_p parameter
    for i in 1:n
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i-1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i+1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
        push!(eqs,
            Dt(T[i]) ~ (abs(port_in.mdot) * cp_water(T[i]) * (T_up - T[i])
                       + h_tc[i] * sum(geometry.heated_parts) * dz * (T_wall_p - T[i]))
                      / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )
        push!(eqs, q_wall[i] ~ h_tc[i] * sum(geometry.heated_parts) * dz * (T_wall_p - T[i]))
        nu_i = mu_water(T[i]) / rho_water(T[i])
        push!(eqs, Gr_over_Re2[i] ~ Gr(beta_water(T[i]), g_acc, T_wall_p - T[i], Dh, nu_i) / Re[i]^2)
    end

    # Observed equations: P[i], T_sat[i], T_ONB[i], dP (D-05, D-11, D-12)
    obs = Equation[]
    for i in 1:n
        P_i = port_in.P - sum(dp[j] for j in 1:i)
        push!(obs, P[i] ~ P_i)
        push!(obs, T_sat[i] ~ sat_temperature(P_i))
        q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)
        push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_spl_i))
    end
    push!(obs, dP ~ sum(dp[i] for i in 1:n))

    all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
                collect(v); collect(q_wall); collect(Gr_over_Re2); collect(dp); T_out]

    compose(System(eqs, t, all_vars, pars; observed=obs, name=name), port_in, port_out)
end

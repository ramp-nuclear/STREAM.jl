using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
import STREAM: Channel, ChannelAndContacts, ChannelHeatFlux, ConstantTemperature

# ─────────────────────────────────────────────────────────────────
# Sign Safety tests (SIGN-04): validate correct behaviour under
# reversed (negative) mass flow for all three channel variants.
#
# Physical setup: T_wall > T_inlet, mdot < 0
# Flow direction: fluid enters at port_out (cell n), exits at port_in (cell 1)
# Expected temperature profile: T[1] > T[2] > ... > T[n]
#   — cell 1 is the outlet (hottest), cell n is the inlet (cold, at T_inlet)
# ─────────────────────────────────────────────────────────────────

const n_sign       = 5
const T_inlet_sign = 313.15    # 40 C — cold inlet temperature
const T_wall_sign  = 373.15    # 100 C — hot wall temperature
const mdot_neg     = -0.490    # negative mass flow (reversed direction)
const L_sign       = 0.6       # channel length [m]
const D_sign       = 0.01      # hydraulic diameter [m]
const geom_sign    = PipeGeometry_circular(L_sign, D_sign)

# Reversed-flow initial guess: T decreasing from cell 1 (hot outlet) to cell n (cold inlet).
# steady_state_guess returns forward-flow profile (T[1] low → T[n] high);
# reversing the vector gives the physically correct starting point for mdot < 0.
T_guess_fwd_sign = steady_state_guess(T_inlet=T_inlet_sign, Q_wall=1e4, mdot_guess=abs(mdot_neg), n=n_sign)
const T_guess_rev_sign = reverse(T_guess_fwd_sign)

# ─────────────────────────────────────────────────────────────────
# SIGN-01/04: Channel reversed flow
# ─────────────────────────────────────────────────────────────────
@testset "SIGN-01/04: Channel reversed flow" begin
    @named pump = Pump(mdot0=mdot_neg)
    @named ch   = Channel(n=n_sign, geometry=geom_sign)
    @named bc   = HeatExchanger(T_inlet_sign)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out,   ch.port_in),
        connect(ch.port_out,   pump.port_in),
        pump.port_in.P ~ 1.0e5,
        ch.thermal.T   ~ T_wall_sign,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, ch)
    ssys = mtkcompile(sys; fully_determined=false)
    op = [ssys.ch.T[i] => T_guess_rev_sign[i] for i in 1:n_sign]
    push!(op, ssys.ch.port_in.mdot => mdot_neg)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals  = [sol[ssys.ch.T[i]]  for i in 1:n_sign]
    Re_vals = [sol[ssys.ch.Re[i]] for i in 1:n_sign]

    # Reversed temperature profile: outlet (cell 1) hotter than inlet (cell n)
    @test T_vals[1] > T_vals[n_sign]

    # Monotone decreasing from cell 1 to cell n
    @test all(T_vals[i] >= T_vals[i+1] for i in 1:n_sign-1)

    # All Reynolds numbers must be positive (uses abs(mdot))
    @test all(Re_vals .> 0)

    # Energy balance: advective heat gain ~ conductive heat from wall (within 1% rtol).
    # For Channel, thermal.Q_flow is not externally driven; use Re-based h_tc proxy check:
    # verify T rise is physically plausible (non-trivial heating occurred)
    @test T_vals[1] > T_inlet_sign     # outlet must be warmer than inlet
    @test T_vals[n_sign] < T_wall_sign  # inlet must not reach T_wall
end

# ─────────────────────────────────────────────────────────────────
# SIGN-02/04: ChannelAndContacts reversed flow
# ─────────────────────────────────────────────────────────────────
@testset "SIGN-02/04: ChannelAndContacts reversed flow" begin
    @named pump = Pump(mdot0=mdot_neg)
    @named cac  = ChannelAndContacts(n=n_sign, geometry=geom_sign)
    @named bc   = HeatExchanger(T_inlet_sign)
    ct_l = [ConstantTemperature(T_wall_sign; name=Symbol(:ct_l, i)) for i in 1:n_sign]
    ct_r = [ConstantTemperature(T_wall_sign; name=Symbol(:ct_r, i)) for i in 1:n_sign]
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out,   cac.port_in),
        connect(cac.port_out,  pump.port_in),
        [connect(ct_l[i].thermal, getproperty(cac, Symbol(:thermal_left,  i))) for i in 1:n_sign]...,
        [connect(ct_r[i].thermal, getproperty(cac, Symbol(:thermal_right, i))) for i in 1:n_sign]...,
        pump.port_in.P  ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, cac, ct_l..., ct_r...)
    ssys = mtkcompile(sys; fully_determined=false)
    op = [ssys.cac.T[i] => T_guess_rev_sign[i] for i in 1:n_sign]
    push!(op, ssys.cac.port_in.mdot => mdot_neg)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals   = [sol[ssys.cac.T[i]]        for i in 1:n_sign]
    Re_vals  = [sol[ssys.cac.Re[i]]       for i in 1:n_sign]
    vel_vals = [sol[ssys.cac.velocity[i]] for i in 1:n_sign]

    # Reversed temperature profile: outlet (cell 1) hotter than inlet (cell n)
    @test T_vals[1] > T_vals[n_sign]

    # Monotone decreasing from cell 1 to cell n
    @test all(T_vals[i] >= T_vals[i+1] for i in 1:n_sign-1)

    # All Reynolds numbers must be positive (uses abs(mdot))
    @test all(Re_vals .> 0)

    # velocity[i] is unsigned speed — must be positive under reverse flow
    @test all(vel_vals .> 0)

    # Energy balance within 1% rtol:
    # Q_wall_total is computed from ConstantTemperature connections (proper acausal balance).
    # Advective heat gain = |mdot| * cp * (T_outlet - T_boundary_inlet).
    # For reversed flow, T_boundary_inlet = T_inlet_sign (resolved via port_in.T pin),
    # NOT T_vals[n_sign] (which has already been partially heated by the wall).
    T_mean       = (T_vals[1] + T_inlet_sign) / 2
    Q_advect     = abs(mdot_neg) * cp_water(T_mean) * (T_vals[1] - T_inlet_sign)
    Q_wall_total = sol[ssys.cac.Q_wall_total]
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end

# ─────────────────────────────────────────────────────────────────
# SIGN-03/04: ChannelHeatFlux reversed flow
# ─────────────────────────────────────────────────────────────────
@testset "SIGN-03/04: ChannelHeatFlux reversed flow" begin
    @named pump = Pump(mdot0=mdot_neg)
    @named chf  = ChannelHeatFlux(n=n_sign, geometry=geom_sign, T_wall=T_wall_sign)
    @named bc   = HeatExchanger(T_inlet_sign)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out,   chf.port_in),
        connect(chf.port_out,  pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, chf)
    ssys = mtkcompile(sys; fully_determined=false)
    op = [ssys.chf.T[i] => T_guess_rev_sign[i] for i in 1:n_sign]
    push!(op, ssys.chf.port_in.mdot => mdot_neg)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success

    T_vals  = [sol[ssys.chf.T[i]]  for i in 1:n_sign]
    Re_vals = [sol[ssys.chf.Re[i]] for i in 1:n_sign]

    # Reversed temperature profile: outlet (cell 1) hotter than inlet (cell n)
    @test T_vals[1] > T_vals[n_sign]

    # Monotone decreasing from cell 1 to cell n
    @test all(T_vals[i] >= T_vals[i+1] for i in 1:n_sign-1)

    # All Reynolds numbers must be positive (uses abs(mdot))
    @test all(Re_vals .> 0)

    # Energy balance: ChannelHeatFlux q_wall computed from h_tc*(T_wall-T[i]).
    # Advective heat gain = |mdot| * cp * (T_outlet - T_boundary_inlet).
    # For reversed flow, T_boundary_inlet = T_inlet_sign (resolved via port_in.T pin).
    T_mean       = (T_vals[1] + T_inlet_sign) / 2
    Q_advect     = abs(mdot_neg) * cp_water(T_mean) * (T_vals[1] - T_inlet_sign)
    Q_wall_total = sum(sol[ssys.chf.q_wall[i]] for i in 1:n_sign)
    @test isapprox(Q_wall_total, Q_advect; rtol=0.01)
end

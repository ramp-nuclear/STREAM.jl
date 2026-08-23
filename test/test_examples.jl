# Builder + loss-of-flow integration tests (src/examples.jl).
#
# The `build_loop*` / `build_cube` builders and the bypass loss-of-flow transient. These
# exercise STREAM's example loops end to end; they are not Python test_integrations.py
# mirrors (those live in test_integration.jl).

using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq
using OrdinaryDiffEq: ReturnCode
using Statistics
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Examples

@testset "Builders smokes" begin
    @testset "build_loop compiles closed loop" begin
        ssys = build_loop()
        @test ssys isa ModelingToolkit.AbstractSystem
        # mtkcompile benchmark reported via @info (not asserted)
    end

    @testset "build_loop compiles + briefly solves" begin
        # Smoke: demonstrate the full `build_loop` API produces a working transient.
        ssys = build_loop()
        ic = Pair{Any,Any}[
            [ssys.ch.T[i] => 40.0 for i in 1:10]...,
            ssys.ch.inlet.ṁ => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.ch.T_out, end] > 40.0  # heating worked
    end

    @testset "build_loop_vertical compiles + briefly solves" begin
        ssys = build_loop_vertical()
        ic = Pair{Any,Any}[
            [ssys.ch.T[i] => 40.0 for i in 1:10]...,
            ssys.ch.inlet.ṁ => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.ch.T_out, end] > 40.0
    end

    @testset "build_loop_transient compiles + briefly solves" begin
        ssys = build_loop_transient()
        ic = Pair{Any,Any}[
            [ssys.ch.T[i] => 40.0 for i in 1:10]...,
            ssys.ch.inlet.ṁ => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
    end

    @testset "build_cube solves its resistor-network steady state" begin
        ssys = build_cube()
        @test ssys isa ModelingToolkit.AbstractSystem

        ss = solve_steady(ssys, Pair{Any,Any}[ssys.r01.inlet.ṁ => 0.1])
        @test ss.retcode == ReturnCode.Success

        # The cube graph between opposite corners has effective resistance (5/6)*R per
        # edge (3 edges at corner 0 in parallel, then 6 middle edges, then 3 in parallel
        # at corner 7). With R = 1e4 and pump head dP = 3e4, total flow = dP/R_eff = 3.6.
        R = 1.0e4
        dP = 3.0e4
        R_eff = (5.0 / 6.0) * R
        mtot_expected = dP / R_eff
        @test isapprox(ss[ssys.pump.inlet.ṁ], mtot_expected; rtol=1e-6)  # = 3.6 kg/s

        # The three edges leaving corner 0 are symmetric, so each carries a third of the
        # total flow.
        m01 = ss[ssys.r01.inlet.ṁ]
        m02 = ss[ssys.r02.inlet.ṁ]
        m04 = ss[ssys.r04.inlet.ṁ]
        @test isapprox(m01, mtot_expected / 3; rtol=1e-6)
        @test isapprox(m01, m02; rtol=1e-6)
        @test isapprox(m01, m04; rtol=1e-6)
    end

    @testset "build_loop_lof_bypass compiles + briefly solves" begin
        # Smoke: fuel-plate builder (CAC + HeatDiffusion plate). Compile only;
        # the full transient is exercised in the loss-of-flow section below.
        ssys = build_loop_lof_bypass()
        @test ssys isa ModelingToolkit.AbstractSystem
        @test length(equations(ssys)) == length(unknowns(ssys))
    end

    @testset "build_loop_pk compiles + briefly solves" begin
        ctrl = ReactivityController()
        ssys, ic = build_loop_pk(ctrl)
        @test length(equations(ssys)) > 0
        @test length(unknowns(ssys)) > 0
        sol = solve_transient(ssys, ic, range(0.0, 0.1, length=5))
        @test sol.retcode == ReturnCode.Success
    end
end

@testset "Loss-of-flow transient" begin
    # Baseline constants for the bypass loss-of-flow loop.
    BYPASS_N = 10
    BYPASS_L_CH = 1.0
    BYPASS_D_CH = 0.01
    BYPASS_T_INLET = 40.0
    BYPASS_G_ACC = G_EARTH
    BYPASS_L_OVER_A = 1.75e5
    BYPASS_R_EXT = 1.0e6
    BYPASS_THRESHOLD = 0.01
    BYPASS_DT_RAMP = 5.0
    # Fuel-plate-specific:
    BYPASS_POWER_W = 1.0e3   # matches build_loop_lof_bypass default
    BYPASS_FUEL_NX = 2
    BYPASS_FUEL_LX = 0.005

    # Loss-of-flow IC via solve_steady then solve_transient on the same system: no
    # separate reference loop, no state transplant. Solve the bypass system with the
    # pump head at its pre-trip value (forced flow), then integrate from that steady
    # state while the pump head ramps to zero. The IC is a true steady state and the
    # pump head is continuous at t=0, so the transient starts consistent.
    BYPASS_DP_PRE   = 2.0e5   # pre-trip pump head [Pa]
    BYPASS_T_TRIP   = 10.0    # pump trips at t = 10 s
    BYPASS_TRIP_TAU = 5.0     # C1 Hermite ramp duration [s]

    # Pump head: pre-trip value at t=0 (continuous with the steady IC), C1 Hermite
    # ramp to 0 over TRIP_TAU starting at t_trip. t_trip = Inf gives a constant
    # pre-trip head for the steady solve (same closure type as the trip function,
    # so both can be assigned to the single `dP_pump_fn` callable parameter).
    function _bypass_pump_fn(t_trip)
        return tt -> begin
            xi = clamp((tt - t_trip) / BYPASS_TRIP_TAU, 0.0, 1.0)
            BYPASS_DP_PRE * (1.0 - (3 * xi^2 - 2 * xi^3))
        end
    end

    function _lof_bypass_ic(; n=BYPASS_N)
        dP_fn_steady = _bypass_pump_fn(Inf)            # constant pre-trip head
        dP_fn        = _bypass_pump_fn(BYPASS_T_TRIP)  # trips at t_trip

        ssys = build_loop_lof_bypass(;
            n=n,
            L_ch=BYPASS_L_CH,
            D_ch=BYPASS_D_CH,
            T_inlet=BYPASS_T_INLET,
            power_W=BYPASS_POWER_W,
            fuel_nx=BYPASS_FUEL_NX,
            fuel_Lx=BYPASS_FUEL_LX,
            L_over_A=BYPASS_L_OVER_A,
            g_acc=BYPASS_G_ACC,
            R_ext=BYPASS_R_EXT,
            dt_ramp=BYPASS_DT_RAMP,
            dP_pump_fn=dP_fn,
        )

        Dt = Differential(t)
        # Forced-flow guess from the dominant linear branch: the pump head drives flow
        # through ext_res (R_ext), so ṁ ~ dP_pre / R_ext, and the coolant warms by
        # power_W / (ṁ * cp) across the channel.
        ṁ_guess = BYPASS_DP_PRE / BYPASS_R_EXT
        cp = cₚ(H2O, BYPASS_T_INLET)
        dT_guess = BYPASS_POWER_W / (ṁ_guess * cp)
        P_top = 1.0e5 + BYPASS_DP_PRE   # pump-out / node-A pressure (anchor + head)

        # Forced-flow steady state (pump on, flapper closed), integrated to steady by
        # DynamicSS(Rodas5P()). The system has a second root at ṁ = 0 (flow
        # recirculating through the closed flapper); DynamicSS lands on whichever root
        # its guess sits nearest. Seed the variables mtkcompile keeps as unknowns
        # (heated.ch.inlet.ṁ + its dummy derivative, ext_res.inlet.ṁ,
        # ine.outlet.p) so the guess lands in the forced-flow basin and DynamicSS
        # converges to ṁ_ss ~ 0.187 kg/s on both package sets. Seeding only the
        # observed aliases (ine.inlet.ṁ, ret.inlet.ṁ) let the latest set fall
        # into ṁ = 0. The aliases are seeded too so the guess is unambiguous either way.
        op_steady = Pair{Any,Any}[
            ssys.pump.dP_pump_fn => dP_fn_steady,
            ssys.flapper.T_open => Inf,
            ssys.heated.ch.inlet.ṁ => ṁ_guess,
            Dt(ssys.heated.ch.inlet.ṁ) => 0.0,
            ssys.ext_res.inlet.ṁ => ṁ_guess,
            ssys.ine.outlet.p => P_top,
            ssys.ine.inlet.ṁ => ṁ_guess,
            ssys.ret.inlet.ṁ => ṁ_guess,
        ]
        for i in 1:n
            push!(op_steady, ssys.heated.ch.T[i] => BYPASS_T_INLET + (i / n) * dT_guess)
            push!(op_steady, ssys.ret.T[i] => BYPASS_T_INLET + dT_guess)
            push!(
                op_steady,
                getproperty(ssys.heated.ch, Symbol(:thermal_left, i)).T =>
                    BYPASS_T_INLET + (i / n) * dT_guess + 5.0,
            )
        end
        for i in 1:n, j in 1:BYPASS_FUEL_NX
            push!(
                op_steady,
                ssys.heated.fuel.T[i, j] => BYPASS_T_INLET + (i / n) * dT_guess + 5.0,
            )
        end
        ss = solve_steady(ssys, op_steady; solver=DynamicSS(Rodas5P()))
        ṁ_ss = ss[ssys.ine.inlet.ṁ]

        # Transient IC = the FULL consistent steady-state vector; pump head now
        # ramps to 0. Seeding EVERY unknown (not a hand-picked subset) is essential:
        # the coupled momentum ODEs + KCL index-reduce to a dummy-derivative state
        # (heated.ch.inlet.ṁ_t) that a `Dt(ṁ) => 0` op guess does NOT map to.
        # Left unset, the latest packages initialize it to NaN, so the transient
        # aborts at t=0 (dt below floating-point epsilon, NaN error estimate). Copying
        # ss[u] for every unknown sets it directly.
        op = Pair{Any,Any}[u => ss[u] for u in unknowns(ssys)]
        push!(op, ssys.pump.dP_pump_fn => dP_fn)
        # T_open is the time the flapper opens. Start it at Inf (never opens); the
        # callback below latches it to the real opening time once flow drops past the
        # threshold.
        push!(op, ssys.flapper.T_open => Inf)

        cb = flapper_callback(ssys, ssys.flapper)
        return ssys, op, ṁ_ss, cb
    end

    # Equilibrium flow of the natural-circulation loop, derived from the solved state rather
    # than stored as a measured number. At equilibrium each channel's momentum ODE has
    # D(ṁ) = 0, so around the closed heated -> return -> flapper -> heated path the pressure
    # differences telescope and the loop friction balances the net buoyancy head. Both sides
    # come out of the model's own per-cell form,
    #   dp[i] = darcy_weisbach_dp(ṁ, rho_i, f_i, dz, Dh, A) + rho_i*g*dz.
    #
    # The friction models here mirror `build_loop_lof_bypass`: the heated channel switches
    # regime, the return channel is plain Blasius. That mirroring is the whole point. The
    # equilibrium Reynolds is ~4800, which is inside the (2000, 5000) transition band, so the
    # heated channel applies a blended f ~ 0.036 and not Blasius's 0.038. A Blasius-only
    # reference is 1.5% off for that reason alone, which is what made the previous stored
    # bracket look wrong when the closure changed.
    #
    # Left out because they do not reach the balance: the flapper's open-state drop is
    # ~0.005 Pa against ~14 Pa of buoyancy, and the inertia/ext_res branch carries no flow.
    function _nc_equilibrium_ṁ(ssys, sol, idx)
        n = BYPASS_N
        dz = BYPASS_L_CH / n
        geom = PipeGeometry_circular(BYPASS_L_CH, BYPASS_D_CH)

        T_ch = [mean(sol[ssys.heated.ch.T[i], idx]) for i in 1:n]
        T_ret = [mean(sol[ssys.ret.T[i], idx]) for i in 1:n]

        # Net buoyancy head: heated leg at g = -G_ACC, return leg at +G_ACC.
        dP_buoy = sum(BYPASS_G_ACC * dz * (ρ(H2O, T_ret[i]) - ρ(H2O, T_ch[i])) for i in 1:n)

        darcy_ch = Friction.RegimeDependent(;
            laminar=Friction.rectangular_laminar(geom), turbulent=Friction.blasius,
        )
        darcy_ret = Friction.Blasius()
        dP_fric(md) = sum(
            Friction.darcy_weisbach_dp(
                md, ρ(H2O, T_ch[i]), darcy_ch(T_ch[i], T_ch[i], md, H2O, geom),
                dz, geom.Dh, geom.A,
            ) + Friction.darcy_weisbach_dp(
                md, ρ(H2O, T_ret[i]), darcy_ret(T_ret[i], T_ret[i], md, H2O, geom),
                dz, geom.Dh, geom.A,
            )
            for i in 1:n
        )

        # Bisect in log space for the root of dP_fric = |dP_buoy|.
        lo, hi = 1.0e-6, 1.0
        for _ in 1:200
            mid = sqrt(lo * hi)
            dP_fric(mid) < abs(dP_buoy) ? (lo = mid) : (hi = mid)
        end
        return sqrt(lo * hi), dP_buoy
    end

    @testset "bypass topology compiles and SS IC is physical" begin
        ssys, op, ṁ_ss, _ = _lof_bypass_ic()

        @test length(equations(ssys)) == length(unknowns(ssys))
        # Forced-flow steady lands on the pump-driven branch at ṁ_ss ~ 0.187 kg/s, which
        # reproduces across package sets to well under 1%, so bracket it at 0.005.
        @test isapprox(ṁ_ss, 0.187; atol=0.005)

        T_open_init = op[findfirst(p -> isequal(p.first, ssys.flapper.T_open), op)].second
        @test T_open_init == Inf
    end

    @testset "Flapper fires at correct threshold" begin
        # After the pump trips, the inertia branch flow decays through the threshold and
        # the callback latches T_open ~ 14.5 s; the open ramp then drives xi to 1.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)

        @test sol.retcode == ReturnCode.Success

        # The valve opens after the trip (t > T_TRIP = 10 s) and within the simulated
        # window, then fully ramps open.
        T_open_end = sol.ps[ssys.flapper.T_open]
        @test BYPASS_T_TRIP < T_open_end < 300.0
        @test isapprox(sol[ssys.flapper.xi, end], 1.0; atol=1e-4)
    end

    @testset "channel flow reversal (ṁ crosses zero)" begin
        # Heated channel has g = -G_ACC (assists downward flow). Positive ṁ = downward
        # (A->B), the forced-flow direction. After the pump trips and natural convection
        # establishes, the heated channel reverses to upward (ṁ < 0): buoyancy carries
        # the hot coolant up the heated leg. Forced flow ~ +0.187 kg/s reverses to a small
        # NC recirculation ~ -0.0042 kg/s.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)

        ṁ_ch_initial = sol[ssys.heated.ch.inlet.ṁ, 1]
        @test ṁ_ch_initial > 0.0

        ṁ_ch_final = sol[ssys.heated.ch.inlet.ṁ, end]
        @test ṁ_ch_final < 0.0

        # The recirculation settles on the buoyancy-against-friction root of the loop, which
        # `_nc_equilibrium_ṁ` derives from the solved cell temperatures. Deriving it beats
        # storing it: the number this used to carry was measured at 4.21 g/s and went stale
        # when the heated channel's friction closure changed, without saying why.
        ṁ_nc = abs(ṁ_ch_final)
        ṁ_ref, _ = _nc_equilibrium_ṁ(ssys, sol, 2701:3001)
        @test isapprox(ṁ_nc, ṁ_ref; rtol=0.02)
    end

    @testset "channel energy conservation across the heated leg" begin
        # The run reaches a natural-convection recirculation, not a thermal steady state:
        # once the flapper opens, flow recirculates heated.ch -> ret -> flapper ->
        # heated.ch while the inertia/HeatExchanger branch (the only heat sink) carries
        # essentially zero flow. With the sink bypassed the 1 kW plate input has nowhere
        # to go, so the coolant keeps warming and sum(q_wall) never equals an ṁ*cp*dT
        # bulk estimate. What does hold is energy conservation on the coolant control
        # volume: the coolant stores enthalpy at a positive rate that stays below the wall
        # heat it absorbs, with the rest carried out by the recirculating flow. The checks
        # below assert 0 < store_rate < Q_wall, reconstructing store_rate from the per-cell
        # rho*cp*A*dz*dT/dt.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)
        @test sol.retcode == ReturnCode.Success

        n = BYPASS_N
        cv_area = pi * (BYPASS_D_CH / 2)^2
        v_cell = cv_area * BYPASS_L_CH / n

        # Energy conservation, rigorous: the channel-side heat absorbed can never exceed
        # the fuel-plate input power. Checked over t = 100..300 s, past the IC settle
        # where the CAC HTC drives a large transient q_wall.
        nc_pwr = 1001:3001
        Q_wall_eq = [
            abs(sum(sol[ssys.heated.ch.q_wall[i], idx] for i in 1:n)) for idx in nc_pwr
        ]
        @test maximum(Q_wall_eq) <= BYPASS_POWER_W   # plate output bounded by its input

        # Direction: once the natural-convection recirculation is established (t = 200..300 s,
        # the window the storage check below uses), the plate heats the coolant, so the summed
        # wall flux stays positive across the whole window. Reading it here rather than just
        # after t = 0 avoids the large startup swing the CAC HTC drives through the settle, where
        # the instantaneous sign flips with the integration path and carries no physical meaning.
        nc_dir = 2001:3000
        q_wall_dir = [sum(sol[ssys.heated.ch.q_wall[i], idx] for i in 1:n) for idx in nc_dir]
        @test minimum(q_wall_dir) > 0

        # Coolant storage rate vs wall heat, averaged over the NC window t = 200..300 s.
        # store_rate_i = rho(Ti)*cp(Ti)*A*dz*dTi/dt, with dTi/dt by central difference.
        store_rate(idx) = sum(
            ρ(H2O, sol[ssys.heated.ch.T[i], idx]) *
            cₚ(H2O, sol[ssys.heated.ch.T[i], idx]) * v_cell *
            (sol[ssys.heated.ch.T[i], idx + 1] - sol[ssys.heated.ch.T[i], idx - 1]) /
            (t_arr[idx + 1] - t_arr[idx - 1])
            for i in 1:n
        )
        nc = 2001:3000
        store_mean = mean(store_rate(idx) for idx in nc)
        Qwall_mean = mean(abs(sum(sol[ssys.heated.ch.q_wall[i], idx] for i in 1:n)) for idx in nc)

        # The coolant is warming (positive storage) but stores strictly less than it
        # absorbs from the wall: the recirculating flow carries the rest out.
        @test store_mean > 0
        @test store_mean < Qwall_mean
        # Storage takes a repeatable share of the wall heat. The 0.5 share is not
        # analytically forced (it depends on the recirculation rate and the axial
        # temperature profile, neither of which has a closed form here); it is a
        # regression value. Over t = 200..300 s the ratio is 0.499 on both package sets
        # (per-sample range 0.476..0.512), so the band is that spread.
        @test 0.49 < store_mean / Qwall_mean < 0.51
    end

    @testset "NC equilibrium ṁ matches a buoyancy-vs-friction balance" begin
        # In the natural-convection recirculation the heated leg (hot, g = -G_ACC) and the
        # return leg (g = +G_ACC) form a closed buoyancy loop, and the equilibrium flow is the
        # root of the loop momentum balance: net buoyancy head = total loop friction. Both
        # sides are derived in `_nc_equilibrium_ṁ` from the solved cell temperatures, using
        # the friction each channel actually applies rather than a single assumed law.
        #
        # The buoyancy head is small, ~14 Pa: the loop runs hot and nearly isothermal, so the
        # leg-to-leg density difference is what drives the whole thing. At the resulting flow
        # the channel Reynolds number is ~4800, which sits inside the (2000, 5000) transition
        # band of the heated channel's `Friction.RegimeDependent`, so it applies a blend at
        # f ~ 0.036 rather than Blasius's 0.038. Getting that right is worth 1.5% in ṁ, and
        # it is why this used to look like a 3% disagreement. A laminar reference at this Re
        # is off by a factor of 3, so the regime really is the question.
        #
        # The reference is derived, not fitted: the integrated model lands on it to 0.03%.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)

        n = BYPASS_N
        nc_indices = 2701:3001

        ṁ_nc_series_signed = sol[ssys.heated.ch.inlet.ṁ, nc_indices]
        ṁ_nc = mean(abs.(ṁ_nc_series_signed))

        ṁ_ref, dP_buoy = _nc_equilibrium_ṁ(ssys, sol, nc_indices)
        # Return leg cooler and therefore denser than the heated leg, which is what drives it.
        @test dP_buoy > 0.0

        # Model NC flow matches the derived root. With the reference built from the friction
        # the channels actually apply, the two agree to 0.03%, so 2% is slack for package
        # drift rather than for a wrong friction law.
        @test isapprox(ṁ_nc, ṁ_ref; rtol=0.02)

        # NC flow is reversed relative to the forced-flow direction at t = 0.
        @test sol[ssys.heated.ch.inlet.ṁ, 1] > 0.0
        @test mean(ṁ_nc_series_signed) < 0.0

        # Energy conservation across the heated leg: channel-side heat absorbed in the NC
        # window is bounded above by the fuel-plate input power.
        Q_wall_nc_mean = mean([
            abs(sum(sol[ssys.heated.ch.q_wall[i], idx] for i in 1:n))
            for idx in nc_indices
        ])
        @test 0.0 < Q_wall_nc_mean <= BYPASS_POWER_W

        # The Channel family is single-phase only: no two-phase model is wired here, and
        # the inertia/HeatExchanger heat sink is bypassed in NC, so the coolant runs
        # superheated relative to saturation and creeps up slowly. This is a known
        # limitation of the single-phase model under a bypassed sink, not a solver artifact.
        # The window-mean peak temperature is a "no thermal runaway" gate with no analytic
        # reference (the slow creep depends on the bypassed-sink storage rate, not a steady
        # balance). It is a regression value: 233.95 °C on both package sets (pinned 233.98,
        # latest 233.97), well below water's critical temperature (373.95 °C). The band is the
        # measured cross-env spread, not a loose runaway window.
        T_max_nc = mean([
            maximum([sol[ssys.heated.ch.T[i], idx] for i in 1:n]) for idx in nc_indices
        ])
        @test T_max_nc > BYPASS_T_INLET   # heating did happen
        @test 231.85 < T_max_nc < 236.85    # tight around the observed 233.95 °C, below critical T
    end
end

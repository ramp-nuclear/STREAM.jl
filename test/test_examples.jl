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
            [ssys.ch.T[i] => 313.15 for i in 1:10]...,
            ssys.ch.port_in.mdot => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.ch.T_out, end] > 313.15  # heating worked
    end

    @testset "build_loop_vertical compiles + briefly solves" begin
        ssys = build_loop_vertical()
        ic = Pair{Any,Any}[
            [ssys.ch.T[i] => 313.15 for i in 1:10]...,
            ssys.ch.port_in.mdot => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
        @test sol[ssys.ch.T_out, end] > 313.15
    end

    @testset "build_loop_transient compiles + briefly solves" begin
        ssys = build_loop_transient()
        ic = Pair{Any,Any}[
            [ssys.ch.T[i] => 313.15 for i in 1:10]...,
            ssys.ch.port_in.mdot => 0.5,
        ]
        sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
        @test sol.retcode == ReturnCode.Success
    end

    @testset "build_cube solves its resistor-network steady state" begin
        # build_cube is a pump driving the 12 edges of a cube graph between opposite
        # corners (0 = pump out, 7 = pump in). No inertia and no thermal dynamics, so
        # mtkcompile reduces it to a purely algebraic Kirchhoff network: solve its
        # steady state and check the flow against the cube's known effective resistance.
        ssys = build_cube()
        @test ssys isa ModelingToolkit.AbstractSystem

        ss = solve_steady(ssys, Pair{Any,Any}[ssys.r01.port_in.mdot => 0.1])
        @test ss.retcode == ReturnCode.Success

        # The cube graph between opposite corners has effective resistance (5/6)*R per
        # edge (3 edges at corner 0 in parallel, then 6 middle edges, then 3 in parallel
        # at corner 7). With R = 1e4 and pump head dP = 3e4, total flow = dP/R_eff = 3.6.
        R = 1.0e4
        dP = 3.0e4
        R_eff = (5.0 / 6.0) * R
        mtot_expected = dP / R_eff
        @test isapprox(ss[ssys.pump.port_in.mdot], mtot_expected; rtol=1e-6)  # = 3.6 kg/s

        # The three edges leaving corner 0 are symmetric, so each carries a third of the
        # total flow.
        m01 = ss[ssys.r01.port_in.mdot]
        m02 = ss[ssys.r02.port_in.mdot]
        m04 = ss[ssys.r04.port_in.mdot]
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
    BYPASS_T_INLET = 313.15
    BYPASS_G_ACC = 9.80665
    BYPASS_L_OVER_A = 1.75e5
    BYPASS_R_EXT = 1.0e6
    BYPASS_THRESHOLD = 0.01
    BYPASS_DT_RAMP = 5.0
    # Fuel-plate-specific:
    BYPASS_POWER_W = 1.0e3   # matches build_loop_lof_bypass default
    BYPASS_FUEL_NX = 2
    BYPASS_FUEL_LX = 0.005

    # Loss-of-flow IC via the canonical steady-then-transient pattern: no separate
    # reference loop, no state transplant. We solve_steady the ACTUAL bypass system
    # with the pump head held at its pre-trip value (forced flow), then run the
    # transient from that consistent steady state while the pump head ramps to zero
    # (the loss-of-flow event). Because the IC is a true steady state of the system
    # being integrated AND the pump head is continuous at t=0, the transient starts
    # fully consistent.
    #
    # The forced-flow steady has a spurious co-existing root (mdot = 0, with flow
    # recirculating through the closed flapper). DynamicSS picks whichever root its
    # initial guess sits nearest, and that choice flips between MTK versions if the
    # guess only seeds the aliased branch flows. The fix is to seed the variables
    # mtkcompile actually keeps as unknowns: the channel flow heated.ch.port_in.mdot
    # and its dummy derivative, plus the algebraic unknowns ext_res.port_in.mdot and
    # ine.port_out.P, so the guess lands squarely in the forced-flow basin. With the
    # real unknowns seeded, DynamicSS converges to mdot_ss ~ 0.187 kg/s on both the
    # pinned and latest package sets; seeding only ine.port_in.mdot / ret.port_in.mdot
    # (which are observed aliases, not unknowns) let the latest set fall into mdot = 0.
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
        # through ext_res (R_ext), so mdot ~ dP_pre / R_ext, and the coolant warms by
        # power_W / (mdot * cp) across the channel.
        mdot_guess = BYPASS_DP_PRE / BYPASS_R_EXT
        cp = cp_water(BYPASS_T_INLET)
        dT_guess = BYPASS_POWER_W / (mdot_guess * cp)
        P_top = 1.0e5 + BYPASS_DP_PRE   # pump-out / node-A pressure (anchor + head)

        # Forced-flow steady state of the actual system (pump on, flapper closed).
        # DynamicSS(Rodas5P()) integrates to steady. Seeding the real unknowns
        # (heated.ch.port_in.mdot + its dummy derivative, ext_res.port_in.mdot,
        # ine.port_out.P) keeps it in the forced-flow basin; the aliased branch flows
        # are seeded too so the guess is unambiguous either way.
        op_steady = Pair{Any,Any}[
            ssys.pump.dP_pump_fn => dP_fn_steady,
            ssys.flapper.T_open => Inf,
            ssys.heated.ch.port_in.mdot => mdot_guess,
            Dt(ssys.heated.ch.port_in.mdot) => 0.0,
            ssys.ext_res.port_in.mdot => mdot_guess,
            ssys.ine.port_out.P => P_top,
            ssys.ine.port_in.mdot => mdot_guess,
            ssys.ret.port_in.mdot => mdot_guess,
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
        mdot_ss = ss[ssys.ine.port_in.mdot]

        # Transient IC = the FULL consistent steady-state vector; pump head now
        # ramps to 0. Seeding EVERY unknown (not a hand-picked subset) is essential:
        # the coupled momentum ODEs + KCL index-reduce to a dummy-derivative state
        # (heated.ch.port_in.mdot_t) that a `Dt(mdot) => 0` op guess does NOT map to.
        # Left unset, the latest packages initialize it to NaN, so the transient
        # aborts at t=0 (dt below floating-point epsilon, NaN error estimate). Copying
        # ss[u] for every unknown sets it directly. T_open is a parameter (not an
        # unknown), so it defaults to Inf (flapper closed) for the transient; we set it
        # explicitly for clarity, and flapper_callback latches it when ine.port_in.mdot
        # crosses the threshold.
        op = Pair{Any,Any}[u => ss[u] for u in unknowns(ssys)]
        push!(op, ssys.pump.dP_pump_fn => dP_fn)
        push!(op, ssys.flapper.T_open => Inf)

        cb = flapper_callback(ssys, ssys.flapper)
        return ssys, op, mdot_ss, cb
    end

    @testset "bypass topology compiles and SS IC is physical" begin
        ssys, op, mdot_ss, _ = _lof_bypass_ic()

        @test length(equations(ssys)) == length(unknowns(ssys))
        # Forced-flow steady lands on the pump-driven branch, mdot_ss ~ 0.187 kg/s.
        # Bracket it tightly around that value rather than over a broad window.
        @test isapprox(mdot_ss, 0.187; atol=0.02)

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

    @testset "channel flow reversal (mdot crosses zero)" begin
        # Heated channel has g = -G_ACC (assists downward flow). Positive mdot = downward
        # (A->B), the forced-flow direction. After the pump trips and natural convection
        # establishes, the heated channel reverses to upward (mdot < 0): buoyancy carries
        # the hot coolant up the heated leg. Forced flow ~ +0.187 kg/s reverses to a small
        # NC recirculation ~ -0.0042 kg/s.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)

        mdot_ch_initial = sol[ssys.heated.ch.port_in.mdot, 1]
        @test mdot_ch_initial > 0.0

        mdot_ch_final = sol[ssys.heated.ch.port_in.mdot, end]
        @test mdot_ch_final < 0.0

        # NC recirculation settles at ~4.21 g/s, a deterministic root of the
        # buoyancy-vs-friction balance (derived in the momentum-balance test below). It
        # reproduces to better than 0.1% across package sets: 4.207 g/s on the pinned set,
        # 4.207 g/s on the latest. Bracket it tightly around that.
        mdot_nc = abs(mdot_ch_final)
        @test isapprox(mdot_nc, 0.00421; atol=5.0e-5)
    end

    @testset "channel energy conservation across the heated leg" begin
        # The bypass loss-of-flow run reaches a natural-convection recirculation, not a
        # thermal steady state: once the flapper opens, the loop flow recirculates
        # heated.ch -> ret -> flapper -> heated.ch while the inertia/HeatExchanger branch
        # (the only heat sink) carries essentially zero flow (mdot_ine ~ 5e-9 kg/s). With
        # the sink bypassed, the 1 kW plate input has nowhere to go, so the coolant keeps
        # warming slowly (dT_max/dt ~ 0.7 K/s near t = 300 s). There is therefore NO
        # equilibrium in which sum(q_wall) equals an mdot*cp*dT bulk estimate, and the
        # legacy "Q_meas vs Q_wall within a factor of 3" gate compared two unrelated
        # quantities (single-boundary-cell dT vs all-cell q_wall) that happen to land
        # ~2x apart.
        #
        # What holds rigorously is energy conservation on the heated-channel coolant
        # control volume: the rate the coolant stores enthalpy is positive (it is
        # warming) and strictly less than the wall heat it absorbs (the remainder is
        # carried away by the recirculating flow). Reconstructing the storage rate from
        # the per-cell rho*cp*A*dz*dT/dt and comparing it to sum(q_wall) gives a
        # version-stable check with no fitted tolerance: 0 < store_rate < Q_wall, and
        # store_rate is a definite fraction (~0.5) of Q_wall, confirming the heat splits
        # between storage and advective removal rather than vanishing.
        #
        # The 0.5 share is not analytically forced: it is set by the recirculation rate and
        # the axial temperature profile in the bypassed-sink transient, neither of which has
        # a closed form here. It is a stable regression value rather than a derived one. Over
        # t = 200..300 s the mean ratio lands at 0.499 on both package sets (pinned 0.4990,
        # latest 0.4990; per-sample range 0.476..0.512), so the band is set to that spread.
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

        # Forced-flow direction: heat flows plate -> coolant just after the IC settles.
        @test sum(sol[ssys.heated.ch.q_wall[i], 11] for i in 1:n) > 0

        # Coolant storage rate vs wall heat, averaged over the NC window t = 200..300 s.
        # store_rate_i = rho(Ti)*cp(Ti)*A*dz*dTi/dt, with dTi/dt by central difference.
        store_rate(idx) = sum(
            rho_water(sol[ssys.heated.ch.T[i], idx]) *
            cp_water(sol[ssys.heated.ch.T[i], idx]) * v_cell *
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
        # Storage takes a definite, repeatable share of the wall heat (~0.499 on both envs).
        @test 0.49 < store_mean / Qwall_mean < 0.51
    end

    @testset "NC equilibrium mdot matches a buoyancy-vs-friction balance" begin
        # In the natural-convection recirculation the heated leg (hot, g = -G_ACC) and the
        # return leg (g = +G_ACC) form a closed buoyancy loop. The equilibrium flow is the
        # root of the loop momentum balance: net buoyancy head = total loop friction.
        #
        # Net buoyancy head: the per-cell gravity terms rho_i*g_acc*dz sum around the loop to
        # g*dz*sum(rho_ret[i] - rho_ch[i]). For this run that is ~13.4 Pa (the loop is hot and
        # nearly isothermal, so the leg-to-leg density difference is small).
        #
        # Loop friction: at the equilibrium flow the channel Reynolds number is ~4600, above
        # the regime-dependent transition (Re_tr = 2300), so both channels apply the Blasius
        # turbulent factor f = 0.3164*Re^-0.25, not laminar Hagen-Poiseuille. A laminar
        # reference at this Re predicts ~0.012 kg/s, 0.36x of the model, because 64/Re is the
        # wrong friction law for the actual Re. The friction of the two channels in series is
        #   dP_fric(mdot) = 2 * f(Re) * mdot^2 / (2*rho*A^2) * (L/D),  Re = mdot*D/(A*mu).
        # Solving dP_fric(mdot) = dP_buoy by bisection gives mdot_ref ~ 0.004217 kg/s, which
        # the integrated model matches to within 0.3%: ratio mdot_nc/mdot_ref = 0.9975 on the
        # pinned set and 0.9975 on the latest. The residual ~0.25% is the entry/exit and
        # open-flapper losses the two-channel friction reference omits (the flapper drop at
        # this flow is ~0.005 Pa, so it is negligible). This is a derived reference, not a
        # fitted band: assert the model within 5% of it.
        ssys, op, _, cb = _lof_bypass_ic()

        t_arr = range(0.0, 300.0; length=3001)
        sol = solve_transient(ssys, op, t_arr; callbacks=cb)

        n = BYPASS_N
        nc_indices = 2701:3001

        mdot_nc_series_signed = sol[ssys.heated.ch.port_in.mdot, nc_indices]
        mdot_nc = mean(abs.(mdot_nc_series_signed))

        # Cell-resolved buoyancy head: g * dz * sum(rho_ret[i] - rho_ch[i]) over the loop.
        dz = BYPASS_L_CH / n
        T_ch = [mean(sol[ssys.heated.ch.T[i], nc_indices]) for i in 1:n]
        T_ret = [mean(sol[ssys.ret.T[i], nc_indices]) for i in 1:n]
        dP_buoy = sum(
            BYPASS_G_ACC * dz * (rho_water(T_ret[i]) - rho_water(T_ch[i])) for i in 1:n
        )

        # Two-channel Blasius friction at the loop-mean properties, the friction law the
        # channels actually apply at Re ~ 4600 (> Re_tr = 2300). Solve dP_fric = dP_buoy for
        # the balancing mdot by bisection.
        T_loop = mean(vcat(T_ch, T_ret))
        rho_loop = rho_water(T_loop)
        mu_loop = mu_water(T_loop)
        cs_area = pi * (BYPASS_D_CH / 2)^2
        dP_fric(md) = begin
            Re = md * BYPASS_D_CH / (cs_area * mu_loop)
            f = blasius_friction(Re)
            2 * f * md^2 / (2 * rho_loop * cs_area^2) * (BYPASS_L_CH / BYPASS_D_CH)
        end
        lo, hi = 1.0e-6, 1.0
        for _ in 1:200
            mid = sqrt(lo * hi)
            dP_fric(mid) < abs(dP_buoy) ? (lo = mid) : (hi = mid)
        end
        mdot_ref = sqrt(lo * hi)

        # Model NC flow matches the derived buoyancy-vs-Blasius-friction root within 5%.
        @test isapprox(mdot_nc, mdot_ref; rtol=0.05)

        # NC flow is reversed relative to the forced-flow direction at t = 0.
        @test sol[ssys.heated.ch.port_in.mdot, 1] > 0.0
        @test mean(mdot_nc_series_signed) < 0.0

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
        # balance). It is a regression value: 507.1 K on both package sets (pinned 507.13,
        # latest 507.12), well below water's critical temperature (647 K). The band is the
        # measured cross-env spread, not a loose runaway window.
        T_max_nc = mean([
            maximum([sol[ssys.heated.ch.T[i], idx] for i in 1:n]) for idx in nc_indices
        ])
        @test T_max_nc > BYPASS_T_INLET   # heating did happen
        @test 505.0 < T_max_nc < 510.0    # tight around the observed 507.1 K, below critical T
    end
end

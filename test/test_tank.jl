using Test
using ModelingToolkit
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.LocalLoss

const T_POOL, A_TANK, L_POOL, A_HOLE = 30.0, 2.0, 4.0, 5e-4
const CD_SHARP = discharge_cd(:sharp)

"""Saved times fine enough over the first seconds to integrate a break's opening ramp."""
_opening_grid(t_end; points=400) =
    vcat(range(0.0, 4.0; length=21), range(4.0, t_end; length=points)[2:end])

"""
Time for a tank of surface `area_tank` to drain through a hole from `h0` to `h1` above it,
quasi-steady Torricelli.
"""
_drain_time(h0, h1, area_tank, area_hole, cd) =
    (area_tank / (cd * area_hole)) * sqrt(2 / G_EARTH) * (sqrt(h0) - sqrt(h1))

"""Level above the hole after draining for `t` from `h0`, the inverse of `_drain_time`."""
_drain_level(t, h0, area_tank, area_hole, cd) =
    max(sqrt(h0) - (cd * area_hole / area_tank) * sqrt(G_EARTH / 2) * t, 0.0)^2

"""Running trapezoid integral of `y` over the saved times `ts`, zero at the first."""
_cumulative_trapezoid(y, ts) = [0.0; cumsum((y[1:(end - 1)] .+ y[2:end]) ./ 2 .* diff(ts))]

"""A tank with a hole in its bottom that discharges to the atmosphere, uncompiled."""
function _tank_with_break(pool, breach)
    @named ambient = Environment()
    @named sys = assembly([connect(pool.bottom, breach.inlet),
                           connect(breach.outlet, ambient.port)],
                          pool, breach, ambient)
    return sys
end

"""A machine that stops the run once `pool`'s level falls below `z`."""
function _uncovery_watch(pool, z)
    watch = StateMachine(; initial_state=:INTACT, abort_states=(:UNCOVERED,))
    push!(watch, (:INTACT => :UNCOVERED, pool.L < z, "uncovered"))
    return watch
end

@testset "Tank" begin
    @testset "a pinned tank holds its level and each port's head" begin
        g_mars = 3.71
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0, side=1.5), T0=T_POOL,
                           g=g_mars)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP)
        @named ambient = Environment()
        @named sys = assembly([connect(pool.bottom, breach.inlet),
                               connect(breach.outlet, ambient.port)],
                              pool, breach, ambient)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys)
        rho_g = ρ(H2O, T_POOL) * g_mars
        @test sol[ssys.pool.L] ≈ L_POOL
        @test sol[ssys.pool.T] == T_POOL
        @test sol[ssys.pool.bottom.p] ≈ ATM + rho_g * L_POOL
        @test sol[ssys.pool.side.p] ≈ ATM + rho_g * (L_POOL - 1.5)
        @test sol[ssys.breach.inlet.ṁ] == 0.0
    end

    @testset "the closed-form drain time matches Python's doctest" begin
        @test _drain_time(L_POOL, 1.0, A_TANK, A_HOLE, CD_SHARP) ≈ 2961.3164311592627
    end

    @testset "a tank drains on the Torricelli curve and stops at uncovery" begin
        z_uncovery = 1.0
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0,), T0=T_POOL)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_linear=1e-3,
                                machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        ssys = mtkcompile(_tank_with_break(pool, breach))
        watch = _uncovery_watch(pool, z_uncovery)
        sol = solve_transient(ssys, solve_steady(ssys), _opening_grid(5000.0; points=500);
                              overrides=[ssys.pool.pinned => false],
                              callbacks=machine_callbacks(ssys, watch))
        level, inventory = sol[ssys.pool.L], sol[ssys.pool.M]

        @testset "the level follows the closed form at every saved time" begin
            expected = _drain_level.(sol.t, L_POOL, A_TANK, A_HOLE, CD_SHARP)
            @test maximum(abs.(level .- expected)) < 1e-3
        end
        @testset "the run stops when the level reaches uncovery" begin
            @test watch.state === :UNCOVERED
            @test sol.t[end] ≈ _drain_time(L_POOL, z_uncovery, A_TANK, A_HOLE, CD_SHARP) atol = 0.5
            @test level[end] ≈ z_uncovery atol = 1e-3
        end
        @testset "the tank plus what left through the break holds the starting inventory" begin
            spilled = _cumulative_trapezoid(sol[ssys.breach.inlet.ṁ], sol.t)
            @test inventory .+ spilled ≈ fill(inventory[1], length(sol.t)) rtol = 1e-4
        end
    end

    @testset "a tank that widens with height drains on its own curve" begin
        A_bottom, flare, z_uncovery = 1.0, 0.5, 1.0
        area(L) = A_bottom + flare * L
        volume(L) = A_bottom * L + flare * L^2 / 2
        # A(h)·dh/dt = −cd·a·sqrt(2gh), integrated from L_POOL down to h.
        drain_time(h) = (2A_bottom * (sqrt(L_POOL) - sqrt(h)) +
                         (2flare / 3) * (L_POOL^1.5 - h^1.5)) /
                        (CD_SHARP * A_HOLE * sqrt(2G_EARTH))
        @test_throws ArgumentError Tank(; name=:no_volume, area=area, L0=L_POOL, ports=(b=0.0,))
        @named pool = Tank(; area=area, volume=volume, L0=L_POOL, ports=(bottom=0.0,), T0=T_POOL)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_linear=1e-3,
                                machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        ssys = mtkcompile(_tank_with_break(pool, breach))
        watch = _uncovery_watch(pool, z_uncovery)
        sol = solve_transient(ssys, solve_steady(ssys), _opening_grid(6000.0; points=600);
                              overrides=[ssys.pool.pinned => false],
                              callbacks=machine_callbacks(ssys, watch))
        level, inventory = sol[ssys.pool.L], sol[ssys.pool.M]

        @testset "each level is reached at the closed-form time" begin
            @test maximum(abs.(drain_time.(level) .- sol.t)) < 1.0
        end
        @testset "the run stops when the level reaches uncovery" begin
            @test watch.state === :UNCOVERED
            @test sol.t[end] ≈ drain_time(z_uncovery) atol = 1.0
        end
        @testset "the tank plus what left through the break holds the starting inventory" begin
            spilled = _cumulative_trapezoid(sol[ssys.breach.inlet.ṁ], sol.t)
            @test inventory .+ spilled ≈ fill(inventory[1], length(sol.t)) rtol = 1e-4
        end
    end

    @testset "external heat warms a sealed pool" begin
        Q, t_end = 1e5, 600.0
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0,), T0=T_POOL, Q_ext=Q,
                           fixed_temperature=false)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP)   # never opens
        ssys = mtkcompile(_tank_with_break(pool, breach))
        # A sealed, heated pool has no steady state, so the run starts from the declared one.
        sol = solve_transient(ssys, [ssys.pool.pinned => false], range(0.0, t_end; length=61))
        @test sol[ssys.pool.L] ≈ fill(L_POOL, length(sol.t))

        V = A_TANK * L_POOL
        warm!(dT, T, _, _) = (dT[1] = Q / (ρ(H2O, T[1]) * V * cₚ(H2O, T[1])))
        ref = solve(ODEProblem(warm!, [T_POOL], (0.0, t_end)), Vern9();
                    reltol=1e-10, abstol=1e-12, saveat=sol.t)
        @test sol[ssys.pool.T] ≈ ref[1, :] rtol = 1e-6
    end

    @testset "two tanks joined at the bottom settle at one level" begin
        A_wide, A_narrow, L_wide, L_narrow, R = 2.0, 1.0, 4.0, 1.0, 1500.0
        @named wide = Tank(; area=A_wide, L0=L_wide, ports=(bottom=0.0,), T0=T_POOL)
        @named narrow = Tank(; area=A_narrow, L0=L_narrow, ports=(bottom=0.0,), T0=T_POOL)
        @named pipe = Resistor(R)
        @named sys = assembly([connect(wide.bottom, pipe.inlet),
                               connect(pipe.outlet, narrow.bottom)],
                              wide, pipe, narrow)
        ssys = mtkcompile(sys)
        sol = solve_transient(ssys, solve_steady(ssys), range(0.0, 1000.0; length=201);
                              overrides=[ssys.wide.pinned => false, ssys.narrow.pinned => false])
        L_w, L_n = sol[ssys.wide.L], sol[ssys.narrow.L]

        @testset "the level difference decays as exp(-t/τ)" begin
            # The head ρgΔL drives ṁ = ρgΔL/R through the linear resistor, so ρ cancels and
            # 1/τ = g·(1/A₁ + 1/A₂)/R.
            τ = R / (G_EARTH * (1 / A_wide + 1 / A_narrow))
            @test maximum(abs.((L_w .- L_n) .- (L_wide - L_narrow) .* exp.(-sol.t ./ τ))) < 1e-4
        end
        @testset "the liquid volume A₁L₁ + A₂L₂ stays constant" begin
            volume = A_wide .* L_w .+ A_narrow .* L_n
            @test volume ≈ fill(A_wide * L_wide + A_narrow * L_narrow, length(volume)) rtol = 1e-9
        end
    end

    @testset "a heated pool settles where its drain matches its feed" begin
        # A small surface so the level settles within the run: its time constant is
        # 2·ρ·A·L/ṁ ≈ 450 s.
        m_in, T_hot, area, t_end = 2.0, 40.0, 0.2, 5000.0
        @named pool = Tank(; area=area, L0=L_POOL, ports=(bottom=0.0, feed=0.0), T0=T_POOL,
                           fixed_temperature=false)
        @named supply = Environment(; T=T_POOL)
        @named feed = Pump(; ṁ0=m_in)
        @named heater = HeatExchanger(T_POOL)
        @named drain = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_linear=1e-3, open_rate=1.0,
                               machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        @named ambient = Environment()
        conns = [
            connect(supply.port, feed.inlet),
            inseries(feed, heater),
            connect(heater.outlet, pool.feed),
            connect(pool.bottom, drain.inlet),
            connect(drain.outlet, ambient.port),
        ]
        @named sys = assembly(conns, pool, supply, feed, heater, drain, ambient)
        ssys = mtkcompile(sys)
        # The pinned pool settles at the feed temperature. The run turns the heater up.
        sol_ss = solve_steady(ssys)
        @test sol_ss[ssys.pool.T] ≈ T_POOL
        sol = solve_transient(ssys, sol_ss, _opening_grid(t_end; points=500);
                              overrides=[ssys.pool.pinned => false, ssys.heater.T_bc => T_hot])
        level, T, M = sol[ssys.pool.L], sol[ssys.pool.T], sol[ssys.pool.M]

        @testset "the level settles where the drain passes the feed" begin
            # ṁ = cd·a·ρ·sqrt(2gL) at the hole, solved for L.
            L_settled = (m_in / (CD_SHARP * A_HOLE * ρ(H2O, T_hot)))^2 / (2G_EARTH)
            @test level[end] ≈ L_settled atol = 1e-3
        end
        @testset "the pool settles at the feed temperature" begin
            @test T[end] ≈ T_hot atol = 1e-3
        end
        @testset "the pool's enthalpy changes by what the flows carry" begin
            cp = cₚ(H2O, T_POOL)
            m_out = sol[ssys.drain.inlet.ṁ]
            carried = _cumulative_trapezoid(cp .* (m_in * T_hot .- m_out .* T), sol.t)
            @test cp * (M[end] * T[end] - M[1] * T[1]) ≈ carried[end] rtol = 2e-2
        end
    end
end

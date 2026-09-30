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

"""Trapezoid integral of `y` over the saved times `ts`."""
_trapezoid(y, ts) = sum((y[i] + y[i + 1]) / 2 * (ts[i + 1] - ts[i]) for i in 1:(length(ts) - 1))

@testset "Tank" begin
    @testset "a pinned tank holds its level and each port's head" begin
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0, side=1.5),
                           fixed_temperature=true, T0=T_POOL)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP)
        @named ambient = Environment()
        @named sys = assembly([connect(pool.bottom, breach.inlet),
                               connect(breach.outlet, ambient.port)],
                              pool, breach, ambient)
        ssys = mtkcompile(sys)
        sol = solve_steady(ssys)
        rho_g = ρ(H2O, T_POOL) * G_EARTH
        @test sol[ssys.pool.L] ≈ L_POOL
        @test sol[ssys.pool.bottom.p] ≈ ATM + rho_g * L_POOL
        @test sol[ssys.pool.side.p] ≈ ATM + rho_g * (L_POOL - 1.5)
        @test sol[ssys.breach.inlet.ṁ] == 0.0
    end

    @testset "a tank drains on the Torricelli curve and stops at uncovery" begin
        z_uncovery = 1.0
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0,),
                           fixed_temperature=true, T0=T_POOL)
        @named breach = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_eps=1e-3,
                                machine=StateMachine(; initial_state=:OPEN, initial_time=0.0))
        @named ambient = Environment()
        @named sys = assembly([connect(pool.bottom, breach.inlet),
                               connect(breach.outlet, ambient.port)],
                              pool, breach, ambient)
        ssys = mtkcompile(sys)
        watch = StateMachine(; initial_state=:INTACT, abort_states=(:UNCOVERED,))
        push!(watch, (:INTACT => :UNCOVERED, pool.L < z_uncovery, "uncovered"))

        sol = solve_transient(ssys, solve_steady(ssys), range(0.0, 5000.0; length=501);
                              overrides=[ssys.pool.pinned => false],
                              callbacks=machine_callbacks(ssys, watch))
        level = sol[ssys.pool.L]
        @test watch.state === :UNCOVERED
        @test sol.t[end] ≈ drain_time(L_POOL, z_uncovery, A_TANK, A_HOLE, CD_SHARP) atol = 0.5
        @test maximum(abs.(level .- drain_level.(sol.t, L_POOL, A_TANK, A_HOLE, CD_SHARP))) < 1e-3
        @test level[end] ≈ z_uncovery atol = 1e-3
    end

    @testset "a heated pool follows its own energy balance" begin
        m_in, T_hot, t_end = 2.0, 40.0, 3000.0
        @named pool = Tank(; area=A_TANK, L0=L_POOL, ports=(bottom=0.0, feed=0.0), T0=T_POOL)
        @named supply = Environment(; T=T_POOL)
        @named feed = Pump(; ṁ0=m_in)
        @named heater = HeatExchanger(T_hot)
        @named drain = Orifice(; area=A_HOLE, cd=CD_SHARP, dp_eps=1e-3, open_rate=1.0,
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
        # Pinned and fed at T_hot, the steady pool sits at T_hot; the run starts it cold.
        sol = solve_transient(ssys, solve_steady(ssys), _opening_grid(t_end; points=300);
                              overrides=[ssys.pool.pinned => false, ssys.pool.T => T_POOL])
        level, T = sol[ssys.pool.L], sol[ssys.pool.T]
        m_out = sol[ssys.drain.inlet.ṁ]

        function reduced!(dy, y, _, _)
            depth, T_pool = y
            rho = ρ(H2O, T_pool)
            out = CD_SHARP * A_HOLE * rho * sqrt(2 * G_EARTH * max(depth, 0.0))
            dy[1] = (m_in - out) / (rho * A_TANK)
            dy[2] = m_in * (T_hot - T_pool) / (rho * A_TANK * depth)
        end
        ref = solve(ODEProblem(reduced!, [L_POOL, T_POOL], (0.0, t_end)), Vern9();
                    reltol=1e-10, abstol=1e-12, saveat=sol.t)
        @test level ≈ ref[1, :] rtol = 1e-3
        @test T ≈ ref[2, :] rtol = 1e-3

        cp = cₚ(H2O, T_POOL)
        energy = ρ(H2O, T_POOL) * A_TANK * cp .* level .* T
        balance = _trapezoid(cp .* (m_in * T_hot .- m_out .* T), sol.t)
        @test energy[end] - energy[1] ≈ balance rtol = 1e-2
    end
end

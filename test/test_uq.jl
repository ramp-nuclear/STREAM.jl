using Test
using ModelingToolkit
using Random: Xoshiro
using OrdinaryDiffEq, SteadyStateDiffEq
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Components: Channel  # explicit: Base.Channel also exists
using STREAM.Thresholds
using STREAM.UQ
@isdefined(build_loop) || include("fixtures.jl")
if Base.find_package("Measurements") !== nothing
    using Measurements: Measurements
end
if Base.find_package("Distributions") !== nothing
    using Distributions: Distributions
end

"""
    second_order_remainders(resolve, x0, h, y0, dydx) -> (r_h, r_half)

The largest `|y(x0 + h) - y0 - dydx h|` over the outputs, at `h` and at `h / 2`, from full
re-solves. A right first derivative leaves a second-order remainder, which halving `h` divides
by four; a wrong one leaves a first-order remainder, which it only halves.
"""
function second_order_remainders(resolve, x0, h, y0, dydx)
    remainder(step) = maximum(abs.(resolve(x0 + step) .- y0 .- dydx .* step))
    return remainder(h), remainder(h / 2)
end

"""
    with(op, entry) -> Vector{Pair}

`op` with `entry` in it, replacing an entry for the same symbol rather than adding a second.
"""
with(op, entry) = [filter(e -> !isequal(first(e), first(entry)), op); entry]

@testset "Uncertainty" begin
    @testset "as_absolute of a number" begin
        u = Uncertainty(systematic_relative=0.1, statistical_relative=0.03,
                        systematic_absolute=2.0, statistical_absolute=4.0)
        sys, stat = as_absolute(u, 100.0)
        @test sys ≈ 12.0
        @test stat ≈ 5.0
    end

    @testset "as_absolute of a vector: relative parts per entry, absolute parts on each" begin
        sys, stat = as_absolute(Uncertainty(systematic_relative=0.1, statistical_absolute=[1.0, 2.0]),
                                [10.0, 20.0])
        @test sys ≈ [1.0, 2.0]
        @test stat == [1.0, 2.0]
    end

    @testset "sum: systematic parts add, statistical ones in quadrature" begin
        total = Uncertainty(systematic_absolute=1.0, statistical_relative=0.3) +
                Uncertainty(systematic_absolute=2.0, statistical_relative=0.4)
        @test total.systematic_absolute == 3.0
        @test total.statistical_relative ≈ 0.5
    end

    @testset "iszero and show" begin
        @test iszero(Uncertainty())
        @test !iszero(Uncertainty(statistical_absolute=[0.0, 1.0]))
        @test sprint(show, Uncertainty(systematic_relative=0.1)) ==
              "Uncertainty(systematic_relative=0.1)"
    end
end

# Python STREAM's `_simplemodel` from tests/test_analysis/test_uq.py, whose Jacobian is known.
simple(x) = [x.v1 + x.v2, x.v1 * x.v2, x.v1^x.v2, sum(x.vec), sin.(x.vec)...]
simple_parameters = (vec=[1.0, 2.0, 3.0], v1=2.0, v2=3.0)

@testset "FunctionUQ" begin
    s = local_sensitivities(FunctionUQ(simple, simple_parameters))

    @testset "nominal outputs and the known Jacobian" begin
        @test s.nominal ≈ [5.0, 6.0, 8.0, 6.0, sin(1.0), sin(2.0), sin(3.0)]
        @test size(jacobian(s)) == (7, 5)
        @test jacobian(s, :v1) ≈ reshape([1.0, 3.0, 3 * 2.0^2, 0, 0, 0, 0], 7, 1)
        @test jacobian(s, :v2) ≈ reshape([1.0, 2.0, 8 * log(2.0), 0, 0, 0, 0], 7, 1)
        @test jacobian(s, :vec)[5:7, :] ≈ [cos(1.0) 0 0; 0 cos(2.0) 0; 0 0 cos(3.0)]
        @test jacobian(s, :vec)[4, :] == [1.0, 1.0, 1.0]
    end

    @testset "uq matches Python's known result" begin
        result = uq(s,
            :vec => Uncertainty(systematic_relative=[0.1, 0.1, 0.1],
                                statistical_absolute=[0.2, 0.2, 0.2]),
            :v1 => Uncertainty(systematic_absolute=1.0),
            :v2 => Uncertainty(statistical_absolute=1.0),
        )
        @test result.sys[1:2] ≈ [1.0, 3.0]
        @test result.stat[1] ≈ 1.0
        # The sum moves by the whole systematic shift of the vector, 0.1 * (1 + 2 + 3).
        @test result.sys[4] ≈ 0.6
        @test result.stat[4] ≈ sqrt(3) * 0.2
    end

    @testset "no uncertainty gives zero" begin
        none = uq(s)
        @test all(iszero, none.sys) && all(iszero, none.stat)
    end

    @testset "a second source only adds" begin
        one_source = uq(s, :v1 => Uncertainty(1.0, 0.5, 0.2, 0.1))
        two_sources = uq(s, :v1 => Uncertainty(1.0, 0.5, 0.2, 0.1),
                         :v2 => Uncertainty(statistical_absolute=0.3))
        @test all(two_sources.sys .>= one_source.sys)
        @test all(two_sources.stat .>= one_source.stat)
        @test sum(two_sources.stat .- one_source.stat) > 0
    end

    @testset "a larger uncertainty gives a larger result" begin
        small = uq(s, :v1 => Uncertainty(0.5, 0.5, 0.5, 0.5))
        large = uq(s, :v1 => Uncertainty(1.0, 1.0, 1.0, 1.0))
        @test all(large.sys .>= small.sys) && all(large.stat .>= small.stat)
        @test sum(large.sys .- small.sys) + sum(large.stat .- small.stat) > 0
    end

    @testset "an unknown input or an output that is not an array is refused" begin
        @test_throws ArgumentError jacobian(s, :v3)
        @test_throws ArgumentError uq(s, :v3 => Uncertainty(statistical_absolute=1.0))
        @test_throws ArgumentError local_sensitivities(FunctionUQ(x -> (x.a, x.a), (a=1.0,)))
    end

    @testset "a problem computes nothing until asked" begin
        calls = Ref(0)
        prob = FunctionUQ(x -> (calls[] += 1; x.a), (a=1.0,))
        @test calls[] == 0
        local_sensitivities(prob)
        @test calls[] > 0
    end
end

@testset "SteadyUQ" begin
    ssys = build_loop(; n=5)
    op = [ssys.ch.inlet.ṁ => 0.5]
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    outputs = [ssys.ch.T_out, ssys.ch.inlet.ṁ, ssys.ch.T[3]]
    s = local_sensitivities(SteadyUQ(ssys, op, parameters; output=outputs))
    J = jacobian(s)

    @testset "the nominal outputs are those of the steady solve" begin
        sol = solve_steady(ssys, op; abstol=1e-10, reltol=1e-10)
        @test s.nominal ≈ sol[outputs] rtol=1e-12
        @test s.values == [40.0, 3.0e4]
    end

    @testset "derivatives have the physical signs" begin
        @test size(J) == (3, 2)
        # The wall is fixed, so a warmer inlet warms the outlet by less than a degree per degree.
        @test 0 < J[1, 1] < 1
        # More head, more flow, and a shorter stay in the heated pipe.
        @test J[2, 2] > 0
        @test J[1, 2] < 0
    end

    @testset "derivatives leave a second-order remainder against re-solves" begin
        for (i, p) in enumerate(parameters)
            x0 = s.values[i]
            resolve(x) = solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12)[outputs]
            r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, s.nominal, J[:, i])
            @test r_half < r_h / 3
        end
    end

    @testset "the same derivatives whichever solver found the root" begin
        by_integration = SteadyUQ(ssys, op, parameters; output=outputs,
                                  solver=DynamicSS(Rodas5P()))
        @test jacobian(local_sensitivities(by_integration)) ≈ J rtol=1e-5
    end

    @testset "an output given as a function reads the same solution" begin
        as_function = SteadyUQ(ssys, op, parameters; output=sol -> sol[outputs])
        @test jacobian(local_sensitivities(as_function)) ≈ J rtol=1e-12
    end

    @testset "every entry that is not a parameter is named in one error" begin
        err = try
            SteadyUQ(ssys, op, [ssys.ch.T_out, ssys.pump.dP_pump, ssys.ch.inlet.ṁ]; output=outputs)
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("T_out", err.msg) && occursin("inlet", err.msg)
        @test !occursin("dP_pump", err.msg)
    end
end

@testset "SteadyUQ through a ChannelState and a pipe built from two knobs" begin
    gap = @design_knob gap = 0.0024
    width = @design_knob width = 0.067
    geometry = PipeGeometry_rectangular(0.6, width, gap, 0.063)
    n = 10
    slab = Slab(; x=range(0.0, 0.00127; length=3), z=range(0.0, 0.6; length=n + 1), y=0.063,
                material=Solid(2700.0, 900.0, 180.0))
    @named fuel = HeatDiffusion(slab; power=2.5e4)
    @named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
    @named cell = symmetric_plate(ch, fuel)
    @named pump = Pump(2.0e4)
    @named hx = HeatExchanger(40.0)
    @named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.inlet.p ~ 1.7e5],
                           pump, hx, cell)
    ssys = mtkcompile(loop)
    op = [knob_defaults([gap, width]); ssys.cell.ch.inlet.ṁ => 0.4]

    function margins(sol)
        state = ChannelState(sol, ssys.cell.ch; pipe=geometry)
        return [minimum(chfr(q_CHF_sudo_kaminaga)(state));
                minimum(bergles_rohsenow_t_onb(state) .- state.T_wall);
                q_OFI_whittle_forgan(state)]
    end
    parameters = [gap, width, ssys.cell.fuel.power]
    s = local_sensitivities(SteadyUQ(ssys, op, parameters; output=margins))
    J = jacobian(s)

    @testset "the nominal margins are those of the numeric pipe" begin
        sol = solve_steady(ssys, op; abstol=1e-10, reltol=1e-10)
        numeric_pipe = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
        plain = threshold_analysis(sol, ssys.cell.ch; pipe=numeric_pipe,
                                   chfr=chfr(q_CHF_sudo_kaminaga), onb=bergles_rohsenow_t_onb,
                                   ofi=q_OFI_whittle_forgan)
        state = ChannelState(sol, ssys.cell.ch; pipe=geometry)
        @test state.pipe == numeric_pipe
        @test s.nominal ≈ [minimum(plain.chfr); minimum(plain.onb .- state.T_wall); plain.ofi]
    end

    @testset "more power, less margin to CHF and to ONB" begin
        @test J[1, 3] < 0 && J[2, 3] < 0
    end

    @testset "derivatives in both knobs leave a second-order remainder" begin
        for (i, p) in enumerate(parameters)
            x0 = s.values[i]
            resolve(x) = margins(solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12))
            r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, s.nominal, J[:, i])
            @test r_half < r_h / 3
        end
    end
end

# tests/test_analysis/test_uq.py::test_uq_improves_with_mdot_for_simple_channel. Python heats
# a ChannelAndContacts through its correlation; here a Channel with a fixed coefficient on
# each face, held at the same walls, since the property is the one the flow gives.
@testset "CHF less its uncertainty rises with the flow" begin
    T_low = @design_knob T_low = 70.0
    n = 20
    geometry = PipeGeometry_rectangular(0.5, 0.06, 0.0025, 0.06)
    @named pump = Pump(; ṁ0=0.1)
    @named hx = HeatExchanger(20.0)
    @named ch = Channel(; n, geometry, h_left=1.0e4, h_right=1.0e4)
    walls = [T_low + offset for offset in range(0.0, 15.0; length=n)]
    connections = [inseries(pump, hx, ch, pump), pump.inlet.p ~ 2ATM,
                   ch.T_wall_left .~ walls, ch.T_wall_right .~ walls]
    @named loop = assembly(connections, pump, hx, ch)
    ssys = mtkcompile(loop)

    chf(sol) = q_CHF_sudo_kaminaga(ChannelState(sol, ssys.ch; pipe=geometry))
    worst = map(range(0.04, 0.2; length=10)) do ṁ
        prob = SteadyUQ(ssys, [knob_defaults([T_low]); ssys.pump.ṁ0 => ṁ],
                        [ssys.pump.ṁ0, T_low]; output=chf)
        result = uq(local_sensitivities(prob), ssys.pump.ṁ0 => Uncertainty(statistical_relative=0.05),
                    T_low => Uncertainty(statistical_relative=0.7))
        minimum(result.nominal .- result.stat)
    end
    @test all(diff(worst) .>= 0)
end

@testset "TransientUQ from its operating point" begin
    ssys = build_loop(; n=5)
    settled = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    # The loop settled at a 40 °C inlet, then the inlet steps to 60 °C.
    op = [unknowns(ssys) .=> settled[unknowns(ssys)]; ssys.bc.T_bc => 60.0]
    times = 0.0:2.0:20.0
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    s = local_sensitivities(TransientUQ(ssys, op, parameters, times; output=[ssys.ch.T_out],
                                        abstol=1e-10, reltol=1e-10))
    run_at(p, x) = solve_transient(ssys, with(op, p => x), times; abstol=1e-10, reltol=1e-10)
    J = jacobian(s)

    @testset "the nominal outputs are those of the transient" begin
        @test length(s.nominal) == length(times)
        @test s.nominal ≈ run_at(ssys.bc.T_bc, 60.0)[ssys.ch.T_out] rtol=1e-8
    end

    @testset "the outlet follows the inlet once the water has crossed the pipe" begin
        # The outlet starts where the steady state left it, whatever the new inlet
        # temperature. The water crosses the pipe in under a tenth of a second, so from the
        # first saved step on it follows the inlet, by less than a degree per degree.
        @test J[1, 1] ≈ 0 atol=1e-8
        @test all(J[2:end, 1] .≈ J[end, 1])
        @test 0 < J[end, 1] < 1
    end

    @testset "derivatives leave a second-order remainder against re-solves" begin
        for (i, p) in enumerate(parameters)
            x0 = s.values[i]
            resolve(x) = run_at(p, x)[ssys.ch.T_out]
            r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, s.nominal, J[:, i])
            @test r_half < r_h / 3
        end
    end

    @testset "an unknown start is refused" begin
        @test_throws ArgumentError TransientUQ(ssys, op, parameters, times;
                                               output=[ssys.ch.T_out], start=:somewhere)
    end
end

@testset "TransientUQ from its steady state" begin
    ssys = build_loop(; n=5)
    op = [ssys.ch.inlet.ṁ => 0.5]
    overrides = [ssys.bc.T_bc => 60.0]
    times = 0.0:2.0:20.0
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    s = local_sensitivities(TransientUQ(ssys, op, parameters, times; output=[ssys.ch.T_out],
                                        start=:steady, overrides, abstol=1e-10, reltol=1e-10))
    J = jacobian(s)

    @testset "an overridden input acts only through where the run starts" begin
        # At t = 0 the inlet temperature acts as it does on the steady state, and less as
        # the run forgets its start.
        steady = local_sensitivities(SteadyUQ(ssys, op, parameters; output=[ssys.ch.T_out]))
        @test J[1, :] ≈ vec(jacobian(steady)) rtol=1e-6
        @test abs(J[end, 1]) < abs(J[1, 1]) / 2
    end

    @testset "an input acting on both matches re-solves" begin
        # Settle at each pump head, then run from there with that head held.
        head = ssys.pump.dP_pump
        function resolve(x)
            settled = solve_steady(ssys, with(op, head => x); abstol=1e-10, reltol=1e-10)
            run = solve_transient(ssys, settled, times; overrides=[overrides; head => x],
                                  abstol=1e-10, reltol=1e-10)
            return run[ssys.ch.T_out]
        end
        @test s.nominal ≈ resolve(s.values[2]) rtol=1e-8
        r_h, r_half = second_order_remainders(resolve, s.values[2], 0.02s.values[2],
                                              s.nominal, J[:, 2])
        @test r_half < r_h / 3
    end
end

@testset "TransientUQ of a DAE whose start is re-initialized" begin
    # A plate between two channels: the wall temperatures are algebraic, and halving the pump
    # head at the start moves them at once, so the start is solved again. Its derivatives
    # have to come through that, at t = 0 as well as after.
    n = 5
    geometry = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
    slab = Slab(; x=range(0.0, 0.00127; length=3), z=range(0.0, 0.6; length=n + 1), y=0.063,
                material=Solid(2700.0, 900.0, 180.0))
    @named fuel = HeatDiffusion(slab; power=2.5e4)
    @named ch = ChannelAndContacts(; n, geometry, g=-G_EARTH)
    @named cell = symmetric_plate(ch, fuel)
    @named pump = Pump(2.0e4)
    @named hx = HeatExchanger(40.0)
    @named loop = assembly([inseries(pump, hx, cell.ch, pump), pump.inlet.p ~ 1.7e5],
                           pump, hx, cell)
    ssys = mtkcompile(loop)
    op = [ssys.cell.ch.inlet.ṁ => 0.4]
    overrides = [ssys.pump.dP_pump => 1.0e4]
    times = [0.0, 0.05, 0.5]
    outputs = [ssys.cell.ch.T_wall_left[n], ssys.cell.fuel.T[n, 1]]
    parameters = [ssys.cell.fuel.power, ssys.hx.T_bc]
    s = local_sensitivities(TransientUQ(ssys, op, parameters, times; output=outputs,
                                        start=:steady, overrides, abstol=1e-10, reltol=1e-10))
    J = jacobian(s)

    @testset "every output depends on every input, from t = 0 on" begin
        @test all(!iszero, J)
    end

    @testset "derivatives leave a second-order remainder against re-solves" begin
        # The reference re-solves in plain numbers and holds the differential states at the
        # start, as local_sensitivities and solve_transient do.
        for (i, p) in enumerate(parameters)
            function resolve(x)
                settled = solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12)
                run = solve_transient(ssys, settled, times; overrides=[overrides; p => x],
                                      abstol=1e-10, reltol=1e-10)
                return reduce(vcat, [run[v] for v in outputs])
            end
            x0 = s.values[i]
            r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, s.nominal, J[:, i])
            @test r_half < r_h / 3
        end
    end
end

@testset "monte_carlo of a transient that trips a StateMachine" begin
    # Rods withdraw until the power passes trip_at, then fall in. The trip time is the
    # machine's, outside the problem, so derivatives cannot follow it and sampling has to.
    @parameters trip_at = 1.2
    machine = StateMachine()
    withdrawal(t) = 2.0e-4 * t
    scram(τ) = -0.05 * clamp(τ / 0.5, 0.0, 1.0)
    rods = ReactivityController(machine=machine) do state, t_state, t
        state === :SCRAM ? withdrawal(t) + scram(t - t_state) : withdrawal(t)
    end
    @named pk = PointKinetics(rods)
    machine.transitions = [(:NORMAL => :SCRAM, pk.P_neutron > trip_at, "high power")]
    @named reactor = assembly([], pk; parameters=[trip_at])
    ssys = mtkcompile(reactor)
    times = 0.0:0.1:30.0
    tripped(sol) = [machine.t_state, maximum(sol[ssys.pk.P_neutron])]
    prob = TransientUQ(ssys, Pair[], [trip_at], times; output=tripped,
                       callbacks=machine_callbacks(ssys, machine), machines=(machine,))
    late = monte_carlo(prob, trip_at => Uncertainty(systematic_relative=0.1); n=3)

    @testset "the nominal run trips as a direct one does" begin
        Components.reset!(machine)
        direct = solve_transient(ssys, times; callbacks=machine_callbacks(ssys, machine))
        @test machine.state === :SCRAM
        @test late.nominal ≈ [machine.t_state, maximum(direct[ssys.pk.P_neutron])]
    end

    @testset "a setpoint read 10% high trips every run later, and higher" begin
        @test all(late.samples[1, :] .> late.nominal[1])
        @test all(late.samples[2, :] .> late.nominal[2])
    end

    @testset "a scattered setpoint scatters the trip time" begin
        scattered = monte_carlo(prob, trip_at => Uncertainty(statistical_relative=0.05);
                                n=50, rng=Xoshiro(2))
        @test scattered.failed == 0 && scattered.std[1] > 0
    end

    @testset "derivatives are refused" begin
        @test_throws ArgumentError local_sensitivities(prob)
    end
end

@testset "monte_carlo" begin
    n = 20_000

    @testset "a linear model: the bias shifts the mean by J s, the spread is J σ" begin
        linear = FunctionUQ(x -> 2x.a + 3x.b, (a=1.0, b=2.0))
        r = monte_carlo(linear, :a => Uncertainty(systematic_absolute=0.5),
                        :b => Uncertainty(statistical_absolute=0.2); n, rng=Xoshiro(7))
        @test size(r.samples) == (1, n) && r.failed == 0
        @test r.mean[1] ≈ r.nominal[1] + 1.0 atol=4 * 0.6 / sqrt(n)
        @test r.std[1] ≈ 0.6 rtol=0.03
        first_order = uq(local_sensitivities(linear), :b => Uncertainty(statistical_absolute=0.2))
        @test r.std ≈ first_order.stat rtol=0.03
    end

    @testset "a curved model: the mean moves where first order does not" begin
        # exp(a) for a normal a has the mean exp(σ²/2), where first order stays at exp(0) = 1.
        curved = FunctionUQ(x -> exp(x.a), (a=0.0,))
        r = monte_carlo(curved, :a => Uncertainty(statistical_absolute=0.5); n, rng=Xoshiro(7))
        @test r.mean[1] ≈ exp(0.5^2 / 2) atol=0.02
        @test r.nominal[1] == 1.0
    end

    @testset "a steady state: a small uncertainty spreads as first order says" begin
        ssys = build_loop(; n=5)
        steady = SteadyUQ(ssys, [ssys.ch.inlet.ṁ => 0.5], [ssys.bc.T_bc];
                          output=[ssys.ch.T_out, ssys.ch.inlet.ṁ])
        u = ssys.bc.T_bc => Uncertainty(statistical_absolute=0.5)
        r = monte_carlo(steady, u; n=400, rng=Xoshiro(3))
        @test r.failed == 0
        @test r.std ≈ uq(local_sensitivities(steady), u).stat rtol=0.15
    end
end

@testset "Distribution inputs" begin
    if !@isdefined(Distributions)
        @warn "Distributions is not installed in this environment, so Distribution inputs " *
              "are not tested. Pkg.test() installs it."
    else
        (; Normal, MvNormal, Uniform) = Distributions
        prob = FunctionUQ(simple, simple_parameters)
        s = local_sensitivities(prob)

        @testset "a normal around the nominal value is a statistical uncertainty" begin
            as_normal = uq(s, :v1 => Normal(2.0, 0.3))
            @test as_normal.stat ≈ uq(s, :v1 => Uncertainty(statistical_absolute=0.3)).stat
            @test all(iszero, as_normal.sys)
        end

        @testset "a shifted mean is the systematic part" begin
            shifted = uq(s, :v1 => Normal(2.5, 0.3))
            @test shifted.sys ≈ abs.(vec(jacobian(s, :v1)) .* 0.5)
        end

        @testset "correlated entries propagate their covariance" begin
            # The sum of the vector has the variance sum(C).
            C = [0.04 0.03 0.0; 0.03 0.09 0.0; 0.0 0.0 0.01]
            correlated = uq(s, :vec => MvNormal([1.0, 2.0, 3.0], C))
            @test correlated.stat[4] ≈ sqrt(sum(C))
            sampled = monte_carlo(prob, :vec => MvNormal([1.0, 2.0, 3.0], C); n=20_000,
                                  rng=Xoshiro(4))
            @test sampled.std[4] ≈ sqrt(sum(C)) rtol=0.03
        end

        @testset "a uniform spread of width w has the standard deviation w / √12" begin
            linear = FunctionUQ(x -> 2x.a, (a=2.0,))
            r = monte_carlo(linear, :a => Uniform(1.9, 2.1); n=20_000, rng=Xoshiro(5))
            @test r.std[1] ≈ 2 * 0.2 / sqrt(12) rtol=0.03
            @test r.mean[1] ≈ 4.0 atol=0.01
        end

        @testset "a scalar distribution on a vector input is refused" begin
            @test_throws ArgumentError uq(s, :vec => Normal(2.0, 0.1))
        end
    end
end

@testset "measurements" begin
    if !@isdefined(Measurements)
        @warn "Measurements is not installed in this environment, so UQ.measurements is not " *
              "tested. Pkg.test() installs it."
    else
        s = local_sensitivities(FunctionUQ(simple, simple_parameters))
        uncertainties = (:v1 => Uncertainty(statistical_absolute=0.1),
                         :vec => Uncertainty(statistical_relative=0.05))
        y = measurements(s, uncertainties...)

        @testset "values and standard deviations are those of uq" begin
            expected = uq(s, uncertainties...)
            @test Measurements.value.(y) ≈ expected.nominal
            @test Measurements.uncertainty.(y) ≈ expected.stat
        end

        @testset "outputs keep the inputs they share" begin
            # y[1] = v1 + v2 and y[2] = v1 v2 move by 1 and by v2 = 3 per unit of v1, so
            # y[2] - 3 y[1] does not depend on v1 at all, where adding the two uncertainties
            # in quadrature would give it some.
            @test Measurements.uncertainty(y[2] - 3 * y[1]) ≈ 0 atol=1e-12
        end

        @testset "a systematic part is refused" begin
            @test_throws ArgumentError measurements(s, :v1 => Uncertainty(systematic_absolute=1.0))
        end
    end
end

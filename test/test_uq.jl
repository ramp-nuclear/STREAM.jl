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
    u = Uncertainty(systematic_relative=0.1, statistical_relative=0.03,
                    systematic_absolute=2.0, statistical_absolute=4.0)
    sys, stat = as_absolute(u, 100.0)
    @test sys ≈ 12.0
    @test stat ≈ 5.0

    # A vector input: relative parts scale entry by entry, absolute parts apply to each.
    sys, stat = as_absolute(Uncertainty(systematic_relative=0.1, statistical_absolute=[1.0, 2.0]),
                            [10.0, 20.0])
    @test sys ≈ [1.0, 2.0]
    @test stat == [1.0, 2.0]

    total = Uncertainty(systematic_absolute=1.0, statistical_relative=0.3) +
            Uncertainty(systematic_absolute=2.0, statistical_relative=0.4)
    @test total.systematic_absolute == 3.0
    @test total.statistical_relative ≈ 0.5

    @test iszero(Uncertainty())
    @test !iszero(Uncertainty(statistical_absolute=[0.0, 1.0]))
    @test sprint(show, Uncertainty(systematic_relative=0.1)) ==
          "Uncertainty(systematic_relative=0.1)"
end

# Python STREAM's `_simplemodel` from tests/test_analysis/test_uq.py, whose Jacobian is known.
simple(x) = [x.v1 + x.v2, x.v1 * x.v2, x.v1^x.v2, sum(x.vec), sin.(x.vec)...]
simple_parameters = (vec=[1.0, 2.0, 3.0], v1=2.0, v2=3.0)

@testset "UQModel of a function" begin
    model = UQModel(simple, simple_parameters)
    @test model.nominal ≈ [5.0, 6.0, 8.0, 6.0, sin(1.0), sin(2.0), sin(3.0)]

    J = jacobian(model)
    @test size(J) == (7, 5)
    @test jacobian(model, :v1) ≈ reshape([1.0, 3.0, 3 * 2.0^2, 0, 0, 0, 0], 7, 1)
    @test jacobian(model, :v2) ≈ reshape([1.0, 2.0, 8 * log(2.0), 0, 0, 0, 0], 7, 1)
    @test jacobian(model, :vec)[5:7, :] ≈ [cos(1.0) 0 0; 0 cos(2.0) 0; 0 0 cos(3.0)]
    @test jacobian(model, :vec)[4, :] == [1.0, 1.0, 1.0]

    # test_uq_of_simplemodel_by_known_result
    result = uq(model,
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

    # test_uq_of_no_uncertainty_is_zero
    none = uq(model)
    @test all(iszero, none.sys) && all(iszero, none.stat)

    # test_uq_of_multiple_sources_strictly_larger_than_one, at fixed values
    one_source = uq(model, :v1 => Uncertainty(1.0, 0.5, 0.2, 0.1))
    two_sources = uq(model, :v1 => Uncertainty(1.0, 0.5, 0.2, 0.1),
                     :v2 => Uncertainty(statistical_absolute=0.3))
    @test all(two_sources.sys .>= one_source.sys) && all(two_sources.stat .>= one_source.stat)
    @test sum(two_sources.stat .- one_source.stat) > 0

    # test_uq_of_larger_uncertainty_is_larger
    small = uq(model, :v1 => Uncertainty(0.5, 0.5, 0.5, 0.5))
    large = uq(model, :v1 => Uncertainty(1.0, 1.0, 1.0, 1.0))
    @test all(large.sys .>= small.sys) && all(large.stat .>= small.stat)
    @test sum(large.sys .- small.sys) + sum(large.stat .- small.stat) > 0

    @test_throws ArgumentError jacobian(model, :v3)
    @test_throws ArgumentError uq(model, :v3 => Uncertainty(statistical_absolute=1.0))
    @test_throws ArgumentError UQModel(x -> (x.a, x.a), (a=1.0,))
end

@testset "UQModel of a steady state" begin
    ssys = build_loop(; n=5)
    op = [ssys.ch.inlet.ṁ => 0.5]
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    outputs = [ssys.ch.T_out, ssys.ch.inlet.ṁ, ssys.ch.T[3]]
    model = UQModel(ssys, op, parameters; output=outputs)

    sol = solve_steady(ssys, op; abstol=1e-10, reltol=1e-10)
    @test model.nominal ≈ sol[outputs] rtol=1e-12
    @test model.values == [40.0, 3.0e4]

    J = jacobian(model)
    @test size(J) == (3, 2)
    # A warmer inlet warms the outlet by less than a degree per degree: the wall is fixed.
    @test 0 < J[1, 1] < 1
    # More head, more flow, and a shorter stay in the heated pipe.
    @test J[2, 2] > 0
    @test J[1, 2] < 0

    # The derivatives are those of the steady state itself, not of a solver's iterations:
    # each leaves only a second-order remainder against full re-solves.
    for (i, p) in enumerate(parameters)
        x0 = model.values[i]
        resolve(x) = solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12)[outputs]
        r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, model.nominal, J[:, i])
        @test r_half < r_h / 3
    end

    # The same derivatives whichever steady solver found the root.
    by_integration = UQModel(ssys, op, parameters; output=outputs,
                             solver=DynamicSS(Rodas5P()))
    @test jacobian(by_integration) ≈ J rtol=1e-5

    # An output given as a function reads the same solution.
    as_function = UQModel(ssys, op, parameters; output=s -> s[outputs])
    @test jacobian(as_function) ≈ J rtol=1e-12

    @test_throws ArgumentError UQModel(ssys, op, [ssys.ch.T_out]; output=outputs)
end

@testset "UQModel through a ChannelState and a pipe built from a knob" begin
    gap = @design_knob gap = 0.0024
    geometry = PipeGeometry_rectangular(0.6, 0.067, gap, 0.063)
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
    op = [knob_defaults([gap]); ssys.cell.ch.inlet.ṁ => 0.4]

    function margins(sol)
        state = ChannelState(sol, ssys.cell.ch; pipe=geometry)
        return [minimum(chfr(q_CHF_sudo_kaminaga)(state));
                minimum(bergles_rohsenow_t_onb(state) .- state.T_wall);
                q_OFI_whittle_forgan(state)]
    end
    parameters = [gap, ssys.cell.fuel.power]
    model = UQModel(ssys, op, parameters; output=margins)

    # The nominal margins are the ones the plain solution gives with the numeric pipe.
    sol = solve_steady(ssys, op; abstol=1e-10, reltol=1e-10)
    numeric_pipe = PipeGeometry_rectangular(0.6, 0.067, 0.0024, 0.063)
    plain = threshold_analysis(sol, ssys.cell.ch; pipe=numeric_pipe,
                               chfr=chfr(q_CHF_sudo_kaminaga), onb=bergles_rohsenow_t_onb,
                               ofi=q_OFI_whittle_forgan)
    state = ChannelState(sol, ssys.cell.ch; pipe=geometry)
    @test model.nominal ≈ [minimum(plain.chfr); minimum(plain.onb .- state.T_wall); plain.ofi]

    J = jacobian(model)
    # More power, less margin to CHF and to ONB.
    @test J[1, 2] < 0 && J[2, 2] < 0
    for (i, p) in enumerate(parameters)
        x0 = model.values[i]
        resolve(x) = margins(solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12))
        r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, model.nominal, J[:, i])
        @test r_half < r_h / 3
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
        model = UQModel(ssys, [knob_defaults([T_low]); ssys.pump.ṁ0 => ṁ],
                        [ssys.pump.ṁ0, T_low]; output=chf)
        result = uq(model, ssys.pump.ṁ0 => Uncertainty(statistical_relative=0.05),
                    T_low => Uncertainty(statistical_relative=0.7))
        minimum(result.nominal .- result.stat)
    end
    @test all(diff(worst) .>= 0)
end

@testset "UQModel of a transient from its operating point" begin
    ssys = build_loop(; n=5)
    settled = solve_steady(ssys, [ssys.ch.inlet.ṁ => 0.5])
    # The loop settled at a 40 °C inlet, then the inlet steps to 60 °C.
    op = [unknowns(ssys) .=> settled[unknowns(ssys)]; ssys.bc.T_bc => 60.0]
    times = 0.0:2.0:20.0
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    model = UQModel(ssys, op, parameters, times; output=[ssys.ch.T_out],
                    abstol=1e-10, reltol=1e-10)
    @test length(model.nominal) == length(times)
    run_at(p, x) = solve_transient(ssys, with(op, p => x), times; abstol=1e-10, reltol=1e-10)
    @test model.nominal ≈ run_at(ssys.bc.T_bc, 60.0)[ssys.ch.T_out] rtol=1e-8

    J = jacobian(model)
    # The outlet starts where the steady state left it, whatever the new inlet temperature.
    # The water crosses the pipe in under a tenth of a second, so from the first saved step
    # on the outlet follows the inlet, by less than a degree per degree past the fixed wall.
    @test J[1, 1] ≈ 0 atol=1e-8
    @test all(J[2:end, 1] .≈ J[end, 1])
    @test 0 < J[end, 1] < 1
    for (i, p) in enumerate(parameters)
        x0 = model.values[i]
        resolve(x) = run_at(p, x)[ssys.ch.T_out]
        r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, model.nominal, J[:, i])
        @test r_half < r_h / 3
    end
    @test_throws ArgumentError UQModel(ssys, op, parameters, times; output=[ssys.ch.T_out],
                                       start=:somewhere)
end

@testset "UQModel of a transient from its steady state" begin
    ssys = build_loop(; n=5)
    op = [ssys.ch.inlet.ṁ => 0.5]
    overrides = [ssys.bc.T_bc => 60.0]
    times = 0.0:2.0:20.0
    parameters = [ssys.bc.T_bc, ssys.pump.dP_pump]
    model = UQModel(ssys, op, parameters, times; output=[ssys.ch.T_out], start=:steady,
                    overrides, abstol=1e-10, reltol=1e-10)
    J = jacobian(model)

    # The inlet temperature is overridden, so it acts only through where the run starts: at
    # t = 0 as it does on the steady state, and less as the run forgets its start.
    steady = UQModel(ssys, op, parameters; output=[ssys.ch.T_out])
    @test J[1, :] ≈ vec(jacobian(steady)) rtol=1e-6
    @test abs(J[end, 1]) < abs(J[1, 1]) / 2

    # The pump head acts on both, and its derivative matches full re-solves, settling at
    # each head and running from there with that head held.
    head = ssys.pump.dP_pump
    function resolve(x)
        settled = solve_steady(ssys, with(op, head => x); abstol=1e-10, reltol=1e-10)
        run = solve_transient(ssys, settled, times; overrides=[overrides; head => x],
                              abstol=1e-10, reltol=1e-10)
        return run[ssys.ch.T_out]
    end
    @test model.nominal ≈ resolve(model.values[2]) rtol=1e-8
    r_h, r_half = second_order_remainders(resolve, model.values[2], 0.02model.values[2],
                                          model.nominal, J[:, 2])
    @test r_half < r_h / 3
end

@testset "UQModel of a DAE transient whose start is re-initialized" begin
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
    model = UQModel(ssys, op, parameters, times; output=outputs, start=:steady, overrides,
                    abstol=1e-10, reltol=1e-10)
    J = jacobian(model)
    @test all(!iszero, J)

    # The reference re-solves in plain numbers and holds the differential states at the
    # start, as UQModel does. MTK's own initialization moves a plate temperature here when
    # the head is overridden, which a temperature cannot do in an instant.
    for (i, p) in enumerate(parameters)
        function resolve(x)
            settled = solve_steady(ssys, with(op, p => x); abstol=1e-12, reltol=1e-12)
            start = [unknowns(ssys) .=> settled[unknowns(ssys)]; overrides; p => x]
            prob = ODEProblem(ssys, start, (0.0, last(times)); build_initializeprob=false,
                              warn_initialize_determined=false)
            run = solve(prob, Rodas5P(); saveat=times, tstops=times, abstol=1e-10,
                        reltol=1e-10, initializealg=OrdinaryDiffEq.BrownFullBasicInit())
            return reduce(vcat, [run[v] for v in outputs])
        end
        x0 = model.values[i]
        r_h, r_half = second_order_remainders(resolve, x0, 0.02x0, model.nominal, J[:, i])
        @test r_half < r_h / 3
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
    model = UQModel(ssys, Pair[], [trip_at], times; output=tripped,
                    callbacks=machine_callbacks(ssys, machine), machines=(machine,))

    Components.reset!(machine)
    direct = solve_transient(ssys, times; callbacks=machine_callbacks(ssys, machine))
    @test machine.state === :SCRAM
    @test model.nominal ≈ [machine.t_state, maximum(direct[ssys.pk.P_neutron])]

    # A setpoint read 10% high trips every run later, and higher.
    late = monte_carlo(model, trip_at => Uncertainty(systematic_relative=0.1); n=3)
    @test all(late.samples[1, :] .> model.nominal[1])
    @test all(late.samples[2, :] .> model.nominal[2])

    scattered = monte_carlo(model, trip_at => Uncertainty(statistical_relative=0.05);
                            n=50, rng=Xoshiro(2))
    @test scattered.failed == 0 && scattered.std[1] > 0

    @test_throws ArgumentError jacobian(model)
end

@testset "monte_carlo" begin
    n = 20_000
    # A linear model: the bias shifts the mean by exactly J s, and the spread is J σ.
    linear = UQModel(x -> 2x.a + 3x.b, (a=1.0, b=2.0))
    r = monte_carlo(linear, :a => Uncertainty(systematic_absolute=0.5),
                    :b => Uncertainty(statistical_absolute=0.2); n, rng=Xoshiro(7))
    @test size(r.samples) == (1, n) && r.failed == 0
    @test r.mean[1] ≈ linear.nominal[1] + 1.0 atol=4 * 0.6 / sqrt(n)
    @test r.std[1] ≈ 0.6 rtol=0.03
    @test r.std ≈ uq(linear, :b => Uncertainty(statistical_absolute=0.2)).stat rtol=0.03

    # exp(a) for a normal a has mean exp(σ²/2), which first order, at exp(0) = 1, misses.
    curved = UQModel(x -> exp(x.a), (a=0.0,))
    r = monte_carlo(curved, :a => Uncertainty(statistical_absolute=0.5); n, rng=Xoshiro(7))
    @test r.mean[1] ≈ exp(0.5^2 / 2) atol=0.02
    @test curved.nominal[1] == 1.0

    # A steady state, sampled by re-solving: for a small uncertainty the spread is the
    # first-order one.
    ssys = build_loop(; n=5)
    steady = UQModel(ssys, [ssys.ch.inlet.ṁ => 0.5], [ssys.bc.T_bc];
                     output=[ssys.ch.T_out, ssys.ch.inlet.ṁ])
    u = ssys.bc.T_bc => Uncertainty(statistical_absolute=0.5)
    r = monte_carlo(steady, u; n=400, rng=Xoshiro(3))
    @test r.failed == 0
    @test r.std ≈ uq(steady, u).stat rtol=0.15
end

@testset "measurements" begin
    if !@isdefined(Measurements)
        @warn "Measurements is not installed in this environment, so UQ.measurements is not " *
              "tested. Pkg.test() installs it."
    else
        model = UQModel(simple, simple_parameters)
        uncertainties = (:v1 => Uncertainty(statistical_absolute=0.1),
                         :vec => Uncertainty(statistical_relative=0.05))
        y = measurements(model, uncertainties...)
        expected = uq(model, uncertainties...)
        @test Measurements.value.(y) ≈ expected.nominal
        @test Measurements.uncertainty.(y) ≈ expected.stat
        # The outputs remember the inputs they share. y[1] = v1 + v2 and y[2] = v1 v2 move by
        # 1 and by v2 = 3 per unit of v1, so y[2] - 3 y[1] does not depend on v1 at all, where
        # adding the two uncertainties in quadrature would give it some.
        @test Measurements.uncertainty(y[2] - 3 * y[1]) ≈ 0 atol=1e-12
        @test_throws ArgumentError measurements(model, :v1 => Uncertainty(systematic_absolute=1.0))
    end
end

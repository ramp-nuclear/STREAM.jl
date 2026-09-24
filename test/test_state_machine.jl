using Test
using STREAM
using STREAM.Assemblies
using STREAM.Components
using STREAM.Examples
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq, SteadyStateDiffEq
using OrdinaryDiffEq: ReturnCode

states(machine) = [entry.state for entry in machine.log]

@testset "StateMachine starts where it is told, with that start in its log" begin
    started = StateMachine(; initial_state=:STARTUP, initial_time=7.5)
    @test started.state === :STARTUP
    @test started.t_state == 7.5
    @test started.log == [(state=:STARTUP, t=7.5, cause="initial")]
    @test isempty(started.abort_states)
    @test StateMachine(; abort_states=(:SCRAM, :ABORT)).abort_states == Set([:SCRAM, :ABORT])
end

@testset "trip! latches the first trip and logs its cause" begin
    machine = StateMachine()
    @test trip!(machine, 2.0) === :SCRAM
    @test machine.state === :SCRAM
    @test machine.t_state == 2.0
    @test machine.log[end] == (state=:SCRAM, t=2.0, cause="manual")
    # A second signal changes nothing: the first trip's time and cause are the ones kept.
    trip!(machine, 5.0; cause="operator")
    @test machine.t_state == 2.0
    @test count(entry -> entry.state === :SCRAM, machine.log) == 1

    trip!(machine, 6.0; state=:SHUTDOWN, cause="operator")
    @test machine.log[end] == (state=:SHUTDOWN, t=6.0, cause="operator")
end

@testset "reset! returns a machine to its start and keeps its transitions" begin
    @variables x(t)
    machine = StateMachine((:NORMAL => :SCRAM, x > 1.0); initial_time=1.0)
    trip!(machine, 3.0)
    trip!(machine, 4.0; state=:ABORT)
    @test reset!(machine) === machine
    @test machine.state === :NORMAL
    @test machine.t_state == 1.0
    @test machine.log == [(state=:NORMAL, t=1.0, cause="initial")]
    @test length(machine.transitions) == 1
end

@testset "from accepts one state, a collection, or nothing" begin
    @variables x(t)
    from(f) = only(StateMachine((f => :SCRAM, x > 1.0)).transitions).from
    @test from(:NORMAL) == Set([:NORMAL])
    @test from((:NORMAL, :DERATED)) == Set([:NORMAL, :DERATED])
    @test from([:NORMAL, :DERATED]) == Set([:NORMAL, :DERATED])
    @test from(Set([:NORMAL])) == Set([:NORMAL])
    @test from(nothing) === nothing
end

@testset "a transition without a description is described by its condition" begin
    @variables x(t)
    edges = StateMachine(
        (:NORMAL => :SCRAM, x > 1.0),
        (:NORMAL => :SCRAM, x > 1.0, "too much x"),
        (:SCRAM => :ABORT, (m, sys, t) -> 1.0),
    ).transitions
    @test edges[1].description == string(x > 1.0)
    @test edges[2].description == "too much x"
    @test edges[3].description == "predicate"
end

@testset "a condition that cannot become an event is rejected when it is added" begin
    @variables x(t)
    @test_throws ArgumentError StateMachine((:NORMAL => :SCRAM, x))
    @test_throws ArgumentError StateMachine((:NORMAL => :SCRAM, x + 1.0))
    @test_throws ArgumentError StateMachine((:NORMAL => :SCRAM, 1.0))
    # A predicate takes (machine, sys, t). The two-argument form fails here, not mid-solve.
    @test_throws ArgumentError StateMachine((:NORMAL => :SCRAM, (m, t) -> true))
    @test_throws ArgumentError push!(StateMachine(), (:NORMAL => :SCRAM, (m, t) -> true))
end

@testset "one machine drives several output signals" begin
    # The machine is the logic, written once. Each output is a schedule reading it.
    machine = StateMachine()
    rods = ReactivityController((s, ts, t) -> s === :SCRAM ? -0.05 : 0.0; machine=machine)
    pump_head = StateSchedule((s, ts, t) -> s === :SCRAM ? exp(-(t - ts)) : 1.0;
                              machine=machine)
    @test (rods(1.0), pump_head(1.0)) == (0.0, 1.0)
    trip!(machine, 2.0)
    @test rods(3.0) == -0.05
    @test pump_head(3.0) ≈ exp(-1.0)
end

@testset "transitions can be set as one list of tuples" begin
    @variables x(t)
    machine = StateMachine((:NORMAL => :OFF, x > 0.0))
    machine.transitions = [
        (:NORMAL => :SCRAM, x > 1.0, "high x"),
        (:SCRAM => :ABORT, (m, sys, t) -> t - m.t_state - 2.0),
    ]
    @test length(machine.transitions) == 2      # the constructor's edge is replaced
    @test machine.transitions[1].description == "high x"
    @test machine.transitions[2].from == Set([:SCRAM])
    # Each tuple goes through the same checks as push!.
    @test_throws ArgumentError (machine.transitions = [(:NORMAL => :SCRAM, x + 1.0)])
end

@testset "a schedule reads the state the machine was in at the time asked" begin
    machine = StateMachine()
    rods = ReactivityController((s, ts, t) -> s === :SCRAM ? -0.05 * (t - ts) : 0.0;
                                machine=machine)
    trip!(machine, 1.5)
    trip!(machine, 4.0; state=:ABORT)
    @test rods(1.0) == 0.0                  # before the scram
    @test rods(3.0) == -0.05 * 1.5          # during it, timed from when it began
    @test rods(5.0) == 0.0                  # after it, in :ABORT

    # The decay heat clock reads the same log, so it runs during the scram even though the
    # machine has since left it.
    source = DecayHeat.DecayHeatSource(DecayHeat.U238CaptureChain(1.0), machine; P0=1.0)
    @test DecayHeat.decay_time(source, 1.0) == 0.0
    @test DecayHeat.decay_time(source, 3.0) ≈ 1.5
end

@testset "a quantity computed from a schedule reads the state at its own time" begin
    # reactivity is computed after the solve. Before the scram it has to show the rods out,
    # not the rods as the machine left them at the end of the run.
    machine = StateMachine()
    rods = ReactivityController((s, ts, t) -> s === :SCRAM ? -0.05 : 0.0; machine=machine)
    @named pk = PointKinetics(rods)
    ssys = mtkcompile(compose(System(Equation[], t; name=:reactor), pk))
    machine.transitions = [(:NORMAL => :SCRAM, t > 1.0, "at 1 s")]
    sol = solve_transient(ssys, Pair{Any,Any}[], range(0.0, 3.0; length=31);
                          callbacks=machine_callbacks(ssys, machine))
    @test sol.retcode == ReturnCode.Success
    @test sol(0.5; idxs=ssys.pk.reactivity) == 0.0
    @test sol(2.0; idxs=ssys.pk.reactivity) == -0.05
    @test sol(0.5; idxs=ssys.pk.P_neutron) ≈ 1.0
end

@testset "a schedule can return a vector for an array-valued callable parameter" begin
    machine = StateMachine()
    signals = StateSchedule(machine=machine) do state, t_state, t
        state === :SCRAM ? [-0.05, 0.0] : [0.0, 1.0]
    end
    FT = typeof(signals)
    @parameters (sig::FT)(..)[1:2] = signals
    @variables rho(t) y(t) = 1.0
    @named signal_reader = System([rho ~ sig(t)[1], D(y) ~ sig(t)[2] - y], t)
    ssys = mtkcompile(signal_reader)
    machine.transitions = [(:NORMAL => :SCRAM, t > 1.0, "at 1 s")]
    sol = solve_transient(ssys, Pair{Any,Any}[], range(0.0, 3.0; length=31);
                          callbacks=machine_callbacks(ssys, machine))
    @test sol.retcode == ReturnCode.Success
    # The second signal holds y at 1 until the scram, then lets it decay.
    @test sol(1.0; idxs=ssys.y) ≈ 1.0
    @test sol(3.0; idxs=ssys.y) ≈ exp(-2.0) rtol = 1e-4
    # The first is read after the solve, at the state of its own time.
    @test sol(0.5; idxs=ssys.rho) == 0.0
    @test sol(2.0; idxs=ssys.rho) == -0.05
end

@testset "transitions on a coasting loop" begin
    # A coasting loop: the pump head is removed and the flow falls through any setpoint
    # below where it starts, while the coolant runs hotter for want of flow. One solved
    # steady state feeds every case below.
    ssys = build_loop(; n=5)
    op = Pair{Any,Any}[ssys.ch.T[i] => 40.0 for i in 1:5]
    push!(op, ssys.ch.inlet.ṁ => 0.5)
    sol_ss = solve_steady(ssys, op)
    setpoint = 0.5 * sol_ss[ssys.ch.inlet.ṁ]
    T_setpoint = sol_ss[ssys.ch.T[5]] + 1.0
    times = range(0.0, 0.5; length=11)
    coast(machine) = solve_transient(
        ssys, sol_ss, times;
        overrides=[ssys.pump.dP_pump => 0.0],
        callbacks=machine_callbacks(ssys, machine),
    )
    low_flow = ssys.ch.inlet.ṁ < setpoint

    @testset "a falling inequality fires where it becomes true" begin
        machine = StateMachine((:NORMAL => :SCRAM, low_flow))
        sol = coast(machine)
        @test sol.retcode == ReturnCode.Success
        @test machine.state === :SCRAM

        # The trip time falls between the last saved flow above the setpoint and the first
        # below.
        ṁ = sol[ssys.ch.inlet.ṁ, :]
        before = sol.t .< machine.t_state
        @test all(ṁ[before] .> setpoint)
        @test all(ṁ[.!before] .<= setpoint * (1 + 1e-6))

        # A decay heat source reading the same machine starts its clock at the trip.
        source = DecayHeat.DecayHeatSource(DecayHeat.U238CaptureChain(1.0), machine; P0=1.0)
        @test DecayHeat.decay_time(source, machine.t_state + 3.0) ≈ 3.0
    end

    @testset "a rising inequality fires on its own edge" begin
        # Less flow over the same wall means a hotter outlet, so this one rises into its
        # setpoint while the flow falls away from its own.
        machine = StateMachine((:NORMAL => :SCRAM, ssys.ch.T[5] > T_setpoint))
        sol = coast(machine)
        @test sol.retcode == ReturnCode.Success
        @test machine.state === :SCRAM
        T = sol[ssys.ch.T[5], :]
        before = sol.t .< machine.t_state
        @test all(T[before] .< T_setpoint)
        @test all(T[.!before] .>= T_setpoint * (1 - 1e-6))
    end

    @testset "an equation fires at the same crossing as the inequality" begin
        # The flow crosses this setpoint once and downwards, so the equation form has to
        # land where the inequality does.
        falling = StateMachine((:NORMAL => :SCRAM, low_flow))
        either = StateMachine((:NORMAL => :SCRAM, ssys.ch.inlet.ṁ ~ setpoint))
        foreach(coast, (falling, either))
        @test either.state === :SCRAM
        @test either.t_state ≈ falling.t_state rtol = 1e-9
    end

    @testset "a transition fires only from the states in its from" begin
        edge = (:NORMAL, :DERATED) => :SCRAM
        from_normal = StateMachine((edge, low_flow))
        from_derated = StateMachine((edge, low_flow); initial_state=:DERATED)
        from_other = StateMachine((edge, low_flow); initial_state=:OFF)
        foreach(coast, (from_normal, from_derated, from_other))
        @test from_normal.state === :SCRAM
        @test from_derated.state === :SCRAM
        @test from_other.state === :OFF     # the edge does not leave :OFF
    end

    @testset "the log records the description of the transition taken" begin
        described = StateMachine((:NORMAL => :SCRAM, low_flow, "low flow"))
        undescribed = StateMachine((:NORMAL => :SCRAM, low_flow))
        foreach(coast, (described, undescribed))
        @test described.log[end].cause == "low flow"
        @test undescribed.log[end].cause == string(low_flow)
    end

    @testset "a predicate fires the instant its dwell time has passed" begin
        dwell = 0.05
        machine = StateMachine(
            (:NORMAL => :SCRAM, low_flow),
            (:SCRAM => :HOLD, (m, sys, t) -> t - m.t_state - dwell, "dwell"),
        )
        sol = coast(machine)
        @test sol.t[end] == last(times)     # :HOLD is not an abort state
        @test states(machine) == [:NORMAL, :SCRAM, :HOLD]
        @test machine.log[3].t - machine.log[2].t ≈ dwell rtol = 1e-6
        @test machine.log[3].cause == "dwell"
    end

    @testset "a predicate reading the model fires where the inequality does" begin
        # The same trip written both ways. The predicate reads the flow through sys, at the
        # states the solver estimates inside a step while it looks for the crossing.
        inequality = StateMachine((:NORMAL => :SCRAM, low_flow))
        predicate = StateMachine(
            (:NORMAL => :SCRAM, (m, sys, t) -> setpoint - sys[ssys.ch.inlet.ṁ])
        )
        foreach(coast, (inequality, predicate))
        @test predicate.state === :SCRAM
        @test predicate.t_state ≈ inequality.t_state rtol = 1e-6
    end

    @testset "a condition already true when its transition can be taken fires at once" begin
        # The outlet is past this limit from the start, while the machine is still :NORMAL
        # and the abort edge cannot be taken. Entering :SCRAM makes it takeable, and since it
        # will never cross again it has to fire then or not at all.
        hot = sol_ss[ssys.ch.T[5]] - 1.0
        machine = StateMachine(
            (:NORMAL => :SCRAM, low_flow),
            (:SCRAM => :ABORT, ssys.ch.T[5] > hot, "hot");
            abort_states=(:ABORT,),
        )
        coast(machine)
        @test states(machine) == [:NORMAL, :SCRAM, :ABORT]
        @test machine.log[3].t == machine.log[2].t
        @test machine.log[3].cause == "hot"
    end

    @testset "a condition already true at the start fires at the start" begin
        machine = StateMachine((:NORMAL => :SCRAM, ssys.ch.inlet.ṁ > setpoint))
        coast(machine)
        @test states(machine) == [:NORMAL, :SCRAM]
        @test machine.t_state == first(times)
    end

    @testset "an edge from any state is not taken into the state it leads to" begin
        machine = StateMachine((nothing => :SCRAM, low_flow))
        coast(machine)
        @test states(machine) == [:NORMAL, :SCRAM]
    end

    @testset "a predicate that returns true or false stops the solve" begin
        machine = StateMachine((:NORMAL => :SCRAM, (m, sys, t) -> t > 0.1))
        @test_throws ArgumentError coast(machine)
    end

    @testset "a cycle whose conditions all hold stops the solve" begin
        machine = StateMachine(
            (:NORMAL => :SCRAM, ssys.ch.inlet.ṁ > 0.0),
            (:SCRAM => :NORMAL, ssys.ch.inlet.ṁ > 0.0),
        )
        @test_throws ErrorException coast(machine)
    end

    @testset "entering an abort state stops the integration" begin
        machine = StateMachine((:NORMAL => :ABORT, low_flow); abort_states=(:ABORT,))
        sol = coast(machine)
        @test machine.state === :ABORT
        @test sol.t[end] ≈ machine.t_state
        @test sol.t[end] < last(times)
    end

    @testset "reset! lets the same machine run again" begin
        machine = StateMachine((:NORMAL => :SCRAM, low_flow))
        coast(machine)
        t_first = machine.t_state
        coast(reset!(machine))
        @test states(machine) == [:NORMAL, :SCRAM]
        @test machine.t_state == t_first
    end

    @testset "push! adds an edge after the machine is built" begin
        machine = StateMachine()
        @test isempty(machine.transitions)
        push!(machine, (:NORMAL => :SCRAM, low_flow))
        coast(machine)
        @test machine.state === :SCRAM
    end
end

@testset "a variable on an uncompiled component is the one the compiled system carries" begin
    # This is what lets a machine take its edges beside the components, before mtkcompile.
    @named lone = PointKinetics(ReactivityController())
    compiled = mtkcompile(compose(System(Equation[], t; name=:parent), lone))
    @test isequal(lone.P_neutron, compiled.lone.P_neutron)
end

# Trip a reactor or open a valve

Control actions in STREAM go through a [`StateMachine`](@ref STREAM.Components.StateMachine):
components follow its state, and its transitions fire when conditions on the model are met.
How the solver finds them is in [Events and control](../explanation/events.md). This page is
the recipes, on a small reactor whose control rods withdraw slowly until it trips.

```@example ev
using STREAM
using STREAM.Components: PointKinetics, ReactivityController, StateMachine, machine_callbacks
using ModelingToolkit: @named, mtkcompile, @parameters
nothing # hide
```

## Trip on a signal

Build the machine, give it to the component that acts on it, then add the transition. A
[`ReactivityController`](@ref STREAM.Components.ReactivityController) gives the kinetics a
reactivity that depends on the machine's state: here a slow withdrawal, and rods falling in
over half a second after a scram.

```@example ev
machine = StateMachine()
withdrawal(t) = 2.0e-4 * t                                  # reactivity rising 20 pcm/s
scram(τ) = -0.05 * clamp(τ / 0.5, 0.0, 1.0)
rods = ReactivityController(machine=machine) do state, t_state, t
    state === :SCRAM ? withdrawal(t) + scram(t - t_state) : withdrawal(t)
end
@named pk = PointKinetics(rods)
machine.transitions = [(:NORMAL => :SCRAM, pk.P_neutron > 1.2, "power above 120%")]

@named reactor = assembly([], pk)
sys = mtkcompile(reactor)
sol = solve_transient(sys, 0.0:0.05:20.0; callbacks=machine_callbacks(sys, machine))
machine.log
```

The condition reads `pk.P_neutron` from the component as built, before compiling: the
transition can be written as soon as the components it mentions exist. The kinetics live
inside an assembly here, so that their variables carry the `pk` prefix the condition uses.

## Read what happened

The machine's `log` records each state it entered, when, and why. After the run, `state` and
`t_state` are where it ended:

```@example ev
(machine.state, machine.t_state)
```

## Stop the run at an end state

A state listed in `abort_states` stops the integration when entered. A *predicate*, a
function `(machine, sys, t) -> Real` that is positive where its condition holds, can say what
an inequality on the model cannot, such as time spent in a state:

```@example ev
machine = StateMachine(; abort_states=(:DONE,))
rods = ReactivityController(machine=machine) do state, t_state, t
    state === :NORMAL ? withdrawal(t) : withdrawal(t) + scram(t - t_state)
end
@named pk = PointKinetics(rods)
machine.transitions = [
    (:NORMAL => :SCRAM, pk.P_neutron > 1.2, "power above 120%"),
    (:SCRAM => :DONE, (m, sys, t) -> t - m.t_state - 5.0, "5 s after the scram"),
]
@named reactor = assembly([], pk)
sys = mtkcompile(reactor)
sol = solve_transient(sys, 0.0:0.05:60.0; callbacks=machine_callbacks(sys, machine))
(sol.t[end], machine.log[end].cause)
```

A predicate is called at trial points inside the solver's steps as well as at the points it
keeps, so it must not change anything. Inside it, `sys[var]` reads any variable of the model.

## Change a setpoint without recompiling

A number in a condition is compiled into the event. Write the setpoint as a parameter of the
model to change it between runs, and reset the machine, which remembers the last run:

```@example ev
@parameters trip_at = 1.2
machine = StateMachine()
rods = ReactivityController(machine=machine) do state, t_state, t
    state === :SCRAM ? withdrawal(t) + scram(t - t_state) : withdrawal(t)
end
@named pk = PointKinetics(rods)
machine.transitions = [(:NORMAL => :SCRAM, pk.P_neutron > trip_at, "high power")]
@named reactor = assembly([], pk; parameters=[trip_at])
sys = mtkcompile(reactor)

trip_times = map((1.2, 1.5, 2.0)) do setpoint
    Components.reset!(machine)
    solve_transient(sys, [trip_at => setpoint], 0.0:0.05:30.0;
                    callbacks=machine_callbacks(sys, machine))
    round(machine.t_state; digits=2)
end
```

A higher setpoint trips later, as the slow withdrawal takes longer to push the power there.
`assembly` needs `parameters=[trip_at]` because no equation of the model mentions it, only the
event.

## Several machines

Equipment that decides on its own gets a machine of its own: a check valve that opens on low
flow, independently of the reactor protection. Pass all of them to `machine_callbacks`:

```julia
valve = StateMachine(; initial_state=:CLOSED)
@named flapper = Flapper(; machine=valve)
valve.transitions = [(:CLOSED => :OPEN, flywheel.inlet.ṁ < 1.5, "low primary flow")]
callbacks = machine_callbacks(sys, ctrl.machine, valve)
```

The [pool loss-of-flow tutorial](../tutorials/07_pool_lofa.md) runs exactly this.

## A trip at a known time

A machine built in the tripped state, `StateMachine(; initial_state=:SCRAM, initial_time=5.0)`,
is a scram at ``t = 5`` s with no transition at all. A valve built `:OPEN` at `t0` opens from
`t0`.

# Get a steady solve to converge

[`solve_steady`](@ref) finds where every time derivative of a model is zero, starting from a
guess. Most failures come from the guess.

```@example ss
using STREAM
using STREAM.Components: Pump, HeatExchanger, Channel
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile, unknowns
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS

@named pump = Pump(3.0e4)
@named hx = HeatExchanger(40.0)
@named ch = Channel(; n=10, geometry=PipeGeometry_circular(0.6, 0.01), h_left=5000.0)
connections = [inseries(pump, hx, ch, pump), pump.inlet.p ~ 1.0e5, ch.T_wall_left .~ 100.0]
@named loop = assembly(connections, pump, hx, ch)
sys = mtkcompile(loop)
nothing # hide
```

## Guess the variables the solver keeps

`mtkcompile` removes most variables, keeping only those the rest can be computed from. A guess
only acts on a kept one. List them:

```@example ss
foreach(println, unknowns(sys))
```

Here the flow is kept as `ch.inlet.ṁ`. The same flow is also `pump.inlet.ṁ` and
`hx.outlet.ṁ`, but those names were eliminated, and a guess for them would do nothing. Which
copy of a variable survives can change when the model changes, so after an edit, look again.

## Give every loop a flow

A closed loop has a solution with no flow at all. Started from zero flow, the solver can land
there, or stall next to it. Guess a flow of the right size and sign for each loop:

```@example ss
sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5])
(sol.retcode, sol[sys.ch.inlet.ṁ])
```

A pump in fixed-flow mode, `Pump(; ṁ0)`, removes the question, since the flow is then given.

## Guess the temperatures

The temperatures start at 26.85 °C unless told otherwise. For a channel that heats the coolant
a lot, a linear guess from inlet to outlet helps. [`steady_state_guess`](@ref) makes one from
a heat input and a flow, and [`uniform`](@ref) gives one value to a variable in many
components at once:

```@example ss
T_guess = steady_state_guess(; T_inlet=40.0, Q_wall=1.0e4, ṁ_guess=0.5, n=10)
op = [sys.ch.inlet.ṁ => 0.5, sys.ch.T => T_guess]
solve_steady(sys, op).retcode
```

```julia
uniform([sys.riser, sys.core.ch], 35.0, :T)   # every cell of both channels at 35 °C
```

## When the solver still fails: integrate to steady state

The default solver is a Newton-type method, fast when the guess is close and lost when it is
not. `DynamicSS` integrates the model in time from the guess until it stops changing, which
finds the operating point a real plant would settle into:

```@example ss
sol = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5]; solver=DynamicSS(Rodas5P()))
(sol.retcode, sol[sys.ch.inlet.ṁ])
```

It is slower, but it is the robust choice for a loop with parallel branches, natural
circulation, or a check valve: the [pool loss-of-flow tutorial](../tutorials/07_pool_lofa.md)
uses it. Give it a guess with the flows in each branch, as above.

## Do not constrain the sign of the flow

When a loop lands on zero or reversed flow, it is tempting to forbid negative flow. Do not.
Flows legitimately reverse: after a pump trip, natural circulation runs the other way through
the core. A model that forbids it forbids the physics. Fix the guess, or integrate to steady
state, instead.

## A transient that starts from a steady state

Solve the steady state first, then hand the solution to
[`solve_transient`](@ref), changing what starts the transient through `overrides`:

```@example ss
sol_ss = solve_steady(sys, [sys.ch.inlet.ṁ => 0.5])
sol_tr = solve_transient(sys, sol_ss, 0.0:0.5:10.0; overrides=[sys.pump.dP_pump => 1.5e4])
sol_tr[sys.ch.inlet.ṁ, end]
```

The whole state is carried over by name, so the start does not depend on which variables
`mtkcompile` kept.

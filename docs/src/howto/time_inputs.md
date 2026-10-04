# Drive an input from a function of time

A transient is usually driven by something that changes in time: a pump head that coasts
down, a reactivity that rises, a wall that heats up. There are two ways to give a model such
an input.

## An expression in time

An equation in the connection list can use the time variable directly. This suits a boundary
value with a formula:

```julia
using ModelingToolkit: t_nounits as t
connections = [..., ch.T_wall_left .~ 60.0 + 40.0 * (1 - exp(-t / 10))]
```

[Bind a wall temperature or heat flux](wall_boundary.md) runs this case.

## A function given to a component

Several components take a Julia function of time in place of a number. The function becomes
a parameter of the model, a *callable parameter*:

| Component | Argument | Parameter | Needs it in the operating point |
|:---|:---|:---|:---|
| [`Pump`](@ref STREAM.Components.Pump) | the head, `Pump(f)` | `dP_pump_fn` | yes |
| [`Channel`](@ref STREAM.Components.Channel) | `h_left`, `h_right` | `h_left_fn`, `h_right_fn` | yes |
| [`VolumetricFlowResistor`](@ref STREAM.Components.VolumetricFlowResistor) | `k` | `k_fn` | yes |
| [`PointKinetics`](@ref STREAM.Components.PointKinetics) | the control reactivity | `rho_c_fn` | no, it stores its default |
| [`PointKinetics`](@ref STREAM.Components.PointKinetics) | `power_input` | `power_input_fn` | no, it stores its default |

Where the table says yes, pass the function again in the operating point of the solve, under
the parameter's name:

```@example ti
using STREAM
using STREAM.Components: Pump, Inertia, ResistorFromKnownPoint, HeatExchanger
using STREAM.Assemblies: inseries
using ModelingToolkit: @named, mtkcompile

head(t) = 3.0e4 * exp(-t / 5)               # coasting down with a 5 s time constant
@named pump = Pump(head)
@named flywheel = Inertia(2.0e4)
@named loss = ResistorFromKnownPoint(; dp=-3.0e4, ṁ=50.0, T=40.0)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, flywheel, loss, hx, pump), pump.inlet.p ~ 1.5e5],
                       pump, flywheel, loss, hx)
sys = mtkcompile(loop)
sol = solve_transient(sys, [sys.loss.inlet.ṁ => 50.0, sys.pump.dP_pump_fn => head],
                      0.0:1.0:30.0)
sol[sys.loss.inlet.ṁ, end]
```

The [pump coastdown tutorial](../tutorials/03_pump_coastdown.md) follows this loop in detail.

## Changing the function between runs

The function's *type* is fixed when the component is built: a different function of another
type cannot replace it without rebuilding. Two functions of the same type can. A closure over
a value has one type whatever the value, so make the varying quantity a captured value:

```@example ti
coastdown(τ) = t -> 3.0e4 * exp(-t / τ)       # every τ gives a function of the same type
@named pump = Pump(coastdown(5.0))
@named flywheel = Inertia(2.0e4)
@named loss = ResistorFromKnownPoint(; dp=-3.0e4, ṁ=50.0, T=40.0)
@named hx = HeatExchanger(40.0)
@named loop = assembly([inseries(pump, flywheel, loss, hx, pump), pump.inlet.p ~ 1.5e5],
                       pump, flywheel, loss, hx)
sys = mtkcompile(loop)
map((2.0, 5.0, 20.0)) do τ
    sol = solve_transient(sys, [sys.loss.inlet.ṁ => 50.0, sys.pump.dP_pump_fn => coastdown(τ)],
                          0.0:1.0:30.0)
    sol[sys.loss.inlet.ṁ, end]
end
```

A slower coastdown keeps more flow at 30 s.

## A function of the control system's state

For an input that depends on a trip, such as rods that fall after a scram, use a
[`ReactivityController`](@ref STREAM.Components.ReactivityController) or a
[`StateSchedule`](@ref STREAM.Components.StateSchedule): a function of the state of a
[`StateMachine`](@ref STREAM.Components.StateMachine), the time it entered it, and the time.
See [Trip a reactor or open a valve](events.md).

## Data instead of a formula

For a measured curve, interpolate it into a function and pass that. Any callable works, an
interpolation object from DataInterpolations.jl included.

When an input jumps, as a step does, tell the solver where with `tstops`, so it steps onto the
jump rather than across it:

```julia
solve_transient(sys, op, times; tstops=[t_step])
```

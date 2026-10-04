# Add decay heat to a transient

Decay heat reaches a model through the kinetics: a
[`DecayHeatSource`](@ref STREAM.DecayHeat.DecayHeatSource) turns a decay heat contribution into
a power, and [`PointKinetics`](@ref STREAM.Components.PointKinetics) adds it to the fission
power. The fuel, heated by the kinetics' total power `P`, then sees both. The physics is in
[Decay heat](../explanation/decay_heat.md).

## Point STREAM at the standards

The fission product tables are published standards that STREAM does not distribute. Tell it
where they are, once per session:

```julia
DecayHeat.standards_dir!("/path/to/standards")
```

or set the environment variable `STREAM_DECAY_HEAT_STANDARDS` before starting Julia. Then
read a standard and source:

```julia
fp = DecayHeat.FissionProducts(DecayHeat.ANS14, DecayHeat.U235)          # ANSI/ANS-5.1-2014
fp_gamma = DecayHeat.FissionProducts(DecayHeat.JAERI91, DecayHeat.U235_gamma)  # gamma only
```

The standards are `ANS73`, `ANS14` and `JAERI91`, and the sources `U235`, `U238`, and, for
JAERI, their `_beta` and `_gamma` parts. [`DecayHeat.read_standard`](@ref) returns the raw
decay constants and strengths.

## Build the contribution

Contributions add and scale, so a component's total is written as a sum. For fuel, the fission
products and the U-238 capture chain:

```julia
heat = fp + DecayHeat.U238CaptureChain(0.5)   # 0.5 captures in U-238 per fission
```

The rest of this page uses a made-up fission product fit, so that it runs without the tables:

```@example dh
using STREAM
using STREAM.Components: PointKinetics, ReactivityController, StateMachine
using ModelingToolkit: @named

fp = DecayHeat.FissionProducts([1.0, 0.05, 1e-3, 1e-5], [3.0, 0.15, 3e-3, 3e-5])
heat = fp + DecayHeat.U238CaptureChain(0.5)
heat(0.0) / 200          # share of the operating power at shutdown, for 200 MeV per fission
```

Do not add `DecayHeat.Fissions` to a model whose power comes from `PointKinetics`: after a
scram the kinetics already compute the fission power, delayed neutrons included.

## Turn it into a power, with a trip clock

`DecayHeatSource` needs the operating power `P0`, in the units the kinetics use, and the
machine that decides when the reactor shuts down. Until the machine enters `:SCRAM`, the source
holds its value at shutdown, the decay heat of a reactor at power. After, it decays.

```@example dh
machine = StateMachine(; initial_state=:SCRAM, initial_time=10.0)   # a scram at t = 10 s
source = DecayHeat.DecayHeatSource(heat, machine; P0=1.0)
[source(t) for t in (0.0, 10.0, 70.0, 610.0)]
```

The source is flat until the scram and decays after. Here the machine is built already
tripped, which is a scram at a known time. In a model where the trip comes from a transition,
pass the machine the protection system uses, or the
[`ReactivityController`](@ref STREAM.Components.ReactivityController) holding it.

## Give it to the kinetics

```@example dh
ctrl = ReactivityController((state, t_state, t) -> state === :SCRAM ? -0.06 : 0.0;
                            machine=StateMachine())
source = DecayHeat.DecayHeatSource(heat, ctrl; P0=1.0)
@named pk = PointKinetics(ctrl; power_input=source)
nothing # hide
```

The kinetics start at total power 1, with fission making up `1 - source(0)` of it. Heat the
fuel with `pk.P`, the total:

```julia
connections = [..., fuel.power ~ pk.P * P_rated]
```

**Units.** `P0` sets the units of the source, which must be those of the kinetics. A model
whose kinetics run in units of the rated power, as above, takes `P0 = 1`. One running in watts
takes the rated power in watts.

## Finite irradiation

The source assumes the reactor ran long enough to saturate every group, `T = Inf`. After a
short run less has built up. Pass the operating time in seconds:

```@example dh
short = DecayHeat.DecayHeatSource(heat, machine; P0=1.0, T=3600.0)
(saturated=DecayHeat.DecayHeatSource(heat, machine; P0=1.0)(610.0), one_hour=short(610.0))
```

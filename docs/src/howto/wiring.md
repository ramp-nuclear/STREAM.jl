# Wire components together

A model is its components plus a list of connections, joined by
[`assembly`](@ref STREAM.Assemblies.assembly). The connection list can nest: it holds single
equations next to the vectors the wiring functions return, and needs no splatting.

```@example wiring
using STREAM
using STREAM.Components: Pump, Resistor, HeatExchanger
using STREAM.Assemblies: inseries, inparallel, weighted
using ModelingToolkit: @named, mtkcompile, connect
nothing # hide
```

## In series

[`inseries`](@ref STREAM.Assemblies.Connect.inseries) joins each component's outlet to the next
one's inlet. Naming the first component again at the end closes a loop:

```julia
inseries(pump, hx, pipe, pump)
```

## In parallel

[`inparallel`](@ref STREAM.Assemblies.Connect.inparallel) splits the flow leaving one component
into several branches and joins them into another. A branch is one component, or a tuple of
components in series:

```@example wiring
@named pump = Pump(1.0e4)
@named hx = HeatExchanger(40.0)
@named a = Resistor(1.0e3)
@named b1 = Resistor(1.0e3)
@named b2 = Resistor(1.0e3)
connections = [
    inseries(pump, hx),
    inparallel(hx, [a, (b1, b2)], pump),     # branch b is b1 then b2
    pump.inlet.p ~ 1.0e5,
]
@named loop = assembly(connections, pump, hx, a, b1, b2)
sys = mtkcompile(loop)
sol = solve_steady(sys)
(a=sol[sys.a.inlet.ṁ], b=sol[sys.b1.inlet.ṁ])
```

Branch `b` has twice the resistance, so it takes half the flow of branch `a`.

## Any junction

`connect`, from ModelingToolkit, joins any number of ports into one junction: the pressure is
the same at all of them and the flows sum to zero. Use it for a network that is not a chain
of series and parallel blocks, as in the cube of [Hydraulic networks](../tutorials/02_hydraulic_networks.md):

```julia
connect(pump.outlet, r01.inlet, r02.inlet, r04.inlet)
```

## Many identical branches

A core of fifty identical assemblies is fifty copies of the same equations.
[`weighted`](@ref STREAM.Assemblies.Connect.weighted) makes one branch stand for `N`: the
junctions at its ends see `N` times its flow, and the solve carries one branch's unknowns.

```@example wiring
@named pump = Pump(1.0e4)
@named hx = HeatExchanger(40.0)
@named single = Resistor(1.0e3)
@named extra = Resistor(1.0e3)
many = weighted(50, single; name=:many)     # single standing for 50 in parallel
connections = [inseries(pump, hx), inparallel(hx, [many, extra], pump), pump.inlet.p ~ 1.0e5]
@named loop = assembly(connections, pump, hx, many..., extra)
sys = mtkcompile(loop)
sol = solve_steady(sys)
(total=sol[sys.pump.inlet.ṁ], each_of_many=sol[sys.single.inlet.ṁ], extra=sol[sys.extra.inlet.ṁ])
```

The fifty and the extra branch share the head, so each carries the same flow, and the pump
carries 51 times that. `weighted` returns a tuple, which goes into the branch list as a path and is
splatted into `assembly` as components.

## Plates and channels

Thermal connections between a channel and a plate are one per axial cell.
[`faces`](@ref STREAM.Assemblies.Connect.faces) joins two faces cell by cell:

```julia
faces((ch, :thermal_right) => (fuel, :thermal_left))
```

[`face`](@ref STREAM.Assemblies.Connect.face) joins a vector of single-port components, such
as [`ConstantTemperature`](@ref STREAM.Components.ConstantTemperature) boundaries, to a face,
and [`port`](@ref STREAM.Assemblies.port) reaches one cell's port, or one variable of all of
them:

```julia
port(ch, :thermal_left, 3)        # the third cell's port, for connect
port(ch, :thermal_left, :T)       # the wall temperature of every cell
```

For the usual arrangements of plates and channels, use the ready-made ones in
[Build a fuel assembly](fuel_assembly.md).

## Fixing the pressure

A closed loop determines pressure differences only. Every model with a closed loop needs one
absolute pressure fixed, as an equation such as `pump.inlet.p ~ 1.0e5`. Without it, the
compiled system is singular. A loop open to a pool already has one: fix the pressure at the
pool.

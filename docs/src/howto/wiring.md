# Wire components together

A model is its components and the connections between them. [`@assembly`](@ref) takes both
in one block: a line such as `pump = Pump(1.0e4)` builds a component named `pump`, and any
other line is a connection: an equation, a flow path drawn with arrows, or one of the vectors
the wiring functions return. It composes the components the connections use and compiles the model.
[`assembly`](@ref STREAM.Assemblies.assembly) is the uncompiled form underneath, taking a
connection list and the components to compose.

```@example wiring
using STREAM
using STREAM.Components: Pump, Resistor, HeatExchanger
using STREAM.Assemblies: weighted
using ModelingToolkit: connect
nothing # hide
```

## In series

`-->` joins each component's outlet to the next one's inlet. Naming the first component again
at the end closes a loop:

```julia
pump --> hx --> pipe --> pump
```

## In parallel

`||` splits the flow leaving the step before it into branches, and joins them into the step
after it. It binds tighter than `-->`, so a branch of several components in series goes in
parentheses:

```@example wiring
@assembly sys begin
    pump = Pump(1.0e4)
    hx = HeatExchanger(40.0)
    a = Resistor(1.0e3)
    b1 = Resistor(1.0e3)
    b2 = Resistor(1.0e3)
    pump --> hx --> a || (b1 --> b2) --> pump  # branch b is b1 then b2
    pump.inlet.p ~ 1.0e5
end
sol = solve_steady(sys)
@assert sol[sys.a.inlet.ṁ] ≈ 2 * sol[sys.b1.inlet.ṁ]
(a=sol[sys.a.inlet.ṁ], b=sol[sys.b1.inlet.ṁ])
```

Branch `b` has twice the resistance, so it takes half the flow of branch `a`.

## Paths outside a block

Inside `@assembly` an arrow line is a connection as it stands. Elsewhere, such as in a
builder function, [`@flowgraph`](@ref STREAM.Assemblies.Connect.@flowgraph) gives its
equations. A path built elsewhere, a tuple or vector of components in series such as the one
[`weighted`](@ref STREAM.Assemblies.Connect.weighted) returns, stands in a path or a branch
as it is, and `branches... || c` adds every branch a vector holds:

```julia
hot = (hx_hot, riser)
@flowgraph pump --> hot || bypass || (hx_cold --> downcomer) --> pump
@flowgraph begin                       # several paths, one per line
    pool.bottom --> breach --> room.port
    pool.side --> pump --> pool.top
end
```

The arrows give the equations of [`inseries`](@ref STREAM.Assemblies.Connect.inseries) and
[`inparallel`](@ref STREAM.Assemblies.Connect.inparallel), which take the components as
arguments: the parallel loop above is `inseries(pump, hx)` and
`inparallel(hx, [a, (b1, b2)], pump)`. A parallel block whose branches are all in one vector
is written with `inparallel(hx, channels, pump)`, since `||` needs two sides.

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
@assembly sys begin
    pump = Pump(1.0e4)
    hx = HeatExchanger(40.0)
    single = Resistor(1.0e3)
    extra = Resistor(1.0e3)
    many = weighted(50, single)  # single standing for 50 in parallel
    pump --> hx --> many || extra --> pump
    pump.inlet.p ~ 1.0e5
end
sol = solve_steady(sys)
(total=sol[sys.pump.inlet.ṁ], each_of_many=sol[sys.single.inlet.ṁ], extra=sol[sys.extra.inlet.ṁ])
```

The fifty and the extra branch share the head, so each carries the same flow, and the pump
carries 51 times that. `weighted` returns a tuple of the systems along the branch, which
stands in the parallel block as one branch and which `@assembly` composes.

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

## Components built elsewhere

A component built before the block joins the model when a connection uses it, so a builder
function can take components as arguments. A connection that reaches into a composed system,
as `pump --> bc --> rods.cac --> pump` reaches the channel of a plate built by
[`symmetric_plate`](@ref STREAM.Assemblies.symmetric_plate), brings in the plate, and the
channel is not composed a second time. A system no connection names, such as a vector of
plates reached only through views into them, goes on a line of its own:

```julia
@assembly sys begin
    plates  # composed whole
    [inseries(pumps[i], plates_cac[i], pumps[i]) for i in eachindex(pumps)]
end
```

A line that gives neither equations nor systems, such as `push!(machine, edge)`, is an error:
put it before or after the block. Keywords after `end` go to `assembly` (`parameters`, `t`) or
to `mtkcompile` (any other, such as `fully_determined=false`).

## Fixing the pressure

A closed loop determines pressure differences only. Every model with a closed loop needs one
absolute pressure fixed, as an equation such as `pump.inlet.p ~ 1.0e5`. Without it, the
compiled system is singular. A loop open to a pool already has one: fix the pressure at the
pool.

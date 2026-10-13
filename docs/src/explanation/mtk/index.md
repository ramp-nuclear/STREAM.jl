# ModelingToolkit in brief

STREAM.jl models are [ModelingToolkit](https://docs.sciml.ai/ModelingToolkit/stable/) (MTK)
systems. Reading or extending one means knowing a handful of MTK's words. This page defines
them, and the three pages after it use them on small systems from outside reactor physics,
the same ones Python STREAM's documentation uses to show how a calculation is written:

- [A series RLC circuit](rlc.md): components, connectors, and what `mtkcompile` keeps;
- [Masses on springs](springs.md): parameters, observed variables, and changing a parameter
  without recompiling;
- [A planar pendulum](pendulum.md): a constraint, index reduction, and initialization.

[How a model is built](../modelling.md) explains the same machinery from STREAM's side.

## The words

**System.** A set of equations with the variables and parameters they use, and possibly
subsystems. Every component in STREAM is a function that returns one, such as
`Resistor(R; name)`. The `@named` macro supplies the name: `@named r = Resistor(1.0)` is
`r = Resistor(1.0; name=:r)`.

**Variable.** A quantity that changes in time, declared as `@variables x(t)`. The solver
finds its value.

**Parameter.** A quantity fixed for the length of a solve, declared as `@parameters R`. A
parameter can change between solves without recompiling, which is what
[`@design_knob`](@ref) builds on. A parameter can also hold a function of time, which is how
STREAM drives a pump head or a reactivity from outside.

**Equation.** Written with `~`, as in `v ~ i * R`. Neither side is an assignment: the equation
states a relation, and MTK decides what to solve it for. `D(x)` is the time derivative of `x`.

**Connector.** A system with variables and no equations, placed on a component's boundary:
STREAM's [`FlowPort`](@ref STREAM.Components.FlowPort) and
[`ThermalPort`](@ref STREAM.Components.ThermalPort), or an electrical pin.
`connect(a.port, b.port)` generates the equations that join them. A plain variable is made
equal at every connected port, a variable marked `Flow` is summed to zero, and a variable
marked `Stream` is carried with the flow.

**Namespace.** A subsystem's variables are reached through it, as `loop.ch.T_out`. MTK prints
the dot as `₊`, so `loop.ch.T_out` reads `ch₊T_out(t)` in a list of unknowns.

**`mtkcompile`.** Turns a composed system into one a solver can run. It expands the
connections, removes every equation that merely makes two variables equal, solves what it can
in closed form, and reduces the index of the system where a constraint ties differential
variables together. What remains is a much smaller system.

**Unknowns.** `unknowns(sys)` lists the variables the compiled system integrates or solves
for. After `mtkcompile` this is usually a small subset of the variables you wrote, and which
member of a set of equal variables represents the set is MTK's choice.

**Observed.** `observed(sys)` lists the equations of the variables `mtkcompile` removed from
the unknowns. Each is computed from the unknowns when you ask for it, so a solution still
answers for every variable in the model.

**Operating point.** One map of initial values and parameter values, such as
`[sys.c.v => -1.0, sys.r.R => 2.0]`, handed to a problem. Values left out are taken from the
defaults given in the declarations. A value may be given for any variable, unknown or
observed, and MTK's initialization works out the unknowns from it.

**Guess.** A starting point for a variable whose value initialization must solve for, such
as a Lagrange multiplier. A guess is not imposed, only iterated from.

**Problem and solution.** `ODEProblem(sys, op, tspan)` pairs the compiled system with an
operating point, `solve` integrates it, and the solution is indexed by variable:
`sol[sys.r.v]` for the whole history, `sol(2.5; idxs=sys.r.v)` interpolated at one time.
STREAM wraps these in [`solve_steady`](@ref) and [`solve_transient`](@ref).

## In Python STREAM's terms

| Python STREAM | ModelingToolkit and STREAM.jl |
|:--|:--|
| `Calculation` subclass | a function returning a `System` |
| `variables` of a calculation | the variables of a component; `unknowns` after compiling |
| `mass_vector` | which equations hold a `D(...)`; MTK reads it off the equations |
| keyword inputs of `calculate`, edges of the graph | connectors and `connect`, or one equation naming both sides |
| external functions, `funcs` | parameters, and parameters holding a function of time |
| `Aggregator` | the composed system: [`assembly`](@ref STREAM.Assemblies.assembly), then `mtkcompile` |
| `report(agr)` | `unknowns`, `equations` and `observed`; `mtkcompile` fails on a system with too few or too many equations |
| `y0` and `yp0` | the operating point; consistent derivatives are found by initialization |
| `jac=ALG_jacobian(agr)` | generated from the equations, with its sparsity |
| `agr.save(sol)`, `at_times` | `sol[sys.x]`, `sol(t; idxs=sys.x)` |

## Showing equations

Every system on these pages prints its own equations. [Latexify](https://github.com/korsbo/Latexify.jl)
turns a list of them into TeX, and a list of variables into a column:

```julia
using Latexify
latexify(equations(sys); env=:aligned)
latexify(unknowns(sys); env=:inline)
```

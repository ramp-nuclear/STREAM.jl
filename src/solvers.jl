"""
    solve_steady(ssys, op; solver=nothing, kwargs...) -> SciMLSolution

Solve a compiled system to steady state.

With `solver=nothing` the SciML stack selects an algorithm. That is the right default across the
loops here, because no single fixed solver suits all of them (a stiff integrator that holds a
near-reversal channel loop will not converge the purely algebraic resistor cube, and the reverse).
If a particular solve does not converge, pass an explicit solver; the coastdown reversal test in
`test_integration.jl` passes `SSRootfind()`.

An operating point is ModelingToolkit's single map over both unknowns and parameters, such as
`[ssys.pump.dP_pump => 6.0e4, ssys.ch.inlet.ṁ => 0.5]`. What an entry means depends on the
solve, so each solver here says what it does with one. The full rules are in
[ModelingToolkit's initialization tutorial](https://docs.sciml.ai/ModelingToolkit/stable/tutorials/initialization/).

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point, a `Vector{Pair}`. A parameter in it takes that value. An unknown in it
  is where the solver starts: the first guess of a root finder, or the state `DynamicSS`
  integrates from. An unknown left out starts from the value the model declares.
- `solver`: steady-state solver to use, or `nothing` to let the stack choose (default `nothing`)
- `abstol`: absolute tolerance (default 1e-8)
- `reltol`: relative tolerance (default 1e-6)
- `build_initializeprob`: passed to `SteadyStateProblem` (default `false`)

A `DynamicSS` solver integrates to steady state and keeps only where it ends, so its inner
integration runs without dense output.

# Returns
`SciMLBase.NonlinearSolution`. Access results via `sol[ssys.component.variable]`.
"""
function solve_steady(
    ssys, op=Pair[]; solver=nothing, abstol=1e-8, reltol=1e-6, build_initializeprob=false
)
    prob = SteadyStateProblem(ssys, op; warn_initialize_determined=false, build_initializeprob)
    # Dense output would only feed interpolation, which DynamicSS never reads, and with it
    # on OrdinaryDiffEq warns about interpolation on a loop with no differential states.
    inner = solver isa DynamicSS ? (; odesolve_kwargs=(; dense=false)) : (;)
    return solve(prob, solver; abstol, reltol, inner...)
end

"""
    solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...) -> SciMLSolution

Solve a transient simulation over a time array, starting from the operating point `op`.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point, a `Vector{Pair}` (see [`solve_steady`](@ref)). A parameter in it
  takes that value for the whole run, including a callable one such as
  `ssys.pump.dP_pump_fn => f`. An unknown in it is its value at `t[1]`, used as given under
  the default `NoInit`. Anything left out takes the value the model declares.
- `t`: time array (e.g. `range(0, 100, length=1000)`); `tspan` derived as `(t[1], t[end])`
- `solver`: ODE solver (default `Rodas5P()`)
- `callbacks`: optional `CallbackSet` for user-supplied events (passed to DifferentialEquations
  `solve`); pre-wired for Flapper support
- `initializealg`: DAE initialization algorithm (default `SciMLBase.NoInit()`, which trusts the
  supplied `op` as a fully consistent initial condition). Pass `SciMLBase.BrownFullBasicInit()`
  to have the solver solve the algebraic constraints for consistency at `t[1]` (holding the
  differential states fixed) before stepping. It is needed when `op` is an approximate or transplanted
  IC that does not exactly satisfy the algebraic equations, where `NoInit` + a stiff solver can
  abort at `t=0` (`dt` driven below floating-point epsilon, `NaN` error estimate).
- `build_initializeprob`: leave at the default `nothing` for almost everything (MTK chooses). Pass
  `false` only for a loop that `mtkcompile` reduces to no differential states (a purely algebraic
  system, such as a flapper and pump with no inertia), where MTK would otherwise build an
  initialization problem that aborts at `t=0`. A stateless system has nothing to make consistent, so
  skipping it is correct.
- `kwargs...`: additional keyword arguments forwarded to `solve`

The solver steps onto every time in `t`, so each saved value is a step's own result rather
than an interpolation inside a step. A smooth run takes long steps, and values read off the
interpolant between them can stray well past the tolerance: a draining pool's level was off by
0.5 m that way. `tstops` passed by the caller are kept alongside.

# Returns
`SciMLBase.ODESolution`. Access time-dependent results via `sol[ssys.component.variable, :]`.
"""
function solve_transient(
    ssys, op, t; solver=Rodas5P(), callbacks=nothing,
    initializealg=SciMLBase.NoInit(), build_initializeprob=nothing, kwargs...,
)
    tspan = (Float64(t[1]), Float64(t[end]))
    init = build_initializeprob === nothing ? (;) : (; build_initializeprob)
    prob = ODEProblem(ssys, op, tspan; warn_initialize_determined=false, init...)
    return solve(prob, solver; saveat=t, callback=callbacks, initializealg,
                 merge(values(kwargs), _saved_steps(prob, t, kwargs))...)
end

"""
    _saved_steps(prob, t, kwargs) -> NamedTuple

The `solve` keywords that put a step end on every saved time: `tstops` holding `t` and any
`tstops` the caller passed.

A problem whose every unknown is algebraic has an all-zero mass matrix, and OrdinaryDiffEq
warns that its interpolation is not error controlled whenever `saveat` is given. With no saved
value interpolated that warning no longer applies, so for such a problem it is silenced unless
the caller passed their own `verbose`.
"""
function _saved_steps(prob, t, kwargs)
    user_stops = collect(Float64, get(kwargs, :tstops, Float64[]))
    tstops = sort!(unique!(vcat(collect(Float64, t), user_stops)))
    M = prob.f.mass_matrix
    stateless = M isa AbstractMatrix && all(iszero, M)
    (stateless && !haskey(kwargs, :verbose)) || return (; tstops)
    # DEVerbosity and SciMLLogging are reached through OrdinaryDiffEqCore, which already
    # loads them, rather than taken on as dependencies of their own.
    core = OrdinaryDiffEq.OrdinaryDiffEqCore
    quiet = core.DEVerbosity(; rosenbrock_no_differential_states=core.SciMLLogging.Silent())
    return (; tstops, verbose=quiet)
end

"""
    solve_transient(ssys, t; kwargs...) -> SciMLSolution

Solve a transient from the values the model declares, with no operating point.

This suits a system whose defaults are the start wanted, such as a `PointKinetics` starting
critical, or one with no differential states, whose equations fix every value at every
instant. The keywords are those of the form that takes
an operating point.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `t`: the times to save at

# Returns
`SciMLBase.ODESolution`.
"""
solve_transient(ssys, t::AbstractVector; kwargs...) = solve_transient(ssys, Pair[], t; kwargs...)

"""
    _state_snapshot(ssys, sol) -> Vector{Pair}

Capture every state of a compiled system at a solved point as a symbolic initial-condition map,
one `unknown => value` per entry of `unknowns(ssys)`.

MTK's problem constructors take a symbolic map rather than a raw state vector. `unknowns(ssys)`
is the complete, non-redundant state, so this seeds a transient from a solved one without
depending on which variables `mtkcompile` kept.

Private, and used only by the [`solve_transient`](@ref) method below.
"""
_state_snapshot(ssys, sol) = [u => sol[u] for u in unknowns(ssys)]

"""
    solve_transient(ssys, sol_ss, t; overrides=Pair[], initializealg=BrownFullBasicInit(),
                    build_initializeprob=false, kwargs...)

Start a transient from an already-solved state.

Takes the full state of `ssys` from `sol_ss`, applies `overrides` (parameter or forcing changes,
such as shutting a pump with `ssys.pump.dP_pump => 0.0` or stepping a reactivity), and integrates
from there. This expresses the settle-then-perturb pipeline: solve a steady state, change one
thing, watch the transient.

Only the unknowns come from `sol_ss`. Every parameter takes the value the model declares
unless `overrides` sets it, so a parameter the steady solve's operating point changed has to
be changed again here. Otherwise the run starts from the steady state with that parameter back
at its declared value, and drifts away from it.

The default `BrownFullBasicInit` re-solves the algebraic constraints for the overridden parameters
while holding the differential states at their snapshotted values, so the start point stays
consistent even though the perturbation broke the old equilibrium. Transplanting the whole state by
symbol means the result does not depend on which variables MTK chose as states.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `sol_ss`: a solved state to start from (e.g. the result of `solve_steady`)
- `t`: time array; `tspan` derived as `(t[1], t[end])`
- `overrides`: `Vector{Pair}` of parameter/forcing changes applied at `t[1]`
- `initializealg`: DAE initialization (default `BrownFullBasicInit()`)
- `build_initializeprob`: build MTK's initialization problem (default `false`, so the run starts
  from the state of `sol_ss` and `initializealg` alone makes it consistent)
- `kwargs...`: forwarded to the lower-level `solve_transient`

# Returns
`SciMLBase.ODESolution`.
"""
function solve_transient(
    ssys, sol_ss::SciMLBase.AbstractSciMLSolution, t;
    overrides=Pair[], initializealg=OrdinaryDiffEq.BrownFullBasicInit(),
    build_initializeprob=false, kwargs...,
)
    # MTK's initialization, solved when the problem is built, can move a differential state off
    # the solution: on a plate loop it shifted one plate temperature by 0.46 K.
    op = Pair{Any,Any}[_state_snapshot(ssys, sol_ss); overrides]
    return solve_transient(ssys, op, t; initializealg, build_initializeprob, kwargs...)
end

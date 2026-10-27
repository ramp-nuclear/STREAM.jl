"""
    solve_steady(ssys, op=Pair[]; t=0.0, solver=nothing, abstol=1e-8, reltol=1e-6) -> SciMLSolution

Solve a compiled system to steady state, with every callable forcing evaluated at the time `t`.

The steady state is the root of `ssys` with each derivative set to zero and the time a
parameter, held at `t`: ModelingToolkit's `NonlinearSystem(ssys; bind_iv=false)`. A pump head
`f(t)` or a valve opening reads its value at `t`, so the steady state is the one a transient
starting at `t` starts from. It keeps the unknowns and observed quantities of `ssys`, with
observed ones evaluated at `t`.

With `solver=nothing`, NonlinearSolve chooses the root finder. A `DynamicSS` solver integrates
from `op` in a pseudo-time, with the model's time held at `t`, until the state stops changing.
That suits a loop whose root finder does not converge from the declared values, or a free
tank level that settles where its inflow and outflow balance. Its integration starts from
`BrownFullBasicInit`, so a guess off the algebraic equations is made consistent rather than
rejected.

An operating point is ModelingToolkit's single map over both unknowns and parameters, such as
`[ssys.pump.dP_pump => 6.0e4, ssys.ch.inlet.ṁ => 0.5]`. The full rules are in
[ModelingToolkit's initialization tutorial](https://docs.sciml.ai/ModelingToolkit/stable/tutorials/initialization/).

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point, a `Vector{Pair}`. A parameter in it takes that value. An unknown in it
  is where the solve starts. An unknown left out starts from the value the model declares.
- `t`: the time the forcings are evaluated at (default 0.0)
- `solver`: `nothing` for NonlinearSolve's default, a NonlinearSolve algorithm, or
  `DynamicSS(alg)`
- `abstol`: absolute tolerance (default 1e-8)
- `reltol`: relative tolerance (default 1e-6)

# Returns
A steady-state solution. Index it with the variables of `ssys`, `sol[ssys.component.variable]`,
and start a transient from it with `solve_transient(ssys, sol, times)`.
"""
function solve_steady(ssys, op=Pair[]; t=0.0, solver=nothing, abstol=1e-8, reltol=1e-6)
    steady = ModelingToolkit.NonlinearSystem(ssys; bind_iv=false)
    # Without initialization: for a system whose unknowns are all observed, MTK's
    # initialization refers to variables it does not define.
    op = Dict{Any,Any}([op; ModelingToolkit.get_iv(ssys) => t])
    residual = NonlinearProblem(steady, op; build_initializeprob=false)
    # The steady residual as an ODE in a pseudo-time, with the mass matrix of `ssys`: a root
    # finder solves it and `DynamicSS` integrates it, and either solution is indexed through
    # `steady`, where `t` is the parameter set above.
    f = ODEFunction{true}(
        (du, u, p, _) -> residual.f(du, u, p);
        mass_matrix=ModelingToolkit.calculate_massmatrix(ssys), sys=steady,
    )
    prob = SteadyStateProblem(f, residual.u0, residual.p)
    # Dense output would only feed interpolation, which DynamicSS never reads, and with it on
    # OrdinaryDiffEq warns about interpolation on a loop with no differential states.
    inner = solver isa DynamicSS ?
        (; odesolve_kwargs=(; dense=false, initializealg=BrownFullBasicInit(; abstol))) : (;)
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
  supplied `op` as a fully consistent initial condition). Pass `BrownFullBasicInit()`, from
  OrdinaryDiffEqNonlinearSolve, to have the solver solve the algebraic constraints for
  consistency at `t[1]` (holding the differential states fixed) before stepping. It is
  needed when `op` is an approximate or transplanted IC that does not exactly satisfy the
  algebraic equations, where `NoInit` + a stiff solver can abort at `t=0` (`dt` driven below
  floating-point epsilon, `NaN` error estimate).
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
    op = [op; _unset_arrays(ssys)]
    prob = ODEProblem(ssys, op, tspan; warn_initialize_determined=false, init...)
    return solve(prob, solver; saveat=t, callback=callbacks, initializealg,
                 merge(values(kwargs), _saved_steps(prob, t, kwargs))...)
end

"""
    _unset_arrays(ssys) -> Vector{Pair}

`v => nothing` for each array variable whose initial condition in `ssys` holds `nothing` in
every element.

`mtkcompile` records such an entry for an array variable it removed, such as the wall of a
channel face no equation reads, and building an initialization system for the problem then
looks for an `Initial` parameter that does not exist. An explicit `nothing` in the operating
point drops the entry.
"""
function _unset_arrays(ssys)
    unset(v) = (u = SymbolicUtils.unwrap_const(v); u isa AbstractArray && all(isnothing, u))
    return [k => nothing for (k, v) in initial_conditions(ssys) if unset(v)]
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
    quiet = DEVerbosity(; rosenbrock_no_differential_states=SciMLLogging.Silent())
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
    solve_transient(ssys, sol_ss, t; overrides=Pair[],
                    initializealg=BrownFullBasicInit(; abstol=1e-8), kwargs...)

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
- `initializealg`: DAE initialization, at the start and after every callback event (default
  `BrownFullBasicInit(; abstol=1e-8)`; the residuals are in SI units, so the algorithm's own
  1e-10 default can be finer than a heat balance in watts resolves)
- `kwargs...`: forwarded to the lower-level `solve_transient`

# Returns
`SciMLBase.ODESolution`.
"""
function solve_transient(
    ssys, sol_ss::SciMLBase.AbstractSciMLSolution, t;
    overrides=Pair[], initializealg=BrownFullBasicInit(; abstol=1e-8), kwargs...,
)
    op = Pair{Any,Any}[_state_snapshot(ssys, sol_ss); overrides]
    return solve_transient(ssys, op, t; initializealg=initializealg, kwargs...)
end

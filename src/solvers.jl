"""
    solve_steady(ssys, op; solver=nothing, kwargs...) -> SciMLSolution

Solve a compiled system to steady state.

With `solver=nothing` the SciML stack selects an algorithm. That is the right default across the
loops here, because no single fixed solver suits all of them (a stiff integrator that holds a
near-reversal channel loop will not converge the purely algebraic resistor cube, and the reverse).
If a particular solve does not converge, pass an explicit solver; the coastdown reversal test in
`test_integration.jl` passes `SSRootfind()`.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point as `Vector{Pair}` of initial guesses
- `solver`: steady-state solver to use, or `nothing` to let the stack choose (default `nothing`)
- `abstol`: absolute tolerance (default 1e-8)
- `reltol`: relative tolerance (default 1e-6)
- `build_initializeprob`: passed to `SteadyStateProblem` (default `false`)

A `DynamicSS` solver integrates to steady state and keeps only where it ends, so its inner
integration runs without dense output.

# Throws
- `ArgumentError`: for a pinned [`Tank`](@ref) with its energy balance on and no inflow,
  whose temperature nothing in the steady state sets

# Returns
`SciMLBase.NonlinearSolution`. Access results via `sol[ssys.component.variable]`.
"""
function solve_steady(
    ssys, op=Pair[]; solver=nothing, abstol=1e-8, reltol=1e-6, build_initializeprob=false
)
    prob = SteadyStateProblem(
        ssys,
        op;
        warn_initialize_determined=false,
        build_initializeprob=build_initializeprob,
    )
    # Dense output would only feed interpolation, which DynamicSS never reads, and with it
    # on OrdinaryDiffEq warns about interpolation on a loop with no differential states.
    inner = solver isa DynamicSS ? (; odesolve_kwargs=(; dense=false)) : (;)
    sol = solve(prob, solver; abstol=abstol, reltol=reltol, inner...)
    _check_tank_temperatures(ssys, sol, abstol)
    return sol
end

"""
    _pinned_parameters(ssys) -> Vector

The `pinned` parameter of every [`Tank`](@ref) in `ssys`, found by name.
"""
_pinned_parameters(ssys) =
    filter(p -> occursin(r"(^|₊)pinned$", string(ModelingToolkit.getname(p))), parameters(ssys))

"""
    _tank_path(pinned) -> String

The tank a `pinned` parameter belongs to, as it is reached from the compiled system:
`"pool"` for `pool₊pinned`.
"""
_tank_path(pinned) = replace(chop(string(ModelingToolkit.getname(pinned)); tail=7), "₊" => ".")

"""
    _check_tank_temperatures(ssys, sol, tol)

Throw an `ArgumentError` for the first pinned [`Tank`](@ref) in `ssys` whose energy balance
is on and whose `inflow` in the steady solution `sol` is `tol` or less. The steady energy
balance of such a tank holds at any temperature, or at none with `Q_ext`, so the solver
returns whatever `T` it ends on.
"""
function _check_tank_temperatures(ssys, sol, tol)
    pinned = filter(p -> sol.ps[p], _pinned_parameters(ssys))
    isempty(pinned) && return nothing
    variables = [unknowns(ssys); [eq.lhs for eq in observed(ssys)]]
    named = Dict(string(ModelingToolkit.getname(v)) => v for v in variables)
    for p in pinned
        prefix = chop(string(ModelingToolkit.getname(p)); tail=length("pinned"))
        inflow = get(named, prefix * "inflow", nothing)
        (inflow === nothing || sol[inflow] > tol) && continue
        tank = _tank_path(p)
        throw(ArgumentError(
            "$tank has no inflow in the steady state, so nothing sets its temperature. " *
            "Build it with `fixed_temperature=true`, or start the transient from its " *
            "declared state: `solve_transient(ssys, [ssys.$tank.pinned => false], t)`",
        ))
    end
    return nothing
end

"""
    solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...) -> SciMLSolution
    solve_transient(ssys, t; kwargs...) -> SciMLSolution

Solve a transient simulation over a time array.

Without `op` the run starts from the values the model declares. That suits a system with no
differential states, whose equations fix every value at every instant, and one whose defaults
are the start wanted, such as a `PointKinetics` starting critical.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point / initial conditions as `Vector{Pair}` (states and parameters,
  including callable parameters such as `ssys.pump.dP_pump_fn => f`)
- `t`: time array (e.g. `range(0, 100, length=1000)`); `tspan` derived as `(t[1], t[end])`
- `solver`: ODE solver (default `Rodas5P()`)
- `callbacks`: optional `CallbackSet` for user-supplied events (passed to DifferentialEquations
  `solve`); pre-wired for Flapper support
- `initializealg`: DAE initialization algorithm (default `SciMLBase.NoInit()`, which trusts the
  supplied `op` as a fully consistent initial condition). Pass `SciMLBase.BrownFullBasicInit()`
  to have the solver solve the algebraic constraints for consistency at `t[1]` (holding the
  differential states fixed) before stepping — needed when `op` is an approximate / transplanted
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
    prob = build_initializeprob === nothing ?
        ODEProblem(ssys, op, tspan; warn_initialize_determined=false) :
        ODEProblem(ssys, op, tspan; warn_initialize_determined=false,
                   build_initializeprob=build_initializeprob)
    _warn_pinned(prob, op)
    sol = solve(
        prob,
        solver;
        saveat=t,
        callback=callbacks,
        initializealg=initializealg,
        merge(values(kwargs), _saved_steps(prob, t, kwargs))...,
    )
    return sol
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

solve_transient(ssys, t::AbstractVector; kwargs...) = solve_transient(ssys, Pair[], t; kwargs...)

"""
    _warn_pinned(prob, op)

Warn about each [`Tank`](@ref) still pinned in `prob` whose `pinned` the operating point `op`
does not name. Naming it, even as `true`, says the pinned run is meant.
"""
function _warn_pinned(prob, op)
    named(p) = any(o -> isequal(ModelingToolkit.unwrap(first(o)), p), op)
    for p in _pinned_parameters(prob.f.sys)
        (prob.ps[p] && !named(p)) || continue
        tank = _tank_path(p)
        @warn "$tank is still pinned, so its level stays at L0. Release it with " *
              "`overrides=[ssys.$tank.pinned => false]`."
    end
    return nothing
end

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
    solve_transient(ssys, sol_ss, t; overrides=Pair[], initializealg=BrownFullBasicInit(), kwargs...)

Start a transient from an already-solved state.

Takes the full state of `ssys` from `sol_ss`, applies `overrides` (parameter or forcing changes,
such as shutting a pump with `ssys.pump.dP_pump => 0.0` or stepping a reactivity), and integrates
from there. This expresses the settle-then-perturb pipeline: solve a steady state, change one
thing, watch the transient.

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
- `kwargs...`: forwarded to the lower-level `solve_transient`

# Returns
`SciMLBase.ODESolution`.
"""
function solve_transient(
    ssys, sol_ss::SciMLBase.AbstractSciMLSolution, t;
    overrides=Pair[], initializealg=OrdinaryDiffEq.BrownFullBasicInit(), kwargs...,
)
    op = Pair{Any,Any}[_state_snapshot(ssys, sol_ss); overrides]
    return solve_transient(ssys, op, t; initializealg=initializealg, kwargs...)
end

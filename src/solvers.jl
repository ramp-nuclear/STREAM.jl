# solvers.jl -- Solver API
#

"""
    steady_state_guess(; T_inlet, Q_wall, mdot_guess, n) -> Vector{Float64}

Generate a linear temperature guess for steady-state initialization.

# Arguments
- `T_inlet`: inlet temperature [K]
- `Q_wall`: total wall heat input [W]
- `mdot_guess`: estimated mass flow rate [kg/s]
- `n`: number of axial cells (Int)

# Returns
Vector of length `n` with linearly interpolated temperatures from `T_inlet` to estimated
`T_outlet` as `Float64`.
"""
function steady_state_guess(;
    T_inlet::Float64, Q_wall::Float64, mdot_guess::Float64, n::Int
)
    cp = cp_water(T_inlet)
    return [T_inlet + i * Q_wall / (n * mdot_guess * cp) for i in 1:n]
end

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

# Returns
`SciMLBase.NonlinearSolution`. Access results via `sol[ssys.component.variable]`.
"""
function solve_steady(
    ssys, op; solver=nothing, abstol=1e-8, reltol=1e-6, build_initializeprob=false
)
    prob = SteadyStateProblem(
        ssys,
        op;
        warn_initialize_determined=false,
        build_initializeprob=build_initializeprob,
    )
    sol = solve(prob, solver; abstol=abstol, reltol=reltol)
    return sol
end

"""
    solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...) -> SciMLSolution

Solve a transient simulation over a time array.

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
    sol = solve(
        prob,
        solver;
        saveat=t,
        callback=callbacks,
        initializealg=initializealg,
        kwargs...,
    )
    return sol
end

# Internal helper. Capture every state of a compiled system from a solved point as a symbolic
# initial-condition map (`unknown => value` for each entry of `unknowns(ssys)`). MTK problem
# constructors require a symbolic map, not a raw state vector or a bare solution. `unknowns(ssys)`
# is the complete, non-redundant state (observed variables are recomputed from it), so this seeds a
# transient from a solved state without guessing which variables MTK kept. Used by the
# `solve_transient(ssys, sol_ss, t; ...)` method below; not part of the public API.
_state_snapshot(ssys, sol) = [u => sol[u] for u in unknowns(ssys)]

"""
    solve_transient(ssys, sol_ss, t; overrides=Pair[], initializealg=BrownFullBasicInit(), kwargs...)

Start a transient from an already-solved state.

Takes the full state of `ssys` from `sol_ss`, applies `overrides` (parameter or forcing changes,
such as shutting a pump with `ssys.pump.dP_pump => 0.0` or stepping a reactivity), and integrates
from there. This expresses the settle-then-perturb pipeline: solve a steady state, change one thing,
watch the transient.

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

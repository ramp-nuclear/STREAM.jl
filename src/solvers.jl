# solvers.jl -- Solver API for STREAM.jl
#
# Future refactor note (v0.2): consider SteadySolution(sol, sys) and
# TransientSolution(sol, sys) wrapper structs that expose named properties
# like sol.T_outlet, sol.mdot instead of MTK symbolic indexing
# sol[sys.ch.T_out]. Deferred until v0.1 usage patterns are clear.

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using OrdinaryDiffEq, SteadyStateDiffEq

# ----------------------------------------------------------------
# steady_state_guess
# Physics-based initial guess for the steady-state solver.
# Based on Python STREAM's symmetric_plate_steady_state pattern.
# T_inlet: K, Q_wall: W, mdot_guess: kg/s, n: number of cells
# Returns T_cells::Vector{Float64} (Kelvin), length n.
# ----------------------------------------------------------------
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
    T_inlet::Float64,
    Q_wall::Float64,
    mdot_guess::Float64,
    n::Int,
    liquid::AbstractLiquid=H2O,
)
    cp = cₚ(liquid, T_inlet)
    return [T_inlet + i * Q_wall / (n * mdot_guess * cp) for i in 1:n]
end

"""
    solve_steady(ssys, op; solver=nothing, kwargs...) -> SciMLSolution

Solve a compiled system to steady state using KINSOL (or a user-specified solver).

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point as `Vector{Pair}` of initial guesses
- `solver`: nonlinear solver to use
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
  `solve`); pre-wired for Phase 23 Flapper support
- `kwargs...`: additional keyword arguments forwarded to `solve`

# Returns
`SciMLBase.ODESolution`. Access time-dependent results via `sol[ssys.component.variable, :]`.
"""
function solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...)
    # MTK mtkcompile produces a mass-matrix ODE (implicit DAE form).
    # Rodas5P is a stiff implicit Runge-Kutta solver that supports mass matrices
    # and ODEProblem — the correct choice for MTK-generated DAE systems.
    tspan = (Float64(t[1]), Float64(t[end]))
    prob = ODEProblem(ssys, op, tspan; warn_initialize_determined=false)

    # NoInit: skip MTK's automatic initialization (which fails for the rough
    # guess op dict). The caller is responsible for providing a consistent-enough
    # initial state (use steady_state_guess or a prior solve_steady solution).
    sol = solve(
        prob,
        solver;
        saveat=t,
        callback=callbacks,
        initializealg=SciMLBase.NoInit(),
        kwargs...,
    )
    return sol
end

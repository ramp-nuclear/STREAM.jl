# solvers.jl -- Solver API for STREAM.jl
#
# Future refactor note (v0.2): consider SteadySolution(sol, sys) and
# TransientSolution(sol, sys) wrapper structs that expose named properties
# like sol.T_outlet, sol.mdot instead of MTK symbolic indexing
# sol[sys.ch.T_out]. Deferred until v0.1 usage patterns are clear.

using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations   # SSRootfind -- NOT in ModelingToolkit
using Sundials                 # KINSOL, IDA

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
function steady_state_guess(; T_inlet::Float64, Q_wall::Float64,
                               mdot_guess::Float64, n::Int)
    cp = cp_water(T_inlet)
    return [T_inlet + i * Q_wall / (n * mdot_guess * cp) for i in 1:n]
end

# ----------------------------------------------------------------
# solve_steady
# Solves the compiled loop system for steady state using KINSOL.
#
# ssys: compiled system from build_loop()
# op:   Vector{Pair} of symbolic_var => initial_value
#       Use symbols from ssys (compiled), e.g. ssys.ch.T[1] => 315.0
#       Build the initial guess using steady_state_guess() for T cells.
#       Also include ssys.ch.port_in.mdot => mdot_guess for mass flow.
#
# Returns SteadyStateSolution. Access results via symbolic indexing:
#   sol[ssys.ch.T_out]              outlet temperature (K)
#   sol[ssys.ch.port_in.mdot]       mass flow (kg/s)
# ----------------------------------------------------------------
"""
    solve_steady(ssys, op; solver=nothing, kwargs...) -> SciMLSolution

Solve a compiled system to steady state using KINSOL (or a user-specified solver).

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `op`: operating point as `Vector{Pair}` of initial guesses
- `abstol`: absolute tolerance (default 1e-8)
- `reltol`: relative tolerance (default 1e-6)
- `build_initializeprob`: passed to `SteadyStateProblem` (default `false`)

# Returns
`SciMLBase.NonlinearSolution`. Access results via `sol[ssys.component.variable]`.
"""
function solve_steady(ssys, op;
                      abstol = 1e-8,
                      reltol = 1e-6,
                      build_initializeprob = false)
    prob = SteadyStateProblem(ssys, op;
                              warn_initialize_determined=false,
                              build_initializeprob=build_initializeprob)
    sol  = solve(prob, SSRootfind(KINSOL()); abstol = abstol, reltol = reltol)
    return sol
end

# ----------------------------------------------------------------
# solve_transient
# Simulates the closed loop with a step change in wall temperature
# (which controls the effective wall heat input).
#
# ssys:         compiled system from build_loop_transient()
# T_wall_sym:   parameter symbol from build_loop_transient() (second return value)
# op:           Vector{Pair} — initial conditions for state variables
#               (same structure as solve_steady op: ch.T[1..n], ch.port_in.mdot)
# tspan:        (t_start, t_end) in seconds, e.g. (0.0, 60.0)
# T_wall_final: new T_wall value (K) after the step change (e.g. 393.15 K for ~120°C)
# t_step:       time of step change (s), default 10.0
#
# Returns ODESolution. Access time-series:
#   sol[ssys.ch.T_out, :]      -- outlet T (K) at all time points
#   sol.t                       -- time vector (s)
# ----------------------------------------------------------------
"""
    solve_transient(; ssys, T_wall_sym, op, tspan, T_wall_final, t_step=10.0) -> SciMLSolution

Solve a transient simulation with a step-change wall temperature callback.

# Arguments
- `ssys`: compiled system from `build_loop_transient`
- `T_wall_sym`: symbolic parameter for wall temperature (second return value of `build_loop_transient`)
- `op`: initial operating point as `Vector{Pair}`
- `tspan`: time span tuple `(t_start, t_end)` [s]
- `T_wall_final`: new wall temperature [K] after the step change
- `t_step`: time of step change [s], default 10.0

# Returns
`SciMLBase.ODESolution`. Access time-dependent results via `sol[ssys.component.variable]`.
"""
function solve_transient(; ssys, T_wall_sym, op, tspan,
                           T_wall_final,
                           t_step = 10.0)
    # MTK mtkcompile produces a mass-matrix ODE (implicit DAE form).

    # IDA requires DAEProblem with explicit du0; CVODE_BDF cannot use mass matrices.
    # Rodas5P is a stiff implicit Runge-Kutta solver that supports mass matrices
    # and ODEProblem — the correct choice for MTK-generated DAE systems.
    prob = ODEProblem(ssys, op, tspan; warn_initialize_determined=false)

    # PresetTimeCallback: fires at t_step, sets T_wall to T_wall_final
    # setp is in ModelingToolkit (not exported from public namespace)
    T_wall_setter = ModelingToolkit.setp(ssys, T_wall_sym)
    step_cb = PresetTimeCallback(
        [t_step],
        integrator -> T_wall_setter(integrator, T_wall_final)
    )

    # NoInit: skip MTK's automatic initialization (which fails for the rough
    # guess op dict). The caller is responsible for providing a consistent-enough
    # initial state (use steady_state_guess or a prior solve_steady solution).
    sol = solve(prob, Rodas5P(); callback = step_cb, initializealg = SciMLBase.NoInit())
    return sol
end

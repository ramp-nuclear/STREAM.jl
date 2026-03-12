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
function steady_state_guess(; T_inlet::Float64, Q_wall::Float64,
                               mdot_guess::Float64, n::Int)
    cp = cp_water(T_inlet)
    return [T_inlet + i * Q_wall / (n * mdot_guess * cp) for i in 1:n]
end

# ----------------------------------------------------------------
# _make_temp_bc (internal helper)
# Creates a temperature-reset boundary condition component.
# Injects T_bc into the downstream stream so that instream() in
# the connected Channel sees T_bc as the inlet temperature.
# This is required because MTK stream semantics resolve instream()
# to the connected port's T variable, which in a closed loop would
# create a circular thermal dependency. The TempBC breaks the loop.
# ----------------------------------------------------------------
function _make_temp_bc(; name, T_bc)
    pars = @parameters T_bc = T_bc
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,    # mass conservation
        port_in.P   - port_out.P    ~ 0,     # no pressure drop
        port_out.T  ~ T_bc,                   # inject T_bc into stream
        port_in.T   ~ instream(port_out.T),   # backward stream (adiabatic)
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end

# ----------------------------------------------------------------
# build_loop
# Assembles the closed forced-convection loop:
#   Pump -> TempBC -> Friction -> Channel -> back to Pump
# and compiles it with mtkcompile.
#
# The TempBC component resets the fluid temperature to T_inlet at
# the pump outlet. This is necessary because MTK stream semantics
# resolve instream(ch.port_in.T) to the upstream connected port's T
# (which would be T[n] in a fully closed loop, giving a trivial
# degenerate steady state at T=T_wall). The TempBC forces the
# "inlet temperature" seen by the Channel's first-cell energy
# balance to be T_inlet, enabling physical non-trivial solutions.
#
# Boundary conditions:
#   pump.port_in.P ~ 1.0e5     pressure gauge freedom fix (absolute anchor)
#   ch.thermal.T ~ T_wall      wall temperature (K) -- required by Channel's
#                              Dittus-Boelter HTC: h_tc[i]*(pi*Dh)*dz*(thermal.T - T[i])
#   ch.port_in.T ~ T_inlet     additional T_inlet constraint (resolves remaining
#                              circular temperature dependency in compiled system)
#
# Returns compiled ssys. Use ssys.ch.T[i], ssys.fr.port_in.mdot, etc.
# for symbolic indexing of results.
# ----------------------------------------------------------------
function build_loop(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    L_fr     = 0.3,
    D_fr     = 0.01,
    A_fr     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,   # coolant inlet temperature (K); 40°C
    T_wall   = 373.15,   # wall temperature (K); ~100°C for forced convection
)
    @named pump = Pump(dP_pump = dP_pump)
    @named fr   = Friction(L = L_fr, D = D_fr, A = A_fr)
    @named ch   = Channel(n = n, L = L_ch, D = D_ch, A = A_ch)
    @named bc   = _make_temp_bc(T_bc = T_inlet)   # temperature reset at pump outlet

    connections = [
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out,   fr.port_in),        # TempBC -> friction
        connect(fr.port_out,   ch.port_in),        # friction -> channel
        connect(ch.port_out,   pump.port_in),      # channel -> pump (closed loop)
        pump.port_in.P  ~ 1.0e5,                  # pressure gauge freedom fix
        ch.thermal.T    ~ T_wall,                  # wall temperature pin (for HTC)
        ch.port_in.T    ~ T_inlet,                 # T_inlet constraint (resolves circular T)
    ]

    @named sys = compose(System(connections, t; name = :sys), pump, bc, fr, ch)

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "mtkcompile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

# ----------------------------------------------------------------
# solve_steady
# Solves the compiled loop system for steady state using KINSOL.
#
# ssys: compiled system from build_loop()
# op:   Vector{Pair} of symbolic_var => initial_value
#       Use symbols from ssys (compiled), e.g. ssys.ch.T[1] => 315.0
#       Build the initial guess using steady_state_guess() for T cells.
#       Also include ssys.fr.port_in.mdot => mdot_guess and
#       ssys.fr.Re => Re_guess for the algebraic variables.
#
# Returns SteadyStateSolution. Access results via symbolic indexing:
#   sol[ssys.ch.T_out]           outlet temperature (K)
#   sol[ssys.fr.port_in.mdot]    mass flow (kg/s)
# ----------------------------------------------------------------
function solve_steady(ssys, op;
                      abstol = 1e-8,
                      reltol = 1e-6)
    prob = SteadyStateProblem(ssys, op; warn_initialize_determined=false)
    sol  = solve(prob, SSRootfind(KINSOL()); abstol = abstol, reltol = reltol)
    return sol
end

# ----------------------------------------------------------------
# build_loop_transient
# Same topology as build_loop (Pump -> TempBC -> Friction -> Channel)
# but with T_wall declared as a @parameters symbol so that
# PresetTimeCallback + setp can modify it at runtime to simulate
# a step change in wall heat input.
#
# Why T_wall rather than Q_wall as the modifiable parameter:
#   Channel's energy balance uses h_tc[i] * (π*Dh) * dz * (thermal.T - T[i])
#   — the driver is the wall temperature, not Q_flow directly. Q_flow is an
#   observable (q_wall[i] ~ thermal.Q_flow / n) not in the energy balance.
#   Stepping T_wall is equivalent to stepping the effective heat input.
#
# Returns (ssys, T_wall_sym) where T_wall_sym is the compiled parameter symbol.
# Pass T_wall_sym as the second argument to solve_transient.
# ----------------------------------------------------------------
function build_loop_transient(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    L_fr     = 0.3,
    D_fr     = 0.01,
    A_fr     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,   # coolant inlet temperature (K); 40°C
    T_wall_0 = 373.15,   # initial wall temperature (K); ~100°C
)
    @named pump = Pump(dP_pump = dP_pump)
    @named fr   = Friction(L = L_fr, D = D_fr, A = A_fr)
    @named ch   = Channel(n = n, L = L_ch, D = D_ch, A = A_ch)
    @named bc   = _make_temp_bc(T_bc = T_inlet)   # temperature reset at pump outlet

    # Declare T_wall as a modifiable parameter
    ps = @parameters T_wall = T_wall_0

    connections = [
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out,   fr.port_in),        # TempBC -> friction
        connect(fr.port_out,   ch.port_in),        # friction -> channel
        connect(ch.port_out,   pump.port_in),      # channel -> pump (closed loop)
        pump.port_in.P  ~ 1.0e5,                   # pressure gauge freedom fix
        ch.thermal.T    ~ ps[1],                   # wall temperature (modifiable parameter)
        ch.port_in.T    ~ T_inlet,                 # T_inlet constraint (resolves circular T)
    ]

    @named sys = compose(
        System(connections, t, [], ps; name = :sys),
        pump, bc, fr, ch
    )

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_transient compile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys, ps[1]
end

# ----------------------------------------------------------------
# solve_transient
# Simulates the closed loop with a step change in wall temperature
# (which controls the effective wall heat input).
#
# ssys:         compiled system from build_loop_transient()
# T_wall_sym:   parameter symbol from build_loop_transient() (second return value)
# op:           Vector{Pair} — initial conditions for state variables
#               (same structure as solve_steady op: ch.T[1..n], fr.port_in.mdot, fr.Re)
# tspan:        (t_start, t_end) in seconds, e.g. (0.0, 60.0)
# T_wall_final: new T_wall value (K) after the step change (e.g. 393.15 K for ~120°C)
# t_step:       time of step change (s), default 10.0
#
# Returns ODESolution. Access time-series:
#   sol[ssys.ch.T_out, :]      -- outlet T (K) at all time points
#   sol.t                       -- time vector (s)
# ----------------------------------------------------------------
function solve_transient(ssys, T_wall_sym, op, tspan;
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

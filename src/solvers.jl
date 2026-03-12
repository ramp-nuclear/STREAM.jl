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
# solve_transient  (stub -- implemented in plan 03-02)
# ----------------------------------------------------------------
function solve_transient(ssys, op, tspan; Q_wall_final, t_step = 10.0)
    error("solve_transient not yet implemented -- see plan 03-02")
end

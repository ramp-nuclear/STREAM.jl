# examples.jl — Example system builders for STREAM.jl
# build_loop, build_loop_vertical, build_loop_transient, build_cube

# ----------------------------------------------------------------
# build_loop
# Assembles the closed forced-convection loop:
#   Pump -> TempBC -> Channel -> back to Pump
# and compiles it with mtkcompile.
#
# Channel handles friction (Darcy-Weisbach Blasius) and gravity internally.
# No separate Friction component — friction is part of Channel's dP equation.
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
# Returns compiled ssys. Use ssys.ch.T[i], ssys.ch.port_in.mdot, etc.
# for symbolic indexing of results.
# ----------------------------------------------------------------
"""
    build_loop(; n=10, T_inlet=313.15, T_wall=373.15, L_ch=0.6, D_ch=0.01, dP_pump=3.0e4) -> ODESystem

Build a simple steady-state horizontal flow loop (Pump + HeatExchanger + ChannelHeatFlux).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall`: wall temperature [K] (default 373.15)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)

# Returns
Compiled `ODESystem` (already passed through `mtkcompile`).
"""
function build_loop(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,   # coolant inlet temperature (K); 40°C
    T_wall   = 373.15,   # wall temperature (K); ~100°C for forced convection
)
    @named pump = Pump(dP_pump)
    @named ch   = Channel(n = n, geometry = PipeGeometry_circular(L_ch, D_ch))
    @named bc   = HeatExchanger(T_bc = T_inlet)   # temperature reset at pump outlet

    connections = [
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out,   ch.port_in),        # TempBC -> channel
        connect(ch.port_out,   pump.port_in),      # channel -> pump (closed loop)
        pump.port_in.P  ~ 1.0e5,                  # pressure gauge freedom fix
        ch.thermal.T    ~ T_wall,                  # wall temperature pin (for HTC)
        ch.port_in.T    ~ T_inlet,                 # T_inlet constraint (resolves circular T)
    ]

    @named sys = compose(System(connections, t; name = :sys), pump, bc, ch)

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "mtkcompile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

# ----------------------------------------------------------------
# build_loop_vertical
# Assembles a vertical closed loop that includes gravity effects:
#   Pump -> TempBC -> Channel(g_acc=9.80665) -> Gravity(H) -> Pump
#
# The upward leg is modelled by Channel with g_acc set to the
# gravitational acceleration (default 9.80665 m/s²). The Channel's
# dP equation includes +rho*g_acc*L representing the hydrostatic
# head loss as the fluid rises.
#
# The return (downward) leg is modelled by the standalone Gravity
# component with height H (default = L_ch). Gravity's equation:
#   port_in.P - port_out.P ~ rho * 9.80665 * H
# represents the pressure gain as the fluid descends.
#
# Cancellation geometry (default): when H_return == L_ch and
# g_acc == 9.80665, the upward head loss equals the downward head
# gain, and the net gravity contribution to the loop pressure
# balance is zero — matching the horizontal reference loop within
# the accuracy of the density evaluation point (~1%).
#
# Returns compiled ssys. Use ssys.ch.T[i], ssys.ch.port_in.mdot
# for symbolic indexing (same pattern as build_loop).
# ----------------------------------------------------------------
"""
    build_loop_vertical(; n=10, T_inlet=313.15, T_wall=373.15, L_ch=0.6, D_ch=0.01, dP_pump=3.0e4, H=0.6) -> ODESystem

Build a vertical flow loop with gravity (Pump + HeatExchanger + Channel + Gravity).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall`: wall temperature [K] (default 373.15)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `g_acc`: gravitational acceleration [m/s^2] (default 9.80665)
- `H_return`: height of return leg [m], defaults to `L_ch` for cancellation geometry

# Returns
Compiled `ODESystem`.
"""
function build_loop_vertical(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,    # coolant inlet temperature (K); 40°C
    T_wall   = 373.15,    # wall temperature (K); ~100°C for forced convection
    g_acc    = 9.80665,   # gravitational acceleration (m/s²)
    H_return = nothing,   # height of return leg (m); defaults to L_ch for cancellation geometry
)
    H = isnothing(H_return) ? L_ch : H_return

    @named pump = Pump(dP_pump)
    @named ch   = Channel(n = n, geometry = PipeGeometry_circular(L_ch, D_ch), g = g_acc)
    @named bc   = HeatExchanger(T_bc = T_inlet)
    @named grav = Gravity(H = H)

    # Gravity wiring note:
    # Gravity equation: port_in.P - port_out.P ~ rho*g*H (port_in = high-P = bottom)
    # For the RETURN leg (fluid descends from channel top back to pump bottom):
    #   - channel outlet (top, low pressure) = grav.port_out (top)
    #   - pump inlet (bottom, higher pressure) = grav.port_in (bottom)
    # This gives: pump_inlet.P = channel_outlet.P + rho*g*H
    # Loop balance: dP_pump = friction + rho*g*L_ch - rho*g*H
    # Cancellation when H = L_ch: dP_pump = friction (gravity terms cancel).
    connections = [
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out,   ch.port_in),        # TempBC -> channel (upward leg)
        connect(ch.port_out,   grav.port_out),     # channel outlet (top) = grav port_out (top)
        connect(grav.port_in,  pump.port_in),      # grav port_in (bottom) = pump inlet (bottom)
        pump.port_in.P  ~ 1.0e5,                  # pressure gauge freedom fix
        ch.thermal.T    ~ T_wall,                  # wall temperature pin (for HTC)
        ch.port_in.T    ~ T_inlet,                 # T_inlet constraint (resolves circular T)
    ]

    @named sys = compose(System(connections, t; name = :sys), pump, bc, ch, grav)

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_vertical compile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

"""
    build_loop_transient(; n=10, T_inlet=313.15, T_wall_0=373.15, L_ch=0.6, D_ch=0.01, dP_pump=3.0e4, T_wall_fn=nothing) -> ODESystem

Build a transient-capable flow loop. When `T_wall_fn` is provided (a callable `t -> K`),
wall temperature is time-varying via an MTK callable parameter. When `T_wall_fn` is `nothing`,
wall temperature is pinned to the scalar `T_wall_0`.

When using a callable `T_wall_fn`, the caller must include the callable parameter in `op`:
`ssys.sys.T_wall_callable => T_wall_fn` (where `ssys` is the compiled system).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall_0`: wall temperature [K] (default 373.15); used when `T_wall_fn` is `nothing`
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `T_wall_fn`: optional callable `(t) -> K` for time-varying wall temperature

# Returns
Compiled `ODESystem` (already passed through `mtkcompile`).
"""
function build_loop_transient(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,    # coolant inlet temperature (K); 40°C
    T_wall_0 = 373.15,    # wall temperature (K); used when T_wall_fn is nothing
    T_wall_fn = nothing,  # optional callable (t) -> K for time-varying wall temperature
)
    @named pump = Pump(dP_pump)
    @named ch   = Channel(n = n, geometry = PipeGeometry_circular(L_ch, D_ch))
    @named bc   = HeatExchanger(T_bc = T_inlet)   # temperature reset at pump outlet

    if T_wall_fn === nothing
        # Scalar wall temperature — same as build_loop; no parameter declaration needed
        connections = [
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out,   ch.port_in),
            connect(ch.port_out,   pump.port_in),
            pump.port_in.P  ~ 1.0e5,
            ch.thermal.T    ~ T_wall_0,
            ch.port_in.T    ~ T_inlet,
        ]
        @named sys = compose(System(connections, t; name = :sys), pump, bc, ch)
    else
        # Callable wall temperature — uses MTK callable parameter
        # Caller must include ssys.sys.T_wall_callable => T_wall_fn in op
        FType = typeof(T_wall_fn)
        ps = @parameters (T_wall_callable::FType)(..)
        connections = [
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out,   ch.port_in),
            connect(ch.port_out,   pump.port_in),
            pump.port_in.P  ~ 1.0e5,
            ch.thermal.T    ~ ps[1](t),
            ch.port_in.T    ~ T_inlet,
        ]
        @named sys = compose(System(connections, t, [], ps; name = :sys), pump, bc, ch)
    end

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_transient compile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

# ----------------------------------------------------------------
# build_cube
# Assembles the Cube hydraulic network: 12 Resistors on the edges
# of a cube, 1 Pump driving body-diagonal flow (corner 0 -> corner 7).
#
# Corner labeling (binary xyz bits):
#   000=0, 001=1, 010=2, 011=3, 100=4, 101=5, 110=6, 111=7
# 12 edges (one Resistor each): r01, r02, r04, r13, r15, r23, r26,
#   r37, r45, r46, r57, r67
# Each interior corner has exactly 3 Resistor ports — wired with a
# 3-way connect() call. Source (corner 0) and sink (corner 7) are
# 4-way (pump + 3 resistors each).
#
# MTK variadic connect() generates the Kirchhoff equations:
#   Flow (mdot): sum = 0 at each junction
#   Across (P):  equal at each junction
#   Stream (T):  instream() mixture
#
# Analytical equivalent resistance (body diagonal): 5/6 * R
# Expected total mdot: dP_pump * 6 / (5 * R)
#
# Returns compiled ssys.
# ----------------------------------------------------------------
"""
    build_cube(; dP_pump=3.0e4, R=1.0e4) -> ODESystem

Build a two-branch parallel network (cube topology) for network solver validation.

# Arguments
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `R`: branch resistance [Pa/(kg/s)] (default 1.0e4)

# Returns
Compiled `ODESystem`.
"""
function build_cube(; dP_pump=3.0e4, R=1.0e4)
    @named pump = Pump(dP_pump)
    # 12 edges of the cube (naming: r_ij where i < j are corner indices)
    @named r01 = Resistor(R=R); @named r02 = Resistor(R=R); @named r04 = Resistor(R=R)
    @named r13 = Resistor(R=R); @named r15 = Resistor(R=R)
    @named r23 = Resistor(R=R); @named r26 = Resistor(R=R)
    @named r37 = Resistor(R=R)
    @named r45 = Resistor(R=R); @named r46 = Resistor(R=R)
    @named r57 = Resistor(R=R)
    @named r67 = Resistor(R=R)

    connections = [
        # Corner 0 (source): pump.port_out + 3 resistor inlets
        connect(pump.port_out, r01.port_in, r02.port_in, r04.port_in),
        # Corner 1: r01 out + r13 in + r15 in
        connect(r01.port_out,  r13.port_in, r15.port_in),
        # Corner 2: r02 out + r23 in + r26 in
        connect(r02.port_out,  r23.port_in, r26.port_in),
        # Corner 3: r13 out + r23 out + r37 in
        connect(r13.port_out,  r23.port_out, r37.port_in),
        # Corner 4: r04 out + r45 in + r46 in
        connect(r04.port_out,  r45.port_in, r46.port_in),
        # Corner 5: r15 out + r45 out + r57 in
        connect(r15.port_out,  r45.port_out, r57.port_in),
        # Corner 6: r26 out + r46 out + r67 in
        connect(r26.port_out,  r46.port_out, r67.port_in),
        # Corner 7 (sink): pump.port_in + 3 resistor outlets
        connect(pump.port_in,  r37.port_out, r57.port_out, r67.port_out),
        # Pressure gauge anchor (absolute level is underdetermined by Kirchhoff equations)
        pump.port_in.P ~ 1.0e5,
    ]

    @named sys = compose(
        System(connections, t; name=:sys),
        pump, r01, r02, r04, r13, r15, r23, r26, r37, r45, r46, r57, r67
    )

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_cube compile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

"""
    build_loop_lof(; n=10, L_ch=1.0, D_ch=0.01, T_wall=373.15, T_inlet=313.15,
                    L_over_A=1.75e5, g_acc_ch=9.80665, threshold=0.01, dt_ramp=5.0) -> ODESystem

Build a loss-of-flow validation loop using a series topology with a Flapper check valve.
Used for end-to-end LOF transient validation (VAL-01, VAL-02).

Topology (series):
`Pump(0.0) -> Inertia -> HeatExchanger(T_inlet) -> ChannelHeatFlux(g=g_acc_ch) -> Flapper -> Pump`

Physics: With `g_acc_ch > 0` (upward channel), gravity opposes forced flow. At t=0 the pump
produces zero pressure rise; the Inertia carries the initial forced-flow momentum which decays
as gravity and friction oppose the flow. When `ine.port_in.mdot` drops below `threshold` the
Flapper opens (resistance drops from R_closed=1e8 to ~0), enabling reversed (downward) flow
driven by buoyancy. The system then transitions to natural circulation.

Initial conditions: set `ine.port_in.mdot` to the forced-flow steady-state value obtained
from a separate `build_loop_vertical` call with the same geometry and a matching `dP_pump`.
Use `Pair{Any,Any}` op vector and `initializealg=SciMLBase.NoInit()` via `solve_transient`.

# Arguments
- `n`: number of axial cells in ChannelHeatFlux (default 10)
- `L_ch`: channel length [m] (default 1.0)
- `D_ch`: channel hydraulic diameter [m] (default 0.01)
- `T_wall`: channel wall temperature [K] (default 373.15)
- `T_inlet`: inlet/HeatExchanger boundary temperature [K] (default 313.15)
- `L_over_A`: Inertia length-to-area ratio [1/m] (default 1.75e5); controls coastdown time constant
- `g_acc_ch`: gravitational acceleration in ChannelHeatFlux [m/s^2]; positive = upward flow, gravity opposes forced flow (default 9.80665)
- `threshold`: Flapper trigger threshold [kg/s]; should be ~10% of steady-state mdot (default 0.01)
- `dt_ramp`: Flapper opening ramp duration [s] (default 5.0)

# Returns
Compiled `ODESystem` (via `mtkcompile(sys; fully_determined=false)`).
"""
function build_loop_lof(;
    n::Int    = 10,
    L_ch      = 1.0,
    D_ch      = 0.01,
    T_wall    = 373.15,
    T_inlet   = 313.15,
    L_over_A  = 1.75e5,
    g_acc_ch  = 9.80665,
    threshold = 0.01,
    dt_ramp   = 5.0,
)
    @named pump    = Pump(0.0)
    @named ine     = Inertia(L_over_A=L_over_A)
    @named bc      = HeatExchanger(T_bc=T_inlet)
    @named ch      = ChannelHeatFlux(n=n, geometry=PipeGeometry_circular(L_ch, D_ch), g=g_acc_ch, T_wall=T_wall)
    @named flapper = Flapper(threshold=threshold, dt=dt_ramp)

    connections = [
        connect(pump.port_out, ine.port_in),
        connect(ine.port_out,  bc.port_in),
        connect(bc.port_out,   ch.port_in),
        connect(ch.port_out,   flapper.port_in),
        connect(flapper.port_out, pump.port_in),
        pump.port_in.P    ~ 1.0e5,
        ch.port_in.T      ~ T_inlet,
        flapper.ref_mdot  ~ ine.port_in.mdot,
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, ine, bc, ch, flapper)

    t_compile = @elapsed ssys = mtkcompile(sys; fully_determined=false)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_lof compile time: $(round(t_compile; digits=2))s" n_equations=n_eq n_unknowns=n_uk

    return ssys
end

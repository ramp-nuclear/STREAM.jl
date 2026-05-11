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
#   pump.port_in.P ~ 1.0e5                pressure gauge freedom fix (absolute anchor)
#   ch.T_wall_left[i]  ~ T_wall   ∀ i      left-face wall temperature pin
#   ch.T_wall_right[i] ~ T_inlet  ∀ i      right-face decoration (h_right=0 ⇒ q=0)
#
# Returns compiled ssys. Use ssys.ch.T[i], ssys.ch.port_in.mdot, etc.
# for symbolic indexing of results.
# ----------------------------------------------------------------
"""
    build_loop(; n=10, T_inlet=313.15, T_wall=373.15, h_wall=5000.0,
                 L_ch=0.6, D_ch=0.01, dP_pump=3.0e4) -> ODESystem

Build a simple steady-state horizontal flow loop (Pump + HeatExchanger + Channel).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall`: wall temperature [K] (default 373.15)
- `h_wall`: convective HTC [W/(m²K)] applied on the left face (default 5000.0)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)

# Returns
Compiled `ODESystem` (already passed through `mtkcompile`).
"""
#! format: off
function build_loop(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,   # coolant inlet temperature (K); 40°C
    T_wall   = 373.15,   # wall temperature (K); ~100°C for forced convection
    h_wall   = 5000.0,   # convective HTC [W/(m²K)] applied on the left face
)
#! format: on
    @named pump = Pump(dP_pump)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_ch, D_ch),
                          h_left=h_wall, h_right=0.0)
    @named bc = HeatExchanger(T_inlet)   # temperature reset at pump outlet

    connections = Equation[
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out, ch.port_in),        # TempBC -> channel
        connect(ch.port_out, pump.port_in),      # channel -> pump (closed loop)
        pump.port_in.P ~ 1.0e5,                  # pressure gauge freedom fix
        # Per-cell binding eqns (Phase 55 D-10 Style 1 — args.funcs idiom)
        [ch.T_wall_left[i]  ~ T_wall  for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, bc, ch)

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop compile time: $(round(t_compile; digits=2))s" n_equations = n_eq n_unknowns =
        n_uk

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
    build_loop_vertical(; n=10, T_inlet=313.15, T_wall=373.15, h_wall=5000.0,
                         L_ch=0.6, D_ch=0.01, dP_pump=3.0e4,
                         g_acc=9.80665, H_return=nothing) -> ODESystem

Build a vertical flow loop with gravity (Pump + HeatExchanger + Channel + Gravity).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall`: wall temperature [K] (default 373.15)
- `h_wall`: convective HTC [W/(m²K)] applied on the left face (default 5000.0)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `g_acc`: gravitational acceleration [m/s^2] (default 9.80665)
- `H_return`: height of return leg [m], defaults to `L_ch` for cancellation geometry

# Returns
Compiled `ODESystem`.
"""
#! format: off
function build_loop_vertical(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,    # coolant inlet temperature (K); 40°C
    T_wall   = 373.15,    # wall temperature (K); ~100°C for forced convection
    h_wall   = 5000.0,    # convective HTC [W/(m²K)] applied on the left face
    g_acc    = 9.80665,   # gravitational acceleration (m/s²)
    H_return = nothing,   # height of return leg (m); defaults to L_ch for cancellation geometry
)
#! format: on
    H = isnothing(H_return) ? L_ch : H_return

    @named pump = Pump(dP_pump)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_ch, D_ch),
                          g=g_acc, h_left=h_wall, h_right=0.0)
    @named bc = HeatExchanger(T_inlet)
    @named grav = Gravity(H)

    # Gravity wiring note:
    # Gravity equation: port_in.P - port_out.P ~ rho*g*H (port_in = high-P = bottom)
    # For the RETURN leg (fluid descends from channel top back to pump bottom):
    #   - channel outlet (top, low pressure) = grav.port_out (top)
    #   - pump inlet (bottom, higher pressure) = grav.port_in (bottom)
    # This gives: pump_inlet.P = channel_outlet.P + rho*g*H
    # Loop balance: dP_pump = friction + rho*g*L_ch - rho*g*H
    # Cancellation when H = L_ch: dP_pump = friction (gravity terms cancel).
    connections = Equation[
        connect(pump.port_out, bc.port_in),       # pump -> TempBC
        connect(bc.port_out, ch.port_in),        # TempBC -> channel (upward leg)
        connect(ch.port_out, grav.port_out),     # channel outlet (top) = grav port_out (top)
        connect(grav.port_in, pump.port_in),      # grav port_in (bottom) = pump inlet (bottom)
        pump.port_in.P ~ 1.0e5,                  # pressure gauge freedom fix
        # Per-cell binding eqns (Phase 55 D-10 Style 1 — args.funcs idiom)
        [ch.T_wall_left[i]  ~ T_wall  for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, bc, ch, grav)

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_vertical compile time: $(round(t_compile; digits=2))s" n_equations =
        n_eq n_unknowns = n_uk

    return ssys
end

"""
    build_loop_transient(; n=10, T_inlet=313.15, T_wall_0=373.15, h_wall=5000.0,
                          L_ch=0.6, D_ch=0.01, dP_pump=3.0e4,
                          T_wall_fn=nothing) -> ODESystem

Build a transient-capable flow loop. When `T_wall_fn` is provided (a callable `t -> K`),
wall temperature is time-varying via an MTK callable parameter at the builder level
(D-10 / Discretion #4 path b — preserves the v0.9 PK pattern; no `WallTemperature`
source component required). When `T_wall_fn` is `nothing`, wall temperature is pinned
to the scalar `T_wall_0`.

When using a callable `T_wall_fn`, the caller must include the callable parameter in `op`:
`ssys.T_wall_callable => T_wall_fn` (where `ssys` is the compiled system).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall_0`: wall temperature [K] (default 373.15); used when `T_wall_fn` is `nothing`
- `h_wall`: convective HTC [W/(m²K)] applied on the left face (default 5000.0)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `T_wall_fn`: optional callable `(t) -> K` for time-varying wall temperature

# Returns
Compiled `ODESystem` (already passed through `mtkcompile`).
"""
#! format: off
function build_loop_transient(;
    n::Int   = 10,
    L_ch     = 0.6,
    D_ch     = 0.01,
    A_ch     = 7.85e-5,
    dP_pump  = 3.0e4,
    T_inlet  = 313.15,    # coolant inlet temperature (K); 40°C
    T_wall_0 = 373.15,    # wall temperature (K); used when T_wall_fn is nothing
    h_wall   = 5000.0,    # convective HTC [W/(m²K)] applied on the left face
    T_wall_fn = nothing,  # optional callable (t) -> K for time-varying wall temperature
)
#! format: on
    @named pump = Pump(dP_pump)
    @named ch = Channel(; n=n, geometry=PipeGeometry_circular(L_ch, D_ch),
                          h_left=h_wall, h_right=0.0)
    @named bc = HeatExchanger(T_inlet)   # temperature reset at pump outlet

    if T_wall_fn === nothing
        # Scalar wall temperature — same as build_loop; no parameter declaration needed.
        # Per-cell Style 1 binding (D-05) replaces the legacy single-port wall pin.
        connections = Equation[
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, ch.port_in),
            connect(ch.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
            [ch.T_wall_left[i]  ~ T_wall_0 for i in 1:n]...,
            [ch.T_wall_right[i] ~ T_inlet  for i in 1:n]...,  # decorative; h_right=0
        ]
        @named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
    else
        # Callable wall temperature — uses MTK callable parameter at builder level
        # (D-10 / Discretion #4 path b — same `ps[1](t)` value broadcast per cell).
        # Caller must include ssys.T_wall_callable => T_wall_fn in op.
        FType = typeof(T_wall_fn)
        ps = @parameters (T_wall_callable::FType)(..)
        connections = Equation[
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, ch.port_in),
            connect(ch.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
            # Style 1 binding with builder-level callable: same `ps[1](t)` value broadcast per cell.
            [ch.T_wall_left[i]  ~ ps[1](t) for i in 1:n]...,
            [ch.T_wall_right[i] ~ T_inlet  for i in 1:n]...,  # decorative; h_right=0
        ]
        @named sys = compose(System(connections, t, [], ps; name=:sys), pump, bc, ch)
    end

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_transient compile time: $(round(t_compile; digits=2))s" n_equations =
        n_eq n_unknowns = n_uk

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
    @named r01 = Resistor(R)
    @named r02 = Resistor(R)
    @named r04 = Resistor(R)
    @named r13 = Resistor(R)
    @named r15 = Resistor(R)
    @named r23 = Resistor(R)
    @named r26 = Resistor(R)
    @named r37 = Resistor(R)
    @named r45 = Resistor(R)
    @named r46 = Resistor(R)
    @named r57 = Resistor(R)
    @named r67 = Resistor(R)

    connections = [
        # Corner 0 (source): pump.port_out + 3 resistor inlets
        connect(pump.port_out, r01.port_in, r02.port_in, r04.port_in),
        # Corner 1: r01 out + r13 in + r15 in
        connect(r01.port_out, r13.port_in, r15.port_in),
        # Corner 2: r02 out + r23 in + r26 in
        connect(r02.port_out, r23.port_in, r26.port_in),
        # Corner 3: r13 out + r23 out + r37 in
        connect(r13.port_out, r23.port_out, r37.port_in),
        # Corner 4: r04 out + r45 in + r46 in
        connect(r04.port_out, r45.port_in, r46.port_in),
        # Corner 5: r15 out + r45 out + r57 in
        connect(r15.port_out, r45.port_out, r57.port_in),
        # Corner 6: r26 out + r46 out + r67 in
        connect(r26.port_out, r46.port_out, r67.port_in),
        # Corner 7 (sink): pump.port_in + 3 resistor outlets
        connect(pump.port_in, r37.port_out, r57.port_out, r67.port_out),
        # Pressure gauge anchor (absolute level is underdetermined by Kirchhoff equations)
        pump.port_in.P ~ 1.0e5,
    ]

    @named sys = compose(
        System(connections, t; name=:sys),
        pump,
        r01,
        r02,
        r04,
        r13,
        r15,
        r23,
        r26,
        r37,
        r45,
        r46,
        r57,
        r67,
    )

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_cube compile time: $(round(t_compile; digits=2))s" n_equations = n_eq n_unknowns =
        n_uk

    return ssys
end

"""
    build_loop_lof_bypass(; n=10, L_ch=1.0, D_ch=0.01, T_inlet=313.15,
                            power_W=1.0e3, fuel_nx=2, fuel_Lx=0.005,
                            L_over_A=1.75e5, g_acc=9.80665,
                            R_ext=1.0e6, dt_ramp=5.0) -> ODESystem

Build a loss-of-flow validation loop with bypass topology. Heated leg uses
`ChannelAndContacts + HeatDiffusion` plate via `one_sided_connection` — Phase 55
Spike B topology (real fuel-plate physics), per Wave 0 spike outcome
(`spike_lof_winner: "B"`).

Topology (4-node parallel network):
- Node A (top): ine output, heated channel input, flapper input (3-way junction)
- Node B (bottom): heated channel output, ret input (2-way)
- Node C (top): ret output, flapper output, ext_res input (3-way junction)
- D series branch: ext_res -> hx -> pump -> ine

Heated leg: `ChannelAndContacts` (`heated.ch`) + `HeatDiffusion` plate
(`heated.fuel`) wired one-sided via `one_sided_connection(ch, fuel; side=:left)`.
Sub-systems retain their `@named` symbols, so access paths inside `heated` are
`heated.ch.*` and `heated.fuel.*` (not `heated.channel.*`). The right thermal
side of `ch` dangles inside the `heated` subsystem; per Spike #1 outcome
(HYPOTHESIS=A) the dangling per-cell `ThermalPort` Flow rule produces zero net
heat flow there, so no extra binding is needed — the right face is adiabatic.

Return leg: `ret` is the new external-input `Channel` (Phase 55 D-01). Default
`h_left=h_right=0.0` makes it adiabatic regardless of `T_wall_*[i]` values; the
per-cell `T_wall_left[i] / T_wall_right[i]` `~`-bindings to `T_inlet` are
decorative under H=A and required to keep MTK fully determined.

Gravity signs:
- heated channel (`heated.ch`, A->B, nominally downward): g = -g_acc
- ret (B->C, nominally upward): g = +g_acc

Physics: Pump coasts to 0 dP. Inertia carries momentum; ch flow decays. Flapper
opens when pump branch mdot (ine.port_in.mdot) drops below threshold (provided
externally via `flapper_callback`). After Flapper opens, flow redistributes:
heated-channel flow reverses (upward NC driven by buoyancy).

# Arguments
- `n`: number of axial cells (default 10)
- `L_ch`: channel length [m] (default 1.0)
- `D_ch`: channel hydraulic diameter [m] (default 0.01)
- `T_inlet`: inlet/HeatExchanger boundary temperature [K] (default 313.15)
- `power_W`: total fuel-plate heat input [W], pinned via `heated.fuel.power ~ power_W`
  (default 1.0e3, matching Spike B's NC-equilibrium-producing baseline)
- `fuel_nx`: lateral cells in the HeatDiffusion plate (default 2)
- `fuel_Lx`: plate lateral thickness [m] (default 0.005)
- `L_over_A`: Inertia length-to-area ratio [1/m] (default 1.75e5)
- `g_acc`: gravitational acceleration magnitude [m/s^2] (default 9.80665)
- `R_ext`: external hydraulic resistance [Pa·s/kg] (default 1.0e6)
- `dt_ramp`: Flapper opening ramp duration [s] (default 5.0)

# Returns
Compiled `ODESystem` (via `mtkcompile(sys)`).
"""
#! format: off
function build_loop_lof_bypass(;
    n::Int    = 10,
    L_ch      = 1.0,
    D_ch      = 0.01,
    T_inlet   = 313.15,
    power_W   = 1.0e3,
    fuel_nx   = 2,
    fuel_Lx   = 0.005,
    L_over_A  = 1.75e5,
    g_acc     = 9.80665,
    R_ext     = 1.0e6,
    dt_ramp   = 5.0,
)
#! format: on
    geom = PipeGeometry_circular(L_ch, D_ch)

    # NC-enabled regime switching for heated channel (D-10)
    rd_ch = regime_dependent(geom;
        htc_laminar=constant_Nusselt(; Nu=8.235),
        htc_turbulent=dittus_boelter,
        friction_laminar=laminar_friction(geom),
        friction_turbulent=blasius_friction,
        htc_natural=elenbaas_htc(geom; g=g_acc),
        g=g_acc,
    )

    @named pump    = Pump(0.0)
    @named ine     = Inertia(L_over_A)
    @named hx      = HeatExchanger(T_inlet)
    @named ch      = ChannelAndContacts(;
        n=n, geometry=geom, g=(-g_acc),
        htc_correlation=rd_ch.htc,
        friction_correlation=rd_ch.friction,
    )
    @named ret     = Channel(; n=n, geometry=geom, g=g_acc)
    # Flapper is a pure equation system — no internal SymbolicContinuousCallback.
    # Use flapper_callback(ssys, ssys.ine.port_in.mdot; threshold=...) to create an
    # external ContinuousCallback and pass it to solve_transient(...; callbacks=cb).
    @named flapper = Flapper(; dt=dt_ramp)
    @named ext_res = Resistor(R_ext)

    # HeatDiffusion plate — 5 mandatory kwargs (RESEARCH.md §6 Pitfalls).
    # power_shape sums to 1.0 so heated.fuel.power == total power into plate.
    ps = fill(1.0 / (n * fuel_nx), n, fuel_nx)
    @named fuel = HeatDiffusion(;
        nz=n, nx=fuel_nx, Lz=L_ch, Lx=fuel_Lx,
        y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0,
        power_shape=ps,
    )
    # one_sided_connection wires ch.thermal_left[i] <-> fuel.thermal_right[i] for i in 1:n.
    # Sub-systems retain their @named symbols inside `heated`: heated.ch and heated.fuel.
    heated = one_sided_connection(ch, fuel; side=:left, name=:heated)

    connections = Equation[
        # D series branch: ext_res -> hx -> pump -> ine
        connect(ext_res.port_out, hx.port_in),
        connect(hx.port_out, pump.port_in),
        connect(pump.port_out, ine.port_in),
        # Node A (3-way): ine output -> heated.ch input + flapper input
        connect(ine.port_out, heated.ch.port_in, flapper.port_in),
        # Node B (2-way): heated.ch output -> ret input
        connect(heated.ch.port_out, ret.port_in),
        # Node C (3-way): ret output + flapper output -> ext_res input
        connect(ret.port_out, flapper.port_out, ext_res.port_in),
        # Boundary conditions
        pump.port_in.P ~ 1.0e5,
        flapper.ref_mdot ~ ine.port_in.mdot,
        # Heated leg: pin total fuel-plate power. Spike B power_shape sums to 1, so
        # heated.fuel.power equals the total W into the plate.
        heated.fuel.power ~ power_W,
        # Return leg: ret uses the new external-input Channel (Phase 55 D-01).
        # h_left=h_right=0 (defaults) make the q-expression zero regardless of T_wall_*;
        # the per-cell T_wall_*[i] @variables still need binding eqns to keep MTK
        # fully determined. Decorative under H=A but kept for symmetry with the rest
        # of the migrated builders.
        [ret.T_wall_left[i]  ~ T_inlet for i in 1:n]...,
        [ret.T_wall_right[i] ~ T_inlet for i in 1:n]...,
    ]

    @named sys = compose_systems(
        heated, pump, ine, hx, ret, flapper, ext_res;
        connections=connections, name=:sys,
    )

    t_compile = @elapsed ssys = mtkcompile(sys)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_lof_bypass compile time: $(round(t_compile; digits=2))s" n_equations =
        n_eq n_unknowns = n_uk

    return ssys
end

"""
    build_loop_pk(ctrl; n=7, nz=7, nx=2, T_inlet=293.15, dP_pump=3.0e4,
                  P0=1.0, power_scale=1e4, temp_worth=nothing, ref_temp=nothing,
                  rho_val=0.0) -> (ODESystem, Vector{Pair{Any,Any}})

Build a full thermal-hydraulic loop coupled to a `PointKinetics` reactor model
(pump + HeatExchanger + ChannelAndContacts + HeatDiffusion + PointKinetics).
This is the primary integration-validation builder for Phase 49: it proves that
PK+T-H coupling compiles, solves stably, responds to reactivity insertion with
negative temperature feedback, and terminates correctly on SCRAM.

Unlike other `build_loop_*` builders which return only a compiled `ODESystem`,
`build_loop_pk` returns `(ssys, ic)` — the compiled system AND a ready-to-use
initial conditions `Pair{Any,Any}[]` vector suitable for passing directly to
`solve_transient`.

# Arguments
- `ctrl`: `ReactivityController` instance (or any callable `(t) -> Float64`)
  providing time-varying control reactivity. Determines the concrete `FType`
  captured in the MTK callable parameter at construction time.
- `n::Int`: number of axial cells in `ChannelAndContacts` (default 7)
- `nz::Int`: number of axial slices in `HeatDiffusion` (default 7)
- `nx::Int`: number of lateral slices in `HeatDiffusion` (default 2)
- `T_inlet`: coolant inlet temperature [K] (default 293.15)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `P0`: initial reactor power [dimensionless or W] passed to
  `point_kinetics_steady_state(P0)` for IC generation (default 1.0)
- `power_scale`: conversion factor from dimensionless PK power to physical
  heat deposition [W]; `fuel.power = pk.P * power_scale` (default 1e4)
- `temp_worth`: per-component temperature feedback weights, or `nothing` (default).
  Accepts `Dict{Symbol,Any}` with keys `:cac` and/or `:fuel`, mapping to scalar,
  1D vector (length `n` for `:cac`), or 2D matrix (shape `nz×nx` for `:fuel`)
  reactivity coefficients. Keys are internally resolved to scoped component
  references inside `symmetric_plate`. `nothing` = no temperature feedback.
- `ref_temp`: per-component reference temperatures [K]. Same key structure as
  `temp_worth`. `nothing` = use zero reference (full T contributes to feedback).
- `rho_val`: constant base reactivity bias [-] (default 0.0 = critical)

# Returns
`(ssys, ic)` where:
- `ssys`: compiled `ODESystem` (passed through `mtkcompile`)
- `ic`: `Vector{Pair{Any,Any}}` initial conditions including PK state
  (P, C_1..C_6, rho_c_fn), hydraulic IC (port_in.mdot), and thermal ICs
  (cac.T[i] and fuel.T[i,j]). Pass directly to `solve_transient(ssys, ic, t)`.
"""
#! format: off
function build_loop_pk(ctrl;
    n::Int      = 7,
    nz::Int     = 7,
    nx::Int     = 2,
    T_inlet     = 293.15,
    dP_pump     = 3.0e4,
    P0          = 1.0,
    power_scale = 1e4,
    temp_worth  = nothing,
    ref_temp    = nothing,
    rho_val     = 0.0,
)
#! format: on
    # Stage 1: Component construction
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    ps = fill(1.0 / (nz * nx), nz, nx)  # uniform power shape, normalized
    @named cac = ChannelAndContacts(;
        n=n,
        geometry=geom,
        htc_correlation=constant_Nusselt(; Nu=8.235),
        friction_correlation=laminar_friction(geom),
    )
    @named fuel = HeatDiffusion(;
        nz=nz,
        nx=nx,
        Lz=0.6,
        Lx=0.005,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    rods = symmetric_plate(cac, fuel; name=:rods)

    # Stage 2: Resolve Symbol keys to scoped component refs for temp_worth/ref_temp.
    # IMPORTANT: cache rods.cac and rods.fuel as local vars to guarantee the same
    # object reference is used as the Dict key in both tw and rt. MTK System
    # getproperty may create new objects on each call, causing Dict lookup failures
    # when iterating temp_worth and calling get(ref_temp, comp, default).
    rods_cac = rods.cac
    rods_fuel = rods.fuel

    function _resolve_tw(d, rods_cac, rods_fuel)
        isnothing(d) && return nothing
        resolved = Dict{Any,Any}()
        for (k, v) in d
            comp = if k == :cac
                rods_cac
            elseif k == :fuel
                rods_fuel
            else
                error("Unknown component key: $k (expected :cac or :fuel)")
            end
            resolved[comp] = v
        end
        return resolved
    end

    tw = _resolve_tw(temp_worth, rods_cac, rods_fuel)
    rt = _resolve_tw(ref_temp, rods_cac, rods_fuel)

    # Stage 3: PK construction with resolved (scoped) temp_worth / ref_temp
    @named pk = PointKinetics(ctrl; rho_val=rho_val, temp_worth=tw, ref_temp=rt)

    # Stage 4: Connections and compose
    # Only wire connect_temperature_feedback for components that have entries in tw.
    # The PK system only has T_source_<cname> unknowns for components listed in temp_worth.
    # Passing a component not in temp_worth would cause "variable T_source_<X> does not exist".
    # We match by component name (Symbol) rather than object identity since System equality
    # is not guaranteed to be stable across composition boundaries.
    fb_components = if isnothing(tw)
        System[]
    else
        tw_names = Set(nameof(k) for k in keys(tw))
        filter(c -> nameof(c) in tw_names, [rods_cac, rods_fuel])
    end
    fb_eqs = if isempty(fb_components)
        Equation[]
    else
        connect_temperature_feedback(pk, fb_components)
    end
    power_eqs = [rods_fuel.power ~ pk.P * power_scale]

    @named pump = Pump(dP_pump)
    @named bc = HeatExchanger(T_inlet)

    all_connections = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods_cac.port_in),
        connect(rods_cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        fb_eqs...,
        power_eqs...,
    ]

    full = compose_systems(rods, pk, pump, bc; connections=all_connections, name=:sys)

    # Stage 5: Compile
    t_compile = @elapsed ssys = mtkcompile(full)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @info "build_loop_pk compile time: $(round(t_compile; digits=2))s" n_equations = n_eq n_unknowns =
        n_uk

    # Stage 6: Build IC dict
    pk_ic = point_kinetics_steady_state(P0)
    ic = Pair{Any,Any}[
        ssys.pk.rho_c_fn => ctrl,
        ssys.pk.P => pk_ic.P,
        ssys.pk.C_1 => pk_ic.C_k[1],
        ssys.pk.C_2 => pk_ic.C_k[2],
        ssys.pk.C_3 => pk_ic.C_k[3],
        ssys.pk.C_4 => pk_ic.C_k[4],
        ssys.pk.C_5 => pk_ic.C_k[5],
        ssys.pk.C_6 => pk_ic.C_k[6],
        ssys.rods.cac.port_in.mdot => 0.2,
        [ssys.rods.cac.T[i] => T_inlet for i in 1:n]...,
        [ssys.rods.fuel.T[i, j] => T_inlet for i in 1:nz for j in 1:nx]...,
    ]
    return (ssys, ic)
end

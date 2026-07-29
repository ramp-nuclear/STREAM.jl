# examples.jl -- Example system builders
# build_loop, build_loop_vertical, build_loop_transient, build_cube

"""
    build_loop(; n=10, T_inlet=313.15, T_wall=373.15, h_wall=5000.0,
                 L_ch=0.6, D_ch=0.01, dP_pump=3.0e4) -> System

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
Compiled `System` (already passed through `mtkcompile`).
"""
function build_loop(;
    n::Int=10,
    L_ch=0.6,
    D_ch=0.01,
    dP_pump=3.0e4,
    T_inlet=313.15,  # coolant inlet temperature (K); 40°C
    T_wall=373.15,  # wall temperature (K); ~100°C for forced convection
    h_wall=5000.0,  # convective HTC [W/(m²K)] applied on the left face
)
    @named pump = Pump(dP_pump)
    geo = PipeGeometry_circular(L_ch, D_ch)
    @named ch = Channel(n=n, geometry=geo, h_left=h_wall, h_right=0.0)
    @named bc = HeatExchanger(T_inlet)   # temperature reset at pump outlet

    connections = Equation[
        inseries(pump, bc, ch, pump)...,
        pump.inlet.p ~ 1.0e5,                  # pressure gauge freedom fix
        # Per-cell binding eqns (args.funcs idiom)
        [ch.T_wall_left[i] ~ T_wall for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
    ssys = mtkcompile(sys)
    return ssys
end

"""
    build_loop_vertical(; n=10, T_inlet=313.15, T_wall=373.15, h_wall=5000.0,
                         L_ch=0.6, D_ch=0.01, dP_pump=3.0e4,
                         g_acc=G_EARTH, H_return=nothing) -> System

Build a vertical flow loop with gravity (Pump + HeatExchanger + Channel + Gravity).

# Arguments
- `n`: number of axial cells (default 10)
- `T_inlet`: inlet temperature [K] (default 313.15)
- `T_wall`: wall temperature [K] (default 373.15)
- `h_wall`: convective HTC [W/(m²K)] applied on the left face (default 5000.0)
- `L_ch`: channel length [m] (default 0.6)
- `D_ch`: channel diameter [m] (default 0.01)
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `g_acc`: gravitational acceleration [m/s^2] (default G_EARTH)
- `H_return`: height of return leg [m], defaults to `L_ch` for cancellation geometry

# Returns
Compiled `System`.
"""
function build_loop_vertical(;
    n::Int=10,
    L_ch=0.6,
    D_ch=0.01,
    dP_pump=3.0e4,
    T_inlet=313.15,  # coolant inlet temperature (K); 40°C
    T_wall=373.15,  # wall temperature (K); ~100°C for forced convection
    h_wall=5000.0,  # convective HTC [W/(m²K)] applied on the left face
    g_acc=G_EARTH,  # gravitational acceleration (m/s²)
    H_return=nothing,  # height of return leg (m); defaults to L_ch for cancellation geometry
)
    H = isnothing(H_return) ? L_ch : H_return

    @named pump = Pump(dP_pump)
    @named ch = Channel(;
        n=n, geometry=PipeGeometry_circular(L_ch, D_ch), g=g_acc, h_left=h_wall, h_right=0.0
    )
    @named bc = HeatExchanger(T_inlet)
    @named grav = Gravity(H)

    connections = Equation[
        inseries(pump, bc, ch, grav, pump)...,
        pump.inlet.p ~ 1.0e5,                  # pressure gauge freedom fix
        # Per-cell binding eqns (args.funcs idiom)
        [ch.T_wall_left[i] ~ T_wall for i in 1:n]...,
        [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
    ]

    @named sys = compose(System(connections, t; name=:sys), pump, bc, ch, grav)

    ssys = mtkcompile(sys)
    return ssys
end

"""
    build_loop_transient(; n=10, T_inlet=313.15, T_wall_0=373.15, h_wall=5000.0,
                          L_ch=0.6, D_ch=0.01, dP_pump=3.0e4,
                          T_wall_fn=nothing) -> System

Build a transient-capable flow loop. When `T_wall_fn` is provided (a callable `t -> K`),
wall temperature is time-varying via an MTK callable parameter at the builder level
(the callable stays wired at the builder level; no `WallTemperature`
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
Compiled `System` (already passed through `mtkcompile`).
"""
function build_loop_transient(;
    n::Int=10,
    L_ch=0.6,
    D_ch=0.01,
    dP_pump=3.0e4,
    T_inlet=313.15,  # coolant inlet temperature (K); 40°C
    T_wall_0=373.15,  # wall temperature (K); used when T_wall_fn is nothing
    h_wall=5000.0,  # convective HTC [W/(m²K)] applied on the left face
    T_wall_fn=nothing,  # optional callable (t) -> K for time-varying wall temperature
)
    @named pump = Pump(dP_pump)
    geo = PipeGeometry_circular(L_ch, D_ch)
    @named ch = Channel(n=n, geometry=geo, h_left=h_wall, h_right=0.0)
    @named bc = HeatExchanger(T_inlet)   # temperature reset at pump outlet

    if T_wall_fn === nothing
        # Scalar wall temperature — same as build_loop; no parameter declaration needed.
        # Per-cell binding replaces the legacy single-port wall pin.
        connections = Equation[
            inseries(pump, bc, ch, pump)...,
            pump.inlet.p ~ 1.0e5,
            [ch.T_wall_left[i] ~ T_wall_0 for i in 1:n]...,
            [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
        ]
        @named sys = compose(System(connections, t; name=:sys), pump, bc, ch)
    else
        # Callable wall temperature — uses MTK callable parameter at builder level
        # (same `ps[1](t)` value broadcast per cell).
        # Caller must include ssys.T_wall_callable => T_wall_fn in op.
        FType = typeof(T_wall_fn)
        ps = @parameters (T_wall_callable::FType)(..)
        connections = Equation[
            inseries(pump, bc, ch, pump)...,
            pump.inlet.p ~ 1.0e5,
            # Style 1 binding with builder-level callable: same `ps[1](t)` value broadcast per cell.
            [ch.T_wall_left[i] ~ ps[1](t) for i in 1:n]...,
            [ch.T_wall_right[i] ~ T_inlet for i in 1:n]...,  # decorative; h_right=0
        ]
        @named sys = compose(System(connections, t, [], ps; name=:sys), pump, bc, ch)
    end

    ssys = mtkcompile(sys)
    return ssys
end

"""
    build_cube(; dP_pump=3.0e4, R=1.0e4) -> System

Build a two-branch parallel network (cube topology) for network solver validation.

# Arguments
- `dP_pump`: pump pressure rise [Pa] (default 3.0e4)
- `R`: branch resistance [Pa/(kg/s)] (default 1.0e4)

# Returns
Compiled `System`.
"""
function build_cube(; dP_pump=3.0e4, R=1.0e4)
    @named pump = Pump(dP_pump)
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
        # Corner 0 (source): pump.outlet + 3 resistor inlets
        connect(pump.outlet, r01.inlet, r02.inlet, r04.inlet),
        # Corner 1: r01 out + r13 in + r15 in
        connect(r01.outlet, r13.inlet, r15.inlet),
        # Corner 2: r02 out + r23 in + r26 in
        connect(r02.outlet, r23.inlet, r26.inlet),
        # Corner 3: r13 out + r23 out + r37 in
        connect(r13.outlet, r23.outlet, r37.inlet),
        # Corner 4: r04 out + r45 in + r46 in
        connect(r04.outlet, r45.inlet, r46.inlet),
        # Corner 5: r15 out + r45 out + r57 in
        connect(r15.outlet, r45.outlet, r57.inlet),
        # Corner 6: r26 out + r46 out + r67 in
        connect(r26.outlet, r46.outlet, r67.inlet),
        # Corner 7 (sink): pump.inlet + 3 resistor outlets
        connect(pump.inlet, r37.outlet, r57.outlet, r67.outlet),
        # Pressure gauge anchor (absolute level is underdetermined by Kirchhoff equations)
        pump.inlet.p ~ 1.0e5,
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
    ssys = mtkcompile(sys)
    return ssys
end

"""
    build_loop_lof_bypass(; n=10, L_ch=1.0, D_ch=0.01, T_inlet=313.15,
                            power_W=1.0e3, fuel_nx=2, fuel_Lx=0.005,
                            L_over_A=1.75e5, g_acc=G_EARTH,
                            R_ext=1.0e6, dt_ramp=5.0) -> System

Build a loss-of-flow validation loop with bypass topology. Heated leg uses
`ChannelAndContacts + HeatDiffusion` plate via `one_sided_connection`
(real fuel-plate physics).

Topology (4-node parallel network):
- Node A (top): ine output, heated channel input, flapper input (3-way junction)
- Node B (bottom): heated channel output, ret input (2-way)
- Node C (top): ret output, flapper output, ext_res input (3-way junction)
- D series branch: ext_res -> hx -> pump -> ine

Heated leg: `ChannelAndContacts` (`heated.ch`) + `HeatDiffusion` plate
(`heated.fuel`) wired one-sided via `one_sided_connection(ch, fuel; side=:left)`.
Sub-systems retain their `@named` symbols, so access paths inside `heated` are
`heated.ch.*` and `heated.fuel.*` (not `heated.channel.*`). The right thermal
side of `ch` dangles inside the `heated` subsystem; the dangling per-cell
`ThermalPort` Flow rule produces zero net heat flow there, so no extra binding
is needed — the right face is adiabatic.

Return leg: `ret` is an external-input `Channel`. Default
`h_left=h_right=0.0` makes it adiabatic regardless of `T_wall_*[i]` values; the
per-cell `T_wall_left[i] / T_wall_right[i]` `~`-bindings to `T_inlet` are
decorative and required to keep MTK fully determined.

Gravity signs:
- heated channel (`heated.ch`, A->B, nominally downward): g = -g_acc
- ret (B->C, nominally upward): g = +g_acc

Physics: the pump head `dP_pump_fn(t)` trips toward 0 (loss of flow). Inertia
carries momentum; ch flow decays. Flapper opens when pump branch ṁ
(ine.inlet.ṁ) drops below threshold (provided externally via
`flapper_callback`). After Flapper opens, flow redistributes: heated-channel flow
reverses (upward NC driven by buoyancy).

Recommended IC idiom (canonical steady-then-transient): build with a `dP_pump_fn`
that trips at some `t_trip > 0`, `solve_steady` the system with the pump head held
at its pre-trip value (a constant-valued `dP_pump_fn`, passed via
`ssys.pump.dP_pump_fn => fn`) to obtain a consistent forced-flow IC, then
`solve_transient` from that steady state with the tripping `dP_pump_fn`. Because the
IC is a true steady state of this system and the head is continuous at `t=0`, the
transient starts fully consistent. See `_lof_bypass_ic` in `test/test_integration.jl`.

# Arguments
- `n`: number of axial cells (default 10)
- `L_ch`: channel length [m] (default 1.0)
- `D_ch`: channel hydraulic diameter [m] (default 0.01)
- `T_inlet`: inlet/HeatExchanger boundary temperature [K] (default 313.15)
- `power_W`: total fuel-plate heat input [W], pinned via `heated.fuel.power ~ power_W`
  (default 1.0e3, an NC-equilibrium-producing baseline)
- `fuel_nx`: lateral cells in the HeatDiffusion plate (default 2)
- `fuel_Lx`: plate lateral thickness [m] (default 0.005)
- `L_over_A`: Inertia length-to-area ratio [1/m] (default 1.75e5)
- `g_acc`: gravitational acceleration magnitude [m/s^2] (default G_EARTH)
- `R_ext`: external hydraulic resistance [Pa·s/kg] (default 1.0e6)
- `dt_ramp`: Flapper opening ramp duration [s] (default 5.0)
- `dP_pump_fn`: callable `f(t) -> Float64` giving the pump head [Pa] over time, stored
  as the MTK callable parameter `pump.dP_pump_fn` (pass `ssys.pump.dP_pump_fn => f` in
  the solve `op`). Default `t -> 0.0` (pump off — NC only). For a loss-of-flow run,
  supply a function that holds the pre-trip head then ramps to 0 (see the IC idiom above).

# Returns
Compiled `System` (via `mtkcompile(sys)`).
"""
function build_loop_lof_bypass(;
    n::Int=10,
    L_ch=1.0,
    D_ch=0.01,
    T_inlet=313.15,
    power_W=1.0e3,
    fuel_nx=2,
    fuel_Lx=0.005,
    L_over_A=1.75e5,
    g_acc=G_EARTH,
    R_ext=1.0e6,
    dt_ramp=5.0,
    dP_pump_fn=(_t -> 0.0),
)
    geom = PipeGeometry_circular(L_ch, D_ch)

    # NC-enabled regime switching for heated channel
    rd_ch = regime_dependent(geom;
        htc_laminar=constant_Nusselt(; Nu=8.235),
        htc_turbulent=dittus_boelter,
        friction_laminar=laminar_friction_rectangular(geom),
        friction_turbulent=blasius_friction,
        htc_natural=elenbaas_htc(geom; g=g_acc),
        g=g_acc,
    )

    @named pump = Pump(dP_pump_fn)
    @named ine = Inertia(L_over_A)
    @named hx = HeatExchanger(T_inlet)
    @named ch = ChannelAndContacts(;
        n=n,
        geometry=geom,
        g=(-g_acc),
        htc_correlation=rd_ch.htc,
        friction_correlation=rd_ch.friction,
    )
    @named ret = Channel(; n=n, geometry=geom, g=g_acc)
    # Open-state quadratic loss tuned (area, f) so the bypass conductance is comparable to the
    # legacy linear open resistance, keeping the loss-of-flow transient well-behaved.
    @named flapper = Flapper(; open_at_current=0.01, f=50.0, area=0.01, open_rate=1.0 / dt_ramp)
    @named ext_res = Resistor(R_ext)

    ps = fill(1.0 / (n * fuel_nx), n, fuel_nx)
    @named fuel = HeatDiffusion(;
        nz=n,
        nx=fuel_nx,
        Lz=L_ch,
        Lx=fuel_Lx,
        y=0.07,
        rho_s=19300.0,
        cp_s=116.0,
        k_s=174.0,
        power_shape=ps,
    )
    heated = one_sided_connection(ch, fuel; side=:left, name=:heated)

    connections = Equation[
        # D series branch: ext_res -> hx -> pump -> ine
        inseries(ext_res, hx, pump, ine)...,
        # Bypass split/merge: ine -> (heated.ch -> ret) in series, or flapper directly -> ext_res
        inparallel(ine, ((heated.ch, ret), flapper), ext_res)...,
        # Boundary conditions
        pump.inlet.p ~ 1.0e5,
        watch_flow(flapper, ine.inlet.ṁ),
        heated.fuel.power ~ power_W,
        [ret.T_wall_left[i] ~ T_inlet for i in 1:n]...,
        [ret.T_wall_right[i] ~ T_inlet for i in 1:n]...,
        # Close the dangling right face of the one-sided CAC (fuel is on the left).
        # The current MTK does not auto-zero an unconnected ThermalPort's flow, so
        # bind each right wall T to the local bulk T ⇒ q_right = h*(T-T) = 0 (adiabatic).
        # Supplies the n equations that keep the heated subsystem fully determined.
        [port(heated.ch, :thermal_right, i).T ~ heated.ch.T[i] for i in 1:n]...,
    ]

    @named sys = compose_systems(
        heated, pump, ine, hx, ret, flapper, ext_res; connections=connections, name=:sys
    )

    ssys = mtkcompile(sys)
    return ssys
end

# Resolve a temp_worth / ref_temp Dict keyed by :cac/:fuel into one keyed by the
# scoped component systems that PointKinetics expects.
function _resolve_tw(d, rods_cac, rods_fuel)
    isnothing(d) && return nothing
    resolved = Dict{Any,Any}()
    for (k, v) in d
        comp = if k == :cac
            rods_cac
        elseif k == :fuel
            rods_fuel
        else
            throw(ArgumentError("unknown component key $k; expected :cac or :fuel"))
        end
        resolved[comp] = v
    end
    return resolved
end

"""
    build_loop_pk(ctrl; n=7, nz=7, nx=2, T_inlet=293.15, dP_pump=3.0e4,
                  P0=1.0, power_scale=1e4, temp_worth=nothing, ref_temp=nothing,
                  rho_val=0.0) -> (System, Vector{Pair{Any,Any}})

Build a full thermal-hydraulic loop coupled to a `PointKinetics` reactor model
(pump + HeatExchanger + ChannelAndContacts + HeatDiffusion + PointKinetics).
This is the primary integration-validation builder: it proves that
PK+T-H coupling compiles, solves stably, responds to reactivity insertion with
negative temperature feedback, and terminates correctly on SCRAM.

Unlike other `build_loop_*` builders which return only a compiled `System`,
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
- `ssys`: compiled `System` (passed through `mtkcompile`)
- `ic`: `Vector{Pair{Any,Any}}` initial conditions including PK state
  (P, C_1..C_6, rho_c_fn), hydraulic IC (inlet.ṁ), and thermal ICs
  (cac.T[i] and fuel.T[i,j]). Pass directly to `solve_transient(ssys, ic, t)`.
"""
function build_loop_pk(ctrl;
    n::Int=7,
    nz::Int=7,
    nx::Int=2,
    T_inlet=293.15,
    dP_pump=3.0e4,
    P0=1.0,
    power_scale=1e4,
    temp_worth=nothing,
    ref_temp=nothing,
    rho_val=0.0,
)
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    ps = fill(1.0 / (nz * nx), nz, nx)  # uniform power shape, normalized
    @named cac = ChannelAndContacts(;
        n=n,
        geometry=geom,
        htc_correlation=constant_Nusselt(; Nu=8.235),
        friction_correlation=laminar_friction_rectangular(geom),
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
    rods_cac = rods.cac
    rods_fuel = rods.fuel

    tw = _resolve_tw(temp_worth, rods_cac, rods_fuel)
    rt = _resolve_tw(ref_temp, rods_cac, rods_fuel)

    @named pk = PointKinetics(ctrl; rho_val=rho_val, temp_worth=tw, ref_temp=rt)

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
        inseries(pump, bc, rods_cac, pump)...,
        pump.inlet.p ~ 1.0e5,
        fb_eqs...,
        power_eqs...,
    ]

    full = compose_systems(rods, pk, pump, bc; connections=all_connections, name=:sys)
    ssys = mtkcompile(full)

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
        ssys.rods.cac.inlet.ṁ => 0.2,
        [ssys.rods.cac.T[i] => T_inlet for i in 1:n]...,
        [ssys.rods.fuel.T[i, j] => T_inlet for i in 1:nz for j in 1:nx]...,
    ]
    # Consistent-IC seeding
    # FlowPort/ThermalPort temperatures default to 300 K (src/connectors.jl). The boundary coolant
    # cells and the channel↔fuel contact nodes are aliased to those port temperatures, and the
    # per-cell `cac.T[i]`/`fuel.T[i,j]` seeds above do NOT pin the port representatives under NoInit.
    # Left unseeded, a temperature-feedback PK loop with ref_temp≠300 sees a spurious (300 − ref_temp)
    # reactivity offset at t=0 that crashes power — a pure initialization artifact, not physics.
    #
    # Each connected port pair (hx↔cac, cac↔pump, pump↔hx, and each cac↔fuel contact) collapses to one
    # alias-elimination representative, and WHICH member survives is not stable across MTK versions /
    # runs (it differed between local and CI). So seed EVERY member of every connection set to T_inlet:
    # whichever representative survives is then always hit, and the duplicate members are harmless
    # (distinct symbolic keys, same value). The cold IC is then genuinely consistent — reactivity[0] = 0
    # when ref_temp = T_inlet, independent of the alias-elimination choice.
    push!(ic, ssys.rods.cac.inlet.T => T_inlet)
    push!(ic, ssys.rods.cac.outlet.T => T_inlet)
    push!(ic, ssys.pump.inlet.T => T_inlet)
    push!(ic, ssys.pump.outlet.T => T_inlet)
    push!(ic, ssys.bc.inlet.T => T_inlet)
    push!(ic, ssys.bc.outlet.T => T_inlet)
    for i in 1:n
        push!(ic, getproperty(ssys.rods.cac, Symbol(:thermal_left, i)).T => T_inlet)
        push!(ic, getproperty(ssys.rods.cac, Symbol(:thermal_right, i)).T => T_inlet)
    end
    for i in 1:nz
        push!(ic, getproperty(ssys.rods.fuel, Symbol(:thermal_left, i)).T => T_inlet)
        push!(ic, getproperty(ssys.rods.fuel, Symbol(:thermal_right, i)).T => T_inlet)
    end
    return (ssys, ic)
end

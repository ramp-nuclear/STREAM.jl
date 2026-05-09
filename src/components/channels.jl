# channels.jl — Channel, ChannelHeatFlux, ChannelAndContacts variants
# and shared `_channel_core` for STREAM.jl.
#
# Phase 54 (v1.1) consolidated channel-family file. Holds:
#   - the `function Channel end` Base-disambiguation declaration
#     (Base.Channel{T} is Julia stdlib's task-communication channel; STREAM.Channel
#     is unrelated). Without this declaration, `function Channel(; name, n, ...)` below
#     would attempt to add a method to `Base.Channel`, which fails at module load.
#   - the private helper `_channel_core` (single source of truth for the channel
#     family's energy balance / friction / momentum / port wiring / observables;
#     introduced in Phase 53).
#   - the three public variants `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts`.
#     CHF and CAC are added in plans 54-02 / 54-03; this file ships only
#     `Channel` for now (Phase 54-01).
#
# `_channel_core` is private (underscore-prefixed; not exported in src/STREAM.jl).

# Declare Channel as a new generic function independent of Base.Channel{T}
# (Base.Channel is Julia stdlib's task-communication channel; STREAM.Channel is unrelated)
function Channel end

# === Phase 53: shared `_channel_core` =====================================
#
# `_channel_core` is the single source of truth for the STREAM channel-family
# physics: energy balance (enthalpy form, face-averaged cp), per-cell friction
# (algebraic dp[i]), mass conservation, momentum ODE, port wiring, and observables
# (Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP).
#
# Phase 54 will migrate Channel, ChannelAndContacts, and ChannelHeatFlux onto
# `_channel_core`; until then those variants carry inlined per-variant equation
# blocks (constant-cp form) instead of calling a shared helper.
#
# Returns a NamedTuple `(; eqs, obs)` (D-01) — variants splice
# `eqs = [variant_eqs; core.eqs]` and `obs = [core.obs; variant_obs]` before
# building the System. Variants declare ALL `@variables` (unknowns AND
# observables core references); core builds equations referencing those symbols.

"""
    _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
                  friction_correlation=blasius_friction,
                  q_left_expr, q_right_expr,
                  Re, Pe, v, P, T_sat, T_ONB,
                  q_wall, q_wall_left, q_wall_right,
                  T_out, dP)::NamedTuple

Shared private helper for STREAM channel-family components. Single source of truth
for energy balance (enthalpy form with face-averaged cp), mass conservation,
momentum ODE `(L/A)*Dt(mdot)`, per-cell friction (algebraic dp[i]), port wiring,
and observables.

Returns `(; eqs, obs)` — variant splices `eqs = [variant_specific_eqs; core.eqs]`,
`obs = [core.obs; variant_specific_obs]`. Variant declares all `@variables`
(unknowns AND observables that core references); core builds equations referencing
those symbols.

# Arguments
- `n::Int`                                          : number of axial cells
- `T`, `dp`                                         : variant-declared `@variables (T(t))[1:n]`, `(dp(t))[1:n]`
- `port_in`, `port_out`                             : variant-created `FlowPort`s
- `geometry::PipeGeometry`                          : pipe geometry descriptor
- `g_acc::Real`                                     : gravitational acceleration [m/s^2]
- `friction_correlation`                            : friction closure `(Re) -> f`
- `q_left_expr`, `q_right_expr`                     : length-n `Vector{Num}`, per-cell heat flow inputs (W) — variant builds these
- `Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right` : variant-declared observable LHS symbols (D-10)
- `T_out, dP`                                       : variant-declared scalar observable LHS symbols

# Returns
NamedTuple `(; eqs::Vector{Equation}, obs::Vector{Equation})` — the variant
splices these into its own equation lists before building the `System`.

# Energy balance per cell (enthalpy form, face-averaged cp; D-06)

    cp_face = (cp_water(T_up) + cp_water(T[i])) / 2
    Dt(T[i]) ~ (|mdot|*cp_face*(T_up - T[i]) + q_left_expr[i] + q_right_expr[i])
              / (rho_water(T[i]) * cp_water(T[i]) * A * dz)

Numerator uses face-averaged cp (NRG-01); boundary face of cell 1 forward and
cell n reverse uses the SAME averaging with `T_up = instream(port_in.T)` /
`instream(port_out.T)` (NRG-02). Denominator retains local `cp_water(T[i])` —
the two cp values do NOT cancel (NRG-03). Single `ifelse(mdot >= 0, ...)`
selects upstream T; cp inherits the selection because `cp_water` is
`@register_symbolic` and deterministic (NRG-04).
"""
function _channel_core(;
    n::Int,
    T,
    dp,
    port_in,
    port_out,
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr,
    q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB,
    q_wall, q_wall_left, q_wall_right,
    T_out, dP,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    dz = L / n
    Dt = Differential(t)

    eqs = Equation[]
    obs = Equation[]

    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    for i in 1:n
        # Flow-reversal upwind selection — single ifelse (D-07, NRG-04).
        # The (i == 1)/(i == n) ternaries collapse at trace time (Julia ?:),
        # so cell 1 forward / cell n reverse correctly use the boundary face.
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)

        # Face-averaged cp — boundary face uses same averaging as interior (D-05).
        # Both branches of T_up run through cp_water; @register_symbolic ensures
        # cp_water is opaque to Symbolics and faithfully transports the ifelse
        # selection at runtime (D-07, NRG-04). NO second ifelse for cp.
        cp_face = (cp_water(T_up) + cp_water(T[i])) / 2     # NRG-01, NRG-02

        # Energy balance — enthalpy form (D-06).
        # Numerator: cp_face (face-averaged); denominator: cp_water(T[i]) (local).
        # The two cp values do NOT cancel (NRG-03) — they coincide only in the
        # constant-cp limit (T_up == T[i]).
        push!(eqs,
            Dt(T[i]) ~ (
                abs(port_in.mdot) * cp_face * (T_up - T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
        )

        # Per-cell friction dp[i] — algebraic (Pitfall 5: inline Re for friction
        # because Re[i] is observed, not unknown, in the new core).
        Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        f_i = friction_correlation(Re_i_for_friction)
        push!(eqs,
            dp[i] ~ f_i * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) * (dz / Dh)
                  + rho_water(T[i]) * g_acc * dz
        )

        # q-agnostic observables (D-08).
        Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(obs, Re[i] ~ Re_i_for_friction)         # reuse the inlined Re_i (NOT Re[i] symbol)
        push!(obs, Pe[i] ~ Re_i_for_friction * Pr_i)  # Re*Pr (Peclet)
        push!(obs, v[i]  ~ port_in.mdot / (rho_water(T[i]) * A))  # canonical form (CAC line 202)

        # Per-cell absolute pressure (distributed inertia correction; CAC pattern).
        # P_i is a Julia local expression (NOT the P[i] symbol) to avoid an
        # observed-to-observed chain when used inside T_sat[i] / T_ONB[i] (Pitfall 7).
        P_i = port_in.P - sum(dp[j] for j in 1:i) -
              (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
        push!(obs, P[i]    ~ P_i)
        push!(obs, T_sat[i] ~ sat_temperature(P_i))

        # q-derived observables (D-08).
        # T_ONB[i] inlines q-density from q_left_expr/q_right_expr (Julia locals)
        # rather than referencing the q_wall[i] observable symbol — avoids
        # observed-to-observed chain (Pitfall 7).
        q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
        push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i))

        push!(obs, q_wall_left[i]  ~ q_left_expr[i])
        push!(obs, q_wall_right[i] ~ q_right_expr[i])
        push!(obs, q_wall[i]       ~ q_left_expr[i] + q_right_expr[i])
    end

    # Scalar equations — port wiring (identical across all variants; PATTERNS.md lines 104-115)
    push!(eqs, T_out ~ T[n])
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n))
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ T[1])
    push!(obs, dP ~ port_in.P - port_out.P)

    return (; eqs, obs)
end

# === Phase 55 D-01 / D-02: external-input-variable Channel ================
#
# Phase 55 walks back the per-cell ThermalPort arrays Phase 54 shipped:
# the new Channel has NO `thermal_left[1:n]` / `thermal_right[1:n]` ports.
# In their place, channel-level external-input variables `T_wall_left[1:n]`
# and `T_wall_right[1:n]` are declared on the System with no internal
# equation. The user closes them either by direct binding eqns at compose
# time (`[ch.T_wall_left[i] ~ value for i in 1:n]...`, args.funcs idiom — D-05
# Style 1) or by wiring a `WallTemperature` source component
# (D-04 / src/components/sources.jl, D-05 Style 2).
#
# Why drop the ports: the Phase 54 design emitted `port.Q_flow ~ q_left_expr[i]`
# per cell; combined with MTK's Flow rule that auto-zeros Q_flow on dangling
# ports, this over-determined the system whenever a user added a binding
# eq on port.T (Phase 54 Deviation 1). The architectural rule
# (`feedback_channel_hd_connection_rule.md`) — only ChannelAndContacts
# connects to HeatDiffusion — means Channel and ChannelHeatFlux never
# needed Flow-based ports. Removing them eliminates the over-determination
# root cause; the q-expression construction proceeds against the plain
# T_wall_left[i] @variables instead.
#
# Adiabatic by default: `h_left=h_right=0.0` (default) makes both
# `q_*_expr[i]` zero regardless of T_wall_*[i], so the energy balance does
# not heat the fluid. Whether T_wall_*[i] is a free unknown after
# `mtkcompile(...; fully_determined=false)` (Hypothesis A) or is collapsed
# by structural simplification (Hypothesis A_PARTIAL) is recorded in
# 55-WAVE0-SPIKE-RESULTS.md and reflected in test_channels.jl assertions.

"""
    Channel(; name, n, geometry, g=0.0, h_left=0.0, h_right=0.0,
            friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells. External-input
recipient: per-cell wall temperature arrives via channel-level `@variables`
`T_wall_left(t)[1:n]` / `T_wall_right(t)[1:n]` (no port — these are plain
unknowns the user closes via binding eqns or a `WallTemperature` source).
`h_left` / `h_right` are constructor kwargs (each `Real | AbstractVector |
Function`, default `0.0`). Adiabatic when `h_*=0.0` (default).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `h_left`, `h_right`: per-side convective HTC [W/(m^2·K)]; `Real` (broadcast to all n cells),
  `AbstractVector{<:Real}` of length n (per-cell static profile), or `Function` (time-varying via
  MTK callable parameter pattern; user must pass `ch.h_left_fn => fn` in solve `op` dict);
  default `0.0` per-side ⇒ adiabatic.
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# External-input variables (Phase 55 D-01)
- `T_wall_left(t)[1:n]`: per-cell left-face wall temperature [K]
- `T_wall_right(t)[1:n]`: per-cell right-face wall temperature [K]

These have no internal equation. Close them via either of:
```julia
# Style 1 — direct binding eqns at compose time (args.funcs idiom; D-05):
connections = [
    ...,
    [ch.T_wall_left[i] ~ T_wall_value for i in 1:n]...,
]

# Style 2 — value-source component:
@named wt = WallTemperature(; n=n, T_wall=T_wall_value)
connections = [
    ...,
    [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...,
]
```

# Ports
- `port_in`, `port_out` -- `FlowPort` (mass + momentum + stream T)
  *No thermal ports — see external-input variables above.*

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Channel(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
    friction_correlation=blasius_friction,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    # ----------------------------------------------------------------
    # Base parameters: geometry + gravity. h_left/h_right resolution is
    # unchanged from Phase 54 D-02 — only the q-expression *consumer*
    # changed (T_wall_left[i] @variable in place of thermal_left[i].T port var).
    # ----------------------------------------------------------------
    pars_base = @parameters begin
        L = L
        D_h = Dh
        A = A
        g_acc = g
    end

    extra_pars = Any[]
    if h_left isa Real
        hL_per_cell = fill(Num(h_left), n)
    elseif h_left isa AbstractVector
        length(h_left) == n ||
            error("Channel: h_left vector length $(length(h_left)) ≠ n=$n")
        hL_per_cell = Num.(h_left)
    else  # Function / callable — MTK callable-parameter pattern (RESEARCH.md §1)
        FType_L = typeof(h_left)
        pL = @parameters (h_left_fn::FType_L)(..)
        hL_call = pL[1](t)
        hL_per_cell = fill(hL_call, n)
        append!(extra_pars, pL)
    end

    if h_right isa Real
        hR_per_cell = fill(Num(h_right), n)
    elseif h_right isa AbstractVector
        length(h_right) == n ||
            error("Channel: h_right vector length $(length(h_right)) ≠ n=$n")
        hR_per_cell = Num.(h_right)
    else  # Function / callable
        FType_R = typeof(h_right)
        pR = @parameters (h_right_fn::FType_R)(..)
        hR_call = pR[1](t)
        hR_per_cell = fill(hR_call, n)
        append!(extra_pars, pR)
    end

    pars = Any[pars_base...; extra_pars...]

    # ----------------------------------------------------------------
    # Variables — variant declares ALL @variables that _channel_core references
    # by symbol (Phase 53 D-10). T, dp are unknowns; the rest are observable LHS.
    # NEW IN PHASE 55 (D-01): T_wall_left[1:n] and T_wall_right[1:n] are plain
    # external-input variables — no equation, no default, user closes them.
    # ----------------------------------------------------------------
    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (dp(t))[1:n] = fill(100.0, n)
        (T_wall_left(t))[1:n]
        (T_wall_right(t))[1:n]
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz = L / n

    # ----------------------------------------------------------------
    # D-02 q-expression construction (per cell) — NO PORT-Q_FLOW EQUATION.
    # The q expression now reads T_wall_left[i] / T_wall_right[i] directly
    # (the channel-level @variable), not thermal_*[i].T (the deleted port var).
    # No `port.Q_flow ~ q_*_expr` closure — there is no port to close.
    #
    # Adiabatic-by-default: h_left=h_right=0.0 ⇒ q_*_expr[i] = 0 ⇒ T[i] is
    # not heated regardless of what T_wall_*[i] is set to (or whether it's
    # bound at all).
    # ----------------------------------------------------------------
    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = hL_per_cell[i] * geometry.heated_parts[1] * dz * (T_wall_left[i]  - T[i])
        q_right_expr[i] = hR_per_cell[i] * geometry.heated_parts[2] * dz * (T_wall_right[i] - T[i])
    end

    # ----------------------------------------------------------------
    # Hand off to _channel_core (Phase 53 D-01 / D-03 — UNCHANGED).
    # ----------------------------------------------------------------
    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q_flow closure
    obs = core.obs

    all_vars = [
        collect(T); collect(dp);
        collect(T_wall_left); collect(T_wall_right);
        collect(Re); collect(Pe); collect(v);
        collect(P); collect(T_sat); collect(T_ONB);
        collect(q_wall); collect(q_wall_left); collect(q_wall_right);
        T_out; dP
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end

# === Phase 55 D-03: external-input-variable ChannelHeatFlux ================
#
# Phase 55 walks back the per-cell heat-flux ports Phase 54 shipped:
# the new ChannelHeatFlux has NO `thermal_left[1:n]` / `thermal_right[1:n]`
# ports. In their place, channel-level external-input variables `q_left[1:n]`
# and `q_right[1:n]` (heat flux density [W/m^2]) are declared on the System
# with no internal equation. The user closes them either by direct binding
# eqns at compose time (`[chf.q_left[i] ~ value for i in 1:n]...`, args.funcs
# idiom — D-05 Style 1) or by wiring a `HeatFluxSource` value-source
# component (D-04 / src/components/sources.jl, D-05 Style 2).
#
# The Phase 52 heat-flux connector type was retired in Phase 55 D-06 — see
# plan 55-04 for the connectors.jl + STREAM.jl exports + test_connectors.jl edits.
#
# Zero-flux by default: unbound `q_left[i] / q_right[i]` (or set to 0.0)
# makes `q_*_expr[i] = 0` regardless of T[i]. Whether the unbound case
# survives `mtkcompile(...; fully_determined=false)` follows the same
# Hypothesis A / A_PARTIAL / B answer Spike #1 produced for Channel's
# T_wall_*[i] vars.

"""
    ChannelHeatFlux(; name, n, geometry, g=0.0,
                    friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with `n` axial finite-volume cells. External-input
recipient of prescribed heat flux: per-cell flux density [W/m^2] arrives via
channel-level `@variables` `q_left(t)[1:n]` / `q_right(t)[1:n]` (no port — these
are plain unknowns the user closes via binding eqns or a `HeatFluxSource` source).

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (`PipeGeometry`)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

# External-input variables (Phase 55 D-03)
- `q_left(t)[1:n]`: per-cell left-face heat flux density [W/m^2]
- `q_right(t)[1:n]`: per-cell right-face heat flux density [W/m^2]

These have no internal equation. Close them via either of:
```julia
# Style 1 — direct binding eqns at compose time:
connections = [
    ...,
    [chf.q_left[i] ~ q_value for i in 1:n]...,
]

# Style 2 — value-source component:
@named hfs = HeatFluxSource(; n=n, q=q_value)
connections = [
    ...,
    [chf.q_left[i] ~ hfs.q_out[i] for i in 1:n]...,
]
```

# Ports
- `port_in`, `port_out` -- `FlowPort` (mass + momentum + stream T)
  *No heat-flux ports — see external-input variables above.*

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ChannelHeatFlux(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    friction_correlation=blasius_friction,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    pars = @parameters begin
        L = L
        D_h = Dh
        A = A
        g_acc = g
    end

    # NEW IN PHASE 55 (D-03): q_left[1:n] and q_right[1:n] are plain external-input
    # variables — no equation, no default, user closes them.
    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (dp(t))[1:n] = fill(100.0, n)
        (q_left(t))[1:n]
        (q_right(t))[1:n]
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    dz = L / n

    # ----------------------------------------------------------------
    # D-03 q-expression construction (per cell) — NO PORT-Q_FLOW EQUATION.
    # q expression reads q_left[i] / q_right[i] directly (channel-level @variable
    # of physical units W/m^2). No `port.Q_flow ~ q_left_expr` closure — there
    # is no port to close. Zero-flux when q_*[i] is bound to 0 (or default-unbound).
    # ----------------------------------------------------------------
    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        q_left_expr[i]  = q_left[i]  * geometry.heated_parts[1] * dz
        q_right_expr[i] = q_right[i] * geometry.heated_parts[2] * dz
    end

    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    eqs = core.eqs        # NO variant_eqs — there is no port-Q_flow closure
    obs = core.obs

    all_vars = [
        collect(T); collect(dp);
        collect(q_left); collect(q_right);
        collect(Re); collect(Pe); collect(v);
        collect(P); collect(T_sat); collect(T_ONB);
        collect(q_wall); collect(q_wall_left); collect(q_wall_right);
        T_out; dP
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out,
    )
end

# === Phase 54 D-08 / D-09: ChannelAndContacts (carry-forward, ThermalPort) ==
#
# ChannelAndContacts retains the legacy CONN-03 connector shape: per-cell
# `ThermalPort` arrays per side. CAC is the ONLY variant that connects to
# `HeatDiffusion` (locked architectural rule, see
# `feedback_channel_hd_connection_rule.md`). h is computed INTERNALLY via the
# `htc_correlation` kwarg (single-phase path) plus an optional `scb_correction`
# closure that augments h_tc[i] by the Bergles-Rohsenow partial-boiling factor
# when T_wall[i] >= T_ONB[i]. Both branches migrate verbatim from the legacy
# CAC body in `thermal_channel.jl` (lines 105-165 of the pre-Phase-54-03 file).
# Surrounding scaffolding (energy balance, friction, port wiring, observables)
# is delegated to `_channel_core` per Phase 53 D-01..D-14.

"""
    ChannelAndContacts(; name, n, geometry, g=0.0,
                       htc_correlation=dittus_boelter,
                       friction_correlation=blasius_friction,
                       scb_correction=nothing) -> ODESystem

Convective channel with per-cell `ThermalPort` arrays on both sides for conjugate heat
transfer (the variant that connects to `HeatDiffusion`). Internal HTC correlation
(single-phase or correlation+SCB-enhanced) drives per-cell `h_tc[i]`; q is computed
inside the variant as `h_tc[i] * heated_parts * dz * (T_wall - T[i])` and fed into
`_channel_core` for the energy balance and the rest of the channel physics.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells (Int)
- `geometry`: pipe geometry descriptor (PipeGeometry)
- `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
- `htc_correlation`: HTC function `(Re, Pr, T_bulk, T_wall) -> Nu`, default `dittus_boelter`
- `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`
- `scb_correction`: optional SCB heat flux closure `(T_wall, T_sat, Re) -> q_scb [W/m^2]`,
  e.g. from `regime_dependent_q_scb(pressure=...)`. When provided, `h_tc[i]` is enhanced
  by the Bergles-Rohsenow partial boiling factor when `T_wall[i] >= T_ONB[i]`.
  Default `nothing` (pure single-phase).

# Ports
- `port_in`, `port_out` -- `FlowPort`
- `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell, per side)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function ChannelAndContacts(;
    name,
    n::Int,
    geometry::PipeGeometry,
    g=0.0,
    htc_correlation=dittus_boelter,
    friction_correlation=blasius_friction,
    scb_correction=nothing,
)
    Dh = geometry.Dh
    A  = geometry.A
    L  = geometry.L
    Dt = Differential(t)

    pars = @parameters begin
        L = L
        D_h = Dh
        A = A
        g_acc = g
    end

    # ----------------------------------------------------------------
    # Variables — variant declares ALL @variables that _channel_core references
    # by symbol (Phase 53 D-10), PLUS variant-specific observables (Phase 53 D-09):
    # h_tc[i] (UNKNOWN — needed for SCB convergence per ISCB-01), Nu, h_tc_left/right,
    # T_wall_left/right, Gr_over_Re2, velocity, Q_wall_total.
    # h_tc default IC 5000.0 (ISCB-01: prevents MTK cyclic guesses init error in SCB).
    # ----------------------------------------------------------------
    vars = @variables begin
        (T(t))[1:n] = fill(600.0, n)
        (dp(t))[1:n] = fill(100.0, n)
        (h_tc(t))[1:n] = fill(5000.0, n)
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        (Nu(t))[1:n]
        (h_tc_left(t))[1:n] = fill(5000.0, n)   # Phase 56-resume per-side h: break MTK cyclic-guess (mirrors h_tc default)
        (h_tc_right(t))[1:n] = fill(5000.0, n)  # Phase 56-resume per-side h: same
        (T_wall_left(t))[1:n]
        (T_wall_right(t))[1:n]
        (Gr_over_Re2(t))[1:n]
        (velocity(t))[1:n]
        T_out(t) = 600.0
        dP(t)
        Q_wall_total(t)
    end

    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    thermal_left  = [ThermalPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
    thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]

    dz = L / n

    # ----------------------------------------------------------------
    # h_tc[i] equation — single-phase OR correlation + SCB.
    # MIGRATED VERBATIM from legacy CAC (thermal_channel.jl lines 111-117 single-phase
    # branch and 141-164 SCB branch). Only the surrounding scaffolding changes.
    # All expressions are inlined (no observed-to-observed chains; ISCB-01 + Pitfall 7).
    # ----------------------------------------------------------------
    variant_eqs = Equation[]
    # ----------------------------------------------------------------
    # Phase 57 D-01/D-02/D-03: HTC fluid-property eval point.
    # ----------------------------------------------------------------
    # The HTC pipeline (Re, Pr, leading k outside Nu) evaluates fluid
    # properties at the FILM temperature T_film = (T_cool + T_wall) / 2,
    # matching Python STREAM's
    #   T_film = film(T_cool, T_wall)
    #   cool   = coolant_funcs.to_properties(T_film, pressure)
    # in heat_transfer_coefficient/__init__.py:208-209.
    #
    # Friction Re (channels.jl:139 inside _channel_core) and the
    # natural-convection Gr inside regime_dependent / elenbaas_htc /
    # variant_obs Gr_over_Re2[i] (channels.jl:742-743) intentionally
    # STAY at bulk T — that matches Python STREAM's convention for
    # those quantities (friction is a bulk-flow phenomenon; NC driving
    # force is a bulk-vs-wall ΔT phenomenon evaluated at bulk).
    # Do NOT "fix" those to film T; they are correct as-is.
    #
    # The shared `_channel_core`'s diagnostic Re[i]/Pr[i]/Pe[i] observables
    # (line 147) ALSO stay at bulk in this phase — `_channel_core` is
    # consumed by Channel, ChannelHeatFlux, and CAC, and only CAC has a
    # wall T in scope. Switching the core would require adding a wall-T
    # kwarg (touches Channel/CHF too) or branching inside the core; both
    # worse than the current arrangement where the CAC-specific film-T
    # diagnostic lives in variant_obs Nu[i] (lines 733-744 below) where
    # thermal_left[i].T is already in scope.
    # ----------------------------------------------------------------
    if scb_correction === nothing
        for i in 1:n
            # Phase 56-resume fix (per-side h): compute h_left using thermal_left[i].T's
            # film, h_right using thermal_right[i].T's film. Matches Python's
            #   h_left  = h_wall(T_wall=T_left,  T_cool, ...)
            #   h_right = h_wall(T_wall=T_right, T_cool, ...)
            # at stream/calculations/channel.py:689-690. Earlier attempts using a
            # single h_tc with max() or ifelse() over the two wall T's destabilized
            # KINSol's Jacobian at the symmetric kink (segfault and NaN convergence).
            # Per-side h is smooth in each path, matches Python's per-side semantics,
            # and produces honest CLEAN/GRAY parity for both heated and adiabatic
            # sides (adiabatic side: T_w ≈ T[i] → T_film ≈ T[i] → h ≈ h_at_bulk;
            # q on that side is h * (T_w−T[i]) ≈ 0 anyway so physics is unaffected).
            # For symmetric scenarios (both walls equal): h_left == h_right (simple_loop unaffected).
            # See .planning/phases/56-python-stream-cross-validation/56-MTR-CONVENTION-RESEARCH.md.
            T_left_w   = thermal_left[i].T
            T_film_l   = (T[i] + T_left_w) / 2
            Re_l       = abs(port_in.mdot) * Dh / (A * mu_water(T_film_l))
            Pr_l       = cp_water(T_film_l) * mu_water(T_film_l) / k_water(T_film_l)
            push!(variant_eqs, h_tc_left[i]  ~ htc_correlation(Re_l, Pr_l, T[i], T_left_w) * k_water(T_film_l) / Dh)

            T_right_w  = thermal_right[i].T
            T_film_r   = (T[i] + T_right_w) / 2
            Re_r       = abs(port_in.mdot) * Dh / (A * mu_water(T_film_r))
            Pr_r       = cp_water(T_film_r) * mu_water(T_film_r) / k_water(T_film_r)
            push!(variant_eqs, h_tc_right[i] ~ htc_correlation(Re_r, Pr_r, T[i], T_right_w) * k_water(T_film_r) / Dh)

            # h_tc[i] retained for backward compat — average of the two sides.
            # (Used by no internal physics now; q_*_expr uses h_tc_left/h_tc_right directly.)
            push!(variant_eqs, h_tc[i] ~ (h_tc_left[i] + h_tc_right[i]) / 2)
        end
    else
        for i in 1:n
            # Phase 56-resume: SCB branch keeps single-h_tc semantics. SCB tests
            # pin both walls to the same T (symmetric); asymmetric SCB is out of
            # v1.1 scope. h_tc_left[i] / h_tc_right[i] alias h_tc[i] here so the
            # variable structure stays uniform across the SCB / non-SCB paths.
            T_w_i    = thermal_left[i].T
            T_film_i = (T[i] + T_w_i) / 2
            Re_i     = abs(port_in.mdot) * Dh / (A * mu_water(T_film_i))
            Pr_i     = cp_water(T_film_i) * mu_water(T_film_i) / k_water(T_film_i)
            h_spl_i  = htc_correlation(Re_i, Pr_i, T[i], T_w_i) * k_water(T_film_i) / Dh

            # Inline P[i] (NOT the P[i] symbol) — Pitfall 7 (avoid observed-to-observed chain)
            P_i = port_in.P - sum(dp[j] for j in 1:i) -
                  (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
            T_sat_i = sat_temperature(P_i)
            # max(q_spl, 0) guards _bergles_rohsenow_dT_ONB against DomainError
            # (SCB-01 / v0.7 retrospective).
            q_spl_i = max(h_spl_i * (T_w_i - T[i]), 0.0)

            # D-03 invariant: scb_correction's Re argument stays at bulk T
            # (separate from the film-T Re_i feeding htc_correlation above).
            # Pre-Phase-57 this was bulk; the SCB closure uses Re only as a
            # regime/laminar gate, which is a bulk-flow phenomenon.
            Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
            q_scb_i     = scb_correction(T_w_i, T_sat_i, Re_i_bulk)
            T_ONB_i     = T_sat_i + _bergles_rohsenow_dT_ONB(P_i, q_spl_i)
            q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i_bulk)
            factor_i    = partial_SCB_correction(q_spl_i, q_scb_i, q_scb_inc_i)

            push!(variant_eqs, h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i * factor_i, h_spl_i))
            push!(variant_eqs, h_tc_left[i]  ~ h_tc[i])
            push!(variant_eqs, h_tc_right[i] ~ h_tc[i])
        end
    end

    # ----------------------------------------------------------------
    # D-09 q-expression construction (per cell). Uses h_tc[i] (the unknown) — core
    # consumes the symbol by reference. Channel-side Q_flow eqns close ThermalPort.
    # When the wall port dangles (no HD connection on that face), MTK's Flow rule
    # auto-zeros Q_flow ⇒ either thermal_*[i].T = T[i] (adiabatic) or h_tc=0 (which
    # cannot happen since h_tc has its own equation) — so unconnected sides settle
    # to the equilibrium where q_*_expr[i] = 0 ⇒ T_wall[i] = T[i]. Adiabatic ✓.
    # ----------------------------------------------------------------
    q_left_expr  = Vector{Num}(undef, n)
    q_right_expr = Vector{Num}(undef, n)
    for i in 1:n
        # Phase 56-resume per-side h: q on each side uses its own side's h.
        # In SCB branch h_tc_left[i] == h_tc_right[i] == h_tc[i] (symmetric SCB).
        q_left_expr[i]  = h_tc_left[i]  * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
        q_right_expr[i] = h_tc_right[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
        push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
        push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
    end

    # ----------------------------------------------------------------
    # Q_wall_total — Phase 53 D-14 — CAC-side scalar diagnostic.
    #
    # Phase 54-05 fix: pushed to variant_obs (was variant_eqs in Wave 3) and
    # expressed directly in q_*_expr to avoid an observed-to-equation chain.
    # The legacy CAC kept `q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow`
    # in `eqs` (q_wall as unknown), so `Q_wall_total ~ sum(q_wall[i])` in eqs was
    # consistent. The new core lifts q_wall[i] into `obs` (matching Channel/CHF),
    # so referencing it from a regular eq created a per-cell shortfall that broke
    # CAC↔HD `mtkcompile` in Phase 54-03 (regression). Direct expression in q_*_expr
    # preserves the semantics (q_wall[i] = q_left_expr[i] + q_right_expr[i]) without
    # the chain.
    # ----------------------------------------------------------------

    # ----------------------------------------------------------------
    # Hand off to _channel_core (Phase 53 D-01 / D-03).
    # ----------------------------------------------------------------
    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry,
        g_acc=g, friction_correlation,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )

    # ----------------------------------------------------------------
    # Variant-internal observables (Phase 53 D-09):
    # Nu[i] (correlation output, not in core), h_tc_left/right (aliases of h_tc),
    # T_wall_left/right (aliases of thermal_*[i].T), Gr_over_Re2 (NC criterion;
    # references variant-specific T_w − T[i] which core doesn't see),
    # velocity (legacy alias). All inlined so no observed-to-observed chains.
    # ----------------------------------------------------------------
    variant_obs = Equation[]
    for i in 1:n
        # Phase 57 D-01/D-02/B3 + Phase 56-resume: Nu[i] reports the same
        # htc_correlation output that h_tc[i] consumes (SPL branch above), so its
        # Re/Pr/wall-T must use the same eval-point convention. The "wall" is
        # max(left, right) — picks the heated side in asymmetric scenarios; equal
        # to either side in symmetric / both-pinned scenarios (simple_loop).
        T_w_obs_i    = thermal_left[i].T
        T_film_obs_i = (T[i] + T_w_obs_i) / 2
        Re_i_film    = abs(port_in.mdot) * Dh / (A * mu_water(T_film_obs_i))
        Pr_i_film    = cp_water(T_film_obs_i) * mu_water(T_film_obs_i) / k_water(T_film_obs_i)
        push!(variant_obs, Nu[i] ~ htc_correlation(Re_i_film, Pr_i_film, T[i], T_w_obs_i))
        # Phase 56-resume per-side h: h_tc_left[i] and h_tc_right[i] are now
        # unknowns with their own equations in variant_eqs (SPL: per-side film T;
        # SCB: aliased to h_tc[i]). No observable aliases here.
        push!(variant_obs, T_wall_left[i]  ~ thermal_left[i].T)
        push!(variant_obs, T_wall_right[i] ~ thermal_right[i].T)
        push!(variant_obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))
        # D-03 invariant: NC criterion `Gr_over_Re2[i]` stays fully bulk-T
        # (numerator AND denominator). Use a separate bulk Re here so the
        # film-T `Re_i_film` above does not leak into the NC observable.
        Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        nu_i = mu_water(T[i]) / rho_water(T[i])
        Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
        push!(variant_obs, Gr_over_Re2[i] ~ Gr_i / Re_i_bulk^2)
    end
    # Q_wall_total — direct sum over q_*_expr to avoid observed-to-equation chain
    # (Phase 54-05 fix; see comment block above before the q-expression loop).
    push!(variant_obs, Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n))

    eqs = [variant_eqs; core.eqs]
    obs = [core.obs; variant_obs]

    all_vars = [
        collect(T); collect(dp); collect(h_tc);
        collect(Re); collect(Pe); collect(v);
        collect(P); collect(T_sat); collect(T_ONB);
        collect(q_wall); collect(q_wall_left); collect(q_wall_right);
        collect(Nu); collect(h_tc_left); collect(h_tc_right);
        collect(T_wall_left); collect(T_wall_right);
        collect(Gr_over_Re2); collect(velocity);
        T_out; dP; Q_wall_total
    ]

    compose(
        System(eqs, t, all_vars, pars; observed=obs, name=name),
        port_in, port_out, thermal_left..., thermal_right...,
    )
end

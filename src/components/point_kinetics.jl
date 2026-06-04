# point_kinetics.jl -- PointKinetics component and steady-state IC helper for STREAM.jl
#
# Implements the 6-group point kinetics equations (7 ODEs: 1 power + 6 precursor groups)
# with a constant reactivity parameter. The companion point_kinetics_steady_state function
# computes analytically correct initial conditions at criticality (rho=0).
#
# ODE formulation (Keepin 1965, same as Python STREAM):
#   dP/dt   = (rho - beta) / Lambda * P + sum_k(lambda_k * C_k)
#   dC_k/dt = -lambda_k * C_k + beta_k / Lambda * P    for k = 1..6
#

# U-235 6-group delayed neutron data (same as Python STREAM reference)
const U235_LAMBDA = 5.4e-5  # neutron generation time [s]
const U235_LAMBDA_K = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]  # precursor decay constants [1/s]
const U235_BETA_K = [0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273]  # delayed neutron fractions [-]
# beta_total = sum(U235_BETA_K) = 0.006502

function _flatten_weights(raw, comp)
    T_sym = getproperty(comp, :T)
    if ndims(T_sym) == 2
        nz, nx = size(T_sym)
        if raw isa Real
            return (fill(Float64(raw), nz * nx), nz * nx)
        elseif raw isa AbstractMatrix && size(raw) == (nz, nx)
            return ([Float64(raw[i, j]) for i in 1:nz for j in 1:nx], nz * nx)
        else
            throw(
                ArgumentError(
                    "weight for $(nameof(comp)) must be scalar or $(nz)x$(nx) matrix, got $(summary(raw))",
                ),
            )
        end
    else
        n = length(T_sym)
        if raw isa Real
            return (fill(Float64(raw), n), n)
        elseif raw isa AbstractVector && length(raw) == n
            return (Float64.(raw), n)
        else
            throw(
                ArgumentError(
                    "weight for $(nameof(comp)) must be scalar or length-$n vector, got $(summary(raw))",
                ),
            )
        end
    end
end

"""
    PointKinetics(; name, rho=0.0, Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K) -> System
    PointKinetics(rho_c_fn::Any; name, rho_val=0.0, Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K) -> System

Standalone 6-group point kinetics component implementing 7 coupled ODEs for reactor
neutronics: 1 power equation and 6 delayed neutron precursor group equations.

At rho=0 (default), the system is exactly critical -- power remains constant when
initialized with the correct precursor concentrations from `point_kinetics_steady_state`.

# Arguments
- `name`: system name (Symbol, injected by `@named` macro)
- `rho`: constant reactivity [-] (default 0.0 = critical). Note: rho=0 is the steady-state
  operating point; positive rho drives supercritical power excursion. (scalar mode only)
- `Lambda`: neutron generation time [s] (default U235_LAMBDA = 5.4e-5)
- `beta_k`: delayed neutron fractions [-] for each of 6 groups (default U235_BETA_K)
- `lambda_k`: precursor decay constants [1/s] for each of 6 groups (default U235_LAMBDA_K)

# Returns
Uncompiled `System` with 7 state variables (P, C_1..C_6) and 3 observed variables
(beta_total, dPdt, reactivity). Call `mtkcompile(sys)` before solving.
"""
function PointKinetics(;
    name, rho=0.0, Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K
)

    pars = @parameters begin
        rho_val = rho
        Lambda_gen = Lambda
        beta_1 = beta_k[1]
        beta_2 = beta_k[2]
        beta_3 = beta_k[3]
        beta_4 = beta_k[4]
        beta_5 = beta_k[5]
        beta_6 = beta_k[6]
        lambda_1 = lambda_k[1]
        lambda_2 = lambda_k[2]
        lambda_3 = lambda_k[3]
        lambda_4 = lambda_k[4]
        lambda_5 = lambda_k[5]
        lambda_6 = lambda_k[6]
    end

    @variables begin
        P(t) = 1.0
        C_1(t)
        C_2(t)
        C_3(t)
        C_4(t)
        C_5(t)
        C_6(t)
        # Observed variables (declared here, assigned in obs equations below)
        beta_total(t)
        dPdt(t)
        reactivity(t)
    end

    beta_sum = beta_1 + beta_2 + beta_3 + beta_4 + beta_5 + beta_6

    # Precursor source terms: sum_k(lambda_k * C_k)
    precursor_source =
        lambda_1 * C_1 +
        lambda_2 * C_2 +
        lambda_3 * C_3 +
        lambda_4 * C_4 +
        lambda_5 * C_5 +
        lambda_6 * C_6

    eqs = Equation[
        D(P) ~ (rho_val - beta_sum) / Lambda_gen * P + precursor_source,
        D(C_1) ~ -lambda_1 * C_1 + beta_1 / Lambda_gen * P,
        D(C_2) ~ -lambda_2 * C_2 + beta_2 / Lambda_gen * P,
        D(C_3) ~ -lambda_3 * C_3 + beta_3 / Lambda_gen * P,
        D(C_4) ~ -lambda_4 * C_4 + beta_4 / Lambda_gen * P,
        D(C_5) ~ -lambda_5 * C_5 + beta_5 / Lambda_gen * P,
        D(C_6) ~ -lambda_6 * C_6 + beta_6 / Lambda_gen * P,
    ]

    # Observed variables: diagnostics computed post-solve (never on RHS of another equation).
    # All expressions are inlined -- no observed-to-observed chains.
    obs = Equation[
        beta_total ~ beta_sum,
        dPdt ~ (rho_val - beta_sum) / Lambda_gen * P + precursor_source,
        reactivity ~ rho_val,
    ]

    return System(
        eqs,
        t,
        [P, C_1, C_2, C_3, C_4, C_5, C_6],
        [
            rho_val,
            Lambda_gen,
            beta_1,
            beta_2,
            beta_3,
            beta_4,
            beta_5,
            beta_6,
            lambda_1,
            lambda_2,
            lambda_3,
            lambda_4,
            lambda_5,
            lambda_6,
        ];
        observed=obs,
        name=name,
    )
end

"""
    PointKinetics(rho_c_fn::Any; name, rho_val=0.0, Lambda=U235_LAMBDA, beta_k=U235_BETA_K,
                  lambda_k=U235_LAMBDA_K, temp_worth=nothing, ref_temp=nothing) -> System

Callable-mode constructor for `PointKinetics`. The control reactivity is provided as a
callable `rho_c_fn(t) -> Float64` (or a `ReactivityController` instance, which is itself
callable). The power ODE becomes:

    D(P) ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source

where `rho_val` is a constant base/bias reactivity, `rho_c_fn(t)` is the time-varying
control contribution (D-01 additive composition), and `feedback_expr` is the per-cell
temperature reactivity sum (Phase 47):

    feedback_expr = sum_j alpha_j * (T_j - Tref_j)

i.e. each `temp_worth` weight `alpha_j` is the temperature coefficient of reactivity
(d_rho/d_T) for that cell and enters the reactivity additively, signed. It is used with
its absolute sign: a stabilizing reactor has a NEGATIVE coefficient, so `alpha_j` is
normally a negative value (hotter -> less reactive). A positive value gives destabilizing
feedback.

When solving, the callable must be passed in the initial conditions dict:
    `op = [ssys.rho_c_fn => rho_c_fn, ssys.P => ic.P, ...]`

This is required because MTK stores callable parameters by reference (D-10); omitting it
causes `KeyError` at `solve_transient`.

# Arguments
- `rho_c_fn` (positional): callable with signature `(t) -> Float64`. May also be a
  `ReactivityController` instance (callable via `ctrl(t)`). Concrete type is captured via
  `FType = typeof(rho_c_fn)` at construction time.
- `name`: system name (Symbol, injected by `@named` macro)
- `rho_val`: constant base reactivity [-] (default 0.0 = critical bias)
- `Lambda`: neutron generation time [s] (default U235_LAMBDA = 5.4e-5)
- `beta_k`: delayed neutron fractions [-] for each of 6 groups (default U235_BETA_K)
- `lambda_k`: precursor decay constants [1/s] for each of 6 groups (default U235_LAMBDA_K)
- `temp_worth::Union{Nothing,Dict}=nothing`: per-component temperature feedback weights.
  Keys are uncompiled MTK Systems; values are scalar (broadcast to all cells), 1D vector
  (matches Channel n-cell structure), or 2D matrix (matches HeatDiffusion nz*nx, flattened
  row-major per D-03: j_flat = (jz-1)*nx + jx). `nothing` (default) = no temperature
  feedback, identical to Phase 46 behavior.
- `ref_temp::Union{Nothing,Dict}=nothing`: per-component reference temperatures [K].
  Same key structure as `temp_worth`. Missing keys default to zero (full T contributes).

# Returns
Uncompiled `System` with 7 + sum(n_flat_per_component) state variables, 3 observed
variables (beta_total, dPdt, reactivity), and an MTK callable parameter `rho_c_fn`.
Call `mtkcompile(sys)` before solving.

**Important:** When `temp_worth` is provided, the resulting System has free T_source
unknowns that MUST be bound by calling `connect_temperature_feedback` and wrapping in
a composed System before `mtkcompile` (Phase 47 D-05).
"""
function PointKinetics(
    rho_c_fn::Any;
    name,
    rho_val=0.0,
    Lambda=U235_LAMBDA,
    beta_k=U235_BETA_K,
    lambda_k=U235_LAMBDA_K,
    temp_worth=nothing,
    ref_temp=nothing,
)
    FType = typeof(rho_c_fn)
    pars = @parameters begin
        rho_val = rho_val
        Lambda_gen = Lambda
        beta_1 = beta_k[1]
        beta_2 = beta_k[2]
        beta_3 = beta_k[3]
        beta_4 = beta_k[4]
        beta_5 = beta_k[5]
        beta_6 = beta_k[6]
        lambda_1 = lambda_k[1]
        lambda_2 = lambda_k[2]
        lambda_3 = lambda_k[3]
        lambda_4 = lambda_k[4]
        lambda_5 = lambda_k[5]
        lambda_6 = lambda_k[6]
        (rho_c_fn::FType)(..)
    end

    @variables begin
        P(t) = 1.0
        C_1(t)
        C_2(t)
        C_3(t)
        C_4(t)
        C_5(t)
        C_6(t)
        beta_total(t)
        dPdt(t)
        reactivity(t)
    end

    beta_sum = beta_1 + beta_2 + beta_3 + beta_4 + beta_5 + beta_6
    precursor_source = (
        lambda_1 * C_1 +
        lambda_2 * C_2 +
        lambda_3 * C_3 +
        lambda_4 * C_4 +
        lambda_5 * C_5 +
        lambda_6 * C_6
    )

    T_source_vars = Num[]
    feedback_expr = 0
    if temp_worth !== nothing
        ref_dict = ref_temp === nothing ? Dict() : ref_temp
        for (comp, alpha_raw) in temp_worth
            cname = nameof(comp)
            alpha_flat, n_flat = _flatten_weights(alpha_raw, comp)
            Tref_raw = get(ref_dict, comp, 0.0)
            Tref_flat, _ = _flatten_weights(Tref_raw, comp)
            @assert length(Tref_flat) == n_flat
            var_sym = Symbol(:T_source_, cname)
            Tsrc = only(@variables $(var_sym)(t)[1:n_flat])
            append!(T_source_vars, collect(Tsrc))
            for j in 1:n_flat
                feedback_expr = feedback_expr + alpha_flat[j] * (Tsrc[j] - Tref_flat[j])
            end
        end
    end

    eqs = Equation[
        D(P) ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source,
        D(C_1) ~ -lambda_1 * C_1 + beta_1 / Lambda_gen * P,
        D(C_2) ~ -lambda_2 * C_2 + beta_2 / Lambda_gen * P,
        D(C_3) ~ -lambda_3 * C_3 + beta_3 / Lambda_gen * P,
        D(C_4) ~ -lambda_4 * C_4 + beta_4 / Lambda_gen * P,
        D(C_5) ~ -lambda_5 * C_5 + beta_5 / Lambda_gen * P,
        D(C_6) ~ -lambda_6 * C_6 + beta_6 / Lambda_gen * P,
    ]

    obs = Equation[
        beta_total ~ beta_sum,
        dPdt ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source,
        reactivity ~ rho_val + rho_c_fn(t) + feedback_expr,
    ]

    return System(
        eqs,
        t,
        [P, C_1, C_2, C_3, C_4, C_5, C_6, T_source_vars...],
        [
            rho_val,
            Lambda_gen,
            beta_1,
            beta_2,
            beta_3,
            beta_4,
            beta_5,
            beta_6,
            lambda_1,
            lambda_2,
            lambda_3,
            lambda_4,
            lambda_5,
            lambda_6,
            rho_c_fn,
        ];
        observed=obs,
        name=name,
    )
end

"""
    point_kinetics_steady_state(P0; Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K) -> NamedTuple

Compute analytically correct initial conditions for the point kinetics equations at
criticality (rho=0). Essential because KINSOL finds the trivial P=0 solution when given
zero or poor initial conditions.

At steady state with rho=0, dC_k/dt = 0 gives: C_k = beta_k / (lambda_k * Lambda) * P0.

# Arguments
- `P0`: initial power [W]
- `Lambda`: neutron generation time [s] (default U235_LAMBDA = 5.4e-5)
- `beta_k`: delayed neutron fractions [-] (default U235_BETA_K)
- `lambda_k`: precursor decay constants [1/s] (default U235_LAMBDA_K)

# Returns
NamedTuple `(P=P0, C_k=Vector{Float64})` where `C_k[i] = beta_k[i] / (lambda_k[i] * Lambda) * P0`.
"""
function point_kinetics_steady_state(
    P0; Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K
)
    C_k = [beta_k[i] / (lambda_k[i] * Lambda) * P0 for i in 1:length(beta_k)]
    return (P=P0, C_k=C_k)
end

"""
    ReactivityController{S, F}

Pure-Julia state-machine controller that provides time-varying control reactivity
for `PointKinetics` in callable mode. Mirrors the Python STREAM `ReactivityController`
API: stores an `input_reactivity` callable with signature `(state, t_state, t) -> Float64`,
a `state_machine` callable with signature `(state, t, power, dPdt) -> new_state`, the
current state and time-of-entry, a transition log, and an `abort_states` set used by
downstream callbacks (Phase 49) to signal early integrator termination.

Instances are callable: `ctrl(t)` returns `worth(ctrl, t)`. This lets users pass a
`ReactivityController` directly as the MTK callable parameter to
`PointKinetics(ctrl; rho_val=0.0, ...)` without writing a wrapper closure.

# Fields
- `input_reactivity::F` : callable `(state, t_state, t) -> Float64`
- `state_machine`       : callable `(state, t, power, dPdt) -> new_state` (untyped -- may be swapped)
- `state::S`            : current controller state (typically a Symbol)
- `t_state::Float64`    : simulation time when the current state was entered
- `log::Vector{Tuple{S, Float64}}` : state transition history (state, entry-time) pairs
- `abort_states::Set`   : states that signal downstream callbacks to stop integration
"""
mutable struct ReactivityController{S,F}
    input_reactivity::F
    state_machine
    state::S
    t_state::Float64
    log::Vector{Tuple{S,Float64}}
    abort_states::Set
end

"""
    ReactivityController(input_reactivity=nothing; initial_state=:NORMAL, initial_time=0.0,
                         state_machine=nothing, abort_states=nothing) -> ReactivityController

Construct a `ReactivityController` with sensible defaults.

# Arguments
- `input_reactivity` (positional, optional): callable `(state, t_state, t) -> Float64`.
  If `nothing`, defaults to `(s, ts, t) -> 0.0`.
- `initial_state` (kwarg): initial controller state (default `:NORMAL`).
- `initial_time` (kwarg): time stamp for the initial state entry (default `0.0`).
- `state_machine` (kwarg): callable `(state, t, power, dPdt) -> new_state`.
  If `nothing`, defaults to identity `(s, t, p, dp) -> s` (state never auto-transitions).
- `abort_states` (kwarg): `Set` of states that signal integrator termination.
  If `nothing`, defaults to an empty `Set()`.

# Returns
A `ReactivityController{S,F}` where `S = typeof(initial_state)` and
`F = typeof(input_reactivity)`. The `log` field starts with `[(initial_state, initial_time)]`.
"""
function ReactivityController(
    input_reactivity=nothing;
    initial_state=:NORMAL,
    initial_time=0.0,
    state_machine=nothing,
    abort_states=nothing,
)
    ir = input_reactivity === nothing ? ((s, ts, t) -> 0.0) : input_reactivity
    sm = state_machine === nothing ? ((s, t, p, dp) -> s) : state_machine
    ab = abort_states === nothing ? Set() : abort_states
    S_t = typeof(initial_state)
    F_t = typeof(ir)
    t0 = Float64(initial_time)
    return ReactivityController{S_t,F_t}(
        ir, sm, initial_state, t0, Tuple{S_t,Float64}[(initial_state, t0)], ab
    )
end

"""
    worth(ctrl::ReactivityController, t_now) -> Float64

Evaluate the controller's `input_reactivity` callable at the current state,
state-entry time, and simulation time `t_now`. This is the primary output method
invoked by the MTK callable parameter when `ctrl` is passed to
`PointKinetics(ctrl; ...)`.

# Arguments
- `ctrl`: the `ReactivityController` instance
- `t_now`: current simulation time [s]

# Returns
`Float64` control reactivity value [-].
"""
function worth(ctrl::ReactivityController, t_now)
    return ctrl.input_reactivity(ctrl.state, ctrl.t_state, t_now)
end

"""
    change_state(ctrl::ReactivityController, t_now, power, dPdt) -> new_state

Invoke the controller's `state_machine` and update `ctrl` if the state changes.
If `state_machine(state, t_now, power, dPdt)` returns a value different from the
current state, `ctrl.state` is updated, `ctrl.t_state` is set to `t_now`, and
`(new_state, t_now)` is appended to `ctrl.log`. If the state is unchanged, no
mutation occurs.

# Arguments
- `ctrl`: the `ReactivityController` instance
- `t_now`: current simulation time [s]
- `power`: current reactor power [W]
- `dPdt`: current dP/dt [W/s]

# Returns
The (possibly new) state after the state_machine call.
"""
function change_state(ctrl::ReactivityController, t_now, power, dPdt)
    new_state = ctrl.state_machine(ctrl.state, t_now, power, dPdt)
    if new_state != ctrl.state
        ctrl.state = new_state
        ctrl.t_state = Float64(t_now)
        push!(ctrl.log, (new_state, Float64(t_now)))
    end
    return new_state
end

(ctrl::ReactivityController)(t_now) = worth(ctrl, t_now)

"""
    SCRAMCondition

State-machine condition struct for power-triggered SCRAM. Constructed via
`SCRAM_at_power(power_limit)`. When called as a state machine by
`ReactivityController.change_state`, returns `:SCRAM` if current power exceeds
`power_limit`, otherwise returns the current state unchanged.

# Fields
- `power_limit::Float64`: reactor power threshold above which SCRAM triggers
"""
struct SCRAMCondition
    power_limit::Float64
end

"""
    SCRAM_at_power(power_limit) -> SCRAMCondition

Construct a `SCRAMCondition` for use as the `state_machine` kwarg of
`ReactivityController`. The returned struct triggers SCRAM when reactor power
exceeds `power_limit`.

# Arguments
- `power_limit`: threshold power value (coerced to Float64)

# Returns
`SCRAMCondition` instance.
"""
SCRAM_at_power(power_limit) = SCRAMCondition(Float64(power_limit))
(s::SCRAMCondition)(state, t, P, dPdt) = P > s.power_limit ? :SCRAM : state

"""
    scram_callback(ssys, p_sym, ctrl; terminate=true) -> ContinuousCallback

Return a `DifferentialEquations.ContinuousCallback` that fires when reactor power P
crosses `ctrl.state_machine.power_limit` from below (upward zero-crossing of
`P - power_limit`). On firing:
1. Calls `change_state(ctrl, t, P, dPdt)` to transition `ctrl.state` to `:SCRAM`.
2. If `terminate=true` (default), calls `terminate!(integrator)` to stop the solver early.

`ctrl.state_machine` must be a `SCRAMCondition` (constructed via `SCRAM_at_power`).

# Arguments
- `ssys`: compiled MTK system from `mtkcompile`. Used to eagerly resolve the integer index
  of `p_sym` in the ODE state vector at callback construction time.
- `p_sym`: symbolic variable for reactor power in the compiled system. After `mtkcompile`,
  this is `ssys.P` if PK is the root system, or `ssys.pk.P` if PK is a subsystem named `:pk`.
  Pass whichever is appropriate for your topology.
- `ctrl`: `ReactivityController` whose `state_machine` is a `SCRAMCondition`.
- `terminate` (kwarg): `true` (default) stops solver early at SCRAM. Pass `false` to
  simulate the full post-SCRAM shutdown transient driven by negative control reactivity.

# Returns
`ContinuousCallback` — pass to `solve_transient(...; callbacks=cb)`.

# Example
```julia
# Standalone PK (PK is root system):
cb = scram_callback(ssys, ssys.P, ctrl)
sol = solve_transient(ssys, op, t_arr; callbacks=cb)

# Full loop (PK nested as :pk subsystem):
cb = scram_callback(ssys, ssys.pk.P, ctrl)

# Simulate full post-SCRAM shutdown (no early termination):
cb = scram_callback(ssys, ssys.pk.P, ctrl; terminate=false)
sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```
"""
function scram_callback(ssys, p_sym::Num, ctrl; terminate=true)
    plimit = ctrl.state_machine.power_limit
    p_idx = ModelingToolkit.variable_index(ssys, p_sym)

    condition = (u, t, integrator) -> u[p_idx] - plimit
    affect! = function (integrator)
        change_state(ctrl, integrator.t, plimit + 1.0, 0.0)
        return terminate && terminate!(integrator)
    end

    return ContinuousCallback(condition, affect!)  # upward crossing only (P - plimit: neg -> pos)
end

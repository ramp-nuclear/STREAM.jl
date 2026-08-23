"""
    U235_LAMBDA

Prompt neutron generation time Λ for U-235, `5.4e-5` s. The default `Lambda` in
[`PointKinetics`](@ref).
"""
const U235_LAMBDA = 5.4e-5

"""
    U235_LAMBDA_K

Precursor decay constants λₖ [1/s] for the six standard U-235 delayed neutron groups, ordered
fastest to slowest. The default `lambda_k` in [`PointKinetics`](@ref), paired group for group
with [`U235_BETA_K`](@ref).
"""
const U235_LAMBDA_K = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]

"""
    U235_BETA_K

Delayed neutron fractions βₖ [-] for the six standard U-235 groups, in the same order as
[`U235_LAMBDA_K`](@ref). The default `beta_k` in [`PointKinetics`](@ref), where
`length(beta_k)` sets the group count.

They sum to β = 0.006502, reported by the `beta_total` observable.
"""
const U235_BETA_K = [0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273]

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
    _temperature_feedback(temp_worth, ref_temp) -> (expr, unknowns)

Build the per-cell temperature reactivity `Σⱼ αⱼ·(Tⱼ - Trefⱼ)` and the free `T_source`
unknowns it reads. Returns `(0, Num[])` when `temp_worth` is `nothing`.

The `T_source` unknowns have no equation here; `temperature_feedback` binds them to
the component temperatures they stand for.
"""
function _temperature_feedback(temp_worth, ref_temp)
    temp_worth === nothing && return (0, Num[])
    ref_dict = ref_temp === nothing ? Dict() : ref_temp
    unknown_vars = Num[]
    expr = 0
    for (comp, alpha_raw) in temp_worth
        alpha, n_flat = _flatten_weights(alpha_raw, comp)
        Tref, _ = _flatten_weights(get(ref_dict, comp, 0.0), comp)
        length(Tref) == n_flat || throw(
            DimensionMismatch(
                "ref_temp for $(nameof(comp)) has length $(length(Tref)), expected $n_flat",
            ),
        )
        var_sym = Symbol(:T_source_, nameof(comp))
        T_source = only(@variables $(var_sym)(t)[1:n_flat])
        append!(unknown_vars, collect(T_source))
        expr = expr + sum(alpha[j] * (T_source[j] - Tref[j]) for j in 1:n_flat)
    end
    return (expr, unknown_vars)
end

"""
    PointKinetics(rho_c_fn::Any; name, Lambda=U235_LAMBDA, beta_k=U235_BETA_K,
                  lambda_k=U235_LAMBDA_K, temp_worth=nothing, ref_temp=nothing) -> System

Keepin (1965) point kinetics with `G` delayed precursor groups, so `1 + G` ODEs:

    dP/dt  = (ρ - β)/Λ · P + Σₖ λₖ·Cₖ
    dCₖ/dt = βₖ/Λ · P - λₖ·Cₖ           k = 1..G

`G` is `length(beta_k)`. The defaults are the six-group U-235 data ([`U235_BETA_K`](@ref),
[`U235_LAMBDA_K`](@ref)), giving seven equations.
[`point_kinetics_steady_state`](@ref) gives the precursor concentrations that hold power steady
at criticality.

The control reactivity comes from a callable `rho_c_fn(t)` (a `ReactivityController` is itself
callable), and the total reactivity becomes

    ρ = rho_c_fn(t) + Σⱼ αⱼ·(Tⱼ - Trefⱼ)

where the sum is the per-cell temperature feedback. Each weight `αⱼ` is a temperature
coefficient of reactivity (dρ/dT) and enters signed: a stabilizing reactor has a negative
coefficient, so `αⱼ` is normally negative.

A critical reactor is `rho_c_fn = t -> 0.0`; a constant bias is `t -> ρ₀`.

When solving, the callable must appear in the operating point:
`op = [ssys.rho_c_fn => rho_c_fn, ssys.P => ic.P, ...]`. MTK stores callable parameters by
reference, so omitting it raises `KeyError` at `solve_transient`.

# Arguments
- `rho_c_fn` (positional): callable `(t) -> Float64`, or a `ReactivityController`. Its
  concrete type is captured at construction.
- `name`: system name (Symbol, injected by `@named`)
- `Lambda`: neutron generation time [s] (default `U235_LAMBDA`)
- `beta_k`, `lambda_k`: per-group delayed data; `length(beta_k)` sets the group count
- `temp_worth::Union{Nothing,Dict}=nothing`: per-component feedback weights. Keys are
  uncompiled MTK Systems; values are scalar (broadcast to every cell), a length-n vector
  (Channel), or an nz×nx matrix (HeatDiffusion, flattened row-major as
  `j = (jz-1)*nx + jx`). `nothing` disables feedback.
- `ref_temp::Union{Nothing,Dict}=nothing`: per-component reference temperatures [°C], same
  key structure. Missing keys default to zero, so the full temperature contributes.

# Returns
Uncompiled `System` with unknowns `P`, `C[1:G]`, and one `T_source` array per feedback
component, plus the callable parameter `rho_c_fn`.

**Important:** with `temp_worth` set, the `T_source` unknowns are free until
`temperature_feedback` binds them; do that and compose before `mtkcompile`.
"""
function PointKinetics(
    rho_c_fn::Any;
    name,
    Lambda=U235_LAMBDA,
    beta_k=U235_BETA_K,
    lambda_k=U235_LAMBDA_K,
    temp_worth=nothing,
    ref_temp=nothing,
)
    FType = typeof(rho_c_fn)
    control = function ()
        control_pars = @parameters (rho_c_fn::FType)(..)
        feedback, feedback_unknowns = _temperature_feedback(temp_worth, ref_temp)
        return (control_pars[1](t) + feedback, control_pars, feedback_unknowns)
    end
    G = length(beta_k)
    G == length(lambda_k) || throw(
        DimensionMismatch("beta_k has $G groups but lambda_k has $(length(lambda_k))")
    )

    pars = @parameters begin
        Λ = Lambda
        β[1:G] = collect(beta_k)
        λ[1:G] = collect(lambda_k)
    end

    @variables begin
        P(t) = 1.0
        (C(t))[1:G]
        # Observed diagnostics, assigned below; never on the RHS of another equation.
        beta_total(t)
        dPdt(t)
        reactivity(t)
    end

    β_k, λ_k, C_k = collect(β), collect(λ), collect(C)
    control_reactivity, control_pars, control_unknowns = control()
    ρ = control_reactivity
    β_sum = sum(β_k)

    # Keepin (1965), G delayed groups. `Ṗ` is the rate expression itself, kept separate from
    # the `dPdt` observable below so neither name shadows the other.
    #     Ṗ  = (ρ - β)/Λ · P + Σₖ λₖ·Cₖ
    #     Ċₖ = βₖ/Λ · P - λₖ·Cₖ
    Ṗ = (ρ - β_sum) / Λ * P + λ_k ⋅ C_k

    eqs = [
        D(P) ~ Ṗ
        D.(C_k) .~ β_k ./ Λ .* P .- λ_k .* C_k
    ]
    obs = Equation[beta_total ~ β_sum, dPdt ~ Ṗ, reactivity ~ ρ]

    return System(
        eqs,
        t,
        [P; C_k; control_unknowns],
        [pars; control_pars];
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
    C_k = [beta_k[i] / (lambda_k[i] * Lambda) * P0 for i in eachindex(beta_k)]
    return (P=P0, C_k=C_k)
end

"""
    ReactivityController{S, F, M}

Pure-Julia state-machine controller that provides time-varying control reactivity
for `PointKinetics` in callable mode. Mirrors the Python STREAM `ReactivityController`
API: stores an `input_reactivity` callable with signature `(state, t_state, t) -> Float64`,
a `state_machine` callable with signature `(state, t, power, dPdt) -> new_state`, the
current state and time-of-entry, a transition log, and an `abort_states` set used by
downstream callbacks to signal early integrator termination.

Instances are callable: `ctrl(t)` returns `worth(ctrl, t)`. This lets users pass a
`ReactivityController` directly as the MTK callable parameter to `PointKinetics(ctrl; ...)`
without writing a wrapper closure.

# Fields
- `input_reactivity::F` : callable `(state, t_state, t) -> Float64`
- `state_machine::M`    : callable `(state, t, power, dPdt) -> new_state`
- `state::S`            : current controller state (typically a Symbol)
- `t_state::Float64`    : simulation time when the current state was entered
- `log::Vector{Tuple{S, Float64}}` : state transition history (state, entry-time) pairs
- `abort_states::Set{S}` : states that signal downstream callbacks to stop integration
"""
mutable struct ReactivityController{S,F,M}
    input_reactivity::F
    state_machine::M
    state::S
    t_state::Float64
    log::Vector{Tuple{S,Float64}}
    abort_states::Set{S}
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
A `ReactivityController{S,F,M}` where `S = typeof(initial_state)`,
`F = typeof(input_reactivity)`, and `M = typeof(state_machine)`. The `log` field
starts with `[(initial_state, initial_time)]`.
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
    S_t = typeof(initial_state)
    F_t = typeof(ir)
    M_t = typeof(sm)
    ab = abort_states === nothing ? Set{S_t}() : Set{S_t}(abort_states)
    t0 = Float64(initial_time)
    return ReactivityController{S_t,F_t,M_t}(
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

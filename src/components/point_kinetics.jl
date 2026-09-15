"""
    U235_LAMBDA

Prompt neutron generation time Λ for U-235, `5.4e-5` s. The default `Lambda` in
[`PointKinetics`](@ref).
"""
const U235_LAMBDA = 5.4e-5

"""
    U235_LAMBDA_K

Precursor decay constants λₖ [1/s] for Keepin's six U-235 thermal-fission delayed neutron
groups (Physics of Nuclear Kinetics, 1965), ordered slowest to fastest: half-lives of 55.72,
22.72, 6.22, 2.30, 0.61 and 0.23 s. The default `lambda_k` in [`PointKinetics`](@ref), paired
group for group with [`U235_BETA_K`](@ref).
"""
const U235_LAMBDA_K = [0.0124, 0.0305, 0.111, 0.301, 1.14, 3.01]

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
    _power_input_term(power_input) -> (term, parameters)

The term [`PointKinetics`](@ref) adds to `P_neutron` to form the total `P`, with the
parameters it introduces: none for `nothing`, the parameter `power_input` for a number, and
the callable parameter `power_input_fn` evaluated at `t` for a function. Each parameter
takes the value passed in as its default.
"""
_power_input_term(::Nothing) = (0, Num[])

function _power_input_term(value::Real)
    pars = @parameters power_input = value
    return (pars[1], pars)
end

function _power_input_term(f)
    F = typeof(f)
    pars = @parameters (power_input_fn::F)(..) = f
    return (pars[1](t), pars)
end

"""
    PointKinetics(rho_c_fn::Any; name, Lambda=U235_LAMBDA, beta_k=U235_BETA_K,
                  lambda_k=U235_LAMBDA_K, temp_worth=nothing, ref_temp=nothing,
                  power_input=nothing, P0=1.0) -> System

Keepin (1965) point kinetics with `G` delayed precursor groups, so `1 + G` ODEs:

    dPₙ/dt = (ρ - β)/Λ · Pₙ + Σₖ λₖ·Cₖ
    dCₖ/dt = βₖ/Λ · Pₙ - λₖ·Cₖ           k = 1..G

with `Pₙ` the neutron power, the unknown `P_neutron`.

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

The system starts where it was built to: `rho_c_fn` defaults to the callable given, and
`P_neutron` and `C` to the critical steady state holding a total power `P0`, with
`power_input` taken at `t = 0`, as [`point_kinetics_steady_state`](@ref) computes it. Put any
of them in the operating point to start elsewhere.

# Neutron and total power

`P_neutron` is the power the equations above integrate. `power_input` adds a source that
fission does not produce, and the total is

    P = P_neutron + power_input

Decay heat is what this is for, through [`STREAM.DecayHeat.DecayHeatSource`](@ref), but any
external source fits: gamma deposition in the reflector, pump heat, and so on. Couple a fuel
plate to `P`, the power it actually receives.

`power_input` carries the same units as `P_neutron`. Those are Watts only if the kinetics
run in Watts; a model running dimensionless kinetics and scaling later (as `build_loop_pk`
does) needs a `power_input` scaled the same way.

With no `power_input`, `P` is `P_neutron` and costs nothing: `mtkcompile` eliminates the
equation either way, so the compiled state count is `1 + G` regardless.

[`scram_callback`](@ref) trips on `P_neutron` rather than `P`, which is what a power-range
monitor reading neutron flux measures.

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
- `power_input=nothing`: non-fission power added to `P_neutron`. A `Real` becomes the
  parameter `power_input`, and anything else is taken as a callable `(t) -> Float64` and
  becomes the callable parameter `power_input_fn`. Either carries the value given as its
  default, so neither has to appear in the operating point, and `solve_transient` can
  override either. `nothing` leaves `P ~ P_neutron`.
- `P0=1.0`: the total power `P` the default initial state holds, in the units of `P_neutron`

# Returns
Uncompiled `System` with unknowns `P_neutron`, `C[1:G]`, `P`, and one `T_source` array per
feedback component, plus the callable parameter `rho_c_fn`.

`P` is algebraic, so `mtkcompile` moves it to `observed` and the compiled system keeps
`1 + G` states. Read it off a solution as `sol[ssys.pk.P]`.

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
    power_input=nothing,
    P0=1.0,
)
    FType = typeof(rho_c_fn)
    rho_c_default = rho_c_fn
    control = function ()
        control_pars = @parameters (rho_c_fn::FType)(..) = rho_c_default
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

    input_power, input_pars = _power_input_term(power_input)
    input_0 = power_input isa Union{Nothing,Real} ? something(power_input, 0.0) : power_input(0.0)
    ic = point_kinetics_steady_state(P0; Lambda, beta_k, lambda_k, power_input=input_0)

    @variables begin
        P_neutron(t) = ic.P_neutron
        (C(t))[1:G] = ic.C_k
        # Algebraic, and read by whatever the reactor heats, so it is an unknown here rather
        # than an observable. `mtkcompile` tears it back out.
        P(t)
        # Observed diagnostics, assigned below; never on the RHS of another equation.
        beta_total(t)
        dPdt(t)
        reactivity(t)
    end

    β_k, λ_k, C_k = collect(β), collect(λ), collect(C)
    control_reactivity, control_pars, control_unknowns = control()
    ρ = control_reactivity
    β_sum = sum(β_k)
    Ṗ = (ρ - β_sum) / Λ * P_neutron + λ_k ⋅ C_k

    eqs = [
        D(P_neutron) ~ Ṗ
        D.(C_k) .~ β_k ./ Λ .* P_neutron .- λ_k .* C_k
        P ~ P_neutron + input_power
    ]
    obs = Equation[beta_total ~ β_sum, dPdt ~ Ṗ, reactivity ~ ρ]

    return System(
        eqs,
        t,
        [P_neutron; C_k; P; control_unknowns],
        [pars; control_pars; input_pars];
        observed=obs,
        name=name,
    )
end

"""
    point_kinetics_steady_state(P0; Lambda=U235_LAMBDA, beta_k=U235_BETA_K,
                                lambda_k=U235_LAMBDA_K, power_input=0.0) -> NamedTuple

Compute analytically correct initial conditions for the point kinetics equations at
criticality (rho=0). Essential because KINSOL finds the trivial zero-power solution when
given zero or poor initial conditions.

At steady state with rho=0, dC_k/dt = 0 gives: C_k = beta_k / (lambda_k * Lambda) * Pn.

`P0` is the total power the reactor is to sit at. When part of it comes from `power_input`,
fission only has to make up `Pn = P0 - power_input`, and the precursors are seeded off `Pn`:
a decaying fission product breeds no delayed neutrons. Feed the same `power_input` the
[`PointKinetics`](@ref) system was built with, evaluated at the initial time, and the
operating point satisfies `P ~ P_neutron + power_input` exactly.

# Arguments
- `P0`: total power at the operating point [W]
- `Lambda`: neutron generation time [s] (default U235_LAMBDA = 5.4e-5)
- `beta_k`: delayed neutron fractions [-] (default U235_BETA_K)
- `lambda_k`: precursor decay constants [1/s] (default U235_LAMBDA_K)
- `power_input`: the non-fission share of `P0` [W] (default 0.0, so fission makes all of it)

# Returns
NamedTuple `(P_neutron=Pn, C_k=Vector{Float64})`, with `Pn = P0 - power_input` the neutron
power and `C_k[i] = beta_k[i] / (lambda_k[i] * Lambda) * Pn`.
"""
function point_kinetics_steady_state(
    P0; Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K, power_input=0.0
)
    Pn = P0 - power_input
    C_k = [beta_k[i] / (lambda_k[i] * Lambda) * Pn for i in eachindex(beta_k)]
    return (P_neutron=Pn, C_k=C_k)
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

Return a `DifferentialEquations.ContinuousCallback` that fires when the neutron power
crosses `ctrl.state_machine.power_limit` from below (upward zero-crossing of
`P - power_limit`). On firing:
1. Calls `change_state(ctrl, t, P, dPdt)` to transition `ctrl.state` to `:SCRAM`.
2. If `terminate=true` (default), calls `terminate!(integrator)` to stop the solver early.

`ctrl.state_machine` must be a `SCRAMCondition` (constructed via `SCRAM_at_power`).

# Arguments
- `ssys`: compiled MTK system from `mtkcompile`. Used to eagerly resolve the integer index
  of `p_sym` in the ODE state vector at callback construction time.
- `p_sym`: the neutron power, a state of the compiled system: `ssys.P_neutron` when the
  kinetics are the root system, or `ssys.pk.P_neutron` inside a subsystem named `:pk`. The
  total `P` is computed from the states rather than being one, so it cannot be watched here.
- `ctrl`: `ReactivityController` whose `state_machine` is a `SCRAMCondition`.
- `terminate` (kwarg): `true` (default) stops solver early at SCRAM. Pass `false` to
  simulate the full post-SCRAM shutdown transient driven by negative control reactivity.

# Returns
`ContinuousCallback`, to pass as `solve_transient(...; callbacks=cb)`.

# Throws
- `ArgumentError`: if `p_sym` is not a state of `ssys`, such as the total `P`

# Example
```julia
# Standalone PK (PK is root system):
cb = scram_callback(ssys, ssys.P_neutron, ctrl)
sol = solve_transient(ssys, op, t_arr; callbacks=cb)

# Full loop (PK nested as :pk subsystem):
cb = scram_callback(ssys, ssys.pk.P_neutron, ctrl)

# Simulate full post-SCRAM shutdown (no early termination):
cb = scram_callback(ssys, ssys.pk.P_neutron, ctrl; terminate=false)
sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```
"""
function scram_callback(ssys, p_sym::Num, ctrl; terminate=true)
    plimit = ctrl.state_machine.power_limit
    p_idx = ModelingToolkit.variable_index(ssys, p_sym)
    p_idx === nothing && throw(
        ArgumentError(
            "$p_sym is not a state of the compiled system, so scram_callback cannot " *
            "watch it; pass the neutron power P_neutron",
        ),
    )

    condition = (u, t, integrator) -> u[p_idx] - plimit
    affect! = function (integrator)
        change_state(ctrl, integrator.t, plimit + 1.0, 0.0)
        return terminate && terminate!(integrator)
    end

    return ContinuousCallback(condition, affect!)  # upward crossing only (P - plimit: neg -> pos)
end

"""
    trip!(ctrl, t; state=:SCRAM) -> state

Put `ctrl` into `state` at time `t`, whatever its state machine says.

This is for trips the state machine cannot see, such as a low-flow signal, since the machine
is only handed power and its rate. It stamps `t_state` and logs the entry the way
[`change_state`](@ref) does, so a reactivity schedule and a `DecayHeatSource` read the trip
time off `ctrl` the same way either way.

A trip latches. Calling it again while `ctrl` is already in `state` changes nothing, so the
time of the first trip is the one that stays.

# Arguments
- `ctrl`: the `ReactivityController` to trip
- `t`: time of the trip [s]

# Keywords
- `state`: the state to enter (default `:SCRAM`)

# Returns
The state `ctrl` is in afterwards.
"""
function trip!(ctrl::ReactivityController, t_now; state=:SCRAM)
    ctrl.state == state && return ctrl.state
    ctrl.state = state
    ctrl.t_state = Float64(t_now)
    push!(ctrl.log, (state, Float64(t_now)))
    return ctrl.state
end

"""
    trip_callback(ssys, sym, threshold, ctrl; state=:SCRAM) -> ContinuousCallback

Trip `ctrl` when `sym` falls through `threshold`.

This is the low-flow trip a loss-of-flow case needs, which [`scram_callback`](@ref) cannot
give because it watches power rising. `sym` is any variable of the compiled system, a flow
or a temperature. The crossing is found by root-finding `sym` at the solver's trial states,
the way [`flapper_callback`](@ref) finds a flapper opening, so the trip time is exact
whether `sym` is a state or computed from one. Only a downward crossing trips, and
[`trip!`](@ref) latches it.

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `sym`: the watched variable, such as `ssys.ine.inlet.ṁ`
- `threshold`: the trip setpoint, in `sym`'s units
- `ctrl`: the `ReactivityController` to trip

# Keywords
- `state`: the state to trip into (default `:SCRAM`)

# Returns
A `ContinuousCallback`, for `solve_transient(...; callbacks=cb)`.
"""
function trip_callback(ssys, sym, threshold, ctrl::ReactivityController; state=:SCRAM)
    watched = ModelingToolkit.build_explicit_observed_function(ssys, sym)
    condition = (u, tt, integ) -> watched(u, integ.p, tt) - threshold
    affect_trip! = integ -> trip!(ctrl, integ.t; state=state)
    # (condition, up-crossing affect = nothing, down-crossing affect = trip)
    return ContinuousCallback(condition, nothing, affect_trip!)
end

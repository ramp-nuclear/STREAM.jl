# Phase 47: Temperature Feedback for PointKinetics — Research

**Researched:** 2026-04-04
**Domain:** ModelingToolkit.jl symbolic systems + Julia STREAM Point Kinetics extension
**Confidence:** HIGH

## Summary

Phase 47 extends the Phase 46 callable `PointKinetics(rho_c_fn; ...)` constructor with
per-cell temperature feedback from any number of Channel / ChannelAndContacts /
ChannelHeatFlux / HeatDiffusion components. All decisions are already locked in
47-CONTEXT.md (D-01 through D-10). The implementation is contained: it edits
`src/components/point_kinetics.jl`, adds one helper to `src/composition/helpers.jl`,
adds one export to `src/STREAM.jl`, and adds a new testset to `test/test_point_kinetics.jl`.
Components are unchanged.

The only non-trivial MTK work is creating **component-name-parameterized array
unknowns** (`T_source_<name>[1:n_flat]`) at construction time from a `Dict` whose keys
are uncompiled MTK Systems, and emitting `Equation`s that bind each `pk.T_source_ch[j]`
to `ch.T[j]` (1D) or `fuel.T[(jz-1)*nx+jx]` (2D flattened row-major). Both patterns exist
elsewhere in the codebase: HeatDiffusion (heat_diffusion.jl:114) creates `(T(t))[1:nz,1:nx]`;
Channel (channel.jl:42) creates `(T(t))[1:n]`; connection helpers return
`Vector{Equation}` already (helpers.jl:168-175).

**Primary recommendation:** Follow the Phase 46 callable constructor verbatim, adding
two preprocessing passes at the top (shape-check + flatten alpha/T_ref, create T_source
arrays), then modify the three equations that reference rho (ODE, dPdt obs, reactivity
obs) to add a `+ feedback_expr` term where `feedback_expr` is a hand-built MTK symbolic
sum. No new MTK patterns required.

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** `temp_worth` + `ref_temp` kwargs on existing callable constructor; both are
  `Dict{System, Union{Real, AbstractArray}}` keyed by uncompiled MTK Systems. Scalar
  broadcasts; 1D vector matches channel n; 2D matrix matches HeatDiffusion (nz, nx).
  `temp_worth=nothing` (default) → Phase 46 behavior unchanged.
- **D-02:** `rho_total(t) = rho_val + rho_c_fn(t) + sum_k(dot(alpha_k_flat, T_source_k - T_ref_k_flat))`.
  Sign convention: negative alpha = stabilizing. Matches Python STREAM.
- **D-03:** For each component in `temp_worth`, PK creates a flat unknown array
  `T_source_<comp_name>[1:n_flat](t)`. Channel: n_flat = n_cells (1D). HeatDiffusion:
  n_flat = nz * nx (2D flattened **row-major**). These are free unknowns in the
  standalone PK system; binding equations are added by `connect_temperature_feedback`.
- **D-04:** New helper `connect_temperature_feedback(pk, temp_worth) -> Vector{Equation}`
  in `src/composition/helpers.jl`. Generates one equation per cell binding
  `pk.T_source_<name>[j] ~ comp.T[j]` (1D) or `pk.T_source_<name>[j] ~ comp.T[jz, jx]`
  with `j = (jz-1)*nx + jx` (row-major 2D).
- **D-05:** Channel, ChannelAndContacts, ChannelHeatFlux, HeatDiffusion are unmodified.
  Connection helper uses the components' existing `T` symbolic via `getproperty(comp, :T)`.
- **D-06:** Add-on to Phase 46 callable constructor only. Phase 45 scalar constructor
  unchanged.
- **D-07:** alpha weights + ref_temp are **inlined constants** in the symbolic equations
  (NOT MTK `@parameters`). Matches power_shape inlining in HeatDiffusion. Rationale:
  avoids 28+ extra MTK parameters for a realistic core.
- **D-08:** `reactivity` observed variable updated to include temperature feedback sum.
- **D-09:** All changes in `src/components/point_kinetics.jl` +
  `src/composition/helpers.jl`. Export `connect_temperature_feedback` in `src/STREAM.jl`.
  Tests: new `@testset "TF-01: Temperature Feedback"` in `test/test_point_kinetics.jl`.
- **D-10:** API mirrors Python STREAM `PointKinetics(temp_worth={ch: alpha}, ref_temp={ch: T0})`.

### Claude's Discretion
- Shape-check mechanics and error messages.
- Whether to dispatch `connect_temperature_feedback` on the component type vs. probe
  `size(comp.T)` — both workable, but probing by `ndims(size(alpha))` (as suggested in
  D-04) or by examining the T variable's size via `Symbolics.shape` is the cleaner route.
- Internal naming of flattened alpha/T_ref vectors (e.g., `alpha_flat_$(name)`).
- Whether to deduplicate the temp-feedback expression between the ODE and the two
  observed equations via a local Julia variable (yes — matches Phase 46 pattern where
  `precursor_source` is factored).

### Deferred Ideas (OUT OF SCOPE)
- SCRAM callback wiring (SymbolicContinuousCallback calling change_state) — Phase 49.
- `TemperatureFeedbackPort` connector type — unnecessary given T_source unknowns.
- Doppler broadening (non-linear feedback) — v1.0+.
- `temp_worth` as MTK parameters (tunable at solve time) — deferred until solve-time
  tuning is required.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| TF-01 | Callable PK constructor accepts `temp_worth=Dict(...)`/`ref_temp=Dict(...)` kwargs; `temp_worth=nothing` falls back to Phase 46 | Phase 46 constructor at `src/components/point_kinetics.jl:144-206` — drop in two kwargs, guard all new logic with `if temp_worth === nothing` |
| TF-02 | Scalar broadcasts; 1D vector per channel cell; 2D matrix per HeatDiffusion (flattened row-major); shape mismatch → `ArgumentError` at construction | HeatDiffusion uses `power_shape` inlining at `heat_diffusion.jl:40`; same pattern works for alpha. Shape check is a pure-Julia `size(alpha)` vs. introspected component shape |
| TF-03 | Missing `ref_temp` key (or `ref_temp=nothing`) defaults to zero reference | Single `get(ref_temp_dict, key, 0.0)`-style lookup; default dict to `Dict()` if `nothing` |
| TF-04 | `connect_temperature_feedback(pk, temp_worth) -> Vector{Equation}` binds `pk.T_source_<name>[j]` to `comp.T[j]` (1D) or `comp.T[jz,jx]` (2D row-major) | helpers.jl:168-175 already returns `Equation[]` vectors — follow `symmetric_plate` pattern; access T via `getproperty(comp, :T)` |
| TF-05 | Channel / ChannelAndContacts / ChannelHeatFlux / HeatDiffusion unchanged; all existing tests still pass | D-05 — connection helper only reads `.T` symbolic which already exists on all four components |
| TF-06 | `pk.reactivity` observed variable includes temperature contribution; verifiable post-solve via `sol[pk.reactivity, :]` | D-08 — update the single `reactivity ~ ...` observed equation (point_kinetics.jl:199) |
| TF-07 | Analytical validation: strong negative alpha + step reactivity → power peaks then stabilizes, does not diverge. Mirror Python STREAM integration tests (test_integrations.py:352-428) | See "Validation Architecture" section below |

## Standard Stack

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | (project-pinned, see Project.toml) | Symbolic DAE/ODE system builder | Already the MTK backbone of STREAM.jl; no new deps [VERIFIED: src/STREAM.jl:2] |
| Symbolics.jl | (transitive via MTK) | `@variables`, `@parameters`, symbolic Num arithmetic | Used throughout; `@register_symbolic` for opaque fns [VERIFIED: src/STREAM.jl:4] |

**No new dependencies.** Phase 47 adds zero new packages.

## Architecture Patterns

### Project Structure (unchanged by Phase 47)
```
src/
├── components/
│   └── point_kinetics.jl    # ADD temp_worth/ref_temp kwargs here
├── composition/
│   └── helpers.jl           # ADD connect_temperature_feedback here
└── STREAM.jl                # ADD export connect_temperature_feedback
test/
└── test_point_kinetics.jl   # ADD @testset "TF-01: Temperature Feedback"
```

### Pattern 1: Component-Name-Parameterized Array Unknowns at Construction Time
**What:** Loop over `temp_worth` keys, build per-component array unknowns whose **names
depend on the component's `name` Symbol**. Each component's T_source array has length
`prod(size(alpha_flattened))`. Unknowns are created via interpolated `@variables` at
runtime — not via the macro form at parse time.

**When to use:** Whenever a component needs to declare unknowns whose count AND names
depend on runtime data (here: the `temp_worth` dict).

**Approach (matches HeatDiffusion dynamic-sized T):**

```julia
# Collect all T_source unknowns across components.
T_source_vars = Num[]                       # flat list for the `unknowns` vector
T_source_by_comp = Dict{Symbol, Vector{Num}}()  # name -> that component's T_source vars
alpha_flat_by_comp  = Dict{Symbol, Vector{Float64}}()
Tref_flat_by_comp   = Dict{Symbol, Vector{Float64}}()

if temp_worth !== nothing
    ref_dict = ref_temp === nothing ? Dict() : ref_temp
    for (comp, alpha_raw) in temp_worth
        comp_name = nameof(comp)             # Symbol of the uncompiled System
        alpha_flat, n_flat = _flatten_weights(alpha_raw, comp)   # D-02, D-03
        Tref_raw   = get(ref_dict, comp, 0.0)
        Tref_flat  = _flatten_weights_like(Tref_raw, alpha_flat) # matches alpha_flat length
        # Create n_flat unknowns named T_source_<comp_name>[1:n_flat]
        var_sym = Symbol(:T_source_, comp_name)                 # e.g. :T_source_ch
        Tsrc    = only(@variables $(var_sym)(t)[1:n_flat])       # array unknown
        append!(T_source_vars, collect(Tsrc))
        T_source_by_comp[comp_name] = collect(Tsrc)
        alpha_flat_by_comp[comp_name] = alpha_flat
        Tref_flat_by_comp[comp_name]  = Tref_flat
    end
end
```

**Source pattern:** `src/components/heat_diffusion.jl:113-114` creates `(T(t))[1:nz,1:nx]`.
Note the `@variables` macro supports interpolation of Symbol-valued variable names via
the standard Symbolics splice form `$(var_sym)(t)[1:n_flat]`.
[VERIFIED: src/components/heat_diffusion.jl, src/components/channel.jl:42]

### Pattern 2: Building the Feedback Sum Expression
**What:** Construct `Num` symbolic expression for
`sum_k(dot(alpha_k_flat, T_source_k .- T_ref_k_flat))` by iterating in Julia
and accumulating into a `Num` variable.

```julia
feedback_expr = 0                            # Julia 0 promotes to Num on first add
for (cname, Tsrc) in T_source_by_comp
    alpha = alpha_flat_by_comp[cname]
    Tref  = Tref_flat_by_comp[cname]
    for j in eachindex(Tsrc)
        feedback_expr = feedback_expr + alpha[j] * (Tsrc[j] - Tref[j])
    end
end
```

This `feedback_expr` is an MTK `Num` tree composed of inlined `Float64` alpha/Tref
values and symbolic T_source unknowns. It mirrors how `power_shape[i,j]` is inlined
in `_diffusion_eqs` at heat_diffusion.jl:40. [VERIFIED: src/components/heat_diffusion.jl:40]

### Pattern 3: Modifying the Callable PK Power ODE + Observables
**What:** Replace the three occurrences of `rho_val + rho_c_fn(t)` in the callable
constructor with `rho_val + rho_c_fn(t) + feedback_expr`.

**Current (point_kinetics.jl:187, 198, 199):**
```julia
Dt(P) ~ (rho_val + rho_c_fn(t) - beta_sum) / Lambda_gen * P + precursor_source
dPdt ~ (rho_val + rho_c_fn(t) - beta_sum) / Lambda_gen * P + precursor_source
reactivity ~ rho_val + rho_c_fn(t)
```

**After Phase 47:**
```julia
Dt(P) ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source
dPdt ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source
reactivity ~ rho_val + rho_c_fn(t) + feedback_expr
```

When `temp_worth===nothing`, `feedback_expr` is the Julia literal `0` and these
equations reduce exactly to Phase 46. [VERIFIED: src/components/point_kinetics.jl:187,198,199]

### Pattern 4: Connection Helper Returns Vector{Equation}
**What:** Mirror `symmetric_plate` — receive uncompiled System instances, read their
existing `.T` symbolic via `getproperty`, build `Equation[]` using the `~` operator.

```julia
function connect_temperature_feedback(pk, temp_worth)
    eqs = Equation[]
    for (comp, alpha_raw) in temp_worth
        comp_name = nameof(comp)
        T_sym = getproperty(comp, :T)           # component's existing T unknown
        pk_T_source = getproperty(pk, Symbol(:T_source_, comp_name))
        if ndims(alpha_raw) == 2 || (alpha_raw isa AbstractArray && ndims(size(T_sym)) > 1)
            # HeatDiffusion: 2D T[1:nz, 1:nx], flatten row-major
            nz, nx = size(T_sym)
            for jz in 1:nz, jx in 1:nx
                j_flat = (jz - 1) * nx + jx
                push!(eqs, pk_T_source[j_flat] ~ T_sym[jz, jx])
            end
        else
            # Channel/ChannelAndContacts/ChannelHeatFlux: 1D T[1:n]
            n = length(T_sym)
            for j in 1:n
                push!(eqs, pk_T_source[j] ~ T_sym[j])
            end
        end
    end
    return eqs
end
```

**Dispatch note:** Prefer introspecting the **component's** T shape (which is
authoritative) rather than the alpha shape (which might be a scalar broadcast). Use
`Symbolics.shape(T_sym)` or `ndims(T_sym)` — the Channel `T` is 1D, HeatDiffusion `T`
is 2D. [VERIFIED: src/components/channel.jl:42, src/components/heat_diffusion.jl:114]

Verified usage pattern: tests access `ssys.hd.T[i,j]` (2D) and `ssys.ch.T[i]` (1D)
at `test/test_heat_diffusion.jl:83,88` and `test/test_channel.jl:57` respectively.

### Pattern 5: `unknowns` vector includes T_source array
Append the flat `T_source_vars` (from Pattern 1) to the positional `unknowns` list
passed to `System(...)`. The existing call at point_kinetics.jl:202-204 is:

```julia
System(eqs, t, [P, C_1, C_2, C_3, C_4, C_5, C_6, T_source_vars...],   # ← new
       [rho_val, Lambda_gen, beta_1, ..., rho_c_fn];
       observed=obs, name=name)
```

This is identical to how HeatDiffusion builds `all_vars = vec(collect(T))` at
`src/components/heat_diffusion.jl:132`.

### Anti-Patterns to Avoid
- **Don't** try to make alpha/T_ref MTK `@parameters` — D-07 explicitly rejects this.
  28+ parameters on a realistic core is noise for no benefit in this phase.
- **Don't** modify Channel/ChannelAndContacts/ChannelHeatFlux/HeatDiffusion — D-05.
- **Don't** add a new `TemperatureFeedbackPort` connector — D-04 uses unknowns + binding
  equations instead (deferred idea).
- **Don't** validate `power_shape` normalization (project rule: trust the caller). Same
  applies to alpha — do shape-checks only, not value checks. [VERIFIED: MEMORY.md
  `feedback_power_shape_trust_caller`]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Flattening scalar → vector broadcast | Custom scalar-detect loop | `alpha isa Real ? fill(Float64(alpha), n) : vec(Float64.(alpha))` | Standard Julia |
| 2D → 1D flattening | Manual index math loops | `vec(transpose(M))` for row-major, or `[M[i,j] for i in 1:nz for j in 1:nx]` | The iterator comprehension IS row-major by construction |
| Building symbolic sum | Use `sum()` on Symbolics array | Julia accumulator loop with `+` | Symbolics.sum can create opaque expressions that MTK struct-analysis handles poorly; explicit `+=` accumulator is a documented safe pattern in this codebase (see `precursor_source` at point_kinetics.jl:84) |
| `dot()` symbolic product | LinearAlgebra.dot on Num arrays | Loop-accumulate `alpha[j] * (Tsrc[j] - Tref[j])` | Same as above — matches project style |

**Key insight:** MTK prefers concrete Julia accumulator loops for building symbolic
expressions that will be compiled. Avoid `LinearAlgebra.dot` and `sum` over Symbolics
arrays to match the existing `precursor_source` pattern in the same file.

## Common Pitfalls

### Pitfall 1: Row-Major Flattening Confusion
**What goes wrong:** Julia arrays are column-major; a user passing a 2D alpha matrix
expects row-major (`j = (jz-1)*nx + jx`) but `vec(M)` is column-major
(`j = (jx-1)*nz + jz`). Mismatch → wrong alpha applied to wrong cell.
**Why it happens:** D-03 locks **row-major** flattening explicitly; Julia's natural
`vec` is column-major.
**How to avoid:** Use either `vec(transpose(M))` or the iterator
`[M[i,j] for i in 1:nz for j in 1:nx]`. Both produce row-major. Apply the SAME rule in
`connect_temperature_feedback` when binding `T[jz,jx]` to `T_source[j]`:
`j_flat = (jz-1)*nx + jx`. Document the rule in a source comment.
**Warning signs:** TF-07 validation test fails with anomalously different symmetric
power when alpha is symmetric.

### Pitfall 2: Shape-Check Before Flatten
**What goes wrong:** User passes `alpha = [0.001, 0.002]` but component has `n=7`; the
accumulator loop silently iterates over 2 elements and binds T_source[3..7] to nothing.
**Why it happens:** Missing assertion after Pattern 1's flatten step.
**How to avoid:** After flattening, assert `length(alpha_flat) == expected_n_flat` and
raise `ArgumentError` with component name + expected/actual shapes. Same assertion
for `ref_temp` flat length. Per TF-02.
**Warning signs:** `BoundsError` deep inside MTK compile OR silently-incorrect
simulation results.

### Pitfall 3: Component Key Identity (Uncompiled System Equality)
**What goes wrong:** User passes the uncompiled `ch` system as a Dict key, then
later passes `mtkcompile(ch)` expecting the lookup to hit. Or rebuilds the System and
expects hash-equality.
**Why it happens:** `Dict{System, ...}` hashes by object identity; each `@named` call
produces a distinct System instance. MTK Systems do not have custom `hash`/`isequal`.
**How to avoid:** Document that the SAME System object constructed with `@named` must
be used throughout (for both the `compose`/`symmetric_plate` call and the
`temp_worth` Dict key). The pattern already holds for `symmetric_plate(cac, fuel)` so
users are familiar. `connect_temperature_feedback(pk, temp_worth)` pulls component
references from the Dict directly, so there is no lookup ambiguity inside the helper.
**Warning signs:** Key not found when iterating; or mysteriously missing feedback
contribution.

### Pitfall 4: `getproperty(comp, :T)` on Uncompiled System
**What goes wrong:** Depending on MTK internals, `getproperty(uncompiled_sys, :T)` may
return a different kind of symbolic reference than `getproperty(compiled_sys, :T)`.
**Why it happens:** `compose()` namespaces subsystem unknowns; before compose, the
component's `T` is the raw unknown; after compose, accessing via the parent requires
`ch.T`.
**How to avoid:** `connect_temperature_feedback` is designed to be called with the SAME
uncompiled System instances the user built (D-04 workflow). The helper builds
equations against `comp.T` from the uncompiled object, and those equations are passed
into `System(...; systems=[pk, ch, fuel, ...])` which applies namespacing
automatically. This is exactly the pattern `symmetric_plate` uses. See the user
workflow in 47-CONTEXT.md D-04.
**Warning signs:** "Unknown variable" errors at `mtkcompile` time referring to
`ch₊T[i]` not being found.

### Pitfall 5: T_source Unknowns Unbound in Standalone PK Compilation
**What goes wrong:** `mtkcompile(pk)` alone (without the connection equations) leaves
T_source_<name> as free unknowns → MTK errors with "system is underdetermined"
(7 + n_flat unknowns but only 7 equations).
**Why it happens:** D-03 says T_source unknowns gain binding equations only in the
composed system. Standalone PK is intentionally incomplete.
**How to avoid:** Expected behavior. Test TF-01 must use the composed-system workflow
(`System([conn_eqs...], t, [], []; systems=[pk, ch, fuel, ...])` → `mtkcompile`).
Add a note in the PK docstring: "When `temp_worth` is provided, the resulting System
has free T_source unknowns that MUST be bound by calling `connect_temperature_feedback`
and wrapping in a composed System before `mtkcompile`."
**Warning signs:** `mtkcompile(pk)` on a feedback-enabled PK throws a structural error.
Also: users who forget `connect_temperature_feedback(pk, temp_worth)` get the same
error even with composition in place.

### Pitfall 6: Symbol Interpolation in @variables Inside a Function
**What goes wrong:** `@variables` at the top level is a macro expanded at parse time;
using `Symbol(:T_source_, comp_name)` at runtime requires the `@variables` splice form.
**Why it happens:** `@variables T_source_ch(t)[1:7]` is parse-time; for runtime
interpolation we need `@variables $(dynamic_sym)(t)[1:n]`.
**How to avoid:** Use the `Symbolics.variable(name, ...)` function or the documented
interpolation form:
```julia
var_sym = Symbol(:T_source_, comp_name)
Tsrc = only(@variables $(var_sym)(t)[1:n_flat])
```
Alternative (if the splice form is problematic): call `Symbolics.variables(var_sym,
1:n_flat; T=Real)` with a dependency on `t`, then use `Num.(...)`. The first form is
used inside MTK itself and should work. Test with a scratch script early.
**Warning signs:** `UndefVarError` or unexpected `Term` construction.

## Code Examples

### Flatten weights (row-major for 2D)
```julia
# Source: derived from src/components/heat_diffusion.jl:40 inlining convention
function _flatten_weights(raw, comp)
    T_sym = getproperty(comp, :T)
    if ndims(T_sym) == 2                               # HeatDiffusion
        nz, nx = size(T_sym)
        if raw isa Real
            return (fill(Float64(raw), nz*nx), nz*nx)
        elseif raw isa AbstractMatrix && size(raw) == (nz, nx)
            return ([Float64(raw[i,j]) for i in 1:nz for j in 1:nx], nz*nx)  # row-major
        else
            throw(ArgumentError("alpha for $(nameof(comp)) must be scalar or $(nz)x$(nx) matrix, got $(size(raw))"))
        end
    else                                               # Channel family
        n = length(T_sym)
        if raw isa Real
            return (fill(Float64(raw), n), n)
        elseif raw isa AbstractVector && length(raw) == n
            return (Float64.(raw), n)
        else
            throw(ArgumentError("alpha for $(nameof(comp)) must be scalar or length-$n vector, got $(summary(raw))"))
        end
    end
end
```

### Callable constructor update (sketch)
```julia
# Source: extends src/components/point_kinetics.jl:144-206
function PointKinetics(rho_c_fn::Any; name, rho_val=0.0,
                         Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K,
                         temp_worth=nothing, ref_temp=nothing)
    Dt = Differential(t)
    FType = typeof(rho_c_fn)
    # ... existing @parameters block ...
    # ... existing @variables block (P, C_1..C_6, beta_total, dPdt, reactivity) ...

    # Phase 47: build T_source unknowns and feedback_expr
    T_source_vars = Num[]
    feedback_expr = 0
    if temp_worth !== nothing
        ref_dict = ref_temp === nothing ? Dict() : ref_temp
        for (comp, alpha_raw) in temp_worth
            cname = nameof(comp)
            alpha_flat, n_flat = _flatten_weights(alpha_raw, comp)
            Tref_raw = get(ref_dict, comp, 0.0)
            Tref_flat, _ = _flatten_weights_scalar_or_vector(Tref_raw, n_flat, cname)
            var_sym = Symbol(:T_source_, cname)
            Tsrc = only(@variables $(var_sym)(t)[1:n_flat])
            append!(T_source_vars, collect(Tsrc))
            for j in 1:n_flat
                feedback_expr = feedback_expr + alpha_flat[j] * (Tsrc[j] - Tref_flat[j])
            end
        end
    end

    # ... existing beta_sum, precursor_source ...
    eqs = Equation[
        Dt(P) ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source,
        # ... 6 precursor ODEs unchanged ...
    ]
    obs = Equation[
        beta_total ~ beta_sum,
        dPdt ~ (rho_val + rho_c_fn(t) + feedback_expr - beta_sum) / Lambda_gen * P + precursor_source,
        reactivity ~ rho_val + rho_c_fn(t) + feedback_expr,
    ]
    System(eqs, t, [P, C_1, C_2, C_3, C_4, C_5, C_6, T_source_vars...],
           [rho_val, Lambda_gen, beta_1, ..., rho_c_fn]; observed=obs, name=name)
end
```

### User workflow (D-04)
```julia
# Source: 47-CONTEXT.md D-04
@named ch   = ChannelAndContacts(n=7, geometry=geom)
@named fuel = HeatDiffusion(nz=7, nx=3, ...)
@named pk   = PointKinetics(ctrl;
                            temp_worth = Dict(ch   => fill(-0.001, 7),
                                              fuel => fill(-0.002, 7, 3)),
                            ref_temp   = Dict(ch   => fill(313.0, 7),
                                              fuel => fill(600.0, 7, 3)))
rods  = symmetric_plate(ch, fuel; name=:rods)
conns = connect_temperature_feedback(pk, Dict(ch => ..., fuel => ...))
full = compose_systems(rods, pk; connections=conns, name=:core)
# full has pk.T_source_ch[j] ~ ch.T[j] and pk.T_source_fuel[j] ~ fuel.T[row,col] bound
ssys = mtkcompile(full)
```

## State of the Art

| Old | Current | Impact |
|-----|---------|--------|
| Scalar `rho` parameter (Phase 45) | Callable `rho_c_fn(t)` (Phase 46) + temperature feedback (Phase 47) | Full coupling between neutronics and thermal-hydraulics state |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `@variables $(dynamic_sym)(t)[1:n]` splice-interpolation works inside a function for a runtime Symbol | Pattern 1, Pitfall 6 | If wrong: fall back to `Symbolics.variable(Symbol, ...)` + manual `Num` wrapping, or accept a pre-built array from the user. Should be tested in a scratch script at start of implementation. [ASSUMED — not grep'd against MTK source in this session] |
| A2 | `getproperty(uncompiled_system, :T)` returns a symbolic array usable in `Equation` RHS, identical to how `port(cac, :thermal_left, i)` works in `symmetric_plate` | Pattern 4 | If wrong: the connection helper pattern matches `symmetric_plate` which IS verified working (helpers.jl:168-175 + test_composition.jl). Very low risk. [VERIFIED by analogy to symmetric_plate] |
| A3 | Channel/ChannelAndContacts/ChannelHeatFlux all declare `T` as a 1D symbolic array accessible as `comp.T[i]` | Pattern 4 | Direct grep shows: channel.jl:42, thermal_channel.jl:65 (CAC), thermal_channel.jl:246 (CHF) — all declare `(T(t))[1:n]`. [VERIFIED] |
| A4 | HeatDiffusion declares `T` as 2D `(T(t))[1:nz, 1:nx]`, accessible as `fuel.T[jz, jx]` | Pattern 4 | heat_diffusion.jl:114. [VERIFIED] |
| A5 | The `precursor_source` Julia-accumulator-in-Num pattern generalizes to sums of arbitrary length | Pattern 2 | precursor_source at point_kinetics.jl:84-85 is 6 terms; the generalization is mechanical. [VERIFIED by analogy] |
| A6 | Free unknowns in a standalone PK System are tolerated by MTK as long as they are bound before `mtkcompile` of the composed system | Pitfall 5 | True for ThermalPort variables in Channel (wall T becomes bound by connect()). T_source behaves the same way because it is declared at the System level but left without a defining equation. [ASSUMED — structurally identical to port variables but no direct test case] |

## Open Questions

None — all architectural decisions are locked by 47-CONTEXT.md. Implementation
mechanics are documented above. Proceed to planning.

## Environment Availability

No external dependencies for this phase — pure Julia/MTK code changes. SKIPPED.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test.jl (Julia stdlib) |
| Config file | test/runtests.jl (include-based orchestrator) |
| Quick run command | `julia --project -e 'using Pkg; Pkg.test(test_args=["test_point_kinetics.jl"])'` OR `julia --project=. test/test_point_kinetics.jl` (direct) |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| TF-01 | Callable constructor with `temp_worth=nothing` compiles identically to Phase 46; with `temp_worth=Dict(...)` adds T_source unknowns | unit | `julia --project test/test_point_kinetics.jl` | yes — extend `test_point_kinetics.jl` |
| TF-02 | Scalar alpha broadcasts; 1D vector matches n; 2D matrix matches (nz,nx); shape mismatch raises `ArgumentError` | unit (4 sub-tests) | same | yes — extend |
| TF-03 | `ref_temp=nothing` or missing key defaults to zero reference; full T contributes | unit | same | yes — extend |
| TF-04 | `connect_temperature_feedback(pk, temp_worth)` returns `Vector{Equation}` of correct length; 1D channel + 2D HeatDiffusion both work | unit + integration | same | yes — extend |
| TF-05 | All existing tests continue to pass | regression | `julia --project -e 'using Pkg; Pkg.test()'` | yes — full suite |
| TF-06 | `sol[pk.reactivity, :]` post-solve equals `rho_val + rho_c_fn(t) + feedback` | integration | same | yes — extend |
| TF-07 | Step reactivity insertion with strong negative alpha → power peaks then stabilizes (does not diverge). Fuel feedback: T_fuel → T_ref ⇒ P→0. Coolant feedback: T_cool → T_ref ⇒ P→0 | integration (analytical) | same | yes — extend |

### Sampling Rate
- **Per task commit:** `julia --project test/test_point_kinetics.jl` (runs only PK + RC tests, fast: <30s)
- **Per wave merge:** full `Pkg.test()` (runs all 1344+ tests, ensures TF-05 regression)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- None — `test/test_point_kinetics.jl` exists and is the canonical location. All TF-0x
  tests are new `@testset "TF-...` blocks added inside the top-level `@testset
  "PointKinetics"`. No new fixtures needed.
- **Optional scratch script** recommended before Task 1: verify `@variables
  $(dynamic_sym)(t)[1:n]` splice interpolation works in function scope — if it fails,
  Pattern 1 needs adjustment (see Pitfall 6 fallback). Five minutes, saves rework.

## Project Constraints (from CLAUDE.md)

These directives govern the phase implementation:

- **File location:** New component logic stays in `src/components/point_kinetics.jl`
  (already the canonical file for PK). New composition helper in
  `src/composition/helpers.jl`. [CLAUDE.md "Where new code goes"]
- **Test mirroring:** `test_point_kinetics.jl` extends for PK changes; helper test
  goes in `test_composition.jl` OR `test_point_kinetics.jl` (latter preferred per
  D-09). [CLAUDE.md "Test placement rule"]
- **Exports centralized:** `connect_temperature_feedback` is added to the export list
  in `src/STREAM.jl` ONLY — no `export` statement inside `helpers.jl`. [CLAUDE.md
  "Exports" + D-09]
- **Keyword arguments for multi-parameter constructors:** `temp_worth` and `ref_temp`
  are kwargs (D-01), consistent with the existing callable PK constructor which is
  already keyword-heavy. [CLAUDE.md Component authoring]
- **Docstring requirements:** Every exported name needs docstring with description, #
  Arguments, # Returns. Applies to the updated `PointKinetics(rho_c_fn; ...)` and the
  new `connect_temperature_feedback`. [CLAUDE.md "Exports"]
- **ASCII variable names only:** Use `alpha`, `beta`, `rho` — no Unicode. [MEMORY.md
  `feedback_ascii_variable_names`]
- **Trust the caller, no value validation:** Shape-check alpha/ref_temp but do NOT
  assert physical reasonableness (e.g., alpha < 0, Tref > 0). Matches
  `power_shape`/`material matrix` rule. [MEMORY.md `feedback_power_shape_trust_caller`]
- **mtkcompile before solve:** Required; already documented throughout. [CLAUDE.md MTK
  Patterns]
- **@observed for diagnostics:** `reactivity`, `dPdt`, `beta_total` are already
  observed — Phase 47 updates `reactivity` in place. [CLAUDE.md MTK Patterns]
- **Inlined constants:** alpha/ref_temp are inlined in symbolic equations (D-07),
  matching the `power_shape`/`beta_k`/`lambda_k` inlining convention. [CLAUDE.md MTK
  Patterns + D-07]

## Sources

### Primary (HIGH confidence)
- `src/components/point_kinetics.jl` (lines 144-206): Phase 46 callable constructor to
  extend
- `src/components/heat_diffusion.jl` (lines 98-136): dynamic-size MTK array unknowns
  (`(T(t))[1:nz,1:nx]`), `power_shape` inlining pattern
- `src/components/channel.jl` (line 42): 1D `(T(t))[1:n]` Channel unknown declaration
- `src/components/thermal_channel.jl` (lines 65, 246): ChannelAndContacts + ChannelHeatFlux `T[1:n]`
- `src/composition/helpers.jl` (lines 168-245): `symmetric_plate`, `plate`,
  `one_sided_connection`, `compose_systems` — Equation-returning helper patterns
- `src/STREAM.jl` (lines 28-40): export list structure
- `test/test_point_kinetics.jl`: existing testset structure; PK-03 callable tests show
  `Pair{Any,Any}[]` op-dict pattern
- `test/test_heat_diffusion.jl` (line 83), `test/test_channel.jl` (line 57): confirmed
  access patterns `ssys.hd.T[i,j]` and `ssys.ch.T[i]`
- `.planning/phases/47-temperature-feedback-point-kinetics/47-CONTEXT.md`: all locked decisions
- `CLAUDE.md`: file structure, exports, MTK patterns, component authoring conventions
- MEMORY.md entries: `feedback_power_shape_trust_caller`, `feedback_ascii_variable_names`

### Secondary (MEDIUM confidence)
- `~/projects/STREAM/stream/calculations/point_kinetics.py` (lines 201-294, 346-368):
  Python STREAM `PointKinetics.__init__`, `reactivity()`, `temperature_reactivity()` —
  API shape reference for D-01/D-02/D-10
- `~/projects/STREAM/tests/test_general/test_integrations.py` (lines 201-267, 352-428):
  `test_channel_point_kinetics`, `test_power_is_negligible_for_negative_Tfuel_feedback...`,
  `test_power_is_negligible_for_negative_Tcool_feedback...` — validation test design
  blueprints for TF-07

### Tertiary (LOW confidence)
- Assumption A1 (Symbolics @variables splice interpolation in function scope) —
  confirmed widely used in MTK ecosystem but not directly grep'd against MTK source in
  this session. Scratch-verify at start of implementation (5 min cost).

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, all patterns exist in-repo
- Architecture (T_source unknowns + feedback_expr + helper): HIGH — directly mirrors
  HeatDiffusion (array unknowns), point_kinetics.jl precursor_source (accumulator), and
  symmetric_plate (Vector{Equation}-returning composition helper)
- Pitfalls: HIGH for #1-#5 (grounded in project conventions); MEDIUM for #6 (splice
  interpolation — verified by analogy, recommend scratch-check)
- Validation: HIGH — TF-07 has two verbatim Python reference tests to port

**Research date:** 2026-04-04
**Valid until:** Implementation complete (stable — no external library churn)

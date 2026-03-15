# Phase 15: Composition Helpers & QoL — Research

**Researched:** 2026-03-15
**Domain:** ModelingToolkit.jl acausal system composition, observed variables, Julia MTK port wiring
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Helpers take **pre-built component instances**, not kwargs-through:
  ```julia
  cac  = ChannelAndContacts(; name=:ch, n=5, geometry=geom, htc_correlation=rd.htc, ...)
  fuel = HeatDiffusion(;      name=:fuel, nz=5, nx=3, ...)
  sys  = symmetric_plate(cac, fuel; name=:plate)
  ```
- User names their components before passing in — helpers compose them as-is
- All helpers return a **raw `ODESystem`** via `compose()` — no hidden compilation
- `build_initializeprob=false` must be the default in any solve helpers called downstream
- `plate(ch_left, ch_right, fuel; name)` connects `ch_left.thermal_right[i] ↔ fuel.thermal_left[i]` and `ch_right.thermal_left[i] ↔ fuel.thermal_right[i]`
- `one_sided_connection(channel, fuel, side=:left; name)` connects the specified side only
- No n/geometry validation inside helpers — caller ensures matching `n` and `nz`
- `compose_systems(sys_a, sys_b, connections; name)` wraps `ODESystem(connections, t, systems=[sys_a, sys_b]; name=name)`
- `compose_systems` accepts variadic systems
- @observed variables to declare: Re[i], Nu[i], h_tc_left[i], h_tc_right[i], T_wall_left[i], T_wall_right[i], Pe[i], velocity[i], q_wall_left[i], q_wall_right[i]
- `@observed` declared using the `observed` keyword in the `ODESystem` constructor inside `ChannelAndContacts`
- `check_gravity_mismatch(sys::ODESystem) -> Symbol` — returns `:ok` or `:mismatch`; algorithm: substitute `mdot=0` into all pressure equations and check consistency
- `port(sys, :thermal_left, i)` wraps `getproperty(sys, Symbol(:thermal_left, i))`
- Exports in `src/STREAM.jl`: add `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`, `check_gravity_mismatch`, `port`

### Claude's Discretion

- Exact Julia file organization (new file for helpers vs. append to components.jl or solvers.jl)
- Whether `compose_systems` takes `systems...` as a splatted first argument or a `Vector{ODESystem}`
- Exact expression for `h_tc_left[i]` vs `h_tc_right[i]`
- Exact residual threshold for `check_gravity_mismatch` `:ok` vs `:mismatch` decision
- Whether `q_wall_left[i]` is `thermal_left[i].Q_flow / cell_area` or derived differently

### Deferred Ideas (OUT OF SCOPE)

- None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| COMP-01 | `symmetric_plate(channel, fuel)` returns a pre-wired solvable ODESystem (HeatDiffusion both sides connected to same ChannelAndContacts) | MTK `System(conns, t; systems=[cac, hd])` pattern confirmed working; wiring via `getproperty(sys, Symbol(:thermal_left, i))` |
| COMP-02 | `plate(ch_left, ch_right, fuel)` returns a pre-wired ODESystem (two independent channels on each side of one plate) | Same wiring pattern; `ch_left.thermal_right[i] ↔ hd.thermal_left[i]`; confirmed via existing VAL-01 test |
| COMP-03 | `one_sided_connection(channel, fuel, side=:left)` returns a single-side pre-wired ODESystem | Same pattern; `side` kwarg selects which face to wire; other face left unconnected (adiabatic by MTK default) |
| COMP-04 | `compose_systems(sys_a, sys_b, connections)` merges two ODESystems with port connection list | `System(connections, t; systems=[a, b])` pattern confirmed; extends to variadic |
| QOL-01 | Re, Nu, h_tc, T_wall declared as `@observed` in ChannelAndContacts; accessible via `sol[sys.ch.Re, :]` | Confirmed: `System(...; observed=[Re ~ expr, ...])` keyword works; propagates through `compose()` automatically; sol indexing tested |
| QOL-02 | `check_gravity_mismatch(sys)` checks gravity pressure terms sum to zero at zero flow | Algorithm verified: scan equations for gravity contribution; `mdot=0` substitution approach; Gravity component equation confirmed |
| QOL-03 | `port(sys, :thermal_left, i)` wraps `getproperty(sys, Symbol(:thermal_left, i))` | Already the exact pattern used in all existing tests; trivial wrapper |
</phase_requirements>

---

## Summary

Phase 15 delivers two feature clusters: (1) composition helpers that reduce multi-line MTK wiring into single-call functions, and (2) QoL introspection — observed variables on ChannelAndContacts and two small utility functions.

All composition helpers follow the same MTK pattern: build a `Vector{Equation}` of `connect(...)` calls, then return `compose(System(conns, t; name=name), sys_a, sys_b, ...)`. This is already used identically in every test in `runtests.jl` and in `build_loop`/`build_loop_vertical` in `solvers.jl`. No new MTK API is introduced — helpers are thin wrappers around existing idioms.

The observed-variable work requires changing `ChannelAndContacts` so that Re[i], Nu[i], h_tc[i], v[i], q_wall[i], Q_wall_total are moved from `all_vars` (unknowns) into an `observed=[...]` argument to the `System(...)` constructor. Live tests confirm the `observed` keyword works in the MTK `System` constructor and that `observed` equations namespace correctly through `compose()`, making `sol[sys.ch.Re, :]` work on nested composed systems.

**Primary recommendation:** Implement in two waves. Wave 1: add `observed=[...]` to `ChannelAndContacts` and add `port()` and `check_gravity_mismatch()` (isolated changes). Wave 2: add the four composition helpers and export them.

---

## Standard Stack

### Core (all already in Project.toml)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | 11.x | System composition, observed variables, connect() | Project foundation — all existing code uses it |
| Symbolics.jl | (transitive) | Symbolic equation manipulation for gravity check | Already available |

No new dependencies required for this phase.

---

## Architecture Patterns

### Recommended File Organization

The planner has discretion here. Recommended approach: add a new `src/helpers.jl` file for composition helpers + `check_gravity_mismatch` + `port`, included from `STREAM.jl` between `components.jl` and `solvers.jl`. This avoids bloating either existing file and keeps helper API clearly separated.

```
src/
├── STREAM.jl          # add include("helpers.jl"); add new exports
├── fluids.jl          # unchanged
├── connectors.jl      # unchanged
├── correlations.jl    # unchanged
├── components.jl      # modify ChannelAndContacts: move vars to observed
├── helpers.jl         # NEW: symmetric_plate, plate, one_sided_connection,
│                      #      compose_systems, check_gravity_mismatch, port
└── solvers.jl         # unchanged
```

### Pattern 1: System with observed keyword

**What:** MTK `System` constructor accepts `observed` kwarg — a `Vector{Equation}` of `lhs ~ rhs` where `lhs` is an undeclared variable and `rhs` is an expression in known unknowns/parameters.

**When to use:** Any derived quantity that can be computed algebraically from existing unknowns; removes it from the solver's unknown vector, making it on-demand only.

```julia
# Source: confirmed via live Julia session against MTK 11.x
@variables x(t) = 300.0
@variables Re(t)  # declared but NOT in all_vars
D = Differential(t)
eqs  = [D(x) ~ -0.01 * (x - 300.0)]
obs  = [Re ~ x / 10.0]

@named sys = System(eqs, t, [x], []; observed=obs)
# After solve: sol[sys.Re, :] returns full time series
```

**Propagation:** Verified live — `observed` equations namespace automatically through `compose()`:
```julia
# Source: confirmed via live Julia session
compiled = mtkcompile(outer)   # outer composes inner which has Re as observed
sol[compiled.inner.Re, :]      # works — observed propagated with namespace prefix
```

### Pattern 2: Composition via System(connections, t; systems=[...])

**What:** Building a composed system from subsystems and cross-connections.

**When to use:** Every composition helper. Replaces the 10-20 line wiring boilerplate that tests currently repeat.

```julia
# Source: confirmed via live Julia session + all existing tests in runtests.jl
function symmetric_plate(cac::ModelingToolkit.System,
                         hd::ModelingToolkit.System;
                         name::Symbol)
    n = ...  # infer from cac (or caller ensures match)
    conns = Equation[
        [connect(getproperty(cac, Symbol(:thermal_left,  i)),
                 getproperty(hd,  Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(getproperty(cac, Symbol(:thermal_right, i)),
                 getproperty(hd,  Symbol(:thermal_right, i))) for i in 1:n]...,
    ]
    return compose(System(conns, t; name=name), cac, hd)
end
```

**Key detail:** `n` must be inferable from `cac`. The number of thermal ports is embedded in `ModelingToolkit.get_systems(cac)` — count subsystems named `:thermal_leftN`. Alternatively, accept `n` as an explicit kwarg. Planner decides; the simpler option is to infer from subsystem count.

### Pattern 3: Port wiring for plate() — asymmetric

**What:** `plate(ch_left, ch_right, fuel)` wires `ch_left.thermal_right[i] ↔ hd.thermal_left[i]` and `ch_right.thermal_left[i] ↔ hd.thermal_right[i]`.

**Source:** Directly derived from VAL-01 test (`runtests.jl:939-943`) which already validates this wiring pattern:
```julia
# VAL-01 pattern (confirmed working in production tests)
[connect(getproperty(hd, Symbol(:thermal_left,  i)),
         getproperty(cac_l, Symbol(:thermal_left, i))) for i in 1:nz]...,
[connect(getproperty(hd, Symbol(:thermal_right, i)),
         getproperty(cac_r, Symbol(:thermal_left, i))) for i in 1:nz]...,
```

Note: In the existing tests, both channels connect via `:thermal_left` face (not `:thermal_right`). The CONTEXT specifies `ch_left.thermal_right[i] ↔ fuel.thermal_left[i]`. Planner must resolve this: the exact face depends on the physical geometry (channel on left sees plate's left face). The CONTEXT is authoritative.

### Pattern 4: check_gravity_mismatch algorithm

**What:** Inspect composed ODESystem equations, identify those containing gravity terms, check if they sum to zero at zero flow.

**Implementation approach:** The `dP` equation in `ChannelAndContacts` (line 10 in equation list) contains the gravity term `rho_water(T[i_mid]) * g_acc * L`. The `Gravity` component has `port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H`.

The algorithm from CONTEXT (substitute mdot=0 and check pressure consistency) can be implemented as:

```julia
function check_gravity_mismatch(sys::ModelingToolkit.System) -> Symbol
    # 1. Extract all equations from full system (ModelingToolkit.equations(sys))
    # 2. Filter equations involving pressure (containing port_in.P, port_out.P, dP)
    # 3. Substitute mdot=0 symbolically
    # 4. For each resulting pressure equation, evaluate the RHS at a reference T
    # 5. Check if the linear pressure system is consistent (gravity terms cancel)
    # Returns :ok or :mismatch
end
```

**Practical simplification:** Since `g_acc` is a baked-in Float64 parameter (not a symbolic), and gravity contributions appear directly in dP equations, a simpler approach is to: walk all equations, for each equation that equals a `dP` or `P_in - P_out` form, extract the gravity-linear term (the term that remains when `mdot=0`), sum across all components, and check if ≈ 0. The threshold is a discretion item — suggest `atol=1e-3` Pa (much smaller than any real pressure scale).

### Pattern 5: port() helper

**What:** Thin wrapper around `getproperty(sys, Symbol(face, i))`.

```julia
# Source: exact pattern from runtests.jl used at lines 667, 676, 804, 840, etc.
port(sys, :thermal_left, i) = getproperty(sys, Symbol(:thermal_left, i))
```

One-liner function; no logic needed.

### Anti-Patterns to Avoid

- **Validation inside helpers:** Do NOT check that `cac.n == hd.nz` inside `symmetric_plate` — caller responsibility (locked decision).
- **Hidden mtkcompile:** Do NOT call `mtkcompile` inside composition helpers — return raw `System` only.
- **Using `sys.thermal_left[i]` syntax in connect():** This fails. Only `getproperty(sys, Symbol(:thermal_left, i))` works. This is proven by all 10+ existing tests.
- **Converting observed variables to @parameters:** Observed equations must be `lhs ~ rhs` with `lhs` being a `@variables` declaration, not `@parameters`. The variable must be declared with `@variables` but NOT included in `all_vars` passed to the System constructor.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-subsystem connections | Custom graph traversal | MTK `connect()` + Kirchhoff equations | MTK handles all flow variable balancing automatically |
| Observed variable access | Custom accessor functions | MTK symbolic indexing `sol[sys.Re, :]` | Already implemented in MTK SciML interface |
| Namespace propagation | Manual prefix/suffix | MTK `compose()` auto-namespacing | Proven in tests: `ssys.ch.Re[i]` works through multiple nesting levels |

**Key insight:** Every line of composition helper code is essentially already in `runtests.jl` — the helpers are simply function-wrapping existing test patterns.

---

## Common Pitfalls

### Pitfall 1: observed variable declaration vs. unknowns

**What goes wrong:** If `Re(t)[1:n]` is declared via `@variables` and also included in `all_vars`, MTK will treat it as an unknown (state) and solve for it. Then it is NOT an observed variable.

**Why it happens:** Currently `ChannelAndContacts` already declares Re, Nu, h_tc, v, q_wall as `@variables` and puts them in `all_vars`. The change needed: remove them from `all_vars` and instead add their defining equations to the `observed=[...]` list.

**How to avoid:** Check that each moved variable is:
1. Declared with `@variables` (still needed for the symbol)
2. NOT in the `all_vars` vector passed to `System(...)`
3. IS in the `observed=[...]` vector as `Re[i] ~ <expression>`

**Warning signs:** If `sol[sys.ch.Re, :]` throws an error saying "variable not found in observed", the variable is still in `all_vars`. If it returns zeros or wrong values, the expression is wrong.

### Pitfall 2: `n` inference in composition helpers

**What goes wrong:** `symmetric_plate(cac, hd)` needs to know `n` to build the connection loop `for i in 1:n`.

**Why it happens:** `ChannelAndContacts` embeds `n` in subsystem count but doesn't expose it as a field.

**How to avoid:** Count the thermal port subsystems: `n = count(s -> startswith(string(ModelingToolkit.getname(s)), "thermal_left"), ModelingToolkit.get_systems(cac))`. Alternatively, accept `n` as an explicit kwarg with no default (forcing caller to be explicit). Recommend: accept explicit `n` kwarg since it's simpler and explicit.

**Warning sign:** Wrong connection count causes MTK to leave some ports unconnected, leading to overdetermined or underdetermined systems.

### Pitfall 3: plate() face-to-face mapping

**What goes wrong:** Confusing which face of the channel connects to which face of the fuel plate.

**Why it happens:** The naming `thermal_left[i]` on `ChannelAndContacts` refers to the left wall of the channel, not the left face of the fuel plate.

**How to avoid:** The CONTEXT.md defines the mapping explicitly:
- `ch_left.thermal_right[i] ↔ fuel.thermal_left[i]` (ch_left is to the left of the plate — its right face sees the plate's left face)
- `ch_right.thermal_left[i] ↔ fuel.thermal_right[i]`

Follow CONTEXT exactly. This is consistent with the physical geometry.

### Pitfall 4: check_gravity_mismatch on uncompiled vs compiled system

**What goes wrong:** Calling `equations(sys)` on an uncompiled composed system returns only the top-level equations — not the subsystem equations. Calling on a compiled system returns the full flattened set.

**Why it happens:** MTK `equations()` behavior differs pre/post `mtkcompile`.

**How to avoid:** The algorithm must work on both. For pre-compiled systems, use `ModelingToolkit.equations(sys)` recursively (or `full_equations`). Test the function on both an uncompiled and a compiled system. The CONTEXT says "pre- or post-mtkcompile" — verify this with a live test.

### Pitfall 5: compose_systems variadic argument order

**What goes wrong:** If `compose_systems` takes `systems...` as first positional args and `connections` as last, Julia dispatch may be ambiguous with a single system argument.

**How to avoid:** Preferred signature: `compose_systems(connections::Vector{Equation}, systems...; name::Symbol)` where connections comes first (avoids ambiguity). Or use a keyword `systems` argument. Planner decides.

---

## Code Examples

### Example 1: symmetric_plate full pattern (from live test + CONTEXT)

```julia
# Source: runtests.jl VAL-01/02/03 patterns + CONTEXT.md decisions

function symmetric_plate(cac::ModelingToolkit.System,
                         hd::ModelingToolkit.System;
                         name::Symbol,
                         n::Int)
    conns = Equation[
        [connect(getproperty(cac, Symbol(:thermal_left,  i)),
                 getproperty(hd,  Symbol(:thermal_left,  i))) for i in 1:n]...,
        [connect(getproperty(cac, Symbol(:thermal_right, i)),
                 getproperty(hd,  Symbol(:thermal_right, i))) for i in 1:n]...,
    ]
    return compose(System(conns, t; name=name), cac, hd)
end
```

### Example 2: observed declaration in ChannelAndContacts

```julia
# Source: confirmed via live Julia session — System observed keyword works in MTK 11.x
# Pattern: move Re, Nu, h_tc, v from all_vars to observed list

# BEFORE (current):
all_vars = [collect(T); collect(Re); collect(Nu); collect(h_tc);
            collect(v); collect(q_wall); T_out; dP; Q_wall_total]
compose(System(eqs, t, all_vars, pars; name=name), ...)

# AFTER (Phase 15):
# Keep only true state/algebraic unknowns in all_vars
all_vars = [collect(T); T_out; dP; Q_wall_total]
# observed expressions use the already-baked-in eqs for Re, Nu, h_tc, v
obs = [
    Re[i] ~ abs(port_in.mdot) * Dh / (A * mu_water(T[i]))  for i in 1:n ...,
    Nu[i] ~ htc_correlation(Re[i], Pr_i)                    for i in 1:n ...,
    # ... etc.
]
compose(System(eqs, t, all_vars, pars; observed=obs, name=name), ...)
```

**Note:** The existing equations for Re[i] etc. must be REMOVED from `eqs` when they are moved to `observed`. They cannot appear in both places. The `_channel_base_eqs` helper currently pushes them into `eqs` — this function must be modified or split.

### Example 3: observed access through namespaced compose (verified)

```julia
# Source: live Julia session — compose() propagates observed correctly
compiled = mtkcompile(outer_sys)  # outer_sys composes plate_sys which composes cac
sol = solve_steady(compiled, op)
sol[compiled.plate.cac.Re[1], :]   # works — returns array of length nz
```

### Example 4: port() helper

```julia
# Source: exact pattern from runtests.jl lines 667, 676, 804, etc.
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))

# Usage:
p = port(sys.cac, :thermal_left, 3)  # returns thermal_left3 subsystem
```

### Example 5: compose_systems

```julia
# Source: CONTEXT.md + confirmed System(conns, t; systems=[...]) works live
function compose_systems(connections::Vector{Equation}, systems...; name::Symbol)
    return compose(System(connections, t; name=name), systems...)
end
```

---

## @observed Variable Expressions

Based on the CONTEXT.md decision table and the existing `_channel_base_eqs` code (`components.jl:319-325`):

| Observed Variable | Expression | Notes |
|------------------|------------|-------|
| `Re[i]` | `abs(port_in.mdot) * Dh / (A * mu_water(T[i]))` | Already in `_channel_base_eqs` as eq — move to observed |
| `Nu[i]` | `htc_correlation(Re[i], Pr_i)` where `Pr_i = cp_water(T[i])*mu_water(T[i])/k_water(T[i])` | Move from eqs |
| `h_tc[i]` | `Nu[i] * k_water(T[i]) / Dh` | Currently `h_tc[i]` (single); split into left/right |
| `h_tc_left[i]` | `Nu[i] * k_water(T[i]) / Dh * heated_parts[1]` | New split from h_tc |
| `h_tc_right[i]` | `Nu[i] * k_water(T[i]) / Dh * heated_parts[2]` | New split from h_tc |
| `T_wall_left[i]` | `thermal_left[i].T` | Alias for wall temp |
| `T_wall_right[i]` | `thermal_right[i].T` | Alias for wall temp |
| `Pe[i]` | `Re[i] * cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])` | Re * Pr |
| `velocity[i]` | `port_in.mdot / (rho_water(T[i]) * A)` | Same as `v[i]` — rename or alias |
| `q_wall_left[i]` | `thermal_left[i].Q_flow` | Already in energy balance eqs |
| `q_wall_right[i]` | `thermal_right[i].Q_flow` | Already in energy balance eqs |

**CRITICAL implementation note:** Moving Re[i], Nu[i], h_tc[i], v[i] from `eqs` to `observed` means the energy balance equations (which currently reference `h_tc[i]`) will reference an observed variable rather than an unknown. MTK handles this correctly — observed variables are substituted symbolically during `mtkcompile`. However, the equations must still close (h_tc must appear in the energy balance equations where needed, with its expression potentially inlined).

**Alternative approach:** Keep h_tc as a local Julia variable (not MTK symbolic) in the energy balance expression and ONLY expose it via `observed`. This avoids circular dependency concerns. The planner must decide based on whether `h_tc` needs to be a named symbol for the observed declaration to reference.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|-----------------|--------|
| Re, Nu, h_tc as ODESystem unknowns (increased solver variable count) | Move to `observed` — computed on-demand after solve | Smaller unknown vector, same diagnostic access |
| Manual 10-line wiring loops in every test | `symmetric_plate(cac, hd; name, n)` single call | Phase 16 tests will be much shorter |
| `getproperty(sys, Symbol(:thermal_left, i))` inline in every test | `port(sys, :thermal_left, i)` | Minor ergonomic win |

---

## Open Questions

1. **Does moving Re/Nu/h_tc from unknowns to observed break the energy balance?**
   - What we know: The energy balance in `_channel_base_eqs` references `h_tc[i]` as an MTK symbolic variable. If `h_tc[i]` becomes observed instead of unknown, MTK must inline it.
   - What's unclear: Whether MTK correctly handles observed-variable references inside `D(T[i]) ~ ...` equations during `mtkcompile`.
   - Recommendation: Test in Wave 1. If inlining fails, keep `h_tc[i]` as an unknown but expose `Re[i]`, `Nu[i]`, `Pe[i]`, `velocity[i]` as observed only (these don't appear in the energy balance RHS directly). The h_tc splitting into `h_tc_left[i]` and `h_tc_right[i]` can be purely observed aliases computed from the existing unknown `h_tc[i]`.

2. **`n` inference in composition helpers**
   - What we know: Helpers need `n` to build connection loops.
   - Recommendation: Accept explicit `n::Int` kwarg — simpler than parsing subsystem names. Add to `symmetric_plate`, `plate`, `one_sided_connection` signatures. The planner must decide.

3. **check_gravity_mismatch: pre-compile vs post-compile behavior**
   - What we know: `equations(sys)` on an uncompiled composed system does NOT return subsystem equations.
   - What's unclear: Whether `ModelingToolkit.full_equations(sys)` or recursive descent gives the right set.
   - Recommendation: Test both paths. If only post-compile works, document that `check_gravity_mismatch` requires a compiled system or use `mtkcompile` internally on a copy. Since CONTEXT says "pre- or post-mtkcompile", investigate `ModelingToolkit.full_equations` or `ModelingToolkit.equations(sys; recursive=true)` options.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (Test.jl) |
| Config file | none — run via `julia --project test/runtests.jl` |
| Quick run command | `julia --project test/runtests.jl` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COMP-01 | `symmetric_plate(cac, hd; name, n)` returns solvable ODESystem | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| COMP-02 | `plate(ch_l, ch_r, hd; name, n)` returns solvable ODESystem | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| COMP-03 | `one_sided_connection(ch, hd, :left; name, n)` returns solvable ODESystem | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| COMP-04 | `compose_systems(conns, a, b; name)` returns solvable ODESystem | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |
| QOL-01 | `sol[ssys.cac.Re, :]` returns length-n array after solve | integration | `julia --project test/runtests.jl` | ❌ Wave 0 |
| QOL-02 | `check_gravity_mismatch(sys)` returns `:ok` on balanced loop | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |
| QOL-03 | `port(sys, :thermal_left, i)` returns correct subsystem | unit | `julia --project test/runtests.jl` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `julia --project test/runtests.jl`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

All new tests belong in `test/runtests.jl` appended after the PHY-02/03/04 test block. No new test files needed — the project uses a single `runtests.jl`. New testsets to create:

- [ ] `@testset "COMP-01: symmetric_plate — builds and solves" begin` — covers COMP-01
- [ ] `@testset "COMP-02: plate — two-channel wiring" begin` — covers COMP-02
- [ ] `@testset "COMP-03: one_sided_connection — single face" begin` — covers COMP-03
- [ ] `@testset "COMP-04: compose_systems — variadic wrapper" begin` — covers COMP-04
- [ ] `@testset "QOL-01: @observed Re/Nu accessible via sol" begin` — covers QOL-01
- [ ] `@testset "QOL-02: check_gravity_mismatch — balanced loop" begin` — covers QOL-02
- [ ] `@testset "QOL-03: port() helper" begin` — covers QOL-03

No framework install required — Test.jl is already in `[extras]`.

---

## Sources

### Primary (HIGH confidence)

- Live Julia session (MTK 11.x, this project) — `System(...; observed=[...])` constructor tested and confirmed
- Live Julia session — `observed` propagates through `compose()` with correct namespace
- `test/runtests.jl` lines 626-627, 939-943, 1026-1029, 1092-1093 — `getproperty(sys, Symbol(:thermal_left, i))` pattern confirmed as the only correct connect() syntax
- `src/components.jl:362-427` — ChannelAndContacts current implementation; exact variables to move to observed
- `src/components.jl:312-341` — `_channel_base_eqs` — source of Re/Nu/h_tc equations
- `src/solvers.jl:53-83` — `build_loop` pattern for compose-then-solve
- `src/STREAM.jl` — current export list; additions needed

### Secondary (MEDIUM confidence)

- ModelingToolkit.jl stable docs (ode_modeling tutorial) — confirmed `observed` keyword concept and `sol[sys.var]` syntax for observed variables
- CONTEXT.md algorithm description for `check_gravity_mismatch` — verified against actual `dP` equation structure in CAC

### Tertiary (LOW confidence)

- `ModelingToolkit.full_equations` or recursive `equations()` for pre-compiled system traversal — not confirmed; needs testing in implementation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all MTK patterns live-tested
- Architecture patterns: HIGH — all patterns are already in use in the codebase
- Observed variable mechanics: HIGH — `System(...; observed=[...])` confirmed working with namespace propagation
- `check_gravity_mismatch` algorithm: MEDIUM — algorithm is sound but pre-compile equation traversal needs implementation verification
- Pitfalls: HIGH — based on actual code inspection and live tests

**Research date:** 2026-03-15
**Valid until:** 2026-04-15 (MTK 11.x stable; no expected breaking changes in 30 days)

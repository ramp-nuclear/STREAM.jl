# Phase 21: Fluid Properties & Natural Convection - Research

**Researched:** 2026-03-17
**Domain:** Julia fluid property functions, dimensionless number utilities, natural convection HTC correlation, MTK pluggable HTC interface extension
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- Extend all HTC correlations from `(Re, Pr) -> Nu` to `(Re, Pr, T_bulk, T_wall) -> Nu`
- All existing correlations (`dittus_boelter`, `blasius_friction`, `constant_Nusselt`, `laminar_friction`, `regime_dependent` inner closures) accept extra args via `args...` splatting — zero behavior change, fully backward-compatible
- `regime_dependent` updated to pass all 4 args through: `(Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall))`
- Channel/ChannelAndContacts/ChannelHeatFlux updated to pass `T_bulk` and `T_wall` at each cell:
  - `Channel`: passes `(Re[i], Pr[i], T[i], T[i])` (dT = 0)
  - `ChannelAndContacts`: `(Re[i], Pr[i], T[i], T_wall_left[i])` for left HTC, `(Re[i], Pr[i], T[i], T_wall_right[i])` for right HTC
  - `ChannelHeatFlux`: passes `(Re[i], Pr[i], T[i], T[i])`
- `elenbaas_nusselt(Ra, b, L)` — plain Julia function, NOT `@register_symbolic`
- Formula: `Nu = (1/24) * Ra * (b/L) * (1 - exp(-35 * L / (Ra * b)))^0.75`
- `elenbaas_htc(; b, L, Dh, g=9.81)` — factory returning `(Re, Pr, T_bulk, T_wall) -> Nu` closure
- `beta_water(T_K)` — `@register_symbolic`, temperature in Kelvin, Simantov formula: `beta = -1.8 * (B + 2*C*TF) / rho_water(T_K)`
- New `src/physical_models/dimensionless.jl` with: `Re`, `Re_vel`, `Pr`, `Nu`, `Pe`, `Gr`, `Ra`, `flow_regimes`
- `Gr(beta, g, dT, L, nu)` = `beta * g * dT * L^3 / nu^2`
- `Ra(Gr_val, Pr_val)` = `Gr_val * Pr_val`
- Validation: compare `elenbaas_nusselt` against Python STREAM `_Elenbaas` at identical inputs within `1e-6` rtol
- Test files: `test/test_correlations.jl` (Elenbaas), `test/test_fluids.jl` (beta_water)

### Claude's Discretion

- Exact docstring wording for dimensionless.jl functions
- Whether `Re_vel` alias is worth adding alongside `Re(mdot,...)`
- Test parameter values for the Elenbaas Python STREAM comparison (pick physically realistic MTR-scale inputs)
- Whether `flow_regimes` uses `Vector` or scalar inputs in the Julia version

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| FLUID-01 | `beta_water(T)` — isobaric thermal expansion coefficient [1/K] for light water, `@register_symbolic` | Formula verified against Python STREAM; reference values computed; `@register_symbolic` pattern established in `fluids.jl` |
| FLUID-02 | `Gr(beta, g, dT, L, nu)` — Grashof number utility (plain exported Julia function) | Simplified form mathematically equivalent to Python STREAM's full form; verified computationally at MTR-scale conditions |
| FLUID-03 | `Ra(Gr_val, Pr_val)` — Rayleigh number utility (plain exported Julia function) | `Ra = Gr * Pr`; consistent with Python STREAM; trivial one-liner |
| NATCONV-01 | `elenbaas_nusselt(Ra, b, L)` — Elenbaas parallel-plate correlation, pluggable HTC | Formula extracted from Python STREAM `_Elenbaas`; HTC interface extension pattern designed; factory `elenbaas_htc` specified |
| NATCONV-02 | `elenbaas_nusselt` validated against published Elenbaas table values or analytical limiting cases | Reference Nu=1.2731625848 computed at MTR-scale test point; Python STREAM comparison methodology established |
</phase_requirements>

---

## Summary

Phase 21 adds thermal expansion coefficient `beta_water(T_K)`, dimensionless number utilities (`Gr`, `Ra`, and friends), and the Elenbaas natural convection HTC correlation. All implementation decisions are fully locked in CONTEXT.md and directly traceable to Python STREAM source files that have been read and verified.

The core technical challenge is the HTC interface extension from `(Re, Pr) -> Nu` to `(Re, Pr, T_bulk, T_wall) -> Nu`. This is required so `elenbaas_htc` can compute the temperature-difference-dependent Rayleigh number inside the closure. The extension strategy — `args...` splatting on all existing correlations — is backward-compatible and requires changes to 5 call sites across 3 source files.

All reference values have been computed directly from the Python STREAM Simantov formulas and the `_Elenbaas` formula, giving HIGH confidence test data that can be compared at `rtol=1e-6`.

**Primary recommendation:** Implement in two plans: (21-01) `beta_water` + `dimensionless.jl` + interface extension + channel call-site updates; (21-02) `elenbaas_nusselt` + `elenbaas_htc` + tests.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit.jl | (project pinned) | MTK system construction, `@register_symbolic` | Established project base; `@register_symbolic` already used for all fluid properties |
| Symbolics.jl | (project pinned) | `@register_symbolic` macro | Already imported in `STREAM.jl` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Test.jl | stdlib | `@test`, `@testset`, `isapprox` | All unit tests; established project pattern |

No new package dependencies are introduced by Phase 21.

**Installation:**
No `Pkg.add` commands needed — all required libraries are already project dependencies.

---

## Architecture Patterns

### Recommended Project Structure
```
src/
├── fluids.jl                    # ADD: beta_water(T_K) + @register_symbolic beta_water
├── physical_models/
│   ├── correlations.jl          # ADD: elenbaas_nusselt, elenbaas_htc; MODIFY: args... splatting + regime_dependent
│   └── dimensionless.jl         # NEW FILE: Re, Re_vel, Pr, Nu, Pe, Gr, Ra, flow_regimes
├── components/
│   ├── channel.jl               # MODIFY: htc call sites pass 4 args
│   └── thermal_channel.jl       # MODIFY: htc call sites pass 4 args
└── STREAM.jl                    # ADD: include("physical_models/dimensionless.jl") + exports
```

### Pattern 1: @register_symbolic for Fluid Properties (FLUID-01)
**What:** Wrap `beta_water(T_K)` with `@register_symbolic` at module top-level in `fluids.jl`
**When to use:** Any function that must be callable on MTK symbolic variables (`Num` type)
**Example:**
```julia
# Source: src/fluids.jl — mirrors existing rho_water pattern exactly
function beta_water(T_K::Real)
    T_C = T_K - 273.15
    T_F = _to_fahrenheit(T_C)
    B   = -0.046283
    C   = -7.9738e-4
    return -1.8 * (B + 2 * C * T_F) / rho_water(T_K)
end
@register_symbolic beta_water(T::Real)
```
Note: `rho_water` is already `@register_symbolic`, so calling it inside `beta_water` from MTK context is safe — MTK will chain the symbolic registrations correctly.

### Pattern 2: args... Splatting for HTC Interface Extension (NATCONV-01)
**What:** Update all existing `(Re, Pr) -> Nu` correlation closures to accept extra positional args via `args...`, discarding them silently
**When to use:** Making N-arg closures accept N+K args without changing existing call sites
**Example:**
```julia
# Before (channel.jl line 80):
push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i))

# After:
push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i, T[i], T[i]))

# constant_Nusselt factory — updated inner closure:
function constant_Nusselt(; Nu = 8.235)
    return (Re, Pr, args...) -> Nu
end

# regime_dependent — updated inner closure (passes all 4 args through):
htc_fn = (Re, Pr, T_bulk, T_wall) -> ifelse(
    Re < Re_tr,
    htc_laminar(Re, Pr, T_bulk, T_wall),
    htc_turbulent(Re, Pr, T_bulk, T_wall)
)
```

### Pattern 3: Factory Closure for elenbaas_htc (NATCONV-01)
**What:** Factory function captures geometry at construction time; returned closure computes Ra from T_bulk/T_wall
**When to use:** Correlations that need geometric parameters baked in, plus dynamic temperature-based quantities
**Example:**
```julia
# Source: src/physical_models/correlations.jl
function elenbaas_htc(; b, L, Dh, g = 9.81)
    return (Re, Pr, T_bulk, T_wall) -> begin
        beta   = beta_water(T_bulk)
        nu     = mu_water(T_bulk) / rho_water(T_bulk)
        Gr_val = Gr(beta, g, T_wall - T_bulk, Dh, nu)
        Ra_val = Ra(Gr_val, Pr)
        elenbaas_nusselt(Ra_val, b, L)
    end
end
```
Note: When used in `Channel` where `T_wall = T_bulk`, then `dT = 0` → `Gr = 0` → `Ra = 0` → `Nu = 0`. This is physically correct — no wall temperature difference means no buoyancy-driven convection. The solver must be given appropriate initial conditions when switching to natural convection.

### Pattern 4: dimensionless.jl — Plain Julia Functions (FLUID-02, FLUID-03)
**What:** All dimensionless number utilities are plain Julia functions (NOT `@register_symbolic`) — MTK traces through plain arithmetic symbolically without registration
**When to use:** Functions that only perform arithmetic on their arguments (no branching on symbolic values at construction time)
**Example:**
```julia
# Source: src/physical_models/dimensionless.jl
# Simplified Gr vs Python STREAM full Gr — mathematically equivalent
# Python: rho^2 * g * beta * dT * Dh^3 / mu^2
# Julia:  beta * g * dT * L^3 / nu^2  (nu = mu/rho, so rho^2/mu^2 = 1/nu^2)
Gr(beta, g, dT, L, nu) = beta * g * dT * L^3 / nu^2
Ra(Gr_val, Pr_val)     = Gr_val * Pr_val
```

### Pattern 5: _channel_base_eqs observed_mode for ChannelAndContacts
**What:** The `observed_mode=true` path in `_channel_base_eqs` already inlines Re/Pr expressions rather than using MTK symbol chains. The 4-arg HTC call must be consistent in BOTH the `eqs` path (for `h_tc[i]` in `_channel_base_eqs`) and the `obs` path (for `Nu[i]` in the `obs` block of `ChannelAndContacts`).
**Critical:** Two call sites in `ChannelAndContacts` must BOTH be updated:
1. `_channel_base_eqs` → `h_tc[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_wall_left_i)` (observed_mode path)
2. `obs` block → `Nu[i] ~ htc_correlation(Re_i, Pr_i, T[i], T_wall_left_i)`

The CONTEXT.md says to pass `T_wall_left[i]` for left HTC. Since `ChannelAndContacts` uses a single `h_tc[i]` for both walls, the call in `_channel_base_eqs` (observed_mode) should use left wall temperature (or `T[i]` if symmetric). Review carefully — the CONTEXT.md specifies:
- `h_tc` (energy balance): uses `thermal_left[i].T` (left wall)
- Separate `h_tc_left[i]` and `h_tc_right[i]` in obs — currently both alias `h_tc[i]`

**Recommendation:** For the `h_tc[i]` equation in `_channel_base_eqs` (observed_mode), pass `thermal_left[i].T` as `T_wall`. For the `Nu[i]` observed equation, also pass `thermal_left[i].T`. This is consistent with how `Channel` has a single thermal port.

### Anti-Patterns to Avoid
- **`@register_symbolic` on `Gr`, `Ra`, `elenbaas_nusselt`:** These are plain arithmetic — MTK traces through them automatically. Registration is only needed for functions that call external (non-symbolic-traceable) code, like the Simantov polynomial functions.
- **Passing 2-arg `htc_correlation` to 4-arg call sites:** After the interface extension, the 4-arg call sites in channels will break with old-style `(Re, Pr) -> Nu` closures. The `args...` splatting on factory outputs is the fix, not on the call site.
- **Updating `dittus_boelter` standalone function signature:** `dittus_boelter` is a standalone function (not a closure), so it must also accept `args...`: `dittus_boelter(Re, Pr, args...) = 0.023 * Re^0.8 * Pr^0.4`. Same for `blasius_friction` — but it only receives `(Re)` from `friction_correlation` call sites which are NOT being extended, so `blasius_friction` signature stays `(Re)` unchanged.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Thermal expansion coefficient | Custom fit or lookup table | Simantov analytical formula (exact) | Same formula in Python STREAM; exact match required for cross-validation |
| Elenbaas correlation | Numerical integration or CFD lookup | `elenbaas_nusselt` one-liner from published formula | Formula is a known semi-empirical result from Elenbaas (1942); exact formula given in CONTEXT.md |
| Ra computation inside elenbaas_htc | Inline all property calls | Call `Gr()` and `Ra()` from `dimensionless.jl` | Reuses validated utilities; keeps closure readable |

**Key insight:** All formulas are deterministic closed-form expressions. The only complexity is plumbing the correct temperature arguments through the HTC interface — not the math itself.

---

## Common Pitfalls

### Pitfall 1: `_channel_base_eqs` observed_mode path also needs updating
**What goes wrong:** `_channel_base_eqs` has two branches: `observed_mode=false` (Channel, ChannelHeatFlux) and `observed_mode=true` (ChannelAndContacts). The 4-arg HTC call must be added to BOTH branches, or `ChannelAndContacts` will silently use the wrong number of args.
**Why it happens:** The helper is shared but `ChannelAndContacts` calls it with `observed_mode=true`, where `h_tc[i]` is built from an inlined expression not passing through the `obs` block.
**How to avoid:** Update the inlined `htc_correlation(Re_i, Pr_i)` in the `observed_mode=true` branch to `htc_correlation(Re_i, Pr_i, T[i], thermal_left_i_T)`. But `_channel_base_eqs` does not receive `thermal_left` — it only gets the equations list and symbolic variables. The `T_wall` arg must come from context. Recommend: add `T_wall_cells` kwarg to `_channel_base_eqs` (defaulting to `T`, i.e., `T_wall = T_bulk`).
**Warning signs:** Test for `elenbaas_htc` in `ChannelAndContacts` returns Nu=0 even when `T_wall != T_bulk`.

### Pitfall 2: `constant_Nusselt` returning a literal before splatting
**What goes wrong:** `constant_Nusselt()` currently returns `(Re, Pr) -> Nu`. If this closure is called with 4 args, Julia will error: "too many arguments". The `args...` must be added before the interface extension lands.
**Why it happens:** Julia closures enforce arity strictly (no implicit varargs).
**How to avoid:** In the same commit that updates call sites to 4-arg, update ALL factory closures to accept `args...`. These must change together atomically.
**Warning signs:** `MethodError: no method matching ... with 4 arguments` in test output.

### Pitfall 3: `elenbaas_htc` called from `Channel` with `T_wall = T_bulk`
**What goes wrong:** `dT = T_wall - T_bulk = 0` → `Ra = 0` → `elenbaas_nusselt` returns `Nu = 0` → `h_tc[i] = 0` → no heat transfer at all, even though wall exists.
**Why it happens:** Elenbaas is a natural convection correlation and requires a temperature difference to drive flow. Using it in `Channel` (no wall temp difference) is physically nonsensical.
**How to avoid:** This is documented as physically correct per CONTEXT.md. Tests should NOT use `elenbaas_htc` with `Channel` — only with `ChannelAndContacts` where `T_wall` differs from `T_bulk`.
**Warning signs:** Solver converges with h_tc=0 but test expected nonzero heat transfer.

### Pitfall 4: Gr signature mismatch — Julia simplified vs Python full
**What goes wrong:** Python STREAM `Gr(rho, mu, beta, T, Twall, Dh, g)` computes `rho^2 * g * beta * (Twall-T) * Dh^3 / mu^2`. The Julia simplified form `Gr(beta, g, dT, L, nu)` uses kinematic viscosity `nu = mu/rho`. These are mathematically identical but the caller must pre-compute `dT` and `nu`. If the caller passes `rho` instead of `nu`, results will be off by `rho^2`.
**How to avoid:** `elenbaas_htc` factory computes `nu = mu_water(T_bulk) / rho_water(T_bulk)` explicitly. The `Gr` docstring must clearly state args are `dT` (already differenced) and `nu` (kinematic viscosity).
**Warning signs:** `Gr` values 10^6 times off from Python STREAM reference (factor of `rho^2 ~ 10^6`).

### Pitfall 5: `flow_regimes` Julia vs Python array behavior
**What goes wrong:** Python `flow_regimes(re, bounds)` takes a numpy array and returns boolean arrays. Julia's scalar behavior differs from array behavior — `re <= bounds[0]` on a scalar gives a `Bool`, not a `BitVector`.
**How to avoid:** Julia `flow_regimes` should accept `AbstractVector{<:Real}` and return `BitVector` tuple (not scalar Bool). This matches Python STREAM's documented usage. Alternatively, implement for scalar and use broadcasting at call sites. Given CONTEXT.md says "Claude's discretion" on this, recommend scalar version (simpler, covers the primary use case).
**Warning signs:** Type errors when calling `flow_regimes(scalar_re, bounds)` in user code.

---

## Code Examples

Verified patterns from direct source inspection and Python STREAM reference:

### beta_water reference values (HIGH confidence — computed from Simantov formula)
```
T=20°C (T_K=293.15K) -> beta = 2.7907882032e-04 1/K  (Python STREAM: 279.0788e-6 ✓)
T=50°C (T_K=323.15K) -> beta = 4.3910662994e-04 1/K
T=100°C (T_K=373.15K)-> beta = 7.2134423031e-04 1/K  (Python STREAM: 721.3442e-6 ✓)
```

### Elenbaas reference values (HIGH confidence — computed from exact formula)
```
Test point: T_bulk=40°C, T_wall=60°C, S (gap)=0.00254m, Lh=0.6m
  rho   = 991.3511 kg/m³
  mu    = 6.5197e-04 Pa·s
  cp    = 4178.9588 J/(kg·K)
  k     = 0.630156 W/(m·K)
  beta  = 3.851798e-04 1/K
  nu    = 6.5766e-07 m²/s
  Gr    = 2862.302086
  Pr    = 4.323622
  Ra    = 12375.512696
  Nu_Elenbaas = 1.2731625848
```
Use this for the Python STREAM comparison test in `test/test_correlations.jl`.

### Gr equivalence proof (confirmed computationally)
```
Python Gr = rho^2 * g * beta * dT * Dh^3 / mu^2 = 2862.302086
Julia  Gr = beta * g * dT * L^3 / nu^2           = 2862.302086
(difference < 1e-10 relative)
```

### dimensionless.jl function signatures
```julia
# Source: Python STREAM dimensionless.py (adapted to Julia conventions)
Re(mdot, A, Dh, mu)    = abs(mdot) * Dh / (A * mu)   # matches existing channel Re inline
Re_vel(rho, u, L, mu)  = rho * abs(u) * L / mu        # Python STREAM Re(rho, u, L, mu)
Pr(cp, mu, k)          = cp * mu / k
Nu(h, Dh, k)           = h * Dh / k
Pe(Re_val, Pr_val)     = Re_val * Pr_val
Gr(beta, g, dT, L, nu) = beta * g * dT * L^3 / nu^2
Ra(Gr_val, Pr_val)     = Gr_val * Pr_val
```

### HTC 4-arg call site update (channel.jl line 80 before -> after)
```julia
# Before (channel.jl observed_mode=false branch):
push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i))

# After:
push!(eqs, Nu[i] ~ htc_correlation(Re[i], Pr_i, T[i], T[i]))

# ChannelAndContacts observed block (thermal_channel.jl ~line 122):
# Before:
push!(obs, Nu[i] ~ htc_correlation(Re_i, Pr_i))
# After:
push!(obs, Nu[i] ~ htc_correlation(Re_i, Pr_i, T[i], thermal_left[i].T))
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| HTC as `(Re, Pr) -> Nu` 2-arg interface | `(Re, Pr, T_bulk, T_wall) -> Nu` 4-arg interface | Phase 21 | Enables natural convection correlations that need temperature difference; no breaking change via `args...` splatting |
| No `beta_water` in STREAM.jl | `beta_water` as `@register_symbolic` Simantov | Phase 21 | Enables buoyancy-driven flow modeling in MTK equations |
| No standalone dimensionless utilities | `dimensionless.jl` with Re, Pr, Nu, Pe, Gr, Ra | Phase 21 | Consistent with Python STREAM API; enables user code without reimplementing basics |

---

## Open Questions

1. **`_channel_base_eqs` `T_wall` argument for observed_mode**
   - What we know: In observed_mode, `h_tc[i]` is computed inline as `htc_correlation(Re_i, Pr_i) * k / Dh`. To extend to 4 args, the `thermal_left[i].T` variable must be threaded through `_channel_base_eqs`, which currently does not receive it.
   - What's unclear: Should `_channel_base_eqs` accept an optional `T_wall_cells` parameter (a vector of symbolic expressions), or should the ChannelAndContacts caller handle the `h_tc[i]` equations directly (not via the helper)?
   - Recommendation: Add `T_wall_cells = nothing` kwarg to `_channel_base_eqs`. When `nothing`, use `T[i]` as wall temp (Channel, ChannelHeatFlux case). When provided, use `T_wall_cells[i]`. This is a small, targeted extension that preserves the helper pattern.

2. **`flow_regimes` scalar vs vector**
   - What we know: Python STREAM uses numpy arrays; Julia use cases in STREAM.jl are currently scalar (per-cell Re values in equations).
   - Recommendation: Implement scalar version returning `Tuple{Bool, Bool, Bool}`. Add a docstring note that broadcast with `.` works for vector inputs. This covers the documented use case without forcing array allocation.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib (Test.jl) |
| Config file | `test/runtests.jl` (thin orchestrator with `@testset` + `include`) |
| Quick run command | `julia --project -e 'include("test/test_fluids.jl")'` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FLUID-01 | `beta_water(T_K)` returns correct values at 3 reference temperatures; is `Symbolics.Num` when called on MTK variable | unit | `julia --project -e 'include("test/test_fluids.jl")'` | Exists — add new `@testset` block |
| FLUID-02 | `Gr(beta, g, dT, L, nu)` returns correct value at MTR reference point (2862.302086) | unit | `julia --project -e 'include("test/test_correlations.jl")'` | Exists — add new `@testset` block |
| FLUID-03 | `Ra(Gr_val, Pr_val)` returns `Gr * Pr` (12375.5 at reference point) | unit | `julia --project -e 'include("test/test_correlations.jl")'` | Exists — add new `@testset` block |
| NATCONV-01 | `elenbaas_nusselt` returns Nu=1.2731625848 at reference point; `elenbaas_htc` factory creates valid 4-arg closure | unit | `julia --project -e 'include("test/test_correlations.jl")'` | Exists — add new `@testset` block |
| NATCONV-02 | `elenbaas_nusselt` matches Python STREAM `_Elenbaas` formula at MTR-scale inputs within rtol=1e-6 | unit | `julia --project -e 'include("test/test_correlations.jl")'` | Exists — add new `@testset` block |

**Note:** NATCONV-02 validation against Python STREAM is done by reproducing the formula computation (Python STREAM import chain is broken in this environment due to missing `scikits.odes`). The test asserts against the pre-computed reference value (1.2731625848) derived from the exact same formula — equivalent to Python STREAM comparison.

### Sampling Rate
- **Per task commit:** `julia --project -e 'include("test/test_fluids.jl"); include("test/test_correlations.jl")'`
- **Per wave merge:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- None — existing test infrastructure covers all phase requirements. New `@testset` blocks are added within existing files, no new test files needed.
  - `test/test_fluids.jl` — add `FLUID-01` beta_water tests
  - `test/test_correlations.jl` — add `FLUID-02`, `FLUID-03`, `NATCONV-01`, `NATCONV-02` tests

---

## Sources

### Primary (HIGH confidence)
- Direct source read: `/home/itay/projects/Julia-STREAM/src/fluids.jl` — exact beta_water formula derivation location, `@register_symbolic` pattern, `_to_fahrenheit` helper
- Direct source read: `/home/itay/projects/Julia-STREAM/src/physical_models/correlations.jl` — factory closure pattern, `regime_dependent` current implementation, `constant_Nusselt` arity
- Direct source read: `/home/itay/projects/Julia-STREAM/src/components/channel.jl` — HTC call site at line 80, `_channel_base_eqs` helper implementation
- Direct source read: `/home/itay/projects/Julia-STREAM/src/components/thermal_channel.jl` — `ChannelAndContacts` observed block HTC call site, dual thermal port wiring
- Direct source read: `/home/itay/projects/STREAM/stream/substances/light_water.py` — `_thermal_expansion(T)` formula (Python reference); confirmed `B=-0.046283`, `C=-7.9738e-4`, `-1.8*(B+2*C*TF)/_density(T)`
- Direct source read: `/home/itay/projects/STREAM/stream/physical_models/heat_transfer_coefficient/natural_convection.py` — `_Elenbaas` exact formula: `(1/24) * ra * (S/Lh) * (1 - exp(-35 * Lh / (ra * S)))^0.75`
- Direct source read: `/home/itay/projects/STREAM/stream/physical_models/dimensionless.py` — all dimensionless number signatures; confirmed `Gr` Python vs Julia equivalence
- Computational verification: Reference values for `beta_water`, `Gr`, `Ra`, `elenbaas_nusselt` computed via standalone Python script using identical Simantov formulas

### Secondary (MEDIUM confidence)
- None needed — all critical facts come from primary sources.

### Tertiary (LOW confidence)
- None — no unverified WebSearch findings used.

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all libraries already in project
- Architecture: HIGH — all locked decisions directly read from source files; patterns confirmed in existing code
- Pitfalls: HIGH — identified from direct code inspection of all modified files; Pitfall 1 (observed_mode) confirmed as genuine ambiguity in CONTEXT.md
- Reference values: HIGH — computed directly from the same formulas that will be used in implementation

**Research date:** 2026-03-17
**Valid until:** 2026-04-17 (30 days — stable formulas, no external dependencies)

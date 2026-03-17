# Phase 21: Fluid Properties & Natural Convection - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Add `beta_water(T)` thermal expansion coefficient, a new `src/physical_models/dimensionless.jl`
module with the full set of dimensionless number utilities (`Re`, `Re_mdot`, `Pr`, `Nu`, `Pe`,
`Gr`, `Ra`, `flow_regimes`), the `elenbaas_nusselt(Ra, b, L)` correlation, and an
`elenbaas_htc(; b, L, Dh, g)` factory that plugs into Channel/ChannelAndContacts via an
extended 4-argument HTC correlation interface.

This phase does NOT implement natural circulation as a solver mode, Flapper, or time-varying
Pump — those are Phases 22–24.

</domain>

<decisions>
## Implementation Decisions

### HTC correlation interface extension
- Extend all HTC correlations from `(Re, Pr) -> Nu` to `(Re, Pr, T_bulk, T_wall) -> Nu`
- All **existing** correlations (`dittus_boelter`, `blasius_friction`, `constant_Nusselt`,
  `laminar_friction`, `regime_dependent` inner closures) accept extra args via `args...` splatting —
  zero behavior change, fully backward-compatible
- `regime_dependent` updated to pass all 4 args through:
  `(Re, Pr, T_bulk, T_wall) -> ifelse(Re < Re_tr, htc_laminar(Re, Pr, T_bulk, T_wall), htc_turbulent(Re, Pr, T_bulk, T_wall))`
- Channel/ChannelAndContacts/ChannelHeatFlux updated to pass `T_bulk` and `T_wall` at each cell:
  - `Channel`: no thermal port → passes `(Re[i], Pr[i], T[i], T[i])` (dT = 0)
  - `ChannelAndContacts`: `(Re[i], Pr[i], T[i], T_wall_left[i])` for left HTC,
    `(Re[i], Pr[i], T[i], T_wall_right[i])` for right HTC
  - `ChannelHeatFlux`: no thermal port → passes `(Re[i], Pr[i], T[i], T[i])`

### elenbaas_nusselt standalone correlation
- Signature: `elenbaas_nusselt(Ra, b, L)` — plain Julia function, NOT `@register_symbolic`
- Formula (from Python STREAM `_Elenbaas`):
  `Nu = (1/24) * Ra * (b/L) * (1 - exp(-35 * L / (Ra * b)))^0.75`
  where `b` = gap between plates (depth), `L` = heated length
- Goes in `src/physical_models/correlations.jl` alongside `dittus_boelter` etc.

### elenbaas_htc factory
- Signature: `elenbaas_htc(; b, L, Dh, g=9.81)` — factory capturing geometry and gravity at construction time
- Returns `(Re, Pr, T_bulk, T_wall) -> Nu` closure:
  ```julia
  function elenbaas_htc(; b, L, Dh, g=9.81)
      return (Re, Pr, T_bulk, T_wall) -> begin
          beta   = beta_water(T_bulk)
          nu     = mu_water(T_bulk) / rho_water(T_bulk)
          Gr_val = Gr(beta, g, T_wall - T_bulk, Dh, nu)
          Ra_val = Ra(Gr_val, Pr)
          elenbaas_nusselt(Ra_val, b, L)
      end
  end
  ```
- `g` is a factory parameter (default 9.81 m/s²); caller can override for non-standard gravity
- When used with `Channel` (T_wall = T_bulk), `dT = 0` → `Ra = 0` → `Nu = 0` — physically
  correct (no wall temperature difference, no natural convection driving force)
- Goes in `src/physical_models/correlations.jl`

### beta_water fluid property
- Signature: `beta_water(T_K)` — temperature in Kelvin (matches all other Julia fluid functions)
- `@register_symbolic` (same as `rho_water`, `cp_water`, etc.) — callable from any MTK equation
- Formula: derived analytically from the Simantov density formula (same approach as Python STREAM `_thermal_expansion`):
  `beta = -1.8 * (B + 2*C*TF) / rho_water(T_K)` where `TF = _to_fahrenheit(T_K - 273.15)`,
  `B = -0.046283`, `C = -7.9738e-4`
- Goes in `src/fluids.jl` alongside the other Simantov fluid properties

### dimensionless.jl — new file
- Create `src/physical_models/dimensionless.jl` mirroring Python STREAM's `dimensionless.py`
- Full initial set (all plain Julia functions, all exported):
  - `Re(mdot, A, Dh, mu)` — Reynolds from mass flow rate
  - `Re_vel(rho, u, L, mu)` — Reynolds from velocity (optional alias)
  - `Pr(cp, mu, k)` — Prandtl
  - `Nu(h, Dh, k)` — Nusselt
  - `Pe(Re_val, Pr_val)` — Péclet = Re·Pr
  - `Gr(beta, g, dT, L, nu)` = `beta * g * dT * L^3 / nu^2`
  - `Ra(Gr_val, Pr_val)` = `Gr_val * Pr_val`
  - `flow_regimes(re, bounds)` — laminar/interim/turbulent masks (matches Python STREAM signature)
- None of these are `@register_symbolic` — plain arithmetic, MTK traces through them
- All future dimensionless number utilities go here

### Gr and Ra signatures
- `Gr(beta, g, dT, L, nu)` — simplified vs. Python STREAM; caller pre-computes `dT = T_wall - T_bulk` and `nu = mu/rho`
- `Ra(Gr_val, Pr_val)` — takes pre-computed Gr and Pr; `Ra = Gr * Pr`
- These are utility functions for user code and for `elenbaas_htc` factory internals

### Validation for NATCONV-02
- Validate `elenbaas_nusselt` by calling Python STREAM's `_Elenbaas` at identical inputs
  (same rho, mu, cp, k, beta, T, Twall, b/S, L/Lh) and asserting Nu matches within `1e-6` rtol
- Same validation pattern used in all prior phases (Python STREAM as reference oracle)
- Test goes in `test/test_correlations.jl` (standalone correlation unit test, no MTK needed)

### Claude's Discretion
- Exact docstring wording for dimensionless.jl functions
- Whether `Re_vel` alias is worth adding alongside `Re(mdot,...)`
- Test parameter values for the Elenbaas Python STREAM comparison (pick physically realistic MTR-scale inputs)
- Whether `flow_regimes` uses `Vector` or scalar inputs in the Julia version

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §Fluid Properties — FLUID-01, FLUID-02, FLUID-03
- `.planning/REQUIREMENTS.md` §Natural Convection HTC — NATCONV-01, NATCONV-02

### Python STREAM reference implementations
- `~/projects/STREAM/stream/substances/light_water.py` — `_thermal_expansion(T)`: beta formula (analytically derived from Simantov density)
- `~/projects/STREAM/stream/physical_models/natural_convection.py` — `_Elenbaas(...)` and `Elenbaas_h_spl(...)`: exact correlation formula and Python STREAM call site
- `~/projects/STREAM/stream/physical_models/dimensionless.py` — all dimensionless number utilities; use as the reference set for `dimensionless.jl`

### Existing source files to modify
- `src/fluids.jl` — add `beta_water(T_K)` and `@register_symbolic beta_water`
- `src/physical_models/correlations.jl` — add `elenbaas_nusselt`, `elenbaas_htc`; update `args...` splatting on all existing correlations; update `regime_dependent` to pass 4 args through
- `src/components/channel.jl` — update HTC correlation call site to pass `(Re[i], Pr[i], T[i], T[i])`
- `src/components/thermal_channel.jl` — update call sites in `ChannelAndContacts` and `ChannelHeatFlux`
- `src/STREAM.jl` — add `include("physical_models/dimensionless.jl")` and export all new names

### New file
- `src/physical_models/dimensionless.jl` — create; mirrors Python STREAM `dimensionless.py`

### Existing test files
- `test/test_correlations.jl` — add Elenbaas standalone unit test (Python STREAM comparison)
- `test/test_fluids.jl` — add `beta_water` unit test
- `test/runtests.jl` — no new include needed (dimensionless functions tested within existing files)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_to_fahrenheit` in `fluids.jl` — already used by rho_water; beta_water needs the same Fahrenheit conversion
- `rho_water(T_K)` in `fluids.jl` — beta formula calls `rho_water` in the denominator (same as Python STREAM); already @register_symbolic, so calling it from beta_water is fine
- `correlations.jl` factory pattern — `constant_Nusselt`, `laminar_friction`, `regime_dependent` show the exact pattern for `elenbaas_htc`

### Established Patterns
- `@register_symbolic` at module top-level in `fluids.jl` — beta_water follows this exactly
- Plain Julia closures for HTC correlations (NOT @register_symbolic) — elenbaas_nusselt and elenbaas_htc follow this
- `args...` splatting is the zero-friction way to make existing 2-arg correlations accept extra context args without breaking call sites

### Integration Points
- `Nu[i] ~ htc_correlation(Re[i], Pr[i])` in `channel.jl` and `thermal_channel.jl` — these become `htc_correlation(Re[i], Pr[i], T[i], T_wall_X[i])` after the interface extension
- `STREAM.jl` exports list — add `beta_water`, `Gr`, `Ra`, `Re`, `Pr`, `Nu`, `Pe`, `flow_regimes`, `elenbaas_nusselt`, `elenbaas_htc`

</code_context>

<specifics>
## Specific Ideas

- `dimensionless.jl` should be the permanent home for all dimensionless number utilities going forward — any new ones (e.g., Eckert number, Fourier number) go here automatically
- Python STREAM `_Elenbaas` is decorated with `@njit` (Numba) — the Julia equivalent is just plain Julia (already fast); no special annotation needed

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 21-fluid-properties-natural-convection*
*Context gathered: 2026-03-17*

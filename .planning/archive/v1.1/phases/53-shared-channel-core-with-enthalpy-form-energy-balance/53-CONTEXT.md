# Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance - Context

**Gathered:** 2026-05-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Extract a single private `_channel_core(...)` function that is the only source of truth for: energy balance (now in **enthalpy form** with face-averaged cp), mass conservation, momentum ODE `(L/A)·D(mdot)`, friction `dp[i]`, port wiring, and observables (Re, Pe, v, P[i], dP, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out). Switch the convective term to enthalpy form (face-averaged cp `(cp(T_up) + cp(T[i])) / 2`, with `cp(instream(...))` at the boundary face) in the same change since both touch the same equation.

This phase ships **the shared core + the energy-balance switch only**. It does NOT rewrite the public variants (`Channel`, `ChannelHeatFlux`, `ChannelAndContacts`) — those move onto the new core in Phase 54. Phase 53 closes when `_channel_core` exists, `_channel_base_eqs` is gone, all three flag knobs (`observed_mode`, `skip_htc`, `T_wall_cells=nothing`) are gone, and the new core is verified against Python STREAM's enthalpy-form formula on placeholder test scaffolding.

File consolidation (`channel.jl` + `thermal_channel.jl` → `channels.jl`) is Phase 54's mandate, not this phase's. Phase 53 leaves the existing two files in place; the variants continue to compile against the old `_channel_base_eqs` until Phase 54 rewires them.

</domain>

<decisions>
## Implementation Decisions

### Core API shape (Area 1)

- **D-01: Structured return.** `_channel_core(...)` returns `(; eqs, obs)` (a `NamedTuple` of two `Vector{Equation}`). Variant call site:
  ```julia
  core = _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
                        friction_correlation, q_left_expr, q_right_expr)
  eqs = [variant_specific_eqs; core.eqs]
  obs = [core.obs; variant_specific_obs]
  System(eqs, t, all_vars, pars; observed=obs, name=name) |> sys -> compose(sys, port_in, port_out, ...)
  ```
  *Why:* Pure data flow is the most Julia-onic shape for cold construction code. The split between core-owned and variant-owned equations is visually obvious in the variant constructor; the core is trivial to test (just inspect the returned lists). Eqs-mutator was rejected because it doubles down on the no-`!`-suffix mutation already in the codebase. Partial-System+`extend()` was rejected because the base depends on `n` and shared array-vars (`T[1:n]`, `dp[1:n]`) would have to be threaded across the boundary — awkward for this shape despite being most "MTK-pure" for OnePort-style components.

- **D-02: `q_left_expr` / `q_right_expr` are length-n `Vector{Num}` inputs.** Variants pre-build the expression vectors and pass them in; core indexes `q_left_expr[i]` / `q_right_expr[i]` per cell. Per-variant q construction:
  - **`Channel`** (Phase 54, passive recipient via `WallPort`): `q_left_expr[i] = thermal_left[i].h * geometry.heated_parts[1] * dz * (thermal_left[i].T_wall − T[i])`. Adiabatic-when-unconnected via Phase 52's drive-aware pattern (port self-anchors `T_wall ~ T_default; h ~ 0`).
  - **`ChannelHeatFlux`** (Phase 54, direct flux via `HeatFluxPort`): `q_left_expr[i] = thermal_left[i].q_flux * geometry.heated_parts[1] * dz`. No reference to `T[i]` in the q expression.
  - **`ChannelAndContacts`** (Phase 54, correlation-driven via `ThermalPort`): variant builds its own `h_tc[i]` equations (with optional SCB), then `q_left_expr[i] = h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T − T[i])`.
  - **Test scaffold (Phase 53):** placeholder `q_left_expr = q_test_left` and `q_right_expr = q_test_right` where the test harness provides driven values to exercise every code path inside core.
  *Why:* Uniform additive contribution to the energy balance — `Dt(T[i]) ~ (advection + q_left_expr[i] + q_right_expr[i]) / (ρ·cp(T[i])·A·dz)` — needs no flag plumbing inside core. One-sided heating is just `q_right_expr = fill(0, n)`. CORE-01 explicitly mandates this signature.

- **D-03: `htc_correlation` is variant-internal; `friction_correlation` stays in core.** In the new design only `ChannelAndContacts` uses an HTC correlation (`Channel` consumes external `h` from `WallPort`; `ChannelHeatFlux` consumes external `q_flux` from `HeatFluxPort`). Friction is identical across all three variants (same Darcy–Weisbach + gravity formula at every cell). Final core signature:
  ```julia
  _channel_core(;
      n,                                            # cell count
      T,                                            # variant-declared @variables (T(t))[1:n]
      dp,                                           # variant-declared @variables (dp(t))[1:n]
      port_in, port_out,                            # variant-created FlowPorts
      geometry,                                     # PipeGeometry
      g_acc,                                        # gravitational acceleration (m/s²)
      friction_correlation=blasius_friction,        # shared by all variants
      q_left_expr,                                  # length-n Vector{Num}, variant-built
      q_right_expr,                                 # length-n Vector{Num}, variant-built
  )::NamedTuple{(:eqs, :obs)}
  ```
  *Why:* Putting `htc_correlation` in core would mean carrying a knob that only one variant uses — that's exactly the flag accretion the v1.1 milestone exists to eliminate. Friction is genuinely shared and stays.

- **D-04: No `htc_correlation`, no `Re/Nu` in or out of the function signature.** Re is computed *inside* core as an observable (depends only on mdot/T/geometry — q-agnostic). Nu and h_tc are CAC-only (they reference variant-specific symbols and an htc_correlation that core doesn't see) and live entirely inside `ChannelAndContacts`.

### Energy balance — enthalpy form (Area 2)

- **D-05: Boundary-face cp uses the same averaging formula as interior faces.** At every cell `i`, the face-averaged cp is `(cp(T_up) + cp(T[i])) / 2`. The "boundary face" of cell 1 (forward flow) is the same averaging with `T_up = instream(port_in.T)`; cell n (reverse flow) is `T_up = instream(port_out.T)`. Selection via the same `ifelse(mdot ≥ 0, ...)` that already picks `T_up` itself — flow-reversal symmetry is automatic because both `T_up` and `cp(T_up)` flip in lockstep.
  *Why:* Verified against Python STREAM `stream/calculations/channel.py:158-162`:
  ```python
  c_bulk = fluid.specific_heat(T)
  cin = fluid.specific_heat(Tin)
  c = directed(pair_mean_1d(directed(c_bulk, mdot), prepend=cin), mdot)
  ```
  And `stream/utilities.py:359-376` (`pair_mean_1d` with `prepend=cin`) shows the boundary face is `(cin + a[0]) / 2 = (cp(T_in) + cp(T[1])) / 2` — same averaging as interior, just with `T_up = T_in`. Reverse flow uses `directed(arr, mdot)` to flip the array, which implicitly substitutes the cell-n boundary `cp(T_in_reverse)` and `cp(T[n])`.

- **D-06: Energy balance equation per cell:**
  ```julia
  cp_face = (cp_water(T_up) + cp_water(T[i])) / 2     # face-averaged cp using ifelse-selected T_up
  Dt(T[i]) ~ (
      abs(port_in.mdot) * cp_face * (T_up - T[i])
    + q_left_expr[i]
    + q_right_expr[i]
  ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
  ```
  Numerator: face-averaged cp; denominator: local `cp(T[i])` (Python's `c_bulk`). The two cp values do NOT cancel (NRG-03).

- **D-07: Flow reversal:** the same `ifelse(mdot ≥ 0, T_up_fwd, T_up_rev)` expression that already selects `T_up` is used implicitly to select `cp(T_up)` because `cp_water` is a deterministic function. No second `ifelse` for cp is needed — selection happens once at the `T_up` level. (NRG-04.)

### Observables ownership (Area 3)

- **D-08: Maximal core + per-side q stubs.** `_channel_core` emits the following observables (everything that's a pure function of inputs already passed to it):
  - **q-agnostic observables:** `Re[i]`, `Pe[i]`, `v[i]`, `T_out`, `P[i]`, `dP`, `T_sat[i]`
  - **q-derived observables:** `q_wall[i]` (= `q_left_expr[i] + q_right_expr[i]`), `q_wall_left[i]` (= `q_left_expr[i]`), `q_wall_right[i]` (= `q_right_expr[i]`), `T_ONB[i]` (uses `q_wall[i] / (sum(geometry.heated_parts) * dz)` as the heat flux density input to `_bergles_rohsenow_dT_ONB`)
  *Why:* These are all pure functions of inputs already in core's hands. Emitting them once eliminates per-variant boilerplate and prevents the kind of subtle drift the current code already shows (e.g., one variant defines `v` as `mdot/(ρ·A)`, another as `abs(mdot)/(ρ·A)`).

- **D-09: Variants own only what depends on variant-specific symbols:**
  - `ChannelAndContacts`: `h_tc[i]`, `Nu[i]`, `h_tc_left[i]`, `h_tc_right[i]`, `T_wall_left[i]`, `T_wall_right[i]`, `Gr_over_Re2[i]`, plus `Q_wall_total` if retained
  - `Channel` (Phase 54): per-side aliases over `WallPort` symbols (e.g. `h_left[i] ~ thermal_left[i].h`, `T_wall_left[i] ~ thermal_left[i].T_wall`) — these are simple aliases, not new equations
  - `ChannelHeatFlux` (Phase 54): per-side `q_flux_left/right` aliases over `HeatFluxPort` symbols, if useful
  *Why:* These reference symbols (`thermal_*[i].h`, `thermal_*[i].T_wall`, `thermal_*[i].q_flux`, `h_tc[i]`) that core doesn't see and shouldn't see — the variant connector type determines which exist.

- **D-10: Observable variable declarations.** All observable LHS variables (`Re[i]`, `Pe[i]`, `v[i]`, `P[i]`, `T_sat[i]`, `T_ONB[i]`, `dP`, `T_out`, `q_wall[i]`, `q_wall_left[i]`, `q_wall_right[i]`) are declared in the variant's `@variables` block (matching the existing pattern where variants own their `@variables` declaration). Core builds equations referencing these by symbol — variant must declare them with the names core expects. *Implementation detail for the planner:* either the variant lists all the obs symbols inline, or a small helper `_channel_core_obs_vars(; n)` returns a named tuple of pre-declared `@variables` for the variant to splat. Planner picks based on call-site readability.

### Phase-53 verification depth (Area 4)

- **D-11: Two-stage analytical verification on placeholder test scaffolding** (in addition to the ROADMAP-mandated single-cell forward/reverse mirror test and the code-path-coverage check).
  - **Stage 1 — Constant-cp limit (sanity):** Build a stub channel via the new `_channel_core` with placeholder q exprs that drive a small dT (~1 K). With cp(T) approximately constant over that range, the new enthalpy form must degenerate to the old form to within ~1e-6 rtol. Compare T_out / mdot / per-cell T[i] against v1.0 numerical baseline values captured before the energy-balance switch (extracted from a current `Channel` solve on the same geometry). *Catches gross structural errors* — wrong indexing, wrong sign, wrong port wiring.
  - **Stage 2 — Realistic cp variation (Python parity):** Build a stub channel that drives a ~30 K rise (real cp(T) variation, ~3% of cp_water at typical reactor conditions). Hand-compute the expected `T_out` offline using Python STREAM's exact `pair_mean_1d` formula on the same geometry/q profile. Assert match within ~1e-9 rtol. *Catches drift in the cp-averaging itself* — exactly the regime where the enthalpy form differs from constant-cp-effective. This is the gate that ensures Phase 54/55 are building on a Python-faithful core, not waiting until Phase 56 for the discrepancy to surface.
  *Why:* `feedback_design_validation_rigor` — don't declare a design viable without numerical parity against the proven baseline. Phase 56 is three phases away; without Phase 53 verification, any drift gets compounded by Phase 54 variant rewrites and Phase 55 full re-wiring before Python parity is checked. Two-stage local verification turns Phase 53 into a self-validating gate.

- **D-12: Test scaffolding lives in `test/test_channel.jl` (or a new `test/test_channel_core.jl`)**. The scaffolding is a minimal stub system that creates `T`, `dp`, `port_in`, `port_out`, calls `_channel_core` with driven `q_*_expr` values, composes into a tiny test loop (Pump → stub → Pump), and runs `solve_steady` / `solve_transient`. *Planner picks the file location* — both placements respect the CLAUDE.md test placement rule (test file mirrors src file).

### Implementation strategy — out of scope to lock here

- **D-13:** Commit granularity (atomic single-step rewrite vs. extract-then-switch-then-delete vs. switch-then-extract) is a planning concern, not a context concern. The planner picks based on what gives the cleanest atomic commits. Note for the planner: the existing variants (`Channel`, `ChannelHeatFlux`, `ChannelAndContacts`) must continue to compile and pass their existing tests at every commit boundary inside Phase 53 — they still call `_channel_base_eqs` until Phase 54 rewires them. This means `_channel_core` must coexist with `_channel_base_eqs` until the final commit of Phase 53 deletes the old helper.

- **D-14: `Q_wall_total` decision (CAC-only convenience).** Currently CAC has `Q_wall_total ~ sum(q_wall[i])` as an observable. With `q_wall[i]` now in core, CAC's `Q_wall_total` is just `sum(core_q_wall[i])` — keep it as a CAC-side observable for backward compatibility. Not a core concern.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance" — phase goal, dependencies, 5 success criteria
- `.planning/REQUIREMENTS.md` §"Shared Core" — CORE-01..05 verbatim (signature mandate, deletion mandate, no-flag mandates)
- `.planning/REQUIREMENTS.md` §"Energy Balance Scheme (Enthalpy Form)" — NRG-01..04 verbatim (face-averaged cp formula, boundary cp from instream, local cp denominator, flow-reversal symmetry)
- `.planning/PROJECT.md` §"Current Milestone: v1.1 Final Channel-Family Redesign" — milestone goal ("never need touching again"), constraints (no flag accretion permitted)

### Prior decisions to honor
- `.planning/STATE.md` §"Key Decisions (carry-forward)" — v1.1 phasing rationale (CORE-* + NRG-* bundled because both touch the energy balance), CONN spike rationale (array-of-scalar pattern locked, vector-form rejected), drive-aware pattern from Phase 52 (D-A2-1 in 52-CONTEXT.md, applied by Phase 54 — context for what `q_left_expr` will look like)
- `.planning/phases/52-channel-connectors/52-CONTEXT.md` — full Phase 52 connector contract that Phase 54 builds on (Phase 53 doesn't directly touch connectors, but the variant rewrites it sets up will)
- `CLAUDE.md` §"File Structure Standard" — `src/components/channel.jl` and `src/components/thermal_channel.jl` are the touched files (consolidation deferred to Phase 54); test placement rule mirrors src
- `CLAUDE.md` §"MTK Patterns" — `ifelse()` (not `if`/`else`) for any conditional inside MTK equations including `ifelse(mdot ≥ 0, T_up_fwd, T_up_rev)`; `mtkcompile` before solve; `@register_symbolic` boundary for `cp_water` / `rho_water` / etc.; `@observed` vs unknowns distinction (`Re`, `Pe`, `v`, `P`, `T_sat`, `T_ONB`, `q_wall`, `dP` are observed; `T`, `dp` are unknowns)
- `CLAUDE.md` §"Component authoring conventions" — internal helper underscore-prefix (`_channel_core` is private, not exported); `name` keyword-only on variant constructors

### Existing code (read before extending)
- `src/components/channel.jl` §`_channel_base_eqs` (lines 172-249) — the helper being deleted; current pattern (mutator, `observed_mode` / `skip_htc` / `T_wall_cells=nothing` flags) is what NEW core MUST replace, not extend
- `src/components/channel.jl` §`Channel` (lines 26-144) — current Channel constructor with its own internal htc_correlation; this body becomes much smaller in Phase 54 once `_channel_core` carries the shared physics
- `src/components/thermal_channel.jl` §`ChannelAndContacts` (lines 48-241) — current CAC, including the SCB-corrected `h_tc[i]` equations and the dual-port two-sided energy balance; Phase 54 simplifies this onto `_channel_core` while preserving the `scb_correction=...` keyword and the full observable surface (h_tc_left/right, T_wall_left/right, Gr_over_Re2, Q_wall_total)
- `src/components/thermal_channel.jl` §`ChannelHeatFlux` (lines 273-396) — current ChannelHeatFlux with scalar `T_wall_p` parameter; Phase 54 replaces this with `q_flux` from `HeatFluxPort` arrays, but the dp/observables structure is the same shape `_channel_core` will produce
- `src/connectors.jl` — `WallPort`, `HeatFluxPort`, `ThermalPort`, `FlowPort` definitions; Phase 53 doesn't modify these but uses `port_in.mdot` / `port_in.P` / `instream(port_in.T)` extensively in core
- `src/fluids.jl` — `cp_water`, `rho_water`, `mu_water`, `k_water` `@register_symbolic` functions; the new face-averaged cp uses `cp_water(T_up)` and `cp_water(T[i])` per cell
- `src/physical_models/friction/` — `blasius_friction`, `laminar_friction`, etc.; the friction_correlation kwarg dispatch in `_channel_core` consumes these closures
- `src/STREAM.jl` — current export list and `include()` order; `_channel_core` is internal (NOT exported); `_channel_base_eqs` removal must be reflected if it was ever export-listed (it isn't — verify)

### Python STREAM reference (validation gate)
- `/home/itayb/projects/STREAM/stream/calculations/channel.py` lines 110-167 — the `_temperature_derivative` function. **This is the byte-for-byte target for the enthalpy-form energy balance.** Includes the docstring formula `m·c_p·dT/dt = (1/2)·mdot·(c_{p,i}+c_{p,i-1})·(T_{i-1}-T_i) + h·Π·(T_wall,i - T_i)`, and the implementation:
  ```python
  rho = fluid.density(T); c_bulk = fluid.specific_heat(T); cin = fluid.specific_heat(Tin)
  c = directed(pair_mean_1d(directed(c_bulk, mdot), prepend=cin), mdot)
  convection = directed(np.abs(mdot) * c * np.diff(directed(T, mdot), prepend=Tin), mdot)
  heat_transfer = dz * (q_left * pipe.heated_parts[0] + q_right * pipe.heated_parts[1])
  heat_capacity = rho * c_bulk * pipe.area * dz
  return (heat_transfer - convection) / heat_capacity
  ```
- `/home/itayb/projects/STREAM/stream/utilities.py` lines 359-376 — `pair_mean_1d(arr, prepend=cin)` implementation: interior `(arr[i-1] + arr[i])/2`, boundary `(prepend + arr[0])/2`. **Confirms boundary face uses the same averaging as interior — Phase 53 D-05 is verified against this code.**
- `/home/itayb/projects/STREAM/stream/utilities.py` lines 537-551 — `directed(arr, mdot)` flow-reversal helper. **Confirms reverse-flow symmetry: array is flipped under `mdot < 0`, so cell-n becomes the new boundary cell.**

### Test references
- `test/test_channel.jl` — existing CHAN-*, GRAV-*, THERM-*, PHY-* tests on Channel/ChannelHeatFlux/ChannelAndContacts. Phase 53 ADDS the placeholder-scaffold tests for `_channel_core`; existing tests remain green because variants still call `_channel_base_eqs` until Phase 54.
- `test/test_connectors.jl` — Phase 52's stub patterns (`_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`); reference for the placeholder-scaffold style Phase 53 will use
- `test/runtests.jl` — orchestrator; if Phase 53 adds a new test file it must be wired in here

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_channel_base_eqs` body (`src/components/channel.jl:172-249`)** — most of its structural logic (per-cell `dp[i]`, mass cons, momentum ODE, port-stream wiring, `T_out`) ports directly into `_channel_core`. The deletion path is: extract logic into `_channel_core` minus the three flags, switch the convective term to enthalpy form, point variants at `_channel_core` (Phase 54), delete `_channel_base_eqs`.
- **Per-cell observable expressions in `ChannelAndContacts` (`src/components/thermal_channel.jl:196-224`)** — P[i] (with distributed inertia correction), T_sat[i], T_ONB[i] formulas already exist. Move into core as the canonical source. Note: P[i] formula is identical across all three current variants — confirms it belongs in core.
- **`partial_SCB_correction`, `_bergles_rohsenow_dT_ONB`, `sat_temperature` (`src/physical_models/`, `src/fluids.jl`)** — used by core's T_ONB observable. No changes; just call from core instead of from each variant.
- **Phase 52's `_StubRecipient` pattern (`test/test_connectors.jl`)** — direct precedent for how Phase 53 builds its placeholder test scaffolding. Same shape, slightly different goal (exercise core's energy balance vs. exercise connector adiabatic-default).

### Established Patterns
- **Variant declares all `@variables`, helper consumes by reference** — current `_channel_base_eqs` already follows this; new `_channel_core` keeps the same contract. Variant's `@variables begin ... end` block declares `T`, `dp`, plus any obs vars core will reference (Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, dP, T_out). Core builds equations using those symbols.
- **`ifelse()` for flow reversal** — `ifelse(port_in.mdot ≥ 0, T_up_fwd, T_up_rev)` already in all three variants. New core uses the same idiom; cp(T_up) is implicitly selected because `cp_water` is a deterministic function of the ifelse-selected T_up.
- **`instream(port_in.T)` / `instream(port_out.T)` for boundary face values** — current channels use this for `T_inlet_fwd` / `T_inlet_rev`. Core uses the same pattern, and now also passes the result into `cp_water(...)` for boundary face cp.
- **Observed equations as pure expressions of unknowns (no observed-to-observed chains)** — current code carefully inlines `Re_i`, `P_i`, `q_spl_i` etc. to avoid cyclic observed dependencies. Core preserves this discipline; e.g., T_ONB[i] uses inlined `(q_left_expr[i] + q_right_expr[i]) / (sum(heated_parts) * dz)` for the heat flux density, not the `q_wall[i]` symbol.
- **Per-cell distributed-inertia P[i] formula** (D-04/D-05/D-06 from earlier phases): `P[i] ~ port_in.P − Σ_{j≤i} dp[j] − (i/n)·((port_in.P − port_out.P) − Σ_all dp[j])`. Identical across variants; goes into core unchanged.

### Integration Points
- **`src/components/channel.jl`** — receives `_channel_core` definition. `_channel_base_eqs` deletion happens at the final commit of Phase 53 (after variants are confirmed unaffected). Keep the file in place for Phase 54 to consolidate.
- **`src/components/thermal_channel.jl`** — UNCHANGED in Phase 53. Variants continue calling `_channel_base_eqs`. Phase 54 rewires them onto `_channel_core` and consolidates the file.
- **`src/STREAM.jl`** — no export change (`_channel_core` is private). Verify `_channel_base_eqs` is also not exported (it isn't — internal helper).
- **`test/runtests.jl`** — if Phase 53 adds a new `test_channel_core.jl`, wire it in here. Otherwise tests append to `test/test_channel.jl`.
- **`test/test_validation.jl`** — Python STREAM cross-validation (VAL-* tests). Phase 53 does NOT touch these; they're Phase 56's gate. But: Phase 53's stage-2 hand-computed test conceptually mirrors what test_validation.jl will do at Phase 56, just on a stub system instead of the full reference loop.

</code_context>

<specifics>
## Specific Ideas

- The user pushed back on an early lazy-shaped proposal that put `htc_correlation` in core's signature. The corrected scope (htc-correlation is variant-internal; only friction stays in core) was reached by working through each variant's q construction in the new design and noticing that only CAC needs the correlation. This is documented as D-03 above.
- Phase 53's verification depth was deliberately set higher than ROADMAP minimum because of `feedback_design_validation_rigor` and the three-phase distance to Phase 56. The two-stage analytical check (constant-cp limit + Python pair_mean_1d hand-compute) is the gate that lets Phase 54 build with confidence.
- The boundary-face cp question (`cp(T_in)` vs. `(cp(T_in) + cp(T[1])) / 2`) was resolved by reading Python STREAM source directly rather than guessing. `pair_mean_1d` with `prepend=cin` produces `(cin + arr[0]) / 2` at index 0 — the boundary face uses the same averaging as interior. Documented as D-05.

</specifics>

<deferred>
## Deferred Ideas

- **Variant rewrites onto `_channel_core`** — Phase 54. `Channel` becomes a thin passive recipient over `WallPort`; `ChannelHeatFlux` consumes `q_flux` from `HeatFluxPort`; `ChannelAndContacts` keeps its h_tc/SCB logic but delegates everything else to core.
- **File consolidation `channel.jl` + `thermal_channel.jl` → `channels.jl`** — Phase 54 (VAR-04). Phase 53 leaves both files in place; consolidating mid-extract would conflate "extract the core" with "rename the files" and make commits harder to bisect.
- **Composition helper updates** for the new connector-driven Channel/ChannelHeatFlux — Phase 55.
- **Cross-validation against Python STREAM under the new convective scheme** — Phase 56. Phase 53's stage-2 hand-computed test is a *local* parity check, not a full system-level check; Phase 56's `test_validation.jl` against `build_loop_pk` etc. is the milestone gate.
- **Implementation strategy / commit granularity** — planning concern, not context. Planner picks based on what produces the cleanest atomic commits; constraint is that variants must continue to compile and pass tests at every commit boundary inside Phase 53.

</deferred>

---

*Phase: 53-Shared `_channel_core` with Enthalpy-Form Energy Balance*
*Context gathered: 2026-05-06*

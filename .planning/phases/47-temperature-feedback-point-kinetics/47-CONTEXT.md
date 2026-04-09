# Phase 47: Temperature Feedback for PointKinetics — Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Extend `PointKinetics` (callable mode) with temperature feedback: per-cell weighted temperature
reactivity from any number of Channel/ChannelAndContacts/ChannelHeatFlux/HeatDiffusion components.
**PointKinetics holds all responsibility** — alpha weights and reference temperatures live in PK.
Connected components expose their existing `T[...]` variables unchanged.
No SCRAM callback wiring (Phase 49). No new ports on channel/plate components.

</domain>

<decisions>
## Implementation Decisions

### Temperature Feedback API (D-01) — G1 resolved
- **D-01:** `temp_worth` + `ref_temp` kwargs on the existing callable constructor:

  ```julia
  @named pk = PointKinetics(ctrl;
      temp_worth = Dict(ch  => fill(-0.001, n_cells),   # per-cell [Δk/k per K]
                        fuel => fill(-0.002, nz, nx)),  # 2D matrix for HeatDiffusion
      ref_temp   = Dict(ch  => fill(293.0, n_cells),    # reference temperature [K]
                        fuel => fill(600.0, nz, nx)))   # zeros if omitted
  ```

  - `temp_worth`: `Dict{System, Union{Real, AbstractArray}}` — keys are uncompiled MTK Systems
    (the same objects built with `@named`). Values are per-cell weights:
    - Scalar → broadcast to all cells of that component
    - 1D vector `[1:n]` → matches Channel n-cell structure
    - 2D matrix `[1:nz, 1:nx]` → matches HeatDiffusion nz×nx structure
  - `ref_temp`: same key structure. If a key is absent or `ref_temp` is omitted entirely,
    that component's reference is zero.
  - `temp_worth=nothing` (default): no temperature feedback; falls back to Phase 46 behavior.

### Reactivity Composition (D-02)
- **D-02:** Total reactivity in the power ODE:
  ```
  rho_total(t) = rho_val + rho_c_fn(t) + sum_k( dot(alpha_k_flat, T_source_k .- T_ref_k_flat) )
  ```
  where `alpha_k_flat` and `T_ref_k_flat` are inlined constants (not MTK parameters) baked
  into the equation at construction time. Sign convention: negative alpha = stabilizing
  (negative temperature coefficient), matching Python STREAM `temp_worth` semantics.

### Internal T_source Variables (D-03)
- **D-03:** For each component in `temp_worth`, PK creates a flat array of unknown state variables:
  `T_source_{comp_name}[1:n_flat](t)` where `comp_name = comp.name` (the Symbol of the System).
  - Channel/ChannelAndContacts/ChannelHeatFlux: `n_flat = n_cells` (1D)
  - HeatDiffusion: `n_flat = nz * nx` (2D flattened row-major)
  
  These unknowns are **free variables** in the standalone PK system — they gain binding equations
  only when the composed system includes `connect_temperature_feedback` output.

### Connection Helper (D-04) — replaces any port mechanism
- **D-04:** New composition helper in `src/composition/helpers.jl`:
  ```julia
  connect_temperature_feedback(pk, temp_worth) -> Vector{Equation}
  ```
  Generates one equation per cell for each component:
  ```julia
  pk.T_source_ch[j] ~ ch.T[j]            # for Channel/ChannelAndContacts/ChannelHeatFlux
  pk.T_source_fuel[j] ~ fuel.T[jz, jx]  # for HeatDiffusion (j = (jz-1)*nx + jx, row-major)
  ```
  Detection of component type: uses `size(alpha)` to infer 2D (HeatDiffusion) vs 1D (channel).
  Or dispatches on whether the component's `T` is 2D or 1D.

  User workflow:
  ```julia
  temp_worth = Dict(ch => alpha_ch_vec, fuel => alpha_fuel_matrix)
  @named pk  = PointKinetics(ctrl; temp_worth=temp_worth, ref_temp=ref_temp)
  @named sys = compose(...)
  feedback_eqs = connect_temperature_feedback(pk, temp_worth)
  full_sys = System([..., feedback_eqs...], t, [], []; systems=[pk, ch, fuel, ...])
  ```

### Components Are Unchanged (D-05)
- **D-05:** No modifications to `Channel`, `ChannelAndContacts`, `ChannelHeatFlux`, or
  `HeatDiffusion`. Their `T[1:n]` (channels) and `T[1:nz, 1:nx]` (HeatDiffusion) variables
  are referenced by the connection helper using `getproperty(comp, :T)` symbolics.
  Components do not need to know about PointKinetics.

### Constructor Dispatch (D-06)
- **D-06:** Temperature feedback is an add-on to the Phase 46 callable constructor only.
  The Phase 45 scalar constructor (`PointKinetics(; name, rho=0.0, ...)`) is unchanged.
  ```julia
  # Phase 45 — scalar mode (unchanged):
  PointKinetics(; name, rho=0.0, Lambda=..., beta_k=..., lambda_k=...)
  
  # Phase 46 — callable control, no feedback (unchanged):
  PointKinetics(rho_c_fn::Any; name, rho_val=0.0, ...)
  
  # Phase 47 — callable control + temperature feedback (new kwargs):
  PointKinetics(rho_c_fn::Any; name, rho_val=0.0, ...,
                temp_worth=nothing, ref_temp=nothing)
  ```
  When `temp_worth=nothing`, the behavior is identical to Phase 46.

### Alpha Inlining (D-07)
- **D-07:** Alpha weights and reference temperatures are **inlined constants** in the symbolic
  equations (same as `power_shape` in HeatDiffusion, same as the 6 beta/lambda constants in
  Phase 45). They are NOT MTK `@parameters`. Rationale: with n_cells=7 and 2 feedback elements,
  making them MTK parameters would add 14 alpha + 14 T_ref = 28 extra parameters. Inlining
  avoids this at the cost of requiring PK reconstruction to change weights.

### Observed Variable Update (D-08)
- **D-08:** The `reactivity` observed variable is updated to include the temperature feedback:
  ```julia
  reactivity ~ rho_val + rho_c_fn(t) + sum_k(dot(alpha_k_flat, T_source_k .- T_ref_k_flat))
  ```
  This makes the total reactivity visible post-solve, useful for diagnostics.

### File Layout (D-09)
- **D-09:** All changes in `src/components/point_kinetics.jl`. Connection helper added to
  `src/composition/helpers.jl`. Exports: `connect_temperature_feedback` added to `src/STREAM.jl`.
  Tests in `test/test_point_kinetics.jl`: new `@testset "TF-01: Temperature Feedback"` block.

### Python STREAM Alignment (D-10)
- **D-10:** API mirrors Python STREAM's `PointKinetics(temp_worth={ch: alpha}, ref_temp={ch: T0})`
  pattern as closely as Julia/MTK allows. Key difference: Python's aggregator passes `T` arrays
  imperatively at each timestep; Julia/MTK binds them symbolically via `T_source` unknowns and
  connection equations. Semantic result is identical: per-cell weighted temperature feedback.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 46 baseline
- `src/components/point_kinetics.jl` — existing callable constructor + ReactivityController;
  Phase 47 adds `temp_worth`/`ref_temp` kwargs and T_source unknowns to this file
- `.planning/phases/46-callable-control-reactivity-reactivity-controller/46-CONTEXT.md` —
  D-01 additive rho composition that Phase 47 extends

### MTK array variable creation pattern
- `src/components/heat_diffusion.jl` — HeatDiffusion creates `T[1:nz, 1:nx]` and
  `T_wall_left[1:nz]` etc. as dynamic-size array unknowns at construction time;
  exact syntax to replicate for `T_source_k[1:n_flat]`

### Composition helper patterns
- `src/composition/helpers.jl` — `compose_systems`, `symmetric_plate`, `plate`,
  `one_sided_connection` — follow the same Equation-returning pattern for
  `connect_temperature_feedback`

### Python STREAM reference
- `~/projects/STREAM/stream/calculations/point_kinetics.py` — `temperature_reactivity()`
  function (line 346), `PointKinetics.__init__` temp_worth/ref_temp kwargs (lines 201-234),
  `calculate()` method showing how T dict is passed (lines 262-294)
- `~/projects/STREAM/tests/test_general/test_integrations.py` — lines 201-267:
  `test_channel_point_kinetics()` shows full wiring with multiple channels and fuels;
  lines 352-428: two analytical validation tests (fuel feedback → power→0, coolant feedback → power→0)

</canonical_refs>

<requirements>
## Phase 47 Requirements

### TF-01: Temperature Feedback Constructor
PointKinetics callable constructor accepts `temp_worth=Dict(...)` and `ref_temp=Dict(...)`
kwargs. Dict keys are uncompiled MTK Systems; values are scalar or array matching component shape.
`temp_worth=nothing` falls back to Phase 46 behavior with zero rho_T.

### TF-02: Per-Cell Weighting
Scalar alpha broadcasts to all cells. 1D vector `[1:n]` applies per-cell to channels.
2D matrix `[1:nz, 1:nx]` applies per-cell to HeatDiffusion (flattened row-major).
Mismatch between alpha shape and component cell count → ArgumentError at construction.

### TF-03: ref_temp Default
`ref_temp` omission or missing keys default to zero reference. No error. Result: full T value
contributes when T_ref=0 (user is responsible for physically correct values).

### TF-04: Connection Helper
`connect_temperature_feedback(pk, temp_worth)` returns `Vector{Equation}` that binds
`pk.T_source_{name}[j]` to the corresponding `T` variable in each component.
Works for 1D channel T and 2D HeatDiffusion T (auto-flattens).

### TF-05: Components Unchanged
No changes to Channel, ChannelAndContacts, ChannelHeatFlux, or HeatDiffusion.
All existing tests continue to pass without modification.

### TF-06: Reactivity Observable
`reactivity` observed variable includes temperature feedback contribution.
Verifiable post-solve via `sol[pk.reactivity, :]`.

### TF-07: Analytical Validation
Test: with strong negative temperature feedback (alpha << 0), a step reactivity insertion
should cause power to peak then stabilize (power does not diverge). Compare peak time and
steady-state power against analytical expectation or Python STREAM's two integration tests:
- Fuel feedback: at steady state T_fuel → T_ref, power → 0 when T_ref is bath temperature
- Coolant feedback: same for T_cool → T_ref

</requirements>

<deferred>
## Deferred Ideas

- SCRAM callback wiring (SymbolicContinuousCallback calling change_state) — Phase 49
- `TemperatureFeedbackPort` connector type — unnecessary given the T_source unknown approach;
  only revisit if MTK structural analysis struggles with many free T_source unknowns
- Doppler broadening (energy-dependent feedback beyond linear alpha*dT) — v1.0+
- `temp_worth` as MTK parameters (tunable without reconstruction) — deferred until a user
  needs solve-time tuning of feedback coefficients

</deferred>

---

*Phase: 47-temperature-feedback-point-kinetics*
*Context gathered: 2026-04-04*

# Phase 55: Composition Helpers, Examples & Test Suite - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

This phase walks back **CONN-02 / `HeatFluxPort`** and re-architects the `Channel` and `ChannelHeatFlux` variants so that the args.funcs idiom from Python STREAM (provide a scalar / vector / function for an unequated value, system closes) works natively in Julia MTK — both via direct binding equations and via dedicated value-source components. Then it ports every downstream consumer (composition helpers if needed, all six shipped builders, all `examples/*.jl` scripts) to the new design, consolidates the test suite onto Python STREAM's organizational rules, and confirms the full local test suite is green vs the v1.0 baseline.

**Two architectural moves this phase makes (rebuilds parts of Phase 54):**

1. **Drop the per-cell ports on Channel and ChannelHeatFlux.** Replace `thermal_left[1:n]` / `thermal_right[1:n]` arrays with channel-level *external-input variables* `T_wall_left[1:n]` / `T_wall_right[1:n]` (Channel) and `q_left[1:n]` / `q_right[1:n]` (CHF). Phase 54 emitted `port.Q_flow ~ q_*_expr[i]` per cell; combined with the dangling-port Flow rule that auto-zeros `Q_flow`, this over-determined the system whenever a user added a binding equation on `port.T`. The Phase 54 deviation (file-local `_WallTempDriver` / `_FluxDriver` connected via `connect()`) was a workaround. The architectural rule (`feedback_channel_hd_connection_rule.md` — only `ChannelAndContacts` connects to `HeatDiffusion`) means Channel and CHF never needed Flow-based ports in the first place; removing them eliminates the over-determination root cause.

2. **Retire `HeatFluxPort` from `src/connectors.jl`.** With CHF dropping its per-cell ports, `HeatFluxPort` has no consumer. Delete from `connectors.jl`, `STREAM.jl` exports, and `test/test_connectors.jl`. Mirrors Phase 54's `WallPort` retirement. End-of-v1.1 connector roster: `FlowPort` (mass / momentum / stream T), `ThermalPort` (CAC ↔ HD only). `CONN-02` in REQUIREMENTS.md must be retroactively annotated as superseded.

**`ChannelAndContacts` is unchanged** — it keeps its `ThermalPort` arrays (`thermal_left[1:n]`, `thermal_right[1:n]`) because it must wire to `HeatDiffusion`, which uses Flow-based ports for heat balance. CAC remains the *only* variant that connects to `HeatDiffusion`.

**Downstream impact (within phase scope):**
- `composition/helpers.jl` — likely zero changes. Helpers exclusively wire CAC↔HD via ThermalPort. Verify and confirm.
- 3 simple-loop builders (`build_loop`, `build_loop_vertical`, `build_loop_transient`) — port to new Channel API.
- `build_loop_lof_bypass` — heated-leg redesign: spike both **CAC + WallTemperature** and **CAC + HeatDiffusion plate**, pick the winner empirically before plan-locking.
- `build_loop_pk` — CAC API unchanged; verify it still solves.
- `build_cube` — pure hydraulic network, no Channel; unchanged.
- `examples/simple_loop.jl`, `examples/lof_transient.jl`, `examples/mtr_assembly.jl` — port to new builder kwargs.
- Test suite — full reorganization onto Python STREAM rules.

**TEST-05 close gate:** `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl`) returns no NEW failures vs the v1.0 baseline. Pre-existing flakies (VAL-01 Fourier numerical, NET-03 Cube flow KINSOL convergence) remain tolerated per the v1.0 baseline.

**Not in scope (phase boundary anchor):**
- Cross-validation against Python STREAM (TEST-04, Phase 56).
- Any new HTC, friction, or fluid-property correlation (REQUIREMENTS Out-of-Scope table).
- HeatDiffusion redesign or new connector type beyond what this phase deletes.

</domain>

<decisions>
## Implementation Decisions

### Channel / ChannelHeatFlux architectural redesign (the central decision)

- **D-01: `Channel` drops per-cell ports.** Delete the `thermal_left[1:n]` / `thermal_right[1:n]` `ThermalPort` arrays from the new `Channel`. In their place, declare channel-level external-input variables:
  ```julia
  @variables T_wall_left(t)[1:n]   # external input — wall temperature on the left face
  @variables T_wall_right(t)[1:n]  # external input — wall temperature on the right face
  ```
  These have no internal equation. The user must supply values either by direct binding eqns or via a `WallTemperature` source component (D-04). Channel constructor signature post-redesign:
  ```julia
  Channel(;
      name,
      n::Int,
      geometry::PipeGeometry,
      g=0.0,
      h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
      h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
      friction_correlation = blasius_friction,
  )
  ```
  Identical to Phase 54 D-02 except the per-cell ports are gone.

- **D-02: `Channel` q-expression construction.** Per cell `i`, after evaluating `h_left` / `h_right` to per-cell scalars `hL_i` / `hR_i` (Real broadcast / Vector indexed / Function evaluated via callable parameter):
  ```julia
  q_left_expr[i]  = hL_i * geometry.heated_parts[1] * dz * (T_wall_left[i]  - T[i])
  q_right_expr[i] = hR_i * geometry.heated_parts[2] * dz * (T_wall_right[i] - T[i])
  ```
  No `port.Q_flow ~ ...` equation is emitted for either side — there is no port. Adiabatic by default falls out automatically: `h_left = h_right = 0.0` (default) makes both `q_*_expr[i]` zero regardless of `T_wall_*[i]`, which is then a free unknown that the user can leave unbound (the channel just doesn't react to it).

- **D-03: `ChannelHeatFlux` drops per-cell ports.** Delete the `thermal_left[1:n]` / `thermal_right[1:n]` `HeatFluxPort` arrays. Replace with channel-level external-input variables:
  ```julia
  @variables q_left(t)[1:n]    # external input — heat flux on the left face [W/m^2]
  @variables q_right(t)[1:n]   # external input — heat flux on the right face [W/m^2]
  ```
  Q-expression construction:
  ```julia
  q_left_expr[i]  = q_left[i]  * geometry.heated_parts[1] * dz
  q_right_expr[i] = q_right[i] * geometry.heated_parts[2] * dz
  ```
  CHF constructor signature unchanged from Phase 54 D-06 (no `T_wall`, no `htc_correlation`, no kwargs related to flux — flux is purely external).

- **D-04: Two value-source components shipped, both first-class STREAM components.** Create `src/components/sources.jl` (NEW file, follows the `connectors.jl` / `resistors.jl` plural-when-multiple-related-components pattern):
  ```julia
  WallTemperature(; name, n::Int, T_wall::Union{Real, AbstractVector{<:Real}, Function})
  # exposes: T_wall_out(t)[1:n]   (or named `T[1:n]` — planner picks)
  # equations:
  #   - Real    → T_wall_out[i] ~ T_wall                    for i in 1:n
  #   - Vector  → T_wall_out[i] ~ T_wall[i]                 for i in 1:n   (length-n required)
  #   - Function→ T_wall_out[i] ~ callable(t)               via MTK callable parameter pattern
  #               (or per-cell `callable(t, i)` if the function takes an index)

  HeatFluxSource(; name, n::Int, q::Union{Real, AbstractVector{<:Real}, Function})
  # exposes: q_out(t)[1:n]
  # equations: same shape as WallTemperature — Real broadcast / Vector indexed /
  #            Function via callable parameter
  ```
  Both components are exported from `STREAM.jl`. Both are pure "value source" subsystems — no ports, no Flow vars, just a vector of variables that other systems can bind to. Mirrors `ConstantTemperature` (which exists in `misc.jl`, exposes `T` for FlowPort use) but for the channel-level external-input vars.

- **D-05: Either-or usage pattern — both styles work natively.** Once D-01..D-04 are in place, both binding styles work without over-determination because there is no port-side `Q_flow` equation to conflict with:
  ```julia
  # Style 1 — direct binding eqns at compose time (Python args.funcs feel):
  connections = [
      ...,
      [ch.T_wall_left[i] ~ 350.0 for i in 1:n]...,
  ]

  # Style 2 — value-source component:
  @named wt = WallTemperature(; n=n, T_wall=350.0)
  connections = [
      ...,
      [ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]...,
  ]
  # (Same shape — the source component just produces the values; binding stays equation-style.)
  ```
  Style 1 is the args.funcs idiom. Style 2 is GUI-friendly (boxes-and-wires). Same underlying mechanism.

- **D-06: `HeatFluxPort` retired.** Delete the `@connector function HeatFluxPort(...)` block from `src/connectors.jl`. Drop `HeatFluxPort` from the `export` line in `src/STREAM.jl`. Delete HeatFluxPort-specific tests + `_StubFluxDriver` from `test/test_connectors.jl`. Mirrors the Phase 54 `WallPort` retirement. End-of-v1.1 connector roster: `FlowPort` (mass + momentum + stream T) and `ThermalPort` (CAC ↔ HD across-T + Flow-Q_flow). REQUIREMENTS.md `CONN-02` must be retroactively annotated as superseded by Phase 55 D-06 (mirror of the Phase 54 walk-back of CONN-01).

- **D-07: `ChannelAndContacts` unchanged.** CAC keeps the `ThermalPort` arrays (`thermal_left[1:n]`, `thermal_right[1:n]`) because it wires to `HeatDiffusion`, which uses Flow-based ports for heat balance. CAC's existing constructor, `h_tc[i]` correlation equation, optional `scb_correction`, and all observables stay exactly as Phase 54 shipped them (`src/components/channels.jl:533-717`).

### Composition helpers (TEST-03)

- **D-08: Likely zero changes to `src/composition/helpers.jl`.** The four composition helpers (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`) and the QoL helpers (`port`, `check_gravity_mismatch`, `connect_temperature_feedback`, `_infer_n`) all target CAC ↔ HD connections via `ThermalPort`. Since CAC keeps `ThermalPort` arrays unchanged, none of the helpers need updating for the new Channel / CHF design. **Verification step (mandatory):** run the composition tests under the new design — if any test fails because a helper was implicitly relying on the old Channel having a `thermal` port, fix it; otherwise sign off as no-change. `_infer_n` counts subsystems named `thermal_left*` on its first arg — works on CAC (still has them), would fail on the new Channel/CHF (don't have them). Since helpers only ever take CAC as the first arg, this should be fine — but planner verifies.

### Builders (TEST-02)

- **D-09: Three simple-loop builders kept separately.** `build_loop`, `build_loop_vertical`, `build_loop_transient` stay as three separate builders (concept-progression: simplest closed loop → adds gravity → adds time-varying input). Don't collapse to a single parameterized builder; the demo lineage is the value here. All three migrate to the new Channel API.

- **D-10: Simple-loop builders use direct binding eqns (Style 1 from D-05).** No driver components inside the builders. The builder's `T_wall=...` kwarg flows directly into per-cell binding equations:
  ```julia
  function build_loop(; n=10, T_wall=373.15, h_wall=5000.0, ...)
      @named ch = Channel(; n=n, geometry=..., h_left=h_wall)
      connections = [
          ...,
          [ch.T_wall_left[i] ~ T_wall for i in 1:n]...,
      ]
      ...
  end
  ```
  `h_wall` becomes a new builder kwarg (defaults to a sensible value, e.g., 5000.0 W/m²K — planner picks a sound default). For `build_loop_transient`, `T_wall_fn::Function` continues to work — the builder evaluates `T_wall_fn(t)` inside the binding equation OR uses the MTK callable-parameter pattern (planner picks).

- **D-11: `build_loop_lof_bypass` redesign — spike-driven, not pre-decided.** Plan a short spike step BEFORE the LOF builder rewrite locks. Spike A: heated leg = `ChannelAndContacts` (correlation-driven internal htc handles regime switching natively) + `WallTemperature` driver pinning `T_wall` per cell — no HeatDiffusion plate. Spike B: heated leg = `ChannelAndContacts` + `HeatDiffusion` plate via `one_sided_connection` (most physically faithful, real fuel-plate transient). Acceptance criteria for the spike: (i) compiles + solves a brief transient; (ii) reproduces the v1.0 LOF NC-reversal qualitative behavior (mdot crosses zero, NC equilibrium reached); (iii) total runtime is reasonable (< 60s per scenario for the integration-test version). Whichever satisfies all three with less complexity wins. If both work, prefer Spike A (simpler topology, less to debug). The `ret` Channel return-leg also migrates to the new Channel API regardless of which spike wins.

- **D-12: `build_loop_pk` — CAC API unchanged, verify only.** PK builder uses CAC + HeatDiffusion via `symmetric_plate` and `connect_temperature_feedback`. None of those touch Channel/CHF. Should "just work" but planner runs a verification step (compile + solve a brief transient + check that the steady-state IC still matches Phase 49 expectations) early in execution to catch any latent breakage.

- **D-13: `build_cube` unchanged.** Pure hydraulic network of Resistors + Pump. No Channel involvement. Listed for completeness — no action needed.

### Examples (TEST-02 carry-forward)

- **D-14: `examples/simple_loop.jl`** — thin wrapper over `build_loop`. Update kwarg list to match the new builder signature (`h_wall` added). One-line touch-up.

- **D-15: `examples/lof_transient.jl` (1008 lines)** — has an inline reference loop at lines 88-103 using `ChannelHeatFlux(T_wall=, ...)` (old API). Migrate the inline reference loop and the call to `build_loop_lof_bypass` to whatever the LOF builder uses post-spike (D-11). Update IC dict and observable accessors accordingly. Otherwise the transient + plotting code is unchanged.

- **D-16: `examples/mtr_assembly.jl`** — pure CAC + HeatDiffusion via `plate()`. No Channel / CHF use. Likely zero changes; planner verifies.

### Test suite reorganization (TEST-01, TEST-05)

The test suite is reorganized to mirror Python STREAM's test layout, which the user identified as the canonical reference. Python STREAM's organizational rules (extracted by reading every `test_*.py` file under `~/projects/STREAM/tests/`):

> - **One file per individual component** under `test_calculations/` — each tests that component's `calculate()` in isolation (instantiation, mass vector, isolated physics, hypothesis-based property tests). Subclasses live in the same file as their parent (e.g., `ChannelAndContacts` lives in `test_channel.py`). Shared underlying core helpers are tested in the same file as the variants that share them (e.g., `coolant_first_order_upwind_dTdt` is tested inside `test_channel.py`).
> - **Stand-alone correlation / threshold math** in `test_libraries/` — pure-function tests, no system involved.
> - **Composition** in `test_composition/` — graph construction, MTR helpers, state manipulation, parameterized constructors. May solve for *composition correctness* (e.g., `symmetric_plate_steady_state` runs a solver to check the assembly produces a meaningful state) but not long-running physics validation.
> - **One big integration file** at `test_general/test_integrations.py` (973 lines, 20+ tests) — *all* multi-component system-level tests live together: pump+resistor analytic, channel + PK, Kirchhoff with decaying pump, **LOF transients**, **PK + thermal feedback**, flow reversal, coastdowns, etc. **LOF and PK + feedback are NOT separate files** in Python STREAM — they're sections of the integration file.
> - **Framework / infrastructure** in `test_general/` — Aggregator, Calculation, dataframes, solvers wrapping, utilities. Not physics.
> - **External-reference validation** is its own file (Julia STREAM uses `test_validation.jl` for Python parity, Phase 56's deliverable).

Final Julia layout (14 files, down from the current 20):

```
test/
  runtests.jl                             # orchestrator

  # Per-component unit tests (Python test_calculations/ pattern)
  test_geometry.jl                        # PipeGeometry — UNCHANGED
  test_pump.jl                            # Pump — UNCHANGED
  test_resistors.jl                       # Friction, Gravity, Resistor — UNCHANGED
  test_misc.jl                            # Inertia, HeatExchanger, ConstantTemperature — UNCHANGED
                                          # (also gains tests for new WallTemperature /
                                          #  HeatFluxSource components if planner places them
                                          #  here; otherwise see D-21)
  test_heat_diffusion.jl                  # HeatDiffusion — UNCHANGED
  test_flapper.jl                         # Flapper — UNCHANGED
  test_channels.jl   REWRITE              # Channel/CHF/CAC variants under new design.
                                          # Absorbs test_channel_core.jl (_channel_core
                                          # enthalpy-form physics — the shared core lives
                                          # with the variants that share it, mirroring
                                          # Python's coolant_first_order_upwind_dTdt
                                          # test placement). Absorbs test_sign_safety.jl
                                          # (flow-reversal sign tests for all three variants).
  test_connectors.jl REWRITE              # FlowPort + ThermalPort unit tests.
                                          # HeatFluxPort tests + _StubFluxDriver removed.
  test_point_kinetics.jl  TRIM            # Component unit tests only:
                                          # PK-01..03, RC-01, TF-01..05, SCRAM-01.
                                          # Full-loop integration (LOOP-01..04, TF-06,
                                          # TF-07) moves to test_integration.jl.

  # Library tests (Python test_libraries/ pattern)
  test_fluids.jl                          # rho/cp/mu/k/sat — UNCHANGED
  test_correlations.jl                    # HTC + friction correlation functions — UNCHANGED
  test_thresholds.jl  RENAMED             # CHF/OFI/OSV/ONB/twall + ChannelState wrappers.
                                          # Was test_analysis.jl — renamed to match
                                          # Python's test_thresholds.py.

  # Composition (Python test_composition/ pattern)
  test_composition.jl REWRITE             # symmetric_plate, plate, one_sided_connection,
                                          # compose_systems, port helper, check_gravity_mismatch,
                                          # connect_temperature_feedback. HEAVY CAC↔HD
                                          # compose-correctness coverage (multiple topologies
                                          # / dimensions / wiring). Mostly no-solve;
                                          # solve-to-verify-composition-state allowed but
                                          # no long transients or physics-vs-analytic.

  # Integration (Python test_general/test_integrations.py pattern — ONE big file)
  test_integration.jl   NEW               # All system-level multi-component tests that
                                          # build, solve, validate against analytic/expected.
                                          # Absorbs:
                                          #   - test_examples.jl (SYS-01, SYS-02 — build_loop /
                                          #     build_cube smokes)
                                          #   - test_solvers.jl (SOLV-01, SOLV-02)
                                          #   - test_loss_of_flow.jl (LOF-01..03, VAL-01..02)
                                          #   - test_subcooled_boiling.jl (SCB + ISCB)
                                          #   - PK loop integration: LOOP-01..04, TF-06, TF-07
                                          #     (relocated from test_point_kinetics.jl)

  # External-reference validation (no Python equivalent — Phase 56)
  test_validation.jl                      # UNTOUCHED here.

DELETED:
  test_channel.jl              → subsumed by test_channels.jl
  test_examples.jl             → into test_integration.jl
  test_solvers.jl              → into test_integration.jl
  test_loss_of_flow.jl         → into test_integration.jl
  test_subcooled_boiling.jl    → into test_integration.jl
  test_channel_core.jl         → into test_channels.jl
  test_sign_safety.jl          → into test_channels.jl
RENAMED:
  test_analysis.jl             → test_thresholds.jl
```

- **D-17: `test_channels.jl` rewrite (TEST-01).** Built fresh under the new architecture — not a port of the old `test_channel.jl`. Sections:
  - **Construction & shape:** all three variants instantiate, `mtkcompile` cleanly in isolation (with `fully_determined=false`), correct equation count, correct subsystem layout (Channel/CHF have `T_wall_*` / `q_*` external-input variables but NO per-cell port subsystems; CAC keeps `thermal_left*` / `thermal_right*` ThermalPort subsystems).
  - **Adiabatic-by-default behavior:** `Channel` with `h_left=h_right=0.0` (default) and unbound `T_wall_*`: solves on a closed `Pump → bc → Channel → Pump` loop, `T_out ≈ T_inlet` (no heating). `ChannelHeatFlux` with unbound `q_*`: same property.
  - **Heated behavior — Style 1 (binding eqns):** `Channel` with `h_left=5000.0`, per-cell `[ch.T_wall_left[i] ~ T_wall]` binding eqns, right side unbound + `h_right=0.0` (asymmetric heating): `T_out > T_inlet`, `q_wall_left[i]` finite and signed correctly, `q_wall_right[i] ≈ 0`. CHF with binding `[chf.q_left[i] ~ q_value]`: `q_wall_left[i] ≈ q_value × heated_parts[1] × dz` to rtol 1e-6.
  - **Heated behavior — Style 2 (component sources):** Same as above but using `WallTemperature(; n, T_wall=value)` / `HeatFluxSource(; n, q=value)` and binding `[ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]`. Asserts equivalence to Style 1.
  - **`h_left` value-shape coverage:** `h_left::Real` (broadcast to all cells), `h_left::Vector` (per-cell axial profile), `h_left::Function` (time-varying via callable parameter). Same matrix for `T_wall_left` (Real / Vector / Function via the `WallTemperature` source).
  - **CAC correlation-driven htc:** instantiate with `htc_correlation=dittus_boelter`, exercise on a `Pump → bc → CAC → Pump` loop with a tiny `WallTemperature` source pinning `T_wall` (equivalent to the old `T_wall = const` test); h_tc[i] is correlation-driven internally; energy balance closes.
  - **CAC SCB correction:** `scb_correction` argument exercises the SCB branch (one sub-ONB case where SCB is bypassed, one super-ONB case where it kicks in). Mostly migrated from existing `test_subcooled_boiling.jl`'s ISCB-* tests if those test the CAC-only scope (otherwise they go to test_integration.jl — planner judges).
  - **Flow reversal sign safety (absorbs `test_sign_safety.jl`):** all three variants with reversed flow (`mdot < 0`), assert mirror behavior — temperature profile flips, `q_wall` signs invert correctly, no NaNs / no DomainErrors.
  - **`_channel_core` enthalpy-form physics (absorbs `test_channel_core.jl`):** the existing G1-G4 stage-tests (Stage-1 baseline, Stage-2 Python `pair_mean_1d` parity, single-cell forward/reverse mirror absolute-equality, multi-cell mirror, branch-coverage matrix). These directly exercise `_channel_core` via Channel/CHF/CAC instantiations — the shared core IS tested with the variants that share it (Python pattern).
  - **CAC ↔ CHF cross-variant equivalence:** the old THERM-03 spirit — give CAC and CHF the same effective wall heat input, compare resulting `T_out` / `mdot` within 0.1%. Restated under the new API: CAC with `htc_correlation` + WallTemperature(T_wall) vs CHF with HeatFluxSource(q_value) where `q_value = htc_value × (T_wall − T_inlet)`. Smoke-level, not a Python-parity check.

- **D-18: `test_composition.jl` rewrite (TEST-03).** Built fresh, focused on CAC↔HD compose-correctness across topologies. Sections:
  - **`port` helper:** indexed port access on uncompiled CAC.
  - **`check_gravity_mismatch`:** existing G_M tests carry forward (these don't touch Channel architecture).
  - **`_infer_n` correctness:** counts `thermal_left*` subsystems on CAC; should still work since CAC kept its ThermalPort arrays.
  - **`symmetric_plate(cac, fuel)` compose-correctness:** assembly compiles cleanly across multiple `(n, nz, nx)` dimensions; equation count + subsystem topology is correct; no ExtraEquations / ExtraVariables warnings.
  - **`plate(ch_left, ch_right, fuel)` compose-correctness:** dual-CAC + HD plate composes; both faces wired correctly.
  - **`one_sided_connection(channel, fuel; side=:left|:right)` compose-correctness:** single-CAC + HD plate with one side wired, other side adiabatic; both side variants exercised.
  - **`compose_systems` cross-plate wiring:** stitch two `symmetric_plate` assemblies via hydraulic-series connect equations; system composes cleanly.
  - **Multi-plate / multi-dimension matrix:** representative shapes (n=4 / nz=4, n=10 / nz=10, asymmetric `nx=1` and `nx=3`) — all compile + `mtkcompile` cleanly.
  - **Solve-to-verify-composition (lightweight):** for each topology, run a single brief `solve_steady` (no transient) to verify the composition produces a *meaningful* steady state — not a physics-vs-analytic check (that's `test_integration.jl`'s job). Mirrors Python's `symmetric_plate_steady_state` test pattern in `test_subsystems.py`.
  - **`connect_temperature_feedback` equation generation:** TF-04 equation-counting tests (1D channel binds n eqns; 2D HeatDiffusion binds nz×nx eqns row-major; multiple components sum). These are PK-related but compose-correctness, not solving — keep here, not in test_integration.jl.

- **D-19: `test_integration.jl` is the single big file (TEST-02 + TEST-05 carry-forward).** Built fresh, organized by physics regime as labeled sections. Strict scope: every test here builds a multi-component system, solves it (steady or transient), and validates output against an analytic / expected behavior. Sections:
  - **§Builders smokes:** `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_lof_bypass`, `build_loop_pk` each compile + solve briefly and produce sane output. Migrated from `test_examples.jl`.
  - **§Solvers wrappers:** `solve_steady` / `solve_transient` correctness on a representative loop (SOLV-01, SOLV-02). Migrated from `test_solvers.jl`.
  - **§Loss-of-flow transient:** LOF-01..03 (bypass topology compiles + SS IC physical, Flapper fires at threshold, channel flow reverses across zero) and VAL-01..02 (energy balance, NC equilibrium mdot within 30% of analytical buoyancy). Migrated from `test_loss_of_flow.jl`. Heated-leg topology adapts to whichever LOF variant wins the D-11 spike.
  - **§Subcooled-boiling integration (ISCB):** ISCB-01..02 — full-loop CAC + SCB transient and equilibrium checks. Migrated from `test_subcooled_boiling.jl`. (The pure-correlation SCB-01..04 stays in `test_thresholds.jl` since they're stand-alone math.)
  - **§Point-kinetics + thermal-feedback loops:** LOOP-01..04 (build_loop_pk compiles, quiescent stability, step reactivity with feedback, SCRAM termination) and TF-06 (reactivity observable in solved system) and TF-07 (strong negative feedback bounds power). Relocated from `test_point_kinetics.jl`.
  - **§COMPAT:** the existing `Pkg.test()` wiring smoke (currently in `test_examples.jl`'s last testset).

- **D-20: `test_thresholds.jl`** is a pure rename of `test_analysis.jl`. No content change. Justified because the file holds threshold-correlation tests + thin analysis-API wrappers — closer to Python's `test_libraries/test_thresholds.py` than to Python's `test_analysis/`. The Julia `test_analysis.jl` name was a misnomer; rename for clarity.

- **D-21: `WallTemperature` / `HeatFluxSource` test placement.** Source-component unit tests (instantiation, equation count, equation shape per Real/Vector/Function input) live in `test_misc.jl` alongside the existing `ConstantTemperature` tests — same family of value-source components. (Optionally a new `test_sources.jl` file if `test_misc.jl` grows too crowded; planner picks based on file size.)

- **D-22: TEST-05 close gate.** `bin/jl test/runtests.jl` (or `julia --project=. test/runtests.jl` cold) returns no NEW failures vs the v1.0 baseline. Pre-existing flakies (VAL-01 Fourier, NET-03 Cube flow KINSOL convergence) remain tolerated. ROADMAP success criterion 4 wording ("no new errors versus the v1.0 baseline") governs — *not* "zero failures absolute."

### File structure & doc maintenance

- **D-23: New file `src/components/sources.jl`.** Holds `WallTemperature` and `HeatFluxSource`. Included from `src/STREAM.jl` after `components/misc.jl` (which has `ConstantTemperature` — same family) and before `components/channels.jl` (which doesn't depend on these but should follow the same components-first-then-channels ordering for predictability).

- **D-24: `CLAUDE.md` File Structure Standard updates.** Update the `src/components/` tree comment to add `sources.jl  # WallTemperature, HeatFluxSource (value-source subsystems for channel external inputs)`. Update the test layout section if present (currently lists individual test files — refresh to match the 14-file post-Phase-55 reality).

- **D-25: `.planning/REQUIREMENTS.md` retrospective annotations** (committed alongside CONTEXT.md / DISCUSSION-LOG.md, mirroring Phase 54 D-17/D-18):
  - `CONN-02` (HeatFluxPort) — append "Superseded by Phase 55 D-06: HeatFluxPort retired in favor of channel-level external-input variables `q_left`/`q_right` on ChannelHeatFlux. See `feedback_channel_hd_connection_rule.md` and `55-CONTEXT.md` for rationale."
  - `TEST-01` — refine wording to reflect the consolidation: "test_channels.jl rewritten under the new design (variants + _channel_core + sign-safety merged in); old test_channel.jl deleted."

- **D-26: `.planning/ROADMAP.md` Phase 55 success-criterion updates** (committed in the same commit as D-25):
  - Criterion 1 — confirm helpers compile and MTR assemblies solve, but note that **zero changes to `composition/helpers.jl`** is an acceptable outcome (CAC keeps ThermalPort, helpers don't depend on Channel/CHF).
  - Criterion 2 — same six builders, but `build_loop_lof_bypass` is gated by the D-11 spike outcome.
  - Criterion 3 — supersede "test/test_channel.jl rewritten" with "test_channels.jl rewritten under new design + test layout consolidated per Python STREAM rules; old test_channel.jl deleted."
  - Criterion 4 — restate the close-gate rule as "no NEW failures vs v1.0 baseline" explicitly (avoiding a future re-litigation).

### Claude's Discretion

- **Plan / wave decomposition.** The planner picks the wave structure (e.g., (a) variant rewrite + sources.jl + connectors.jl HeatFluxPort retirement; (b) test_channels.jl rewrite + test_connectors.jl trim; (c) helpers verify + test_composition.jl rewrite; (d) builders rewrite + LOF spike; (e) test_integration.jl consolidation; (f) doc fixes + close gate). Atomicity: each wave commits independently; the test suite need not be green at every commit boundary, but each wave's deliverable must be self-consistent.
- **Naming of value-source-component output variables.** D-04 sketches `T_wall_out[1:n]` / `q_out[1:n]` but the planner can pick `T[1:n]` / `q[1:n]` (matching `ConstantTemperature.T`) for consistency. Either is fine; pick once and document.
- **Default value of `h_wall` in builders.** Phase 54 smoke used `5000.0` W/m²K. Planner picks a sensible default for `build_loop` / `build_loop_vertical` / `build_loop_transient` that makes the existing `T_wall=373.15` / `T_inlet=313.15` defaults produce a meaningful T_out rise. 5000.0 is a reasonable starting point.
- **`build_loop_transient` time-varying T_wall mechanism.** Two valid options: (a) bind `[ch.T_wall_left[i] ~ T_wall_fn(t)]` directly (plain Julia closure called inside the equation — works because MTK traces the closure); (b) the v0.9 callable-parameter pattern (`@parameters (T_wall_callable::FType)(..)`). Planner picks based on what the existing test_solvers SOLV-02 callers expect; both are correct.
- **Whether to keep `ConstantTemperature` separately or fold its semantics into `WallTemperature`.** They're related but distinct: `ConstantTemperature` is a FlowPort-side fluid-temperature pin (used as the inlet of a flow, expects `port_in.T` / `port_out.T`); `WallTemperature` is a non-port value source for wall-T external inputs. They have different shapes (FlowPort has a scalar T plus mdot stream var; WallTemperature has a vector of plain variables). Keep them separate; document the distinction.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase scope and requirements
- `.planning/ROADMAP.md` §"Phase 55: Composition Helpers, Examples & Test Suite" — phase goal, dependencies, four success criteria. **Note:** the criteria need updating per D-26 to reflect the architectural redesign (criteria 1-4 carry forward but criterion 3 is rewritten and criterion 4's "no new failures vs baseline" framing is made explicit).
- `.planning/REQUIREMENTS.md` §"Tests, Examples, Composition" — TEST-01 (rewritten per D-25), TEST-02, TEST-03, TEST-05. **Note:** CONN-02 in §Connectors is annotated as superseded by Phase 55 D-06 in this commit (mirror of the Phase 54 walk-back of CONN-01).
- `.planning/PROJECT.md` §"Current Milestone: v1.1 Final Channel-Family Redesign" — milestone goal, "never need touching again" mandate.
- `.planning/STATE.md` §"Key Decisions (carry-forward)" — v1.1 phasing rationale, connector-pattern history (now further updated by Phase 55).

### Prior phase decisions to honor
- `.planning/phases/52-channel-connectors/52-CONTEXT.md` — original connector contract. **Most superseded:** D-02 (WallPort) was retired in Phase 54; D-03 (HeatFluxPort) is retired in Phase 55. Only D-04 (ThermalPort retained for CAC, kept its `T` across + `Q_flow` Flow shape) survives unchanged.
- `.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md` — `_channel_core` API D-01..D-14, especially D-02 (`q_left_expr` / `q_right_expr` are length-n `Vector{Num}` inputs the variant builds) and D-10 (variant declares all `@variables`, `_channel_core` consumes by reference). Phase 55 D-02 / D-03 specify the per-variant q-expression construction under the new external-input-var design — feeds into core unchanged.
- `.planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md` — D-01 (WallPort retirement), D-02..D-04 (Channel kwargs + driver pattern), D-06 (CHF minimal signature), D-07 (CHF q-expression), D-08..D-09 (CAC unchanged). **Phase 55 supersedes:** D-04 (Channel emits `port.Q_flow ~ q_expr`) — the channel-side Q_flow eqn is removed because there's no port. D-07 (CHF emits `port.Q_flow ~ q_expr`) — same. D-13..D-16 (smoke-test driver-component pattern) — superseded by direct binding eqns and value-source components in Phase 55.
- `.planning/phases/54-variant-rewrites-file-consolidation/54-VERIFICATION.md` — Phase 54 deviations (especially Deviation 1: binding-eq idiom over-determined because of port Q_flow eqn — this is the empirical justification for the Phase 55 redesign).

### Architectural rules (MANDATORY)
- `/home/itay/.claude/projects/-home-itay-projects-Julia-STREAM/memory/feedback_channel_hd_connection_rule.md` — **HeatDiffusion connects ONLY to ChannelAndContacts**. Channel and ChannelHeatFlux NEVER wire to HeatDiffusion. Phase 55 D-01 / D-03 lean on this rule to justify dropping the per-cell ports — Channel/CHF never needed Flow-based ports because they never connect to HD.
- `/home/itay/.claude/projects/-home-itay-projects-Julia-STREAM/memory/feedback_keyword_only_rule.md` — keyword-only kwargs are the default; positional only when multiple dispatch on type matters. None of the Phase 55 signatures use multiple dispatch — keyword-only stays correct.

### Existing code (read before extending)
- `src/components/channels.jl` — Phase 54's deliverable (717 lines). `_channel_core` at line 84, `Channel` at line 219, `ChannelHeatFlux` at line 396, `ChannelAndContacts` at line 533. Phase 55 modifies `Channel` (lines 219-359 — drop port arrays, add T_wall_left/right external-input variables, drop port-Q_flow eqn) and `ChannelHeatFlux` (lines 396-487 — drop port arrays, add q_left/right external-input variables, drop port-Q_flow eqn). `ChannelAndContacts` (lines 533-717) and `_channel_core` (line 84+) are UNCHANGED.
- `src/connectors.jl` — `FlowPort` (kept), `ThermalPort` (kept, used by CAC + HD), `HeatFluxPort` (DELETED in Phase 55).
- `src/STREAM.jl` — drop `HeatFluxPort` from the `export FlowPort, ThermalPort, HeatFluxPort` line. Add `include("components/sources.jl")` line, ordered after `components/misc.jl` (which has `ConstantTemperature`) and before `components/channels.jl`. Add `WallTemperature, HeatFluxSource` to exports.
- `src/components/misc.jl` — existing `ConstantTemperature` is the closest analog for the new `WallTemperature` / `HeatFluxSource` (value-source subsystem pattern). Read before authoring `sources.jl`.
- `src/components/heat_diffusion.jl` — exposes `ThermalPort` arrays for CAC wiring. UNCHANGED in Phase 55. Read-only reference for composition helpers.
- `src/composition/helpers.jl` — `symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`, `port`, `check_gravity_mismatch`, `connect_temperature_feedback`, `_infer_n`. UNCHANGED in Phase 55 (D-08), pending verification step.
- `src/examples.jl` — six builders. `build_loop` (lines 48-79), `build_loop_vertical` (lines 124-169), `build_loop_transient` (lines 194-241), `build_cube` (lines 278-339, no Channel — unchanged), `build_loop_lof_bypass` (lines 378-448, redesign per D-11 spike), `build_loop_pk` (lines 496-617, CAC API unchanged — verify only).
- `src/fluids.jl` — `cp_water`, `rho_water`, `mu_water`, `k_water` `@register_symbolic` functions. UNCHANGED.
- `src/physical_models/htc/correlations.jl`, `src/physical_models/friction/correlations.jl` — UNCHANGED.

### Test references
- `test/test_channels.jl` (Phase 54's smokes — 269 lines, 31 tests passing) — wholesale REWRITTEN under D-17. The Phase 54 file-local `_WallTempDriver` / `_FluxDriver` stubs are obsoleted by D-04's first-class `WallTemperature` / `HeatFluxSource` components.
- `test/test_channel.jl` (legacy — 958 lines, 33 testsets, all stale under new API) — DELETED. Content triaged into `test_channels.jl` (variant unit tests) and `test_integration.jl` (system-level tests like GRAV-01..02 vertical-loop solves) where any of it survives the rewrite.
- `test/test_channel_core.jl` (604 lines) — DELETED, content absorbed into `test_channels.jl` per D-17 (shared-core tests live with the variants that share them, mirroring Python's `coolant_first_order_upwind_dTdt` placement in `test_channel.py`).
- `test/test_sign_safety.jl` (173 lines) — DELETED, content absorbed into `test_channels.jl` flow-reversal section per D-17.
- `test/test_examples.jl`, `test/test_solvers.jl`, `test/test_loss_of_flow.jl`, `test/test_subcooled_boiling.jl` — DELETED, content absorbed into `test_integration.jl` per D-19.
- `test/test_analysis.jl` — RENAMED to `test_thresholds.jl` per D-20 (no content change).
- `test/test_point_kinetics.jl` — TRIMMED per D-19. Component unit tests (PK-01..03, RC-01, TF-01..05, SCRAM-01) stay; full-loop integration tests (LOOP-01..04, TF-06, TF-07) move to `test_integration.jl`.
- `test/test_composition.jl` — REWRITE per D-18. Existing 354 lines (Phase 15 helpers tests + scattered CAC↔HD probes) are largely re-derived under the new structure.
- `test/test_connectors.jl` — REWRITE per D-06. HeatFluxPort tests + `_StubFluxDriver` removed; FlowPort + ThermalPort tests retained.
- `test/test_validation.jl` — UNTOUCHED (Phase 56's deliverable).
- `test/runtests.jl` — orchestrator. Update `include` lines to match the new file inventory (delete the absorbed files' includes, add `test_integration.jl`).

### Examples
- `examples/simple_loop.jl` (106 lines) — D-14 minor kwarg update.
- `examples/lof_transient.jl` (1008 lines) — D-15 rework of inline reference loop (lines 88-103) + IC dict + observable accessors per LOF spike outcome.
- `examples/mtr_assembly.jl` (175 lines) — D-16 likely zero changes (pure CAC + HD via `plate()`).

### Python STREAM reference (test layout source-of-truth)
- `~/projects/STREAM/tests/test_calculations/test_channel.py` — pattern: one file per component-class; ChannelAndContacts subclass tested in same file as Channel; underlying core helper `coolant_first_order_upwind_dTdt` tested in same file. Rule extracted: shared core tested with the variants that share it.
- `~/projects/STREAM/tests/test_calculations/test_heat.py`, `test_flapper.py`, `test_kirchhoff.py`, `test_point_kinetics.py`, `test_serializability.py` — one file per component, isolated calculate() tests.
- `~/projects/STREAM/tests/test_libraries/test_htc.py`, `test_pressure_drop.py`, `test_thresholds.py`, `test_decay_heat.py` — pure-function correlation tests, no system involved. Pattern source for the Julia `test_correlations.jl` / `test_thresholds.jl` / `test_fluids.jl` library tests.
- `~/projects/STREAM/tests/test_composition/test_subsystems.py`, `test_constructors.py`, `test_cycle.py`, `test_gravity_checker.py`, `test_maximal_coupling.py`, `test_mtr_geometry.py`, `test_partial_states.py` — composition tests. May solve for compose-correctness (e.g., `symmetric_plate_steady_state` runs a solver) but no long-running physics validation. Pattern source for the Julia `test_composition.jl` rewrite.
- `~/projects/STREAM/tests/test_general/test_integrations.py` (973 lines, 20+ tests) — **THE big integration file**. Contains: pump+resistor analytic, channel point-kinetics, Kirchhoff with decaying pump (flow reversal), Tin jumps at flow reversal, **inertia with friction in PCS coastdown** (LOF), **inertia with flapper in PCS coastdown** (LOF), **inertia with transistor in PCS coastdown** (LOF), pump coastdown + channel reversal, T-feedback (Tfuel + Tcool), kirchhoff_significance variants. **Crucial rule: LOF and PK + thermal feedback are NOT separate files in Python STREAM — they're sections of this one big integration file.** Pattern source for the Julia `test_integration.jl`.
- `~/projects/STREAM/tests/test_general/test_aggregator.py`, `test_calculation.py`, `test_dataframes.py`, `test_solvers.py`, `test_utilities.py` — framework / infrastructure tests. Julia STREAM has no direct equivalent (we use MTK directly so the framework is MTK's responsibility); SOLV-01/02 are integration tests of STREAM's solve_steady/solve_transient wrappers, not framework unit tests, hence relocate to `test_integration.jl`.
- `~/projects/STREAM/tests/test_calculations/conftest.py` (small file with `are_close`, `pos_medium_floats`) and `test_composition/conftest.py` (`MTR_fuel_and_channel`) — fixtures. Julia equivalent uses module-local helpers; planner decides per-file.

### Python STREAM reference (Channel API design intent)
- `~/projects/STREAM/stream/calculations/channel.py` lines 224-238 — `Channel.calculate(*, T_left=None, T_right=None, h_left=0.0, h_right=0.0, Tin, mdot, ...)`. The defaults `T_left=None`, `T_right=None`, `h_left=0.0`, `h_right=0.0` map onto Julia D-01..D-04: `T_wall_left` / `T_wall_right` are external-input variables (the `=None` Python sentinel maps to MTK "free unknown unless bound"); `h_left` / `h_right` are kwargs (Python defaults `0.0` → Julia kwarg defaults `0.0`).
- `~/projects/STREAM/stream/calculations/channel.py` line 384 — `class ChannelHeatFlux(Channel)` accepts `q_left`, `q_right` per cell. Julia equivalent: `q_left[1:n]`, `q_right[1:n]` external-input variables under D-03.
- `~/projects/STREAM/stream/aggregator.py` `Aggregator.from_decoupled(funcs={...})` — Python args.funcs idiom. Julia equivalent under D-05: direct binding eqns at compose time (`[ch.T_wall_left[i] ~ value for i in 1:n]...`).

### Existing memory references
- `feedback_channel_hd_connection_rule.md` — HeatDiffusion ↔ CAC architectural rule.
- `feedback_keyword_only_rule.md` — kwarg conventions.
- `feedback_ascii_variable_names.md` — no Unicode in variable names (T_wall, q_left, h_wall — all ASCII).
- `feedback_power_shape_trust_caller.md` — don't validate caller-supplied data; trust the inputs (applies to `T_wall::Vector` length checks — error early but don't re-validate per call).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_channel_core` (`src/components/channels.jl:84+`)** — Phase 53's shared core. UNCHANGED in Phase 55. All three variants continue to feed `q_left_expr` / `q_right_expr` into core; the only difference is how the variants build those expressions (now using channel-level `T_wall_left[i]` / `q_left[i]` external-input variables instead of `thermal_left[i].T` / `thermal_left[i].q_flux` port-side variables).
- **CAC's existing h_tc[i] equation block (`src/components/channels.jl:564-628`)** — UNCHANGED. Single-phase and SCB-corrected branches stay as Phase 54 shipped them.
- **`ConstantTemperature` (`src/components/misc.jl`)** — closest analog for `WallTemperature` / `HeatFluxSource` (D-04). Read before authoring `sources.jl` to match the existing component-style: `@named` keyword-only, `@variables` for outputs, `@parameters` for the value, simple equation block. Difference: `ConstantTemperature` is FlowPort-side (scalar T tied into a stream port); `WallTemperature` is portless (vector of plain output variables).
- **MTK callable-parameter pattern (v0.9 PointKinetics, retained in Phase 54 D-03)** — `FType=typeof(fn)` captured at construction, `@parameters (fn::FType)(..)` variadic. Reused for time-varying `h_left` / `h_right` in `Channel`, time-varying `T_wall` in `WallTemperature`, time-varying `q` in `HeatFluxSource`. Same mechanism, three new uses in Phase 55.
- **`port(sys, face, i)` helper (`src/composition/helpers.jl:28`)** — used by composition helpers and by CAC ↔ HD `connect()` calls. UNCHANGED. Note: this only ever takes CAC or HD as the first arg; never Channel/CHF (which no longer have indexed thermal port arrays under D-01 / D-03).
- **Phase 54 file-local `_WallTempDriver` / `_FluxDriver` (`test/test_channels.jl:36-48`)** — superseded. The first-class `WallTemperature` / `HeatFluxSource` components in `src/components/sources.jl` (D-04) replace them. Phase 54's stubs are deleted as part of the `test_channels.jl` rewrite.

### Established Patterns
- **Variant declares all `@variables`, `_channel_core` consumes by reference** (Phase 53 D-10) — UNCHANGED. Phase 55 variants additionally declare `T_wall_left[1:n]` / `T_wall_right[1:n]` (Channel) or `q_left[1:n]` / `q_right[1:n]` (CHF) as external-input variables (no equation, no default — user supplies value via binding eqn or component source).
- **`ifelse(port_in.mdot ≥ 0, T_up_fwd, T_up_rev)` for flow reversal** (inside `_channel_core`) — UNCHANGED.
- **`instream(port_in.T)` / `instream(port_out.T)` for boundary face values** (inside `_channel_core`) — UNCHANGED.
- **External-input variable pattern** (NEW for Phase 55, but mirrors how Python STREAM treats args.funcs entries): declare `@variables T_wall_left(t)[1:n]` on the variant System without an equation; the user is responsible for closing the system either via direct binding eqns or by wiring a value-source component. MTK auto-promotes unequated `@variables` to free unknowns; with default `h_left=0.0` they fall out of the energy balance and adiabatic-by-default holds without user intervention.
- **Direct binding eqn idiom** (NEW for Phase 55, but used elsewhere in `src/examples.jl`): `[ch.T_wall_left[i] ~ value for i in 1:n]...` inside the `connections` Vector{Equation}. Already proven idiom for `pump.port_in.P ~ 1.0e5` and old-style `ch.thermal.T ~ T_wall`. Now works for the variant's external-input variables without over-determination.

### Integration Points
- **`src/components/sources.jl` (NEW)** — receives `WallTemperature` and `HeatFluxSource` per D-04. Includes from `src/STREAM.jl` ordered between `misc.jl` and `channels.jl`.
- **`src/components/channels.jl`** — Channel (lines 219-359) and ChannelHeatFlux (lines 396-487) are MODIFIED per D-01..D-03 (drop ports, add external-input vars, drop port-Q_flow eqn). CAC (lines 533-717) and `_channel_core` (line 84+) are UNCHANGED.
- **`src/connectors.jl`** — `HeatFluxPort` `@connector function` block DELETED per D-06.
- **`src/STREAM.jl`** — `export FlowPort, ThermalPort, HeatFluxPort` becomes `export FlowPort, ThermalPort`; `WallTemperature, HeatFluxSource` added to exports; `include("components/sources.jl")` line added.
- **`src/composition/helpers.jl`** — UNCHANGED (D-08).
- **`src/examples.jl`** — `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_loop_lof_bypass`, `build_loop_pk` modified per D-09..D-12 + D-15. `build_cube` UNCHANGED.
- **`examples/*.jl`** — `simple_loop.jl` (D-14) and `lof_transient.jl` (D-15) modified; `mtr_assembly.jl` (D-16) likely unchanged.
- **`test/test_*.jl`** — full reorganization per D-17..D-21. See file inventory in §"Test suite reorganization".
- **`test/runtests.jl`** — `include` lines updated to match the new test-file inventory.
- **`CLAUDE.md`** File Structure Standard updated per D-24 (new `sources.jl` listed; test-tree refresh if section exists).
- **`.planning/REQUIREMENTS.md`** — CONN-02 superseded annotation + TEST-01 wording refresh per D-25.
- **`.planning/ROADMAP.md`** — Phase 55 success criteria updates per D-26.

</code_context>

<specifics>
## Specific Ideas

- **User's foundational frame (this discuss):** "The main driver of what STREAM is and what people will use STREAM for revolves around the CAC and HeatDiffusion connection. ... Whenever we want to prove physics or prove that something is comparable to something in other code — we should strive for the CAC-HeatDiffusion connection in various compositions." Channel and CHF are simplified-model fixtures and concept demos; CAC + HD is the centerpiece. This is the lens for the test rewrite — heavy CAC↔HD coverage, with Channel/CHF tests scoped to API-shape and adiabatic-by-default smokes.

- **User's args.funcs intent (this discuss):** "If users still just want to add their own equation where it just says channel.T_wall_left ~ my_T_wall_left it works no problem. ... If they just want to add an equation that sets a variable to a scalar/vector/function it should be fine." Direct binding equations on a channel-level external-input variable must work natively, without driver components or workarounds. D-01 (drop ports) is what makes this possible — without the port-side `Q_flow ~ q_expr` eqn, the dangling Flow rule can't conflict with a user-supplied binding on `T_wall_left`. The driver-component pattern (D-04) is *also* available, primarily for GUI / boxes-and-wires use cases.

- **User's "rewrite, not port" frame (this discuss):** "This is a rewrite. This is the time to break what was written before if it's for our benefit. We don't need to make minimal edits. What was before was wrong. The channels were written incorrectly." This is the license for D-01 / D-03 (architectural rebuild of Channel and CHF, retiring per-cell ports that Phase 54 just shipped) and for D-17 (test_channels.jl built fresh, not a port of test_channel.jl).

- **User's "make it make sense" frame on test layout (this discuss):** "Make it make sense and no random files or random tests. Test stuff to the core and put it in a file system that makes sense." Plus the explicit ask to research Python STREAM's test layout. The 14-file Julia layout (D-17..D-22) was derived by reading every `~/projects/STREAM/tests/**/*.py` file and extracting the rules: one-file-per-component, libraries-for-pure-functions, composition-for-wiring, ONE-big-integration-file, validation-separate.

- **LOF physics ground truth (D-11 acceptance):** the v1.0 LOF transient produces (i) exponential mdot decay after pump trip, (ii) Flapper firing at ~20-30s (mdot crosses threshold), (iii) flow reversal and NC establishment by ~100-150s, (iv) NC equilibrium by ~270s with `ch.mdot < 0` and `|mdot_nc| << mdot_ss`. The Phase 55 spike must reproduce these qualitative milestones to count as a successful redesign. Quantitative parity is Phase 56's job (TEST-04).

- **Connector-retirement narrative (post-Phase-55):** v1.1 became "the milestone where we figured out which connectors actually earn their keep." Phase 52 added `WallPort` + `HeatFluxPort` as new connector types; Phase 54 retired `WallPort` (2-across-1-flow shape couldn't auto-zero on dangling ports under any MTK mechanism — verified by `/tmp/spike_input_true.jl`); Phase 55 retires `HeatFluxPort` (no consumer left after Channel/CHF drop their per-cell ports). End state: `FlowPort` for hydraulic, `ThermalPort` for CAC↔HD heat balance — two connector types, both proven. Worth capturing in `STATE.md` Key Decisions after milestone close.

</specifics>

<deferred>
## Deferred Ideas

- **`ConstantTemperature` / `WallTemperature` / `HeatFluxSource` rationalization** — three "value source" components with overlapping semantics (ConstantTemperature is FlowPort-side scalar T; WallTemperature is portless vector of T; HeatFluxSource is portless vector of q). Could potentially unify under a more general "ValueSource" abstraction or document the distinctions clearly. Out of v1.1 scope — keep them separate, document the distinction in docstrings, defer rationalization to a future GUI / API-cleanup phase.

- **`Channel` / `ChannelHeatFlux` "extra inputs" beyond T_wall and q** — the Python `args.funcs` mechanism takes ANY missing variable, not just T_wall / q. Examples: pressure forcing on `port_in.P`, mdot forcing on `port_in.mdot`, time-varying inlet T via `Tin`. Julia equivalent already works via existing binding-eqn idiom (`pump.port_in.P ~ 1e5` style). No phase action needed; the new external-input-var mechanism for `T_wall_left` / `q_left` is consistent with how the rest of the API already handles forcing.

- **MTK-upstream issue for the unconnected-input auto-anchor gap** — Phase 54 deferred this; Phase 55 makes it less necessary for Channel/CHF (the redesign sidesteps the gap by removing the ports), but the issue still exists for any future 2-across-1-flow connector. Out of v1.1 scope. Reference spike: `/tmp/spike_input_true.jl`.

- **GUI component-registry sync for the new `WallTemperature` / `HeatFluxSource`** — REQUIREMENTS.md Out-of-Scope table calls out "GUI component-registry sync" as deferred to a later GUI milestone. No Phase 55 action.

- **Python STREAM cross-validation under the new architecture (TEST-04, Phase 56)** — milestone gate. Phase 56 will verify steady-state parity to ≤1% rtol and transient parity to existing tolerances. Phase 55's local "no new failures" gate (D-22) is necessary but not sufficient.

- **STATE.md Key Decisions update** — Phase 55 produces material new decisions (HeatFluxPort retirement, Channel/CHF ports dropped, value-source-component pattern, test layout consolidated on Python STREAM rules, connector-retirement narrative). After Phase 55 close, STATE.md "Key Decisions (carry-forward)" section should append the v1.1 Phase 55 entries. Not part of Phase 55 plans; happens via `/gsd:execute-phase` finalization or `/gsd:extract-learnings`.

- **CONN-02 + TEST-01 doc fixes** — committed alongside `55-CONTEXT.md` / `55-DISCUSSION-LOG.md` per D-25 (mirrors Phase 54's pattern). Not deferred — they happen at this discuss phase's commit time.

- **Unification of `simple_loop.jl` + `mtr_assembly.jl` + `lof_transient.jl` example structure** — three examples with three different boilerplate styles. Could be standardized post-v1.1. No Phase 55 action.

</deferred>

---

*Phase: 55-Composition Helpers, Examples & Test Suite*
*Context gathered: 2026-05-07*

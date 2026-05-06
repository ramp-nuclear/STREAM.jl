# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

---

## Milestone: v0.1 — MVP

**Shipped:** 2026-03-13
**Phases:** 5 | **Plans:** 12

### What Was Built
- Julia package STREAM.jl with MTK v11 + DiffEq v7 + Sundials v5 compatibility
- Light water fluid properties registered as MTK symbolic functions (Simantov correlations for ρ, cp, μ, k)
- FlowPort and ThermalPort acausal connectors with correct across/through semantics
- Channel component: n-cell 1D FVM with Dittus-Boelter HTC and Darcy-Weisbach dP
- Pump, Friction, Gravity components (Pump and Gravity wired in loop; Friction absorbed into Channel)
- Steady-state and transient solvers with clean user API (build_loop, solve_steady, solve_transient)
- Python STREAM cross-validation: T_out=327.79 K, ṁ=0.609 kg/s — both within 1%
- 54-test suite covering all 15 requirements (FOUND, CONN, COMP, SYS, SOLV, VAL)
- Tech debt cleanup: BUG-01 (H_grav), BUG-02 (stale docstring), stale TDD files removed
- Nyquist compliance records for all three core phases

### What Worked
- Wave-based parallel execution let Phase 2 (4 plans) run efficiently — Wave 0 stubs enabled parallel Wave 1 components
- GSD workflow forced atomic commits per task, making git history readable and traceable
- Python STREAM reference generator (generate_reference.py) baked hardcoded values into tests — removes live Python dependency from CI
- MTK's acausal connect() fully replaced the Python Aggregator pattern with zero explicit variable routing
- @register_symbolic for fluid properties was the right call — zero injection complexity, ForwardDiff-compatible

### What Was Inefficient
- Phase 4 (tech debt cleanup) should have been caught earlier; BUG-01 and BUG-02 were obvious during Phase 2/3 planning
- Friction ended up orphaned in the loop (absorbed into Channel) but remained an exported component — creates a confusing API that needs v0.2 attention
- The milestone audit (v0.1-MILESTONE-AUDIT.md) was run after all phases were complete rather than interleaved with development; earlier auditing would have caught BUG-01 during Phase 2
- VAL-01/02/03 missing from SUMMARY.md frontmatter was a minor doc debt that had to be fixed in Phase 4

### Patterns Established
- Wave 0 stub plan (test scaffold + stubs) enables parallel Wave 1 execution — repeat this for any phase with independent parallel components
- Python reference values baked into test constants (not computed at test time) — use for any cross-language validation
- Nyquist compliance via VALIDATION.md at phase completion — run /gsd:validate-phase immediately after each phase, not as a separate phase
- MTK parameter naming: use same name for kwarg and MTK parameter (e.g., `H` in Gravity) to avoid the BUG-01 class of silent mismatch

### Key Lessons
1. **Run audit-milestone after each phase cluster, not after all phases are done** — BUG-01 sat undetected through all of Phase 3 testing
2. **Friction-inside-Channel was expedient but wrong for the public API** — exported components should be wired into the loop or clearly marked as standalone utilities
3. **`@register_symbolic` functions need to be defined before registration** — this bit us early; the fix is simple but the error message is not obvious
4. **MTK v11 `@connector function` pattern (not DSL block syntax)** — this was a breaking change from tutorials; document immediately when hitting it
5. **Validate-phase should be a step in each phase's success criteria**, not a separate bookkeeping phase at the end of the milestone

### Cost Observations
- Model mix: ~100% sonnet (all agents configured to sonnet profile)
- Sessions: ~1 (single intensive session 2026-03-12/13)
- Notable: 75 commits in ~2 days from a standing start; executor agents with fresh 200k context per plan worked well at this scale

---

## Milestone: v0.2 — Component & Network Expansion

**Shipped:** 2026-03-13
**Phases:** 4 (6-9) | **Plans:** 7

### What Was Built
- `build_loop_vertical`: vertical closed loop with Channel(g_acc) + Gravity(H) reversed-port wiring; hydrostatic cancellation test within 1%
- `Resistor` component: linear hydraulic resistor (dP = R·ṁ) as building block for networks
- `build_cube`: 12-Resistor cube network via MTK variadic connect(), KINSOL solve, 5/6·R analytical match
- `Inertia` ODE component: L/A·D(ṁ) pressure drop; RL-decay transient match to 2.6×10⁻⁶ rtol
- `HeatExchanger` public component: `_make_temp_bc` promoted to public API, all build_loop variants updated
- `ChannelAndContacts` + `ChannelHeatFlux`: per-cell ThermalPort array via `_channel_base_eqs` shared helper; v0.3 interface ready

### What Worked
- TDD Red/Green approach continued to work cleanly — stubs + failing assertions gave clear targets
- `_channel_base_eqs` shared-helper extraction emerged organically from the implementation; the shared-equations pattern should be the default for component variants
- MTK variadic connect() proved sufficient for Kirchhoff junctions at cube scale (8 nodes, three 3-way + two 4-way junctions) — the "no Junction component" decision from v0.1 planning held up
- All 4 phases executed in a single day (~7 hours total) — the v0.1 velocity transferred intact

### What Was Inefficient
- Gravity wiring ambiguity in the plan ("let MTK sort out signs") led to a Port-connection-direction bug in Phase 6 — the convention needed to be nailed down in the plan, not discovered at runtime
- The `t_inlet` parameter in `_channel_base_eqs` is dead (both callers compute their own `T_inlet`) — a small code review gap that will need cleanup in v0.3
- THERM-03 was validated via `ChannelHeatFlux` proxy rather than direct `ChannelAndContacts` pin — algebraically correct but leaves a gap; add direct test in v0.3
- ODEProblem construction for pure pressure circuits (Inertia + Resistor loop) required two non-obvious flags (`fully_determined=false`, `check_length=false`) — the plan predicted one but not both

### Patterns Established
- **Reversed-port wiring for descending components**: For any component where `inlet.P > outlet.P` (high-pressure entry), connect the physically-bottom-end to inlet regardless of flow direction
- **Multi-branch junction**: `connect(a, b, c, ...)` generates Kirchhoff automatically; always add a pressure anchor (`pump.inlet.P ~ 1.0e5`) to fix absolute pressure level
- **Shared equation helper pattern**: Extract `_foo_base_eqs(eqs, ...; kwargs)` that mutates `eqs` in-place before variant-specific coupling loop
- **ODE component with auto-promoted state**: Use `vars = []` and let MTK promote the `Dt(inlet.mdot)` variable; don't declare an explicit `mdot(t)` state

### Key Lessons
1. **Pin port wiring conventions explicitly in the plan** — "MTK will figure it out" is never safe for port direction; write out which end connects where
2. **Pressure anchor is a mandatory fixture for multi-branch networks** — add it to every build_cube/build_network helper, not as an afterthought
3. **Document dead parameters at creation time** — the `t_inlet` parameter in `_channel_base_eqs` was dead from day one; a one-line comment at creation would have avoided the audit note
4. **Test both proxy and direct** — when THERM-03 was validated via proxy (algebraically equivalent), a follow-up direct test should have been written immediately

### Cost Observations
- Model mix: ~100% sonnet
- Sessions: ~1 (single intensive session 2026-03-13)
- Notable: 4 phases in 7 hours, 32 new tests — velocity roughly matched v0.1 per-plan pace (~5-10 min/plan vs 13 min/plan baseline)

---

## Milestone: v0.3 — HeatDiffusion

**Shipped:** 2026-03-14
**Phases:** 4 (10-12.1) | **Plans:** 8

### What Was Built
- ChannelAndContacts rewritten with dual `thermal_left[1:n]` / `thermal_right[1:n]` ThermalPort arrays; two-sided energy balance; adiabatic default verified by CHAN-03 test
- v0.2 tech debt fully cleared: `_channel_base_eqs` t_inlet removed, THERM-03 direct assertion, DEBT-03 doc fix
- `HeatDiffusion` component: 2D FD solid plate with `T(t)[1:nz, 1:nx]` MTK ODE state, `_diffusion_eqs` helper, power_shape + power source, dual ThermalPort arrays; 7-testset unit suite (HDIFF-01..05)
- MTR fuel assembly integration tests: VAL-01 (symmetric), VAL-02 (asymmetric), VAL-03 (one-sided); all against Python STREAM reference
- `PipeGeometry` struct with `circular(; D, ...)` and `rectangular(; y, ...)` constructors; Channel/ChannelHeatFlux/ChannelAndContacts refactored to accept it
- Quantitative VAL-01/02/03 assertions at ≤1% rtol against hardcoded Python STREAM rectangular MTR reference constants

### What Worked
- Phase 12.1 insertion as a decimal phase was seamless — the geometry error was caught before archival and fixed without disrupting the broader plan structure
- Hardcoding Python STREAM reference constants into Julia tests (rather than computing at test time) worked perfectly: stable, fast, zero Python dependency at CI time
- KINSOL (KINSOL nonlinear solver) handled the coupled HeatDiffusion + ChannelAndContacts DAE without special tuning
- MTK acausal semantics gave adiabatic defaults for free — HDIFF-05 / CHAN-03 required no explicit `Q_flow = 0` equations, just leaving a port unconnected

### What Was Inefficient
- Phase 12 produced physics-based (qualitative) VAL assertions first, then Phase 12.1 replaced them with quantitative 1% assertions — if PipeGeometry had been planned from the start, quantitative assertions would have been in Phase 12 directly
- The 4.46× geometry error (circular `π·Dh/2` vs rectangular `2·y`) was not caught during planning — it only surfaced when comparing Julia vs Python reference values; a geometry cross-check step in Phase 12 planning would have avoided the inserted phase
- VAL-02/03 Python reference script had convergence issues (NonUniqueCalculationNameError, initial guess) that required mid-plan fixes

### Patterns Established
- **Decimal phase for post-validation corrections**: When a geometry or physics error is found after the main validation phase, insert a decimal phase (12.1) to fix and re-validate — don't amend the completed phase plan
- **PipeGeometry encapsulation**: All pipe geometry (L, Dh, A, heated_parts) belongs in a single struct; callers specify geometry explicitly rather than having it hardcoded in component constructors
- **Rectangular heated perimeter = 2·y, not π·Dh/2**: MTR flat-plate geometry uses plate width as heated perimeter; document the distinction in any plan involving rectangular channels
- **KINSOL initial guess sensitivity**: For coupled solid+fluid systems, using a physics-informed initial guess (e.g., T_plate_avg from energy balance) avoids convergence failures in asymmetric cases

### Key Lessons
1. **Cross-check geometry against Python STREAM before writing integration tests** — a five-minute dimensional check (circular vs rectangular perimeter) would have avoided an entire inserted phase
2. **Plan quantitative validation targets from the start** — if the milestone goal says "within 1%", the plan should specify the geometry and reference constants up front, not discover them mid-phase
3. **Decimal phase insertion works well for post-discovery corrections** — Phase 12.1 completed cleanly; the pattern is reusable for any mid-stream physics or API correction
4. **MTK adiabatic default (unconnected port = Q_flow 0) must be tested explicitly** — it's not obvious from the framework docs; CHAN-03 and HDIFF-05 make it a regression target

### Cost Observations
- Model mix: ~100% sonnet (balanced profile throughout)
- Sessions: ~2 (Phase 10 on 2026-03-13, Phases 11-12.1 on 2026-03-14)
- Notable: Phase 12.1 (geometry fix + quantitative assertions) added ~1 hour but prevented shipping a 4.46× physics error in the milestone

---

## Milestone: v0.4 — Composability & Physics

**Shipped:** 2026-03-16
**Phases:** 4 (13-16) | **Plans:** 7

### What Was Built
- PipeGeometry redesigned with 6 fields and `wet_perimeter`; Dh = 4A/wet_perimeter; MTR hydraulic diameter corrected from 10 mm → 2.5 mm; all ~20 call sites migrated to `PipeGeometry_rectangular` / `PipeGeometry_circular` factory functions
- Pump dual-mode dispatch: `Pump(mdot0=...)` for fixed-flow, `Pump(dP_pump=...)` for fixed-pressure; PHY-05 loop integration test
- Six pluggable correlation functions in `src/correlations.jl`: `constant_Nusselt`, `dittus_boelter`, `laminar_friction`, `blasius_friction`, `rectangular_laminar_correction` (KAERI K_R), `regime_dependent` with ifelse() Re-switching
- ChannelAndContacts refactored to accept `htc_correlation` and `friction_correlation` closure kwargs; default unchanged
- 10 MTK `@observed` variables in ChannelAndContacts: Re, Nu, velocity, Pe, h_tc_left/right, T_wall_left/right, q_wall_left/right
- `src/helpers.jl` with `port()`, `check_gravity_mismatch()`, `symmetric_plate()`, `plate()`, `one_sided_connection()`, `compose_systems()`
- Three quantitative VAL assertions: Fourier series transient (VAL-01, 4 checkpoints ≤1%), two-plate one-channel topology energy balance (VAL-02), T_max adiabatic formula (VAL-03, ≤1%)

### What Worked
- PipeGeometry factory functions (no sentinel-kwargs constructor) made the call sites cleaner than the old API
- Correlation functions as plain Julia closures — no `@register_symbolic` needed; MTK traces arithmetic symbolically; clean API, no framework plumbing
- `@observed` for Re/Nu/v/Pe worked cleanly: solver unknown vector shrinks, diagnostics still accessible via `sol[sys.ch.Re, :]`
- Composition helpers infer `n` from CAC's uncompiled thermal_left subsystem count — callers don't need to pass `n` explicitly; ergonomic and safe
- `regime_dependent` `ifelse()` pattern reused from flow-reversal smoothing — smooth switching, no solver discontinuity
- VAL-03 using analytical energy balance instead of Python STREAM reference was the right call — caught a Python bug and produced a more rigorous assertion

### What Was Inefficient
- VAL-02/03 use raw `getproperty` wiring because the topology (2 plates → 1 channel; plate.thermal_left ↔ cac.thermal_left) is incompatible with `one_sided_connection` — the helpers were verified independently but couldn't be used in validation tests; a future helper covering these topologies would close this gap
- The `build_initializeprob=false` requirement for coupled HeatDiffusion+CAC was discovered during execution rather than anticipated in the plan; it should be a first-class planning note for any HeatDiffusion integration test
- PHY-05 channel thermal port pinning (`ch5.thermal.T ~ 350.0`) was unexpected — a planning note about unconnected ThermalPort unknowns would have prevented the mid-task discovery

### Patterns Established
- **Correlation closures**: All HTC and friction correlations are plain Julia functions returning `(Re, Pr, geom) -> value`; no MTK registration needed; pass as kwargs to channel components
- **`@observed` for diagnostics**: Variables that feed equations (h_tc) stay as unknowns; variables that are derived outputs (Re, Nu) go to `@observed`; h_tc equation is inlined to avoid MTK observed-chain resolution issues
- **Composition helpers infer n**: Any helper that wraps ChannelAndContacts should use `_infer_n(cac)` rather than require an explicit `n` argument
- **No backward-compat shims**: When redesigning constructors, delete the old one; MethodError is the correct migration signal

### Key Lessons
1. **Plan call-site migration alongside struct redesign** — PipeGeometry_rectangular was planned, but the ~20 call sites in `src/solvers.jl` were missed in the initial plan migration map; the executor caught it, but the plan should have listed migration sites explicitly
2. **VAL tests for coupled systems need `build_initializeprob=false`** — add this to the standard HeatDiffusion+CAC test template; it should never be discovered at execution time
3. **Unconnected ThermalPort creates an extra unknown** — always pin any unconnected `thermal` port in test loops; add to test fixture checklist
4. **Use analytical references when Python has known bugs** — VAL-03 demonstrates that deriving the assertion from first principles is both more rigorous and more portable than copying Python output

### Cost Observations
- Model mix: ~100% sonnet (balanced profile throughout)
- Sessions: ~3 (Phase 13-14 on 2026-03-14, Phase 15 on 2026-03-15, Phase 16 + audit/tech debt on 2026-03-15/16)
- Notable: Tech debt resolution from milestone audit (commit 5c4f9ad) added one focused session; 5 of 6 audit items resolved same-day, 1 accepted as architectural

---

## Milestone: v0.5 — Code Quality

**Shipped:** 2026-03-16
**Phases:** 3 (17-19) | **Plans:** 6

### What Was Built
- Source reorganized into canonical layout: `geometry.jl`, `src/components/` (6 files), `src/physical_models/correlations.jl`, `src/composition/helpers.jl`, `src/examples.jl` — CLAUDE.md contract fully on disk
- Monolithic `test/runtests.jl` exploded into 13 self-contained `test_*.jl` files; each imports its own deps and runs independently
- `solve_transient` converted to keyword-only; project-wide keyword-only API convention now 100% complete
- Structured Julia docstrings on all 28 exported names (`# Arguments`, `# Ports`, `# Returns`) — full REPL `?help` coverage
- CLAUDE.md rewritten with **Why:** rationale after every rule + 5-pattern MTK Patterns section
- `Project.toml` bumped to `0.5.0`

### What Worked
- Pure code quality milestone with no feature creep made execution fast and focused — all 6 plans completed in 1 day
- Retroactive Nyquist audits (18, 19) caught missing SUMMARY frontmatter tracking quickly without blocking development
- The `tech_debt` audit status (not `gaps_found`) allowed milestone completion with known minor doc gaps documented — right call
- Phase 17 → 18 → 19 dependency chain was perfectly linear; no parallelization needed or beneficial

### What Was Inefficient
- The SUMMARY.md frontmatter for 18-01 and 18-02 was incomplete at phase completion — tracking IDs were not in the required fields; caught by retroactive Nyquist audit rather than live
- FlowPort and ThermalPort docstrings were explicitly out of scope for DOC-01..04 but not called out during phase planning; created an audit gap (29 exported names documented, 2 skipped)
- Milestones.md accomplishments field was blank from CLI (no `one_liner` fields in SUMMARY.md frontmatter) — required manual update

### Patterns Established
- Pure refactor milestones benefit from a strict "no new features" guard in the audit — audit status `tech_debt` (not `gaps_found`) is the right outcome for pure quality milestones
- SUMMARY.md frontmatter `one_liner` field is required for CLI milestone archival to work — enforce this in phase wrap-up checklist
- Retroactive Nyquist audits are fast and low-cost; running them after every phase catches tracking gaps before they accumulate

### Key Lessons
- Code quality milestones ship faster than feature milestones — 3 phases, 6 plans, 1 day is achievable when scope is clear and there are no blocked dependencies
- "Why:" rationale in CLAUDE.md prevents future contributors (and AI agents) from accidentally reverting intentional design decisions
- Test files that mirror source files one-to-one make test location predictable — worth the upfront reorganization cost

### Cost Observations
- Model mix: ~100% sonnet (balanced profile)
- Sessions: 1 day (all 3 phases executed 2026-03-16)
- Notable: Fastest milestone to date; pure reorganization + documentation with zero new DAE equations

---

## Milestone: v0.6 — Flow Reversal Systems

**Shipped:** 2026-03-27
**Phases:** 8 (20-26 incl. 24.1) | **Plans:** 14

### What Was Built
- Sign-safe channel energy loops: ifelse() upwinding selects upstream temperature by mdot sign; abs(mdot) in Re; inlet.T ~ T[1] stream equation corrected in all three channel variants
- `beta_water(T)` thermal expansion coefficient (@register_symbolic), `Gr`/`Ra` dimensionless utilities, 4-arg HTC interface `(Re, Pr, T_bulk, T_wall)` extended to all correlations and channel call sites
- `elenbaas_nusselt(Ra, b, L)` Elenbaas 1942 natural convection correlation + `elenbaas_htc(; b, L, Dh, g)` pluggable factory; validated against Python STREAM MTR reference
- Three-method Pump dispatch: `Pump(dP_pump::Real)`, `Pump(mdot0::Real)`, `Pump(dP_pump::Any)` for callable; `solve_transient` redesigned to positional API `(ssys, op, t; ...)`
- `Flapper` check-valve: Hermite cubic C1 ramp, MTK SymbolicContinuousCallback latch (T_open=1e30 sentinel, affect_neg fires on downward ref_mdot crossing), wired via plain algebraic equation
- 4-node bypass LOF topology (`build_loop_lof_bypass`): real junctions, parallel heated channel / Flapper shortcut paths, standalone Inertia, gravity signs per branch
- `regime_dependent` extended with NC detection: `ifelse(Gr/Re² > 1, htc_natural(...), htc_forced)` — MTK-compatible; `Gr_over_Re2[i]` observable added
- LOF transient validated: energy balance 0.09% rtol, NC established, dT matches Elenbaas within 0.3% (ratio 0.997)
- 6 public signatures migrated from keyword-only to positional + multiple dispatch; CLAUDE.md two-tier convention rule codified

### What Worked
- `Flapper` sentinel pattern (T_open=1e30) is robust — avoids domain errors from Inf arithmetic; generalizable to any "unlatched" state machine in MTK
- Series-loop → bypass topology replacement was the right call; the physical reasoning (real junctions, parallel paths) made the NC result significantly more meaningful
- NC detection via `ifelse(Gr/Re² > 1)` is a direct match to Python STREAM convention and needed no convergence tuning
- Phase 26 (NC cleanup) added Elenbaas temperature-rise validation retroactively to an already-passing test — fast and additive, no rework

### What Was Inefficient
- Series-loop LOF topology was built in Phase 24, found insufficient, and replaced by Phase 24.1 — the physical bypass requirement should have been identified during planning
- Channel momentum inertia `(L/A)*Dt(inlet.mdot)` was added in Phase 24.1-01 and reverted in Phase 24.1-02 after discovering it breaks parallel topologies — cost one plan of rework
- Phase 22 VALIDATION.md left as Nyquist non-compliant (tech debt in audit) — should have been closed at phase completion

### Patterns Established
- **Bypass topology is the correct LOF model**: any loss-of-flow scenario needs parallel flow paths; a series loop can't capture the physics of Flapper opening a bypass route
- **Callable MTK parameters**: `@parameters (fn::FType)(..)` is the idiomatic pattern for time-varying inputs; `@register_symbolic` is for pure functions, not closures
- **Sentinel value for event latch**: T_open=1e30 > any physical time; arithmetic with sentinel is safe; direct Inf initialization is not safe in MTK parameter arithmetic
- **Positional + dispatch when types differ**: `Pump(dP::Real)` vs `Pump(dP::Any)` — argument type encodes behavior; this is the correct Julia idiom; keyword-only only when distinguishing named concepts of same type

### Key Lessons
1. **Topology planning matters most**: the two physical planning mistakes (series LOF, channel inertia) cost 1.5 plans; next time, sketch the graph with node/edge count before committing to topology
2. **VALIDATION.md must close at phase completion**, not retroactively — tech debt items in the audit show where this wasn't done
3. **NC regime detection is a switchover, not a blend** — `ifelse(Gr/Re² > 1)` is a hard switch; blending is future work; get the switch right first, then worry about transition smoothness

### Cost Observations
- Model mix: ~100% sonnet (balanced profile)
- Sessions: ~10 days (2026-03-17 → 2026-03-27), with gaps between phases
- Notable: Largest milestone to date by phase count (8); most complex MTK patterns (continuous events, callable parameters, parallel topology)

---

## Milestone: v0.7 — Safety Physics & Pressure Field

**Shipped:** 2026-04-01
**Phases:** 7 (27, 27.1, 28, 29, 30, 31, 32) | **Plans:** 13

### What Was Built
- Per-cell pressure field (dp[i], P[i]) in all three channel variants; sat_temperature @register_symbolic; T_sat[i]/T_ONB[i] observables (PRES-01..04)
- Distributed momentum ODE (L/A)*Dt(mdot) in Channel, ChannelAndContacts, ChannelHeatFlux with P[i] inertia correction; 8 transient PRES-05..12 tests passing
- Subcooled boiling suite: McAdams_SCB_heat_flux, Bergles_Rohsenow_SCB_heat_flux, partial_SCB_correction, regime_dependent_q_scb factory; in-loop SCB correction for ChannelAndContacts
- Nuclear safety threshold analysis: 8 physics functions (T_ONB, OFI, OSV, CHF×3, twall_limit) + ChannelState struct + threshold_analysis dispatcher + chfr factory + 8 pre-built wrappers
- Complete HTC/friction library: Marco_Han_Nusselt, fully_developed_laminar_h_spl, developing_laminar_h_spl, maximal_htc, turbulent_friction (Colebrook-White), viscosity_correction; correlations.jl split into htc/ + friction/ subdirs
- Audit gap closure phases: 27-VERIFICATION.md retroactively written; _extract_channel_state ArgumentError guard; E2E solve→extract→analyze pipeline test; Phase 30 in-system smoke tests

### What Worked
- **Structured audit → gap-closure phases pattern**: running `/gsd:audit-milestone` before completion surfaced 3 real gaps; creating Phases 31+32 specifically to close them produced a cleaner milestone than ignoring the gaps
- **Retroactive VERIFICATION.md from VALIDATION.md**: Phase 27's documentation gap was a 15-minute task (Phase 31); the audit correctly identified it as documentation-only, not implementation
- **E2E test coverage as explicit phase goal**: Phase 32's goal was specifically an E2E test for the solve→extract→analyze pipeline — made the previously-untested bridge a first-class deliverable
- **ifelse() discipline**: consistently applying the ifelse() pattern for all piecewise functions in MTK closures (max(dT,0), _nusselt_coefficient_developing) prevented symbolic tracing errors

### What Was Inefficient
- **Audit ran after Phase 30 was done**: ideally audit runs at Phase 29 completion; discovered the Phase 30 in-system test gap post-hoc; required an extra gap-closure phase
- **VALIDATION.md nyquist_compliant: false** on 3 of 5 phases (27.1, 29, 30) — validation strategies weren't updated at phase completion; consistent pattern of tech debt appearing in audit
- **Phase 29 THRS-09 mock-only tests**: threshold_analysis E2E was never written during Phase 29 itself; the integration checker caught it only in the audit; should be part of the acceptance criteria at Phase 29 plan time

### Patterns Established
- **Audit-before-complete as standard workflow**: `/gsd:audit-milestone` before `/gsd:complete-milestone` is now validated as producing better milestone quality
- **Gap-closure phases (31, 32 pattern)**: small focused phases that address audit findings are more trackable than ad-hoc "fix during completion"
- **ArgumentError guard for component-specific helpers**: `_extract_channel_state` guard (`hasproperty(:T_wall_left)`) is the right pattern for functions with structural preconditions — fail fast with a clear message

### Key Lessons
1. **Write VALIDATION.md nyquist_compliant: true at plan completion, not retroactively** — 3/5 phases left this as false; it's a 5-minute update that prevents audit findings
2. **E2E tests should be in the plan's acceptance criteria**, not added as gap-closure — the THRS-09 E2E test was always needed; stating it as a requirement upfront avoids the audit round-trip
3. **Correlations used only in standalone tests will fail in MTK** — any new correlation factory should have a one-line compile test in the plan (the `ifelse()` discovery in Phase 32 was preventable)

### Cost Observations
- Model mix: ~100% sonnet (quality profile)
- Timeline: 5 days (2026-03-27 → 2026-04-01) across 7 phases
- Notable: First milestone to use explicit audit-before-complete pattern; 2 gap-closure phases added post-audit; VAL-PRES-01 is the only intentionally deferred requirement across all 7 milestones

---

## Milestone: v0.8 — STREAM Composer GUI

**Shipped:** 2026-04-04
**Phases:** 13 (33-44, incl. 35.1) | **Plans:** 32

### What Was Built
- Tauri 2 + React + ReactFlow desktop app with three-panel layout, Zustand store, Tailwind v4, shadcn design tokens, Vitest; JSON component registry for all 12 STREAM.jl components with TypeScript types
- Drag-drop canvas with FlowPort connection validation, undo/redo (10+ ops), pan/zoom/minimap, Hydraulic/Thermal toolbox categories
- Parameter editing sidebar: registry-driven form dispatching, PipeGeometry picker, Pump mode toggle, factory correlation pickers (regime_dependent, elenbaas_htc, maximal_htc) with nested sub-parameter fields
- Pure code generator: graph→valid STREAM.jl Julia with positional/keyword arg handling, factory recursion, default elision; live preview panel; Tauri file export
- Project persistence: save/load .streamgui JSON, unsaved-changes guard, WelcomeOverlay with recent files, Ctrl+S/O/N shortcuts, close guard; 7 real-runtime bug fixes including WSLg title workaround and kbLock mutex
- Topology validation: pure validateTopology (11 TDD tests), error rings on nodes, ValidationDialog, gated export/save
- Thermal composition: amber diamond ThermalPort handles, connection type enforcement, symmetric_plate/plate/one_sided_connection detection, compose_systems code-gen
- Layered canvas: Hydraulic/Thermal toggle with dimming, toolbox filtering, Tab cycling, StreamProject v2 schema
- Edge visual overhaul: arrowheads, parallel offset routing, FlowPort polarity colors, cursor fix, counter reconstruction fix
- UI polish: 12×12px ThermalPort handles, Info icon tooltips on all parameter fields, draggable bottom panel resize
- Light/dark/system theme: ThemeMenu gear icon, localStorage persistence, FOUC prevention, ReactFlow colorMode integration, One Dark Pro palette

### What Worked
- **`gsd:ui-phase` + `gsd:ui-review` gates per frontend phase**: design contracts caught visual issues before they were baked in; shadcn/ui prevented hand-rolled CSS anti-patterns; every frontend phase had a clear visual acceptance contract
- **Pure function extraction pattern**: generateCode(), validateTopology(), layer detection utilities, projectIO — all implemented as pure functions with comprehensive unit tests before UI wiring; made the UI code thin and the logic testable
- **Registry-as-truth principle**: the component metadata JSON was the single source of truth for the sidebar, toolbox, and code generator; adding a new component or parameter only required updating the registry, not the UI code
- **Decimal phase (35.1) for emergent scope**: correlation pickers emerged during Phase 35 discuss-phase; the 35.1 decimal insertion kept the numbering clean and the audit traceable
- **Real-runtime verification** (Phases 33-03, 34-03, etc.): human-verify plans exposed multiple integration bugs that unit tests missed (WSLg title workaround, kbLock mutex, React close-guard dialog)

### What Was Inefficient
- **Several SUMMARY.md files had broken one_liner fields**: "Outcome:", "One-liner:", "[Rule 3 - Blocking]" artifacts appeared in the MILESTONES.md auto-generated accomplishments list; required manual cleanup — one_liner field should be validated at plan completion
- **Phase 35 started before SCAF-02 (Windows installer) was resolved**: installer build requires Windows + Rust environment; was deferred without a clear plan for the constraint; still unresolved at v0.8 close
- **FileMenu Open Recent gap (PERS-04)**: WelcomeOverlay disappears once a node is on canvas, making recent projects unreachable from FileMenu; a known gap since Phase 37 that wasn't addressed before v0.8 close

### Patterns Established
- **UI-phase → code → UI-review per frontend phase**: this 3-step gate is now the standard for any frontend phase; it catches visual issues before they compound
- **Pure function TDD for UI logic**: all stateful UI behavior extracted to pure functions first (validateTopology, generateCode, layerDetection, projectIO) — this is the right default for any complex UI state
- **Tech debt YAML in audit frontmatter**: the `tech_debt:` section in v0.8-MILESTONE-AUDIT.md provided a structured record of known deferrals that fed directly into the completion notes

### Key Lessons
1. **Verify SUMMARY.md one_liner at plan completion** — broken one_liners propagate to MILESTONES.md; the field should contain a clean sentence, not a plan-checker report fragment
2. **Platform build constraints need a resolution plan, not just a deferral note** — SCAF-02 Windows installer has been deferred since Phase 33; by v0.9 GUI it should have a concrete resolution (CI job, cross-compile, or explicit out-of-scope)
3. **WelcomeOverlay-only recent files is a UX dead end** — PERS-04's Open Recent should be in both WelcomeOverlay and FileMenu; the current design only works if the user hasn't started work

### Cost Observations
- Model mix: ~100% sonnet (quality profile)
- Timeline: 3 days (2026-04-01 → 2026-04-04) across 13 phases, 32 plans
- Notable: First entirely TypeScript/React milestone in a Julia-centric project; first use of ui-phase design contracts; tech debt audit status (not gaps_found) allowed completion without gap-closure phases

---

## Milestone: v0.9 — Point Kinetics & Reactor Control

**Shipped:** 2026-04-10
**Phases:** 5 (45-49) | **Plans:** 8

### What Was Built
- `PointKinetics` MTK component: 7-ODE DAE (power P + 6 delayed-neutron precursor groups C_k), U-235 6-group constants, `mtkcompile` confirmed; `point_kinetics_steady_state(P0)` analytical IC helper
- `PointKinetics(rho_c_fn::Any; ...)` callable-mode constructor using MTK variadic callable parameter (`FType=typeof(fn)` + `@parameters (fn::FType)(..)`); additive rho composition `rho_val + rho_c_fn(t) - beta_sum`
- `ReactivityController{S,F}` mutable struct: `input_reactivity` callable, `state_machine`, `state`, `t_state`, `log`, `abort_states`; `worth`/`change_state` methods; `ctrl(t) = worth(ctrl, t)` callable dispatch
- Temperature feedback: `_flatten_weights` helper + callable constructor extension for Doppler/coolant α coefficients; `connect_temperature_feedback` composition helper with `scoped_comps` kwarg for symmetric_plate-wrapped regions; TF-07 multi-region validated
- Unified callback factory pattern: `SCRAMCondition`, `scram_callback(ssys, ctrl, condition)`, `flapper_callback(ssys, flapper)`; Flapper refactored to new API; existing LOF and flapper tests updated
- `build_loop_pk(ctrl; ...)` full-loop builder coupling PointKinetics to TH loop (pump, channel, HeatDiffusion, HeatExchanger); LOOP-01..04 integration tests (compilation, quiescent stability, power excursion, SCRAM); VAL-PK-01..03 quantitative validation vs Python STREAM (prompt-jump, beta-effective, reactivity insertion)

### What Worked
- **Callable MTK parameter pattern extended cleanly**: the `Pump(dP_pump::Any)` precedent from Phase 22 transferred directly to `PointKinetics(rho_c_fn::Any)`; no new patterns needed, just application
- **Additive rho composition (D-01)** made temperature feedback in Phase 47 a natural extension — `+ alpha*(T-T0)` terms required no ODE restructuring
- **connect_temperature_feedback as a pure composition helper** (returns `Vector{Equation}`) matched the `symmetric_plate` helper pattern exactly; the scoped_comps Dict kwarg solved the symbolic re-scoping problem cleanly
- **Prompt-jump physics investigation** (Phase 46-02) replaced a plan-specified sample time of 0.01s with the physically correct `t_step + Λ/δρ ≈ 0.027s`; the deviation was caught and fixed during execution rather than slipping into a wrong test
- **Phase 49 VAL-PK-01..03**: quantitative validation against Python STREAM confirmed the coupled PK+TH model is physically correct; the KINSOL NaN guard fix (guard `dT >= 0` in VAL-PK-02a/b) was a clean surgical fix

### What Was Inefficient
- **Phase 47 VERIFICATION.md was never created** — verification happened via UAT (47-UAT.md) but the standard VERIFICATION.md artifact was missing; noted as tech debt in audit; UAT-only verification is acceptable but non-standard
- **47-02-SUMMARY.md Self-Check falsely claimed scoped_comps kwarg was added to connect_temperature_feedback** — the actual fix was passing scoped refs as Dict keys; summary accuracy gap caught in milestone audit
- **Worktree merge commits required post-hoc squash before PR** — two `git merge` commits from worktree agents blocked GitHub FF merge; had to `git reset --soft main && git commit` + force-push after PR was already created; this should be caught pre-ship

### Patterns Established
- **Pre-ship merge-commit check**: always run `git log --merges main..HEAD` before `/gsd:ship`; if any exist, squash with `git reset --soft main && git commit` before pushing — the milestone is one logical unit, squashing is acceptable
- **Callable MTK parameter pattern**: `FType=typeof(fn)` captured at construction + `@parameters (fn::FType)(..)` variadic — generalizes to any Julia callable that needs to be embedded in an MTK symbolic equation
- **Prompt-jump test window**: sample `t_step + Λ/δρ` after reactivity step insertion; using a fixed 0.01s is wrong — the settling time scales with neutron generation time divided by reactivity insertion

### Key Lessons
1. **Check for merge commits before every `/gsd:ship`** — worktree agents produce merge commits silently; the pre-ship checklist must include `git log --merges main..HEAD` and squash if non-empty
2. **VERIFICATION.md is required, not optional** — UAT alone is not equivalent; the VERIFICATION.md status field drives `/gsd:ship` preflight; Phase 47's missing file created ambiguity at ship time
3. **MTK callable parameters are the right pattern for any "pluggable physics" scenario** — wherever Python STREAM uses a callable class/protocol, the Julia MTK equivalent is `@parameters (fn::FType)(..)` with FType captured at construction

### Cost Observations
- Model mix: ~100% sonnet (quality profile)
- Timeline: 6 days (2026-04-04 → 2026-04-10) across 5 phases, 8 plans
- Notable: First neutronics milestone; callable MTK parameter pattern reused from Phase 22 without modification; most complex composition helper (connect_temperature_feedback) required scoped_comps workaround for MTK symbolic re-scoping

---

## Milestone: v1.0 — Open-Source Release

**Shipped:** 2026-04-10
**Phases:** 2 (50-51) | **Plans:** 7

### What Was Built
- MIT license, Project.toml with fresh UUID, PackageCompiler moved to [extras] only (not a transitive runtime dep)
- GitHub Actions CI workflow: Julia stable + ubuntu-latest; RobustMultiNewton for NET-03; NoInit removed from VAL-01 ODE for reliable Fourier convergence at t=0.5·tau
- Two example scripts: `examples/simple_loop.jl` (hello-world forced convection loop with plots) and `examples/mtr_assembly.jl` (MTR plate-fuel two-channel thermal assembly)
- README.md: physics-first lead paragraph, component catalog table, install + usage examples, sysimage performance section
- `test/Project.toml`: enables `julia --project=. test/runtests.jl` direct invocation without Pkg.test()
- MTR assembly power equation fix: HeatDiffusion `power` is MTK `@variables` unknown (not a parameter); `rods.hd.power ~ POWER` governing equation required
- `build_sysimage.sh`: mtkcompile warmup baked into precompile, 6 GB RAM pre-flight gate, dynamic heap-size-hint (75% free RAM), time_startup.jl TTFX baseline script
- PackageCompiler+Julia1.12+WSL2 incompatibility fully investigated and documented: SIGTERM at ~7min on incremental LLVM link regardless of package list; persistent REPL + Revise.jl established as primary development workflow

### What Worked
- Phase 50 executed as a clean 5-plan wave: each plan had a single clear deliverable and no dependencies between Wave 1 plans (after 50-01 metadata)
- The `test/Project.toml` solution for direct test invocation is simple and doesn't break CI or Pkg.test()
- Physics-first README framing (reactor cooling loops and safety analysis before any mention of MTK) is the right orientation for a research library audience
- Phase 51 root-cause investigation was thorough — confirming the OOM was in the base incremental link step (not package-specific IR) required 4 attempts with progressively reduced package lists; result is a confident, documented conclusion rather than a workaround

### What Was Inefficient
- The MTR assembly power equation bug (HeatDiffusion power as @variables unknown) was a pre-existing misunderstanding that should have been caught during Phase 50-03 example development; it surfaced only during Phase 50-05 gap closure UAT
- Phase 51 goal (reliable sysimage) was not achievable on the current platform (Julia1.12+WSL2); the phase delivered documentation and best-effort build tooling, but the primary TTFX requirements (TTFX-04) were not met — the goal was too platform-dependent to be framed as a deliverable requirement

### Patterns Established
- **`test/Project.toml` for direct test invocation**: adding `[deps]` section with test-only packages enables `julia --project=. test/runtests.jl`; coexists with root `[extras]/[targets]` for CI
- **PackageCompiler to `[extras]`**: avoids LLVM becoming a transitive runtime dep for end users; always put build-only tools in `[extras]` not `[deps]`
- **Physics-first README structure**: lead with what the library *does* (reactor cooling loops, safety analysis) before mentioning MTK; target audience is domain scientists, not Julia library users

### Key Lessons
1. **Platform-dependent performance requirements need escape hatches in the plan** — TTFX-04 (sysimage on WSL2) should have been written as "if buildable" with a documented alternative (persistent REPL); framing it as a hard requirement led to a partial outcome
2. **UAT before marking a phase complete catches integration gaps** — the Phase 50 UAT found the MTR power equation bug that example-only testing missed; don't skip UAT for "documentation phases"
3. **Minimal CI is better than complex CI at first public release** — starting with stable-only, ubuntu-only keeps the matrix small and failures actionable; expand after usage patterns are established

### Cost Observations
- Model mix: ~100% sonnet (quality profile)
- Timeline: 2026-04-10 (single day, ~16 hours of wall time across two phases)
- Notable: Single-day release sprint from "all v0.9 work done" to "v1.0 public"; most of the time was Phase 51 sysimage investigation (4 build attempts); Phase 50 execution was fast (~30 min for 5 plans)

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.1 | 5 | 12 | First milestone — baseline established |
| v0.2 | 4 | 7 | Smaller plans (avg 1.75/phase vs 2.4/phase); `_channel_base_eqs` shared helper pattern emerges |
| v0.3 | 4 | 8 | Decimal phase insertion for post-validation correction; PipeGeometry encapsulation pattern; KINSOL for coupled solid+fluid DAE |
| v0.4 | 4 | 7 | Pluggable correlations via plain closures; `@observed` pattern for diagnostics; composition helpers with n-inference |
| v0.5 | 3 | 6 | Pure code quality — canonical file layout, test split, full docstrings, CLAUDE.md rationale; no new features |
| v0.6 | 8 | 14 | Flow reversal systems — MTK continuous events, callable parameters, bypass topology, NC regime detection |
| v0.7 | 7 | 13 | Safety physics suite — pressure field, SCB, threshold analysis, HTC/friction completions; audit-before-complete pattern validated |
| v0.8 | 13 | 32 | First GUI milestone — Tauri 2 + React + ReactFlow; ui-phase design contracts per frontend phase; pure function TDD for UI logic; registry-as-truth pattern |
| v0.9 | 5 | 8 | First neutronics milestone — callable MTK parameter pattern; additive rho composition; connect_temperature_feedback composition helper; SCRAM callback factory |
| v1.0 | 2 | 7 | Open-source release milestone — MIT license, CI, examples, README, test/Project.toml; sysimage WSL2 incompatibility documented; persistent REPL as primary workflow |

### Cumulative Quality

| Milestone | Tests | Requirements | Zero-Dep Additions |
|-----------|-------|--------------|-------------------|
| v0.1 | 54 | 15/15 | 0 |
| v0.2 | 86 | 10/10 | 0 |
| v0.3 | 161 | 14/14 | 0 |
| v0.4 | ~200+ | 15/15 | 0 |
| v0.5 | ~200+ | 15/15 | 0 |
| v0.6 | ~230+ | 21/21 | 0 |
| v0.7 | ~300+ | 33/34 | 1 (QuadGK) |
| v0.8 | ~300+ Julia + Vitest GUI | 40/40 | Tauri + React + ReactFlow stack (separate from Julia deps) |
| v0.9 | ~400+ Julia | 24/24 | No new deps — callable MTK pattern uses existing MTK infrastructure |
| v1.0 | ~400+ Julia (unchanged) | N/A (release infra) | No new Julia deps — PackageCompiler to [extras]; GitHub Actions added |

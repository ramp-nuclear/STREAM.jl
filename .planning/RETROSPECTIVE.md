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
- **Reversed-port wiring for descending components**: For any component where `port_in.P > port_out.P` (high-pressure entry), connect the physically-bottom-end to port_in regardless of flow direction
- **Multi-branch junction**: `connect(a, b, c, ...)` generates Kirchhoff automatically; always add a pressure anchor (`pump.port_in.P ~ 1.0e5`) to fix absolute pressure level
- **Shared equation helper pattern**: Extract `_foo_base_eqs(eqs, ...; kwargs)` that mutates `eqs` in-place before variant-specific coupling loop
- **ODE component with auto-promoted state**: Use `vars = []` and let MTK promote the `Dt(port_in.mdot)` variable; don't declare an explicit `mdot(t)` state

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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.1 | 5 | 12 | First milestone — baseline established |
| v0.2 | 4 | 7 | Smaller plans (avg 1.75/phase vs 2.4/phase); `_channel_base_eqs` shared helper pattern emerges |
| v0.3 | 4 | 8 | Decimal phase insertion for post-validation correction; PipeGeometry encapsulation pattern; KINSOL for coupled solid+fluid DAE |

### Cumulative Quality

| Milestone | Tests | Requirements | Zero-Dep Additions |
|-----------|-------|--------------|-------------------|
| v0.1 | 54 | 15/15 | 0 |
| v0.2 | 86 | 10/10 | 0 |
| v0.3 | 161 | 14/14 | 0 |

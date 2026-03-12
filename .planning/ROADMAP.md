# ROADMAP: STREAM.jl

**Milestone:** v0.1 — Single forced-convection loop proof-of-concept
**Granularity:** Coarse
**Requirements coverage:** 15/15 v1 requirements mapped

---

## Phases

- [x] **Phase 1: Foundation** - Package scaffold, fluid properties, and connectors that all components depend on
- [x] **Phase 2: Components** - All four thermal-hydraulic components with correct MTK equations (completed 2026-03-12)
- [x] **Phase 3: Integration and Validation** - Closed loop assembly, solver API, and comparison against Python STREAM (completed 2026-03-12)

---

## Phase Details

### Phase 1: Foundation
**Goal**: The substrate is in place — any component can be written and any equation can reference fluid properties
**Depends on**: Nothing
**Requirements**: FOUND-01, FOUND-02, CONN-01, CONN-02
**Success Criteria** (what must be TRUE):
  1. `using STREAM` loads without error and the package resolves its dependencies (MTK, DifferentialEquations, Sundials)
  2. `ρ_water(T)`, `cp_water(T)`, `μ_water(T)`, `k_water(T)` are callable symbolic functions; a short MTK model that uses them compiles without error
  3. `FlowPort` can be instantiated; it exposes pressure, mass flow, and temperature as symbolic variables with correct across/through semantics
  4. `ThermalPort` can be instantiated; it exposes temperature (across) and heat flow (through) as symbolic variables
**Plans**: 3 plans

Plans:
- [ ] 01-01-PLAN.md — Package scaffold, source stubs, and complete test suite
- [ ] 01-02-PLAN.md — Simantov fluid property implementations (FOUND-02)
- [ ] 01-03-PLAN.md — Connector verification and finalization (CONN-01, CONN-02)

### Phase 2: Components
**Goal**: Each thermal-hydraulic component is implemented as a standalone MTK component that can be instantiated and inspected in isolation
**Depends on**: Phase 1
**Requirements**: COMP-01, COMP-02, COMP-03, COMP-04
**Success Criteria** (what must be TRUE):
  1. `Channel(n=5)` instantiates and its equations include n energy balance cells, Dittus-Boelter HTC, and FlowPort/ThermalPort connections
  2. `Pump(dP_pump=...)` instantiates and its equation imposes a constant pressure rise across its two FlowPorts
  3. `Friction(L=..., D=..., ...)` instantiates and its equation applies Darcy-Weisbach pressure drop with the Blasius friction factor
  4. `Gravity(H=..., A_grav=...)` instantiates and its equation applies the hydrostatic pressure term ρgh across its two FlowPorts
  5. Each component passes `mtkcompile` in isolation (no connection errors, no unresolved variables)
**Plans**: 4 plans

Plans:
- [x] 02-01-PLAN.md — Test scaffold and component stubs (wave 0: enables parallel execution)
- [ ] 02-02-PLAN.md — Channel implementation with array variables and Dittus-Boelter HTC (COMP-01)
- [ ] 02-03-PLAN.md — Pump, Friction, Gravity algebraic component implementations (COMP-02, COMP-03, COMP-04)
- [ ] 02-04-PLAN.md — Gap closure: rename Pump/Gravity constructor kwargs to match MTK parameter names (COMP-02, COMP-04)

### Phase 3: Integration and Validation
**Goal**: A complete forced-convection loop runs, produces physically correct results, and those results match Python STREAM within tolerance
**Depends on**: Phase 2
**Requirements**: SYS-01, SYS-02, SOLV-01, SOLV-02, VAL-01, VAL-02, VAL-03
**Success Criteria** (what must be TRUE):
  1. The closed loop (Pump → Friction → Channel → Pump) assembles with `connect()`, compiles with `mtkcompile`, and produces a DAE system with no structural errors
  2. A user can construct components, wire them, call `solve_steady(system)`, and get back named outputs (T per cell, mass flow, pressures) without inspecting MTK internals
  3. `solve_steady` returns T_outlet and mass flow that differ from Python STREAM reference values by less than 1% on identical inputs
  4. `solve_transient` with a step change in channel power returns a time-series where temperature evolution qualitatively matches Python STREAM (same direction, same timescale order of magnitude)
  5. `julia --project -e "using Pkg; Pkg.test()"` runs and passes all comparison tests against Python STREAM reference outputs automatically
**Plans**: 3 plans

Plans:
- [ ] 03-01-PLAN.md — Closed-loop assembly, solve_steady, steady_state_guess (SYS-01, SYS-02, SOLV-01)
- [ ] 03-02-PLAN.md — Transient solver with PresetTimeCallback step change (SOLV-02)
- [ ] 03-03-PLAN.md — Python reference generation and Phase 3 test suite (VAL-01, VAL-02, VAL-03)

### Phase 4: Tech Debt Cleanup
**Goal**: All known tech debt from the v0.1 audit is resolved — no dead parameters, no stale docstrings, no broken test files, naming convention aligned with Python STREAM
**Depends on**: Phase 3
**Requirements**: None (quality/cleanup — no new requirements)
**Gap Closure**: Closes tech debt items from v0.1 audit
**Success Criteria** (what must be TRUE):
  1. `Gravity` component uses `H` as the MTK parameter in its pressure equation (BUG-01 fixed); `H_grav` and dead `A_grav` removed
  2. Channel, Friction parameters renamed to drop `_ch`/`_f` suffixes: `L_ch→L`, `A_ch→A`, `L_f→L`, `A_f→A` (aligned with Python STREAM)
  3. `solve_steady` docstring no longer references `ssys.fr.*`; example uses correct `ssys.ch.*` variables (BUG-02 fixed)
  4. Stale TDD files removed: `test_transient_tdd.jl`, `test_solvers_tdd.jl` deleted; `test_comp_tdd.jl` unstaged deletion committed
  5. `03-03-SUMMARY.md` `requirements-completed` frontmatter lists VAL-01, VAL-02, VAL-03
  6. `Pkg.test()` still passes all 54 tests after all changes
**Plans**: 1 plan

Plans:
- [ ] 04-01-PLAN.md — Fix BUG-01/BUG-02, rename parameters, clean stale files, fix SUMMARY frontmatter

### Phase 5: Nyquist Validation
**Goal**: All three v0.1 phases have formal validation records — the GSD system knows the code was verified, not just that tests pass
**Depends on**: Phase 4
**Requirements**: None (process/bookkeeping)
**Gap Closure**: Closes Nyquist compliance gaps for phases 01, 02, 03
**Success Criteria** (what must be TRUE):
  1. Phase 01 has a completed Nyquist validation record
  2. Phase 02 has a completed Nyquist validation record
  3. Phase 03 has a completed Nyquist validation record
  4. All three phases show `nyquist_compliant: true` in their metadata
**Plans**: 1 plan

Plans:
- [ ] 05-01-PLAN.md — Run /gsd:validate-phase for phases 01, 02, 03

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 3/3 | Done | 2026-03-12 |
| 2. Components | 4/4 | Complete   | 2026-03-12 |
| 3. Integration and Validation | 3/3 | Complete   | 2026-03-12 |
| 4. Tech Debt Cleanup | 0/1 | Pending | — |
| 5. Nyquist Validation | 0/1 | Pending | — |

---

*Created: 2026-03-12*
*Updated: 2026-03-12 — Phase 2 gap closure plan added (02-04)*
*Updated: 2026-03-12 — Phases 4-5 added from v0.1 audit gap closure*

# ROADMAP: STREAM.jl

**Milestone:** v0.1 — Single forced-convection loop proof-of-concept
**Granularity:** Coarse
**Requirements coverage:** 15/15 v1 requirements mapped

---

## Phases

- [ ] **Phase 1: Foundation** - Package scaffold, fluid properties, and connectors that all components depend on
- [x] **Phase 2: Components** - All four thermal-hydraulic components with correct MTK equations (completed 2026-03-12)
- [ ] **Phase 3: Integration and Validation** - Closed loop assembly, solver API, and comparison against Python STREAM

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
  2. `Pump(dP=...)` instantiates and its equation imposes a constant pressure rise across its two FlowPorts
  3. `Friction(L=..., D=..., ...)` instantiates and its equation applies Darcy-Weisbach pressure drop with the Blasius friction factor
  4. `Gravity(H=..., ...)` instantiates and its equation applies the hydrostatic pressure term ρgh across its two FlowPorts
  5. Each component passes `mtkcompile` in isolation (no connection errors, no unresolved variables)
**Plans**: 3 plans

Plans:
- [x] 02-01-PLAN.md — Test scaffold and component stubs (wave 0: enables parallel execution)
- [ ] 02-02-PLAN.md — Channel implementation with array variables and Dittus-Boelter HTC (COMP-01)
- [ ] 02-03-PLAN.md — Pump, Friction, Gravity algebraic component implementations (COMP-02, COMP-03, COMP-04)

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
**Plans**: TBD

---

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 3/3 | Done | 2026-03-12 |
| 2. Components | 3/3 | Complete   | 2026-03-12 |
| 3. Integration and Validation | 0/? | Not started | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-12 — Phase 2 plans written*

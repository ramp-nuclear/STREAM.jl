# ROADMAP: STREAM.jl

## Milestones

- ✅ **v0.1 MVP** — Phases 1-5 (shipped 2026-03-13)
- ✅ **v0.2 Component & Network Expansion** — Phases 6-9 (shipped 2026-03-13)
- ✅ **v0.3 HeatDiffusion** — Phases 10-12.1 (shipped 2026-03-14)
- ✅ **v0.4 Composability & Physics** — Phases 13-16 (shipped 2026-03-16)
- 🚧 **v0.5 Code Quality** — Phases 17-19 (in progress)

## Phases

<details>
<summary>✅ v0.1 MVP (Phases 1-5) — SHIPPED 2026-03-13</summary>

- [x] Phase 1: Foundation (3/3 plans) — completed 2026-03-12
- [x] Phase 2: Components (4/4 plans) — completed 2026-03-12
- [x] Phase 3: Integration and Validation (3/3 plans) — completed 2026-03-12
- [x] Phase 4: Tech Debt Cleanup (1/1 plan) — completed 2026-03-12
- [x] Phase 5: Nyquist Validation (1/1 plan) — completed 2026-03-12

Full phase details: `.planning/milestones/v0.1-ROADMAP.md`

</details>

<details>
<summary>✅ v0.2 Component & Network Expansion (Phases 6-9) — SHIPPED 2026-03-13</summary>

- [x] Phase 6: Gravity Validation (1/1 plan) — completed 2026-03-13
- [x] Phase 7: Network Architecture (2/2 plans) — completed 2026-03-13
- [x] Phase 8: Inertia and HeatExchanger (2/2 plans) — completed 2026-03-13
- [x] Phase 9: ChannelAndContacts (2/2 plans) — completed 2026-03-13

Full phase details: `.planning/milestones/v0.2-ROADMAP.md`

</details>

<details>
<summary>✅ v0.3 HeatDiffusion (Phases 10-12.1) — SHIPPED 2026-03-14</summary>

- [x] Phase 10: ChannelAndContacts Two-Sided Upgrade (2/2 plans) — completed 2026-03-13
- [x] Phase 11: HeatDiffusion Component (2/2 plans) — completed 2026-03-14
- [x] Phase 12: MTR Validation (2/2 plans) — completed 2026-03-14
- [x] Phase 12.1: PipeGeometry Struct (2/2 plans) — completed 2026-03-14

Full phase details: `.planning/milestones/v0.3-ROADMAP.md`

</details>

<details>
<summary>✅ v0.4 Composability & Physics (Phases 13-16) — SHIPPED 2026-03-16</summary>

- [x] Phase 13: Physics Foundation (2/2 plans) — completed 2026-03-14
- [x] Phase 14: Laminar Correlations (2/2 plans) — completed 2026-03-14
- [x] Phase 15: Composition Helpers & QoL (2/2 plans) — completed 2026-03-15
- [x] Phase 16: Validation (1/1 plan) — completed 2026-03-15

Full phase details: `.planning/milestones/v0.4-ROADMAP.md`

</details>

### 🚧 v0.5 Code Quality (In Progress)

**Milestone Goal:** Reorganize files to match the canonical CLAUDE.md layout, add docstrings to all exported names, split the monolithic test file, and fix minor code quality issues — no new features.

## Phase Details

### Phase 17: File Structure Reorganization
**Goal**: The codebase on disk matches the canonical file layout defined in CLAUDE.md
**Depends on**: Phase 16
**Requirements**: STR-01, STR-02, STR-03, STR-04, STR-05
**Success Criteria** (what must be TRUE):
  1. `src/geometry.jl` exists as a standalone file; `components.jl` no longer contains `PipeGeometry`
  2. `src/components/` contains six dedicated files (`channel.jl`, `pump.jl`, `resistors.jl`, `misc.jl`, `thermal_channel.jl`, `heat_diffusion.jl`); the old monolithic `components.jl` is gone
  3. `src/physical_models/correlations.jl` exists; the old `src/correlations.jl` is gone
  4. `src/composition/helpers.jl` exists; the old `src/helpers.jl` is gone
  5. `src/examples.jl` contains `build_loop*`, `build_cube`; `src/solvers.jl` contains only solver logic
**Plans**: 2 plans

Plans:
- [ ] 17-01-PLAN.md — Extract geometry.jl and split components.jl into src/components/ (STR-01, STR-02)
- [ ] 17-02-PLAN.md — Move correlations.jl, helpers.jl, extract examples.jl (STR-03, STR-04, STR-05)

### Phase 18: Test Split and API Cleanup
**Goal**: The test suite is a collection of focused per-file test modules; `solve_transient` has a keyword-only signature; the orphaned VAL-03 placeholder is gone
**Depends on**: Phase 17
**Requirements**: TEST-01, QOL-01, QOL-02
**Success Criteria** (what must be TRUE):
  1. `test/runtests.jl` contains only `@testset` wrappers and `include()` calls — no test logic
  2. Thirteen `test_*.jl` files exist under `test/`, each matching one src file area per CLAUDE.md layout
  3. `solve_transient(sys, prob; kwargs...)` rejects positional arguments for solver options at the call site
  4. The orphaned `@testset "VAL-03"` block is absent from `runtests.jl` and from all `test_*.jl` files
**Plans**: TBD

Plans:
- [ ] 18-01: TBD

### Phase 19: Docstrings, CLAUDE.md, and Final Polish
**Goal**: Every exported name has a Julia docstring; CLAUDE.md explains the rationale behind each rule; `ChannelHeatFlux`/`ConstantTemperature` are confirmed ship-ready; version is bumped to 0.5.0
**Depends on**: Phase 18
**Requirements**: DOC-01, DOC-02, DOC-03, DOC-04, QOL-03, QOL-04, QOL-05
**Success Criteria** (what must be TRUE):
  1. `?ComponentName` in the Julia REPL returns a docstring with `# Arguments` and `# Returns` for all 11 component constructors
  2. `?helperName` returns a docstring with `# Arguments` and `# Returns` for all 6 composition and QoL helpers
  3. `?solve_steady`, `?solve_transient`, `?build_loop`, and related solver/example functions each return a complete docstring
  4. `?rho_water` (and `cp_water`, `mu_water`, `k_water`) return docstrings with `# Arguments` and `# Returns`
  5. CLAUDE.md contains a rationale sentence for each rule; `Project.toml` reads `version = "0.5.0"`; `ChannelHeatFlux` and `ConstantTemperature` are exported, tested, and documented
**Plans**: TBD

Plans:
- [ ] 19-01: TBD

## Progress

**Execution Order:** Phases execute in numeric order: 17 → 18 → 19

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 2. Components | v0.1 | 4/4 | Complete | 2026-03-12 |
| 3. Integration and Validation | v0.1 | 3/3 | Complete | 2026-03-12 |
| 4. Tech Debt Cleanup | v0.1 | 1/1 | Complete | 2026-03-12 |
| 5. Nyquist Validation | v0.1 | 1/1 | Complete | 2026-03-12 |
| 6. Gravity Validation | v0.2 | 1/1 | Complete | 2026-03-13 |
| 7. Network Architecture | v0.2 | 2/2 | Complete | 2026-03-13 |
| 8. Inertia and HeatExchanger | v0.2 | 2/2 | Complete | 2026-03-13 |
| 9. ChannelAndContacts | v0.2 | 2/2 | Complete | 2026-03-13 |
| 10. ChannelAndContacts Two-Sided Upgrade | v0.3 | 2/2 | Complete | 2026-03-13 |
| 11. HeatDiffusion Component | v0.3 | 2/2 | Complete | 2026-03-14 |
| 12. MTR Validation | v0.3 | 2/2 | Complete | 2026-03-14 |
| 12.1. PipeGeometry Struct | v0.3 | 2/2 | Complete | 2026-03-14 |
| 13. Physics Foundation | v0.4 | 2/2 | Complete | 2026-03-14 |
| 14. Laminar Correlations | v0.4 | 2/2 | Complete | 2026-03-14 |
| 15. Composition Helpers & QoL | v0.4 | 2/2 | Complete | 2026-03-15 |
| 16. Validation | v0.4 | 1/1 | Complete | 2026-03-15 |
| 17. File Structure Reorganization | 2/2 | Complete    | 2026-03-16 | - |
| 18. Test Split and API Cleanup | v0.5 | 0/TBD | Not started | - |
| 19. Docstrings, CLAUDE.md, and Final Polish | v0.5 | 0/TBD | Not started | - |

---

*Created: 2026-03-12*
*Updated: 2026-03-16 — Phase 17 planned: 2 plans*

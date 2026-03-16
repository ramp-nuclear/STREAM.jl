# Requirements: STREAM.jl

**Defined:** 2026-03-16
**Core Value:** A Julia MTK-based thermal-hydraulics library that matches Python STREAM results, proving the architecture is sound before large-scale porting begins.

## v0.5 Requirements

### Structure

- [x] **STR-01**: Codebase can load after `src/geometry.jl` is extracted from `components.jl` and `STREAM.jl` includes updated
- [x] **STR-02**: `components.jl` is split into 6 files under `src/components/` (`channel.jl`, `pump.jl`, `resistors.jl`, `misc.jl`, `thermal_channel.jl`, `heat_diffusion.jl`) and all tests still pass
- [ ] **STR-03**: `correlations.jl` is moved to `src/physical_models/correlations.jl`
- [ ] **STR-04**: `helpers.jl` is moved to `src/composition/helpers.jl`
- [ ] **STR-05**: `build_loop*`/`build_cube`/`steady_state_guess` are extracted from `solvers.jl` into `src/examples.jl`

### Docs

- [ ] **DOC-01**: All 11 component constructors have Julia docstrings with `# Arguments` and `# Returns`
- [ ] **DOC-02**: All 6 composition/QoL helpers have Julia docstrings with `# Arguments` and `# Returns`
- [ ] **DOC-03**: All 7 solver/example functions have Julia docstrings with `# Arguments` and `# Returns`
- [ ] **DOC-04**: `rho_water`, `cp_water`, `mu_water`, `k_water` docstrings completed with `# Arguments` and `# Returns`

### Test

- [ ] **TEST-01**: `test/runtests.jl` is a thin orchestrator of `include()` calls; all test logic lives in 13 dedicated `test_*.jl` files matching CLAUDE.md layout

### QoL

- [ ] **QOL-01**: `solve_transient` converted to keyword-only signature; all call sites updated
- [ ] **QOL-02**: Orphaned `@testset "VAL-03"` Phase 1 placeholder removed from `runtests.jl`
- [ ] **QOL-03**: CLAUDE.md rewritten with rationale behind each rule and MTK-specific patterns
- [ ] **QOL-04**: `Project.toml` version bumped to `0.5.0`
- [ ] **QOL-05**: `ChannelHeatFlux` and `ConstantTemperature` audited — confirm exported, tested, and documented

## Future Requirements

### Structure

- **STR-F01**: `src/fluids.jl` split into `src/substances/light_water.jl` (+ `heavy_water.jl`) when multi-fluid support is added — align with Python STREAM `substances/` naming
- **STR-F02**: `src/physical_models/correlations.jl` split into `htc/` and `friction/` subdirectories when file exceeds ~300 lines

## Out of Scope

| Feature | Reason |
|---------|--------|
| New components or physics | v0.5 is pure code quality — zero new features |
| AbstractFluid / multi-fluid dispatch | Deferred to v0.6+ per agreed long-term design |
| Point kinetics, decay heat | Deferred to v0.6+ |
| Python adapter (juliacall) | Explicitly out of scope across all milestones |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STR-01 | Phase 17 | Complete |
| STR-02 | Phase 17 | Complete |
| STR-03 | Phase 17 | Pending |
| STR-04 | Phase 17 | Pending |
| STR-05 | Phase 17 | Pending |
| DOC-01 | Phase 19 | Pending |
| DOC-02 | Phase 19 | Pending |
| DOC-03 | Phase 19 | Pending |
| DOC-04 | Phase 19 | Pending |
| TEST-01 | Phase 18 | Pending |
| QOL-01 | Phase 18 | Pending |
| QOL-02 | Phase 18 | Pending |
| QOL-03 | Phase 19 | Pending |
| QOL-04 | Phase 19 | Pending |
| QOL-05 | Phase 19 | Pending |

**Coverage:**
- v0.5 requirements: 15 total
- Mapped to phases: 15
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-16*
*Last updated: 2026-03-16 — traceability updated after roadmap creation (phases 17-19)*

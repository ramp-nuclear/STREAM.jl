# Phase 18: Test Split and API Cleanup - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Split the 1805-line monolithic `test/runtests.jl` into 13 focused `test_*.jl` files matching the CLAUDE.md layout. Convert `solve_transient` to a fully keyword-only signature and update all call sites. The "orphaned VAL-03 placeholder" requirement (QOL-02) is already satisfied — VAL-03 has real content and will be kept, moved to `test_validation.jl`.

No new tests, no new physics, no logic changes.

</domain>

<decisions>
## Implementation Decisions

### Test file mapping

All VAL-* tests land in `test_validation.jl` regardless of which phase introduced them:
- Phase 3 VAL-01 (steady-state vs Python STREAM) → `test_validation.jl`
- Phase 3 VAL-02 (transient T_outlet rises) → `test_validation.jl`
- Phase 12 VAL-01/02/03 (MTR symmetric/asymmetric/one-sided) → `test_validation.jl`
- Phase 16 VAL-01 (HeatDiffusion Fourier transient) → `test_validation.jl`
- Phase 16 VAL-02 (two-plate one-channel topology) → `test_validation.jl`

SOLV-01/02 tests (Phase 3: build_loop compiles, solve_steady/solve_transient behavior) → `test_solvers.jl`

All other placements follow the CLAUDE.md file layout directly (component file → matching test file).

### VAL-03 disposition

QOL-02 ("remove orphaned VAL-03 placeholder") is already satisfied. The VAL-03 test at line 1074 has real, passing content implementing the one-sided MTR adiabatic validation. It was not a placeholder at the time of Phase 18. **Keep it and move to `test_validation.jl`.**

Do NOT delete it.

### solve_transient keyword-only

Convert to fully keyword-only signature — all 4 positional args become keyword args:

```julia
# Before:
function solve_transient(ssys, T_wall_sym, op, tspan; T_wall_final, t_step=10.0)

# After:
function solve_transient(; ssys, T_wall_sym, op, tspan, T_wall_final, t_step=10.0)
```

Update all call sites in `test/` (approximately 4 call sites). This matches the project-wide convention that all exported functions/constructors use keyword-only arguments.

### runtests.jl thin orchestrator

After the split, `test/runtests.jl` contains **only `include()` calls** — no `using` statements, no test logic.

Each `test_*.jl` file is self-contained with its own `using Test`, `using STREAM`, etc., so it can be run standalone with `julia test/test_channel.jl`. This is standard Julia convention for test suites.

### Claude's Discretion

- Exact ordering of `include()` calls in the new `runtests.jl`
- Whether to add a top-level `@testset "STREAM.jl"` wrapper in runtests.jl or leave includes bare
- Handling the `const SciMLBase = ...` line (currently at file top for the RL-decay test) — move it into the relevant test file

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Target test file layout
- `CLAUDE.md` §`test/` — authoritative list of 13 target test files and which src file each mirrors

### Requirements
- `.planning/REQUIREMENTS.md` §TEST-01, QOL-01, QOL-02 — the three requirements for this phase
- `.planning/ROADMAP.md` §Phase 18 — success criteria

### Source to understand
- `test/runtests.jl` — the 1805-line monolith being split; read it fully before planning the split
- `src/solvers.jl` — contains `solve_transient` signature and its call sites in test/ need updating

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `test/runtests.jl` — the complete monolith; every line moves to exactly one destination file (nothing is deleted except the top-level `using` block, which gets redistributed into each test file)

### Established Patterns
- All src files use keyword-only constructors — `solve_transient` keyword conversion brings solvers.jl into alignment
- `@testset` blocks do NOT need to change names or content during the split — only their file location changes
- The CLAUDE.md test placement rule: `components/channel.jl` → `test_channel.jl`, etc.

### Integration Points
- `test/runtests.jl` is the only entry point for `Pkg.test()` — the thin orchestrator must include all 13 files to preserve full coverage
- `src/solvers.jl` function signature change cascades to ~4 call sites in the test files

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for the mechanical split.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 18-test-split-and-api-cleanup*
*Context gathered: 2026-03-16*

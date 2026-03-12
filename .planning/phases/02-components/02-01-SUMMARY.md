---
phase: 02-components
plan: 01
subsystem: testing
tags: [julia, modelingtoolkit, components, stubs, tdd, test-scaffold]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "FlowPort, ThermalPort connectors; fluid property functions; STREAM module structure"
provides:
  - "src/components.jl with Channel, Pump, Friction, Gravity stub functions that throw ErrorException"
  - "Updated src/STREAM.jl exporting all four component names"
  - "Phase 2 testsets in test/runtests.jl (COMP-01 through COMP-04)"
  - "Wave-0 test harness: stub tests pass, deferred implementation tests skipped"
affects: [02-02, 02-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stub-first TDD: declare function stubs that throw ErrorException before implementing"
    - "Explicit import disambiguation: `import STREAM: Channel` resolves Base.Channel name conflict"
    - "q_wall indirection: single ThermalPort carries total Q_wall, split per-cell internally"
    - "@test_skip for deferred implementation tests (vs @test_broken for known failures)"

key-files:
  created:
    - src/components.jl
  modified:
    - src/STREAM.jl
    - test/runtests.jl

key-decisions:
  - "Use `function Channel end` forward declaration to create new generic function independent of Base.Channel"
  - "Add `import STREAM: Channel, Pump, Friction, Gravity` in runtests.jl header to resolve ambiguity"
  - "Use @test_skip (not @test_broken) for deferred equation-count and mtkcompile tests"

patterns-established:
  - "Stub pattern: keyword-argument functions matching locked signatures that throw ErrorException"
  - "Name conflict resolution: explicit module import in test file when component name clashes with Base"

requirements-completed: [COMP-01, COMP-02, COMP-03, COMP-04]

# Metrics
duration: 2min
completed: 2026-03-12
---

# Phase 2 Plan 01: Component Stubs and Test Scaffold Summary

**Four thermal-hydraulic component stubs (Channel, Pump, Friction, Gravity) with Phase 2 testsets — wave-0 harness enabling parallel PLAN 02 and PLAN 03 execution**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-12T00:52:00Z
- **Completed:** 2026-03-12T00:54:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Created `src/components.jl` with four stub functions matching locked parameter signatures, each throwing `ErrorException`
- Included q_wall indirection design comment in components.jl per CONTEXT.md requirement
- Updated `src/STREAM.jl` to include components.jl and export Channel, Pump, Friction, Gravity
- Added Phase 2 testsets (COMP-01 through COMP-04) to `test/runtests.jl`
- Full test suite passes: Phase 1 all 25 green, Phase 2 four @test_throws pass + two @test_skip

## Task Commits

Each task was committed atomically:

1. **Task 1: Create src/components.jl with stubs and update STREAM.jl** - `a33c023` (feat)
2. **Task 2: Add Phase 2 testsets to test/runtests.jl** - `a3382cf` (test)

## Files Created/Modified
- `src/components.jl` - Four stub component functions with ErrorException + q_wall design comment
- `src/STREAM.jl` - Added include("components.jl") and exports for Channel/Pump/Friction/Gravity
- `test/runtests.jl` - Added STREAM Phase 2 Tests block + import disambiguation

## Decisions Made
- `function Channel end` forward declaration used to create a new generic function independent of `Base.Channel` (Julia's built-in concurrency channel type), avoiding method overwrite error during precompilation
- Added `import STREAM: Channel, Pump, Friction, Gravity` in runtests.jl to resolve name ambiguity that would otherwise cause `UndefVarError` when both `Base` and `STREAM` export `Channel`
- Used `@test_skip` (not `@test_broken`) for deferred equation-count and mtkcompile checks — skip indicates "not yet written", producing yellow indicators rather than red failures

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Base.Channel name conflict preventing STREAM precompilation**
- **Found during:** Task 1 (Create src/components.jl)
- **Issue:** Julia treats `function Channel(; ...)` as extending `Base.Channel` constructor, causing "Method overwriting is not permitted during Module precompilation" error
- **Fix:** Added `function Channel end` forward declaration before the method definition to declare a new generic function; added `import STREAM: Channel, Pump, Friction, Gravity` in runtests.jl header to resolve the resulting ambiguity when `using STREAM`
- **Files modified:** src/components.jl, test/runtests.jl
- **Verification:** `julia --project=. -e 'using STREAM; import STREAM: Channel; println(Channel)'` prints `Channel`; full test suite exits 0
- **Committed in:** a33c023 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - bug: Julia name shadowing)
**Impact on plan:** Fix is essential for correctness — without it STREAM fails to precompile. No scope creep.

## Issues Encountered
- `Base.Channel` name collision: Julia 1.12 deprecated silent method extension without explicit import, making the `Channel` function name a breaking conflict. Resolved via forward declaration pattern.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Wave-0 test harness complete — PLAN 02 (Channel implementation) and PLAN 03 (Pump/Friction/Gravity) can run in parallel
- All stubs throw `ErrorException` so test failures are explicit (not load errors)
- `@test_skip` entries in COMP-01 will be filled in by PLAN 02

---
*Phase: 02-components*
*Completed: 2026-03-12*

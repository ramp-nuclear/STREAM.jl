---
phase: 36-code-generation
plan: 01
subsystem: ui
tags: [typescript, vitest, code-generation, julia, stream-composer]

# Dependency graph
requires:
  - phase: 35-canvas-store-sidebar
    provides: Component registry (types.ts, components.json), store (useStore.ts), validation (validation.ts)
provides:
  - generateCode() pure function for canvas-to-Julia-code transformation
  - BCEntry interface for boundary condition specification
affects: [36-02 (CodePanel UI wiring), 36-03 (clipboard/export integration)]

# Tech tracking
tech-stack:
  added: []
  patterns: [pure-function code generation, factory-param recursion, default elision against registry]

key-files:
  created:
    - gui/src/lib/codeGenerator.ts
    - gui/src/lib/codeGenerator.test.ts
  modified: []

key-decisions:
  - "formatFunctionParam recurses one level for nested factory sub-params (e.g., regime_dependent containing elenbaas_htc)"
  - "Default elision compares parameter values against registry defaults and omits matches for cleaner generated code"
  - "Factory sub-parameter defaults are looked up from FunctionOption.sub_parameters definitions in registry"

patterns-established:
  - "Pure function pattern: generateCode has zero React/DOM dependencies, testable in node environment"
  - "Registry-driven code gen: all formatting decisions driven by ComponentDefinition metadata"

requirements-completed: [CODE-01, CODE-03, CODE-04, CODE-05, CODE-06, CODE-07]

# Metrics
duration: 3min
completed: 2026-04-02
---

# Phase 36 Plan 01: Code Generator Pure Function Summary

**Pure generateCode() function transforms canvas nodes/edges/BCs into valid STREAM.jl Julia code with positional/keyword arg handling, factory param recursion, and default elision**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-02T14:22:42Z
- **Completed:** 2026-04-02T14:26:14Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 2

## Accomplishments
- Pure code generation function with zero React dependencies
- Handles all parameter types: Real, Int, Bool, PipeGeometry, Function (simple + factory with nesting), Matrix
- Default parameter elision against registry definitions (including factory sub-param defaults)
- 22 unit tests covering empty state, all component types, connections, BCs, identifier validation, formatting, system structure

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Failing tests** - `0783408` (test)
2. **Task 1 GREEN: Implementation** - `e13523b` (feat)

## Files Created/Modified
- `gui/src/lib/codeGenerator.ts` - Pure code generation function (generateCode, BCEntry, formatReal, formatFunctionParam, etc.)
- `gui/src/lib/codeGenerator.test.ts` - 22 unit tests with mock component definitions matching real registry structure

## Decisions Made
- Factory function parameter formatting recurses through FunctionOption.sub_parameters for nested factories (e.g., regime_dependent with elenbaas_htc)
- Default elision uses direct value comparison against registry param.default; factory objects never match string defaults
- PipeGeometry emits TODO comment when dimensions are missing rather than failing

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- generateCode() ready for wiring into CodePanel UI (Plan 02)
- BCEntry type exported for boundary condition UI integration
- All tests green, function is pure and side-effect-free

## Self-Check: PASSED

All files exist, all commits found.

---
*Phase: 36-code-generation*
*Completed: 2026-04-02*

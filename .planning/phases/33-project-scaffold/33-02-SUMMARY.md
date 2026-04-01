---
phase: 33-project-scaffold
plan: 02
subsystem: ui
tags: [typescript, json-registry, vitest, reactflow, stream-components]

# Dependency graph
requires:
  - phase: 33-01
    provides: Tauri 2 + React + Vite scaffold with Zustand store and Vitest config
provides:
  - gui/src/registry/types.ts with TypeScript interfaces for registry schema
  - gui/src/registry/components.json with all 12 STREAM.jl components
  - gui/src/registry/index.ts with getComponent/getComponentsByCategory/getAllComponents/registry exports
  - gui/src/registry/__tests__/registry.test.ts with 14 passing validation tests
affects: [34-canvas-editor, 36-code-generation, 40-thermal-composition]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Registry-driven component metadata: all STREAM.jl component knowledge in JSON; TypeScript is data-unaware"
    - "ThermalPort array metadata: array=true + arrayParam on Port interface for n-cell ThermalPort arrays"
    - "Pump multi-dispatch: two constructorModes (fixed-dP positional, fixed-mdot keyword) in single JSON entry"
    - "positional field on Parameter drives Phase 36 code generation for @named macro output"

key-files:
  created:
    - gui/src/registry/types.ts
    - gui/src/registry/components.json
    - gui/src/registry/index.ts
    - gui/src/registry/__tests__/registry.test.ts
  modified:
    - gui/vitest.config.ts

key-decisions:
  - "vitest default environment changed from jsdom to node: jsdom has ESM incompatibility with html-encoding-sniffer on Node.js 18; registry tests are pure data-logic (no DOM); React component tests in later phases should use @vitest-environment jsdom docblock per-file"
  - "ChannelHeatFlux has no ThermalPort: T_wall is a scalar Real parameter, not a port connection; _note field added to JSON entry to prevent future confusion"
  - "positional: boolean added to Parameter interface beyond RESEARCH.md spec: needed for Phase 36 code generation to distinguish @named macro positional vs keyword arg syntax"
  - "Bool and Matrix added to Parameter.type union: needed for Flapper.use_callback and HeatDiffusion.power_shape respectively"
  - "category union restricted to Hydraulic|Thermal only (removed Structural from RESEARCH.md spec): no Structural components in STREAM.jl v0.7"

patterns-established:
  - "Registry-first architecture: SCAF-04 validated -- no TypeScript knows component IDs; all component knowledge flows from JSON import"
  - "Per-file vitest environment override: use @vitest-environment jsdom docblock for React component tests; registry/logic tests use node default"

requirements-completed:
  - SCAF-03
  - SCAF-04
  - SCAF-05

# Metrics
duration: 4min
completed: 2026-04-01
---

# Phase 33 Plan 02: Component Registry Summary

**JSON registry of all 12 STREAM.jl components with TypeScript types, loader module, and 14 passing Vitest validation tests covering ports, parameters, constructor modes, ThermalPort arrays, and stream_version**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-01T20:24:42Z
- **Completed:** 2026-04-01T20:28:30Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Created types.ts with Port, Parameter (including positional field), ConstructorMode, ComponentDefinition, ComponentRegistry interfaces
- Created components.json with all 12 STREAM.jl components: correct ThermalPort arrays for ChannelAndContacts (arrayParam="n") and HeatDiffusion (arrayParam="nz"), ChannelHeatFlux correctly with no ThermalPort and _note field, Pump with 2 constructor modes, stream_version "0.7.0"
- Created index.ts registry loader with getComponent, getComponentsByCategory, getAllComponents, registry exports
- Created 14 Vitest tests covering SCAF-03, SCAF-04, SCAF-05; all pass; fixed jsdom ESM incompatibility on Node.js 18 by switching vitest default environment to node

## Task Commits

Each task was committed atomically:

1. **Task 1: Create registry TypeScript types, components.json, and loader module** - `e43f254` (feat)
2. **Task 2: Create registry validation tests** - `2c3b2e6` (test)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified
- `gui/src/registry/types.ts` - TypeScript interfaces for registry schema (Port, Parameter with positional, ConstructorMode, ComponentDefinition, ComponentRegistry)
- `gui/src/registry/components.json` - Full 12-component registry with stream_version "0.7.0", schema_version "1.0"
- `gui/src/registry/index.ts` - Registry loader and accessor functions
- `gui/src/registry/__tests__/registry.test.ts` - 14 Vitest tests validating SCAF-03/04/05
- `gui/vitest.config.ts` - Changed default environment from jsdom to node (ESM compatibility fix)

## Decisions Made
- Added `positional: boolean` to Parameter interface (beyond RESEARCH.md spec) because Phase 36 code generation needs to distinguish positional vs keyword args for `@named` macro output
- Added `Bool` and `Matrix` to Parameter.type union for Flapper.use_callback and HeatDiffusion.power_shape
- Category union restricted to `Hydraulic | Thermal` only (RESEARCH.md included `Structural` which has no STREAM.jl components)
- `_note` field added to ComponentDefinition interface and ChannelHeatFlux JSON entry to document T_wall scalar BC distinction

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed Vitest jsdom ESM incompatibility on Node.js 18**
- **Found during:** Task 2 (registry validation tests)
- **Issue:** `npx vitest run` failed with `require() of ES Module encoding-lite.js ... not supported` from html-encoding-sniffer within jsdom; error prevented test runner from starting
- **Fix:** Changed vitest.config.ts default environment from `"jsdom"` to `"node"`; added comment that React component tests in later phases should use `@vitest-environment jsdom` docblock per-file
- **Files modified:** gui/vitest.config.ts
- **Verification:** All 14 tests pass with `npx vitest run`
- **Committed in:** 2c3b2e6 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking environment issue)
**Impact on plan:** Fix necessary for tests to run at all. No scope creep. Per-file jsdom override is the correct Vitest v4 pattern for mixed-environment test suites.

## Issues Encountered
- Node.js 18 + jsdom have ESM incompatibility via `html-encoding-sniffer` - resolved by switching vitest default to `node` environment

## Known Stubs
None - registry is complete data with no stubs or placeholder values.

## Next Phase Readiness
- Registry is the coupling contract between STREAM.jl and the GUI; Phase 34 (canvas editor) can consume registry data to populate toolbox and render nodes
- Phase 36 (code generation) can use `positional: boolean` and `constructorModes` to generate correct `@named` syntax
- Phase 40 (thermal composition) can use `array: true` and `arrayParam` to render ThermalPort array handles for ChannelAndContacts and HeatDiffusion
- TypeScript compiles cleanly; all 14 registry tests pass

---
*Phase: 33-project-scaffold*
*Completed: 2026-04-01*

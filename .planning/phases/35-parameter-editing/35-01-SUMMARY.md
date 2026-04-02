---
phase: 35-parameter-editing
plan: 01
subsystem: gui
tags: [registry, store, validation, shadcn, canvas-selection]
dependency_graph:
  requires: [34-02]
  provides: [registry-function-options, store-updateNodeParams, validation-library, canvas-selection]
  affects: [35-02, 35-03]
tech_stack:
  added: [class-variance-authority, "@radix-ui/react-label", "@radix-ui/react-select", "@radix-ui/react-tooltip", "@radix-ui/react-separator", "@radix-ui/react-scroll-area"]
  patterns: [FunctionOption-registry-schema, updateNodeParams-store-action, default-population-on-addNode]
key_files:
  created:
    - gui/src/lib/validation.ts
    - gui/src/lib/__tests__/validation.test.ts
    - gui/src/components/ui/input.tsx
    - gui/src/components/ui/label.tsx
    - gui/src/components/ui/button.tsx
    - gui/src/components/ui/select.tsx
    - gui/src/components/ui/tooltip.tsx
    - gui/src/components/ui/separator.tsx
    - gui/src/components/ui/badge.tsx
    - gui/src/components/ui/scroll-area.tsx
  modified:
    - gui/src/registry/types.ts
    - gui/src/registry/components.json
    - gui/src/store/useStore.ts
    - gui/src/components/CanvasPanel.tsx
    - gui/src/store/__tests__/useStore.test.ts
    - gui/package.json
decisions:
  - "class-variance-authority added as dependency for shadcn badge and button components"
  - "Node data cast uses 'as unknown as StreamNodeData' to satisfy TypeScript strict mode with ReactFlow's Record<string, unknown> node data type"
metrics:
  duration: 284s
  completed: "2026-04-02T00:22:00Z"
---

# Phase 35 Plan 01: Store, Registry & Validation Foundation Summary

Extended the registry, store, and validation layer to support parameter editing -- the data foundation for all sidebar UI components in Plan 02.

## One-liner

FunctionOption registry schema with correlation dropdowns, updateNodeParams store action with default population, validation library with 4 exported functions, and canvas-to-sidebar selection wiring.

## Changes Made

### Task 1: Extend registry schema, store, and install shadcn components (222dd2b)

- Added `FunctionOption` interface (`value`, `label`, `kind: "simple" | "factory"`) to `types.ts`
- Added `options?: FunctionOption[]` field to `Parameter` interface
- Added `options` arrays to `htc_correlation` (5 entries: Dittus-Boelter, Constant Nusselt, Regime Dependent, Elenbaas, Maximal HTC) and `friction_correlation` (2 entries: Blasius, Laminar) on Channel, ChannelAndContacts, and ChannelHeatFlux in `components.json`
- Added `constructorMode?: string` to `StreamNodeData` interface
- Added `updateNodeParams` action to store (merges parameters, updates instanceName and constructorMode)
- Modified `addNode` to populate default parameter values from registry via `getComponent()` and set `constructorMode` to first available mode
- Wired `onNodeClick` (calls `selectNode(node.id)`) and `onPaneClick` (calls `selectNode(null)`) in `CanvasPanel.tsx`
- Installed 8 shadcn UI components: input, label, button, select, tooltip, separator, badge, scroll-area
- Installed `class-variance-authority` dependency required by shadcn badge/button

### Task 2: Create validation library and extend store tests (2a2c2a2)

- Created `gui/src/lib/validation.ts` with 4 exported functions:
  - `validateInt`: positive integer validation
  - `validateReal`: finite number validation
  - `validatePositiveReal`: positive finite number validation
  - `validateJuliaIdentifier`: Julia identifier pattern validation
- Created `gui/src/lib/__tests__/validation.test.ts` with 23 test cases covering all validation rules
- Extended `gui/src/store/__tests__/useStore.test.ts` with:
  - 5 tests for `updateNodeParams` (update params, merge params, rename, mode change, undo coverage)
  - 3 tests for `addNode` default population (defaults from registry, constructorMode, no defaults for required params)

## Verification

- `npx tsc --noEmit` exits 0
- `npx vitest run` passes all 61 tests (30 existing + 23 validation + 8 store)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing class-variance-authority dependency**
- **Found during:** Task 1 (shadcn install)
- **Issue:** shadcn badge.tsx and button.tsx import `class-variance-authority` which was not in package.json
- **Fix:** `npm install class-variance-authority`
- **Files modified:** gui/package.json, gui/package-lock.json

**2. [Rule 1 - Bug] TypeScript strict mode cast error on node.data**
- **Found during:** Task 1 (tsc --noEmit)
- **Issue:** ReactFlow Node.data is `Record<string, unknown>`, direct cast to `StreamNodeData` fails in strict mode
- **Fix:** Used `as unknown as StreamNodeData` double cast
- **Files modified:** gui/src/store/useStore.ts

## Known Stubs

None -- all data flows are fully wired.

## Self-Check: PASSED

- All 7 key files verified present on disk
- Both commits (222dd2b, 2a2c2a2) verified in git log

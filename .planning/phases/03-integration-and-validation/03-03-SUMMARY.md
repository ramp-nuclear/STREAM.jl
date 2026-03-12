---
phase: 03-integration-and-validation
plan: "03"
requirements-completed: [VAL-01, VAL-02, VAL-03]
subsystem: validation
tags: [julia, modelingtoolkit, validation, python-stream, reference-values, cross-validation]

# Dependency graph
requires:
  - phase: 03-integration-and-validation
    plan: "01"
    provides: "build_loop, solve_steady, steady_state_guess"
  - phase: 03-integration-and-validation
    plan: "02"
    provides: "build_loop_transient, solve_transient"
provides:
  - "test/generate_reference.py: Python STREAM reference value generator"
  - "test/runtests.jl: Phase 3 VAL-01/02/03 testset with hardcoded reference values"
  - "54 total tests green (25 Phase 1 + 9 Phase 2 + 20 Phase 3)"
  - "VAL-01: T_outlet and mdot within 1% of Python STREAM reference"
  - "VAL-02: Transient T_outlet rises after T_wall step change"
  - "VAL-03: Full test suite passes via Pkg.test()"
affects: []

# Tech tracking
tech-stack:
  added:
    - "Python STREAM FlowGraph+ChannelAndContacts API for cross-validation"
    - "HeatExchanger(outlet=T_inlet) as TempBC equivalent in Python STREAM"
  patterns:
    - "T_outlet_ref = 327.7894 K (54.64°C), mdot_ref = 0.609289 kg/s from Python STREAM"
    - "isapprox(T_out, T_outlet_ref; rtol=0.01) and isapprox(mdot, mdot_ref; rtol=0.01)"
    - "Transient VAL-02 uses T_wall step 373.15→393.15 K at t=10s over 60s simulation"

key-files:
  created:
    - "test/generate_reference.py"
  modified:
    - "test/runtests.jl (added VAL-01, VAL-02, VAL-03, SYS-01, SOLV-01 Phase 3 testsets)"

key-decisions:
  - "Python STREAM topology uses FlowGraph+ChannelAndContacts (not simple Channel) — required ChannelAndContacts with pressure_func=partial(pressure_diff, g=0) for exact parameter match"
  - "generate_reference.py uses HeatExchanger(outlet=T_inlet) to match Julia TempBC — both inject fixed T_inlet into closed-loop stream variable"
  - "T_outlet_ref = 327.7894 K and mdot_ref = 0.609289 kg/s obtained from Python STREAM and hardcoded in runtests.jl"
  - "VAL-02 uses T_wall step (not Q_wall step) to match transient solver implementation from plan 03-02"

# Metrics
duration: 15min
completed: 2026-03-12
---

# Phase 3 Plan 03: Validation and Reference Value Cross-Check Summary

**Python STREAM reference values (T_outlet=327.7894 K, mdot=0.609289 kg/s) hardcoded in runtests.jl; all 54 tests green with VAL-01 within 1%, VAL-02 transient rising, VAL-03 auto-suite confirmed**

## Performance

- **Duration:** ~15 min (prior session)
- **Completed:** 2026-03-12
- **Tasks:** 2 (+ checkpoint)
- **Files modified:** 2

## Accomplishments

- Created `test/generate_reference.py` using Python STREAM FlowGraph+ChannelAndContacts API with geometry exactly matching Julia `build_loop()` defaults
- Ran generate_reference.py and obtained T_outlet=327.7894 K (54.64°C) and mdot=0.609289 kg/s as Python STREAM reference values
- Hardcoded reference values in `test/runtests.jl` Phase 3 testset
- All 54 tests pass: 25 Phase 1 + 9 Phase 2 + 20 Phase 3 (SYS-01, SYS-02, SOLV-01, SOLV-02×2, VAL-01, VAL-02, VAL-03 + additional)
- VAL-01 isapprox passes at rtol=0.01 for both T_outlet and mdot
- VAL-02 transient T_outlet rises after T_wall step (318→331 K range)
- VAL-03 confirmed: `julia --project -e 'using Pkg; Pkg.test()'` exits successfully

## Task Commits

1. **Task 1: Create test/generate_reference.py** - `4c7c60c` (feat)
2. **Task 2: Hardcode VAL-01/02/03 tests + fix build_loop topology** - `2e5ed5c` (feat)

## Files Created/Modified

- `test/generate_reference.py` — Python STREAM reference value generator using FlowGraph+ChannelAndContacts API; produces T_outlet in Kelvin and mdot in kg/s for exact parameter match with Julia build_loop()
- `test/runtests.jl` — Phase 3 testset with SYS-01, SOLV-01, VAL-01, VAL-02, VAL-03 coverage and hardcoded reference values

## Decisions Made

1. **Python STREAM FlowGraph+ChannelAndContacts for reference**: Python STREAM does not have a simple `Channel` component matching Julia's exactly. The correct equivalent is `ChannelAndContacts` (computes Dittus-Boelter HTC and Darcy-Weisbach friction internally) inside a `FlowGraph` that handles the closed-loop topology and Kirchhoff matrix.

2. **HeatExchanger(outlet=T_inlet) as TempBC equivalent**: Python STREAM's `HeatExchanger` component with `outlet=T_inlet_C` resets the coolant temperature back to 40°C at the pump outlet — the exact functional equivalent of Julia's TempBC component that injects T_inlet into the stream before the channel.

3. **Reference values hardcoded (not loaded at test time)**: Python STREAM reference values are computed once by running generate_reference.py, then hardcoded in runtests.jl. This makes tests fully reproducible without requiring Python STREAM to be installed in the test environment.

4. **VAL-02 uses T_wall step**: The transient validation uses a T_wall step (373.15→393.15 K) rather than Q_wall step, because the Julia solve_transient implementation uses T_wall as the modifiable parameter (matches plan 03-02 decision).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] build_loop had extra Friction component (topology mismatch with Python STREAM)**
- **Found during:** Task 2 (writing VAL-01 test comparing against Python STREAM)
- **Issue:** The original `build_loop` included a separate `Friction` component (Pump → TempBC → Friction → Channel), while Python STREAM's `ChannelAndContacts` computes friction internally. This meant the Julia loop had additional friction pressure drop that Python STREAM did not have, making VAL-01 comparison fail.
- **Fix:** Removed the separate Friction component from build_loop and build_loop_transient (Pump → TempBC → Channel topology). Channel's internal Darcy-Weisbach term handles friction.
- **Files modified:** src/solvers.jl, test/runtests.jl
- **Committed in:** `2e5ed5c`

**2. [Rule 2 - Missing Critical] gravity term was not added to Channel for consistency**
- **Found during:** Task 2 (Python STREAM uses `pressure_func=partial(pressure_diff, g=0)`)
- **Fix:** Verified Channel's g_acc defaults to 0 (horizontal loop assumption), matching Python STREAM's `g=0` parameter. No code change needed.
- **Committed in:** N/A (already correct)

---

**Total deviations:** 1 auto-fixed (topology mismatch requiring Friction removal)
**Impact on plan:** The Friction removal was the key deviation — it aligned Julia build_loop topology with Python STREAM ChannelAndContacts topology, enabling the VAL-01 1% comparison to pass.

## Test Results

```
Test Summary:        | Pass  Total  Time
STREAM Phase 1 Tests |   25     25  4.5s
STREAM Phase 2 Tests |    9      9  32.2s
STREAM Phase 3 Tests |   20     20  30.9s
     Testing STREAM tests passed
```

Final validation: `julia --project -e "using Pkg; Pkg.test()"` exits 0.

## Reference Values

| Quantity | Python STREAM | Julia STREAM | Difference |
|----------|--------------|--------------|------------|
| T_outlet | 327.7894 K (54.64°C) | ~327.7 K | <1% |
| mdot | 0.609289 kg/s | ~0.609 kg/s | <1% |

## User Setup Required

None — all tests run automatically via `julia --project -e "using Pkg; Pkg.test()"`.

---
*Phase: 03-integration-and-validation*
*Completed: 2026-03-12*

## Self-Check: PASSED

- FOUND: test/generate_reference.py
- FOUND: test/runtests.jl (with VAL-01, VAL-02, VAL-03 testsets)
- FOUND: commit 4c7c60c (feat(03-03): create test/generate_reference.py)
- FOUND: commit 2e5ed5c (feat(03-03): remove extra Friction component, hardcode VAL-01/02/03 tests)
- TEST RESULT: 54/54 tests pass (0 failures, 0 errors)

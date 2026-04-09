---
status: passed
phase: 46-callable-control-reactivity-reactivity-controller
started: 2026-04-04
updated: 2026-04-04
---

## Tests

### 1. Callable PointKinetics — basic construction
expected: `unknowns: 7` and `has rho_c_fn param: true` — callable constructor compiles with 7 unknowns and registers the MTK callable parameter.
result: pass

### 2. Scalar PointKinetics still works (Phase 45 unchanged)
expected: `unknowns: 7` with no errors — scalar constructor is untouched by Phase 46.
result: pass

### 3. ReactivityController — default and custom construction
expected: default worth=0.0, state=:NORMAL, log=[(:NORMAL, 0.0)]; custom fn worth=0.003 at t=3; callable form matches worth.
result: pass

### 4. change_state — transition logging and no-op behavior
expected: no log entry on low-power call; state transitions to :SCRAM at t=5.0 with log=[(:NORMAL, 0.0), (:SCRAM, 5.0)]; abort_states contains :SCRAM.
result: pass

### 5. End-to-end solve with ReactivityController (prompt-jump validation)
expected: step insertion δρ=0.002 at t=1s; numerical P jump within 1% of prompt-jump formula β/(β−δρ)·P0.
result: pass

### 6. State-aware reactivity — worth sees state and t_state
expected: worth=0.0 in :NORMAL; after change_state at t=2.0 → :RAMP; worth(ctrl, 2.5)=0.0005 (ramps from t_state, not t=0).
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0

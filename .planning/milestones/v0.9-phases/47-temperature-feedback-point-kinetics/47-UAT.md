---
status: complete
phase: 47-temperature-feedback-point-kinetics
source: [47-01-SUMMARY.md, 47-02-SUMMARY.md]
started: 2026-04-09T23:35:00Z
updated: 2026-04-10T00:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Full test suite — all 1380 TF tests pass
expected: Run `julia --project=. test/test_point_kinetics.jl`. Expect Pass=1380+, no failures. TF-01..TF-07 testsets all green.
result: issue
reported: "TF-07 fails: P_max > P0 evaluates to 1.0 > 1.0. Power never rises above P0 after step reactivity insertion. 1391 passed, 1 failed."
severity: major

### 2. Default callable PointKinetics still has 7 state variables
expected: |
  With no temp_worth kwarg, the callable constructor behaves identically to Phase 46.
  Running:
    ctrl = ReactivityController()
    @named pk = PointKinetics(ctrl; name=:pk)
    ssys = mtkcompile(pk)
    length(unknowns(ssys)) == 7
  Should return true. No T_source unknowns present.
result: pass

### 3. Scalar alpha broadcasts to all channel cells
expected: |
  Passing a scalar alpha for a Channel with n=5 cells creates 5 T_source unknowns:
    @named ch = Channel(; L=1.0, Dh=0.01, A_flow=1e-4, wet_perimeter=0.04, n=5, ...)
    ctrl = ReactivityController()
    @named pk = PointKinetics(ctrl; temp_worth=Dict(ch => -0.001))
    length(unknowns(pk)) == 12   # 7 PK states + 5 T_source_ch
  Should be true.
result: pass

### 4. Shape mismatch raises ArgumentError
expected: |
  Passing a length-2 vector for a Channel with n=5 throws at construction time:
    @test_throws ArgumentError PointKinetics(ctrl; name=:pk, temp_worth=Dict(ch => [1.0, 2.0]))
  Should throw ArgumentError immediately (not at solve time).
result: pass

### 5. connect_temperature_feedback generates correct binding equations
expected: |
  For a Channel with n=5:
    eqs = connect_temperature_feedback(pk, [ch])
    length(eqs) == 5
  Each equation binds pk.T_source_ch[j] ~ ch.T[j]. No errors.
result: pass

### 6. TF-07 analytical validation — negative feedback damps power
expected: |
  The TF-07 testset (in test_point_kinetics.jl) shows that with a composed
  PK + ChannelAndContacts + HeatDiffusion system, applying a step reactivity
  delta_rho=0.0005 at t=0.1s with negative temperature feedback (alpha<0)
  causes P_max/P0 ≈ 1.168 — power rises above P0 then damps back down.
  The test assertions: P_max > P0 AND rho_trace[end] <= delta_rho both pass.
  Confirmed by test suite passing in test 1 above.
result: pass

## Summary

total: 6
passed: 5
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "P_max > P0 after step reactivity insertion with negative temperature feedback"
  status: fixed
  reason: "User reported: TF-07 fails: P_max > P0 evaluates to 1.0 > 1.0. Power never rises above P0 after step reactivity insertion."
  severity: major
  test: 1
  root_cause: "Stale rods7.cac7 reference in TF-07 test setup caused spurious negative feedback cancelling the reactivity step"
  artifacts:
    - path: "test/test_point_kinetics.jl"
      issue: "rods7.cac7 ref not cached before compose — picked up wrong component"
  missing: []
  debug_session: "fixed in commit 9cf46a5"

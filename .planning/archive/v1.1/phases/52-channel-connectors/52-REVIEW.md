---
phase: 52-channel-connectors
reviewed: 2026-05-06T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - src/connectors.jl
  - src/STREAM.jl
  - test/test_connectors.jl
findings:
  critical: 0
  warning: 2
  info: 5
  total: 7
status: issues_found
---

# Phase 52: Code Review Report

**Reviewed:** 2026-05-06T00:00:00Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 52 introduces two new MTK acausal connector types (`WallPort`,
`HeatFluxPort`) plus an export-line update and a substantial expansion of
`test/test_connectors.jl`. The connector source itself is small, surgical, and
mirrors the established `FlowPort` / `ThermalPort` idiom — no security
concerns, no functional bugs in `src/connectors.jl`, and the export rule
(single-source in `STREAM.jl`) is honored.

The findings are concentrated in `test/test_connectors.jl`:

- **Two warnings** flag a fragile-default pitfall in `_StubRecipient` that
  will misbehave silently if a caller passes a `BitVector` of the wrong
  length, and a hidden coupling between the stub's self-anchor numeric
  literal (`300.0`) and the connector's IC default that breaks the adiabatic
  test if `WallPort`'s default `T_wall` is ever changed.
- **Five info items** cover untested code paths (`drive_right` plumbed but
  never exercised), redundant collection of a symbolic array, an
  over-restrictive `BitVector` type annotation that breaks on plain
  `Vector{Bool}`, a redundant `Q_flow` IC default on a Flow variable, and a
  testset naming collision with the legacy FlowPort/ThermalPort suite.

No findings in `src/STREAM.jl`. No critical/security findings overall.

## Warnings

### WR-01: `_StubRecipient` `drive_*` defaults silently mis-size when caller passes wrong-length `BitVector`

**File:** `test/test_connectors.jl:33-35`
**Issue:** The stub signature is

```julia
function _StubRecipient(; name, n::Int, port_type::Symbol=:wall,
                        drive_left::BitVector=falses(n),
                        drive_right::BitVector=falses(n))
```

The defaults work, but the function body indexes `drive_left[i]` and
`drive_right[i]` for `i in 1:n` with no length check. If a future test
passes `drive_left=trues(2)` while constructing with `n=3` (or vice-versa),
the code will throw a `BoundsError` deep inside the equation-construction
loop with no useful context, or worse — for `drive_left=BitVector([true])`
and `n=2` it would fail on `i=2` after already pushing equations for `i=1`,
leaving the test in a half-constructed state that is hard to debug. Today's
two test sites both pass `n=2` paired with `trues(2)`, so this is latent,
but the contract is fragile.
**Fix:** Add an explicit precondition in the helper:

```julia
function _StubRecipient(; name, n::Int, port_type::Symbol=:wall,
                        drive_left::BitVector=falses(n),
                        drive_right::BitVector=falses(n))
    @assert length(drive_left)  == n "drive_left must have length n=$n"
    @assert length(drive_right) == n "drive_right must have length n=$n"
    ...
```

### WR-02: Hidden coupling between self-anchor literal `300.0` and `WallPort`'s `T_wall` IC default breaks the adiabatic test silently

**File:** `test/test_connectors.jl:55, 62` (and conceptually `src/connectors.jl:45`)
**Issue:** The unconnected/self-anchored branch hard-codes
`thermal_left[i].T_wall ~ 300.0` and `thermal_right[i].T_wall ~ 300.0`. The
adiabatic test asserts `T[i, end] ≈ T[i, 1]` with `rtol=1e-8`, where `T[i]`
has IC `300.0`. The test only passes because the self-anchored `T_wall` is
exactly `300.0`, matching the stub's `T` IC, so `(T_wall - T) = 0` and
`Q_flow = h*A*0 = 0` even before the `h=0` IC takes effect. If
`WallPort`'s default `T_wall` is ever changed (e.g., to `280.0` or
`273.15`), and a future maintainer updates the stub's self-anchor to match
without also updating `T[i]`'s IC, the adiabatic test would still pass
because `h=0` zeros the product anyway — but the test would no longer be
exercising what it claims to (`Dt(T)=0` from `Q_flow=0`, not from
`(T_wall-T)=0`). Worse, if someone "fixes" the stub by removing the
self-anchor line for `T_wall` (since `Q_flow=0` already, `T_wall` value
seems irrelevant), MTK will report the system as underdetermined: the
across var `T_wall` has no equation. This is exactly the failure mode the
plan-deviation note (lines 18-31) warns about, but the literal `300.0`
buries the dependency.
**Fix:** Either reference the connector default symbolically, or add a
comment that pins the rationale at the literal:

```julia
# Self-anchor uses 300.0 to match WallPort's default T_wall IC (src/connectors.jl:45).
# T_wall must be anchored even when h=0 — MTK only auto-zeros Q_flow (Flow rule),
# not the across vars. Changing this requires updating the connector default in lockstep.
push!(eqs, thermal_left[i].T_wall ~ 300.0)
push!(eqs, thermal_left[i].h      ~ 0.0)
```

A stricter fix is to expose the literal as a stub kwarg
(`T_wall_anchor::Float64=300.0`) so callers can vary it, but the comment
alone closes the maintenance hazard.

## Info

### IN-01: `drive_right` plumbed through but never exercised

**File:** `test/test_connectors.jl:35, 58-64, 71-75`
**Issue:** The `_StubRecipient` helper accepts a `drive_right::BitVector`
kwarg and contains a parallel `if drive_right[i] / else` branch in both the
`:wall` and `:flux` arms (lines 58-64, 71-75). No callsite in the test
suite passes `drive_right` — every driven testset uses
`drive_left=trues(2)` only. This means roughly 25% of the helper's
equation-construction logic is unverified by Phase 52 tests. Untested code
in test fixtures hides bugs that surface only later, when Phase 54 (which
the comment cites as the consumer pattern) hits the same code path.
**Fix:** Add one driven-right testset that mirrors the
"WallPort driven case" but with `drive_right=trues(2)` and a second
`_StubWallDriver` connected to `stub.thermal_right1` / `stub.thermal_right2`,
or — if the symmetry is truly trivial — drop `drive_right` from the helper
and add it back when the right-side driver case is actually needed.

### IN-02: `BitVector` type annotation rejects plain `Vector{Bool}`

**File:** `test/test_connectors.jl:34-35`
**Issue:** `drive_left::BitVector` and `drive_right::BitVector` reject
`Vector{Bool}`, even though both are valid boolean indexable collections.
A future maintainer writing `drive_left=[true, false]` (the natural Julia
literal) gets a `MethodError` rather than the obvious behavior. The current
testsets all use `trues(2)` / `falses(n)` which return `BitVector`, so
this is latent.
**Fix:** Loosen to `AbstractVector{Bool}`:

```julia
function _StubRecipient(; name, n::Int, port_type::Symbol=:wall,
                        drive_left::AbstractVector{Bool}=falses(n),
                        drive_right::AbstractVector{Bool}=falses(n))
```

### IN-03: Redundant `[collect(T)...]` splat on a symbolic array variable

**File:** `test/test_connectors.jl:86`
**Issue:** `System(eqs, t, [collect(T)...], []; name=name)` first calls
`collect(T)` which materializes the symbolic array as a `Vector{Num}`,
then splats it into a fresh `Vector{Num}`. The intermediate splat-and-rebuild
is a no-op; `collect(T)` already produces the desired vector.
**Fix:**

```julia
sys = System(eqs, t, collect(T), []; name=name)
```

### IN-04: `Q_flow=0.0` IC default on a Flow variable is redundant and misleading

**File:** `src/connectors.jl:45, 49-50, 73, 76-77`
**Issue:** Both `WallPort` and `HeatFluxPort` declare `Q_flow=0.0` as both
a kwarg default and an MTK initial condition. `Q_flow` is a Flow variable,
which means MTK's connect rule pins it algebraically (sum across a
connection set = 0; auto-zeroed when unconnected). The IC on a Flow
variable is consumed by the solver only as an initial guess and is not
authoritative — the connect rule overrides it at every step. Carrying it
in the public signature suggests a knob that has no real effect, and
diverges from `ThermalPort` (line 17) which does the same thing — so
this is a pre-existing pattern, but worth flagging now that the connector
inventory is doubling.
**Fix:** Either drop the kwarg entirely (`@connector function WallPort(; name, T_wall=300.0, h=0.0)`) or add a docstring note that the value is purely an initial guess for the DAE consistency step and has no steady-state effect. The "drop" path is cleaner; the "document" path keeps API symmetry with `ThermalPort`.

### IN-05: Testset name collision with legacy FlowPort/ThermalPort suite

**File:** `test/test_connectors.jl:121-186 vs 192-264`
**Issue:** The new testsets use the same `CONN-01:` / `CONN-02:` prefixes
as the legacy FlowPort / ThermalPort testsets (lines 121, 130, 135, 145
vs 192, 200, 205, 214, 223). The disambiguation comment at lines 189-191
documents the intent, but full testset names like
`"CONN-01: WallPort instantiation"` vs `"CONN-01: FlowPort instantiation"`
are still distinct strings, so `Test.jl` won't merge them. However, any
external dashboard or grep that pattern-matches on `^CONN-01:` will
collapse the two phases' coverage, making it harder to triage which
connector is failing. The CONTEXT note (D-11) said new tests should
disambiguate; the suffix does, but the prefix re-use is still suboptimal.
**Fix:** Switch the new tests to a v1.1-prefixed test ID (e.g.,
`v1.1-CONN-01: WallPort instantiation`) matching the comment header on
line 189, or simply collapse to unique IDs (`CONN-W01`, `CONN-W02`, ...,
`CONN-F01`, `CONN-F02`, ...).

---

_Reviewed: 2026-05-06T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

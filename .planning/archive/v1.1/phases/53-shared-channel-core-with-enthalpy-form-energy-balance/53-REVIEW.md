---
phase: 53-shared-channel-core-with-enthalpy-form-energy-balance
reviewed: 2026-05-07T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - src/components/channel.jl
  - src/components/thermal_channel.jl
  - test/data/stage2_reference.py
  - test/runtests.jl
  - test/test_channel_core.jl
findings:
  critical: 1
  warning: 7
  info: 6
  total: 14
status: issues_found
---

# Phase 53: Code Review Report

**Reviewed:** 2026-05-07
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 53 introduced a private `_channel_core(...)` helper carrying the new
enthalpy-form (face-averaged-cp) energy balance and rebuilt the verification
test suite around four Gates (G1..G4). The execution is mostly clean, but
adversarial inspection surfaces one BLOCKER and several WARNING / INFO items
worth addressing:

- **BLOCKER:** the legacy `Channel(...)` constructor still emits the *old*
  constant-cp energy balance — Phase 53's stated goal of unifying the family
  on the enthalpy form is therefore only partially achieved; `Channel` is now
  numerically inconsistent with `ChannelAndContacts` and `ChannelHeatFlux`.
  Worse, since `_channel_base_eqs` was deleted, anyone reading the codebase
  has no audit trail explaining why `Channel`'s body looks different from
  the helper.
- **WARNINGS:** several scope / staleness issues — e.g. the `Channel`
  docstring still references `_channel_base_eqs`; `T_ONB[i]` in `Channel`
  drops the `q_wall[i]` term that the cell would actually carry on
  reverse-flow; the Stage-2 reference Python script imports a `pair_mean_1d`
  it then never uses; the `try/catch` rtol-relaxation pattern in G3/G3b
  silently double-counts test results; etc.
- **INFO:** dead `T_ONB` formula divergence between the three variants,
  redundant scratch variables, copy-paste inertia.

No security vulnerabilities are present. The Python helper does not call
`eval`/`exec`/`subprocess` — only `os.path.expanduser` and `sys.path.insert`,
both safe under the documented developer workflow.

## Critical Issues

### CR-01 [BLOCKER] `Channel(...)` still uses constant-cp energy balance — diverges from `_channel_core`

**File:** `src/components/channel.jl:77-84`
**Issue:** Phase 53's stated objective (per the phase plan and CONTEXT) is
to unify the channel family on a single enthalpy-form energy balance. The
new `_channel_core` (lines 253-259) implements
`(|mdot|*cp_face*(T_up - T[i]) + ...) / (rho*cp(T[i])*A*dz)` with
`cp_face = (cp_water(T_up) + cp_water(T[i]))/2`, but the legacy
`Channel(...)` constructor in this very same file *still* emits the old
constant-cp form
`(|mdot|*cp_water(T[i])*(T_up - T[i]) + ...) / (rho*cp(T[i])*A*dz)`
(lines 81-83). The two cp values cancel only in the constant-cp limit
(NRG-03), so for any non-trivial temperature swing `Channel` and
`ChannelAndContacts` / `ChannelHeatFlux` now disagree — and the disagreement
silently grows with cell-to-cell ΔT.

This is a correctness defect for any user who picks `Channel` (an exported
public API; see `src/STREAM.jl:29`) over the contacts/heat-flux variants:
they get a quietly-deprecated discretization while the docstring (and the
phase summary) advertises a unified family.

Two reasonable fixes; either one is acceptable:

**Fix (a) — finish the migration in `Channel`:**
```julia
# replace lines 77-84 with the same enthalpy form _channel_core uses
cp_face = (cp_water(T_up) + cp_water(T[i])) / 2
push!(
    eqs,
    Dt(T[i]) ~
    (
        abs(port_in.mdot) * cp_face * (T_up - T[i]) +
        h_tc[i] * sum(geometry.heated_parts) * dz * (thermal.T - T[i])
    ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz),
)
```

**Fix (b) — call `_channel_core` from `Channel` (preferred, matches the
spirit of "shared core"):** declare the same observables `Channel` will need,
build `q_left_expr[i] = h_tc[i] * geometry.heated_parts[1] * dz * (thermal.T - T[i])`
(and the right counterpart), then splice `core.eqs` and `core.obs` exactly
as `_StubChannelCore` does in `test/test_channel_core.jl:138-151`.

Phase 54 was originally planned to perform this migration; if the team
elects to keep that scope split, then at minimum CR-01 should be downgraded
to a *documented* known divergence — but the docstring and the phase
SUMMARY currently claim the unification is complete, so leaving the code as
written is misleading.

## Warnings

### WR-01 Stale docstring/comment references `_channel_base_eqs` after deletion

**File:** `src/components/channel.jl:6-7` (Channel docstring header) and
`src/components/channel.jl:148-160` (block comment introducing the new helper)
**Issue:** Commit `68ade99` deleted `_channel_base_eqs`, but several pieces
of in-file prose still refer to it:
- `channel.jl:6` — the `Channel` docstring used to mention the old helper;
  it now silently advertises the constant-cp legacy path without saying so.
- `channel.jl:153-155` — the block comment says "Phase 54 will migrate
  Channel, ChannelAndContacts, and ChannelHeatFlux onto `_channel_core`;
  until then those variants carry inlined per-variant equation blocks
  (constant-cp form) instead of calling a shared helper." This is correct
  for `Channel` but **wrong** for `ChannelAndContacts` and `ChannelHeatFlux`,
  which were *already* inlined in this same Phase 53 (Wave 4 commits
  `c9da9c1`, `5bbc522`) — and they no longer use the constant-cp form
  there. The comment is misleading: it implies a future state that is
  partly already true and partly false.

**Fix:** Rewrite the block comment to reflect the current state of the
three variants, and either (a) add a "Phase 54 TODO" inline marker on
`Channel`'s energy-balance lines, or (b) execute fix CR-01 above and
delete the comment entirely.

### WR-02 `T_ONB` formula divergence between variants

**File:** `src/components/channel.jl:286-289`,
`src/components/thermal_channel.jl:227-228, 386-387`
**Issue:** The three variants compute the q-density input to
`_bergles_rohsenow_dT_ONB` differently:
- `_channel_core`: `q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)` (channel.jl:288)
- `ChannelAndContacts`: `q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)` (thermal_channel.jl:227)
- `ChannelHeatFlux`: `q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)` (thermal_channel.jl:386)

For the contacts variant `q_wall[i] = thermal_left[i].Q_flow + thermal_right[i].Q_flow`,
which is *signed*: it can transiently be negative during the solver's
Newton iteration (cold wall / hot fluid, or wrong-sign initial guess), and
`(negative)^(non-integer exponent)` raises a `DomainError` from
`_bergles_rohsenow_dT_ONB` (the formula is `0.556 * (q_spl/(1082*p^1.156))^(0.463*p^0.0234)`).
The same guard is *applied inside the SCB block* (thermal_channel.jl:156:
`q_spl_i = max(h_spl_i * (T_w_i - T[i]), 0.0)`), but **not** in the
top-level observable equations at lines 227-228 nor in CHF at 386-387.
`_channel_core` inherits the same hazard via `q_density_i` (channel.jl:288),
since `q_left_expr[i] + q_right_expr[i]` can be negative for an initial
guess that puts the wall colder than the fluid.

This is also inconsistent with the existing comment at thermal_channel.jl:153-155
which acknowledges the DomainError risk inside the SCB closure — the same
risk in the *observable* path is unguarded.

**Fix:** Apply the same `max(..., 0.0)` guard everywhere
`_bergles_rohsenow_dT_ONB` is called from an observed equation:
```julia
# in _channel_core (channel.jl:288)
q_density_i = max((q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz), 0.0)

# in ChannelAndContacts (thermal_channel.jl:227)
q_spl_i = max(q_wall[i] / (sum(geometry.heated_parts) * dz), 0.0)

# in ChannelHeatFlux (thermal_channel.jl:386)
q_spl_i = max(q_wall[i] / (sum(geometry.heated_parts) * dz), 0.0)
```

### WR-03 G3 / G3b `try/catch` around `@test` produces double-counted results

**File:** `test/test_channel_core.jl:472-479` and `541-549`
**Issue:** The "strict-then-relax" pattern is:
```julia
try
    @test isapprox(dT_fwd, dT_rev; rtol=1e-12)
    passed_strict = true
catch err
    @warn "G3 rtol=1e-12 failed; relaxing to rtol=1e-9" dT_fwd dT_rev
    @test isapprox(dT_fwd, dT_rev; rtol=1e-9)
end
```
This relies on `@test` *throwing* when it fails. In Julia's `Test`
framework, however, `@test` does **not** throw on failure by default —
it records the failure and returns. In the default test runner the
`catch err` branch will never execute, so the relaxed
fallback `@test` is dead code, and the strict `@test` will always
report whatever it found (pass or fail). When a failure occurs, the
intended behaviour (re-running with rtol=1e-9 and counting *only* that
relaxed result) does not happen — instead, the test session shows a
strict failure and never records the relaxed result.

If the project ever switches to `@testset` with `failfast=true` or to
`@test_throws`, the same code would emit *both* a recorded failure and
a recorded extra `@test`, double-counting in the testset summary.

**Fix:** Use `@test isapprox(...; rtol=1e-9)` (the realistic tolerance)
or compute the result first and dispatch:
```julia
strict = isapprox(dT_fwd, dT_rev; rtol=1e-12)
if !strict
    @warn "G3 strict tolerance missed; falling back to 1e-9" dT_fwd dT_rev
end
@test strict || isapprox(dT_fwd, dT_rev; rtol=1e-9)
```
The same pattern appears at lines 541-549 in G3b and needs the same fix.

### WR-04 G3 reverse-flow comparison reads the wrong symbol

**File:** `test/test_channel_core.jl:463-464`
**Issue:**
```julia
T_out_fwd = sol_fwd[ssys_fwd.stub.T_out]
T_out_rev = sol_rev[ssys_rev.stub.T[1]]  # T[1] is the only cell
```
The intent (per the comment at line 464 and the testset header at
line 421) is "for n=1, T[1] is the only cell — both forward and reverse
should give the same single-cell temperature." But the forward branch
reads `T_out` (which is `T[n] = T[1]` for n=1, OK) while the reverse
branch reads `T[1]` directly. For n=1 these alias to the same MTK
unknown, so the test passes — but the asymmetry obscures a real
question: in reverse flow, is `T_out` (defined as `T[n]`) still the
*outlet*? In reverse flow, the outlet of the channel is `port_in`, not
`port_out`, so `T_out := T[n]` is conceptually upstream, not
downstream. The single-cell test does not exercise this distinction
because n=1 collapses the two — but this asymmetric read *invites* a
bug if anyone copies the pattern to a multi-cell test in the future.

**Fix:** Read the same symbol in both branches:
```julia
T_out_fwd = sol_fwd[ssys_fwd.stub.T[1]]
T_out_rev = sol_rev[ssys_rev.stub.T[1]]
```
And consider documenting (in `_channel_core`'s docstring) that
`T_out := T[n]` always refers to the cell at the high-index end, *not*
the hydraulic outlet, which depends on flow direction.

### WR-05 G2 `pair_mean_1d` import is dragged into the test fixture but never used

**File:** `test/data/stage2_reference.py:115-124, 138-173`
**Issue:** `_bootstrap_python_stream` imports `pair_mean_1d` and threads
it through `_converged_T(cp_K, pair_mean_1d, ...)`. The function body
(lines 152-173) **never calls** `pair_mean_1d` — instead it inlines
`c_face = 0.5 * (cp_up + cp_self)` directly. The `pair_mean_1d`
parameter is verified in `_verify_pair_mean(...)` and then carried
unused.

The script's docstring (lines 23-27) and the file header
(lines 6-9) both claim "Stage-2 parity uses Python STREAM's exact
`pair_mean_1d` averaging on Python STREAM's exact
`light_water.specific_heat` correlation." That is now *only half true*:
the cp correlation comes from Python STREAM (or the byte-for-byte
fallback), but the pair-mean averaging is an inlined Julia-mirror, not
the Python-STREAM library function. The reference array
`STAGE2_REFERENCE_T` is therefore not a faithful Python-STREAM parity
reference for the *averaging step* — it would silently agree with a
different averaging implementation if Python STREAM ever changed
`pair_mean_1d` (e.g. weighted vs. arithmetic mean).

**Fix:** Either (a) actually call `pair_mean_1d` to compute the
face-cp vector — that requires reformulating the iteration so the
whole `cp` array is built first and then averaged, mirroring Python
STREAM's vectorized form — or (b) drop the parameter and rewrite the
docstring to say "Stage-2 parity uses an inlined arithmetic average
*equivalent to* Python STREAM's pair_mean_1d."

### WR-06 `_StubChannelCore` is silently dependent on `STREAM` internals

**File:** `test/test_channel_core.jl:139-145`
**Issue:** `_StubChannelCore` calls `STREAM._channel_core(...)` — a
private (underscore-prefixed) helper. Per CLAUDE.md "Internal helpers
are prefixed with `_` and not exported... [the prefix] signals that
these functions may change without notice." The test file is therefore
coupled to a private API by design (acceptable for a phase-internal
gate test) but the coupling has *no comment in the test* explaining
why this is OK or what to do when the signature drifts. The G2 / G3 /
G3b / G4 testsets will all break at once if `_channel_core`'s argument
list changes. The plan summary mentions Phase 54 will migrate the
variants onto `_channel_core` — that wave will likely refactor the
signature, and these tests will need updating.

**Fix:** Add a one-line comment near the `STREAM._channel_core(...)`
call documenting the coupling and what to do when the signature
changes (e.g. "If `_channel_core` keyword args change, update both
this stub and the variant call sites in `src/components/`.").

### WR-07 Re-defining `Channel` as a generic function shadows `Base.Channel` for callers

**File:** `src/components/channel.jl:3-4`
```julia
# Declare as new generic functions independent of Base
function Channel end
```
**Issue:** `STREAM` exports `Channel` (`src/STREAM.jl:29`). Any user
script that does `using STREAM` and `using Base` (implicit) will see a
name collision: STREAM's `Channel` overrides `Base.Channel`
(concurrency primitive). The test file at `test/test_channel_core.jl:27`
already documents this with `import STREAM: Channel  # disambiguate
from Base.Channel`, confirming the collision is real. This is
established behaviour (existed pre-Phase-53), but Phase 53 did not
take the opportunity to rename or to document it in the public
docstring. New users who come to STREAM through `using STREAM` will
trip over this when trying to call `Channel(...)` (the concurrency
primitive) or `Channel{T}(buf)` (typed channel construction).

**Fix:** Add a note to the `Channel` docstring (channel.jl:6-25)
mentioning the `Base.Channel` shadowing and the disambiguation idiom,
and consider scheduling a rename (e.g. `FlowChannel`) in a future
breaking-change phase.

## Info

### IN-01 `Channel`'s `vars` block declares unused names `Re`, `Nu`, `h_tc`, `v`, `q_wall`, `dp` as `@variables` and as both unknowns and observable LHS

**File:** `src/components/channel.jl:46-57`
**Issue:** Compared to the new `_channel_core` (which keeps Re, Pe,
v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right as observables
only — see channel.jl:188), the legacy `Channel` constructor declares
all of Re, Nu, h_tc, v, q_wall, dp, P, T_out, dP as `@variables` and
then writes equations for them as full unknowns (lines 86-91, 100-105,
124-126). This is the v1.0 pattern, kept intentionally for
constant-cp parity, but it now duplicates work `_channel_core`
already factors. After CR-01 (migrate `Channel` to call
`_channel_core`), most of these declarations should go away.

**Fix:** Resolve as part of CR-01.

### IN-02 `Re_i_for_friction` recomputed twice per cell in `_channel_core`

**File:** `src/components/channel.jl:263, 272-273`
**Issue:** `Re_i_for_friction` is computed at line 263 and then used
at lines 264 (friction), 272 (`Re[i] ~ Re_i_for_friction`) and 273
(`Pe[i] ~ Re_i_for_friction * Pr_i`). This is fine — but the
expression `abs(port_in.mdot) * Dh / (A * mu_water(T[i]))` is also
inlined at line 263 (line 263) directly instead of reusing a single
local. Symbolics will likely CSE this, but for readability and
audit-friendliness consider `Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))`
once and using `Re_i` everywhere (matches the convention in
ChannelAndContacts / ChannelHeatFlux at thermal_channel.jl:113, 144,
203 etc.).

**Fix:** Cosmetic; rename `Re_i_for_friction` to `Re_i` (one symbol,
re-used).

### IN-03 G2 `if isempty(STAGE2_REFERENCE_T)` branch is dead

**File:** `test/test_channel_core.jl:368-371`
**Issue:** `STAGE2_REFERENCE_T` is declared at top-of-file (line 81)
as `Float64[319.155..., 325.159..., ...]` — a length-5 non-empty
array. The `if isempty(...)` branch at line 368 cannot trigger.
It was useful while Wave 0 had `STAGE2_REFERENCE_T = Float64[]` but
Wave 0 captured real values; the placeholder code is now dead.

**Fix:** Remove the `if isempty(...) ... else ... end` and inline the
`else` body. Keep the `@assert length(STAGE2_REFERENCE_T) == STAGE2_N`
defensive check.

### IN-04 G3 `passed_strict` is set but never read

**File:** `test/test_channel_core.jl:472, 478`
**Issue:** `passed_strict = false` is initialized at line 472 and set
to `true` inside the try block at line 475, but never inspected. The
identical pattern in G3b at lines 540-549 *also* sets `passed_strict`
without reading it. Dead state.

**Fix:** Remove `passed_strict` lines from both G3 and G3b. (See also
WR-03; the `try/catch` itself is the deeper problem.)

### IN-05 `_StubChannelCore` redundantly declares `Pe(t)` but the v1.0 parity gates do not exercise Peclet-number paths

**File:** `test/test_channel_core.jl:121-128`
**Issue:** `_StubChannelCore` declares `Pe(t)`, `T_sat(t)`, `T_ONB(t)`,
`q_wall_left(t)`, `q_wall_right(t)` as `@variables`. None of the four
Gate testsets (G1-G4) ever read these symbols from the solution. They
exist only to satisfy `_channel_core`'s required argument list. This
is fine for a structural existence test, but G4 ("Branch-coverage
matrix") could be strengthened by spot-checking at least one of these
observables in each row of `coverage_rows` — otherwise an observable
LHS could become silently broken (e.g., `T_ONB[i] ~ NaN`) without any
gate failing.

**Fix:** In G4, after `solve_steady`, add a smoke check like
`@test all(isfinite(sol[ssys.stub.T_ONB[i]]) for i in 1:n)` and
similarly for `T_sat`, `Pe`, `q_wall`.

### IN-06 `stage2_reference.py` `_pair_mean_1d_pure(a, prepend)` ignores `a`'s last cell when used by Python STREAM's prepend pattern

**File:** `test/data/stage2_reference.py:89-101`
**Issue:** The pure-Python implementation matches the docstring
description (`res[0] = (prepend + a[0]) / 2`, interior faces are
`(a[i-1] + a[i])/2`), but `a[-1]` (the last cell's value) never enters
`res` — only `a[0..n-2]` and `prepend` are read. This is faithful to
Python STREAM's actual `pair_mean_1d(prepend=cin)` behavior (per the
docstring at lines 89-95), but it's worth flagging that the function
returns a length-n vector that *omits* the downstream face — the
energy balance has to handle the cell-n outlet face separately. As
WR-05 notes, this function is never actually called in the converged-
T solve, so the issue is academic until WR-05 is fixed; but if WR-05
*is* fixed by routing through `pair_mean_1d`, then the cell-n outlet
face in the Julia code (which `_channel_core` *does* compute, via
the boundary `T_inlet_rev` for reverse flow at i=n) needs an
analogous treatment in the Python reference, or the parity assertion
will fail for the last cell.

**Fix:** Resolve only if/when WR-05 is addressed by routing through
`pair_mean_1d`.

---

_Reviewed: 2026-05-07_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

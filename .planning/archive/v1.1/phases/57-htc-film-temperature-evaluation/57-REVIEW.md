---
phase: 57-htc-film-temperature-evaluation
reviewed: 2026-05-08T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - src/components/channels.jl
  - src/physical_models/htc/correlations.jl
findings:
  critical: 1
  warning: 1
  info: 3
  total: 5
status: issues_found
---

# Phase 57: Code Review Report

**Reviewed:** 2026-05-08
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

The phase moves the HTC pipeline (Re, Pr, leading `k` outside `Nu`) to film-T
evaluation in three sites inside `ChannelAndContacts`: SPL branch (~681), SCB
branch (~689), and `variant_obs` `Nu[i]` observable (~770). Friction Re,
`_channel_core` diagnostic Pr_i, and natural-convection `nu_i`/`Gr_i` are
intended to remain at bulk per Python STREAM convention, and a long comment
block (lines 651-677) explicitly documents that intent.

The implementation contradicts its own stated invariant in one place: the
`variant_obs` `Re_i` local variable was rebound to film-T evaluation, but
that same `Re_i` is reused in the denominator of `Gr_over_Re2[i]` immediately
below. The result is `Gr(bulk) / Re(film)^2`, which is exactly what the
comment block at lines 661-666 says NOT to do. This is the headline bug.

A second behavior change rides along the SCB branch refactor: `Re_i` (now
film-T) is passed as the third argument to `scb_correction(T_w_i, T_sat_i,
Re_i)` at lines 702 and 704. The phase plan describes moving the htc_correlation
Re/Pr/leading-k inputs to film-T, but does not call out moving the Re argument
of `scb_correction` to film-T. Whether intended or a ripple effect, it deserves
explicit acknowledgement.

`correlations.jl` changes are docstring-only and look fine.

## Critical Issues

### CR-01: `Gr_over_Re2[i]` denominator now uses film-T Re, contradicting the documented invariant

**File:** `src/components/channels.jl:770-780`
**Issue:**
The `variant_obs` loop redefines the local `Re_i` at line 770 to use the
**film** temperature:
```julia
T_film_obs_i = (T[i] + thermal_left[i].T) / 2
Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T_film_obs_i))
Pr_i = cp_water(T_film_obs_i) * mu_water(T_film_obs_i) / k_water(T_film_obs_i)
push!(variant_obs, Nu[i] ~ htc_correlation(Re_i, Pr_i, T[i], thermal_left[i].T))
...
nu_i = mu_water(T[i]) / rho_water(T[i])
Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
push!(variant_obs, Gr_over_Re2[i] ~ Gr_i / Re_i^2)   # <-- Re_i is FILM-T here
```
The denominator `Re_i^2` reuses the film-T `Re_i` defined for the `Nu[i]`
observable, so `Gr_over_Re2[i]` is now `Gr(bulk) / Re(film)^2`.

This directly contradicts the explicit invariant the phase asserts in the
comment block at lines 661-666:
> "Friction Re ... and the natural-convection Gr inside regime_dependent /
> elenbaas_htc / **variant_obs Gr_over_Re2[i]** ... intentionally STAY at
> bulk T ... Do NOT 'fix' those to film T; they are correct as-is."

Pre-Phase-57, `Gr_over_Re2[i]` was `Gr(bulk) / Re(bulk)^2`. After this phase,
the numerator is still bulk but the denominator silently moved to film. The
plan and the comment both say this should NOT happen. Because `Gr_over_Re2 > 1`
is the NC-detection criterion in `regime_dependent` (correlations.jl line 161
in `htc_fn`), this discrepancy also creates a values-divergence between the
diagnostic observable in CAC and the NC switch criterion that callers see —
they should be the same number, computed the same way.

Note that `regime_dependent`'s NC switch *also* receives film-T Re from the
caller (since CAC now passes film-T Re into `htc_correlation`), so the NC
criterion `Gr_val / Re^2 > 1` inside the closure is *also* `Gr(bulk) / Re(film)^2`.
That mismatch with Python STREAM (Gr/Re^2 both at bulk for the NC criterion)
is structurally harder to fix without touching `regime_dependent` (or passing
a separate bulk Re alongside the film Re), but the `Gr_over_Re2[i]` observable
under direct control of CAC has no such excuse.

**Fix:**
Compute a separate bulk-T `Re_i_bulk` and use it in the `Gr_over_Re2[i]` line.
Either explicitly:
```julia
for i in 1:n
    # Film-T Re/Pr for Nu[i] observable (matches h_tc[i] in variant_eqs)
    T_film_obs_i = (T[i] + thermal_left[i].T) / 2
    Re_i_film = abs(port_in.mdot) * Dh / (A * mu_water(T_film_obs_i))
    Pr_i_film = cp_water(T_film_obs_i) * mu_water(T_film_obs_i) / k_water(T_film_obs_i)
    push!(variant_obs, Nu[i] ~ htc_correlation(Re_i_film, Pr_i_film, T[i], thermal_left[i].T))
    push!(variant_obs, h_tc_left[i]  ~ h_tc[i])
    push!(variant_obs, h_tc_right[i] ~ h_tc[i])
    push!(variant_obs, T_wall_left[i]  ~ thermal_left[i].T)
    push!(variant_obs, T_wall_right[i] ~ thermal_right[i].T)
    push!(variant_obs, velocity[i] ~ abs(port_in.mdot) / (rho_water(T[i]) * A))

    # Bulk-T Re for the NC criterion observable (Python STREAM convention)
    Re_i_bulk = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
    nu_i = mu_water(T[i]) / rho_water(T[i])
    Gr_i = Gr(beta_water(T[i]), g_acc, thermal_left[i].T - T[i], Dh, nu_i)
    push!(variant_obs, Gr_over_Re2[i] ~ Gr_i / Re_i_bulk^2)
end
```
Then either (a) accept that the `regime_dependent` NC switch sees film-T Re
and document it as a Phase-57 known deviation, or (b) make CAC compute both
forms and pass bulk Re to the NC switch by extending the htc_correlation
signature — out of scope for this phase but worth a TODO.

A unit test asserting `Gr_over_Re2[i]` matches `Gr(bulk) / Re(bulk)^2`
numerically (to a tight tolerance, on a known case where `T_wall != T[i]`)
would have caught this regression.

## Warnings

### WR-01: `scb_correction(..., Re_i)` silently switched from bulk Re to film Re

**File:** `src/components/channels.jl:690, 702, 704`
**Issue:**
Inside the SCB branch, `Re_i` is now defined at line 690 using film T:
```julia
Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T_film_i))
```
That same `Re_i` is then passed as the third argument to `scb_correction` at
both call sites:
```julia
q_scb_i     = scb_correction(T_w_i, T_sat_i, Re_i)        # line 702
...
q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i)      # line 704
```
The phase plan only mentions moving `Re`, `Pr`, and the leading `k_water` of
the htc_correlation pipeline to film T. The Re argument of `scb_correction` is
not mentioned and was, pre-phase, evaluated at bulk T. After this phase it is
film-T.

Whether this is desired (consistent with the htc-pipeline shift) or a regression
(Python STREAM may evaluate the SCB Re at bulk) is not asserted anywhere in the
plan or comments. Given that `regime_dependent_q_scb` (the typical
`scb_correction` factory) closes a `htc_turbulent` correlation that itself
uses `Re` as input, passing film-T Re here further propagates the film-T
convention into the SCB closure — which may or may not match Python STREAM.

**Fix:**
Decide explicitly. If film-T Re is intended for the SCB closure, add a sentence
to the comment block at lines 651-677 enumerating the call sites this phase
affects, including `scb_correction`'s Re argument. If bulk-T is intended,
introduce a separate bulk Re inside the SCB loop:
```julia
T_w_i      = thermal_left[i].T
T_film_i   = (T[i] + T_w_i) / 2
Re_i_bulk  = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
Re_i_film  = abs(port_in.mdot) * Dh / (A * mu_water(T_film_i))
Pr_i_film  = cp_water(T_film_i) * mu_water(T_film_i) / k_water(T_film_i)
h_spl_i    = htc_correlation(Re_i_film, Pr_i_film, T[i], T_w_i) * k_water(T_film_i) / Dh
...
q_scb_i     = scb_correction(T_w_i, T_sat_i, Re_i_bulk)
q_scb_inc_i = scb_correction(T_ONB_i, T_sat_i, Re_i_bulk)
```
A regression test comparing SCB `h_tc[i]` against a known-good Python STREAM
case (parity_report.csv pipeline already used for v1.1 validation) would
disambiguate this.

## Info

### IN-01: Stale line references in the Phase 57 comment block

**File:** `src/components/channels.jl:651-677` (specifically lines 663-664, 675)
**Issue:**
The comment block references obsolete line numbers:
- Line 664: "variant_obs Gr_over_Re2[i] (channels.jl:742-743)" — actual location
  is `~779-780` after the comment-block insertion shifted everything down.
- Line 675: "variant_obs Nu[i] (lines 733-744 below)" — actual location is
  `~762-781`.
- The comment also references "channels.jl:139 inside _channel_core" for
  friction Re — that is currently line 139, so it is correct, but it is the
  only line reference that is. Mixing accurate and stale line numbers is worse
  than using none.

**Fix:**
Either update the line numbers to match the post-edit file or — preferably —
drop bare line numbers and refer to the named locations only ("inside
`_channel_core`'s friction block", "in the `variant_obs` `Gr_over_Re2[i]`
push", etc.). Bare line numbers always rot.

### IN-02: `ChannelAndContacts` docstring does not mention the film-T HTC convention

**File:** `src/components/channels.jl:553-583`
**Issue:**
The docstring for `ChannelAndContacts` lists `htc_correlation` with the
signature `(Re, Pr, T_bulk, T_wall) -> Nu` but does not state that Re and Pr
are now evaluated at the film temperature when computing `h_tc[i]`. The
correlations.jl docstrings were updated as part of this phase to spell out
the convention, but the CAC docstring — which is the user-facing entry point —
was not. A user implementing a custom `htc_correlation` and reading the CAC
docstring will not know what eval-point to expect.

**Fix:**
Add a "HTC eval-point convention" subsection to the `ChannelAndContacts`
docstring, e.g.:
```
# HTC eval-point convention (Phase 57)
The `Re` and `Pr` passed to `htc_correlation` are evaluated at the film
temperature `T_film = (T[i] + T_wall) / 2`, matching Python STREAM's
`coolant_funcs.to_properties(T_film, pressure)` convention. The leading
`k_water` outside `Nu` (in `h = Nu * k / Dh`) is also evaluated at `T_film`.
Friction `Re` and the diagnostic `Re[i]/Pr[i]/Pe[i]` observables in the
shared core remain at bulk T.
```

### IN-03: `correlations.jl` repeats the same eval-point sentence verbatim across seven docstrings

**File:** `src/physical_models/htc/correlations.jl` (lines 29, 49, 115, 223, 281, 302, 325, 345)
**Issue:**
The sentence
> "Eval-point convention: callers should pass `Re` and `Pr` evaluated at
> `T_film = (T_bulk + T_wall)/2`. The Channel core in
> `src/components/channels.jl` does this."
is duplicated in eight docstrings. Verbatim repetition like this drifts:
when the convention is later refined (e.g. when the h-pipeline for
HeatExchanger or MicroChannel is added, or when a partial-film convention
is introduced), each copy must be hand-edited and one will be missed.

The file header at lines 9-15 already documents the convention authoritatively.
The per-function docstrings could either (a) link to the file header
("see file-level Eval-point convention note"), or (b) keep the one-liner
but make it tightly identical so a `grep -F` audit can verify all copies
agree.

This is a maintenance hazard, not a correctness issue — Info severity.

**Fix:**
Replace each duplicate with a one-liner that points at the file header,
e.g. "Eval-point convention: see file-level note (callers pass `Re`/`Pr`
at film T)." The file header already has the full statement.

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

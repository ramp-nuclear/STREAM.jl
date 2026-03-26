# Phase 26: NC Regime HTC + LOF Cleanup - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-26
**Phase:** 26-nc-regime-htc-lof-cleanup
**Areas discussed:** VAL-02 temperature rise test, regime_dependent NC interface, build_loop_lof_bypass wiring, Gr observable

---

## VAL-02 Temperature Rise Test

| Option | Description | Selected |
|--------|-------------|----------|
| ΔT = Q_wall/(mdot_nc*cp), 30% rtol | Energy balance analytical estimate, same tolerance as mdot test | ✓ |
| Elenbaas Nu back-calculation, 30% rtol | More physics-accurate but more complex test calculation | |
| Just assert ΔT > forced-flow ΔT | Qualitative only — NC mdot lower → ΔT must be larger | |

**User's choice:** ΔT = Q_wall/(mdot_nc*cp), 30% rtol — consistent with existing mdot test tolerance.

---

## regime_dependent NC Interface

| Option | Description | Selected |
|--------|-------------|----------|
| Backward compat + construction-time warning | htc_natural/Dh/g default to nothing; @warn if Dh/g given but htc_natural missing | ✓ |
| Error if partial NC args provided | ArgumentError when htc_natural given without Dh/g | ✓ (for htc_natural without Dh/g case) |

**User's choice:** Return existing lam/turb switching unchanged when htc_natural=nothing. Construction-time `@warn` if Dh/g provided but htc_natural is missing (user wants some visibility into NC-relevant regions even when NC HTC is not wired). `ArgumentError` if htc_natural provided but Dh or g missing.

**User note:** "we don't provide enough for htc_natural to work, AND we reach a region where we would actually want to use a NC htc, at least raise a warning in some sort of way that would be either always visible to the user, or visible somewhere where he can check if that exists right now"

---

## Gr Observable

| Option | Description | Selected |
|--------|-------------|----------|
| Add Gr/Re² as @observed to ChannelAndContacts and ChannelHeatFlux | Post-solve NC diagnostics via sol[sys.ch.Gr_over_Re2, :] | ✓ |
| Defer Gr observable to later phase | Keep Phase 26 minimal, no component changes | |

**User's choice:** Add Gr_over_Re2[i] as @observed — users want to inspect NC regime the same way they inspect Re post-solve.

**User note:** "what if I want it to be an observable of the various channels? Can we easily do that? I mean like Re and the rest of the dimensionless variables can be asked for after successfully finding a steady state or transient solution"

---

## build_loop_lof_bypass Wiring

| Option | Description | Selected |
|--------|-------------|----------|
| Both ch and ret per ROADMAP SC2 | NC wired for both, per spec; NC dormant in ret (Gr=0) | |
| Just ch (heated channel only) | Physics-driven: NC only where T_wall ≠ T_fluid | ✓ |

**User's choice:** Just ch (ChannelHeatFlux). ret stays with pure lam/turb switching. Slight deviation from ROADMAP SC2 wording — user prefers physics-correct scoping over mechanical compliance.

---

## Claude's Discretion

- Exact wording of construction-time @warn
- Whether to add both Gr[i] and Gr_over_Re2[i] or just Gr_over_Re2[i]
- Exact formula for VAL-02 ΔT analytical estimate
- Whether to expose htc_natural/Dh/g as optional kwargs to build_loop_lof_bypass

## Deferred Ideas

- NC wiring for ret (return Channel) — physics-driven decision to omit; revisit for heated-return scenarios
- Transition blending — v0.7+ per agreed architecture

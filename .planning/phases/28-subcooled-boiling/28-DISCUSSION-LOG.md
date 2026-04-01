# Phase 28: Subcooled Boiling - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-29
**Phase:** 28-subcooled-boiling
**Areas discussed:** scb_correction kwarg design, Bergles-Rohsenow property inputs, SCB-04 re_bounds parameterization

---

## scb_correction kwarg design

| Option | Description | Selected |
|--------|-------------|----------|
| q-flux closure (Recommended) | scb_correction = (T_wall, T_sat, Re) → q_scb [W/m²]. CAC calls it twice (at T_wall and at T_ONB) to get q_scb and q_scb_inc, then calls partial_SCB_correction internally. | ✓ |
| Full correction closure | scb_correction = (T_wall, T_ONB, q_spl, Re) → factor. Caller pre-wires McAdams/BR + partial_SCB_correction. More composable but verbose. | |
| Partial correction direct | scb_correction = (q_spl, q_scb, q_scb_inc) → factor. CAC also needs a separate q_scb_fn kwarg. Two kwargs instead of one. | |

**User's choice:** q-flux closure
**Notes:** CAC owns the partial correction logic; user passes regime_dependent_q_scb as the closure. Minimal surface area.

---

## Bergles-Rohsenow property inputs

| Option | Description | Selected |
|--------|-------------|----------|
| Optional kwargs with LW defaults (Recommended) | h_fg and sigma are optional keyword args with light-water defaults at ~100°C. | ✓ |
| Required positional args | h_fg and sigma required; no defaults. Consistent with 'scalar constants' framing but verbose. | |
| Pressure-interpolated from table | Helper looks up h_fg(P) and sigma(P). More accurate but out of scope per REQUIREMENTS.md. | |

**User's choice:** Optional kwargs with light-water defaults
**Notes:** Works for standard reactor conditions without boilerplate; advanced users can override.

---

## SCB-04 re_bounds parameterization

| Option | Description | Selected |
|--------|-------------|----------|
| Sharp cutoff, same Re_transition=2300 (Recommended) | No interpolation zone. McAdams for Re ≥ 2300, Bergles-Rohsenow for Re < 2300. Consistent with existing regime_dependent. | ✓ |
| Configurable re_bounds tuple | (Re_low, Re_high) with linear interpolation in transition zone. More complex. | |
| Delegate to existing regime_dependent | Thin wrapper over regime_dependent() with McAdams and B-R as closures. | |

**User's choice:** Sharp cutoff, same Re_transition=2300
**Notes:** re_bounds in REQUIREMENTS.md signature maps to a single Re_transition kwarg (not a tuple).

---

## Claude's Discretion

- Exact McAdams coefficient/exponent (match Python STREAM)
- Exact Bergles-Rohsenow formula variant (match Python STREAM)
- Light-water default values for h_fg and sigma
- Whether scb_correction wiring goes through _channel_base_eqs or directly in ChannelAndContacts constructor
- Export names (follow existing pattern)

## Deferred Ideas

None.

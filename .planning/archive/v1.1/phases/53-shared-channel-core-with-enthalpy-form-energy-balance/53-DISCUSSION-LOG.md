# Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-06
**Phase:** 53-Shared `_channel_core` with Enthalpy-Form Energy Balance
**Areas discussed:** Core API shape, Boundary-face cp formula, Observables ownership, Phase-53 verification depth

---

## Core API shape

### Initial framing (rejected by user as lazy)

First proposal anchored on "what's already there" — eqs-mutator (current `_channel_base_eqs` style) — without examining whether it was actually idiomatic. User pushed back: "if this is idiomatic to Julia thats ok, but if you are just doing this because its whats already in place then we can shake it up if we can do something that is clearly better." Reframed honestly:

| Option | Description | Selected |
|--------|-------------|----------|
| Eqs-mutator `_channel_core!(eqs, obs; ...)` | Mirror `_channel_base_eqs`: appends in place. Doubles down on the no-`!`-suffix mutation already in the codebase. | |
| Structured return `(; eqs, obs)` | Pure data flow. Variants concatenate `[variant_eqs; core.eqs]`. Most Julia-onic for cold construction code. | ✓ |
| Partial System + `extend()` | OnePort-style. Awkward when the base depends on `n` and shared array-vars must be threaded across the boundary. | |

**User's choice:** Structured return.

### Follow-up: signature scope (user pushed back a second time)

User flagged that the proposed signature included `htc_correlation`, but only `ChannelAndContacts` actually uses an HTC correlation in the new design — `Channel` consumes external `h` from `WallPort`, `ChannelHeatFlux` consumes external `q_flux` from `HeatFluxPort`. Reworked the scope by walking through each variant's q construction:

| Concern | Belongs in core? | Why |
|---------|------------------|-----|
| `htc_correlation` | NO | Only CAC uses it; making it a core kwarg re-introduces a flag-style knob |
| `friction_correlation` | YES | Identical Darcy-Weisbach formula in all three variants |
| `q_left_expr` / `q_right_expr` | YES (as inputs) | Variant-built; uniform additive contribution to energy balance, no flags inside core |
| Energy balance equation | YES | Single source of truth for NRG-01..04 |

**Final signature:** `_channel_core(; n, T, dp, port_in, port_out, geometry, g_acc, friction_correlation, q_left_expr, q_right_expr)::NamedTuple{(:eqs, :obs)}`.

### Follow-up: q-expression form

| Option | Description | Selected |
|--------|-------------|----------|
| Vector of `Num` length n | Variant builds the vector once (e.g. `[h * heated[1] * dz * (T_wall[i] - T[i]) for i in 1:n]`) and passes it in. Symmetric with how T/dp/Re are already handled. | ✓ (implicit, no separate ask) |
| Per-cell closure `(i) -> Num` | More flexible but no current variant needs the flexibility. | |
| Two scalar expressions per side | Doesn't fit Channel/CAC where q varies per cell. | |

User's framing: "if its general and works fine without flags or all that - we can keep giving _channel_core those expressions." Confirmed via reasoning that uniform additive contribution introduces no flags, and CORE-01 explicitly mandates the `q_*_expr` signature.

**User's choice:** Vector of Num as inputs to core (locked via "yes" after reasoning).

**Notes:** The first round was a sloppy framing on my part — the user's pushback on "is this Julia-onic or just inertia?" and "why is htc_correlation in core?" both led to better scope. Memory note candidate: when laying out trade-offs, separate "matches what's there" from "principled idiom" so the user can spot inertia.

---

## Boundary-face cp formula

**Resolved by reading Python STREAM source — no AskUserQuestion needed.**

### The ambiguity

REQUIREMENTS NRG-01 says interior face cp = `(cp(T_up) + cp(T[i])) / 2`. NRG-02 says boundary face uses `cp(T_in)`. Two readings possible:
- (a) Boundary uses bare `cp(T_in)` — different formula from interior
- (b) Boundary uses the same averaging formula with `T_up = T_in` → `(cp(T_in) + cp(T[1])) / 2`

### Resolution via Python source

`stream/calculations/channel.py:158-162`:
```python
c_bulk = fluid.specific_heat(T)
cin = fluid.specific_heat(Tin)
c = directed(pair_mean_1d(directed(c_bulk, mdot), prepend=cin), mdot)
```

`stream/utilities.py:359-376` (`pair_mean_1d` with `prepend=cin`):
- Interior (i ≥ 1): `res[i] = (arr[i-1] + arr[i]) / 2`
- Boundary (i = 0): `res[0] = (prepend + arr[0]) / 2 = (cp(T_in) + cp(T[1])) / 2`

**Verdict: reading (b) is correct.** Boundary face uses the same averaging as interior, with `T_up = T_in`.

**User's choice:** Confirmed via "yes, but please return to the gsd interface" after the source-level finding was presented.

**Notes:** This is exactly the kind of question where reading reference code is faster and more accurate than AskUserQuestion roundtripping. No options were presented — the answer is determined by Python.

---

## Observables ownership

| Option | Description | Selected |
|--------|-------------|----------|
| Maximal core | Core owns CORE-01 list + `v[i]`, `T_out`, `q_wall[i]`. | |
| Strict CORE-01 list | Core owns only Re, Pe, P[i], T_sat, T_ONB, dP. Honors requirement text literally; duplicates trivial equations across variants. | |
| Maximal core + per-side q stubs | Same as Maximal, plus `q_wall_left[i] ~ q_left_expr[i]` and `q_wall_right[i] ~ q_right_expr[i]` as per-side diagnostics. Every variant gets a uniform per-side q observable for free. | ✓ |

**User's choice:** Maximal core + per-side q stubs.

**Notes:** Locks in: core owns Re, Pe, v, T_out, P[i], dP, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right. Variants own h_tc, Nu, h_tc_left/right, T_wall_left/right, Gr_over_Re2 (and any per-variant aliases over connector vars). User chose "Next area" on the follow-up, so no sub-questions about declaration mechanics — left to the planner.

---

## Phase-53 verification depth

| Option | Description | Selected |
|--------|-------------|----------|
| Constant-cp limit + hand-computed Python parity | Two tests: (a) Constant-cp limit (~1 K dT, match v1.0 baseline within ~1e-6), (b) Realistic cp variation (~30 K dT, hand-computed Python pair_mean_1d expected within ~1e-9). | ✓ |
| Constant-cp limit only | Just (a). Catches gross errors but cp(T) variation drift only surfaces in Phase 56. | |
| ROADMAP minimum | Compile-clean + single-cell mirror + code-path coverage. Trust Phase 56. | |
| Mini build_loop with Phase-53-shipped variant | Pull one variant rewrite into Phase 53 for an end-to-end loop test. Expands scope into Phase 54. | |

**User's choice:** Constant-cp limit + hand-computed Python parity.

**Notes:** Choice driven by `feedback_design_validation_rigor` memory ("don't declare a design viable without numerical parity against the proven baseline") and the three-phase distance from Phase 53 to Phase 56's Python-parity gate. Two-stage local verification means Phase 54/55 build on a Python-faithful core.

---

## Claude's Discretion

The following implementation details were deferred to the planner, not pinned by user choice:

- **Commit granularity** inside Phase 53 (atomic single-step rewrite vs. extract→switch→delete vs. switch→extract). Constraint: variants must continue to compile and pass tests at every commit boundary, since `_channel_base_eqs` callers (Channel, CAC, CHF) aren't rewired until Phase 54.
- **Where the placeholder test scaffold lives** (`test/test_channel.jl` extension vs. new `test/test_channel_core.jl`). Both placements respect CLAUDE.md test placement rules.
- **Where core's observable LHS variables get declared** (variant `@variables` block vs. small `_channel_core_obs_vars(; n)` helper that returns a named tuple to splat). Planner picks based on call-site readability.
- **`Q_wall_total` for CAC** — keep as a CAC-only observable summing `core.q_wall[i]`; not a core concern.

## Deferred Ideas

None — discussion stayed within Phase 53 scope. All cross-phase concerns (variant rewrites in Phase 54, file consolidation in Phase 54 VAR-04, composition-helper updates in Phase 55, Python cross-validation in Phase 56) were already mapped in REQUIREMENTS.md and ROADMAP.md before this discussion.

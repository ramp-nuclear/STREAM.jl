# Phase 60: `fuel_assembly` composition helper - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-11
**Phase:** 60-fuel-assembly-composition-helper
**Areas discussed:** GUI code-gen detection scope, `bookend` parameter design, Vector ordering / Variant 3 orientation, Reuse existing helpers vs raw connect chain

---

## GUI code-gen detection scope

| Option | Description | Selected |
|--------|-------------|----------|
| Defer to Phase 61 | Phase 60 is pure `src/` work (helper + Julia tests). The TypeScript codeGenerator.ts rule lands in Phase 61 alongside the registry/codeGen overhaul. Keeps Phase 60 small (~100 LOC) and single-concern; Phase 61 already owns codeGen edits. | ✓ |
| Include in Phase 60 | Add the detection rule to `gui/src/lib/codeGenerator.ts` as part of Phase 60. Matches the literal ROADMAP+§3.12 wording. Larger phase, mixes Julia + TypeScript work. | |
| Stub in Phase 60, complete in Phase 61 | Phase 60 adds a minimal recognition stub or comment block in codeGenerator.ts so the helper is at least referenced, but full detection logic + emit lands in Phase 61. | |

**User's choice:** Delegated to Claude with the instruction "whichever produces the best result."
**Notes:** Claude selected "Defer to Phase 61" on four grounds: (1) single-concern phase boundaries; (2) Phase 59 already established the precedent of emitting a Phase 61 handoff note (`correlation-geom-first-api.md`) for GUI-side downstream work; (3) Phase 61 must revisit `codeGenerator.ts` anyway for the `scope`-field split and the `htc_correlation` removal from Channel; (4) pure-Julia phases interact better with the daemon dev loop and worktree-isolated executors. Phase 60 emits `.planning/notes/fuel-assembly-api.md` as the Phase 61 handoff artifact.

---

## `bookend` parameter design

| Option | Description | Selected |
|--------|-------------|----------|
| Strict: `:auto` from lengths, error on conflict | `:auto` infers from `(length(channels), length(plates))`. Explicit `bookend` contradicting lengths → `ArgumentError` naming what was passed vs what lengths imply. Consistent with `one_sided_connection`'s explicit `side` validation. | ✓ |
| Lengths only — drop the kwarg | Lengths fully determine bookend for variants 1, 2, 4. For variant 3 use a separate `start` kwarg instead. Simpler API; caller never has to align bookend with lengths. | |
| Permissive: warn-and-coerce | `:auto` infers; explicit conflicting value emits `@warn` and proceeds with length-implied behavior. Lower friction. | |

**User's choice:** Strict.
**Notes:** Refusing silent reinterpretation matches the project's trust-the-user-but-catch-fixable-mistakes-early posture. Variant-3 orientation is handled by a separate `start` kwarg (next area).

---

## Vector ordering / Variant 3 orientation

| Option | Description | Selected |
|--------|-------------|----------|
| `start = :channel | :plate` kwarg (mixed only) | Dedicated `start::Symbol` kwarg. Required when `bookend==:mixed`; ignored (or `nothing`-default) for other variants. Explicit, self-documenting at call site. | ✓ |
| Replace `bookend` with `start` + `stop` | Drop the bookend symbol entirely. Take `start::Symbol` and `stop::Symbol`. Every variant maps to one `(start, stop)` pair. More verbose but fully orthogonal. | |
| Encode by vector argument order | When `bookend==:mixed`, the first element of `channels` and `plates` determine the chain start. Magical; caller has to know the convention. | |

**User's choice:** `start` kwarg.
**Notes:** Validation rules: `bookend==:mixed && start===nothing` → `ArgumentError`; `bookend!=:mixed && start!==nothing` → `ArgumentError` (refuse silent ignore of caller intent). `closed=true` ignores `start` (irrelevant for a ring).

---

## Reuse existing helpers vs raw connect chain

| Option | Description | Selected |
|--------|-------------|----------|
| Flat compose with raw connect chain (Path B) | One `compose(System(eqs, t; name), channels..., plates...)` at the top level. Helper walks the alternation pattern and emits per-cell `connect(...)` equations directly. Matches §3.12 wording. Single flat namespace. | ✓ |
| Per-cell reuse of `plate` / `one_sided_connection` (Path A) | Builds sub-assemblies and composes them. Each CAC is shared between two adjacent triplets — MTK forbids the same uncompiled subsystem appearing under two parents. Path A would require per-cell copies of each CAC, defeating identity. | |
| Hybrid — reuse for single-cell, flat for multi-cell | If 2- or 3-component case, delegate to existing helpers; otherwise flat. Two code paths and documentation burden with no real payoff. | |

**User's choice:** Path B.
**Notes:** The MTK "shared subsystem under two parents" constraint is the load-bearing reason — Path A would either lose unknown-binding identity (per-cell deep-copy) or break MTK's structural assumptions. Flat compose is also what `plate(...)` and `symmetric_plate(...)` already do internally, so this is a direct generalization.

---

## Claude's Discretion

- Internal helper names inside `fuel_assembly` (e.g. `_walk_alternation`, `_assembly_connections`) — private `_`-prefixed helpers, planner's call.
- Docstring example block shapes and parameter values (one canonical example per variant required, but specific values are open).
- Loop-bound check ordering vs `bookend` resolution — whichever produces clearer errors.
- Adiabatic endpoint handling for variants 1 & 2 — Claude's discretion notes that unconnected faces remain unconnected (MTK default, identical to `one_sided_connection`'s precedent). No explicit `connect(..., 0)` injection.
- Variant-4 wraparound pair shape — match the established alternation convention; planner pins exact port-array index on each side during implementation.
- Element type of `Vector{<:System}` vs `Vector{<:AbstractSystem}` — planner confirms by reading the public API of `ChannelAndContacts` and `HeatDiffusion`.

## Deferred Ideas

- GUI code-gen detection rule in `gui/src/lib/codeGenerator.ts` → Phase 61.
- GUI registry entry for `fuel_assembly` in `components.json` → Phase 61.
- Topology validation rules in the GUI validation framework → Phase 71.
- Single-cell delegate shortcut (k=1 routing) — rejected via D-04, not deferred.
- Pre-loop n-homogeneity validation across the vector — rejected via D-05; caller responsibility per existing helper precedent.
- Python STREAM parity gate — no analog in Python; Julia v1.2 is first appearance.
- Helper for asymmetric (non-alternating) chains — out of scope of §3.12.
- PK temperature feedback integration into `fuel_assembly` subsystems — out of scope here, but D-04's flat-compose choice preserves the option.

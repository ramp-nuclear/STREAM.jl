# Phase 60: `fuel_assembly` composition helper - Context

**Gathered:** 2026-05-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Add a new composition helper `fuel_assembly(channels, plates; bookend, start,
closed, name)` to `src/composition/helpers.jl` that handles the four variants
of alternating CAC↔Plate chains documented in §3.12 of the v1.2 design
contract:

1. **Channel-bookended** — `k` plates, `k+1` channels; chain starts and ends
   with a CAC (adiabatic outer CAC faces).
2. **Plate-bookended** — `k+1` plates, `k` channels; chain starts and ends
   with a plate (adiabatic outer plate faces).
3. **Mixed-bookended** — equal counts (`k` of each); one end is a plate, the
   other a channel. Orientation pinned by `start` kwarg (see D-03).
4. **Closed annular** — equal counts (`k` of each), forms a ring; last
   element wraps around to the first.

The helper walks the alternation pattern and emits the per-cell
`connect(port(...), port(...))` chain (same wiring shape that `plate(...)`
already produces), plus the wrap-around connections in the closed case.
Returns an uncompiled `ODESystem` from `compose()` — caller adds boundary
conditions and calls `mtkcompile()`, identical to the contract of every
existing helper in this file.

**In scope:**
- New helper `fuel_assembly` in `src/composition/helpers.jl`.
- Export from `src/STREAM.jl`.
- Tests in `test/test_composition.jl` covering all four variants — parity
  against hand-rolled `connect()` chains at representative `k`.
- Phase 61 handoff: short note appended to `.planning/notes/correlation-geom-first-api.md`
  (or a sibling note) specifying helper signature + topology-detection rule
  for the GUI codeGenerator to consume.

**Out of scope:**
- GUI code-gen detection rule (`gui/src/lib/codeGenerator.ts`) — deferred to
  Phase 61 per D-01. Phase 60 is `src/`-only.
- GUI registry entries (`gui/src/registry/components.json`) — Phase 61.
- Python STREAM analog parity — Python does not have this helper; not a v1.2
  parity gate.
- Refactor of existing helpers (`symmetric_plate`, `plate`,
  `one_sided_connection`). These remain unchanged.
- Topology validation rules in the GUI validation framework — Phase 71.

</domain>

<decisions>
## Implementation Decisions

### Scope split with Phase 61
- **D-01:** Phase 60 is `src/`-only. The GUI code-gen detection rule for the
  alternating CAC↔Plate sequence lands in Phase 61 alongside the rest of the
  `codeGenerator.ts` + `components.json` rewrite. Rationale: (a) Phase 61
  already owns those files; (b) Phase 59's precedent (`correlation-geom-first-api.md`
  handoff note feeding Phase 61) maps cleanly here; (c) single-language
  phases interact better with the daemon dev loop; (d) Phase 61 must
  revisit topology detection anyway for the `scope`-field split and
  `htc_correlation` removal from Channel. Phase 60 emits a Phase 61
  handoff note specifying the helper signature + the detection-rule spec.

### `bookend` parameter design
- **D-02:** `bookend` is a `Symbol` kwarg with values
  `:auto | :channel | :plate | :mixed` (default `:auto`).
  `:auto` infers from `(length(channels), length(plates))`:
  - `length(channels) == length(plates) + 1` → `:channel`
  - `length(plates) == length(channels) + 1` → `:plate`
  - equal lengths → `:mixed`
  - any other shape → `ArgumentError` naming the lengths
  Explicit bookend that contradicts the length-implied value → `ArgumentError`
  reporting both the passed and inferred values. Trust-the-user posture, but
  catch user-fixable mistakes early. Consistent with the
  `one_sided_connection`'s `side in (:left, :right) || error(...)` precedent.

### Variant 3 (mixed) orientation
- **D-03:** Add a dedicated `start::Union{Symbol,Nothing} = nothing` kwarg.
  Values `:channel | :plate`. Semantics:
  - `bookend == :mixed && start === nothing` → `ArgumentError` requiring
    `start=:channel` or `start=:plate`.
  - `bookend != :mixed && start !== nothing` → `ArgumentError` (caller intent
    is unused; refuse the silent ignore).
  - `start=:channel` means the chain starts with `channels[1]`, alternates
    `Plate, CAC, Plate, …`, ends with `plates[end]`.
  - `start=:plate` means the chain starts with `plates[1]`, ends with
    `channels[end]`.
  Self-documenting at call site; avoids overloading `bookend`.

### Internal wiring strategy
- **D-04:** Flat compose with raw connect chain. The helper builds a single
  `Vector{Equation}` of `connect(port(cac, :thermal_right, i), port(plate, :thermal_left, i))`
  pairs (and the symmetric `cac.thermal_left ↔ plate.thermal_right` pair on
  the next cell), then calls
  `compose(System(connections, t; name=name), channels..., plates...)` once
  at the top level. Mirrors the existing `plate(...)` / `symmetric_plate(...)`
  internal shape (Equation[] + single `compose()` call).
  Path-A (per-cell reuse of `plate(...)` / `one_sided_connection(...)`) was
  rejected: each CAC is shared between two adjacent triplets, and MTK
  forbids the same uncompiled subsystem appearing under two parents — Path A
  would require synthesizing a per-cell copy of each CAC, which loses
  unknown-binding identity and defeats the point of a composition helper.

### Helper signature (final)
```julia
fuel_assembly(channels::Vector{<:System}, plates::Vector{<:System};
              bookend::Symbol = :auto,
              start::Union{Symbol,Nothing} = nothing,
              closed::Bool = false,
              name::Symbol)
```
- Element types are typed loosely as `Vector{<:System}` (or
  `Vector{<:AbstractSystem}`) rather than `Vector{<:CAC}` / `Vector{<:HD>}`,
  because `ChannelAndContacts` and `HeatDiffusion` are factory functions that
  return concrete `System` / `ODESystem` instances — there is no `CAC`
  abstract type in the codebase. Planner confirms exact element type from
  the public API.
- `name` is keyword-only (CLAUDE.md convention, required by `@named`).
- `closed = true` requires `bookend ∈ {:mixed, :auto}` and equal lengths;
  the helper validates and errors otherwise. With `closed=true`, the chain
  is a ring (variant 4); `start` is ignored (irrelevant for a ring).

### Validation strictness
- **D-05:** Per-cell `n` matching (`cac.n == plate.nz` for every adjacent
  pair) follows the existing helper precedent — **caller responsibility**.
  Helpers in this file already note "caller ensures this" and do not
  validate. `_infer_n` is used once on `channels[1]` to determine the
  per-cell port-loop bound. Mismatched n across the vector is caught by MTK
  at `mtkcompile()` time (port-count mismatch in `connect`). Adding pre-loop
  homogeneity assertions is gratuitous and inconsistent with the rest of
  `helpers.jl`.

### Test coverage (locked to follow §3.12 test plan)
- **D-06:** Tests live in `test/test_composition.jl` (per CLAUDE.md
  "Test placement rule: test file mirrors src file"). Coverage per variant:
  - One representative `k` per variant — minimum `k=2` for variants 1/2/3
    and `k=3` for variant 4 (smaller closed loops are degenerate).
  - For each variant, build the helper-composed system AND a hand-rolled
    `connect()` system at the same `k`. After `mtkcompile()` + a steady
    `solve_steady` call, compare the unknown vector pointwise to
    machine-precision (`isapprox(...; rtol=1e-10)`). This is the parity
    gate §3.12 names.
  - `ArgumentError` paths: explicit `bookend` conflicting with lengths;
    `bookend=:mixed` without `start`; `start` set with non-mixed bookend;
    `closed=true` with unequal lengths.
  - Smoke test: helper output is a valid uncompiled `ODESystem` (no early
    `mtkcompile` inside the helper).
- No Python parity gate — Python STREAM has no `fuel_assembly` analog (this
  helper is new in Julia v1.2).

### Phase 61 handoff artifact
- **D-07:** Phase 60 emits a short markdown reference at
  `.planning/notes/fuel-assembly-api.md` (sibling to
  `correlation-geom-first-api.md`). Contents:
  1. Final helper signature with each kwarg's semantics.
  2. The four variants in ascii-art form, copied from §3.12.
  3. Topology-detection rule spec (input: graph of CAC + HD nodes with
     thermal edges; output: variant 1/2/3/4 or "fall through to direct
     `connect`").
  4. Endpoint/wraparound determination rules (which port-array index goes
     to which face on which neighbour) — so the Phase 61 codeGenerator
     emitter knows exactly which Julia call shape to produce.
  Phase 61 reads this directly instead of re-deriving from source.

### Claude's Discretion
- Exact internal helper names (`_walk_alternation`, `_assembly_connections`,
  etc.) are left to the planner — these are private (`_` prefix) and not
  part of the public API.
- Docstring example block(s) — at minimum one canonical example per variant
  in the public docstring, but the example shapes and parameter values are
  the planner's call.
- Whether the loop bound check (`length(channels)`, `length(plates) ≥ 1`)
  fires before or after the `bookend` resolution — choose whichever path
  produces the clearer error message.
- Adiabatic endpoint handling for variants 1 & 2: unconnected faces remain
  unconnected (MTK's default, identical to `one_sided_connection`'s
  precedent). No explicit `connect(..., 0)` or boundary-condition injection
  inside the helper.
- Wraparound pair shape for variant 4 (closed): match the established
  alternation convention — for `start=:channel` semantics on a closed loop,
  the wrap connects `channels[1].thermal_left[i] ↔ plates[end].thermal_right[i]`
  to mirror the per-cell pattern. Planner confirms in the implementation.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Design contract for this phase
- `.planning/notes/gui-redesign-design-decisions.md` §3.12 — `fuel_assembly`
  Composition Helper. Locks the helper name, location, the four variants,
  the rough signature, and the GUI code-gen detection rule (which Phase 61
  will implement). Authoritative source.
- `.planning/notes/gui-redesign-design-decisions.md` §1 — Core invariants
  (CAC = `ChannelAndContacts`, HD = `HeatDiffusion`, port-array shape
  `thermal_left[i]` / `thermal_right[i]`).
- `.planning/notes/gui-redesign-design-decisions.md` Table at line 1296 —
  phase-numbering table that confirms Phase 60 = sub-phase 1.5 (small helper
  scope).

### Source files to edit
- `src/composition/helpers.jl` — new `fuel_assembly` function appended after
  existing helpers (`symmetric_plate`, `plate`, `one_sided_connection`,
  `compose_systems`). Reuses `_infer_n` and `port(...)`. ~80–120 LOC plus
  docstring.
- `src/STREAM.jl` — add `fuel_assembly` to the export list.

### Existing helpers — wiring precedent
- `src/composition/helpers.jl` lines ~145–185 (`symmetric_plate`) — single
  triplet wiring shape `cac.thermal_right[i] ↔ fuel.thermal_left[i]` and
  the symmetric pair on the opposite face. Same pattern repeats per cell in
  `fuel_assembly`.
- `src/composition/helpers.jl` lines ~187–230 (`plate`) — two-channels-one-plate
  wiring; this is the canonical per-cell shape `fuel_assembly` walks.
- `src/composition/helpers.jl` lines ~232–277 (`one_sided_connection`) —
  half-cell wiring with `side::Symbol` arg validation. D-02/D-03 mirror this
  validation style.
- `src/composition/helpers.jl` lines ~136–143 (`_infer_n`) — port-count
  detection used for the per-cell loop bound. Operates on the first
  uncompiled channel.
- `src/composition/helpers.jl` line ~28 (`port(sys, face, i)`) — the only
  correct MTK syntax for indexed port array access inside `connect()`.

### Test conventions
- `test/test_composition.jl` — destination file (per CLAUDE.md). Already
  contains heavy CAC↔HD coverage from Phase 55 D-18; the new variant tests
  slot in alongside `symmetric_plate` / `plate` / `one_sided_connection`
  parity tests.
- `test/runtests.jl` — thin orchestrator; one `include()` per test file. No
  changes needed for `fuel_assembly` (already included).
- Phase 15 plan-02 `test_composition.jl` precedent — the existing helpers'
  parity tests in this file demonstrate the "build via helper, build via
  hand-rolled `connect()`, compare solutions" pattern.

### Solver / compilation contract
- `src/solvers.jl` — `solve_steady` used by parity tests.
- Helpers return raw uncompiled `ODESystem`; caller calls `mtkcompile()`.
  `build_initializeprob=false` is required when solving HeatDiffusion+CAC
  systems (per existing helper docstrings and Phase 47 notes).

### CLAUDE.md project conventions
- File structure standard — `src/composition/helpers.jl` (composition
  helper destination), `test/test_composition.jl` (test destination).
- Component authoring conventions — positional args when types determine
  behavior; `name` always keyword-only; `_` prefix for internal helpers;
  docstring sections (description, Arguments, Returns) mandatory for
  exports.
- Exports declared in `STREAM.jl` only — never inside component files.
- Branching policy — work on `gui-redesign` branch; never auto-create new
  branches. `.planning/config.json` `git.branching_strategy` stays `"none"`.

### Phase-flow predecessors
- `.planning/phases/59-correlation-geom-first-refactor/59-CONTEXT.md` —
  Phase 59 precedent for "small `src/` change + Phase 61 handoff note"
  pattern. D-05 there mirrors D-07 here.
- `.planning/notes/correlation-geom-first-api.md` — Phase 59's handoff note.
  Phase 60's handoff note (`fuel-assembly-api.md`, D-07) sits beside it and
  is read together by Phase 61.

### Handoff (emitted by this phase)
- `.planning/notes/fuel-assembly-api.md` — produced as a Phase 60 deliverable
  per D-07. Phase 61 consumes it for the `codeGenerator.ts` detection rule
  and the (eventual) registry entry for `fuel_assembly`.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_infer_n(sys)`** (`src/composition/helpers.jl` line ~136): counts
  `thermal_leftN` subsystems on an uncompiled channel. Use once on
  `channels[1]` to get the per-cell port loop bound. Errors with a helpful
  message if the caller passes a compiled system.
- **`port(sys, face::Symbol, i::Int)`** (line ~28): the only correct MTK
  syntax for indexed port-array access. Every `connect()` in
  `fuel_assembly` uses this.
- **`compose(System(connections, t; name=name), channels..., plates...)`
  shape** — used by every existing helper; varargs splat works because
  `compose()` accepts an arbitrary positional system list.

### Established Patterns
- **`Equation[ ... ]` array splat** for connection equations (see
  `symmetric_plate`, `plate`). Pattern:
  ```julia
  connections = Equation[
      [connect(port(a, :face_a, i), port(b, :face_b, i)) for i in 1:n]...,
      [connect(port(c, :face_c, i), port(d, :face_d, i)) for i in 1:n]...,
  ]
  ```
  Carries forward: each adjacent-cell pair produces two splat'd
  comprehensions (one per thermal face).
- **Kwarg validation idiom** (from `one_sided_connection`):
  `side in (:left, :right) || error("...")`. D-02 and D-03 use the same
  shape for `bookend` and `start`.
- **`name::Symbol` is always kwarg-only**, required by `@named` macro.
- **Raw `ODESystem` return** from helpers — caller calls `mtkcompile()`
  with `build_initializeprob=false` for HD+CAC systems.

### Integration Points
- `src/components/channels.jl` (`ChannelAndContacts`) — the CAC factory.
  `fuel_assembly` consumes the *uncompiled* instances; their `thermal_left`
  / `thermal_right` port arrays are what `port(...)` indexes into.
- `src/components/heat_diffusion.jl` (`HeatDiffusion`) — the HD factory.
  Same story: uncompiled instances with `thermal_left` / `thermal_right`
  arrays of length `nz`.
- `src/solvers.jl` — `solve_steady` used by Phase 15 parity tests; reused
  for D-06 variant-by-variant parity gates.
- **No interaction with `connect_temperature_feedback(pk, components)`**
  (lines ~315–367) in this phase — but planner should verify scoped
  reference syntax `assembly.cac1.T`, `assembly.plate2.T` resolves
  correctly after `compose(...; name=:assembly)`, so a future Phase 47-style
  point-kinetics integration on a fuel_assembly works without surprises.

### Naming inside the composed system
- After `compose(System(...; name=name), channels..., plates...)`, the
  sub-components are reachable via the names of the underlying
  uncompiled instances. So if the caller does:
  ```julia
  @named c1 = ChannelAndContacts(...); @named c2 = ...; @named c3 = ...
  @named p1 = HeatDiffusion(...);      @named p2 = ...
  assembly = fuel_assembly([c1, c2, c3], [p1, p2]; name=:assembly)
  ```
  the sub-components appear as `assembly.c1`, `assembly.p1`, etc. — *their
  own names*, not synthesized indices. This matters for Phase 61
  codeGenerator: it should round-trip the user-chosen names, not impose
  `cac1`/`plate1`/…

</code_context>

<specifics>
## Specific Ideas

- Canonical example block for the public docstring (one per variant):
  ```julia
  # Variant 1 — channel-bookended (k=2 plates, k+1=3 channels)
  assembly = fuel_assembly([c1, c2, c3], [p1, p2]; name=:asm)
  # bookend defaults to :auto → resolves to :channel

  # Variant 2 — plate-bookended (k=1 channel, k+1=2 plates)
  assembly = fuel_assembly([c1], [p1, p2]; name=:asm)

  # Variant 3 — mixed (k=2 of each), channel-first
  assembly = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm)

  # Variant 4 — closed annular ring (k=3 of each)
  assembly = fuel_assembly([c1, c2, c3], [p1, p2, p3]; closed=true, name=:asm)
  ```

- Phase 61 handoff note structure (suggested):
  ```
  | Variant | Bookend | Equal counts | Closed | Topology rule (GUI) |
  |---------|---------|--------------|--------|---------------------|
  | 1 | :channel | no  | false | endpoints are both CAC; len(CAC)=len(plate)+1 |
  | 2 | :plate   | no  | false | endpoints are both HD;  len(plate)=len(CAC)+1 |
  | 3 | :mixed   | yes | false | endpoints differ; equal counts; no wraparound |
  | 4 | :mixed   | yes | true  | equal counts; first and last share thermal edge |
  ```

- Per-cell wiring shape (`plate(...)` is the unit cell):
  ```julia
  # For CAC↔Plate↔CAC triplet at position k:
  connect(port(cac_left, :thermal_right, i),  port(plate_k, :thermal_left, i))
  connect(port(cac_right, :thermal_left, i),  port(plate_k, :thermal_right, i))
  # fuel_assembly walks this for every adjacent triplet in the chain.
  ```

</specifics>

<deferred>
## Deferred Ideas

- **GUI code-gen detection rule** (`gui/src/lib/codeGenerator.ts`) — deferred
  to Phase 61 per D-01. The handoff note `.planning/notes/fuel-assembly-api.md`
  (D-07) carries the spec.
- **GUI registry entry** for `fuel_assembly` (`gui/src/registry/components.json`)
  — deferred to Phase 61 as part of the registry rewrite.
- **Topology validation rules** for fuel_assembly in the GUI validation
  framework — deferred to Phase 71 (validation framework phase).
- **Single-cell delegate shortcut** (k=1 routing to `symmetric_plate` /
  `plate` / `one_sided_connection`) — explicitly rejected via D-04. Path B
  (flat compose) handles k=1 naturally; routing to existing helpers
  introduces two code paths and a documentation burden with no payoff.
- **Pre-loop n-homogeneity validation** across the vector — explicitly
  deferred via D-05. MTK catches per-pair mismatches at `mtkcompile()`.
- **Python STREAM parity gate** — Python has no `fuel_assembly` analog;
  Julia v1.2 is the first appearance. Not a v1.2 parity gate.
- **Helper for asymmetric (non-alternating) chains** (e.g.,
  Plate-CAC-CAC-Plate) — out of scope; §3.12 alternation invariant.
  Would be a future helper, not an extension of `fuel_assembly`.
- **PK temperature feedback into fuel_assembly subsystems** — not in
  scope, but D-04's flat-compose decision was specifically motivated in
  part by keeping `assembly.cac_k.T` reachable for a future Phase
  47-style `connect_temperature_feedback(pk, [assembly.c1, ...])` call.

</deferred>

---

*Phase: 60-fuel-assembly-composition-helper*
*Context gathered: 2026-05-11*

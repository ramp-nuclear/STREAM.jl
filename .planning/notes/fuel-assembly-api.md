# Fuel-assembly composition helper — Post-Phase-60 surface

**Status:** Canonical handoff artifact for Phase 61 (GUI codeGenerator +
registry rewrite).
**Source decision:** Phase 60 CONTEXT.md `<decisions>` D-07.
**Companion document:** `.planning/notes/gui-redesign-design-decisions.md`
§3.12 (`fuel_assembly` Composition Helper).
**Scope:** Captures the post-Phase-60 helper API + GUI topology-detection
rule. Does NOT replace docstrings — in-source docstrings in
`src/composition/helpers.jl` remain the canonical source of truth for
per-kwarg semantics and example shapes. Phase 61 reads this doc instead of
re-deriving the surface from `src/`.

Phase 60 landed in 2 plans on the `gui-redesign` working branch:
- 60-01 — `fuel_assembly(...)` helper + private `_walk_alternation` /
  `_pair_connections` helpers + export. Commits `7e21922` (Task 1) and
  `3d270c0` (Task 2).
- 60-02 — Four-variant parity tests + four ArgumentError tests + smoke test
  + this handoff note. Commit SHAs filled in at archive time.

---

## Helper signature

```julia
fuel_assembly(channels::Vector{<:ModelingToolkit.AbstractSystem},
              plates::Vector{<:ModelingToolkit.AbstractSystem};
              bookend::Symbol = :auto,
              start::Union{Symbol,Nothing} = nothing,
              closed::Bool = false,
              name::Symbol) -> ODESystem
```

Declared and exported from `src/STREAM.jl` (composition-helpers export
line). Returns an uncompiled `ODESystem` from `compose()` — caller adds BCs
(pump loop, pressure anchor, plate power bindings) and calls
`mtkcompile(...; build_initializeprob=false)`. Sub-components round-trip
the caller's `@named` names (`assembly.c1`, `assembly.p1`, …) — the helper
does NOT synthesize index-based names.

| Kwarg | Type | Default | Semantics |
|-------|------|---------|-----------|
| `bookend` | `Symbol` | `:auto` | One of `:auto`, `:channel`, `:plate`, `:mixed`. `:auto` infers from `(length(channels), length(plates))`. An explicit value contradicting the inferred value raises `ArgumentError`. See D-02. |
| `start` | `Union{Symbol,Nothing}` | `nothing` | Required when resolved `bookend == :mixed && !closed`. Values `:channel` (chain starts with `channels[1]`, ends with `plates[end]`) or `:plate` (chain starts with `plates[1]`, ends with `channels[end]`). Must be `nothing` for non-mixed bookends. See D-03. |
| `closed` | `Bool` | `false` | When `true`, wrap the chain into a ring (variant 4). Requires equal `length(channels) == length(plates)`. Raises `ArgumentError` otherwise. See D-04. |
| `name` | `Symbol` | (kwarg-only, required) | System name supplied by `@named` macro. |

**Closed-loop note:** when `closed == true && start === nothing`, the
helper defaults `start = :channel` (the ring is rotationally symmetric;
`:channel` gives the wrap pair a deterministic orientation). Documented
in `src/composition/helpers.jl` docstring under `# Arguments`.

**Caller-responsibility note (D-05):** per-pair `n` matching
(`cac.n == plate.nz` for every adjacent pair) is the caller's
responsibility — same contract as `symmetric_plate` / `plate` /
`one_sided_connection`. `_infer_n(channels[1])` is called once for the
per-cell port-loop bound; mismatched `n` across the vector is caught by
MTK at `mtkcompile()` time.

---

## The four variants

The ASCII diagrams below are copied verbatim from
`.planning/notes/gui-redesign-design-decisions.md` §3.12.

### Variant 1 — channel-bookended

```
Variant 1 (channel-bookended, +1 channel):
  [adiabatic] CAC1 ↔ Plate1 ↔ CAC2 ↔ Plate2 ↔ ... ↔ Platek ↔ CAC(k+1) [adiabatic]
  k plates, k+1 channels
```

Canonical call shape (from 60-CONTEXT `<specifics>`):
```julia
assembly = fuel_assembly([c1, c2, c3], [p1, p2]; name=:asm)
# bookend defaults to :auto → resolves to :channel
```

### Variant 2 — plate-bookended

```
Variant 2 (plate-bookended, +1 plate):
  [adiabatic] Plate1 ↔ CAC1 ↔ Plate2 ↔ ... ↔ CACk ↔ Plate(k+1) [adiabatic]
  k+1 plates, k channels
```

Canonical call shape:
```julia
assembly = fuel_assembly([c1], [p1, p2]; name=:asm)
# bookend defaults to :auto → resolves to :plate
```

### Variant 3 — mixed

```
Variant 3 (mixed-bookended, equal counts):
  Plate1 ↔ CAC1 ↔ Plate2 ↔ CAC2 ↔ ... ↔ Platek ↔ CACk
  k plates, k channels (or the reverse)
```

Canonical call shape:
```julia
assembly = fuel_assembly([c1, c2], [p1, p2]; bookend=:mixed, start=:channel, name=:asm)
# `start=:plate` gives the reverse orientation (plates[1] is the first element).
```

### Variant 4 — closed annular

```
Variant 4 (closed annular loop):
  CAC1 ↔ Plate1 ↔ CAC2 ↔ Plate2 ↔ ... ↔ CACk ↔ Platek ↔ CAC1 (wraps)
  k plates, k channels, ring topology
```

Canonical call shape:
```julia
assembly = fuel_assembly([c1, c2, c3], [p1, p2, p3]; closed=true, name=:asm)
# `start` defaults to :channel (canonical ring orientation, see closed-loop note)
```

---

## Topology-detection rule (for Phase 61)

Phase 61's `gui/src/lib/codeGenerator.ts` walks the user's component graph
and, before falling through to direct per-pair `connect()` emission,
checks whether the subgraph matches one of the four variants below. When
a match fires, the codeGenerator should emit a single `fuel_assembly(...)`
call instead of N hand-rolled `connect()` lines.

The table below extends the planner-supplied seed (60-CONTEXT
`<specifics>`) with two operational columns: **Input signature** describes
the topology features the codeGenerator inspects; **Emitted call shape**
gives the exact Julia source it should produce.

| Variant | Bookend | Equal counts | Closed | Topology rule (input signature) | Emitted call shape (Julia) |
|---------|---------|--------------|--------|--------------------------------|-----------------------------|
| 1 | `:channel` | no  | false | endpoints are both CAC; `len(CAC) == len(plate) + 1`; alternation CAC-HD-CAC-HD-…-CAC | `fuel_assembly([c1, c2, …, ck1], [p1, …, pk]; name=:asm)` |
| 2 | `:plate`   | no  | false | endpoints are both HD;  `len(plate) == len(CAC) + 1`; alternation HD-CAC-HD-CAC-…-HD | `fuel_assembly([c1, …, ck], [p1, p2, …, pk1]; name=:asm)` |
| 3 | `:mixed`   | yes | false | endpoints differ (one CAC one HD); `len(CAC) == len(plate)`; no closing edge | `fuel_assembly([c1, …, ck], [p1, …, pk]; bookend=:mixed, start=<:channel\|:plate>, name=:asm)` |
| 4 | `:mixed`   | yes | true  | `len(CAC) == len(plate)`; first and last share a thermal edge (closing edge present) | `fuel_assembly([c1, …, ck], [p1, …, pk]; closed=true, name=:asm)` |

**Detector input columns explained:**
- *Number of CAC nodes* — count of `ChannelAndContacts` instances on the
  thermal subgraph being analyzed.
- *Number of HD nodes* — count of `HeatDiffusion` instances.
- *Endpoint kinds* — the two nodes with exactly one thermal-edge neighbour
  (variants 1, 2, 3); both endpoints CAC = variant 1, both HD = variant 2,
  one each = variant 3. Variant 4 has no endpoints (ring).
- *Closing edge* — true iff the alternation has a thermal edge from the
  last node back to the first (variant 4 only).

**For variant 3**, the codeGenerator must pin `start` from the actual
endpoint kind: if `channels[1]` is the first-element in the user's chain,
emit `start=:channel`; if `plates[1]` is first, emit `start=:plate`.

**Fallthrough:** if the topology does NOT match any of variants 1–4, the
codeGenerator falls through to direct `connect(...)` emission per the
existing v0.8 behavior — `fuel_assembly` is opt-in detection, not a
forced rewrite.

---

## Endpoint / wraparound rules

Pseudo-code for the Phase 61 codeGenerator emitter when a `fuel_assembly`
match is detected. Steps a/b/c below are the wiring rules the emitter
implements; they mirror the in-source private helpers
`_walk_alternation` and `_pair_connections` in
`src/composition/helpers.jl` (which already implement these rules
internally — Phase 61 just needs to know the wiring convention).

**a) Per-pair adjacent-cell wiring (the alternation interior):**

```
For each adjacent pair (X, Y) in the alternation order:
    For each cell index i in 1..n:
        Emit:  connect(port(X, :thermal_right, i), port(Y, :thermal_left, i))
```

X is the left neighbour, Y is the right neighbour. The face convention is
**spatial-absolute**: the left-of-pair node always exposes its
`thermal_right` face to the pair; the right-of-pair node always exposes
its `thermal_left` face. This is the convention encoded by `helpers.jl`
in the `port(...)` / `_pair_connections` block.

> **Convention disagreement, inherited not created:** STATE.md
> "Blockers/Concerns" notes a documented disagreement between Channel's
> internal port-naming convention and the spatial-absolute L/R convention
> used here. Phase 61 inherits the existing v1.1 convention as-is and
> should NOT attempt to harmonize it during the codeGenerator rewrite.
> See `.planning/STATE.md` for the full context.

**b) Endpoint adiabatic faces:**

The codeGenerator should **NOT** emit explicit adiabatic boundary
equations on unconnected thermal faces. MTK's `Flow` connector default
(unconnected → `Q_flow = 0`) handles adiabatic endpoints automatically —
this is the same precedent `one_sided_connection` relies on (called out
in 60-CONTEXT `<decisions>` "Adiabatic endpoint handling" bullet). Just
skip emission for:

- *Variant 1* — `channels[1].thermal_left[i]` and
  `channels[end].thermal_right[i]` (the two outer-CAC adiabatic faces).
- *Variant 2* — `plates[1].thermal_left[i]` and
  `plates[end].thermal_right[i]` (the two outer-HD adiabatic faces).
- *Variant 3* — whichever endpoint faces lie at the start (per `start`
  kwarg) and the end of the chain. Two distinct faces.
- *Variant 4* — no unconnected endpoints (ring). This case skips zero
  faces.

**c) Wraparound pair (variant 4 only):**

```
After the per-pair interior wiring (rule a), if closed=true also emit:
    For each cell index i in 1..n:
        Emit:  connect(port(channels[1], :thermal_left, i),
                       port(plates[end], :thermal_right, i))
```

This mirrors the spatial-absolute convention used in rule (a) but with
swapped face polarity because the wraparound edge points from the *end*
back to the *start* (60-CONTEXT `<decisions>` last bullet, "Claude's
Discretion: Wraparound pair shape"). The default `start=:channel` (when
the user did not pin `start` explicitly) makes this pair shape canonical.

---

## GUI registry implications (Phase 61 guidance)

Parallel to the `correlation-geom-first-api.md` section of the same name.

- **`fuel_assembly` is a composition helper, not a component** — it should
  NOT appear in `gui/src/registry/components.json` as a draggable node.
  It is a CODEGEN-time emission, not a USER-edit-time entity. Users build
  the assembly out of regular CAC + HD nodes; the topology detector
  collapses the wiring into one `fuel_assembly(...)` call at code-emit
  time.
- **Detector lives in `gui/src/lib/codeGenerator.ts`** — Phase 61 owns
  this file. The detector is a pure pre-emission pass over the thermal
  subgraph (see "Topology-detection rule" above).
- **No new `scope` field** is needed for `fuel_assembly` — the helper has
  no user-tunable parameters beyond the component vectors themselves
  (which come from each component node's existing `@named` declaration,
  not a separate registry entry).
- **Replacement semantics:** when the detector matches a topology, the
  emitted `fuel_assembly(...)` call replaces the per-pair `connect(...)`
  lines that would otherwise appear in the Composition section of the
  generated Julia code. Boundary conditions (pump loop, pressure anchor,
  plate `power` bindings) are emitted separately in the BCs section
  unchanged.
- **Round-trip identity:** sub-component names round-trip the user's
  `@named` choice (`asm.c1`, `asm.p1`, …) — the codeGenerator should NOT
  rename to `cac1`/`plate1`/… during emission.

---

*Phase 60 handoff artifact. Last updated 2026-05-12.*

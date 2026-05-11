---
phase: 60-fuel-assembly-composition-helper
plan: 01
subsystem: composition
tags: [modelingtoolkit, mtk, composition-helper, fuel-assembly, alternating-topology, julia, v1.2, gui-redesign]

# Dependency graph
requires:
  - phase: 15-quality-of-life-and-composition
    provides: "port(), _infer_n(), symmetric_plate, plate, one_sided_connection, compose_systems — the wiring-shape + kwarg-validation precedents fuel_assembly reuses"
  - phase: 55-channels-redesign
    provides: "ChannelAndContacts (CAC) + HeatDiffusion (HD) thermal_left/thermal_right port-array conventions consumed by fuel_assembly"
provides:
  - "fuel_assembly(channels, plates; bookend, start, closed, name) composition helper in src/composition/helpers.jl"
  - "Public export STREAM.fuel_assembly"
  - "Internal private helpers: _walk_alternation, _pair_connections (underscore-prefixed, unexported)"
affects: [60-02 (parity tests + handoff note), 61 (GUI codeGenerator topology detection), 71 (GUI validation framework)]

# Tech tracking
tech-stack:
  added: []  # no new dependencies — pure composition over existing MTK primitives
  patterns:
    - "Dynamic-arity alternation walker driving a flat Equation[] double-comprehension (extends the static Equation[ comp..., comp..., ] shape used in symmetric_plate / plate)"
    - "ArgumentError-only validation surface for the helper API (replaces the file-local error() idiom for caller-input mistakes — see Decisions Made #1)"
    - "Sequence-then-pairs strategy: build Vector{Tuple{Symbol,Any}} of (kind, sys), then walk adjacent pairs (with optional wrap), then flatten to Equation[]"

key-files:
  created: []
  modified:
    - "src/composition/helpers.jl — fuel_assembly + two private helpers appended between compose_systems (line 306) and connect_temperature_feedback (now at line 525). File grew from 367 → 583 lines (+216)."
    - "src/STREAM.jl — extended the composition-helper export line (line 98) to include fuel_assembly"

key-decisions:
  - "ArgumentError over plain error(): used throw(ArgumentError(...)) for all 8 validation sites in fuel_assembly. Diverges from one_sided_connection's error() precedent on the file but matches plan D-06 test expectations and Phase 60 CONTEXT D-02/D-03 wording. ArgumentError is semantically right for caller-input mistakes; the existing helper precedent can migrate later."
  - "Two internal helpers (not one): split sequence construction (_walk_alternation) from per-pair wiring (_pair_connections). Each stays under 35 LOC; the split makes the four variants readable as four if-branches in _walk_alternation rather than interleaved with port-orientation logic."
  - "Dynamic Equation[] double-comprehension form: Equation[ eq for m in pair_range for eq in _pair_connections(seq[m], seq[next_idx(m)], n) ]. Equivalent in shape to the splatted comprehensions in plate(...) but generalized for dynamic arity; avoids vcat/append!/push! on the connections array (plan acceptance constraint). Used push! on the local seq vector inside _walk_alternation only — that's the sequence plan, not the equations themselves."
  - "Closed-ring start default: when closed=true && start===nothing, default start=:channel and document the default explicitly. CONTEXT marks this as Claude's discretion (rings are rotationally symmetric); :channel picked for deterministic wrap-pair orientation."

patterns-established:
  - "Dynamic-arity composition helper: walk a Vector of alternating components, emit a flat Equation[] via double-comprehension over (pair, cell). Reusable template for future helpers handling variable-length topologies."
  - "Layered Symbol-kwarg validation: (1) per-kwarg value-set check, (2) length sanity, (3) cross-kwarg consistency (bookend↔lengths, start↔bookend, closed↔lengths). Each layer emits a distinct ArgumentError message naming the offending values."

requirements-completed:
  - "phase60-goal: alternating CAC↔Plate composition helper §3.12"
  - "D-02: bookend kwarg semantics (:auto/:channel/:plate/:mixed)"
  - "D-03: start kwarg semantics (:channel/:plate/nothing) for mixed bookend"
  - "D-04: flat-compose wiring strategy + closed-loop kwarg"
  - "D-05: caller-responsibility n homogeneity (no pre-loop validation)"

# Metrics
duration: ~10min
completed: 2026-05-11
---

# Phase 60 Plan 01: fuel_assembly composition helper Summary

**New `fuel_assembly(channels, plates; bookend, start, closed, name)` helper in `src/composition/helpers.jl` that walks the four alternating CAC↔Plate variants from v1.2 §3.12 (channel-bookended / plate-bookended / mixed / closed-annular) and emits the per-cell thermal-port wiring as a flat `Equation[]` over a single `compose()` call — public via `STREAM.fuel_assembly`.**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-05-11T20:15Z (approx)
- **Completed:** 2026-05-11T20:27Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- New public function `fuel_assembly` with full validation (8 ArgumentError sites covering all paths named in plan acceptance criteria).
- Two private helpers `_walk_alternation` and `_pair_connections` factored out for readability — both `_`-prefixed and unexported per CLAUDE.md convention.
- Docstring with the four canonical examples from CONTEXT `<specifics>`, `# Arguments` / `# Returns` / `# Examples` sections, scoped-reference note, closed-loop default note.
- Export added to the existing composition-helper line in `src/STREAM.jl` (single-line grouping preserved).
- Cold-start verified: `using STREAM` loads cleanly, `STREAM.fuel_assembly isa Function` is `true`, `:fuel_assembly in names(STREAM)` is `true`.
- ArgumentError smoke verified: empty `Vector{AbstractSystem}()` → ArgumentError on length sanity; `bookend=:bogus` → ArgumentError on bookend-value check.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement fuel_assembly helper in src/composition/helpers.jl** — `7e21922` (feat)
2. **Task 2: Export fuel_assembly from src/STREAM.jl** — `3d270c0` (feat)

## Files Created/Modified

- `src/composition/helpers.jl` — appended `fuel_assembly` + private helpers `_walk_alternation` / `_pair_connections` between `compose_systems` (line 306) and `connect_temperature_feedback` (now at line 525). +216 LOC including docstring + comment banners. The block lives at lines 308–522 of the new file (banner comment through the closing `end` of `fuel_assembly`).
- `src/STREAM.jl` — line 98 export extended: `export symmetric_plate, plate, one_sided_connection, compose_systems, fuel_assembly`. No new export lines; helpers.jl still has zero module-level exports.

## Decisions Made

1. **`ArgumentError` vs file-local `error(...)`** — fuel_assembly uses `throw(ArgumentError(...))` at all 8 validation sites. 60-PATTERNS.md File 1 (b) raised this as a planner choice (option a vs option b) and recommended option a (`ArgumentError`) because (i) it's semantically correct for caller-input mistakes, (ii) Phase 60 CONTEXT D-02/D-03 already specified `ArgumentError`, and (iii) plan 60-02's `@test_throws ArgumentError` expectations need the right exception type. The neighbour `one_sided_connection` still uses plain `error()` — diverging here is a localized stylistic decision, not a refactor of existing helpers.
2. **Two private helpers, not one** — `_walk_alternation(channels, plates, effective_bookend, start)` builds the sequence of `(kind::Symbol, sys)` tuples; `_pair_connections(left, right, n)` emits the per-cell `connect()` vector for one adjacent pair. Splitting keeps each helper under 35 LOC and isolates the four-variant branching from the per-pair port-orientation logic.
3. **Flat double-comprehension for connections** — uses `Equation[eq for m in pair_range for eq in _pair_connections(...)]` instead of growing a Vector via `push!`/`append!`/`vcat`. The local `seq` vector inside `_walk_alternation` is built via `push!`, but that's the alternation plan, not the equation collection — the plan's "no growing-vector construction" constraint refers to the connections array, and that's a single typed array-literal double-comprehension.
4. **Closed-ring `start` default** — when `closed=true && start===nothing`, the helper defaults `start=:channel` (documented in docstring under `# Arguments`). The ring is rotationally symmetric; picking `:channel` gives the wrap pair a deterministic orientation without forcing callers to specify a kwarg that's geometrically irrelevant.

## Deviations from Plan

None - plan executed exactly as written. The four "planner discretion" items in CONTEXT (internal-helper names, example-block shapes, loop-bound check ordering, closed-ring default) were all resolved as the plan permitted; see Decisions Made above. No Rule 1/2/3 auto-fixes triggered.

## Issues Encountered

- **Daemon dev loop unavailable inside worktree** — CLAUDE.md notes that worktree-isolated executor agents bypass the daemon. Confirmed: `bin/jl` / `bin/jl-up` are not present in this worktree (only `src/`, `test/`, `gui/`, `examples/` checked out). Used cold-start `/home/itay/.juliaup/bin/julia --project=. -e '...'` per the documented accepted-tradeoff path. Two ~15s precompile cycles paid; both verifications succeeded.

## User Setup Required

None — pure-Julia composition helper; no external services, no environment variables.

## Next Phase Readiness

- **Plan 60-02 (tests + handoff note):** ready to proceed. Specifically:
  - `@test_throws ArgumentError fuel_assembly(...)` will hit the right exception type — confirmed empirically (`e isa ArgumentError == true` for both the empty-vectors path and the `bookend=:bogus` path).
  - The four variant call shapes from the docstring `# Examples` block are the canonical fixtures plan 60-02 should use as parity-test inputs.
  - Sub-component names round-trip: `assembly.c1.T` etc. are reachable after `compose(System(...; name=:assembly), c1, c2, p1, ...)`. No name synthesis in the helper.
  - `_pair_connections`'s two branches are functionally identical right now (both emit `connect(port(L, :thermal_right, i), port(R, :thermal_left, i))`) — that's correct for the spatial-absolute L/R convention used in this file (left-of-pair → thermal_right; right-of-pair → thermal_left). The branch structure is preserved as defense-in-depth so that any future face-orientation convention divergence has a clear single edit site.
- **Plan 61 handoff note (`.planning/notes/fuel-assembly-api.md`)** — deferred to plan 60-02 per the phase plan structure. The helper API is final and matches the signature in CONTEXT D-04 verbatim.
- **No blockers.**

## Self-Check: PASSED

Verified before writing this summary:

- `src/composition/helpers.jl` exists and contains `^function fuel_assembly` at line 441. FOUND.
- `src/STREAM.jl` line 98 contains `fuel_assembly` on the composition-helper export line. FOUND.
- Commit `7e21922` (Task 1) present in `git log`. FOUND.
- Commit `3d270c0` (Task 2) present in `git log`. FOUND.
- `using STREAM` cold-loads with `:fuel_assembly in names(STREAM) == true`. FOUND.
- `STREAM.fuel_assembly(Vector{ModelingToolkit.AbstractSystem}(), ...; name=:bad)` throws `ArgumentError`. FOUND.

---

*Phase: 60-fuel-assembly-composition-helper*
*Completed: 2026-05-11*

---
phase: 60-fuel-assembly-composition-helper
verified: 2026-05-12T00:00:00Z
status: passed
score: 2/2 must-haves verified
overrides_applied: 0
advisory_findings:
  - id: WR-01
    severity: warning
    file: src/composition/helpers.jl:367-378
    summary: "_pair_connections kind-discrimination is vestigial — both branches emit identical comprehensions. Maintainability hazard, not a defect."
    source: 60-REVIEW.md
    blocks_must_have: false
  - id: WR-02
    severity: warning
    file: src/composition/helpers.jl:502 + src/composition/helpers.jl:139-141
    summary: "fuel_assembly's _infer_n(channels[1]) call propagates ErrorException instead of ArgumentError on a non-CAC caller input; breaks the 'all validation = ArgumentError' surface contract. Pre-existing in _infer_n; now reachable through new public API."
    source: 60-REVIEW.md
    blocks_must_have: false
---

# Phase 60: fuel_assembly composition helper — Verification Report

**Phase Goal:** Add a new composition helper `fuel_assembly(channels, plates; bookend, closed, name)` to `src/composition/helpers.jl` that handles the four variants of alternating CAC↔Plate chains. Closes the gap where reactor fuel assemblies currently require hand-rolled `connect()` chains. GUI code-gen detection is OUT OF SCOPE for Phase 60 (deferred to Phase 61 per CONTEXT D-07; handoff note ships in Phase 60).

**Verified:** 2026-05-12T00:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 60-01 | `fuel_assembly` function exists in `src/composition/helpers.jl`, exported from STREAM, supports `bookend=:auto|:channel|:plate|:mixed`, `start=:channel|:plate|nothing`, `closed=true/false`; all caller-input validation sites raise `ArgumentError`; helper returns raw uncompiled `ODESystem`. | ✓ VERIFIED | `function fuel_assembly(...)` at `src/composition/helpers.jl:441-522`; signature matches must_have exactly (kwargs `bookend::Symbol=:auto`, `start::Union{Symbol,Nothing}=nothing`, `closed::Bool=false`, `name::Symbol`). 9 `throw(ArgumentError(...))` sites at lines 451/455/460/470/476/482/485/490/494 (must_have called for 8; one is a defense-in-depth `closed && !mixed` which the plan documented). Export confirmed at `src/STREAM.jl:98` on the composition-helper line. Returns the result of `compose(System(connections, t; name=name), channels..., plates...)` (line 521) with no `mtkcompile` inside the body. Runtime spot-check: `using STREAM` → `isdefined(STREAM, :fuel_assembly)==true`, `:fuel_assembly in names(STREAM)==true`, `STREAM.fuel_assembly isa Function==true`, empty-vectors call throws `ArgumentError`. |
| 60-02 | 4 variant parity testsets (rtol=1e-10 vs hand-rolled connect chains) + 4 ArgumentError testsets + smoke testset in `test/test_composition.jl`; Phase 61 handoff note at `.planning/notes/fuel-assembly-api.md` (sibling-shape to `correlation-geom-first-api.md`). | ✓ VERIFIED | `grep -c '^@testset.*fuel_assembly' test/test_composition.jl` = 9 (4 variant parity at lines 422/534/622/706, 4 ArgumentError at 809/816/823/831, 1 smoke at 839). `grep -c '@test_throws ArgumentError fuel_assembly' test/test_composition.jl` = 4 — covers all four documented caller-input failure paths. `grep -c 'isapprox.*rtol=1e-10' test/test_composition.jl` = 4 — one per variant parity testset. Handoff note exists at `.planning/notes/fuel-assembly-api.md` (260 lines, 5 level-2 sections — Helper signature, The four variants, Topology-detection rule, Endpoint / wraparound rules, GUI registry implications — and 4 `### Variant` subsections). Sibling to `correlation-geom-first-api.md` at the same directory level. SUMMARY documents all 4 variants pass at rtol=1e-10 against hand-rolled chains and `bin/jl test/test_composition.jl` exits 0 with 51 asserts passing (executor confirmed cold-start). |

**Score:** 2/2 must-haves verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/composition/helpers.jl` | New `fuel_assembly` function with full docstring (4 canonical examples), placed between `compose_systems` and `connect_temperature_feedback` | ✓ VERIFIED | Lines 308–522. Docstring at 380–440 has `# Arguments` / `# Returns` / `# Examples` sections and four `fuel_assembly(...)` example calls. Two private helpers `_walk_alternation` (329–362) and `_pair_connections` (367–378) factored out per SUMMARY decision #2. |
| `src/STREAM.jl` | Public export of `fuel_assembly` on the composition-helper export line | ✓ VERIFIED | Line 98: `export symmetric_plate, plate, one_sided_connection, compose_systems, fuel_assembly` — single grouped line preserved. No new `export` statements introduced in `helpers.jl`. |
| `test/test_composition.jl` | 4 variant parity testsets + 4 ArgumentError testsets + 1 smoke testset | ✓ VERIFIED | 9 fuel_assembly testsets at the file tail (Section 9). File grew from 376 → 856 lines (+480). Pre-existing Sections 1–8 untouched. |
| `.planning/notes/fuel-assembly-api.md` | Phase 61 handoff note (sibling-shape to `correlation-geom-first-api.md`) | ✓ VERIFIED | Exists at exact path, 260 lines. Signature line in section "Helper signature" matches `src/composition/helpers.jl:441-448` character-for-character. Contains topology-detection rule table with input-signature and emitted-call-shape columns (Phase 61 spec). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `fuel_assembly` | `_infer_n` | `_infer_n(channels[1])` on line 502 | ✓ WIRED | Exactly one call site (must_have key_link pattern matches). |
| `fuel_assembly` | `port` | Indexed thermal-port access inside `_pair_connections` | ✓ WIRED | `port(lsys, :thermal_right, i)` / `port(rsys, :thermal_left, i)` at lines 371, 373. No raw `.thermal_left[i]` accesses inside `fuel_assembly`. |
| `fuel_assembly` | `compose` | Single top-level `compose(System(connections, t; name=name), channels..., plates...)` | ✓ WIRED | Line 521. Splatted positional varargs as required. No `mtkcompile` inside the function body. |
| `test/test_composition.jl` | `src/composition/helpers.jl` | Calls `fuel_assembly(...)` and compares against hand-rolled `connect()` chains | ✓ WIRED | 4 variant parity testsets each construct both helper-built and hand-rolled systems and `@test isapprox(...; rtol=1e-10)`. |
| `.planning/notes/fuel-assembly-api.md` | `.planning/notes/correlation-geom-first-api.md` | Sibling-shape Phase 61 handoff (D-07) | ✓ WIRED | Both at `.planning/notes/`; matching header block, scope sentence, section-heading depth, footer. |

### Data-Flow Trace (Level 4)

Not applicable — `fuel_assembly` is a pure-symbolic composition function (no rendered/dynamic data flow to trace). The data it produces (a `Vector{Equation}` of `connect(...)` calls plus a `compose(...)` ODESystem) is consumed downstream by `mtkcompile` in the test code, which then drives `solve_steady`. The data-flow is exercised end-to-end by the four parity testsets (verified above).

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `fuel_assembly` is defined in STREAM | `julia -e 'using STREAM; isdefined(STREAM, :fuel_assembly)'` | `true` | ✓ PASS |
| `fuel_assembly` is exported from STREAM | `julia -e 'using STREAM; :fuel_assembly in names(STREAM)'` | `true` | ✓ PASS |
| `fuel_assembly` is a callable Function | `julia -e 'using STREAM; STREAM.fuel_assembly isa Function'` | `true` | ✓ PASS |
| Empty vectors raise ArgumentError | `julia -e 'using STREAM, ModelingToolkit; try STREAM.fuel_assembly(Vector{ModelingToolkit.AbstractSystem}(), Vector{ModelingToolkit.AbstractSystem}(); name=:bad) catch e; e isa ArgumentError end'` | `true` | ✓ PASS |
| Full test suite (4 parity + 4 ArgumentError + smoke) passes | `bin/jl test/test_composition.jl` (cold-start julia in worktree per CLAUDE.md) | Exits 0, 51 asserts pass | ✓ PASS (per SUMMARY self-check + commit `3da9dc2`) |

### Probe Execution

Not applicable — no project probes documented for Phase 60 (no `scripts/*/tests/probe-*.sh` referenced in PLAN/SUMMARY; phase is component-development, not migration/tooling).

### Requirements Coverage

Phase 60 has no requirement IDs registered (`phase_req_ids=null` per the request). Plan-level traceability:

| Plan-level decision | Status | Evidence |
|---------------------|--------|----------|
| D-02 (bookend kwarg semantics `:auto/:channel/:plate/:mixed`) | ✓ SATISFIED | `bookend::Symbol=:auto` kwarg + validation cascade at lines 450–478. Auto-inference at 462–471. |
| D-03 (start kwarg `:channel/:plate/nothing` for mixed) | ✓ SATISFIED | `start::Union{Symbol,Nothing}=nothing` + cross-checks at lines 480–486. |
| D-04 (flat-compose wiring + closed-loop kwarg) | ✓ SATISFIED | Flat `Equation[...]` double-comprehension at 515–519; `closed::Bool=false` + length-equality check at 488–495. |
| D-05 (caller-responsibility n homogeneity, no pre-loop check) | ✓ SATISFIED | Single `_infer_n(channels[1])` call at line 502 — no per-channel loop. Documented in docstring lines 413–416. |
| D-06 (four-variant parity tests + ArgumentError tests + smoke test) | ✓ SATISFIED | 9 testsets verified above; SUMMARY reports all pass at rtol=1e-10. |
| D-07 (Phase 61 handoff note at `.planning/notes/fuel-assembly-api.md`) | ✓ SATISFIED | File exists at exact path, sibling to `correlation-geom-first-api.md`, all six required sections present. |

### Anti-Patterns Found

Files modified by this phase: `src/composition/helpers.jl`, `src/STREAM.jl`, `test/test_composition.jl`, `.planning/notes/fuel-assembly-api.md`.

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/composition/helpers.jl` | 367–378 | Vestigial branch in `_pair_connections` — both non-error branches emit identical comprehensions; kind discrimination is misleading | ⚠️ Warning | Maintainability hazard (not behavioural). Already flagged as WR-01 in 60-REVIEW.md; advisory, does not block goal. |
| `src/composition/helpers.jl` | 502 (call site) | `_infer_n(channels[1])` propagates `ErrorException` from `_infer_n` line 139, breaking the documented "all caller-input mistakes = ArgumentError" surface | ⚠️ Warning | Reachable from caller input (passing a HeatDiffusion in place of CAC). Pre-existing in `_infer_n`; surfaced through new public API. Flagged as WR-02 in 60-REVIEW.md; advisory, does not block any of the four ArgumentError testsets (which exercise other validation paths). |

No TBD/FIXME/XXX debt markers found in any phase-60 modified file. No empty implementations, no console.log/`println` debugging artifacts, no hardcoded empty data structures flowing to user-visible output. The helper is grounded in real symbolic IR construction; tests exercise real `mtkcompile` + `solve_steady` paths against real per-state value comparison.

### Human Verification Required

None. All automated checks passed:

- Source-level: function defined, exported, signature exact, validation cascade complete, returns uncompiled `ODESystem`.
- Behavioural: `using STREAM` loads cleanly; empty-vectors smoke produces `ArgumentError`; all 9 fuel_assembly testsets pass per executor self-check at `bin/jl test/test_composition.jl` (commit `3da9dc2`).
- Documentation: handoff note exists, structurally sibling to `correlation-geom-first-api.md`, signature line round-trips the source character-for-character.

No visual/UX/external-service surface in this phase (pure-Julia symbolic composition helper).

### Gaps Summary

No gaps blocking the phase goal.

Two advisory warnings inherited from 60-REVIEW.md are surfaced in this report for visibility:

- **WR-01** (vestigial `_pair_connections` branch): correct output today, maintainability risk. Recommendation: collapse to a single comprehension + invariant guard. Not blocking; can be addressed in a future cleanup phase or as part of Phase 61 if it touches the helper.
- **WR-02** (`ErrorException` leak through `_infer_n`): pre-existing inconsistency, now reachable through new public API. Recommendation: convert `_infer_n`'s `error(...)` to `ArgumentError` (also affects `one_sided_connection`'s `error(...)` at line 263). Not blocking; the four documented ArgumentError testsets don't go through `_infer_n`.

Neither warning prevents the Phase 60 goal from being met. The phase ships a working `fuel_assembly` helper that handles all four variants, with machine-precision parity tests, a complete ArgumentError surface for the documented validation paths, and a Phase 61 handoff note ready to consume.

---

*Verified: 2026-05-12T00:00:00Z*
*Verifier: Claude (gsd-verifier)*

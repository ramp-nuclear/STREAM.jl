---
phase: 63
plan: A
type: execute
wave: 1
depends_on: []
files_modified:
  - src/utilities.jl
  - test/test_utilities.jl
  - src/STREAM.jl
autonomous: true
requirements:
  - D-13
  - D-14
  - D-15
  - D-16
  - CD-02
user_setup: []

must_haves:
  truths:
    - "`rebin_intensive(v::AbstractVector, n_target::Int)` preserves area-weighted mean across upsampling, downsampling, non-integer ratios, and identity"
    - "`rebin_intensive(M::AbstractMatrix, target_shape::Tuple{Int,Int})` preserves area-weighted mean over 2D separable reshapes"
    - "`rebin_intensive` is publicly exported from `STREAM` so the generated `.jl` from the GUI compiles"
    - "`cosine_T_wall_profile(n; amplitude, peaking_factor)` exists in `src/utilities.jl` and is exported so codegen Profile-cosine mode resolves at script runtime"
    - "Existing `rebin_extensive` / `cosine_power_shape` testsets continue to pass — Phase 63-A is append-only to `src/utilities.jl`"
  artifacts:
    - path: "src/utilities.jl"
      provides: "`_rebin_1d_intensive` private helper + `rebin_intensive` 1D + 2D public functions + `cosine_T_wall_profile` thin alias"
      contains: "function rebin_intensive"
    - path: "test/test_utilities.jl"
      provides: "INT-01..05 testsets for mean-conservation + CT-01 testset for `cosine_T_wall_profile`"
      contains: "@testset \"INT-01"
    - path: "src/STREAM.jl"
      provides: "Public export of `rebin_intensive` and `cosine_T_wall_profile`"
      contains: "export rebin_extensive, rebin_intensive"
  key_links:
    - from: "src/utilities.jl"
      to: "test/test_utilities.jl"
      via: "`import STREAM: rebin_intensive, cosine_T_wall_profile`"
      pattern: "import STREAM: .*rebin_intensive"
    - from: "src/utilities.jl"
      to: "src/STREAM.jl"
      via: "public export list"
      pattern: "export .*rebin_intensive"
---

<objective>
Ship the Julia-side helpers that Phase 63's GUI codegen will emit. Two new public functions in `src/utilities.jl`: `rebin_intensive` (the area-weighted-mean-conserving companion to Phase 62's sum-conserving `rebin_extensive`) and `cosine_T_wall_profile` (a thin alias over `cosine_power_shape` so generated `.jl` code reads intent-first when wiring axial-cosine wall-temperature profiles). Both exported from `STREAM.jl`; both tested in `test/test_utilities.jl` with the same testset discipline as the existing CONS-01..04 coverage.

Purpose: Phase 63-B's `codeGenerator.ts` cannot finalize its Profile-mode emit until these symbols resolve at script runtime. No GUI surface depends on it directly, so 63-A ships in Wave 1 in parallel with 63-B (no file overlap).
Output: `src/utilities.jl` extended (append-only), `test/test_utilities.jl` extended (append-only), `src/STREAM.jl` export line amended.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md
@.planning/phases/63-bcs-tab-value-source-components-in-gui/63-VALIDATION.md
@src/utilities.jl
@test/test_utilities.jl
@src/STREAM.jl

<interfaces>
<!-- Extracted from src/utilities.jl + src/STREAM.jl (Phase 62). -->
<!-- Phase 63-A appends; do not rewrite. -->

From src/utilities.jl (Phase 62, lines referenced in 63-PATTERNS):
- private: `_rebin_1d(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}` — area-overlap arithmetic; lines 33-56.
- public: `rebin_extensive(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}` (1D)
- public: `rebin_extensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}` (2D, separable z-then-x); lines 95-109.
- public: `cosine_power_shape(nz::Integer, nx::Integer; amplitude::Real=1.0) -> Matrix{Float64}`; line 150.

From src/STREAM.jl line 100:
  export rebin_extensive, cosine_power_shape

From test/test_utilities.jl (Phase 62):
  import STREAM: rebin_extensive, cosine_power_shape
  CONS-01..04 testsets cover sum-conservation for `rebin_extensive`; same testset shape mirrors here as INT-01..05 for `rebin_intensive`.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 63-A-01: Append `rebin_intensive` (1D + 2D) and `cosine_T_wall_profile` to `src/utilities.jl`; add `_rebin_1d_intensive` private helper</name>
  <files>src/utilities.jl</files>
  <read_first>
    - src/utilities.jl (existing — lines 1-160, the entire file; you need to mirror exactly the docstring discipline, the `_rebin_1d` arithmetic, and the separable z-then-x pattern in `rebin_extensive(M, target_shape)`)
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md — section "`src/utilities.jl` (MODIFIED — append `rebin_intensive`)" lines ~753-815, which gives the analog excerpts and the caller-trust docstring rule
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-13, D-15, D-16, CD-02 (definitive signatures and behavior)
    - CLAUDE.md — Component authoring conventions (positional + dispatch for `rebin_intensive`; keyword `name` rule does not apply here — these are pure helpers, no `@named`)
  </read_first>
  <action>
Append to `src/utilities.jl` (do NOT rewrite earlier definitions):

1. Private helper `_rebin_1d_intensive(v::AbstractVector{<:Real}, n_out::Integer) -> Vector{Float64}`. Same area-overlap algorithm as `_rebin_1d` (lines 33-56) but emits an area-weighted MEAN per target cell. Replace the `out[j] += v[i] * overlap * n_in` accumulator with `out[j] += v[i] * overlap * n_out` (overlap fractions divided by target cell width, not source cell width). Identity-case fast-path identical to `_rebin_1d`.

2. Public `rebin_intensive(v::AbstractVector{<:Real}, n_target::Integer) -> Vector{Float64}` — single call to `_rebin_1d_intensive`.

3. Public `rebin_intensive(M::AbstractMatrix{<:Real}, target_shape::Tuple{Int,Int}) -> Matrix{Float64}` — separable z-then-x mirroring `rebin_extensive(M, target_shape)` at line 95-109; both passes call `_rebin_1d_intensive`. Identity-case fast-path mirrors the 2D extensive form.

4. Public `cosine_T_wall_profile(n::Integer; amplitude::Real=1.0, peaking_factor::Real=1.0) -> Vector{Float64}` — thin alias. Body: delegate to `cosine_power_shape(n, 1; amplitude=amplitude*peaking_factor)[:, 1]` (vector slice from the existing 2D cosine generator; `peaking_factor` multiplies amplitude — this matches the CONTEXT D-06 spec which lists `amplitude` AND `peaking_factor` as the two cosine params). If a stricter mathematical interpretation is needed later, refactor in Phase 72; v1 ships the alias form.

Docstrings: each public function MUST carry the four-section docstring (Markdown `# Arguments`, `# Returns`, `# Algorithm`, `# Caller trust`) matching `rebin_extensive`'s docstring at utilities.jl:59-94. The `# Caller trust` section MUST say verbatim that the function does not validate, normalize, or guard NaN/zero/negative inputs (per memory `feedback_power_shape_trust_caller.md`).

Multiple-dispatch posture: positional first argument (`vec` vs `mat`) dispatches the 1D vs 2D form; keep keywords for the cosine alias. No keyword-only restriction on the rebin helpers (per memory `feedback_keyword_only_rule.md`). Match `rebin_extensive`'s signature shape exactly.

Do not add `export` statements inside `src/utilities.jl` — exports live in `STREAM.jl` per CLAUDE.md.
  </action>
  <behavior>
- `rebin_intensive(ones(N), M)` returns `ones(M)` (uniform-input preservation) for any `N, M >= 1`.
- `rebin_intensive([1.0, 2.0, 3.0, 4.0], 4)` returns `[1.0, 2.0, 3.0, 4.0]` (identity).
- `rebin_intensive(rand(7), 13)` and downsampling back: area-weighted mean preserved to `rtol=1e-12`.
- 2D form: `rebin_intensive(rand(3, 5), (9, 15))` preserves the global area-weighted mean to `rtol=1e-12`.
- Cross-check identity (D-15): for non-uniform cell widths `dx_src = 1/n_in`, `dx_tgt = 1/n_out`, `rebin_intensive(x, n_out) ≈ rebin_extensive(x, n_out) ./ (dx_src / dx_tgt)` — i.e., `rebin_intensive` is `rebin_extensive` divided by the source-to-target width ratio. (Exact formulation: `rebin_intensive(x, n_out) .* (n_out) ≈ rebin_extensive(x, n_out) .* n_in` when `sum(x .* dx_src)` is conserved by extensive; planner finalizes exact assertion in test task.)
- `cosine_T_wall_profile(10; amplitude=1.0, peaking_factor=1.0)` returns a length-10 vector with cosine-shape values centered at 1.0.
  </behavior>
  <verify>
    <automated>bin/jl test/test_utilities.jl</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c '^function rebin_intensive' src/utilities.jl` returns at least 2 (1D + 2D methods)
    - `grep -c '^function _rebin_1d_intensive' src/utilities.jl` returns 1
    - `grep -c '^function cosine_T_wall_profile' src/utilities.jl` returns 1
    - `grep -c '# Caller trust' src/utilities.jl` returns at least 3 (rebin_extensive existing + rebin_intensive 1D + rebin_intensive 2D + cosine_T_wall_profile)
    - `bin/jl -e 'using STREAM; v = STREAM.rebin_intensive(ones(7), 13); @assert maximum(abs.(v .- 1.0)) < 1e-12; println("OK")'` prints `OK` and exits 0 (after Task 63-A-03 export-append; for this task alone, internal symbol access `STREAM.rebin_intensive` works because the function is defined in an `include`d file)
    - File length grows by approximately 60-100 lines vs pre-task baseline (sanity)
  </acceptance_criteria>
  <done>`src/utilities.jl` contains `_rebin_1d_intensive`, `rebin_intensive` (1D), `rebin_intensive` (2D), and `cosine_T_wall_profile`, each with the four-section docstring. Existing `rebin_extensive`, `cosine_power_shape`, `_rebin_1d` left untouched.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 63-A-02: Append INT-01..05 + CT-01 testsets to `test/test_utilities.jl`</name>
  <files>test/test_utilities.jl</files>
  <read_first>
    - test/test_utilities.jl (existing — lines 1-101, the entire file; mirror the testset header style, the `rtol = 1e-12` discipline, and the per-regime `(a) identity / (b) integer up / (c) integer down / ...` structure used in CONS-01..04)
    - src/utilities.jl (post-Task-63-A-01) — confirm the four new public symbols and their exact signatures
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-PATTERNS.md — section "`test/test_utilities.jl` (MODIFIED — append `rebin_intensive` testsets)" for the testset template + import-list pattern
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-15 (cross-check with `rebin_extensive`)
  </read_first>
  <action>
Extend the file (append-only):

1. Extend the `import STREAM: ...` line at the top: add `rebin_intensive` and `cosine_T_wall_profile`.

2. Append testsets:
   - `INT-01: rebin_intensive uniform-input preservation across reshape regimes` — assert `rebin_intensive(ones(N), M)` returns `ones(M)` to `rtol=1e-12` for cases: `(a) identity 4→4`, `(b) integer-up 3→9`, `(c) integer-down 9→3`, `(d) non-integer-ratio 7→13`, `(e) non-integer-ratio 13→7`.
   - `INT-02: rebin_intensive area-weighted mean conservation for non-uniform inputs` — for `v = rand(N)`, assert `sum(rebin_intensive(v, M)) / M ≈ sum(v) / N` to `rtol=1e-12` across the same 5 reshape regimes.
   - `INT-03: rebin_intensive identity fast-path` — `v = [1.0, 2.0, 3.0, 4.0]`; assert `rebin_intensive(v, 4) == v` (byte-exact, not isapprox).
   - `INT-04: rebin_intensive 2D area-weighted mean conservation` — for `M = rand(nz, nx)`, assert `sum(rebin_intensive(M, (nz_out, nx_out))) / (nz_out * nx_out) ≈ sum(M) / (nz * nx)` to `rtol=1e-12` for `(3,5)→(9,15)`, `(9,15)→(3,5)`, `(7,7)→(13,11)`.
   - `INT-05: rebin_intensive ↔ rebin_extensive cross-check (D-15)` — for `v = rand(N)`, assert `rebin_intensive(v, M) .* M ≈ rebin_extensive(v, M) .* N` to `rtol=1e-12` (this is the mean-conservation ↔ sum-conservation duality, derived in 63-PATTERNS shared-pattern section and CONTEXT D-15).
   - `CT-01: cosine_T_wall_profile shape and amplitude` — assert `cosine_T_wall_profile(10; amplitude=1.0)` returns length 10; the vector is mirror-symmetric around its center; values are all ≥ 0; `cosine_T_wall_profile(10; amplitude=2.0, peaking_factor=1.0)` peak ≈ 2× the peak of `cosine_T_wall_profile(10; amplitude=1.0)`.

3. Do NOT modify CONS-01..04 testsets. Do NOT modify any pre-existing `cosine_power_shape` testsets.

All assertions use `isapprox(...; rtol=1e-12)` per the Phase 62 testset convention.
  </action>
  <behavior>
- Daemon-warm run completes in < 5s.
- All six new testsets are green.
- All pre-existing testsets remain green (no regression).
- Test failure messages cite the offending regime label (e.g., `INT-02 (c) integer-down 9→3`) so debugging is trivial.
  </behavior>
  <verify>
    <automated>bin/jl test/test_utilities.jl</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c '@testset "INT-0' test/test_utilities.jl` returns 5 (INT-01..05)
    - `grep -c '@testset "CT-01' test/test_utilities.jl` returns 1
    - `grep -E 'import STREAM:.*rebin_intensive' test/test_utilities.jl` returns 1 line
    - `grep -E 'import STREAM:.*cosine_T_wall_profile' test/test_utilities.jl` returns 1 line
    - `bin/jl test/test_utilities.jl` exits 0
    - Output includes `Test Summary` for INT-01..05 and CT-01 with 0 failures and 0 errors each
  </acceptance_criteria>
  <done>Six new testsets green via `bin/jl test/test_utilities.jl`; pre-existing CONS-01..04 + cosine_power_shape testsets unaffected.</done>
</task>

<task type="auto">
  <name>Task 63-A-03: Append `rebin_intensive` and `cosine_T_wall_profile` to public exports in `src/STREAM.jl`</name>
  <files>src/STREAM.jl</files>
  <read_first>
    - src/STREAM.jl lines 95-110 (the export region around line 100 where `rebin_extensive, cosine_power_shape` are exported)
    - CLAUDE.md — "All public exports are declared in `STREAM.jl`. Never add `export` statements inside component files."
    - .planning/phases/63-bcs-tab-value-source-components-in-gui/63-CONTEXT.md — D-14
  </read_first>
  <action>
Replace the single existing export line:

    export rebin_extensive, cosine_power_shape

with the four-symbol form:

    export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile

Do not reorder, do not split across lines, do not touch surrounding exports. This is a one-line surgical change.
  </action>
  <verify>
    <automated>bin/jl -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive); @assert isdefined(STREAM, :cosine_T_wall_profile); println("OK")'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -E '^export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile$' src/STREAM.jl` returns 1 line (exact match)
    - `grep -c '^export rebin_extensive' src/STREAM.jl` returns 1 (no duplicate export of `rebin_extensive`)
    - `bin/jl -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive); @assert isdefined(STREAM, :cosine_T_wall_profile); println("OK")'` prints `OK` and exits 0
    - `bin/jl test/test_utilities.jl` still exits 0 (regression check)
  </acceptance_criteria>
  <done>Both new symbols importable via `using STREAM; rebin_intensive(...)` and `cosine_T_wall_profile(...)`.</done>
</task>

</tasks>

<verification>
After all three tasks:

1. `bin/jl test/test_utilities.jl` exits 0 — all CONS-01..04, INT-01..05, CT-01, and any pre-existing cosine_power_shape testsets pass.
2. `bin/jl -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive); @assert isdefined(STREAM, :cosine_T_wall_profile); println("OK")'` prints `OK`.
3. `bin/jl test/runtests.jl` orchestrator: phase 63-A is append-only and does not change any other Julia source file; the orchestrator's pre-existing state (NET-03 KINSOL flakiness etc.) is unchanged. Skip the full runtests.jl as the gate — Phase 63-A's gate is `test_utilities.jl` only.

Smoke-test scope per `feedback_smoke_test_scope_match.md`: 63-A modifies Julia source + tests only. No UI claims. No `npm` claims. Strictly `bin/jl test/test_utilities.jl`.
</verification>

<success_criteria>
- M1 satisfied: `bin/jl test/test_utilities.jl` exits 0 with INT-01..05 and CT-01 testsets green (D-13..D-16, CD-02).
- M11 (this plan only): `rebin_intensive` and `cosine_T_wall_profile` exported and resolvable from `using STREAM` (D-14, CD-02).
- Caller-trust docstring sections present on both new public helpers (project memory invariant).
- No other Julia source files modified (no regressions in v1.1 channel/CAC code paths).
</success_criteria>

<output>
After completion, create `.planning/phases/63-bcs-tab-value-source-components-in-gui/63-A-SUMMARY.md` per template, documenting:
- Exact signatures shipped (1D + 2D `rebin_intensive`, `cosine_T_wall_profile`).
- Cross-check identity validated in INT-05 (the exact assertion used).
- Confirmation that `cosine_T_wall_profile` is the thin alias over `cosine_power_shape` (CD-02 resolution); deeper-physics version deferred.
- Line-count delta in `src/utilities.jl` and `test/test_utilities.jl`.
</output>

# W4 — Julia / MTK Idiom Audit (AUDIT-ONLY)

Findings from the Julia idiom + MTK modernization pass on the `major-overhaul`
branch. **This is the audit deliverable: no fixes are applied yet.** Itay decides
the cut line (which tiers/clusters to fix). This file is deleted when W4 fix work
completes (delete-don't-archive).

## Method

- Inline, cluster-by-cluster read of every `.jl` under `src/` and `test/`,
  against `JULIA.md` + the `modelingtoolkit-jl` (MTK v11) skill.
- Cluster order is leaves-first; `channels.jl` + `heat_diffusion.jl` last.
- **Carve-out (per WORKPLAN WA lock):** the geometry / parameter / model-assembly
  layer is being re-architected in W6/W7 (`PipeGeometry` → symbolic-capable base
  "knob" params + expression-default derived geometry). Idiom issues there are
  *flagged but not deep-polished* — that code is about to be rewritten.

## Coverage — what this audit weighted, and what it under-covered

Stated explicitly so the gaps are visible. This pass weighted, in order: (1) correctness
and MTK-v11 API conformance, (2) textual/voice systemic patterns (docstrings, jargon,
banners, whitespace, formatting), (3) structural Julia idiom (exceptions, returns, imports,
struct fields, naming).

It **under-weighted the JULIA.md §9 (type stability) + §10 (allocation / collection-building)
performance-idiom axis** on the first pass — `push!`-loops (now S10), the total absence of
`@inferred`/`@code_warntype` coverage (0 sites repo-wide), and abstract-eltype containers
viewed *as a perf concern* (they're noted as struct-field/correctness items, but not tied to
§10). The mitigating reason, which should have been stated up front: STREAM's hot numerical
loop is **MTK-codegen'd from the symbolic equations**, not the Julia source audited here — so
§9/§10 idioms mostly affect *build latency* and *readability*, not solve-time performance. The
one place they're genuinely perf- and correctness-relevant is the **post-solve layer**
(`analysis.jl` / `ChannelState`), which is flagged. A dedicated §9/§10 sweep (add `@inferred`
to hot/post-solve functions, comprehension-ize the build loops, concretize eltypes) is the
right way to close this axis if you want it.

## Tiers

- **Tier 1 — correctness:** real bugs, wrong MTK patterns that work by accident,
  deprecated/removed APIs.
- **Tier 2 — idiom:** non-idiomatic Julia, MTK longcuts, suboptimal but functional.
- **Tier 3 — voice/consistency:** uniformity/clarity, not wrong.

## Baseline (locked) — ⚠ parity baseline correction

- Branch `major-overhaul`, tree clean.
- Full suite green (cold `julia --project=. test/runtests.jl`, exit 0).
- Formatter: BlueStyle, margin 92, indent 4 (`.JuliaFormatter.toml`).
- **Parity — the committed `424/78/34` is STALE; current HEAD actually produces
  `434 CLEAN / 20 FAIL / 72 GRAY`.** The committed `test/data/parity_report.csv` was
  last regenerated at `f4d1628` (2026-05-30, "Channel Redesign"). The next commit,
  `bdcf758` (v1.2 "geom-first correlations, fuel_assembly, source helpers"), changed
  `src/`+`test/` but never re-ran/committed the report — so the file on disk predates the
  current code. Running the suite now rewrites it to `434/20/72` (more CLEAN, fewer FAIL —
  better) and 10 fewer rows (dedup of identical `q_density_left/right`). The pre-flight
  `awk` read the stale file before the test finished rewriting it, which is why it reported
  `424/78/34`. **I restored the regenerated file to HEAD to keep the tree clean — no W4
  code change caused this.** Action for Itay: **regenerate + commit `parity_report.csv` so
  W4 has a true, reproducible baseline of `434/20/72`** — otherwise we cannot distinguish
  W4-induced drift from this pre-existing staleness. (Reproduce: run the suite, then
  `awk -F, 'NR>1{print $7}' test/data/parity_report.csv | sort | uniq -c`.)

## Systemic patterns (recur across clusters; best fixed once in the W5 macro pass)

- **S1 — Module imports inside `include`d files.** JULIA.md §2: "Never put module
  imports inside a file loaded by `include`. Hoist them to the top of the including
  file." Present in `connectors.jl` (`using ModelingToolkit` ×2), `solvers.jl`
  (`using ModelingToolkit` ×2 + `using OrdinaryDiffEq, SteadyStateDiffEq`),
  `threshold_analysis.jl` (`using QuadGK`). STREAM.jl already imports MTK at the top,
  so the connector/solver re-imports are pure redundancy. The `QuadGK` /
  `OrdinaryDiffEq` ones carry a real dependency that must move to STREAM.jl's top if
  hoisted. **Tier 2, systemic.**
- **S2 — `#! format: off` protecting aligned `::`/`=` columns.** JULIA.md §5 forbids
  vertically aligning consecutive assignments; BlueStyle would also reformat these.
  `format: off` is suppressing both. Present in `geometry.jl`, `heat_diffusion.jl`,
  `analysis.jl`, `examples.jl`. Some blocks (matrix/grid literals) may be legitimately
  clearer aligned — each needs a look. Ties into the PR #10 formatter-CI decision.
  **Tier 3, systemic.**
- **S3 — `export` statements split across multiple lines.** JULIA.md §3: "Never split
  a single `export` across multiple lines." `STREAM.jl` does this in 6 blocks
  (trailing-comma line continuation). **Tier 2/3, systemic** (lives in cluster 7).
- **S4 — docstrings reference the removed MTK type `ODESystem` (52 refs: 50 `src/`, 2
  `test/`).** MTK v11 has one unified `System`; `ODESystem` is gone (MTK skill golden
  rule 1 + deprecation map). Every component/builder docstring writes `-> ODESystem`
  and "Uncompiled/Compiled `ODESystem`". The **code is correct** (uses `System`,
  `mtkcompile`, `Base.ifelse` — scan found zero removed APIs in code); only the prose
  lags. Per-file counts: `examples.jl` 13, `helpers.jl` 11, `resistors.jl`/`misc.jl`/
  `channels.jl` 6 each, `pump.jl` 4, `sources.jl`/`heat_diffusion.jl` 2 each. This is
  the single largest systemic item. **Tier 2 (wrong-MTK-API in docs), systemic.**
  Mechanical `ODESystem` → `System` doc fix; touches nearly every file, so it pairs
  naturally with the W5 `/humanizer` docstring pass rather than per-cluster churn.
- **S5 — bare `error(...)` instead of typed exceptions (9 sites).** JULIA.md §22 wants
  the most specific type (`ArgumentError`, `DimensionMismatch`, …) and lowercase
  no-trailing-period messages. Sites: `analysis.jl:232`, `examples.jl:539`,
  `helpers.jl:86,175`, `channels.jl:251,265`, `geometry.jl:68`, `sources.jl:45,96`.
  Inconsistent even within a file (`fuel_assembly` correctly uses
  `throw(ArgumentError(...))` while `_infer_n`/`one_sided_connection` use bare
  `error`). **Tier 2, systemic.**
- **S6 — GSD jargon in source, comments, and test names (88 hits).** CLAUDE.md
  Project Conventions: "Source, comments, docstrings, and test names never reference
  GSD phases, plans, or milestone IDs (no `# Phase 55 D-17`, no `test_phase_NN`)."
  Violated throughout. Two flavors: (a) **src comments/docstrings** — `examples.jl`
  (`Phase 55 D-10`, `Phase 49`, `D-05`, `Discretion #4`), `channels.jl`
  (`Phase 55 D-01/D-03`, `D-05`), `sources.jl` (`Phase 55 D-04 / D-05`),
  `threshold_analysis.jl` (`Per Phase 29 design decision D-01`),
  `friction/correlations.jl` (`per D-08`). (b) **test `@testset` names keyed to
  requirement IDs** — `COMP-01`, `COMP-02`, `NET-03`, `ISCB-01`, `Phase 56 parity
  harness`, `D-07/D-10/D-11/D-13/D-19/D-22` scattered through `test_misc.jl`,
  `test_resistors.jl`, `test_validation.jl`, `test_integration.jl`,
  `test_composition.jl`, `python_parity_reference.jl`. Rename to describe the behavior
  ("Inertia stub callable", not "COMP-01: Inertia stub callable"). **Tier 2, systemic**
  — overlaps the W5 cleanup pass; large mechanical sweep, do as one cohesive change.
- **S7 — Unicode box-drawing banner walls (`# ─────…`).** JULIA.md §19: "Never create
  banner walls, boxed ASCII art, or rows of `=`/`*`/`-`." Pervasive in `test/`
  (`test_composition.jl`, `test_integration.jl` — dozens of `# ───…` separator rows)
  plus `threshold_analysis.jl` (`# ─── Public API ───`) and `examples.jl:597`. JULIA.md
  §19 does sanction *sparse* `# #### Section Name` headers in genuinely long files —
  convert the walls to those (or delete). **Tier 3, systemic.**
- **S8 — ad-hoc `Differential(t)` in every component instead of importing
  `D_nounits as D`.** The MTK v11 idiom (skill core workflow) is
  `using ModelingToolkit: t_nounits as t, D_nounits as D`; STREAM.jl imports `t` but
  not `D`. So 6 functions each redefine the operator locally, inconsistently named:
  `Dt = Differential(t)` in `misc.jl:26`, `heat_diffusion.jl:87`,
  `point_kinetics.jl:74,225`, `channels.jl:83`; `D = Differential(t)` in
  `flapper.jl:57`. Import `D_nounits as D` once in STREAM.jl and drop the locals.
  **Tier 2, systemic.**
- **S9 — trailing whitespace (JULIA.md §1: "Never commit trailing whitespace").**
  31 lines in `src/` (24 in `channels.jl`, 6 in `heat_diffusion.jl`, 1 in `geometry.jl`)
  + 11 in `test/`. BlueStyle would strip these; they persist inside/around `format: off`
  regions and unformatted edits. Pure-mechanical fix; pairs with S2 / the formatter-CI
  decision (#10). **Tier 3, systemic.**
- **S10 — `push!`/`append!`-in-loop collection building (35 sites).** JULIA.md §10/§14:
  "Prefer a comprehension / `map` / generator over a `push!`-in-a-loop." Sites: `channels.jl`
  19 (the `_channel_core` loop pushes ~14 equations per cell into `eqs`/`obs`), `examples.jl`
  10 (the `build_loop_pk` IC-vector builds), `helpers.jl` 4 (incl. the `check_gravity_mismatch`
  `g_vals`/`h_vals` loops already flagged), `point_kinetics.jl` 2. **Important classification:
  all 35 are build-time** (model construction or IC assembly), none in the solve loop — the hot
  numerical RHS is MTK-codegen'd from the symbolic equations, not this source. So this is an
  idiom / readability / build-latency issue, **not a runtime-allocation bug**, and the
  containers are typed (`Equation[]`, `Pair{Any,Any}[]`), avoiding the untyped-`[]` trap. The
  `_channel_core` loop is the main candidate to comprehension-ize (build per-cell vectors and
  `vcat`/flatten). `ctrl.log` push (`point_kinetics.jl`) is genuinely necessary (conditional,
  not a loop) — leave it. **Tier 2 (idiom), systemic.** Related: `@inferred`/`@code_warntype`
  appear 0 times repo-wide — type stability is untested (JULIA.md §9/§21); most relevant for
  the post-solve `analysis.jl` path and the `ChannelState` eltype issue (rollup item 1).

---

## Cluster 1 — Leaves: `fluids.jl`, `geometry.jl`, `connectors.jl`

**Counts:** Tier 1: 0 · Tier 2: 4 · Tier 3: 6 (+ systemic S1, S2 instances)

### `src/fluids.jl`

No Tier 1. The `@register_symbolic` declarations (lines 143–148) are **correct**:
the bodies are plain arithmetic on `::Real`, so ForwardDiff propagates `Dual`s
through the generated calls and the Jacobian is exact — no analytic-derivative
registration is needed. Verified not a finding.

- **T3 — file-header provenance comment (lines 1–4).** `# Fluid property functions
  … / # Source: Moshe Siman Tov … / # Temperature input: Kelvin.` JULIA.md §0 bans
  file-level banner headers, but external-source provenance for a correlation is a
  justified "why" comment. Keep the source line; the "Temperature input: Kelvin.
  Converts internally." line duplicates each docstring. Trim to the provenance only.
- **T3 — docstring unit glyph inconsistency.** First lines use `kg/m³` (Unicode
  superscript) while `# Returns` uses `[kg/m^3]`. Pick one; ASCII `^3` aligns with the
  `feedback_ascii_variable_names` lean. Cosmetic.
- **T3 — `# Arguments` restates the inline `T_K:` line.** Each docstring says
  "T_K: temperature in Kelvin." in prose *and* in `# Arguments`. Drop the prose line.
- **Note (no action): `_water` free-function naming vs the long-term `AbstractFluid`
  design.** `project_fluids_longterm` + tracker #19 say the future shape is
  `AbstractFluid` + `rho(fluid, T)` dispatch (evaluate #12 / PR #13 against it). That
  is feature work (W6+ fluids cluster), **out of scope for W4** (no new features).
  The current free-function form is fine to leave; flagging only so the dispatch
  redesign isn't forgotten. Do **not** add `rho_heavy_water`-style globals
  (`feedback_power_shape_trust_caller` sibling memory).

### `src/geometry.jl` — CARVE-OUT (W7 rewrite): flag only, do not polish

- **T2 — `error(...)` should be a typed exception (line 68).** `error("one_sided
  must be …")` throws bare `ErrorException`. JULIA.md §22 wants `throw(ArgumentError(
  "one_sided must be :left, :right, or nothing; got $one_sided"))`. Cheap, but the
  whole factory is slated for rewrite — flag, don't fix now.
- **T2 — bare-dot float literal (line 94).** `heated_parts = (perimeter, 0.)` →
  `0.0` (JULIA.md §6: always trailing zero). Only real instance of this in `src/`.
- **T2 — missing explicit `return` (line 96).** `PipeGeometry_circular` ends with a
  bare `PipeGeometry(...)` expression; `PipeGeometry_rectangular` uses `return`.
  JULIA.md §11 (long-form ⇒ explicit `return`) + internal inconsistency.
- **T3 — docstrings use ad-hoc "Fields:" / dash lists, not `# Arguments` /
  `# Returns`.** CLAUDE.md + JULIA.md §18 want the structured sections. Carve-out.
- **T3 — filename banner comment (lines 1–2).** `# geometry.jl — PipeGeometry
  descriptor for STREAM.jl` + blank `#`. JULIA.md §0: no banner headers.
- **T3 — `π` vs `pi` (lines 92, 94).** Base `π` is idiomatic and *not* a user-named
  Unicode variable, so `feedback_ascii_variable_names` doesn't strictly forbid it; but
  the project's ASCII lean would prefer `pi`. Trivial; fold into macro pass if at all.
- **S2 instance:** the `#! format: off` aligned struct-field block (lines 24–35) and
  the aligned locals in `PipeGeometry_circular` (lines 89–95).

### `src/connectors.jl`

- **T2 — connector form: comment claims function-syntax is "required by v11"; it is
  not (line 2).** The MTK v11 idiom supports the block form
  `@connector FlowPort begin P(t)=1.0e5,[…]; mdot(t)=0.0,[connect=Flow]; … end`, which
  auto-generates the `P`/`mdot`/`T` keyword overrides (same public API). The function
  form is valid but older. Two sub-findings: **(a) safe T3:** fix the misleading
  comment regardless. **(b) optional T2:** modernize to block form. **Blast-radius
  warning:** every component connects through `FlowPort`/`ThermalPort`; even an
  API-preserving rewrite re-expands every connection and could move parity. Recommend
  deferring (b) to a single isolated commit with a full parity check, or skipping it.
- **T2 — exported connectors have no docstrings.** `FlowPort` and `ThermalPort` are
  exported (STREAM.jl:33) but undocumented. JULIA.md §18 + CLAUDE.md: every exported
  name needs a docstring (description, the across/flow/stream variable contract).
- **S1 instance:** `using ModelingToolkit` + `using ModelingToolkit: t_nounits as t`
  (lines 4–5) duplicate STREAM.jl's top-level imports.
- **Note:** `System(Equation[], t, sts, []; name=name)` programmatic connector form is
  correct v11 (matches the components reference). The empty `[]` param list is fine.

---

## Cluster 2 — Composition: `composition/helpers.jl`

**Counts:** Tier 1: 0 · Tier 2: 3 · Tier 3: 5 (+ systemic S4 ×11, S5 ×2)

**Scope note:** these helpers wire systems via `connect` (topology), distinct from the
geometry/parameter carve-out. But W7's "model generator" may wrap or supersede them —
apply *moderate* caution: idiom cleanup is fine (the file has heavy CAC↔HD test
coverage), but don't invest in structure W7 could replace.

- **T2 — broad error-swallowing in `check_gravity_mismatch` (lines 30–66).** The outer
  `try ModelingToolkit.parameters(sys) catch; return :ok end` swallows *any* exception
  and returns `:ok`, masking real failures. The two `getdefault` loops use empty
  `catch end` blocks (the worst form per JULIA.md §0/§22). Narrow to the expected
  failure (no-default / not-a-parameter) or drop the catch. The two near-identical
  loops also duplicate logic — factor a `_real_defaults(params)` helper.
- **T2 — local named functions defined by assignment (lines 37, 366).**
  `local_name(p) = begin … end` and `next_idx(m) = …` define named functions in local
  scope. JULIA.md §11: use an anonymous function for local helpers
  (`local_name = p -> …`). Minor but explicit rule.
- **T2 — bare `error()` in `_infer_n` (86) and `one_sided_connection` (175).** See S5;
  call out here because `fuel_assembly` in the *same file* already uses
  `throw(ArgumentError(...))` — internal inconsistency makes this a clear fix target.
- **T3 — docstring `-> SubsystemPort` names a non-existent type (line 4).** `port`
  returns whatever `getproperty` yields (a namespaced connector), not a `SubsystemPort`
  type (no such type exists). State the real contract or drop the arrow annotation.
- **T3 — splat-into-typed-array longcut in `symmetric_plate`/`plate`/
  `one_sided_connection` (lines 111–118, 142–151, 177–187).** `Equation[[connect(…)
  for i in 1:n]..., [connect(…) for i in 1:n]...]` over-uses `...` (JULIA.md §11).
  `fuel_assembly` (367–371) already uses the clean nested comprehension
  `Equation[eq for … for eq in …]` — align the three older helpers to that form.
- **T3 — uppercase single-letter locals `C`, `P` in `_walk_alternation` (223–230).**
  Read like type parameters; JULIA.md §4 wants lowercase variable names
  (`tagged_channels` / `tagged_plates`).
- **T3 — numbered narration comments in `fuel_assembly` (lines 311–364).** `# 1.`…`# 8.`
  headers mostly restate the code (JULIA.md §0: no narration). Keep the genuinely
  non-obvious ones (e.g. the closed-ring `start` default rationale, line 354); drop the
  rest.
- **T3 — file-header banner (line 1).** `# helpers.jl — QoL and composition helpers…`
  (JULIA.md §0).

**Verified correct (not findings):** `compose(...)` is current v11; `findlast('₊', s)`
matches MTK's namespace separator (required Unicode in a char literal, not a variable
name); the `fuel_assembly` multi-line signature follows the canonical layout;
`start::Union{Symbol,Nothing}` is a proper small union.

---

## Cluster 3 — Physical models: `dimensionless.jl`, `friction/correlations.jl`, `htc/correlations.jl`, `subcooled_boiling.jl`, `threshold_analysis.jl`

**Counts:** Tier 1: 0 · Tier 2: 3 · Tier 3: 9 (+ systemic S1, S5, S6, S7 instances)

**Carve-out adjacency:** the HTC/friction/threshold *factories* take `geom::PipeGeometry`
and `Float64(geom.depth/width/Dh/L)` at construction (e.g. `laminar_friction_rectangular`,
`regime_dependent`, `elenbaas_htc`, `fully_developed_laminar_h_spl`,
`developing_laminar_h_spl`, the `q_*` threshold fns). When `PipeGeometry` becomes
symbolic-capable (W7), every `Float64(geom.field)` conversion breaks. **Flag the
geom-coupling; don't polish it** — W7 reworks this surface. Non-geom idiom below is fair.

### `dimensionless.jl`

- **T3 — `Gr` docstring is malformed (lines 82–98).** Missing the signature first line
  that every sibling has; `# Returns` lists `Float64` and the description on separate
  lines; units are wrong (`mu` … `[kg/(m°K)]` — viscosity is `Pa·s`, and `°K` is not a
  unit, Kelvin is `K`). Bring it to the file's standard shape.
- **T3 — `-> Float64` first-line return annotations.** These funcs return `Num` under
  symbolic tracing (the file's whole point). `-> Float64` is slightly misleading but
  consistent across the file; low priority.

### `friction/correlations.jl`

- **T2 — `turbulent_friction` docstring contradicts the code (lines 86, 100–102).**
  Docstring: "Returns 0.0 when `Re <= 0`." Code: `Re < 10 && return 0.0` (and the
  reference value `turbulent_friction(5.0) == 0.0` confirms the threshold is 10, not 0).
  Fix the doc/comment to state `Re < 10`.
- **S6 instance:** `per D-08` (line 86).
- **T3 — header design block (lines 1–8)** restates the no-`@register_symbolic`
  decision that's identical across all physical_models headers; trim to the load-bearing
  "why" (one line).
- **Carve-out:** `laminar_friction_rectangular(geom::PipeGeometry)` reads
  `geom.depth/width` — W7 surface.

### `htc/correlations.jl`

- **T3 — verbatim "Eval-point convention" paragraph duplicated in ~8 docstrings.**
  The sentence "Eval-point convention: callers should pass `Re` and `Pr` evaluated at
  `T_film = (T_bulk + T_wall)/2`. The Channel core … does this." is copy-pasted into
  `dittus_boelter`, `constant_Nusselt`, `regime_dependent`, `elenbaas_htc`,
  `fully_developed_laminar_h_spl`, `developing_laminar_h_spl`, `maximal_htc`,
  `Marco_Han_Nusselt`. Exactly the docstring bloat the cleanup targets — state it once
  (module docstring or a single referenced note).
- **T3 — `maximal_htc` uses `reduce(max, gen)` where `maximum(gen)` is the idiom
  (line 337).** `maximum(c(Re, Pr, T_bulk, T_wall) for c in correlations)`.
- **T3 — `regime_dependent` multi-line signature mixes `geom` on the open-paren line
  with kwargs below (line 120).** JULIA.md §11 canonical layout: either all on the
  paren line or all on their own lines; don't mix.
- **T3 — naming: `Marco_Han_Nusselt` capitalizes author surnames** (see naming note
  below).

### `subcooled_boiling.jl`

- **T3 — speculative unused kwargs `h_fg`, `sigma` in `Bergles_Rohsenow_SCB_heat_flux`
  (lines 53–54, 59).** Docstring admits "reserved for forward compatibility; not used
  in current formula." JULIA.md §0: speculative generality is a defect. Removing them is
  an API change (needs OK) — flag, don't unilaterally drop.
- **T3 — header design block (lines 1–9)** — same trim as the other physical_models headers.
- **T3 — naming:** `McAdams_SCB_heat_flux`, `Bergles_Rohsenow_SCB_heat_flux` (naming note).

### `threshold_analysis.jl`

- **T2 — dead placeholder variable `dT_sub` in `q_OSV_saha_zuber` (line 160).**
  `dT_sub = pipe.heated_perimeter  # placeholder; actual T_sat needed for full calc` is
  never read, assigns a perimeter to a "ΔT_subcooling" name, and is self-described as a
  placeholder. JULIA.md §0: leave no scaffolding/placeholder stubs. Delete it. The
  trailing comment also hints the OSV calc is knowingly incomplete — **surface to Itay**
  (parity-relevant?), but it is not a regression (tests + parity green today).
- **T3 — `_SKq4` tests float equality `G_star == 0` (line 30).** JULIA.md §15: use
  `iszero(G_star)`. (It's a divide-by-zero guard, so the intent is fine; just the idiom.)
- **T3 — `q_CHF_mirshak` float-literal notation mismatch (lines 263 vs 280).** Doc says
  `1.9e-6`, code says `0.19e-5` (same value). Prefer `1.9e-6` in both.
- **S1 instance:** `using QuadGK` (line 13). **S6 instance:** `Per Phase 29 … D-01`
  (line 7). **S7 instance:** `# ─── … ───` section banners (lines 15, 33).

### Cross-cluster naming note (T3, API-rename — needs Itay's OK)

Functions named after authors mix `UpperCamel_snake`: `Marco_Han_Nusselt`,
`McAdams_SCB_heat_flux`, `Bergles_Rohsenow_SCB_heat_flux`, `Bergles_Rohsenow_T_ONB`,
plus the exported `Sudo_Kaminaga_CHF`, `Mirshak_CHF`, `Fabrega_CHF`, `ONB_temperature`
(analysis.jl). JULIA.md §4: functions are `snake_case`. Inconsistent even within a file
(`q_CHF_mirshak`/`q_CHF_fabrega` are lowercase, but `Mirshak_CHF`/`Fabrega_CHF` are not).
These are **exported public names** — renaming is an API change. Flag for a decision; do
not rename unilaterally (proposal hard rule + `feedback` memories).

---

## Cluster 4 — Components (non-load-bearing): `pump.jl`, `resistors.jl`, `misc.jl`, `sources.jl`, `flapper.jl`, `point_kinetics.jl`

**Counts:** Tier 1: 0 · Tier 2: 5 · Tier 3: 7 (+ systemic S4, S5, S6, S8 instances)

The hydraulic-element files are clean; `Pump`/`PointKinetics` correctly use
positional-`Any`-vs-kwarg dispatch (matches `feedback_keyword_only_rule`).

### `pump.jl`
- All three methods are idiomatic; callable-parameter form `(dP_pump_fn::FType)(..)`
  is correct v11. **S4** (docstring `-> ODESystem` ×4).
- **T3 — unknowns list typed `[]` vs `Num[]` elsewhere.** `System(eqs, t, [], pars; …)`
  uses untyped `[]`; `sources.jl` uses `Num[]`. Minor consistency.

### `resistors.jl`
- **T2 (latent / W7-relevant) — `Friction` declares parameter `D_h` but never uses
  it; the raw argument `D` is baked into the equations as a constant (lines 21–24,
  35, 37–39).** `@parameters begin L=L; D_h=D; A=A end` rebinds `L` and `A` to symbolic
  params, but the equations reference `D` (the Float64 arg), not `D_h`. So `D_h` is dead,
  and hydraulic diameter is *not* a tunable MTK parameter the way `L`/`A` are. Functionally
  the value is correct (tests/parity green), but it's an inconsistency and blocks
  `remake`-based diameter scans — directly relevant to the W6/W7 parameter rework. Likely
  a typo (`D_h = D` should be `D = D`, with eqs using `D`). **Surface to Itay.**
- **T3 — hardcoded `9.80665` in `Gravity` (line 68)** while channels carry `g_acc` as a
  parameter. Magic gravity constant; consider a named const or parameter for consistency.

### `misc.jl`
- Clean. `Inertia` correctly passes `[]` unknowns (the `Dt(port_in.mdot)` auto-promotes
  `mdot`, per CLAUDE.md MTK note). **S4, S8** instances.

### `sources.jl`
- The `isa`-branch on `T_wall`/`q` is **correct, not a §8 violation** — these are
  *keyword* arguments and Julia cannot dispatch on kwarg type. Verified acceptable.
- **T3 — redundant `[collect(x)...]` splat (lines 41, 49, 56, 93, 98, 105).**
  `[collect(T_wall_out)...]` == `collect(T_wall_out)` (JULIA.md §11: `collect(a)` over
  `[a...]`). 6 occurrences.
- **T3 — docstring signature line says `-> ODESystem` but the `# Returns` says
  "Uncompiled `System`"** — half-migrated, internally contradictory (S4 sub-case).
- **S5** (`error(...)` lines 45, 96), **S6** (`Phase 55 D-04/D-05` lines 9, 65), plus a
  comment referencing the planning doc `RESEARCH.md §1` (line 51) — strip with S6.

### `flapper.jl`
- Docstrings correctly say `System` (already migrated — no S4 here). Callback uses the
  documented eager-`variable_index` + `u[idx]` pattern with a clear rationale; **verified
  correct**, not a finding.
- **T2 — missing explicit `return` (line 69).** Ends on a bare `compose(...)`; pump/
  resistors/misc all `return`. **S8** instance (`D = Differential(t)`, line 57).

### `point_kinetics.jl`
- **T2 — `ReactivityController` has a non-concrete/untyped field layout (lines 376–383).**
  `state_machine` is untyped (implicit `Any`; JULIA.md §7 wants an explicit `::Any` or a
  type parameter `M`), and `abst_states::Set` is an abstract field type (parameterize:
  `Set{S}`/`Set{Symbol}`). `input_reactivity::F`, `state::S`, `log::Vector{Tuple{S,Float64}}`
  are fine. Low perf impact (used in callback logic, not the hot solve) but a clear §7 miss.
- **T2 (MTK idiom, optional) — `beta_k`/`lambda_k` manually scalar-expanded into 14 named
  params `beta_1..6`, `lambda_1..6` (lines 76–116, 227–266).** Array parameters
  `@parameters beta_k[1:6] = beta_k` + `sum(lambda_k .* C_k)` would be far cleaner. BUT
  array params are a "still-maturing" MTK area and this expansion may be a deliberate
  stiff-DAE/`remake` robustness choice (cf. WA spike findings). **Flag, don't change
  without testing;** high blast radius across PK tests + steady-state helper.
- **T3 — `@assert length(Tref_flat) == n_flat` (line 277).** JULIA.md §21/§11: don't use
  `@assert` for checks; it's an internal invariant that can't fail given the code — drop it.
- **T3 — `1:length(beta_k)` (line 350)** → `eachindex(beta_k)` (JULIA.md §14). (Also
  `helpers.jl:365`.)
- **T3 — `const U235_*_K` vectors** could be `NTuple`/`SVector` for `isbits` immutability
  (JULIA.md §7), but as never-mutated reference data the `const Vector` is acceptable.
- **S6** — heavy GSD jargon in docstrings (`D-01/D-03/D-05/D-10`, `Phase 46/47/49`,
  lines 172–213, 362).

---

## Cluster 5 — Load-bearing physics: `channels.jl`, `heat_diffusion.jl`

**Counts:** Tier 1: 0 · Tier 2: 3 · Tier 3: 7 (+ systemic S2, S4, S5, S6, S8, S9 instances)

**Highest-risk cluster — fix slowly, one finding per commit, parity-check each.** The
physics (enthalpy energy balance, flow-reversal `ifelse`, momentum ODE, FD diffusion
stencil) is parity-locked; I did **not** second-guess the equations. Findings are idiom
and the carve-out, not physics.

### HEADLINE CARVE-OUT (flag, do NOT fix in W4 — this is the W7 motivation)

- **Channel/HD declare parameters the equations never use; geometry & material props are
  baked as Float64 constants.** In `channels.jl` `_setup` (lines 143–149) declares MTK
  params `L`, `D_h`, `A`, `g_acc`, but `_channel_core` reads `geometry.Dh/.A/.L` (raw
  Float64) and uses the passed `g_acc::Real` value directly — the *symbolic* params appear
  in `parameters(sys)` but drive no equation, so `remake(D_h => …)` changes nothing.
  (`check_gravity_mismatch` reads the `g_acc`/`H` *defaults* by introspection, so they're
  not fully dead — they carry metadata while not affecting the solve, which is its own
  inconsistency.) `heat_diffusion.jl` is the extreme case: `System(eqs, t, all_vars, [])`
  declares **zero** parameters — `k_s`, `rho_s`, `cp_s`, `Lx/Lz/y`, `power_shape` are all
  closed-over Float64 constants, so none are `remake`-scannable. **This is exactly the
  "components flatten geometry to unlinked numbers" problem the WA model-authoring lock
  calls out (tracker #19).** W7 reworks it (base knob params + expression-default derived
  geometry). **Do not touch in W4** beyond this flag. Friction's dead `D_h` (Cluster 4) is
  the same family.

### `channels.jl`

- **T2 — `NamedVars` is a 15-field untyped struct (lines 10–26).** JULIA.md §7: no
  untyped/abstract struct fields (annotate `::Any` explicitly or type them). It's also
  built positionally via `NamedVars(vars...)` from the `@setup` `@variables` block (line
  172), coupling field order to declaration order — fragile. A `NamedTuple` keyed by name
  removes both problems (build-time only, so perf is moot; this is about robustness/idiom).
- **T2 — channel constructors omit explicit `return` (lines 301, 385, 557).** All three
  (`Channel`, `ChannelHeatFlux`, `ChannelAndContacts`) end on a bare `compose(...)`.
  JULIA.md §11. (Same family as `geometry.jl:96`, `flapper.jl:69`.)
- **T3 — `sum([vars.dp[j] for j in 1:i])` materializes a temp array (lines 507, 510).**
  Use the generator `sum(vars.dp[j] for j in 1:i)` (JULIA.md §10/§14) — and note
  `_channel_core:120` already does it correctly, so this is internal inconsistency.
- **T3 — heavy `[[…]…; […]…]` splat-concat in `ChannelAndContacts` variant_eqs/obs
  (lines 499–547).** Same splat longcut as `helpers.jl`; flatten with nested
  comprehensions. Also `Channel` builds `q_*_expr` via `Vector{Num}(undef,n)`+loop while
  `ChannelAndContacts` uses a comprehension — pick one.
- **T3 — malformed docstring backticks (lines 193–194).** Stray leading `` ` `` on two
  lines ("`Heat flux is defined…", "`prescribed heat transfer…") — unbalanced markdown.
- **S5** (`error` 251, 265), **S6** (`Phase 55 D-01/D-03`, `D-05` 208, 214, 322), **S8**
  (`Dt` 83), **S9** (24 trailing-ws lines), `RESEARCH.md §1` comment (253, strip w/ S6).
- **Verified correct (not findings):** `function Channel end` stub with the `Base.Channel`
  rationale (good); flow-reversal `ifelse`; `::Real` annotations accept `Num` (`Num<:Real`);
  the `h_tc=fill(5000.0,n)` init-seed with its "Cyclic guesses" comment (keep that comment).

### `heat_diffusion.jl`

- **T3 — malformed formatter directive `#!format: on` (line 117).** Missing space — Blue
  recognizes `#! format: on`, so this one is inert; the matching `#! format: off` (line
  100) may never get re-enabled. Fix the directive (or drop both per S2).
- **T3 — `_diffusion_eqs` returns a `[[…]… […]… …]` splat-concatenated vector
  (lines 19–49).** Splat longcut (§11); a flat comprehension + `vcat`/`reduce` reads
  cleaner. The `# Left heat flux` / `# Right cell …` labels are borderline-narration but
  do mark distinct boundary stencils — keep or convert to a one-word section note.
- **S2** (`format: off` blocks), **S4** (`-> ODESystem` ×2), **S8** (`Dt` 87), **S9** (6
  trailing-ws lines).
- **Verified correct:** no `power_shape` validation (matches `feedback_power_shape_trust_caller`);
  `power` as a constrained free unknown is intentional and documented.

---

## Cluster 6 — Solvers + analysis + utilities + examples

**Counts:** Tier 1: 0 · Tier 2: 4 · Tier 3: 6 (+ heavy systemic S1, S2, S4, S5, S6, S7)

### `solvers.jl`
- MTK is current: operating-point `SteadyStateProblem(ssys, op; …)` /
  `ODEProblem(ssys, op, tspan; …)`, `NoInit()`, `Rodas5P()` — all v11-correct.
- **S1** — `using ModelingToolkit` ×2 + `using OrdinaryDiffEq, SteadyStateDiffEq`
  (lines 4–6); the latter is also two-packages-on-one-line (JULIA.md §2). Real deps —
  hoist to STREAM.jl, one per line.
- **S6** — "pre-wired for Phase 23 Flapper support" (line 71).
- **T3** — `steady_state_guess(; T_inlet::Float64, …)` annotates kwargs tightly as
  `::Float64`; `::Real` is more generic (JULIA.md §7). Entry-point, low priority.

### `analysis.jl`
- **T2 (latent — surface to Itay) — `ChannelState` field types contradict the
  transient path.** Fields are `::AbstractVector` (lines 49–62) but the docstring (26–27)
  and `_extract_channel_state` transient branch (96–104) build `AbstractMatrix` (`hcat(...)'`),
  and `OFI_power` (290) explicitly branches on `state.T_sat isa AbstractMatrix`. Assigning a
  matrix to an `::AbstractVector` field throws at construction — so transient
  `threshold_analysis` either errors or is **untested**. Either way the field types are
  wrong: use a parametric `ChannelState{V<:AbstractArray}` (also fixes the §7 issue below)
  or `::AbstractArray`. **Confirm whether transient `threshold_analysis` is exercised.**
- **T2 — abstract struct field types (§7).** Even setting aside the matrix issue, 11
  `::AbstractVector` fields are abstract (JULIA.md §7: never abstract struct fields).
  Parameterize. (`pipe::Union{PipeGeometry,Nothing}` is a fine small union.)
- **T3 — broad `try …; length(sol.t) > 1; catch false end` (lines 87–91).** Swallows any
  error to detect steady-vs-transient; `hasproperty(sol, :t)` is the targeted check.
- **S2** (aligned `@kwdef`/constructor `format: off` blocks), **S5** (`error` 232),
  **S6** (`D-04/D-05` 79, 127, 215), **S7** (`# ─── Private helper ───` 68). Naming note
  (`ONB_temperature`/`Sudo_Kaminaga_CHF`/`Mirshak_CHF`/`Fabrega_CHF` capitalized, exported).

### `utilities.jl` — REFERENCE-QUALITY (the "target voice")
- **Essentially clean.** Crisp docstrings with the multi-signature form, `eachindex`,
  `view`, column-major writes, trust-the-caller (matches `feedback_power_shape_trust_caller`),
  ASCII throughout, internal helpers underscore-prefixed. This is the file the rest of the
  codebase should converge toward in the W5 voice pass — **use it as the exemplar.**
- **T3 (note only)** — `src_edges == tgt_edges` (line 36) is a float-vector `==`, but it's
  an intentional, commented exact-grid fast path on *inputs* (not computed results), so it's
  acceptable under JULIA.md §15.

### `examples.jl` — builder/demo file (lighter touch; W7 may rewrite builders)
- **T2 — dead kwarg `A_ch = 7.85e-5` in `build_loop`, `build_loop_vertical`,
  `build_loop_transient` (lines 27, 87, 159).** Never used — geometry comes from
  `PipeGeometry_circular(L_ch, D_ch)`. Speculative/dead (JULIA.md §0). Removing changes the
  kwarg API of demo builders — flag.
- **T2 — nested named function `_resolve_tw` defined inside `build_loop_pk`
  (lines 530–544).** JULIA.md §11: no non-top-level named functions. Hoist to a module
  helper (it's already underscore-named) or make it a closure.
- **T3 — builders emit `@info` compile-time on every call** (correct use of logging over
  `println`, but it's the noise we saw in the test run; consider `@debug`).
- **Heavy systemic load:** **S2** (5 `format: off` signature blocks), **S4** (13
  `ODESystem` doc refs), **S5** (`error` 539), **S6** (the densest jargon in the repo —
  `Phase 55 D-10`, `D-05`, `Discretion #4`, `Phase 49`, `Spike B`, `Wave 0`,
  `spike_lof_winner`, `HYPOTHESIS=A`, lines 45–455), **S7** (`# ── … ──` 597).
- **Keep:** the consistent-IC seeding rationale (597–609) is a genuine non-obvious "why" —
  but drop/inline the `.planning/notes/*.md` path (line 597) since that file may be deleted.

---

## Cluster 7 — Module entry: `STREAM.jl`

**Counts:** Tier 1: 0 · Tier 2: 1 · Tier 3: 2 (+ systemic S3)

- **S3 / T2 — six `export` blocks split across multiple lines (lines 34–103).** JULIA.md §3:
  "Never split a single `export` across multiple lines." Each is one `export` statement
  continued over many lines via trailing commas. Reflow to one-name-per-line `export X`
  or grouped single-line `export A, B, C` blocks.
- **T3 — exports sit after all `include`s, not "right after imports" (JULIA.md §3).** The
  current placement (after the included files define the names) is arguably more readable;
  flag for consistency only — low priority.
- **T3 — exported `const HTCCorrelation = Function` (line 8, exported line 65).** An alias
  for the abstract `Function`, self-described "documentation only, not enforced." Fine as an
  *argument* annotation (abstract args are allowed), but reconsider whether it earns a place
  in the public API surface. Ties to the W6/W7 parameter rework (closures-as-correlations).
- **Verified correct:** imports at top, one-per-line, `t_nounits as t`; `include` order is
  sound (`geometry.jl` and the `const HTCCorrelation` precede the physical-models files that
  annotate `::PipeGeometry` / `::HTCCorrelation` at definition time); module block unindented.
  Note S8's fix (`D_nounits as D`) lands here.

---

## Cluster 8 — Tests (`test/`, 19 files, ~7,000 lines)

**Method note:** tests got a pattern-scan + representative-read pass (`runtests.jl`,
`test_geometry.jl`, `test_channels.jl`, `parity_helpers.jl`, plus targeted greps for test
anti-patterns), not an exhaustive line-by-line read of all 7,000 lines — appropriate for
the lower-risk layer where the systemic findings dominate. A deeper read is warranted only
if you want Tier-3 test-voice cleanup beyond the systemic sweeps.

**Counts:** Tier 1: 0 · Tier 2: 3 · Tier 3: 3 (+ heavy systemic S6, S7, S9)

- **T2 — `@assert` used for test/guard assertions (JULIA.md §21: "Don't use `@assert` to
  test anything").** `parity_helpers.jl` lines 137–203 use `@assert isapprox(...)` as
  equivalence guards (and `test_validation.jl:105`). Beyond the style rule, this is a real
  hazard: `@assert` is compiled out under `-O`/`--check-bounds=no`, so the parity guard can
  silently vanish. Replace with `isapprox(...) || error(...)` (hard, non-elidable) — which
  also preserves the intended abort-on-broken-baseline semantics.
- **T2 — tautological `@test true` (`test_integration.jl:845`).** JULIA.md §0/§21: assert
  real behavior. Replace with a meaningful assertion or remove.
- **T2 — tests use `import STREAM: name` where `using STREAM: name` is preferred
  (JULIA.md §2).** Seen in `test_geometry.jl:3`, `test_channels.jl:8`; likely more. `import`
  is for extending methods; plain name access should be `using`.
- **T3 — `@test x == <float>` (≈40 sites, mostly `test_correlations.jl`).** Most compare to
  exact-by-construction values (constant-`Nu` returns, guard returns like
  `turbulent_friction(5.0) == 0.0`, polynomial-at-0), so they're defensible under JULIA.md
  §15 — but a few recompute the RHS expression (`rd.friction(5000.0) == 0.316*5000.0^(-0.25)`)
  and would be more robust as `≈`. Low priority; don't churn the exact-value ones.
- **T3 — manually aligned `const` columns in test files** (e.g. `test_channels.jl:11–18) —
  JULIA.md §5 / BlueStyle; folds into S2/formatter sweep.
- **Systemic load:** **S6** is heaviest here — 138 `@testset "<REQ-ID>:"` names
  (`test_point_kinetics.jl` 25, `test_correlations.jl` 25, `test_integration.jl` 19, …) plus
  jargon in file-header banners (`# … Phase 55 TEST-01`). Rename to behavior-describing
  testset names (`test_channels.jl` already does this — use it as the model). **S7** (dozens
  of `# ───` walls in `test_composition.jl`/`test_integration.jl`), **S9** (11 trailing-ws
  lines). **S4** (2 `ODESystem` doc refs).
- **CLAUDE.md vs JULIA.md tension (NOT a finding):** JULIA.md §21 wants a single root
  `@testset "STREAM" begin include(...) end` in `runtests.jl`; CLAUDE.md's File Structure
  Standard explicitly mandates a "thin orchestrator: one `include()` per test file, nothing
  else." **CLAUDE.md (project-specific) wins** — leave `runtests.jl` as the bare include list.
- **Good signs:** `test_geometry.jl` uses `isapprox` with explicit tolerances and
  `@test_throws`; `@test_nowarn mtkcompile(...)` is a legitimate clean-compile assertion;
  `test_channels.jl` already carries descriptive testset names.

---

## Rollup & recommended cut line

### Tally
- **Tier 1 (correctness / wrong-MTK / deprecated): 0.** The v11 migration is real in code —
  zero removed APIs (`structural_simplify`/`@mtkbuild`/`states`/`ODAEProblem`/`IfElse` all
  absent); MTK usage (operating-point problems, `instream`, stream connectors, callable
  params, `compose`) is current. Nothing is wrong-but-passing-by-accident.
- **Tier 2 (idiom): ~25** local + the structural items in S1/S4/S5/S8.
- **Tier 3 (voice/consistency): ~35** local + S2/S7/S9.
- **9 systemic patterns (S1–S9)** account for the large majority of raw hits
  (S4 ≈52, S6 ≈88, S9 ≈42, plus S2/S5/S7/S8).

### Three things to decide before any fixing
1. **Surface-but-don't-fix items needing your verdict (not pure idiom):**
   - `analysis.jl` `ChannelState` field-type vs transient `AbstractMatrix` — **is transient
     `threshold_analysis` actually exercised?** Possible latent break.
   - `Friction` dead `D_h` param + the channel/HD **baked-geometry / dead-parameter** carve-out
     — confirm this is wholly W7's problem (I believe yes) and leave it.
   - `q_OSV_saha_zuber` `dT_sub` placeholder + "actual T_sat needed for full calc" comment —
     is the OSV calc knowingly incomplete? Parity-relevant?
   - Author-surname function names (`Mirshak_CHF`, `Marco_Han_Nusselt`, …) — **exported API
     renames need your OK** (hard rule).
2. **Where systemic sweeps belong: W4 vs W5.** S4 (`ODESystem`→`System` docs), S6 (GSD
   jargon), S7 (banner walls), S9 (trailing ws), and the S2 formatter question are large
   mechanical sweeps that overlap the W5 cleanup/humanizer pass. Recommend doing S2/S4/S6/S7/S9
   **as dedicated atomic commits** (one sweep each) rather than smearing them across per-file
   W4 commits — cleaner history, easier parity-checking.
3. **Carve-out confirmation.** Everything tagged "carve-out" (`geometry.jl`, the
   geom-coupled factories in `physical_models/`, channel/HD parameter baking) is flagged only.
   Confirm W4 leaves it for W7.

### Suggested cut line (my recommendation)
- **Do in W4 (per-cluster, atomic, parity-checked each):** the local Tier-2 idiom fixes that
  are *not* carve-out and *not* systemic — S1 hoist, S8 `D_nounits as D`, S5 typed exceptions,
  missing `return`s, `NamedVars`→`NamedTuple`, redundant `collect` splats, `sum([...])`→
  generator, the `turbulent_friction` doc/threshold mismatch, the `@assert` parity guards,
  `@test true`, `import`→`using` in tests.
- **Fold into W5:** S2, S4, S6, S7, S9, the docstring-dedup (HTC eval-point paragraph), and
  Tier-3 voice — they're mechanical and overlap the humanizer/cleanup pass.
- **Defer to W7 (flag only):** all carve-out items.
- **Needs your decision first:** the four items in (1) above.

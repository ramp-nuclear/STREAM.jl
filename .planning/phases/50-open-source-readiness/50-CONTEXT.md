# Phase 50: Open-Source Readiness - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Prepare STREAM.jl for public discovery and use: README, LICENSE, expanded examples, GitHub Actions CI, and Project.toml metadata cleanup. Does NOT include a Documenter.jl documentation site (deferred) or sysimage fix (deferred).

</domain>

<decisions>
## Implementation Decisions

### README
- **D-01:** Target audience is nuclear engineers / thermal-hydraulics physicists — lead with what STREAM.jl models, not MTK internals
- **D-02:** Include a runnable `build_loop` example as the quick-start
- **D-03:** Installation section must note that the sysimage (`build_sysimage.sh`) is aspirational — it currently does not work reliably and should not be presented as a prerequisite
- **D-04:** Include a component catalog table: Channel, Pump, HeatDiffusion, PointKinetics, ChannelAndContacts, HeatExchanger — one-line description of what each models
- **D-05:** Include a validation summary: "Validated within 1% of Python STREAM across steady-state, transient, and point kinetics benchmarks"
- **D-06:** Include a "Relationship to Python STREAM" section explaining why Julia/MTK was chosen and linking to the Python original

### LICENSE
- **D-07:** MIT License, copyright `2026 Itay Benvenisti`

### Documentation / Examples
- **D-08:** No Documenter.jl in this phase — docstrings (all 28 exports, complete since v0.5) are sufficient for API reference
- **D-09:** Add `examples/simple_loop.jl` — minimal forced-convection loop using `build_loop`, solve_steady, plot T_out. The "hello world" that teaches the basic workflow
- **D-10:** Add `examples/mtr_assembly.jl` — HeatDiffusion + ChannelAndContacts composition workflow (symmetric_plate, compose_systems). Teaches the thermal coupling pattern
- **D-11:** Existing `examples/lof_transient.jl` stays as-is — covers the dynamics workflow

### CI
- **D-12:** Add `.github/workflows/ci.yml` — Julia stable, Ubuntu latest, triggered on push and PR to main
- **D-13:** Fix VAL-01 (Fourier series flaky) and NET-03 (Cube KINSOL failure) properly before CI is active — these are pre-existing failures that would make CI permanently red if left unaddressed
- **D-14:** No branch protection rules added — CI is informational, does not block merges

### Project.toml Metadata
- **D-15:** Bump version to `0.9.0` (currently `0.6.0` — stale since v0.5 era)
- **D-16:** Generate a real UUID (current placeholder `a1b2c3d4-e5f6-7890-abcd-ef1234567890` must be replaced with `uuidgen` output)
- **D-17:** Set `authors = ["Itay Benvenisti <itaybnv@github.com>"]`
- **D-18:** Add `repo = "https://github.com/itaybnv/STREAM.jl"` field
- **D-19:** Move `PackageCompiler` out of `[deps]` into `[extras]`/`[targets]` or remove — it is a build tool, not a runtime dependency

### Claude's Discretion
- Exact README prose, section ordering, and formatting
- Component catalog table layout
- Whether to include a badges section (Julia version, CI status, license)
- CI workflow file details (cache config, timeout settings)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

No external specs — requirements are fully captured in decisions above.

### Relevant existing files to read before planning
- `Project.toml` — current metadata state (stale version, placeholder UUID, PackageCompiler in deps)
- `src/STREAM.jl` — full export list (determines what goes in the component catalog)
- `examples/lof_transient.jl` — existing example style to match
- `test/runtests.jl` — test orchestrator; VAL-01 and NET-03 are in `test/test_validation.jl` and `test/test_resistors.jl`
- `CLAUDE.md` — developer conventions (sysimage instructions live here)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/examples.jl` — `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube`, `build_loop_pk` are all available as the basis for new example scripts
- All 28 exported names have structured docstrings (`# Arguments`, `# Ports`, `# Returns`) — component catalog can be sourced directly from these
- `test/test_validation.jl` — VAL-01 Fourier series test (flaky, needs fix); `test/test_resistors.jl` — NET-03 Cube KINSOL failure

### Established Patterns
- Example scripts use `build_*` functions from `src/examples.jl` rather than building systems from scratch — new examples should follow the same pattern
- Julia CI standard: `julia-actions/setup-julia`, `julia-actions/cache`, `julia-actions/julia-buildpkg`, `julia-actions/julia-runtest`

### Integration Points
- `.github/workflows/ci.yml` is new (no existing CI)
- `Project.toml` is the authoritative metadata file — version, UUID, authors, compat all live here
- `LICENSE` goes in repo root (same level as `Project.toml`)
- `README.md` goes in repo root

</code_context>

<specifics>
## Specific Ideas

- "I could never get the sysimage to actually work" — installation section must not imply sysimage is required or working. Mention it as an optional performance optimization that is still in progress.
- The sysimage issue warrants its own phase after this one (see Deferred Ideas).
- Repo URL: `https://github.com/itaybnv/STREAM.jl`

</specifics>

<deferred>
## Deferred Ideas

- **Sysimage fix** — sysimage (`build_sysimage.sh`) has never reliably worked. Should be its own dedicated phase after Phase 50 to diagnose and fix WSL2 memory constraints, Julia precompilation issues, and verify end-to-end.
- **Documenter.jl site** — Full documentation site with API reference and tutorials. Defer until after sysimage is fixed and the project has stabilized. Planned as a future phase.

</deferred>

---

*Phase: 50-open-source-readiness*
*Context gathered: 2026-04-10*

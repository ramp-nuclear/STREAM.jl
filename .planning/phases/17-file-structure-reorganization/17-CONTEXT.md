# Phase 17: File Structure Reorganization - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Move source files on disk to match the canonical layout defined in CLAUDE.md. No logic changes, no new features, no physics changes. Every test must pass after the reorganization.

Files being reorganized:
- `src/components.jl` (monolithic) → split into 6 files under `src/components/`
- `src/correlations.jl` → `src/physical_models/correlations.jl`
- `src/helpers.jl` → `src/composition/helpers.jl`
- PipeGeometry extracted from components.jl → `src/geometry.jl`
- `build_loop*`/`build_cube` extracted from `solvers.jl` → `src/examples.jl`

`src/connectors.jl` and `src/fluids.jl` do NOT move.

</domain>

<decisions>
## Implementation Decisions

### steady_state_guess placement
- `steady_state_guess` stays in `solvers.jl` — it is a general-purpose solver utility used in 14 test cases directly, not an example-only helper.
- REQUIREMENTS.md STR-05 text was imprecise: only `build_loop`, `build_loop_vertical`, `build_loop_transient`, and `build_cube` move to `examples.jl`.
- CLAUDE.md is the authoritative source for file placement.

### Execution strategy
- Incremental: move one logical group, update `STREAM.jl` includes, run tests, then proceed to the next group.
- Do not batch all moves and test once — catch forward-reference errors early.
- Suggested sequence: geometry.jl → components/ (one file at a time or as a batch if clearly safe) → physical_models/ → composition/ → examples.jl split.

### STREAM.jl include order (after reorganization)
- Claude's discretion — verify no forward-reference errors.
- Natural order:
  1. `fluids.jl`
  2. `connectors.jl`
  3. `geometry.jl`
  4. `physical_models/correlations.jl`
  5. `components/channel.jl` (defines `_channel_base_eqs` used by thermal_channel.jl)
  6. `components/pump.jl`
  7. `components/resistors.jl`
  8. `components/misc.jl`
  9. `components/thermal_channel.jl` (uses `_channel_base_eqs` from channel.jl)
  10. `components/heat_diffusion.jl`
  11. `composition/helpers.jl`
  12. `solvers.jl`
  13. `examples.jl`

### Internal helpers placement
- `_channel_base_eqs` lives in `components/channel.jl` — used by both `Channel` and `ChannelHeatFlux`; the sequential include order makes it available when `thermal_channel.jl` is loaded.
- `_diffusion_eqs` lives in `components/heat_diffusion.jl` — only used by `HeatDiffusion`.

### Claude's Discretion
- Exact include ordering within the components/ group (pump/resistors/misc order is flexible)
- Whether to create subdirectories in one mkdir call or one at a time

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### File layout specification
- `CLAUDE.md` — Canonical file structure standard; authoritative for all placement decisions. The `## File Structure Standard` section defines exactly which file goes where.

### Requirements
- `.planning/REQUIREMENTS.md` §STR-01 through STR-05 — Requirements for this phase (note: STR-05 text is imprecise about steady_state_guess; see decisions above)
- `.planning/ROADMAP.md` §Phase 17 — Success criteria for this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/STREAM.jl` — Module entry point; needs its `include()` list updated to reflect new paths and new files

### Established Patterns
- Components are defined with `@mtkmodel` blocks in Julia; splitting is a straight cut-and-paste with no logic changes required
- Private helpers (`_channel_base_eqs`, `_diffusion_eqs`) are prefixed with `_` and not exported — they must be defined before the components that call them within the same include sequence
- All exports remain in `src/STREAM.jl` — no `export` statements inside component files

### Integration Points
- `STREAM.jl` include list is the only file that wires all pieces together — the only structural change beyond moving files
- Tests reference exported symbols only — no direct file-path dependencies — so test files need no changes from the file moves themselves

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches for the mechanical file moves.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 17-file-structure-reorganization*
*Context gathered: 2026-03-16*

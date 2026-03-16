# Phase 19: Docstrings, CLAUDE.md, and Final Polish - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Julia docstrings to all exported names (11 components, 6 composition helpers, 7 solver/example functions, 4 fluid functions — fluid functions and correlations already have docstrings). Expand CLAUDE.md with rationale per rule and an MTK patterns section. Add a dedicated ChannelHeatFlux test group. Bump version to 0.5.0. No new features, no physics changes.

</domain>

<decisions>
## Implementation Decisions

### Docstring format (components)
- Format: one-line description + `# Arguments` (constructor kwargs only) + `# Ports` + `# Returns`
- `# Arguments`: list only the kwargs the caller passes (e.g., `n`, `geometry`, `name`, `htc_func`). Omit MTK-internal metadata.
- `# Ports`: list the connector ports each component exposes with their types.
  - Standard flow components (Channel, Pump, Friction, Gravity, Resistor, Inertia, HeatExchanger, ChannelHeatFlux): `port_in`, `port_out` (FlowPort)
  - ChannelAndContacts: `port_in`, `port_out` (FlowPort) + `thermal_left[1:n]`, `thermal_right[1:n]` (ThermalPort arrays)
  - HeatDiffusion: `thermal_left[1:n]`, `thermal_right[1:n]` (ThermalPort arrays, no FlowPorts)
  - ConstantTemperature: `thermal` (ThermalPort, single — it's a BC not a component)
- `# Returns`: the ODESystem
- No `# Examples` block — too much maintenance burden for a single-dev project
- No `# Observables` section — user queries `unknowns(sys)` / `observed(sys)` at runtime

### Docstring format (composition helpers)
- Same format: one-line description + `# Arguments` (kwargs) + `# Returns`
- No `# Ports` section (helpers return assembled systems, not single components)
- Consistent with components — no special treatment

### Docstring format (solver/example functions)
- Same format: one-line description + `# Arguments` (kwargs) + `# Returns`
- `solve_steady`, `solve_transient`, `steady_state_guess`, `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube` all follow this pattern

### What's already documented (do not re-write)
- `rho_water`, `cp_water`, `mu_water`, `k_water` — have docstrings; just verify `# Arguments` and `# Returns` sections are present per DOC-04
- Correlation functions (`dittus_boelter`, `blasius_friction`, etc.) — already documented; skip

### CLAUDE.md rewrite
- Audience: future-me (single developer, will return after months away)
- Add a rationale sentence (`Why:`) after each existing rule — concise, opinionated
- Add a short **MTK Patterns** section covering non-obvious conventions:
  - Why `@register_symbolic` for fluid properties (not plain functions)
  - Why `ifelse()` for flow reversal (not if-branches: solver discontinuity)
  - Why `vars=[]` for Inertia (MTK auto-promotes `Dt(port_in.mdot)`)
  - When to use `@observed` vs plain unknowns (diagnostic-only vs equation-referenced)
  - Why `mtkcompile` is required before solve (symbolic reduction, Jacobian)
- Keep CLAUDE.md focused: file structure + component conventions + MTK patterns. Not a tutorial.

### ChannelHeatFlux audit (QOL-05)
- Add a dedicated `@testset "ChannelHeatFlux"` block in `test/test_channel.jl`
- Depth: similar to other channel tests — build the component, solve a simple loop, assert `T_out` is reasonable
- Not exhaustive; one happy-path test is sufficient to confirm it's ship-ready
- ConstantTemperature: already well-tested across 5+ test files — no new tests needed

### Version bump
- `Project.toml`: `version = "0.5.0"` (QOL-04)
- Claude's discretion on placement within the plan (trivial, last task)

### Claude's Discretion
- Exact wording of each docstring (style consistent with Julia stdlib conventions)
- Which MTK gotchas to include in the MTK patterns section (beyond the four listed above)
- Test parameter values for the ChannelHeatFlux dedicated test

</decisions>

<canonical_refs>
## Canonical References

No external specs — requirements are fully captured in decisions above and REQUIREMENTS.md.

### Phase requirements
- `.planning/REQUIREMENTS.md` — DOC-01..04, QOL-03..05 define the acceptance criteria
- `.planning/ROADMAP.md` Phase 19 success criteria — exact list of what must be true

</canonical_refs>

<code_context>
## Existing Code Insights

### Already documented (skip or verify only)
- `src/fluids.jl` — rho_water, cp_water, mu_water, k_water have docstrings (verify # Arguments + # Returns)
- `src/physical_models/correlations.jl` — all correlation functions documented
- `src/geometry.jl` — PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular have docstrings

### Need docstrings written from scratch
- `src/components/channel.jl` — Channel (+ _channel_base_eqs, internal, skip)
- `src/components/pump.jl` — Pump
- `src/components/resistors.jl` — Friction, Gravity, Resistor
- `src/components/misc.jl` — Inertia, HeatExchanger, ConstantTemperature
- `src/components/thermal_channel.jl` — ChannelAndContacts, ChannelHeatFlux
- `src/components/heat_diffusion.jl` — HeatDiffusion
- `src/composition/helpers.jl` — symmetric_plate, plate, one_sided_connection, compose_systems, port, check_gravity_mismatch
- `src/solvers.jl` — solve_steady, solve_transient, steady_state_guess
- `src/examples.jl` — build_loop, build_loop_vertical, build_loop_transient, build_cube

### Established Patterns
- All exports declared in `src/STREAM.jl` — docstrings go in the component file, not STREAM.jl
- All component constructors are keyword-only — `# Arguments` lists only keyword params
- Internal helpers prefixed with `_` (e.g., `_channel_base_eqs`, `_diffusion_eqs`) — NOT exported, NOT documented

### Integration Points
- `test/test_channel.jl` — ChannelHeatFlux dedicated test group goes here
- `CLAUDE.md` at project root — expand in-place
- `Project.toml` at project root — version field

</code_context>

<specifics>
## Specific Ideas

- No specific requirements — open to standard Julia docstring conventions
- ChannelHeatFlux test should mirror depth of existing Channel tests in test_channel.jl

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 19-docstrings-claude-md-and-final-polish*
*Context gathered: 2026-03-16*

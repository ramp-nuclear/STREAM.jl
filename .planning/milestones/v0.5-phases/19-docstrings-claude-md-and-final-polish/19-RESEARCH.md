# Phase 19: Docstrings, CLAUDE.md, and Final Polish - Research

**Researched:** 2026-03-16
**Domain:** Julia docstrings, CLAUDE.md documentation, test coverage audit
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Docstring format (components):**
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

**Docstring format (composition helpers):**
- Same format: one-line description + `# Arguments` (kwargs) + `# Returns`
- No `# Ports` section (helpers return assembled systems, not single components)
- Consistent with components — no special treatment

**Docstring format (solver/example functions):**
- Same format: one-line description + `# Arguments` (kwargs) + `# Returns`
- `solve_steady`, `solve_transient`, `steady_state_guess`, `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube` all follow this pattern

**What's already documented (do not re-write):**
- `rho_water`, `cp_water`, `mu_water`, `k_water` — have docstrings; just verify `# Arguments` and `# Returns` sections are present per DOC-04
- Correlation functions (`dittus_boelter`, `blasius_friction`, etc.) — already documented; skip

**CLAUDE.md rewrite:**
- Audience: future-me (single developer, will return after months away)
- Add a rationale sentence (`Why:`) after each existing rule — concise, opinionated
- Add a short **MTK Patterns** section covering non-obvious conventions:
  - Why `@register_symbolic` for fluid properties (not plain functions)
  - Why `ifelse()` for flow reversal (not if-branches: solver discontinuity)
  - Why `vars=[]` for Inertia (MTK auto-promotes `Dt(port_in.mdot)`)
  - When to use `@observed` vs plain unknowns (diagnostic-only vs equation-referenced)
  - Why `mtkcompile` is required before solve (symbolic reduction, Jacobian)
- Keep CLAUDE.md focused: file structure + component conventions + MTK patterns. Not a tutorial.

**ChannelHeatFlux audit (QOL-05):**
- Add a dedicated `@testset "ChannelHeatFlux"` block in `test/test_channel.jl`
- Depth: similar to other channel tests — build the component, solve a simple loop, assert `T_out` is reasonable
- Not exhaustive; one happy-path test is sufficient to confirm it's ship-ready
- ConstantTemperature: already well-tested across 5+ test files — no new tests needed

**Version bump:**
- `Project.toml`: `version = "0.5.0"` (QOL-04)
- Claude's discretion on placement within the plan (trivial, last task)

### Claude's Discretion
- Exact wording of each docstring (style consistent with Julia stdlib conventions)
- Which MTK gotchas to include in the MTK patterns section (beyond the four listed above)
- Test parameter values for the ChannelHeatFlux dedicated test

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DOC-01 | All 11 component constructors have Julia docstrings with `# Arguments` and `# Returns` | Source audit confirms 0 of 11 components have docstrings; format decided in CONTEXT.md |
| DOC-02 | All 6 composition/QoL helpers have Julia docstrings with `# Arguments` and `# Returns` | Source audit confirms 0 of 6 helpers have docstrings; comment blocks present, need conversion |
| DOC-03 | All 7 solver/example functions have Julia docstrings with `# Arguments` and `# Returns` | Source audit confirms 0 of 7 functions have formal docstrings; detailed comments exist as prose |
| DOC-04 | `rho_water`, `cp_water`, `mu_water`, `k_water` docstrings completed with `# Arguments` and `# Returns` | Fluids.jl docstrings exist but use ad-hoc format; need `# Arguments` and `# Returns` sections added |
| QOL-03 | CLAUDE.md rewritten with rationale behind each rule and MTK-specific patterns | Current CLAUDE.md has rules but no rationale; MTK patterns section absent entirely |
| QOL-04 | `Project.toml` version bumped to `0.5.0` | Project.toml currently at `0.1.0` — needs update |
| QOL-05 | `ChannelHeatFlux` and `ConstantTemperature` audited — confirm exported, tested, and documented | Both exported in STREAM.jl; ConstantTemperature tested in 5+ testsets; ChannelHeatFlux tested in THERM-03 as reference but has no dedicated testset; no docstrings on either |
</phase_requirements>

---

## Summary

Phase 19 is a pure documentation and polish phase. The codebase structure is final (as of Phase 17) and the API is stable (as of Phase 18). The work consists of: writing Julia docstrings for every exported name that lacks them, expanding CLAUDE.md with rationale and MTK patterns, adding a dedicated ChannelHeatFlux testset, and bumping the version to 0.5.0.

The existing codebase has excellent inline comments (block comments describing component behavior, parameter meanings, and design rationale) but these are in `#`-comment style rather than Julia's `"""..."""` docstring format. The conversion task is therefore well-defined: extract the semantic content from existing comments and reformat into the agreed docstring structure.

The fluids docstrings (DOC-04) are the closest to complete — they use Julia's `"""..."""` syntax but omit structured `# Arguments` and `# Returns` sections. All other exported names need docstrings written from the existing inline comments.

**Primary recommendation:** Organize work into 4 tasks — (1) component docstrings (DOC-01), (2) helper/solver/example docstrings (DOC-02, DOC-03, DOC-04), (3) CLAUDE.md rewrite (QOL-03), (4) ChannelHeatFlux test + version bump (QOL-05, QOL-04).

---

## Current State: What Exists vs. What's Needed

### DOC-01: Component Constructors (11 total — all need docstrings)

| Component | File | Has Docstring | Has Inline Comments | Notes |
|-----------|------|---------------|---------------------|-------|
| Channel | `src/components/channel.jl` | No | Minimal | Ports: port_in, port_out (FlowPort); also has thermal (FlowPort — single scalar ThermalPort) |
| Pump | `src/components/pump.jl` | No | No | Two modes: dP_pump OR mdot0 (mutually exclusive) |
| Friction | `src/components/resistors.jl` | No | No | Ports: port_in, port_out (FlowPort) |
| Gravity | `src/components/resistors.jl` | No | No | Ports: port_in, port_out (FlowPort) |
| Resistor | `src/components/resistors.jl` | No | No | Ports: port_in, port_out (FlowPort) |
| Inertia | `src/components/misc.jl` | No | Yes (good block) | Notable: `vars=[]`, MTK auto-promotes Dt(port_in.mdot) |
| HeatExchanger | `src/components/misc.jl` | No | Yes (good block) | Ports: port_in, port_out (FlowPort) |
| ConstantTemperature | `src/components/misc.jl` | No | Yes (brief) | Port: thermal (ThermalPort, single) |
| ChannelAndContacts | `src/components/thermal_channel.jl` | No | Yes (detailed header) | Ports: port_in, port_out (FlowPort) + thermal_left[1:n], thermal_right[1:n] |
| ChannelHeatFlux | `src/components/thermal_channel.jl` | No | Yes (good block) | Ports: port_in, port_out only — no ThermalPorts |
| HeatDiffusion | `src/components/heat_diffusion.jl` | No | Yes (detailed header) | Ports: thermal_left[1:n], thermal_right[1:n] only |

**Note on Channel's `thermal` port:** Channel has a single `thermal` FlowPort (not an array), used for a wall temperature BC. This is distinct from ChannelAndContacts which has per-cell arrays. The docstring must document this port accurately.

**Note on Pump:** The constructor takes exactly one of `dP_pump` or `mdot0` — errors if both or neither provided. The docstring must convey this mutual-exclusion constraint.

### DOC-02: Composition/QoL Helpers (6 total — all need docstrings)

| Function | File | Has Docstring | Has Inline Comments |
|----------|------|---------------|---------------------|
| `port` | `src/composition/helpers.jl` | No | Yes (brief) |
| `check_gravity_mismatch` | `src/composition/helpers.jl` | No | Yes (detailed strategy block) |
| `symmetric_plate` | `src/composition/helpers.jl` | No | Yes (wiring described) |
| `plate` | `src/composition/helpers.jl` | No | Yes (wiring described) |
| `one_sided_connection` | `src/composition/helpers.jl` | No | Yes (side semantics) |
| `compose_systems` | `src/composition/helpers.jl` | No | Yes (usage example) |

**Note:** All 6 functions have comment blocks immediately above them that describe behavior and usage. The conversion to docstring format is straightforward — lift content, restructure into `# Arguments` + `# Returns`.

### DOC-03: Solver/Example Functions (7 total — all need docstrings)

| Function | File | Has Docstring | Has Prose Comments |
|----------|------|---------------|--------------------|
| `steady_state_guess` | `src/solvers.jl` | No | Yes (brief) |
| `solve_steady` | `src/solvers.jl` | No | Yes (detailed — describes op format, return) |
| `solve_transient` | `src/solvers.jl` | No | Yes (detailed — describes all kwargs, return) |
| `build_loop` | `src/examples.jl` | No | Yes (very detailed — topology, BCs, returns) |
| `build_loop_vertical` | `src/examples.jl` | No | Yes (very detailed — gravity wiring) |
| `build_loop_transient` | `src/examples.jl` | No | Yes (detailed — T_wall parameter, returns tuple) |
| `build_cube` | `src/examples.jl` | No | Yes (detailed — topology, analytical answer) |

**Note:** `build_loop_transient` returns a tuple `(ssys, T_wall_sym)`, not just `ssys`. The `# Returns` section must document this.

### DOC-04: Fluid Functions (4 total — docstrings exist, need sections added)

The four fluid functions (`rho_water`, `cp_water`, `mu_water`, `k_water`) in `src/fluids.jl` already have `"""..."""` docstrings. The existing format is:

```
one-line description
blank line
T_K: description
```

They are missing structured `# Arguments` and `# Returns` sections. The fix is to add these two sections to each existing docstring — not a rewrite.

### QOL-03: CLAUDE.md Rewrite

**Current state:** CLAUDE.md has three sections:
1. File Structure Standard — lists canonical layout with brief annotations
2. Component authoring conventions — 4 rules (keyword-only, factory functions keyword-only, `_` prefix, docstring minimum)
3. Exports — 1 rule (all exports in STREAM.jl)

**Gap:** No `Why:` rationale after any rule. No MTK Patterns section at all.

**Content to add for MTK Patterns section (from CONTEXT.md):**
1. Why `@register_symbolic` for fluid properties — plain Julia functions can't accept MTK's `Num` type (symbolic variables); `@register_symbolic` wraps them to be opaque to Symbolics.jl's tracing, allowing them to appear in MTK equations without being differentiated symbolically.
2. Why `ifelse()` for flow reversal (and regime switching) — Julia `if`/`else` on a symbolic expression would branch on the concrete value at trace time (always one branch, degenerate). `ifelse()` is the MTK/Symbolics.jl form of a ternary that emits a symbolic `ifelse` node, enabling smooth transitions and correct Jacobians.
3. Why `vars=[]` for Inertia — MTK auto-promotes `port_in.mdot` to a state variable when it appears inside `Dt(port_in.mdot)`. Declaring it in `vars` would be redundant and confusing; leaving `vars=[]` lets MTK handle the promotion.
4. When to use `@observed` vs plain unknowns — `@observed` variables are computed post-solve (not part of the DAE); use for diagnostic quantities that are not referenced in any other equation. If a variable appears on the RHS of another equation, it must be a plain unknown.
5. Why `mtkcompile` is required before solve — MTK's symbolic IR needs structural analysis, index reduction (DAE to ODE form), Jacobian sparsity computation, and code generation. Passing an uncompiled `System` to `solve` silently omits these and will either error or give wrong results.

### QOL-04: Version Bump

**Current:** `Project.toml` has `version = "0.1.0"`. Target is `version = "0.5.0"`.

### QOL-05: ChannelHeatFlux Dedicated Test

**Current coverage:** ChannelHeatFlux is referenced in `test/test_channel.jl` inside the `THERM-03` testset as the reference solution for a comparison against ChannelAndContacts. It is tested indirectly — the test verifies that CHF and CAC agree to 0.1%, which means CHF is exercised. However, there is no `@testset "ChannelHeatFlux"` block that stands on its own.

**Gap:** No standalone testset for ChannelHeatFlux. If THERM-03 were removed, CHF would have zero direct test coverage.

**Required:** Add a `@testset "ChannelHeatFlux"` block to `test/test_channel.jl` that:
- Constructs a ChannelHeatFlux with known parameters
- Assembles a simple closed loop (same pattern as THERM-03's CHF side)
- Solves to steady state
- Asserts `T_out > T_inlet` (heated, so outlet must be hotter)
- Optionally asserts `retcode == ReturnCode.Success`

**Pattern to follow:** The CHF loop assembly in THERM-03 (lines 143-159 of test_channel.jl) is exactly the right template. The dedicated testset should use the same topology (Pump + HeatExchanger + ChannelHeatFlux) and similar parameters.

---

## Julia Docstring Conventions (Standard)

**Confidence: HIGH** — standard Julia language documentation.

Julia docstrings use triple-quoted strings (`"""..."""`) placed immediately before the function/struct definition. The canonical format from the Julia docs manual:

```julia
"""
    function_name(arg1, arg2; kwarg1, kwarg2) -> ReturnType

One-line summary of what the function does.

Optional extended description paragraph.

# Arguments
- `kwarg1`: description [units if applicable]
- `kwarg2`: description [units if applicable]

# Returns
Description of return value and how to use it.
"""
function function_name(...)
```

**Key rules for this project (from CONTEXT.md decisions):**
- First line is the function signature (indented 4 spaces)
- Second line is blank
- Third line is the one-line description
- `# Arguments` section lists only user-facing kwargs (not MTK internal metadata)
- `# Ports` section for components (before `# Returns`)
- `# Returns` section last
- No `# Examples` block
- No `# Observables` section

**Placement rule:** Docstrings go in the component file (e.g., `src/components/pump.jl`), not in `src/STREAM.jl`. The docstring is associated with the function at definition site.

**Multiple-definition functions:** `Pump` has two branches inside a single function body (not multiple method definitions). One docstring above the function covers both modes. The docstring should describe both modes and the mutual-exclusion constraint.

---

## Architecture Patterns

### Docstring Placement Pattern

For this codebase, every component follows the pattern:
```
# block comment describing design rationale
function ComponentName(; name, kwarg1, kwarg2, ...)
    ...
end
```

The conversion path is: retain the block comment for developer context, add a `"""..."""` docstring immediately before the `function` keyword.

For helpers in `helpers.jl`, the existing comment blocks use `# ---` separators. These become prose in the docstring body.

### Test Pattern for ChannelHeatFlux Dedicated Testset

Based on the existing THERM-03 pattern (test_channel.jl lines 143-159), the CHF dedicated test follows:

```julia
@testset "ChannelHeatFlux: standalone happy-path" begin
    n = 10; T_inlet = 313.15; T_wall = 373.15
    L_ch = 0.6; D_ch = 0.01; dP_pump = 3.0e4

    @named pump = Pump(dP_pump=dP_pump)
    @named chf  = ChannelHeatFlux(n=n, geometry=PipeGeometry_circular(L_ch, D_ch), T_wall=T_wall)
    @named bc   = HeatExchanger(T_bc=T_inlet)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, chf.port_in),
        connect(chf.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        chf.port_in.T  ~ T_inlet,
    ]
    @named sys = compose(System(conns, t; name=:sys), pump, bc, chf)
    ssys = mtkcompile(sys)
    T_guess = steady_state_guess(T_inlet=T_inlet, Q_wall=1e4, mdot_guess=0.490, n=n)
    op = [ssys.chf.T[i] => T_guess[i] for i in 1:n]
    push!(op, ssys.chf.port_in.mdot => 0.490)
    sol = solve_steady(ssys, op)

    @test sol.retcode == ReturnCode.Success
    @test sol[ssys.chf.T_out] > T_inlet   # outlet must be warmer than inlet
end
```

This pattern is verified to work — it is structurally identical to the CHF side of the existing THERM-03 testset.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Docstring format | Custom documentation conventions | Julia stdlib docstring format | Standard, Documenter.jl-compatible, familiar to Julia ecosystem |
| Markdown sections | HTML/custom markup | `# Arguments`, `# Returns` headers | Julia convention, rendered by REPL `?help` and Documenter.jl |
| Version format | Date-based or custom versioning | Semver in Project.toml | Julia package ecosystem requirement |

---

## Common Pitfalls

### Pitfall 1: Docstring Placed After Function Definition
**What goes wrong:** Julia does not associate a docstring with a function if the `"""..."""` block comes after the function definition.
**Why it happens:** Confusion with Python's docstring-inside-body convention.
**How to avoid:** Always place the `"""..."""` block immediately before the `function` keyword on the preceding line.
**Warning signs:** `?ComponentName` in REPL shows no documentation.

### Pitfall 2: Documenting Internal Helpers
**What goes wrong:** Adding docstrings to `_channel_base_eqs` or `_diffusion_eqs`.
**Why it happens:** They have detailed block comments that look like docstrings.
**How to avoid:** CONTEXT.md is explicit — internal helpers (prefixed `_`) are NOT exported and NOT documented. The existing block comments are sufficient.

### Pitfall 3: Duplicating MTK Metadata in `# Arguments`
**What goes wrong:** Including MTK-internal parameters (e.g., `name` as part of system metadata, or parameter symbols like `D_h`, `g_acc`) in the `# Arguments` list.
**Why it happens:** Confusion between the constructor's Julia kwargs and the internal MTK parameter names.
**How to avoid:** CONTEXT.md decision: list only the kwargs the caller passes (`n`, `geometry`, `name`, `htc_func`, etc.). `name` is always a kwarg and should be listed. MTK internal parameter names (`D_h`, `g_acc`) should not appear.

### Pitfall 4: Fluid Docstring Full Rewrite
**What goes wrong:** Rewriting the fluid function docstrings from scratch, losing the existing content.
**Why it happens:** The existing format looks non-standard.
**How to avoid:** DOC-04 is a targeted addition — add `# Arguments` and `# Returns` sections to the existing docstrings. Do not replace the one-line summary or the Simantov correlation note.

### Pitfall 5: CLAUDE.md Losing Existing Rules
**What goes wrong:** Rewriting CLAUDE.md from scratch and losing rules that are already there.
**Why it happens:** CONTEXT.md says "expand" and "add rationale" but it's easy to over-edit.
**How to avoid:** Edit in-place. Every existing rule gets a `Why:` sentence added after it. The MTK Patterns section is appended as a new section. File structure table and test table are preserved verbatim.

### Pitfall 6: ConstantTemperature Test Duplication
**What goes wrong:** Adding a new dedicated ConstantTemperature testset, duplicating coverage that already exists.
**Why it happens:** QOL-05 says "ConstantTemperature audited" which could be interpreted as requiring new tests.
**How to avoid:** CONTEXT.md decision: ConstantTemperature is already well-tested across 5+ test files — no new tests needed. QOL-05 for ConstantTemperature means confirming it is exported, tested, and documented.

---

## Code Examples

### Julia Docstring for a Component (pattern)

```julia
# Source: Julia documentation manual — https://docs.julialang.org/en/v1/manual/documentation/
"""
    Channel(; name, n, geometry, g=0.0, htc_correlation=dittus_boelter,
             friction_correlation=blasius_friction) -> ODESystem

Single-phase convective channel with n axial finite-volume cells and one-sided wall heating.

# Arguments
- `name`: system name (Symbol)
- `n`: number of axial cells
- `geometry`: `PipeGeometry` descriptor (hydraulic diameter, area, length, heated perimeter)
- `g`: gravitational acceleration [m/s²]; 0.0 for horizontal, 9.80665 for vertical upward flow
- `htc_correlation`: HTC correlation function `(Re, Pr) -> Nu`; default `dittus_boelter`
- `friction_correlation`: friction correlation function `(Re) -> f_darcy`; default `blasius_friction`

# Ports
- `port_in`, `port_out` — `FlowPort` (hydraulic: pressure, mass flow, temperature)
- `thermal` — `ThermalPort` (wall temperature BC; `thermal.T` drives the energy balance)

# Returns
Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
"""
function Channel(; name, n::Int, geometry::PipeGeometry, g = 0.0, ...)
```

### Julia Docstring for a Helper Function (pattern)

```julia
"""
    symmetric_plate(cac, fuel; name) -> ODESystem

Wire one `HeatDiffusion` fuel plate symmetrically to one `ChannelAndContacts` channel.

Both faces of the plate heat the same channel. Wiring: `cac.thermal_right[i] <-> fuel.thermal_left[i]`
and `cac.thermal_left[i] <-> fuel.thermal_right[i]` for all `i` in `1:n`.

# Arguments
- `cac`: uncompiled `ChannelAndContacts` instance
- `fuel`: uncompiled `HeatDiffusion` instance; `fuel.nz` must equal `cac.n`
- `name`: name for the assembled system (Symbol)

# Returns
Raw `ODESystem` from `compose()`. Add boundary conditions, then call `mtkcompile()`.
"""
function symmetric_plate(cac, fuel; name::Symbol)
```

### Fluid Docstring Addition (pattern)

```julia
# Source: existing src/fluids.jl — add # Arguments and # Returns sections
"""
    rho_water(T_K) -> kg/m³

Saturated liquid water density (Simantov correlation).
T_K: temperature in Kelvin.

Note: uses Fahrenheit internally — this is a quirk of the Simantov correlation.

# Arguments
- `T_K`: temperature [K]

# Returns
Density [kg/m³] as `Float64`.
"""
```

---

## State of the Art

| Old Approach | Current Approach | Impact for This Phase |
|--------------|------------------|----------------------|
| Inline `#` block comments | Julia `"""..."""` docstrings | Must convert comments to docstring format |
| No structured sections | `# Arguments`, `# Ports`, `# Returns` | Add sections per CONTEXT.md decisions |
| Version `0.1.0` in Project.toml | `0.5.0` | Single field update |

---

## Open Questions

1. **`name` kwarg in `# Arguments` for components**
   - What we know: `name` is a required kwarg for all component constructors (Julia convention for MTK components)
   - What's unclear: Should `name` always appear first in `# Arguments` and what description to give it?
   - Recommendation: Yes, list `name` first with description "system name (Symbol)". All MTK components require it and callers always pass it.

2. **`@vars=[]` note in Inertia docstring**
   - What we know: Inertia uses `vars=[]` because MTK auto-promotes `port_in.mdot` as a state when it appears in `Dt(port_in.mdot)`. This is a non-obvious MTK pattern.
   - What's unclear: Should this implementation detail appear in the docstring or only in CLAUDE.md?
   - Recommendation: Keep it out of the docstring (CONTEXT.md: no observables/implementation notes). This belongs in the CLAUDE.md MTK Patterns section. The docstring should only document the interface.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia's built-in `Test` stdlib |
| Config file | none (tests run via `julia --project test/runtests.jl`) |
| Quick run command | `julia --project -e 'include("test/test_channel.jl")'` |
| Full suite command | `julia --project test/runtests.jl` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DOC-01 | Component constructors have docstrings | Manual inspection | `julia --project -e 'using STREAM; @doc Channel'` | N/A |
| DOC-02 | Helpers have docstrings | Manual inspection | `julia --project -e 'using STREAM; @doc symmetric_plate'` | N/A |
| DOC-03 | Solver functions have docstrings | Manual inspection | `julia --project -e 'using STREAM; @doc solve_steady'` | N/A |
| DOC-04 | Fluid function docstrings complete | Manual inspection | `julia --project -e 'using STREAM; @doc rho_water'` | N/A |
| QOL-03 | CLAUDE.md has rationale + MTK patterns | Manual inspection | n/a | N/A |
| QOL-04 | Project.toml version == 0.5.0 | Smoke check | `julia --project -e 'import Pkg; Pkg.status()'` | ✅ |
| QOL-05 | ChannelHeatFlux has dedicated testset | Unit test | `julia --project test/runtests.jl` | ❌ Wave 0: add testset to test_channel.jl |

### Sampling Rate
- **Per task commit:** `julia --project -e 'using STREAM'` — confirms package loads without error after each docstring batch
- **Per wave merge:** `julia --project test/runtests.jl` — full suite green
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_channel.jl` — add `@testset "ChannelHeatFlux"` dedicated block (covers QOL-05)

*(All other test infrastructure exists and is sufficient for this phase.)*

---

## Sources

### Primary (HIGH confidence)
- Direct source code inspection of all 9 source files listed in CONTEXT.md
- `src/fluids.jl` — confirmed existing docstrings and their gaps
- `src/geometry.jl` — confirmed existing docstrings (reference format for `# Arguments` style)
- `src/physical_models/correlations.jl` — confirmed existing docstrings (reference format for usage examples)
- `test/test_channel.jl` — confirmed THERM-03 covers CHF indirectly; no standalone ChannelHeatFlux testset
- `Project.toml` — confirmed current version is `0.1.0`
- `CLAUDE.md` — confirmed current content (3 sections, no rationale, no MTK Patterns)

### Secondary (MEDIUM confidence)
- Julia documentation manual conventions (standard language feature, HIGH confidence in practice)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Julia docstrings are a language feature with no external dependencies
- Architecture: HIGH — all source files read; exact gaps identified
- Pitfalls: HIGH — derived from reading the actual source and CONTEXT.md decisions

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (stable domain — Julia docstring format does not change)

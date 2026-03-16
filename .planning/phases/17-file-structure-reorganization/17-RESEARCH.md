# Phase 17: File Structure Reorganization - Research

**Researched:** 2026-03-16
**Domain:** Julia source file reorganization — mechanical file moves and include-order wiring
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Phase boundary:** Move source files on disk to match the canonical layout defined in CLAUDE.md. No logic changes, no new features, no physics changes. Every test must pass after the reorganization.
- **Files being reorganized:**
  - `src/components.jl` (monolithic) → split into 6 files under `src/components/`
  - `src/correlations.jl` → `src/physical_models/correlations.jl`
  - `src/helpers.jl` → `src/composition/helpers.jl`
  - PipeGeometry extracted from components.jl → `src/geometry.jl`
  - `build_loop*`/`build_cube` extracted from `solvers.jl` → `src/examples.jl`
  - `src/connectors.jl` and `src/fluids.jl` do NOT move.
- **steady_state_guess placement:** Stays in `solvers.jl` — it is a general-purpose solver utility, not an example-only helper. STR-05 text was imprecise; CLAUDE.md is authoritative.
- **Execution strategy:** Incremental — move one logical group, update `STREAM.jl` includes, run tests, then proceed to the next group.
- **Suggested sequence:** geometry.jl → components/ (one file at a time or as a batch if clearly safe) → physical_models/ → composition/ → examples.jl split.
- **STREAM.jl include order (after reorganization):**
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
- **Internal helpers placement:**
  - `_channel_base_eqs` lives in `components/channel.jl`
  - `_diffusion_eqs` lives in `components/heat_diffusion.jl`

### Claude's Discretion
- Exact include ordering within the components/ group (pump/resistors/misc order is flexible)
- Whether to create subdirectories in one mkdir call or one at a time

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| STR-01 | Codebase can load after `src/geometry.jl` is extracted from `components.jl` and `STREAM.jl` includes updated | PipeGeometry struct + 2 factory functions are cleanly self-contained at lines 14–101 of components.jl; no forward references |
| STR-02 | `components.jl` is split into 6 files under `src/components/` and all tests still pass | components.jl contains 6 logical units with clear boundaries; `_channel_base_eqs` must precede `thermal_channel.jl` in include order |
| STR-03 | `correlations.jl` is moved to `src/physical_models/correlations.jl` | correlations.jl has no dependencies on other src files; directory `src/physical_models/` must be created |
| STR-04 | `helpers.jl` is moved to `src/composition/helpers.jl` | helpers.jl depends on `t` (from MTK, already in scope) and `ThermalPort`, `FlowPort`, `System` (in scope via earlier includes); directory `src/composition/` must be created |
| STR-05 | `build_loop*`/`build_cube` are extracted from `solvers.jl` into `src/examples.jl`; `steady_state_guess` stays in `solvers.jl` | Four functions to extract: `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_cube` (lines 53–342 in solvers.jl); `steady_state_guess` (lines 20–24) stays |
</phase_requirements>

## Summary

Phase 17 is a pure mechanical refactor: move Julia source code from the current flat `src/` layout to the canonical nested layout specified in CLAUDE.md. There are zero logic changes. The work consists of:

1. Creating three new subdirectories (`src/components/`, `src/physical_models/`, `src/composition/`)
2. Splitting `src/components.jl` (656 lines) into six dedicated files
3. Moving `src/correlations.jl` to `src/physical_models/correlations.jl` (file copy + delete)
4. Moving `src/helpers.jl` to `src/composition/helpers.jl` (file copy + delete)
5. Extracting the four example builders from `src/solvers.jl` into a new `src/examples.jl`
6. Rewriting the six `include()` calls in `src/STREAM.jl` to thirteen includes in the correct forward-reference order

The only non-trivial risk is include ordering: `_channel_base_eqs` (defined in `channel.jl`) is called by both `ChannelHeatFlux` and `ChannelAndContacts` which must live in a separate file (`thermal_channel.jl`) included after `channel.jl`. All other splits are independent.

**Primary recommendation:** Follow the locked incremental sequence from CONTEXT.md exactly. Run `julia --project=. -e 'using STREAM'` and the full test suite after each logical group to catch forward-reference errors immediately.

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Julia file system | stdlib | `mkdir`, file write | No third-party tool needed for file moves |
| `include()` in Julia | stdlib | Wires split files into module | Standard Julia module composition mechanism |
| `Pkg.test()` / `julia --project=. test/runtests.jl` | stdlib | Validation after each step | Single monolithic runtests.jl covers all symbols |

No new libraries are introduced. This phase uses only what is already present.

## Architecture Patterns

### Canonical Post-Reorganization Structure
```
src/
  STREAM.jl                        # updated include list (13 includes)
  geometry.jl                      # PipeGeometry struct + factories (extracted)
  connectors.jl                    # unchanged
  fluids.jl                        # unchanged
  components/
    channel.jl                     # Channel + _channel_base_eqs
    pump.jl                        # Pump
    resistors.jl                   # Friction, Gravity, Resistor
    misc.jl                        # Inertia, HeatExchanger, ConstantTemperature
    thermal_channel.jl             # ChannelAndContacts, ChannelHeatFlux
    heat_diffusion.jl              # _diffusion_eqs + HeatDiffusion
  physical_models/
    correlations.jl                # moved (unchanged content)
  composition/
    helpers.jl                     # moved (unchanged content)
  solvers.jl                       # unchanged except 4 functions removed
  examples.jl                      # new file: build_loop, build_loop_vertical,
                                   #           build_loop_transient, build_cube
```

### Pattern 1: Incremental Move-and-Verify
**What:** Each logical group is moved in one commit, then the test suite is run before proceeding.
**When to use:** Whenever splitting a file where forward-reference errors are possible.
**Example:**
```
Step 1: Create src/geometry.jl, update STREAM.jl includes → run tests
Step 2: Create src/components/ dir and 6 files, update STREAM.jl → run tests
Step 3: Create src/physical_models/ dir, move correlations.jl → update STREAM.jl → run tests
Step 4: Create src/composition/ dir, move helpers.jl → update STREAM.jl → run tests
Step 5: Create src/examples.jl, trim solvers.jl → update STREAM.jl → run tests
```

### Pattern 2: STREAM.jl as the Single Wiring Point
**What:** All `include()` calls live only in `src/STREAM.jl`. Component files contain zero `include()` or `export` statements.
**When to use:** Always — this is the established project convention.

### Anti-Patterns to Avoid
- **Adding `export` inside component files:** CLAUDE.md forbids this; all exports stay in `STREAM.jl`.
- **Adding `using ModelingToolkit` inside component files:** MTK is imported once at module level in `STREAM.jl`; component files rely on the module scope.
- **Moving `steady_state_guess` to `examples.jl`:** CONTEXT.md locked this — it stays in `solvers.jl`.
- **Batching all moves before running tests:** Violates the locked incremental strategy; breaks early feedback.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Verifying include order correctness | Custom dependency graph tool | Run `julia --project=. -e 'using STREAM'` | Julia's loader gives an immediate MethodError or UndefVarError if a symbol is used before it is defined |
| Testing that all symbols still work after moves | Manual symbol inventory | Existing `test/runtests.jl` (161 tests) | Every public symbol is exercised by the existing suite |

**Key insight:** This phase has no algorithm or library complexity. The entire verification strategy is "run `using STREAM` and `Pkg.test()`." The hard part is sequencing, not code.

## Common Pitfalls

### Pitfall 1: Forward Reference in Include Order
**What goes wrong:** `thermal_channel.jl` calls `_channel_base_eqs` which is defined in `channel.jl`. If `thermal_channel.jl` is included before `channel.jl`, Julia raises `UndefVarError: _channel_base_eqs not defined`.
**Why it happens:** Julia evaluates `include()` sequentially at module load time; it does not pre-scan for symbols.
**How to avoid:** Follow the locked include order exactly: `channel.jl` at position 5, `thermal_channel.jl` at position 9.
**Warning signs:** `UndefVarError` for `_channel_base_eqs` when loading the module.

### Pitfall 2: Missing `using` / Import in Component Files
**What goes wrong:** Component files that use `Differential`, `@parameters`, `@variables`, `connect`, etc. will work because these are in scope from `STREAM.jl`'s `using ModelingToolkit`. This is correct — do NOT add redundant `using` statements inside component files.
**Why it happens:** Developers familiar with multi-file projects outside Julia modules sometimes add `using` per file. In Julia, `include()` pastes the file into the enclosing module scope.
**How to avoid:** No `using` statements in any component file; all imports live in `STREAM.jl`.
**Warning signs:** Duplicate method warnings if MTK gets `using`-imported twice.

### Pitfall 3: `solvers.jl` Still Needs Its `using` Statements
**What goes wrong:** `solvers.jl` has its own `using ModelingToolkit`, `using DifferentialEquations`, `using Sundials` at the top. These are redundant given `STREAM.jl` imports, but removing them would be a logic change outside this phase's scope.
**Why it happens:** `solvers.jl` was apparently designed to be loadable standalone.
**How to avoid:** Leave the `using` statements at the top of `solvers.jl` untouched during this phase.

### Pitfall 4: `examples.jl` Needs All Referenced Symbols in Scope
**What goes wrong:** `build_loop`, `build_loop_vertical`, `build_loop_transient`, and `build_cube` reference `Pump`, `Channel`, `HeatExchanger`, `Gravity`, `Resistor`, `PipeGeometry_circular`, `System`, `compose`, `mtkcompile`, `connect`, `@named`, `@parameters`, `t`. All of these are in scope by the time `examples.jl` is included (position 13 in the locked order).
**Why it happens:** Not a problem given the correct include order; mentioning as confirmation.
**How to avoid:** Ensure `examples.jl` is included after `solvers.jl` (which is after all components). The locked order already guarantees this.

### Pitfall 5: Stale `components.jl` Left on Disk
**What goes wrong:** If `src/components.jl` is not deleted after the split, `include("components.jl")` in an outdated `STREAM.jl` would load duplicate symbol definitions. Julia allows method redefinition with a warning, not an error, so this could silently create confusing duplicate definitions.
**Why it happens:** Forgetting to delete the source file after splitting.
**How to avoid:** Delete `src/components.jl` (and old `src/correlations.jl`, `src/helpers.jl`) as part of the same step that creates the new files. Confirm with `ls src/` before running tests.

### Pitfall 6: Content Split Boundary Errors
**What goes wrong:** Accidentally splitting `_channel_base_eqs` into `thermal_channel.jl` (where it is first visually proximate) rather than `channel.jl`.
**Why it happens:** `_channel_base_eqs` appears between `Channel` and `ChannelAndContacts` in `components.jl` (lines 298–355). It logically belongs to `channel.jl` because it is called by `Channel`'s successors.
**How to avoid:** CONTEXT.md locked this: `_channel_base_eqs` → `channel.jl`. Follow the locked decision.

## Code Examples

### Exact content boundaries in `src/components.jl`

```
geometry.jl content:      lines 1–101   (PipeGeometry struct, PipeGeometry_rectangular, PipeGeometry_circular)
channel.jl content:       lines 103–355 (Channel function declaration + body, _channel_base_eqs)
pump.jl content:          lines 179–207 (Pump)
resistors.jl content:     lines 209–259 (Friction, Gravity, Resistor)
misc.jl content:          lines 261–295 + 539–545 (Inertia, HeatExchanger, ConstantTemperature)
thermal_channel.jl:       lines 357–536 (ChannelAndContacts, ChannelHeatFlux)
heat_diffusion.jl:        lines 547–656 (_diffusion_eqs, HeatDiffusion)
```

Note: `misc.jl` content (Inertia, HeatExchanger, ConstantTemperature) is non-contiguous in `components.jl` — Inertia/HeatExchanger are at lines 261–296, ConstantTemperature is at line 539–545. The planner must account for these non-adjacent code sections when writing the move task.

### STREAM.jl after reorganization (updated include block)
```julia
include("fluids.jl")
include("connectors.jl")
include("geometry.jl")
include("physical_models/correlations.jl")
include("components/channel.jl")
include("components/pump.jl")
include("components/resistors.jl")
include("components/misc.jl")
include("components/thermal_channel.jl")
include("components/heat_diffusion.jl")
include("composition/helpers.jl")
include("solvers.jl")
include("examples.jl")
```

### Exact content boundaries in `src/solvers.jl`

```
steady_state_guess:   lines 20–24   → STAYS in solvers.jl
build_loop:           lines 53–83   → moves to examples.jl
solve_steady:         lines 99–108  → STAYS in solvers.jl
build_loop_vertical:  lines 134–178 → moves to examples.jl
build_loop_transient: lines 196–232 → moves to examples.jl
solve_transient:      lines 251–274 → STAYS in solvers.jl
build_cube:           lines 299–342 → moves to examples.jl
```

### Test command for incremental validation
```bash
cd /home/itay/projects/Julia-STREAM && julia --project=. -e 'using STREAM; println("load ok")'
cd /home/itay/projects/Julia-STREAM && julia --project=. -e 'using Pkg; Pkg.test()'
```

## State of the Art

| Old Layout | New Layout | When | Impact |
|------------|------------|------|--------|
| `src/components.jl` (monolithic, 656 lines) | `src/components/` (6 files) | Phase 17 | Each file now owns one concern; easier to locate and edit |
| `src/correlations.jl` | `src/physical_models/correlations.jl` | Phase 17 | Matches Python STREAM `physical_models/` naming |
| `src/helpers.jl` | `src/composition/helpers.jl` | Phase 17 | Matches CLAUDE.md canonical layout |
| example builders mixed in `solvers.jl` | `src/examples.jl` | Phase 17 | Solver logic is isolated from demo code |

## Open Questions

1. **`misc.jl` non-contiguous content**
   - What we know: `Inertia` and `HeatExchanger` are at lines 261–296; `ConstantTemperature` is at line 539–545 (separated by ~240 lines of `_channel_base_eqs`, `ChannelAndContacts`, `ChannelHeatFlux`).
   - What's unclear: Whether the planner should copy each block separately or note the non-contiguous nature explicitly.
   - Recommendation: Task description should explicitly call out that `misc.jl` requires grabbing two non-adjacent code sections.

2. **`solvers.jl` header comments after extraction**
   - What we know: `solvers.jl` has a file-level comment block at lines 1–7 that says "Solver API for STREAM.jl".
   - What's unclear: Whether the `using` statements at lines 8–10 should be cleaned up (removing redundant `using ModelingToolkit` already imported at module level).
   - Recommendation: Leave `solvers.jl` exactly as-is except removing the four extracted functions — no cleanup in this phase; that is a separate concern.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia `Test` stdlib |
| Config file | none — single `test/runtests.jl` monolith |
| Quick run command | `julia --project=. -e 'using STREAM; println("ok")'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STR-01 | Package loads after geometry.jl extracted | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :PipeGeometry)'` | ✅ (FOUND-01 in runtests.jl) |
| STR-02 | All 11 components accessible post-split | smoke + unit | `julia --project=. -e 'using Pkg; Pkg.test()'` | ✅ (all component tests in runtests.jl) |
| STR-03 | correlations.jl accessible from new path | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :dittus_boelter)'` | ✅ (correlation tests in runtests.jl) |
| STR-04 | helpers.jl accessible from new path | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :symmetric_plate)'` | ✅ (composition tests in runtests.jl) |
| STR-05 | build_loop* and build_cube accessible from examples.jl | smoke | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :build_loop)'` | ✅ (example tests in runtests.jl) |

### Sampling Rate
- **Per step (after each logical group move):** `julia --project=. -e 'using STREAM; println("load ok")'`
- **Per wave merge:** `julia --project=. -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green (all 161 tests pass) before `/gsd:verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all phase requirements. This phase adds no new functionality, so no new test files are needed.

## Sources

### Primary (HIGH confidence)
- Direct inspection of `src/components.jl` (656 lines) — exact line boundaries for all 6 component groups confirmed
- Direct inspection of `src/solvers.jl` (343 lines) — exact line boundaries for functions to move vs. keep
- Direct inspection of `src/STREAM.jl` — current include list (6 includes) confirmed
- `17-CONTEXT.md` — locked decisions from user discussion session
- `CLAUDE.md` — canonical file structure standard (authoritative for placement)

### Secondary (MEDIUM confidence)
- Julia language documentation: `include()` pastes file into enclosing module scope; no `using` needed per-file

### Tertiary (LOW confidence)
None.

## Metadata

**Confidence breakdown:**
- File content boundaries: HIGH — read directly from source files
- Include order: HIGH — locked in CONTEXT.md with rationale
- Forward-reference analysis: HIGH — confirmed by reading all 6 component definitions
- Pitfalls: HIGH — derived from direct code inspection, not assumptions

**Research date:** 2026-03-16
**Valid until:** 2026-04-16 (stable; source files do not change between research and planning in this milestone)

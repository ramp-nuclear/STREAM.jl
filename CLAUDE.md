# STREAM.jl — Claude Code Instructions

## Purpose

This project aims to replace eventually the Python STREAM implementation
and should be compared against it, especially for physics and features.
The Python implementation can be found at [here](https://github.com/ramp-nuclear/STREAM),
or locally in a nearby folder.

## Coding Rules

When writing or editing Julia code, follow the conventions in `JULIA.md` (repo root). `JULIA.md` governs general Julia.

**MUST USE — MTK skill.** Before writing or editing ANY ModelingToolkit code (anything touching `System`, `@mtkmodel`/`@mtkcompile`/`mtkcompile`, `@variables`/`@parameters`/`@connector`, `connect`, problem/solution construction, `unknowns`/`observed`, initialization, `GlobalScope`, callbacks, `@register_symbolic`, or any SciML solve), you MUST invoke the `modelingtoolkit-jl` skill (`.claude/skills/modelingtoolkit-jl/`) first and follow it — do not rely on auto-trigger or prior knowledge, since training data for MTK is stale and emits removed APIs (`ODESystem`, `structural_simplify`, `states`, 4-arg problems, integer indexing). The skill takes precedence on MTK-specific API; `JULIA.md` governs general Julia. Read the relevant `references/*.md` before writing in that area.

**MUST USE — humanizer for ALL prose.** No text anywhere in this repo should read as AI slop. Every piece of prose you write or edit — inline comments, docstrings, test/`@testset` names, commit messages, and `.md` files — must pass the `/humanizer` skill: no em dashes, no rule-of-three padding, no "AI vocabulary" or promotional/significance filler, plain and specific. Run `/humanizer` over prose before committing it, and over every GitHub comment/PR/issue body before it is shown for posting (see the no-auto-post rule: draft → humanize → show the user → they confirm → post). The whole existing codebase is also slated for a humanizer sweep; until then, at minimum leave any prose you touch cleaner than you found it.

## Units

Temperatures are **Celsius** everywhere: component arguments, connector variables, solution
values, and correlation inputs. This matches Python STREAM, which is the reference
implementation. Pressures are Pa, and the per-degree units (`J/(kg·K)`, `W/(m·K)`, `1/K`) are
unchanged since a degree Celsius and a kelvin are the same size.

## Project Conventions

- **No GSD jargon in code.** Source, comments, docstrings, and test names never reference GSD phases, plans, or milestone IDs (no `# Phase 55 D-17`, no `test_phase_NN`). Name things for what they are. Test files mirror their source file (see File Structure Standard).
- **Docstrings have a purpose and read like a human wrote them.** Every exported name carries a docstring (description, `# Arguments`, `# Returns`). Run `/humanizer` over docstring prose; do not pad with AI-tone filler. General comment discipline lives in `JULIA.md` §0.
- **Delete, don't archive.** When a milestone or phase completes, delete its planning `.md` files instead of moving them to an archive. Keep only currently-in-work planning docs.
- **Merge is squash-only.** The repo ruleset permits only squash merges into `main` (linear history, PR required, review threads resolved). No rebase/FF or merge commits.

## Branching Policy

**The user owns branch creation. GSD must never create its own branches.**

The user creates one working branch per milestone (e.g. `channels-redesign` for v1.1) off `main`, and Claude works only on that branch for the duration of the milestone. When the milestone is complete and archived through GSD, the user opens a single PR from the working branch into `main`.

Hard rules:
- `.planning/config.json` `git.branching_strategy` MUST stay `"none"`. Do not "fix" it back to `"milestone"` or `"phase"` — those values cause GSD's `handle_branching` step to auto-create a `gsd/<...>` branch off the working branch, which has happened before and required manual consolidation.
- Never run `git switch`, `git checkout -b`, or `git branch <new>` without an explicit instruction from the user in the current message.
- At session start, before any commit, verify the current branch matches the user's intended working branch (read `.planning/STATE.md` "Working branch" line and confirm `git rev-parse --abbrev-ref HEAD` matches). If it does not, stop and ask before committing.
- Worktree-isolated executor agents (Claude Code's `isolation="worktree"`) are exempt — they create temporary `worktree-agent-*` branches that exist only inside the worktree and are deleted after merge. That is not a violation of this policy.

## File Structure Standard

This is the canonical layout. **Always follow it when editing or adding files.**

### `src/` — Source

```
src/
  STREAM.jl                   # Module entry point: imports, includes, exports only
  constants.jl                # G_EARTH and friends
  geometry.jl                 # PipeGeometry struct + PipeGeometry_rectangular, PipeGeometry_circular
  connectors.jl               # FlowPort, ThermalPort acausal connectors
  knobs.jl                    # @design_knob, knob_defaults
  substances/
    liquid.jl                 # AbstractLiquid interface, Liquid snapshot, unicode aliases (ρ, cₚ, μ, κ, β, Tsat)
    light_water.jl            # LightWater / H2O correlations
    heavy_water.jl            # HeavyWater / D2O correlations
  physical_models/
    dimensionless.jl          # Re, Pr, Nu, Pe, Gr, Ra, including the (liquid, T) forms
    htc/
      correlations.jl         # Nusselt correlations and the closures that select between them
      single_phase.jl         # h_single_phase: a Nusselt correlation evaluated at film temperature
    subcooled_boiling.jl      # SCB heat flux, ONB superheat, h_subcooled_boiling
    pressure_drop/
      friction.jl             # Darcy friction factor correlations
      local.jl                # Idelchik expansion / contraction local losses
    thresholds.jl             # CHF, OFI, OSV, ONB, wall-temperature limit correlations
  components/
    twoports.jl               # HydraulicTwoPort, shared by the two-port components
    pump.jl                   # Pump (fixed-dP and fixed-mdot modes)
    flapper.jl                # Flapper
    resistors.jl              # Friction, Gravity, Resistor, VolumetricFlowResistor, LocalPressureDrop
    ideal.jl                  # Inertia, HeatExchanger, ConstantTemperature
    sources.jl                # WallTemperature, HeatFluxSource, ConvectiveBoundary (external inputs)
    channels.jl               # Channel, ChannelHeatFlux, ChannelAndContacts + shared private core
    heat_diffusion.jl         # HeatDiffusion (2D FD solid plate)
    point_kinetics.jl         # PointKinetics (any group count), ReactivityController, SCRAM
  composition/
    connections.jl            # inseries, inparallel, connect_face(s), port, compose_systems,
                              # check_gravity_mismatch, connect_temperature_feedback
    assemblies.jl             # symmetric_plate, plate, one_sided_connection,
                              # single_channel_connection, fuel_assembly
  solvers.jl                  # solve_steady, solve_transient, steady_state_guess
  analysis.jl                 # ChannelState + the post-solve threshold wrappers
  utilities.jl                # rebin_*, cosine_power_shape, cosine_T_wall_profile
  examples.jl                 # build_loop*, build_cube, build_loop_pk
```

**Where new code goes:**
- New component (single MTK component) → `src/components/` in the most relevant file, or a new file if it's a new domain
- New correlation → the matching `src/physical_models/` folder: Nusselt into `htc/`, friction or local loss into `pressure_drop/`, a safety limit into `thresholds.jl`
- New composition helper → `connections.jl` for wiring primitives, `assemblies.jl` for named arrangements of components
- New coolant → `src/substances/` (e.g. `src/substances/molten_salt.jl`), implementing the nine `AbstractLiquid` property methods
- Build/example helpers → `src/examples.jl` only (never add examples to core files)

Placement beats file length. A long file whose contents all belong together is fine; a short
file named `misc` or `helpers` is not. Physics goes in `physical_models/`, even when a
component is its only caller: components state equations, they do not define correlations.

### `test/` — Tests

```
test/
  runtests.jl               # Thin orchestrator: one include() per test file, nothing else
  test_geometry.jl          # PipeGeometry
  test_connectors.jl        # FlowPort, ThermalPort
  test_substances.jl        # AbstractLiquid interface, H2O/D2O correlations, Liquid snapshot
  test_channels.jl          # Channel/CHF/CAC variants + _channel_core enthalpy-form physics
                            # + flow-reversal sign safety + subcooled-boiling integration (ISCB)
  test_pump.jl              # Pump
  test_flapper.jl           # Flapper
  test_resistors.jl         # Friction, Gravity, Resistor, network tests
  test_ideal.jl             # Inertia, HeatExchanger, ConstantTemperature, WallTemperature, HeatFluxSource
  test_heat_diffusion.jl    # HeatDiffusion
  test_correlations.jl      # HTC + friction correlation function unit tests
  test_thresholds.jl        # CHF/OFI/OSV/ONB/twall + ChannelState
  test_composition.jl       # symmetric_plate, plate, one_sided_connection, compose_systems,
                            # port, check_gravity_mismatch, _infer_n, connect_temperature_feedback,
                            # fuel_assembly — heavy CAC<->HD coverage
  test_utilities.jl         # rebin_extensive/intensive, cosine_power_shape, cosine_T_wall_profile
  test_solvers.jl           # steady_state_guess + solve_steady/solve_transient wrappers (src/solvers.jl)
  test_examples.jl          # build_loop* / build_cube builders + loss-of-flow transient (src/examples.jl)
  test_determinacy.jl       # equation/unknown balance (fully_determined) for builders + scenarios
  test_validation.jl        # Quantitative cross-validation against Python STREAM
  test_integration.jl       # STRICT 1:1 port of Python tests/test_general/test_integrations.py —
                            # exactly the 21 Python integration tests, nothing else
  test_point_kinetics.jl    # PointKinetics component-unit tests + coupled neutronics/T-H
                            # feedback loops (SCRAM, cold-IC, prompt-jump)
```

**Test placement rule:** test file mirrors src file. `components/channels.jl` → `test_channels.jl`. New component file → new test file. The value-source family (`WallTemperature`, `HeatFluxSource` in `src/components/sources.jl`) is a documented exception — its unit tests live in `test_ideal.jl` alongside `ConstantTemperature` (same value-source family). `physical_models/` is covered by `test_correlations.jl` (htc, pressure_drop) and `test_thresholds.jl`.

## Component authoring conventions

- **Positional arguments** when: (a) the argument type determines behavior, enabling multiple dispatch (e.g., `Pump(dP::Real; name)` vs `Pump(dP::Any; name)`); OR (b) the constructor/function has 1 or fewer physics parameters and its role is unambiguous from the function name (e.g., `Resistor(R; name)`, `Gravity(H; name)`, `HeatExchanger(T_bc; name)`).
  *Why: Positional args with type annotations enable Julia's multiple dispatch and keep call sites concise when the meaning is obvious.*
- **Keyword arguments** when: multiple arguments of the same type where labeling prevents order bugs (e.g., `Channel(; name, L, Dh, ...)` has many Float64 params); OR complex constructors with many parameters where self-documentation outweighs brevity.
  *Why: Keyword-only prevents argument-order bugs for multi-parameter constructors where positional would be ambiguous.*
- Factory functions (`PipeGeometry_rectangular`, `PipeGeometry_circular`) use positional arguments (established in v0.4).
- The `name` kwarg is **always keyword-only** (provided by `@named` macro, never positional).
  *Why: The `@named` macro injects `name=:varname` as a keyword argument. Making it positional would break `@named`.*
- Internal helpers are prefixed with `_` and not exported.
  *Why: Keeps the public API surface small and signals that these functions may change without notice. The `_` prefix is a Julia community convention.*
- Every exported name has a docstring with at minimum: description, `# Arguments`, `# Returns`.
  *Why: The REPL `?name` lookup is the primary discovery mechanism for Julia packages. Structured sections make docstrings scannable.*

## Exports

All public exports are declared in `STREAM.jl`. Never add `export` statements inside component files.
  *Why: A single export list in the module entry point makes the public API auditable at a glance. Scattered exports are easy to lose track of.*

## MTK Patterns

Non-obvious ModelingToolkit conventions used throughout the codebase.

### `@register_symbolic` for fluid properties

Plain Julia functions cannot accept MTK's `Num` type (symbolic variables). `@register_symbolic` wraps them as opaque nodes in the symbolic expression graph, allowing them to appear in MTK equations without being traced or differentiated symbolically by Symbolics.jl.

### `ifelse()` for flow reversal and regime switching

Julia's `if`/`else` on a symbolic `Num` expression would evaluate the branch condition at trace time (equation construction), collapsing to a single branch permanently. `ifelse()` emits a symbolic conditional node that the solver evaluates at each timestep, enabling correct flow-reversal and laminar/turbulent regime switching.

### `vars=[]` for Inertia

When `Dt(port_in.mdot)` appears in an equation, MTK automatically promotes `port_in.mdot` to a differential state variable. Explicitly listing it in `vars` would be redundant. Passing `vars=[]` makes clear that the component introduces no *additional* state variables beyond what MTK infers.

### `@observed` vs plain unknowns

`@observed` variables are computed post-solve from the solution trajectory -- they are not part of the DAE system. Use `@observed` for diagnostic quantities (e.g., `Re`, `Nu`, `htc`) that are never referenced on the RHS of another equation. If a variable appears in another equation, it must be a plain unknown so the solver can see it.

### `mtkcompile` before solve

MTK's symbolic IR requires structural analysis (index reduction from DAE to ODE), Jacobian sparsity detection, and code generation before a numerical solver can use it. Always call `mtkcompile(sys)` to produce a compiled system. Passing an uncompiled `System` to `solve` will error or produce wrong results.

## Running the code

```bash
julia --project=. test/runtests.jl        # full suite
julia --project=. test/test_channels.jl   # a single file
julia --project=. examples/simple_loop.jl
```

Each invocation pays full cold-start (~30–90s `using STREAM` plus first `mtkcompile` ~10–30s). That is the accepted dev loop.

### Abandoned approaches — do not re-introduce

Two attempts to beat cold-start were tried and abandoned. Do not bring either back:

- **Daemon dev loop** (`Revise` + `DaemonMode`, `bin/jl*` scripts, tmux session `stream-jl`). A Claude-Code-specific speedup that did not pay off; fully removed from this branch (scripts, the `DaemonMode`/`Revise` deps, and `time_startup.jl`).
- **PackageCompiler sysimage** (`stream.so`). PackageCompiler's incremental link step is killed by SIGTERM at ~7 min on Julia 1.12 + WSL2 regardless of package set. Tooling was removed in v1.0. Historical `--sysimage` references under `.planning/` are archive only — do not act on them.

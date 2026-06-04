# STREAM.jl — Claude Code Instructions

## Coding Rules

When writing or editing Julia code, follow the conventions in `JULIA.md` (repo root). For ModelingToolkit code, the `modelingtoolkit-jl` skill (`.claude/skills/modelingtoolkit-jl/`) auto-triggers and takes precedence on MTK-specific API usage; `JULIA.md` governs general Julia.

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
  geometry.jl                 # PipeGeometry struct + PipeGeometry_rectangular, PipeGeometry_circular
  connectors.jl               # FlowPort, ThermalPort acausal connectors
  fluids.jl                   # @register_symbolic fluid properties (rho_water, cp_water, mu_water, k_water)
  components/
    pump.jl                   # Pump (fixed-dP and fixed-mdot modes)
    resistors.jl              # Friction, Gravity, Resistor
    misc.jl                   # Inertia, HeatExchanger, ConstantTemperature
    sources.jl                # WallTemperature, HeatFluxSource (value-source subsystems for channel external inputs)
    channels.jl               # Channel, ChannelHeatFlux, ChannelAndContacts + _channel_core (shared private core)
    heat_diffusion.jl         # HeatDiffusion + _diffusion_eqs (2D FD solid plate)
  physical_models/
    correlations.jl           # HTC + friction correlation closures
  composition/
    helpers.jl                # symmetric_plate, plate, one_sided_connection, compose_systems, port, check_gravity_mismatch
  solvers.jl                  # solve_steady, solve_transient, steady_state_guess
  examples.jl                 # build_loop, build_loop_vertical, build_loop_transient, build_cube
```

**Where new code goes:**
- New component (single MTK component) → `src/components/` in the most relevant file, or a new file if it's a new domain (e.g. `point_kinetics.jl`, `flapper.jl`)
- New physical correlation (HTC, friction, etc.) → `src/physical_models/correlations.jl` until that file exceeds ~300 lines, then split into `src/physical_models/htc/` and `src/physical_models/friction/` (mirroring Python STREAM `physical_models/`)
- New composition helper → `src/composition/helpers.jl`
- New fluid → `src/fluids/` subfolder (e.g. `src/fluids/light_water.jl`, `src/fluids/heavy_water.jl`) when multi-fluid support is added
- Build/example helpers → `src/examples.jl` only (never add examples to core files)

### `test/` — Tests

```
test/
  runtests.jl               # Thin orchestrator: one include() per test file, nothing else
  test_geometry.jl          # PipeGeometry tests (PHY-01)
  test_connectors.jl        # FlowPort, ThermalPort (HeatFluxPort retired in Phase 55 D-06)
  test_fluids.jl            # Fluid property functions (FOUND-02)
  test_channels.jl          # Channel/CHF/CAC variants + _channel_core enthalpy-form physics
                            # + flow-reversal sign safety (Phase 55 D-17 unified file —
                            # absorbs legacy test_channel.jl, test_channel_core.jl,
                            # test_sign_safety.jl)
  test_pump.jl              # Pump tests (COMP-02, PHY-05)
  test_flapper.jl           # Flapper tests
  test_resistors.jl         # Friction, Gravity, Resistor, network tests (COMP-03/04, NET-*)
  test_misc.jl              # Inertia, HeatExchanger, ConstantTemperature, WallTemperature, HeatFluxSource
  test_heat_diffusion.jl    # HeatDiffusion (HDIFF-01..05)
  test_correlations.jl      # HTC + friction correlation function unit tests
  test_thresholds.jl        # CHF/OFI/OSV/ONB/twall + ChannelState (renamed from test_analysis.jl, Phase 55 D-20)
  test_composition.jl       # symmetric_plate, plate, one_sided_connection, compose_systems,
                            # port, check_gravity_mismatch, _infer_n, connect_temperature_feedback
                            # — heavy CAC↔HD coverage (Phase 55 D-18)
  test_validation.jl        # Quantitative cross-validation against Python STREAM (Phase 56)
  test_integration.jl       # NEW: single big integration file — builders, solvers,
                            # LOF transient, ISCB, PK loops, COMPAT (Phase 55 D-19)
  test_point_kinetics.jl    # PK component-unit tests only (coupled-loop feedback now in
                            # test_integration.jl as PK-IC-01 + PK-FB-01/02, which replaced the
                            # retired TF-06/TF-07 — see .planning/notes/2026-05-29-pk-coupling-investigation.md)
```

**Test placement rule:** test file mirrors src file. `components/channels.jl` → `test_channels.jl`. New component file → new test file. The value-source family (`WallTemperature`, `HeatFluxSource` in `src/components/sources.jl`) is a documented exception — its unit tests live in `test_misc.jl` alongside `ConstantTemperature` (same value-source family) per Phase 55 D-21.

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

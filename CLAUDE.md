# STREAM.jl — Claude Code Instructions

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
    channel.jl                # Channel + _channel_base_eqs (basic convective channel)
    thermal_channel.jl        # ChannelAndContacts, ChannelHeatFlux (with ThermalPort arrays)
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
  runtests.jl               # Thin orchestrator: one @testset per include(), nothing else
  test_geometry.jl          # PipeGeometry tests (PHY-01)
  test_connectors.jl        # FlowPort, ThermalPort, package load (FOUND-01, CONN-01/02)
  test_fluids.jl            # Fluid property functions (FOUND-02)
  test_channel.jl           # Channel, ChannelAndContacts, ChannelHeatFlux (COMP-01, GRAV-*, CHAN-*, THERM-*, PHY-02/03/04)
  test_pump.jl              # Pump tests (COMP-02, PHY-05)
  test_resistors.jl         # Friction, Gravity, Resistor, network tests (COMP-03/04, NET-*)
  test_misc.jl              # Inertia, HeatExchanger (phase 8 COMP-01/02)
  test_heat_diffusion.jl    # HeatDiffusion (HDIFF-01..05)
  test_correlations.jl      # Correlation function unit tests (PHY-02/03/04 standalone)
  test_composition.jl       # Composition helpers, QoL (COMP-01..04, QOL-01..03)
  test_solvers.jl           # Solver integration tests (SYS-*, SOLV-*)
  test_validation.jl        # Quantitative cross-validation against Python STREAM (VAL-*)
  test_examples.jl          # build_loop / build_cube smoke tests (COMPAT)
```

**Test placement rule:** test file mirrors src file. `components/channel.jl` → `test_channel.jl`. New component file → new test file.

## Component authoring conventions

- All component constructor arguments are **keyword-only** (no positional args). Matches MTK convention everywhere.
  *Why: Keyword-only prevents argument-order bugs and makes call sites self-documenting. MTK's own `@mtkmodel` macro generates keyword-only constructors.*
- Factory functions (`PipeGeometry_rectangular`, `PipeGeometry_circular`) are also keyword-only.
  *Why: Consistency with component constructors. Mixing positional and keyword styles across the API creates confusion.*
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

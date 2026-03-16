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
- Factory functions (`PipeGeometry_rectangular`, `PipeGeometry_circular`) are also keyword-only.
- Internal helpers are prefixed with `_` and not exported.
- Every exported name has a docstring with at minimum: description, `# Arguments`, `# Returns`.

## Exports

All public exports are declared in `STREAM.jl`. Never add `export` statements inside component files.

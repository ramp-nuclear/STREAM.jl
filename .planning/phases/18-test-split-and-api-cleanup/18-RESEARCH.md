# Phase 18: Test Split and API Cleanup - Research

**Researched:** 2026-03-16
**Domain:** Julia test suite refactoring, keyword-only function signatures
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- All VAL-* tests land in `test_validation.jl` regardless of which phase introduced them (Phase 3 VAL-01/02, Phase 12 VAL-01/02/03, Phase 16 VAL-01/02)
- SOLV-01/02 tests (Phase 3: build_loop compiles, solve_steady/solve_transient behavior) go to `test_solvers.jl`
- All other placements follow CLAUDE.md file layout directly (component file -> matching test file)
- VAL-03 is NOT orphaned — it has real content (one-sided MTR adiabatic validation, line 1074). Keep it; move to `test_validation.jl`
- `solve_transient` converts from 4 positional args to fully keyword-only: `function solve_transient(; ssys, T_wall_sym, op, tspan, T_wall_final, t_step=10.0)`
- After split, `test/runtests.jl` contains ONLY `include()` calls — no `using` statements, no test logic
- Each `test_*.jl` file is self-contained with its own `using Test`, `using STREAM`, etc.

### Claude's Discretion

- Exact ordering of `include()` calls in the new `runtests.jl`
- Whether to add a top-level `@testset "STREAM.jl"` wrapper in runtests.jl or leave includes bare
- Handling the `const SciMLBase = ...` line (currently at file top for the RL-decay test) — move it into the relevant test file

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-01 | `test/runtests.jl` is a thin orchestrator of `include()` calls; all test logic lives in 13 dedicated `test_*.jl` files matching CLAUDE.md layout | Full test-to-file mapping documented below; all 1805 lines accounted for |
| QOL-01 | `solve_transient` converted to keyword-only signature; all call sites updated | Signature change documented; exactly 2 call sites in runtests.jl at lines 312 and 356; 0 call sites in src/ |
| QOL-02 | Orphaned `@testset "VAL-03"` Phase 1 placeholder removed | Already satisfied — VAL-03 at line 1074 has real content; move to test_validation.jl, do NOT delete |
</phase_requirements>

## Summary

Phase 18 is a pure mechanical refactoring with no logic changes. The 1805-line `test/runtests.jl` monolith is split into 13 self-contained `test_*.jl` files matching the CLAUDE.md canonical layout. The only logic change is the `solve_transient` function signature in `src/solvers.jl` — converting 4 positional arguments to keyword-only — and updating the 2 call sites in the test files.

The "orphaned VAL-03" requirement (QOL-02) is already satisfied by virtue of the split: the VAL-03 test at line 1074 has real, passing content and simply moves to `test_validation.jl` as part of the mechanical split. No tests are deleted.

**Primary recommendation:** Execute as two tasks — (1) split runtests.jl into 13 files with runtests.jl becoming a thin include-only orchestrator, then (2) convert solve_transient to keyword-only and update its 2 call sites.

## Standard Stack

This phase involves no new dependencies. The existing test infrastructure is:

| Tool | Purpose | Notes |
|------|---------|-------|
| `Test` stdlib | `@testset`, `@test`, `@test_nowarn` | Standard Julia test module |
| `Pkg.test()` | Runs `test/runtests.jl` | Entry point must remain `runtests.jl` |
| `julia test/test_X.jl` | Standalone file execution | Requires each file to be self-contained |

## Architecture Patterns

### Target File Layout (13 files)

Per CLAUDE.md canonical layout:

```
test/
  runtests.jl              # THIN ORCHESTRATOR: include() calls only
  test_geometry.jl         # PHY-01: PipeGeometry tests
  test_connectors.jl       # FOUND-01, CONN-01/02: FlowPort, ThermalPort, package load
  test_fluids.jl           # FOUND-02: rho_water, cp_water, mu_water, k_water
  test_channel.jl          # COMP-01 (Channel), GRAV-*, CHAN-*, THERM-*, PHY-02/03/04
  test_pump.jl             # COMP-02, PHY-05: Pump tests
  test_resistors.jl        # COMP-03/04, NET-*: Friction, Gravity, Resistor, network tests
  test_misc.jl             # COMP-01/02 (phase 8): Inertia, HeatExchanger
  test_heat_diffusion.jl   # HDIFF-01..05: HeatDiffusion
  test_correlations.jl     # PHY-02/03/04 standalone: correlation function unit tests
  test_composition.jl      # COMP-01..04, QOL-01..03: composition helpers, QoL
  test_solvers.jl          # SYS-*, SOLV-*: solver integration tests
  test_validation.jl       # VAL-*: all quantitative cross-validation tests
  test_examples.jl         # COMPAT: build_loop/build_cube smoke tests
```

### Complete Test-to-File Mapping

The following maps every named `@testset` block in `runtests.jl` to its destination file. Line numbers are from the current monolith.

**test_connectors.jl** (from Phase 1 "STREAM Phase 1 Tests", lines 9-118):
- `FOUND-01: Package loads` (line 14) — reaching this line proves `using STREAM` worked
- `CONN-01: FlowPort instantiation` (line 59)
- `CONN-01: FlowPort variable count` (line 68)
- `CONN-01: mdot is a Flow variable` (line 73)
- `CONN-01: T is a Stream variable` (line 81)
- `CONN-02: ThermalPort instantiation` (line 91)
- `CONN-02: ThermalPort variable count` (line 98)
- `CONN-02: Q_flow is a Flow variable` (line 103)
- `CONN-02: T is an across variable (no connect metadata)` (line 110)

**test_fluids.jl** (from Phase 1, lines 23-54):
- `FOUND-02: rho_water` (line 23)
- `FOUND-02: cp_water` (line 29)
- `FOUND-02: mu_water` (line 35)
- `FOUND-02: k_water` (line 41)
- `FOUND-02: MTK smoke test — rho_water symbolic` (line 47)

**test_geometry.jl** (lines 120-158, orphaned outside any Phase wrapper):
- `PHY-01: PipeGeometry_rectangular geometry` (line 120)
- `PHY-01: PipeGeometry_circular geometry` (line 144)

**test_pump.jl** (lines 163-199, orphaned outside any Phase wrapper):
- `PHY-05: Pump fixed-flow mode` (line 163)
- `PHY-05: Pump error cases` (line 194)

**test_channel.jl** (from Phase 2 "STREAM Phase 2 Tests", lines 201-238, plus Phase 6, Phase 9, Phase 10):
- Phase 2 (lines 201-238):
  - `COMP-01: Channel stub callable` (line 203)
  - `COMP-01: Channel equation count` (line 208)
  - `COMP-01: Channel mtkcompile` (line 214)
  - `COMP-02: Pump stub callable` (line 220) — NOTE: this is a Pump smoke test but lives in Phase 2 Channel tests
  - `COMP-03: Friction stub callable` (line 226)
  - `COMP-04: Gravity stub callable` (line 232)
- Phase 6 (lines 373-426):
  - `GRAV-01: vertical loop mtkcompiles` (line 380)
  - `GRAV-01: vertical loop solves` (line 385)
  - `GRAV-02: gravity cancellation within 1% of horizontal` (line 405)
- Phase 9 (lines 553-688):
  - `THERM-01: ChannelAndContacts callable` (line 558)
  - `THERM-01: ChannelAndContacts mtkcompile` (line 563)
  - `THERM-01: ChannelAndContacts has n ThermalPort subsystems` (line 568)
  - `THERM-02: Channel unmodified (regression)` (line 583)
  - `THERM-03: ChannelAndContacts two-sided matches ChannelHeatFlux within 0.1%` (line 596)
  - `CHAN-03: Unconnected thermal_right is adiabatic (Q_flow == 0)` (line 651)
- Phase 10 (lines 690-715):
  - `CHAN-01: ChannelAndContacts callable with dual ports` (line 695)
  - `CHAN-01: ChannelAndContacts mtkcompile (bare, no connections)` (line 700)
  - `CHAN-02: ConstantTemperature exported from STREAM` (line 705)
  - `CHAN-02: ConstantTemperature callable and mtkcompiles` (line 709)

**test_misc.jl** (from Phase 8 "STREAM Phase 8 Tests", lines 476-551):
- `COMP-01: Inertia stub callable` (line 482)
- `COMP-01: Inertia mtkcompile` (line 487)
- `COMP-01: RL-decay transient matches exp(-(R/L_over_A)*t) within 1%` (line 492)
- `COMP-02: HeatExchanger stub callable` (line 532)
- `COMP-02: HeatExchanger mtkcompile` (line 537)
- `COMP-02: HeatExchanger exported from STREAM` (line 542)
- `COMP-02: build_loop compiles after HeatExchanger rename (regression)` (line 546)

**test_solvers.jl** (from Phase 3 "STREAM Phase 3 Tests", lines 240-371):
- `SYS-01: build_loop compiles closed loop` (line 245)
- `SYS-02: steady_state_guess monotonically increasing` (line 254)
- `SOLV-01: solve_steady returns physical solution` (line 264)
- `SOLV-02: build_loop_transient compiles` (line 287)
- `SOLV-02: solve_transient returns time-series` (line 293)
- `COMPAT: Test suite runs automatically via Pkg.test()` (line 367)

**test_resistors.jl** (from Phase 7 "STREAM Phase 7 Tests", lines 428-474):
- `NET-01: Resistor stub callable` (line 433)
- `NET-01: Resistor mtkcompile` (line 438)
- `NET-02: build_cube assembles and mtkcompiles` (line 448)
- `NET-03: Cube flow matches 5/6 R analytical within 1%` (line 458)

**test_heat_diffusion.jl** (from Phase 11 "STREAM Phase 11 Tests" + Phase 12 HDIFF-03-gap):
- Phase 11 (lines 720-852):
  - `HDIFF-01: HeatDiffusion callable and returns MTK System` (line 725)
  - `HDIFF-01: HeatDiffusion exported from STREAM` (line 733)
  - `HDIFF-01: HeatDiffusion mtkcompile bare (no connections)` (line 737)
  - `HDIFF-01: HeatDiffusion state T[1:nz, 1:nx] present in unknowns` (line 745)
  - `HDIFF-04: HeatDiffusion has thermal_left and thermal_right subsystems` (line 760)
  - `HDIFF-02/03: Steady-state plate T > T_boundary and Q_flow signs correct` (line 776)
  - `HDIFF-05: Unconnected thermal_right has Q_flow == 0 (adiabatic)` (line 826)
- Phase 12 HDIFF gap (lines 854-908):
  - `HDIFF-03-gap: Non-uniform power_shape: center-only source cell is hottest` (line 861)

**test_correlations.jl** (from Phase 13 section, lines 1163-1234 standalone + 1236-1411 integration):
- Standalone unit tests (lines 1172-1234):
  - `PHY-02/03/04: Correlation Library` wrapper
  - `PHY-03: rectangular_laminar_correction reference values` (line 1174)
  - `dittus_boelter standalone function` (line 1182)
  - `blasius_friction standalone function` (line 1188)
  - `PHY-02: constant_Nusselt factory` (line 1194)
  - `PHY-03: laminar_friction factory` (line 1204)
  - `PHY-04: regime_dependent switching` (line 1213)
- Integration tests (lines 1243-1411):
  - `PHY-02/03/04: Integration Tests — Pluggable Correlations in Solved Systems` wrapper
  - `PHY-02: constant_Nusselt integration — Nu≈8.235 in solution` (line 1249)
  - `PHY-03: laminar_friction integration — dP > 0 in solution` (line 1286)
  - `PHY-04: regime_dependent integration — laminar branch (Re < 2300)` (line 1330)
  - `PHY-04: regime_dependent integration — turbulent branch (Re > 2300)` (line 1371)

**test_composition.jl** (from Phase 15 section, lines 1413-1657):
- `QOL-01: @observed Re/Nu accessible via sol` (line 1422)
- `QOL-02: check_gravity_mismatch — balanced loop` (line 1465)
- `QOL-02: check_gravity_mismatch — unbalanced loop :mismatch` (line 1472)
- `QOL-03: port() helper` (line 1491)
- `COMP-01: symmetric_plate — builds and solves` (line 1507)
- `COMP-02: plate — two-channel wiring` (line 1531)
- `COMP-03: one_sided_connection — single face` (line 1563)
- `COMP-04: compose_systems — variadic wrapper` (line 1587)
- `COMP: symmetric_plate — physics verification (energy balance)` (line 1620)

**test_validation.jl** (Phase 3 VAL-01/02, Phase 12 VAL-01/02/03, Phase 16 VAL-01/02):
- Phase 3 (lines 329-362):
  - `VAL-01: Steady-state matches Python STREAM within 1%` (line 329)
  - `VAL-02: Transient T_outlet rises after T_wall step` (line 346)
- Phase 12 (lines 913-1161):
  - `VAL-01: Symmetric MTR — HeatDiffusion + two ChannelAndContacts` (line 913)
  - `VAL-02: Asymmetric MTR — right channel at 363.15 K inlet` (line 1005)
  - `VAL-03: One-sided MTR — left channel only, thermal_right adiabatic` (line 1074)
- Phase 16 (lines 1662-1805):
  - `VAL-01: HeatDiffusion transient — Fourier series validation` (line 1670)
  - `VAL-02: Two-plate one-channel topology — both faces active` (line 1737)

**test_examples.jl** (the COMPAT test is already assigned to test_solvers.jl; test_examples.jl may be stub-only or not created if no example-specific tests exist beyond COMPAT)

### Special Cases and Non-Obvious Decisions

**The `import STREAM: check_gravity_mismatch, port` line (line 1420):** This is a local import that was needed at the time these helpers were added. In the split, `test_composition.jl` will use `using STREAM` at the top (like all other files), making this import redundant. It should be dropped; the `using STREAM` statement provides these symbols.

**The `const SciMLBase = ...` line (line 7):** `const SciMLBase = DifferentialEquations.SciMLBase` exists only to support `SciMLBase.NoInit()` in the RL-decay test (line 518) inside Phase 8 tests. This line moves into `test_misc.jl` as a local const.

**The top-level free variables (lines 326-327):** `T_outlet_ref` and `mdot_ref` are defined as bare constants outside any `@testset` (before VAL-01 at line 329). These move into `test_validation.jl` as local constants before the testsets that use them.

**Phase 12 HDIFF-03-gap testset (lines 854-908):** This block sits inside `@testset "STREAM Phase 12 Tests"` but tests HeatDiffusion, not MTR validation. It belongs in `test_heat_diffusion.jl`.

**The `const geom_comp` and `const ps_comp` lines (lines 1503-1505):** These shared geometry constants for COMP tests move into `test_composition.jl` as file-level constants before the testsets that use them.

**The Phase 16 wrapper `@testset "Phase 16: Validation"` (line 1662, ends line 1805):** The outer wrapper is dropped; the inner testsets go directly into `test_validation.jl` without a Phase-number wrapper (they get the file's structure, not the phase label).

**test_examples.jl:** CLAUDE.md lists this file for `build_loop / build_cube smoke tests (COMPAT)`. The COMPAT test currently sits in what will become `test_solvers.jl`. Since CLAUDE.md explicitly names `test_examples.jl`, it should exist — either with the COMPAT test moved there from test_solvers.jl, or as a minimal stub with a single `@test true` confirming the file is present. Moving COMPAT to test_examples.jl is cleaner since COMPAT specifically tests `build_loop`/`build_cube` callable via `Pkg.test()`.

### runtests.jl Structure After Split

```julia
# test/runtests.jl — thin orchestrator
include("test_geometry.jl")
include("test_connectors.jl")
include("test_fluids.jl")
include("test_channel.jl")
include("test_pump.jl")
include("test_resistors.jl")
include("test_misc.jl")
include("test_heat_diffusion.jl")
include("test_correlations.jl")
include("test_composition.jl")
include("test_solvers.jl")
include("test_validation.jl")
include("test_examples.jl")
```

The include order matters for test output readability and matches the logical dependency order (geometry/connectors/fluids before components, components before systems, systems before validation).

### Each test_*.jl File Header Pattern

```julia
using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using DifferentialEquations
using STREAM
import STREAM: Channel, Pump, ...  # only where Base.Channel ambiguity is a concern
```

The `import STREAM: Channel, ...` line in the current monolith (line 6) exists specifically to avoid the `Base.Channel` ambiguity. Only test files that explicitly use `Channel(...)` need this import. Others can rely purely on `using STREAM`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Test runner | Custom test orchestrator | `include()` in runtests.jl | Julia's Pkg.test() already discovers via runtests.jl |
| Keyword enforcement | Runtime argument validation | Julia `function f(; kw...)` syntax | Language-level enforcement, no boilerplate needed |

## Common Pitfalls

### Pitfall 1: Missing `using` Statements in Split Files

**What goes wrong:** A test in the monolith relies on a `using` at the top of runtests.jl (line 1-7). After split, the test file has no `using` block and the test errors on undefined names.

**Why it happens:** The monolith has one global `using` block shared by all 1805 lines. Each split file must be self-sufficient.

**How to avoid:** Every `test_*.jl` must begin with its own `using Test`, `using STREAM`, and any other packages it needs. Check each file for every symbol used: `ReturnCode`, `Symbolics`, `ModelingToolkitBase`, `Rodas5P`, `SciMLBase.NoInit()`, etc.

**Warning signs:** `UndefVarError` when running `julia test/test_X.jl` standalone.

### Pitfall 2: Shared Constants Defined Outside Testsets

**What goes wrong:** `T_outlet_ref`, `mdot_ref` (lines 326-327) and `geom_comp`, `ps_comp` (lines 1503-1505) are defined outside any `@testset`. After split, these must be defined in the destination file before the testsets that use them.

**How to avoid:** When extracting a section, scan above each `@testset` for bare constant definitions that feed into it.

### Pitfall 3: The `const SciMLBase` Binding

**What goes wrong:** `const SciMLBase = DifferentialEquations.SciMLBase` (line 7) is needed for `SciMLBase.NoInit()` in `test_misc.jl` (RL-decay test, line 518). If it doesn't move into `test_misc.jl`, the test fails.

**How to avoid:** Move it to `test_misc.jl` as a file-level constant.

### Pitfall 4: solve_transient Call Sites Not Updated

**What goes wrong:** After changing `solve_transient` to keyword-only, the 2 call sites in runtests.jl (lines 312 and 356) will fail with a positional-argument error if not updated.

**Where they are:**
- Line 312: `solve_transient(ssys, T_wall_sym, op_ic, (0.0, 30.0); T_wall_final=393.15, t_step=10.0)` → goes to `test_solvers.jl`
- Line 356: `solve_transient(ssys, T_wall_sym, op_ic, (0.0, 60.0); T_wall_final=393.15, t_step=10.0)` → goes to `test_validation.jl`

**Updated form:**
```julia
solve_transient(ssys=ssys, T_wall_sym=T_wall_sym, op=op_ic, tspan=(0.0, 30.0),
                T_wall_final=393.15, t_step=10.0)
```

**How to avoid:** Update both call sites in the destination files when split. Also verify no call sites exist in `src/examples.jl` (the comment at line 147 references `solve_transient` in a docstring but does NOT call it — confirmed safe).

### Pitfall 5: The COMPAT Test Placement Decision

**What goes wrong:** COMPAT is currently in Phase 3 tests (which maps to `test_solvers.jl`), but CLAUDE.md names `test_examples.jl` for "build_loop / build_cube smoke tests (COMPAT)".

**Resolution:** Move COMPAT to `test_examples.jl`. This is both cleaner and matches CLAUDE.md intent. The test is `@test true` — trivial to move.

### Pitfall 6: Duplicate Test ID Names Across Files

**What goes wrong:** Multiple `@testset "VAL-01: ..."` blocks exist — one for Phase 3 steady-state, one for Phase 12 symmetric MTR, one for Phase 16 Fourier. All go to `test_validation.jl`. Julia allows duplicate testset names (they don't conflict), but the output may be confusing.

**How to avoid:** These are pre-existing names; do NOT rename them. The CONTEXT.md decision is that `@testset` block names and content do not change during the split — only file location changes.

## Code Examples

### solve_transient Before and After

```julia
# BEFORE (src/solvers.jl)
function solve_transient(ssys, T_wall_sym, op, tspan;
                         T_wall_final,
                         t_step = 10.0)

# AFTER (src/solvers.jl)
function solve_transient(; ssys, T_wall_sym, op, tspan,
                           T_wall_final,
                           t_step = 10.0)
```

```julia
# BEFORE (call site in test_solvers.jl)
sol = solve_transient(ssys, T_wall_sym, op_ic, (0.0, 30.0);
                      T_wall_final=393.15, t_step=10.0)

# AFTER (call site in test_solvers.jl)
sol = solve_transient(ssys=ssys, T_wall_sym=T_wall_sym, op=op_ic, tspan=(0.0, 30.0),
                      T_wall_final=393.15, t_step=10.0)
```

### Self-Contained test_*.jl Header

```julia
# test_fluids.jl
using Test
using ModelingToolkit
using ModelingToolkit: t_nounits as t
using STREAM

@testset "FOUND-02: rho_water" begin
    ...
end
```

### Thin runtests.jl

```julia
# test/runtests.jl
include("test_geometry.jl")
include("test_connectors.jl")
include("test_fluids.jl")
# ... 10 more includes
```

No `using` statements, no `@testset` wrappers, no logic.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Test stdlib (built-in Julia) |
| Config file | none — driven by `test/runtests.jl` |
| Quick run command | `julia --project test/runtests.jl` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TEST-01 | runtests.jl is thin orchestrator; 13 test_*.jl files exist | structural | `julia --project test/runtests.jl` | ❌ Wave 0 (split creates them) |
| QOL-01 | solve_transient accepts keyword-only args | smoke | `julia --project test/runtests.jl` | ❌ Wave 0 (signature change) |
| QOL-02 | No orphaned VAL-03 placeholder | structural | `julia --project test/runtests.jl` | satisfied by split |

### Sampling Rate

- **Per task commit:** `julia --project test/runtests.jl`
- **Per wave merge:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

- [ ] `test/test_geometry.jl` — covers PHY-01
- [ ] `test/test_connectors.jl` — covers FOUND-01, CONN-01/02
- [ ] `test/test_fluids.jl` — covers FOUND-02
- [ ] `test/test_channel.jl` — covers COMP-01 (channel), GRAV-*, CHAN-*, THERM-*
- [ ] `test/test_pump.jl` — covers COMP-02, PHY-05
- [ ] `test/test_resistors.jl` — covers COMP-03/04, NET-*
- [ ] `test/test_misc.jl` — covers COMP-01/02 (Inertia/HeatExchanger)
- [ ] `test/test_heat_diffusion.jl` — covers HDIFF-01..05
- [ ] `test/test_correlations.jl` — covers PHY-02/03/04
- [ ] `test/test_composition.jl` — covers COMP-01..04, QOL-01..03
- [ ] `test/test_solvers.jl` — covers SYS-*, SOLV-*
- [ ] `test/test_validation.jl` — covers VAL-*
- [ ] `test/test_examples.jl` — covers COMPAT
- [ ] `test/runtests.jl` rewritten to thin orchestrator
- [ ] `src/solvers.jl` solve_transient signature changed to keyword-only

All Wave 0 gaps are the deliverables of this phase, not prerequisite infrastructure.

## Sources

### Primary (HIGH confidence)

- `test/runtests.jl` — read directly; complete line-by-line mapping performed
- `src/solvers.jl` — read directly; current signature confirmed at line 68
- `.planning/phases/18-test-split-and-api-cleanup/18-CONTEXT.md` — locked decisions
- `CLAUDE.md` — canonical 13-file test layout

### Secondary (MEDIUM confidence)

- Julia Test stdlib documentation — standard `include()` pattern for test orchestrators is idiomatic Julia (confirmed by Julia official testing documentation convention)

## Metadata

**Confidence breakdown:**
- Test-to-file mapping: HIGH — derived from direct read of all 1805 lines of runtests.jl
- solve_transient call sites: HIGH — grep confirmed exactly 2 call sites in test files, 0 in src (comments only)
- Architecture patterns: HIGH — standard Julia test suite conventions, no new libraries
- Pitfalls: HIGH — identified from direct code inspection, not inferred

**Research date:** 2026-03-16
**Valid until:** This is a code refactoring — research reflects exact current state; valid as long as runtests.jl is not modified before Phase 18 executes.

# Project Research Summary

**Project:** Julia-STREAM v0.3 — HeatDiffusion + Two-Sided ChannelAndContacts
**Domain:** MTK-based 2D finite-difference fuel plate with acausal thermal-hydraulic coupling (MTR reactor geometry)
**Researched:** 2026-03-13
**Confidence:** HIGH

## Executive Summary

Julia-STREAM v0.3 is a symbolic simulation library milestone whose sole deliverable is a working, validated 2D fuel plate (HeatDiffusion) coupled to two coolant channels via an upgraded ChannelAndContacts component. The project is implemented using ModelingToolkit.jl v11 (acausal, equation-based modeling) on top of Sundials IDA (DAE solver). No new packages are required — the existing stack fully supports 2D indexed MTK variables via `(T(t))[1:nz, 1:nx]`, the same Symbolics.jl symbolic array infrastructure already proven in v0.2's Channel/ChannelAndContacts 1D patterns. The approach is to extend existing patterns incrementally: 2D array variables extend 1D, two-sided ThermalPort arrays extend the single-sided design, and the FD stencil follows the same push!-loop equation generation used throughout the codebase.

The recommended build order is: (1) clean up v0.2 tech debt and upgrade ChannelAndContacts to two-sided ports first — this stabilizes the interface contract before HeatDiffusion is written against it; (2) implement HeatDiffusion with x-direction diffusion only (matching Python STREAM's `x_diffusion` default), validate the component in isolation, then (3) couple the full MTR geometry (cladding+meat+cladding plate sandwiched between two water channels) and validate against Python STREAM reference outputs within 1%. Z-direction diffusion is a differentiator but not required for the reference case validation and should be deferred to after Phase 12 validation passes.

The primary risks are not algorithmic but convention-based: Python STREAM's Fuel class stores T with axes `(nz, nx)` (row=axial, col=lateral), opposite to the intuitive Julia `[nx, nz]` naming in the original PROJECT.md. Additionally, Python's `Fuel.indices()` has an intentional left/right swap that will produce mirrored but otherwise-valid-looking results if not caught by an asymmetric test. A third risk is MTK's handling of unconnected ThermalPort Q_flow variables in partially-connected systems, which must be tested explicitly rather than assumed. All three risks are well-defined and preventable with targeted tests.

---

## Key Findings

### Recommended Stack

No Project.toml changes are needed. ModelingToolkit v11 + Symbolics v7 + Sundials v5 + DifferentialEquations v7 already cover all v0.3 requirements. The 2D array variable pattern `(T(t))[1:nz, 1:nx]` is native to Symbolics.jl and follows the same mechanics as the 1D `(T(t))[1:n]` already in production use. The critical implementation note is that `vec(collect(T))` (not just `collect(T)`) is required to flatten a 2D symbolic array into the 1D `Vector{Num}` that `System()` expects for `all_vars`. Initial conditions must use Dict syntax (`Dict(hd.T => fill(700.0, nz, nx))`) — never manually constructed vectors — because MTK state ordering is not stable across patch releases.

**Core technologies:**
- ModelingToolkit.jl v11: symbolic equation system, mtkcompile, compose(), connect() — already validated for acausal thermal-hydraulic modeling
- Symbolics.jl v7: 2D indexed variable declaration `(T(t))[1:nz, 1:nx]` — same infrastructure as existing 1D arrays
- Sundials.jl v5 (IDA backend): DAE solver — HeatDiffusion adds ODE states but does not change DAE structure
- LinearAlgebra (stdlib): `vec(collect(T))` to flatten 2D symbolic arrays for System() state var list

See `.planning/research/STACK.md` for complete integration patterns and alternatives considered.

### Expected Features

The v0.3 feature set is precisely scoped: HeatDiffusion (2D FD fuel plate with two-sided ThermalPort arrays) + ChannelAndContacts upgrade (single-sided to two-sided thermal ports) + MTR reference case validation. Everything else is explicitly deferred.

**Must have (table stakes):**
- `HeatDiffusion` component with `T(t)[1:nz, 1:nx]` 2D MTK state — core of v0.3, without this there is no fuel plate
- x-direction diffusion (across plate thickness) — dominant heat path; without it plate is isothermal
- `thermal_left[1:nz]` + `thermal_right[1:nz]` ThermalPort arrays on HeatDiffusion — interface contract to coolant channels
- ChannelAndContacts upgraded from `thermal_ports[1:n]` to `thermal_left[1:n]` + `thermal_right[1:n]` — MTR requires two-sided coupling
- Adiabatic default for unconnected ThermalPort (Q_flow=0 from MTK acausal semantics) — one-sided test cases must work
- MTR reference case validation: HeatDiffusion + two ChannelAndContacts matches Python STREAM within 1%

**Should have (differentiators):**
- MTK symbolic Jacobian for 2D PDE (automatic via mtkcompile; no extra user effort; dramatically improves IDA convergence)
- Asymmetric left/right heating support (emerges automatically from two-port design; no extra equations)
- Multi-layer material (cladding+meat) via per-cell `k[i,j]` and harmonic mean conductivity at cell faces

**Defer (v0.4+):**
- z-direction diffusion (xz_diffusion): differentiator but not required for the MTR reference case validation; add after Phase 12 passes
- Point kinetics coupling — out of scope through v0.3
- Additional HTC correlations (laminar, Marco-Han) — Dittus-Boelter is sufficient for MTR turbulent regime
- Power shape profiling (cosine, non-uniform) — uniform q_gen is sufficient for reference case
- Cylindrical/polar geometry, subcooled boiling, natural convection — no validation target

See `.planning/research/FEATURES.md` for full boundary condition details, discretization scheme, and validation patterns.

### Architecture Approach

The architecture extends the existing acausal component pattern. HeatDiffusion is implemented as a new file (`src/heat_diffusion.jl`) following the same `compose(System(...), ports...)` structure as ChannelAndContacts. ChannelAndContacts is modified in-place (breaking change) to replace `thermal_ports[1:n]` with `thermal_left[1:n]` + `thermal_right[1:n]`. MTK's `connect()` handles the plate-channel coupling; no new connector types are needed. The file inclusion order in STREAM.jl must be: `fluids.jl → connectors.jl → components.jl → heat_diffusion.jl → solvers.jl`.

**Major components:**
1. `HeatDiffusion` (new, `src/heat_diffusion.jl`) — 2D FD fuel plate; nx×nz state variables `T[i,j]`; exposes `thermal_left[1:nz]` and `thermal_right[1:nz]` ThermalPort arrays; no FlowPorts (solid component)
2. `ChannelAndContacts` (modified, `src/components.jl`) — n-cell heated channel upgraded from single-sided to `thermal_left[1:n]` + `thermal_right[1:n]`; breaking change, clean rename with no backward compatibility
3. `ThermalPort` / `FlowPort` (unchanged, `src/connectors.jl`) — acausal connectors; ThermalPort Q_flow sign: positive = into component
4. Solver helpers (new `build_mtr_loop` in `src/solvers.jl`) — wires the MTR topology for the reference case validation

**Key patterns:**
- FD stencil: nested `for i in 1:nz, j in 1:nx` loop with explicit boundary handling (left/right/top/bottom as separate code blocks, not symbolic `ifelse`)
- Material properties (`rho_s`, `cp_s`, `k_s`): plain Julia Float64 constructor arguments, not MTK parameters — no symbolic overhead for time-invariant solids
- Two-sided energy balance in ChannelAndContacts: `Q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow`

See `.planning/research/ARCHITECTURE.md` for data flow diagrams, interface contracts, and build order details.

### Critical Pitfalls

1. **T array axis convention mismatch (T[z,x] vs T[x,z])** — Python STREAM's `Fuel` stores T with shape `(nz, nx)` (row=axial z, col=lateral x). The original Julia PROJECT.md wrote `T[1:nx, 1:nz]` which is transposed. Use `T[1:nz, 1:nx]` to match Python, and document the axis convention as the first line in `heat_diffusion.jl`. Validate by extracting T at a known asymmetric condition and comparing element-by-element.

2. **Python `Fuel.indices()` intentional left/right swap** — `indices()` routes `"T_left"` to `T_wall_right` internals and vice versa. This is intentional (it returns what the fuel *provides* to neighbors, not what it *receives*). Test with an asymmetric channel configuration (left channel 50 K hotter than right) before trusting any coupling direction. The symmetric MTR case will pass even if the swap is wrong.

3. **ThermalPort Q_flow sign convention** — positive Q_flow = into component. HeatDiffusion is a heat source; at steady state, `sum(thermal_left[i].Q_flow)` on the fuel's ports must be negative (heat leaving the plate). Write a unit test for isolated HeatDiffusion before coupling: pinned boundary conditions with T_boundary < T_interior must yield `sum(Q_flow) < 0` on fuel ports.

4. **Unconnected ThermalPort adiabatic assumption** — MTK's `Q_flow = 0` for unconnected Flow variables is version-dependent and must be tested explicitly, not assumed. Build a one-sided test (only `thermal_left` connected, `thermal_right` unconnected) and verify the solver compiles and `thermal_right[i].Q_flow ~ 0` holds at steady state.

5. **ChannelAndContacts port rename breaks existing tests** — The rename from `thermal1..thermalN` to `thermal_left[i]` must be done atomically: modify the component and update all test call sites in the same commit. Audit all occurrences of `thermal_ports`, `thermal1`, `thermal2` in the test suite before making the change.

See `.planning/research/PITFALLS.md` for full pitfall descriptions, warning signs, recovery strategies, and the "Looks Done But Isn't" checklist.

---

## Implications for Roadmap

Based on combined research, the natural phase structure is a 4-phase sequence matching the dependency graph from ARCHITECTURE.md.

### Phase 10: v0.2 Tech Debt + ChannelAndContacts Two-Sided Upgrade

**Rationale:** The ChannelAndContacts interface is the foundation everything else connects to. Getting the two-sided port contract right before HeatDiffusion is written means HeatDiffusion can be implemented against a stable API. Reversing this order means HeatDiffusion must be revised if the channel port design changes. The v0.2 tech debt items (dead `t_inlet` parameter, THERM-03 direct assertion, cosmetic doc fix) are independent and bundle cleanly into this phase.

**Delivers:** Upgraded ChannelAndContacts with `thermal_left[1:n]` + `thermal_right[1:n]`; cleared v0.2 debt; updated THERM tests; verified adiabatic default for unconnected ports.

**Features addressed:** ChannelAndContacts two-sided upgrade (table stakes); adiabatic default for unconnected ThermalPort (table stakes).

**Pitfalls to avoid:** Port rename breaking tests silently (Pitfall 5) — atomic commit; adiabatic unconnected port assumption (Pitfall 6) — explicit one-sided test.

### Phase 11: HeatDiffusion Component (x-diffusion, uniform plate)

**Rationale:** Implement HeatDiffusion with x-direction diffusion only, matching Python STREAM's `x_diffusion` default. This tests the 2D MTK array variable pattern, the FD stencil generation, and the ThermalPort array coupling in isolation before the complexity of z-diffusion and system coupling is added. The axis convention (Pitfall 1) and Q_flow sign convention (Pitfall 3) must be locked down here, not discovered during coupled validation.

**Delivers:** `src/heat_diffusion.jl` with `T[1:nz, 1:nx]`, x-diffusion stencil, uniform power, `thermal_left/right` port arrays; HDIFF-01..04 tests; documented axis convention; benchmarked mtkcompile time on 3x3 and representative MTR grids.

**Features addressed:** HeatDiffusion 2D MTK state (table stakes); x-direction diffusion (table stakes); ThermalPort arrays on HeatDiffusion (table stakes); MTK symbolic Jacobian (differentiator, free from mtkcompile).

**Pitfalls to avoid:** Axis convention mismatch (Pitfall 1) — document before writing stencil; Q_flow sign error (Pitfall 3) — unit test with pinned BC; FD top/bottom Neumann BC conflict (Pitfall 7) — ghost-cell approach; mtkcompile performance (Pitfall 4) — benchmark early with small grid.

### Phase 12: Coupled System + MTR Reference Case Validation

**Rationale:** Wire HeatDiffusion between two ChannelAndContacts instances in the MTR geometry (cladding+meat+cladding, two water channels) and validate against Python STREAM reference outputs. This is the milestone exit criterion. The asymmetric coupling test (Pitfall 2, Python left/right swap) must be explicitly included — the symmetric case alone will not catch the swap.

**Delivers:** `build_mtr_loop` helper in `solvers.jl`; VAL-03 validation test comparing T_outlet, T_wall_left, T_wall_right, T_center vs Python STREAM within 1%; asymmetric heating test.

**Features addressed:** MTR reference case validation (table stakes); asymmetric left/right heating (differentiator); multi-layer material support (differentiator, needed for cladding+meat geometry).

**Pitfalls to avoid:** Python left/right swap in indices() (Pitfall 2) — asymmetric test mandatory; inconsistent IC for coupled system (Pitfall 8) — decoupled warm-start strategy.

### Phase 13: z-Direction Diffusion (Conditional)

**Rationale:** Add axial (z-direction) diffusion to HeatDiffusion only if Phase 12 validation reveals a discrepancy attributable to axial conduction. Python STREAM uses `x_diffusion` as the default for flat MTR plates where axial conduction is negligible. This phase is conditional on Phase 12 results.

**Delivers:** `xz_diffusion` mode in HeatDiffusion; re-validation showing axial contribution is within expected range.

**Features addressed:** z-direction diffusion (differentiator; deferred from Phase 11).

**Pitfalls to avoid:** Neumann BC stencil consistency (Pitfall 7) — same ghost-cell approach; mtkcompile performance at larger equation count (Pitfall 4).

### Phase Ordering Rationale

- **Interface before implementation:** ChannelAndContacts (Phase 10) before HeatDiffusion (Phase 11) because HeatDiffusion is written against ChannelAndContacts's port contract. Writing HeatDiffusion first requires revisiting it when the channel interface changes.
- **Isolation before coupling:** HeatDiffusion unit tests (Phase 11) before MTR coupling (Phase 12) because convention errors (axis order, Q_flow sign) discovered during isolated testing cost one equation change; discovered during coupled validation cost a full debug session on a coupled nonlinear system.
- **x-only before xz:** Python STREAM's default is x-only; the MTR validation case does not require axial conduction; adding z-diffusion before validation passes adds risk to an unproven coupled system.
- **Tech debt first:** Clearing dead parameters and cosmetic issues at the start prevents them from accumulating through v0.3 phases and cluttering validation diffs.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 12 (MTR Validation):** The Python STREAM reference outputs need to be generated via `generate_reference.py` (flagged in memory: `todo_comprehensive_review.md`). Confirm the reference generation script is working and produces the exact geometry + boundary conditions used in Julia-STREAM's test before this phase begins. Also requires confirming the exact Python `Fuel.indices()` left/right swap behavior with a concrete numerical test.
- **Phase 13 (z-diffusion):** Conditional on Phase 12 results. If needed, requires reviewing Python STREAM's `xz_diffusion` stencil coefficients before implementation.

Phases with standard patterns (skip deeper research):
- **Phase 10 (ChannelAndContacts upgrade):** Well-understood rename + energy balance extension of proven v0.2 pattern. Pitfalls are documented; no research needed.
- **Phase 11 (HeatDiffusion skeleton):** MTK 2D array variable pattern is documented in STACK.md and ARCHITECTURE.md with concrete code. No research needed beyond the FD stencil details already captured in FEATURES.md.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Verified via installed manifest + direct codebase inspection + official MTK/Symbolics docs. No new packages; 2D array variable syntax confirmed from multiple sources including community discourse. |
| Features | HIGH | Sourced directly from Python STREAM source code (`heat_diffusion.py`, `channel.py`, `mtr_geometry.py`) and existing Julia-STREAM `components.jl`. Boundary condition details match Python implementation. |
| Architecture | HIGH | Based on direct code inspection of existing codebase and Python STREAM. FD stencil patterns, port contracts, and component structure are all confirmed. Perimeter split in two-sided energy balance is MEDIUM (needs confirmation against Python STREAM MTR geometry during implementation). |
| Pitfalls | HIGH | Axis convention mismatch and left/right swap confirmed from direct Python source read. Q_flow sign confirmed from connectors.jl. MTK unconnected port behavior confirmed from v0.1/v0.2 experience. |

**Overall confidence:** HIGH

### Gaps to Address

- **Exact perimeter geometry constants in two-sided ChannelAndContacts energy balance:** The hydraulic perimeter split (wall area per side for flat MTR channels) needs to be confirmed against Python STREAM's MTR geometry constants (`W * dz` per side). Address during Phase 10 implementation by cross-checking against `channel.py`'s `ChannelAndContacts` heat transfer area calculation.

- **`generate_reference.py` validation status:** Memory notes an outstanding task to validate this script against Python STREAM outputs. This script provides the reference values for VAL-03. Confirm it is working before Phase 12 begins.

- **MTK array port access syntax for `thermal_left[i]`:** The syntax for accessing array-indexed subsystem ports in MTK v11 (`sys.thermal_left[1].T` vs some other form) should be confirmed with a small smoke test early in Phase 10 before writing all tests against it.

- **`mtkcompile` performance at MTR grid scale (nz=10, nx=3..5):** Research documents expected behavior but actual compile time for the coupled system (plate + two channels) should be benchmarked explicitly in Phase 11. Document in VALIDATION.md.

---

## Sources

### Primary (HIGH confidence)

- `/home/itay/projects/Julia-STREAM/src/components.jl` — existing ChannelAndContacts 1D symbolic array pattern; ThermalPort splat into compose
- `/home/itay/projects/Julia-STREAM/src/connectors.jl` — ThermalPort Q_flow sign declaration
- `/home/itay/projects/STREAM/stream/calculations/heat_diffusion.py` — Python Fuel class; axis order `(nz, nx)`; `indices()` left/right swap; `x_diffusion` / `xz_diffusion`
- `/home/itay/projects/STREAM/stream/calculations/channel.py` — Python ChannelAndContacts two-sided design
- [Symbolics.jl Arrays Documentation](https://symbolics.juliasymbolics.org/dev/manual/arrays/) — `@variables A[1:5, 1:3]` 2D array syntax
- [MTK Language Documentation](https://docs.sciml.ai/ModelingToolkit/stable/basics/MTKLanguage/) — `(v_array(t))[1:N, 1:M]` syntax
- Julia-STREAM `.planning/PROJECT.md` — v0.3 scope and requirements

### Secondary (MEDIUM confidence)

- [Julia Discourse: 2D Arrays with ModelingToolkit](https://discourse.julialang.org/t/2d-arrays-with-modelingtoolkit/107448) — community confirmation of 2D indexed variable syntax; Dict u0 requirement
- [SciML Discourse: MTK performance for large models](https://discourse.julialang.org/t/modelingtoolkit-jl-performance-for-large-models-with-similar-components/82442) — practical guidance on system size limits
- Python STREAM `tribal_knowledge.md` — T_left / T_right x-direction convention

### Tertiary (LOW confidence)

- MTK behavior for unconnected connector Q_flow = 0 across versions — inferred from Modelica semantics and v0.1/v0.2 experience; must be tested explicitly in Phase 10/11

---

*Research completed: 2026-03-13*
*Ready for roadmap: yes*

# Pitfalls Research

**Domain:** 2D MTK finite-difference components + two-sided ThermalPort coupling in Julia-STREAM v0.3
**Researched:** 2026-03-13
**Confidence:** HIGH (based on direct reading of Python STREAM source, existing Julia MTK codebase, and MTK/Symbolics documentation patterns)

---

## Critical Pitfalls

### Pitfall 1: Python Fuel T array is T[z, x] — Julia PROJECT.md says T[nx, nz]

**What goes wrong:**
The Python `Fuel` class stores temperatures as `T.reshape(self.shape)` where `self.shape = (m, n)`, `m = len(dz)` (axial cells), `n = len(dx)` (lateral/x cells). This means the Python array is indexed `T[z_index, x_index]` — row is axial, column is lateral.

The current Julia PROJECT.md requirement says `T(t)[1:nx, 1:nz]` which is `T[x_index, z_index]` — the transpose. When comparing against Python STREAM, the axes must match exactly or a factor-of-`nz` vs `nx` indexing error will corrupt the validation comparison silently (temperatures extracted will be from wrong cells, but the solver will still converge).

**Why it happens:**
The Julia convention was written without cross-checking the Python source. The naming `[1:nx, 1:nz]` is intuitive from a "plate cross-section" mental model but transposes the Python convention.

**How to avoid:**
Decide on one canonical axis order before writing a single equation and document it explicitly. The safest choice is to match Python: `T[1:nz, 1:nx]` (row=axial z, col=lateral x) — this makes direct numerical comparison trivial. Whatever is chosen, add a comment at the top of the HeatDiffusion component stating the axis convention.

When extracting `thermal_left[i]` and `thermal_right[i]` for axial cell `i`, the correct slice is `T[i, 1]` (leftmost x column of row i) and `T[i, end]` (rightmost x column of row i) under Python convention, or `T[1, i]` and `T[end, i]` under transposed convention.

**Warning signs:**
- Validation comparison shows temperature profiles that are rotated/transposed relative to Python STREAM output
- `T_wall_left` matches Python's `T_wall_right` and vice versa
- Center temperature is correct but axial profile is wrong (nx cells along what should be nz)

**Phase to address:**
HeatDiffusion implementation phase (first phase of v0.3). Document the axis convention in the component header before writing the FD stencil loop.

---

### Pitfall 2: Python Fuel indices() has an intentional left/right swap

**What goes wrong:**
In `heat_diffusion.py`, the `indices()` method maps `"T_left"` to `self._vars["T_wall_right"]` and `"T_right"` to `self._vars["T_wall_left"]`. This is not a bug in Python STREAM — it is an intentional convention where the fuel's "left wall temperature" (what it exposes to the channel on its left) is computed from the fuel's right-side cladding variables. The swap exists because `indices()` returns what the fuel *provides* to its neighbors, not what it *receives*.

If Julia's HeatDiffusion exposes `thermal_left[i].T` as the temperature on the left face of the plate, but Python STREAM's `T_wall_left` is the wall temperature sent to the right channel (due to the swap), the coupled validation will produce symmetric but physically mirrored results.

**Why it happens:**
The Python coupling convention is subtle: in a `plate(ch_l, ch_r, fuel)` topology, the fuel receives `T_left` (coolant temp from left channel) and provides `T_wall_left` (plate surface temp back to left channel). But `Fuel.indices()` routes `T_left` → `T_wall_right` slice — meaning when the graph says "give channel_left the fuel's T_left variable," it actually pulls the right-side wall data. This convention is embedded in the composition helpers and may be reversed versus naive expectation.

**How to avoid:**
Before writing the Julia coupling equations, generate a small Python STREAM MTR reference case (fuel sandwiched between two asymmetric channels) and print both `T_wall_left` and `T_wall_right`. Confirm which corresponds to which channel by setting only one channel to a high temperature. Use this as the ground truth for the Julia port convention.

**Warning signs:**
- Asymmetric heating test (left channel hotter than right) produces the correct magnitude but mirrored side (right channel shows the higher wall temperature)
- Symmetric case validates correctly but asymmetric case does not

**Phase to address:**
HeatDiffusion + ChannelAndContacts coupling validation phase (the MTR reference case phase). Test asymmetric configuration explicitly, not just the symmetric case.

---

### Pitfall 3: ThermalPort Q_flow sign convention silently reverses heat direction

**What goes wrong:**
`ThermalPort` in connectors.jl declares `Q_flow` as `[connect = Flow]` with the comment "positive = into component." In MTK acausal semantics, this means when two ThermalPorts are connected, MTK generates the Kirchhoff-like equation: `portA.Q_flow + portB.Q_flow ~ 0`. So the component that receives heat has positive Q_flow, and the one that sends heat has negative Q_flow.

HeatDiffusion generates heat (fuel plate is a source). When writing the energy balance equation for the left boundary cell, the heat leaving the plate into the channel must appear as negative Q_flow on the fuel's port and positive Q_flow on the channel's port. If both sides write `Q_flow ~ h * A * (T_wall - T_cool)` with the same sign, the heat will be double-counted or the direction will be wrong.

The current ChannelAndContacts energy balance `h_tc[i] * (π * Dh) * dz * (thermal_ports[i].T - T[i])` is written from the channel's perspective: positive when wall is hotter than coolant. This already implies the channel receives heat (positive Q_flow into channel). HeatDiffusion must be consistent: the fuel's port Q_flow equation must be the negative of the channel's perspective, or left as an algebraic observable only (the MTK `connect()` equation already handles the balance).

**Why it happens:**
The channel energy balance uses `thermal_ports[i].T` as a temperature boundary — it reads the temperature from the port, not the heat flow. The Q_flow on the channel's port is an observable (`q_wall[i] ~ thermal_ports[i].Q_flow`) not a driver. HeatDiffusion will be the first component that actually drives Q_flow from the fuel side. Getting the driving direction wrong silently produces cooling where there should be heating.

**How to avoid:**
Follow the pattern already established: write the FD boundary equation as `Q_flow ~ -k_eff * A * (T_boundary - T_interior) / (dx/2)` from the fuel's perspective. The negative sign ensures that when the interior is cooler than the boundary (heat flowing out of the fuel), Q_flow on the fuel's port is negative (consistent with "positive = into fuel"). The channel's port then sees positive Q_flow from the `connect()` equation.

As a sanity check: at steady state, `sum(thermal_left[i].Q_flow for i in 1:nz)` should be negative on the fuel side and the corresponding channel's `Q_wall_total` should be positive and equal in magnitude.

**Warning signs:**
- Coupled system converges but the channel temperature decreases along the flow direction despite a hot fuel plate
- `Q_wall_total` on the channel is negative (heat flowing from coolant to plate)
- `abs(Q_flow)` is correct but sign is wrong

**Phase to address:**
HeatDiffusion component implementation phase. Write a unit test before coupling: isolated HeatDiffusion with pinned boundary temperatures should have `sum(Q_flow)` negative at left and right thermal ports when the fuel interior is hotter than the boundary conditions.

---

### Pitfall 4: MTK 2D array variable `(T(t))[1:nz, 1:nx]` — mtkcompile performance and Jacobian density

**What goes wrong:**
MTK/Symbolics.jl supports array-valued time-dependent variables, and `(T(t))[1:nz, 1:nx]` is valid syntax. However, `mtkcompile` with a large 2D FD grid (e.g., 10x10 = 100 cells, each with a 5-point stencil) creates a symbolic system with O(nx*nz) ODE equations where each equation references at most 5 neighboring symbolic variables. The total system equation count becomes O(nx*nz + n_channel_cells), which can be hundreds of equations for a realistic MTR plate.

Known Symbolics.jl behavior: structural_simplify (called by mtkcompile) performs tearing on all algebraic equations. With 100 differential temperature states and ~200 algebraic equations (HTC, Re, Nu, q_wall per cell), compile time can spike dramatically — potentially minutes instead of seconds.

**Why it happens:**
The v0.1/v0.2 systems had at most 10 cells per channel. A 10-axial x 5-lateral plate adds 50 FD nodes, each coupling to its neighbors symbolically. Symbolics.jl's tearing algorithm is O(n²) or worse on dense equation graphs. The FD stencil is sparse numerically but Symbolics.jl may not exploit that sparsity during compilation.

**How to avoid:**
Start development with the smallest possible grid (3x3 or 5x3) and measure `mtkcompile` time before scaling. If compile time exceeds 60 seconds for a 10x10 grid, switch to the `sparse=true` option in `mtkcompile` (available in MTK ≥ v9) or use `structural_simplify(sys; fully_determined=false)` to skip tearing for diagnostic purposes.

Keep the channel-side algebraic variables (Re, Nu, h_tc per cell) inside `ChannelAndContacts` and do not expose them through ThermalPorts — this avoids expanding the coupled symbolic system with channel algebraics when compiling HeatDiffusion.

For the MTR reference case validation, a 10z x 5x grid (50 FD nodes) is realistic. Profile `@time mtkcompile(...)` explicitly and document the result.

**Warning signs:**
- `mtkcompile` takes more than 30 seconds for a small test system
- `OutOfMemoryError` or LLVM crashes during `mtkcompile` on grid > 20x20
- Julia process hangs with high CPU (Symbolics symbolic manipulation loop)

**Phase to address:**
HeatDiffusion implementation phase. Benchmark with 3x3 grid first, then scale. Document the compile time in the phase VALIDATION.md.

---

### Pitfall 5: ChannelAndContacts thermal_ports renaming breaks existing tests silently

**What goes wrong:**
The existing ChannelAndContacts creates per-cell ThermalPorts named `thermal1`, `thermal2`, ..., `thermalN` via `Symbol(:thermal, i)`. When the component is upgraded to `thermal_left` and `thermal_right` arrays, every existing test that accesses `cac.thermal1` or `cac.thermal2` will fail with a "field not found" or "subsystem not found" error. More dangerously, tests that call `mtkcompile` and access port equations by string name (via `sys.thermal1.T`) will silently use a stale MTK system object if the test file caches the old compiled system.

**Why it happens:**
MTK subsystems are accessed by name. Renaming `thermalN` to `thermal_left[i]` changes the internal name from `thermal1` to the array indexing syntax. Any test setup that pins wall temperature via `[cac.thermal1.T ~ 600.0]` must be rewritten to use the new array port name syntax.

**How to avoid:**
Before the breaking change, audit every occurrence of `thermal_ports`, `thermal1`, `thermal2` in the test suite. Treat this as a rename refactor: update all call sites atomically in the same commit as the component change. Do not attempt to maintain backward compatibility by keeping both naming schemes — it will create an inconsistent port structure that confuses MTK's compose().

Write a minimal smoke test for the new API before touching existing tests: `cac.thermal_left` and `cac.thermal_right` are accessible as named subsystem arrays.

**Warning signs:**
- Tests that previously passed now throw `KeyError` or `UndefVarError` on port access
- `mtkcompile` succeeds but `sol[cac.thermal1.T]` returns wrong values (using stale compiled system)
- Test count drops by exactly the number of `thermal_ports` references (deletions rather than updates)

**Phase to address:**
ChannelAndContacts upgrade phase. This should be done as an atomic change: modify the component and update all test call sites in one plan.

---

### Pitfall 6: Unconnected ThermalPort adiabatic assumption — Q_flow = 0 only if explicitly stated

**What goes wrong:**
The PROJECT.md requirement states "Unconnected ThermalPort sides default to adiabatic (Q_flow=0 from MTK acausal semantics — no explicit flag needed)." This is conditionally true: in MTK, an unconnected `[connect = Flow]` variable is treated as zero *if the system is closed* (i.e., the equation count matches the unknown count after mtkcompile). However, for a `thermal_left` or `thermal_right` array port that is declared but not connected in a `compose()` call, MTK may not automatically add Q_flow=0 — it depends on the MTK version and whether `structural_simplify` sees the port as a boundary or as an underdetermined equation.

In Modelica semantics, unconnected flow variables have zero by default. MTK follows this for `[connect = Flow]` variables in fully closed systems. But if a user builds a test with only the fuel plate (no channel connected), the left and right port equations are underdetermined unless MTK's structural analysis generates the zero equation. This behavior has changed between MTK versions.

**Why it happens:**
MTK's handling of unconnected connectors was improved across versions. In older MTK versions (< v9), unconnected Flow variables were sometimes left as free variables rather than zeroed, causing "system is underdetermined" errors. In current MTK v9+, the behavior is correct for well-formed systems, but only when the port is included in `compose()` even if unconnected at the outer level.

**How to avoid:**
Write an explicit test for adiabatic behavior: build a HeatDiffusion system with thermal_right connected to a channel and thermal_left left unconnected, then call `mtkcompile`. Verify that the solution sets `thermal_left[i].Q_flow ~ 0` for all i and that the temperature profile is one-sided. Do not assume this works without testing it.

As a fallback, add explicit `~ 0` equations for unconnected ports in the component definition itself — but only as a last resort, since it conflicts with MTK's connector pattern.

**Warning signs:**
- `mtkcompile` throws "system is singular" or "not fully determined" when only one side is connected
- One-sided heating test produces symmetrically heated plate (both sides see heat flow)
- MTK warning about unset or over-constrained equations when a single-sided connection is tested

**Phase to address:**
HeatDiffusion + ChannelAndContacts coupling phase. Test one-sided connection explicitly before testing symmetric coupling.

---

### Pitfall 7: FD stencil top/bottom boundary (adiabatic z-ends) creates an implicit Q=0 equation that must not conflict with the FD stencil

**What goes wrong:**
The HeatDiffusion plate has four boundaries: left/right (lateral x, connected to channels via ThermalPorts) and top/bottom (axial z-ends, adiabatic by default). The left/right boundaries are driven by ThermalPort connections. The top/bottom boundaries are purely adiabatic: no flux crosses the top or bottom of the plate.

In the FD stencil, the top boundary condition is typically implemented as a ghost-cell or zero-flux Neumann BC: the flux at the top face equals zero, meaning `T[1, :]` (top row) sees no axial diffusion from above. If this is implemented as a separate equation `Q_top[j] ~ 0 for j in 1:nx`, it adds `nx` equations that must not duplicate or conflict with the FD stencil's top-row treatment.

The risk: if the FD loop for the top row `i=1` already includes the axial flux term (which evaluates to zero only because `T_ghost = T[1, :]`), and an additional explicit `Q_top ~ 0` equation is added, the system is overconstrained.

**Why it happens:**
The Python `Fuel` handles this via the `T_walls.z = (top, bottom)` Walls dataclass where `top` and `bottom` are passed as optional external inputs. When not provided, `wall_or_default()` substitutes `T_last_cell.top = T[0, :]` (the actual cell temperature), which creates a Neumann BC by making the wall equal to the interior. This is elegant in Python but subtle to replicate in MTK.

**How to avoid:**
Implement the adiabatic top/bottom as a zero-flux Neumann BC by treating the ghost cell temperature as equal to the boundary cell: `T_ghost_top[j] = T[1, j]` for all j. This means the flux across the top face is `(T_ghost - T[1,j]) / dx_ghost = 0` — no additional equation needed, and the stencil is self-consistent. Do not create a separate `Q_top` port or equation.

**Warning signs:**
- `mtkcompile` reports overconstrained system when using a full 2D FD stencil
- Solver diverges at the plate edges (top/bottom rows show unphysical temperatures)
- Adding an explicit `Q_flow = 0` boundary term doubles the residual at top/bottom rows

**Phase to address:**
HeatDiffusion FD stencil implementation phase.

---

### Pitfall 8: Initial condition for 2D T array must be consistent with the coupled FD + channel system

**What goes wrong:**
The existing components (Channel, ChannelAndContacts) use `fill(600.0, n)` as the initial condition for cell temperatures. For HeatDiffusion, all `nx * nz` cells need initial conditions. If the initial guess is far from steady state (e.g., uniform 300 K for a plate that equilibrates to 700 K), Sundials IDA must integrate through a large transient before reaching steady state — or if used directly as a steady-state initial condition for an algebraic solve, it may fail to converge.

More critically: the coupled system (HeatDiffusion + two ChannelAndContacts) has a larger algebraic structure than anything tested so far. The initial condition for the coupled system must be consistent: all differential states (T in fuel, T in both channels) must satisfy the algebraic constraints (HTC, Re, Nu equations in both channels). An inconsistent IC causes IDA's consistent IC initialization to fail or take excessive iterations.

**Why it happens:**
In v0.1/v0.2, the initial conditions were simple enough that MTK's default IC computation (via IDA's `calc_ic`) handled inconsistencies. With O(100) new differential states and coupled nonlinear algebraics, the IC problem is harder. Python STREAM addresses this with `symmetric_plate_steady_state()` which runs decoupled iterations before the full coupled solve.

**How to avoid:**
Use a decoupled warm-start strategy: first solve the channel alone (with `T_wall` pinned as a parameter), then solve the fuel alone (with channel T and HTC as fixed boundary conditions), then couple and iterate. This mirrors Python STREAM's `symmetric_plate_steady_state` helper. Document this as the recommended IC construction pattern for the coupled system.

**Warning signs:**
- IDA's `calc_ic` fails with "consistent IC not found" or throws `DimensionMismatch`
- The steady-state solve converges to a physically wrong solution (uniform temperature, or very high temperatures)
- Transient simulation shows a huge spike in the first few time steps before settling

**Phase to address:**
MTR reference case validation phase (the final validation phase). Document the IC construction strategy explicitly in the phase plan.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode `T[1:nz, 1:nx]` axis order without comment | Saves one line of documentation | Anyone comparing to Python STREAM must re-derive the convention; breaks if the array is transposed during validation | Never — always document the axis convention explicitly |
| Skip asymmetric coupling test, only test symmetric case | Faster validation | Left/right swap bugs (Pitfall 2) are undetectable; the symmetric case hides sign convention errors | Never for validation milestone |
| Use `fully_determined=false` in mtkcompile to suppress errors during development | Faster iteration when system is structurally incomplete | Silently allows underdetermined systems to "compile"; solver will fail at runtime with cryptic errors | Acceptable during RED phase; remove before GREEN |
| Use `fill(700.0, nz, nx)` as IC without warm-start | Simple, fast to write | IDA consistent IC computation may fail on coupled system; decoupled warm-start needed | Acceptable for unit tests of isolated HeatDiffusion; not for coupled system |
| Keep `t_inlet` dead parameter in `_channel_base_eqs` | No action needed | Misleading signature; future callers may try to use it | Remove during v0.2 tech debt cleanup phase (already documented) |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| HeatDiffusion ↔ ChannelAndContacts via ThermalPort | Forgetting that MTK `connect()` generates `Q_flow_left + Q_flow_right ~ 0` — so one side must not also define Q_flow independently | Let the channel's energy balance use `thermal_left[i].T` as a temperature boundary; define `q_wall` as an observable (`q_wall[i] ~ thermal_left[i].Q_flow`), not a driver |
| Python STREAM `Fuel.T` extract vs Julia `HeatDiffusion.T` | Python saves T as `T.reshape(self.shape)` — shape is `(nz, nx)`; Julia's MTK solution `sol[hd.T]` returns whatever shape was declared | Declare `(T(t))[1:nz, 1:nx]` to match Python, or explicitly transpose before numerical comparison |
| Python `Fuel.indices()` left/right swap | Assuming `T_wall_left` in Python maps to the left side of the plate — it does not; indices() swaps it | Test with asymmetric temperatures before trusting the coupling direction |
| ChannelAndContacts `thermal_left` array vs old `thermal1..thermalN` | MTK port access: `sys.thermal_left[1].T` vs old `sys.thermal1.T` — different syntax for array vs named ports | Confirm MTK's array port access syntax for your version before writing tests |
| Sundials IDA tolerance on mixed-scale system | Default atol=1e-6 works for 300-700 K temperatures but may be too loose for small `dx` FD cells with steep gradients | Set atol per-variable: tighter on T (1e-4 is sufficient for 1% validation) and normal on algebraics |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `mtkcompile` symbolic explosion on large FD grid | Compilation takes >2 minutes; Julia OOM on 20x20 grid | Benchmark with 3x3 first; use `sparse=true` in mtkcompile if available | Grid > ~10x10 with full algebraic channel coupling |
| Sundials IDA Jacobian density for O(100) state system | IDA takes >10 seconds per time step; progress bar stalls | Ensure MTK generates sparse Jacobian (default in MTK v9+); verify `jac_sparsity` is not dense | Any system with >50 states and dense coupling |
| Re-compilation on every test run | Each test recreates the MTK system from scratch; `mtkcompile` dominates test time | Cache compiled system across tests using module-level `const` or `@testset` setup block | Test suite with >5 test cases using the same compiled system |
| FD stencil with non-uniform grid spacing | Arithmetic mean of neighbor temperatures is wrong for non-uniform dx | Use harmonic mean of conductivities weighted by dx (as Python STREAM does) | Any plate with fuel+cladding layers of different thicknesses |

---

## "Looks Done But Isn't" Checklist

- [ ] **Axis convention:** T array axis order is documented AND matches Python STREAM's `(nz, nx)` convention — verify by extracting T at a known asymmetric condition and comparing element-by-element with Python output
- [ ] **Adiabatic unconnected ports:** One-sided connection test passes (HeatDiffusion with only thermal_left connected; thermal_right sees Q_flow ~ 0 at steady state)
- [ ] **Q_flow sign consistency:** `sum(thermal_left[i].Q_flow) + sum(thermal_right[i].Q_flow)` equals total power deposited in plate at steady state (energy balance closure)
- [ ] **ChannelAndContacts migration:** All existing THERM tests still pass after thermal_ports → thermal_left + thermal_right rename
- [ ] **Asymmetric coupling:** Left channel at different temperature than right channel produces correctly asymmetric plate temperature profile (not mirrored)
- [ ] **v0.2 tech debt:** `_channel_base_eqs` dead `t_inlet` parameter removed, THERM-03 direct assertion added, 09-01-SUMMARY.md cosmetic fix applied
- [ ] **MTR reference case:** Coupled system steady-state T_outlet and T_wall_max match Python STREAM within 1% on identical inputs

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Axis convention mismatch discovered at validation | MEDIUM | Transpose the Julia T array extraction in the validation script; no component rewrite needed if the Julia array indexing is internally consistent |
| Left/right swap error discovered after tests pass | MEDIUM | Swap the `thermal_left` ↔ `thermal_right` connection in the coupling equations; re-run all coupled tests |
| Q_flow sign error causing reverse heat transfer | LOW | Add a negative sign to the boundary flux equation in HeatDiffusion; all other equations are unchanged |
| mtkcompile timeout on large grid | HIGH | Reduce grid to 5x3 for validation, or restructure the FD equations to reduce algebraic coupling (e.g., compute FD fluxes as Julia functions rather than symbolic equations) |
| Inconsistent IC causing IDA failure | MEDIUM | Implement the decoupled warm-start strategy: solve channel-only first, then fuel-only, then couple |
| ChannelAndContacts port rename breaks tests | LOW | Bulk search-replace `thermal_ports\[i\]` → `thermal_left[i]` (or `thermal_right[i]`) with appropriate context |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Axis convention T[z,x] vs T[x,z] | Phase 1: HeatDiffusion component implementation | Extract T at asymmetric condition, compare element-by-element with Python `Fuel.save()` output |
| Python left/right swap in indices() | Phase 3: MTR reference case validation | Asymmetric heating test: pin left channel 50K hotter than right; confirm left plate surface is hotter |
| Q_flow sign convention | Phase 1: HeatDiffusion component implementation | Unit test: isolated plate with T_boundary < T_interior; verify `sum(Q_flow) < 0` on fuel ports |
| mtkcompile performance on 2D FD | Phase 1: HeatDiffusion component implementation | Benchmark `@time mtkcompile(...)` on 3x3, 5x5, 10x10 grids; document in VALIDATION.md |
| ChannelAndContacts port rename breaking change | Phase 2: ChannelAndContacts upgrade | All existing THERM tests pass after rename; zero new failures introduced |
| Adiabatic unconnected ports | Phase 2: ChannelAndContacts upgrade + Phase 3 | One-sided connection test: `thermal_right` unconnected; verify Q_flow ~ 0 at right boundary |
| FD top/bottom Neumann BC conflicts with stencil | Phase 1: HeatDiffusion component implementation | Verify axial temperature profile has zero gradient at top and bottom rows |
| Inconsistent IC for coupled system | Phase 3: MTR reference case validation | Coupled steady-state solve converges from decoupled warm-start IC; no `calc_ic` failure |

---

## Sources

- Python STREAM `heat_diffusion.py` (direct source read): `Fuel.__init__`, `Fuel.calculate`, `Fuel.indices()` — confirms `self.shape = (m, n)` = `(nz, nx)`, and the intentional left/right swap in `indices()`
- Python STREAM `SKILL.md` (stream-user): `Fuel` variables documentation, `plate()` / `symmetric_plate()` composition API, coupling direction convention
- Python STREAM `tribal_knowledge.md`: tribal rule on `T_left / T_right` referring to x-direction boundaries
- Julia `connectors.jl`: `ThermalPort` Q_flow sign declaration (`positive = into component`)
- Julia `components.jl`: `ChannelAndContacts` implementation — existing `thermal_ports` naming, `q_wall[i] ~ thermal_ports[i].Q_flow` 1:1 mapping
- Julia `PROJECT.md`: v0.3 requirements, current ChannelAndContacts interface contract
- MTK documentation patterns (HIGH confidence from v0.1/v0.2 established patterns): `compose()` with array ports, `[connect = Flow]` Kirchhoff semantics, `mtkcompile` structural simplify behavior

---
*Pitfalls research for: 2D MTK FD components + two-sided ThermalPort coupling (Julia-STREAM v0.3)*
*Researched: 2026-03-13*

# Phase 16: Validation - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Write quantitative test assertions that prove HeatDiffusion transient behavior and two-plate coupling configurations are physically correct. Covers VAL-01 (transient Fourier series), VAL-02 (two HeatDiffusion to one CAC), VAL-03 (one-sided T_max analytical assertion). No new components or correlations — validation only.

</domain>

<decisions>
## Implementation Decisions

### VAL-01: Transient scenario

- **Pure plate test, no fluid** — only HeatDiffusion + ConstantTemperature BCs on both faces; no hydraulic loop
- **Both faces prescribed at T_wall** — thermal_left[i] and thermal_right[i] all set to T_wall via ConstantTemperature BCs
- **No internal power** — power=0; plate starts uniform at T0 ≠ T_wall and relaxes toward T_wall (pure diffusion)
- **Assert at multiple time points**: t = {0.5τ, 1τ, 2τ, 5τ} where τ = Lx²/(π²α), α = k_s/(ρ_s·cp_s)
- **Aluminum MTR plate parameters**: rho_s=2700, cp_s=900, k_s=200 — same as existing VAL tests; nz=10, nx=5, Lx=0.00127m
- τ ≈ Lx²/(π²α) = (0.00127)²/(9.87 × 8.23×10⁻⁵) ≈ 0.002 s (2 ms); 5τ ≈ 10 ms total; fast ODE solve

### VAL-01: Fourier series analytical reference

- **Formula** (symmetric BCs, both faces at T_wall, uniform initial T0, no power, center at x=Lx/2):
  ```
  T(x,t) = T_wall + (4/π)(T0 - T_wall) Σ_{n odd} (1/n) sin(nπx/Lx) exp(-α(nπ/Lx)²t)
  ```
  Assertions use x = Lx/2 → sin(nπ/2) = ±1 for odd n; series converges rapidly for t > 0.1τ
- **50 Fourier terms** summed in the analytical reference (more than sufficient for convergence)
- **rtol=0.01** (1%) — consistent with all other validation tests in this codebase
- **Time span**: (0, 5τ); compare at t = 0.5τ, 1τ, 2τ, 5τ (4 assertion points)

### VAL-02: Two HeatDiffusion to one ChannelAndContacts topology

- **Topology**: One ChannelAndContacts with BOTH faces simultaneously active:
  - `thermal_left[i]` → HeatDiffusion_1 (plate1) left face
  - `thermal_right[i]` → HeatDiffusion_2 (plate2) left face (so plate2 is also on the right of the channel)
- **Assembly**: Manual `connect()` wiring — no composition helpers (keep physics test isolated from helper correctness)
- **Symmetric setup**: Both plates have identical power, material, geometry (same MTR parameters as VAL-01/02/03)
- **Assertions** (all four required):
  1. `sol.retcode == ReturnCode.Success`
  2. Energy balance: `T_rise ≈ (P1 + P2) / (mdot * cp)` (both plates heat the single channel, rtol=0.05)
  3. Each plate T_center > T_fluid at midaxial row: `sol[hd1.T[nz÷2, (nx+1)÷2]] > sol[cac.T[nz÷2]]`
  4. Q_flow < 0 on connected faces for each plate (heat flows FROM plate TO fluid, MTK convention)

### VAL-03: One-sided T_max analytical assertion

- **"T_center" = hottest point = adiabatic face** (not the lateral midpoint): `sol[ssys.hd.T[nz÷2, nx]]`
  - j=nx is the rightmost lateral cell (the adiabatic face) — this is where T is maximum for one-sided coupling
  - The existing VAL-03 test uses j=(nx+1)÷2 (lateral midpoint) for `T_center_03`; the new assertion uses j=nx
- **Analytical formula** (uniform volumetric generation, left face at T_wall, right face adiabatic, steady state):
  ```
  T_max = T_wall_avg + q * Lx / (2 * k_s * A)
  where A = y * Lz  (face area of the plate)
  ```
- **T_wall_avg** = mean of `sol[getproperty(ssys.cac_l, Symbol(:thermal_left, i)).T]` for i in 1:nz
  (Average wall temperature across all axial cells — approximation since T_wall varies axially)
- **Integration**: Add the assertion to the EXISTING Phase 12 VAL-03 test (`@testset "VAL-03: One-sided MTR — left channel only, thermal_right adiabatic"`); do NOT create a new test
- **Update the NOTE comment** in that test: change "T_plate_center quantitative assertion omitted" to document the new assertion and its formula
- **Tolerance**: rtol=0.01 — consistent with project conventions
- **Expected values** for existing test params (nz=10, nx=3, k_s=200, Lx=0.00127, y=0.07, Lz=0.6, q=1e4):
  - A = 0.07 × 0.6 = 0.042 m²; ΔT ≈ 10000 × 0.00127 / (2 × 200 × 0.042) ≈ 0.756 K above T_wall_avg
  - Very small ΔT expected for aluminum — the assertion validates the diffusion equation is correct even for small signals

### Claude's Discretion

- Exact time points for Fourier comparison (can adjust 0.5τ, 1τ, 2τ, 5τ to convenient round numbers in seconds)
- Whether to use `solve_transient` or raw `solve()` for the VAL-01 transient test
- How to wire ConstantTemperature BCs to all nz thermal ports (loop vs. vectorized comprehension)
- Exact T0 and T_wall values for the transient test (e.g., T0=400K, T_wall=300K for clear signal)
- Number of cells for VAL-02 (can reuse nz=10, nx=3 for consistency)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing test structure (VAL-03 integration point)
- `test/runtests.jl` §VAL-03 (line ~1066-1141) — existing one-sided test to modify; append T_max assertion and update NOTE comment

### HeatDiffusion component
- `src/components.jl` §HeatDiffusion (line ~610-655) — T[nz,nx] state layout, thermal_left/right port naming, adiabatic semantics
- `src/components.jl` §_diffusion_eqs (line ~547-608) — how lateral diffusion equations are built; boundary conditions

### ConstantTemperature BC (for VAL-01)
- `src/components.jl` — ConstantTemperature component (check if it exists; if not, the test may need direct `thermal_left[i].T ~ T_wall` equations instead)

### Python STREAM reference tests (for VAL-02 energy balance cross-check)
- `~/projects/STREAM/tests/test_calculations/test_heat.py` — analytical validation patterns used in Python STREAM

No external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- `ConstantTemperature` (`src/components.jl`): check if this exists as a component; if so, use it for the VAL-01 prescribed BC. If not, use direct MTK equations `thermal_left[i].T ~ T_wall` inside the composed system.
- Existing `@testset "VAL-03: One-sided MTR..."` (test/runtests.jl:1068): full setup already there; just append T_max assertion
- `solve_transient` (src/solvers.jl): used in existing SOLV-02 tests; check if suitable for the isolated plate transient or if raw `solve()` is better
- `build_initializeprob=false`: MUST be used for any HeatDiffusion solve (established project decision)

### Established Patterns

- MTK port array access: `getproperty(ssys.hd, Symbol(:thermal_left, i))` — used in existing VAL-03 test for Q_flow check
- rtol=0.01 for all numerical comparisons — project-wide convention
- MTR parameters: rho_s=2700, cp_s=900, k_s=200, Lx=0.00127, y=0.07, Lz=0.6, power=1e4 — reuse for consistency
- mdot initial guess: +0.250 for rectangular Dh≈2.495mm at dP=30 kPa

### Integration Points

- `test/runtests.jl`: new @testset blocks for VAL-01 and VAL-02 added after Phase 15 COMP tests; VAL-03 assertion added inline to existing Phase 12 VAL-03 test
- Phase 12 VAL-03 test at line ~1066: modify in-place (add T_max assertion, update NOTE comment)

</code_context>

<specifics>
## Specific Ideas

- The Fourier series for VAL-01 converges very quickly for symmetric BC: by n=50, terms like sin(nπ/2)/n × exp(-n²π²αt/Lx²) are negligibly small even at t=0.5τ
- VAL-01 τ ≈ 2 ms for aluminum MTR plate — the solve will be very fast; no performance concern
- VAL-03 expected ΔT ≈ 0.756 K above T_wall_avg — very small signal, proving the high-k aluminum diffusion equation is quantitatively correct even in the limit of small temperature gradients
- VAL-02 tests the Phase 10 two-sided upgrade end-to-end: this is the first test where BOTH thermal_left AND thermal_right of a single CAC are simultaneously connected to plates (Phase 12 tested them in separate @testsets)

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 16-validation*
*Context gathered: 2026-03-15*

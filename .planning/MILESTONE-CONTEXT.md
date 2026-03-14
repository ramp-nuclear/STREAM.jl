# Milestone Context: v0.4 — Composability & Physics

**Created:** 2026-03-14
**Status:** Ready for requirements + roadmap

This file captures the full scope, rationale, and design decisions for v0.4 agreed in the milestone planning session. Read this before writing requirements or planning any phase.

---

## Milestone Goal

Make Julia STREAM ergonomic for real reactor assembly workflows and physically correct for the full MTR operating envelope (including laminar flow). The two pillars are:

1. **Composability** — users build subsystems independently and assemble them, like Python STREAM's `symmetric_plate()` / `plate()` / `CalculationGraph +`
2. **Physics accuracy** — fix the Dh computation (wet vs heated perimeter), add laminar flow regime support, clean up power shape and pump API

---

## Group A: Validation & Correctness

### VAL-01: Transient HeatDiffusion validation

**What:** Step change in `power` parameter → solve transient → compare T_plate(t) to analytical 1D slab diffusion solution within tolerance.

**Why:** HeatDiffusion's ODE equations (`_diffusion_eqs`) have never been validated in time — only at steady state. The diffusion terms could have a wrong sign, wrong coefficient, or wrong boundary condition and all steady-state tests would still pass. This is a real gap.

**Implementation note:** 1D slab with uniform heat source, adiabatic boundaries, known initial condition has a textbook analytical solution (Fourier series). Use a simple nz=1, nx=3 geometry (cladding+meat+cladding treated as uniform slab) so the geometry is simple enough for an analytical reference. Compare T_plate_center(t) at a few time points.

---

### VAL-02: CHAN-04 — two HeatDiffusion instances on one ChannelAndContacts

**What:** Connect a HeatDiffusion to `thermal_left` and a different HeatDiffusion to `thermal_right` of a single ChannelAndContacts. Verify steady-state solves correctly.

**Why:** This is the "channel sandwiched between two fuel plates" geometry (common in MTR). The dual-port architecture was designed for this but was never tested with two active plates simultaneously. It may just work, or there may be a subtle issue with the energy balance equation (`q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow`) when both sides are non-trivial.

**Implementation note:** If it already works, the phase is just adding a test. If it doesn't, find and fix the equation. Either way, create a VAL test.

---

### VAL-03: One-sided connection quantitative assertion

**What:** Add a quantitative `T_plate_center` assertion to VAL-03.

**Why:** This assertion was omitted in v0.3 because Python STREAM's `one_sided_connection()` gives T_plate_center = 318.48 K (same as the symmetric case — physically wrong: with only one active face, the plate center must be hotter). Julia gives 323.64 K, which is physically correct. The Python reference is buggy for this scenario.

**Implementation note:** Derive the reference value from energy balance, not from Python STREAM. For a plate with one adiabatic face and one active face, the steady-state center temperature is analytically derivable: T_center = T_wall + q_total * L / (2 * k * A). Use this as the assertion reference. Document the Python STREAM discrepancy explicitly in the test comment.

---

## Group B: Composition Helpers

### COMP-01: `symmetric_plate(channel, fuel)`

**What:** Takes one ChannelAndContacts + one HeatDiffusion, returns a pre-wired complete MTK ODESystem with HeatDiffusion's `thermal_left` and `thermal_right` both connected to the same channel's corresponding ports.

**Why:** The most common MTR geometry. Currently requires ~10 lines of manual MTK wiring. Python STREAM's `symmetric_plate()` is one line.

**Python reference:** `stream.composition.symmetric_plate(channel, fuel, funcs={...})`

**Design intent:** Return a fully composed ODESystem that can be passed directly to a solver. The user provides initial conditions (mdot, Tin, power) separately via u0/p, not as funcs arguments (since Julia uses MTK parameter/remake approach instead of Python's funcs dict).

---

### COMP-02: `plate(ch_left, ch_right, fuel)`

**What:** Takes two distinct ChannelAndContacts + one HeatDiffusion, returns pre-wired ODESystem. Left channel connects to `thermal_left`, right channel to `thermal_right`.

**Why:** Two independent channels on either side of a plate (different inlet temperatures, flow rates). This is what VAL-02 (asymmetric) tested manually. Python STREAM's `plate()` function.

**Python reference:** `stream.composition.plate(channel_left, channel_right, fuel)`

---

### COMP-03: `one_sided_connection(channel, fuel, side=:left)`

**What:** Connects a channel to one side of HeatDiffusion only. Other side is left unconnected (adiabatic by MTK default).

**Why:** Already tested in VAL-03 but requires manual MTK wiring. Python has `one_sided_connection(channel, fuel, fuel_side='left')`.

---

### COMP-04: `compose_systems(sys_a, sys_b, connections)` — composable subsystem assembly

**What:** Takes two independently-built ODESystems + a list of port connections, calls `compose()` + `connect()`, and returns a merged system. Also encapsulates the solver setup quirks (build_initializeprob=false, initial guess construction).

**Why:** Python STREAM's killer ergonomic feature is `CalculationGraph +` — users build a thermal subsystem and a hydraulic subsystem separately, then merge them with `core = thermal + hydraulic`. Julia STREAM needs this for complex topologies (multi-rod assemblies, full-core models). Without it, wiring grows O(n²) in complexity.

**Design intent:**
```julia
# Build subsystems independently
thermal = symmetric_plate(channel, fuel)
hydraulic = build_loop(pump, channel, friction)
# Compose
sys = compose_systems(thermal, hydraulic, [
    thermal.channel.port_in => hydraulic.channel.port_out,
    thermal.channel.port_out => hydraulic.channel.port_in,
])
```

The helper should also handle the `build_initializeprob=false` requirement and warn if ports are left unconnected.

---

## Group C: Physics Accuracy

### PHY-01: `wet_perimeter` in PipeGeometry

**What:** Add `wet_perimeter` field to PipeGeometry. Hydraulic diameter Dh = 4A / wet_perimeter (not 4A / heated_perimeter). Update rectangular constructor to compute wet_perimeter = 2*(edge1 + edge2) (all four walls are wetted). Update circular constructor: wet_perimeter = π*D (same as heated_perimeter for circular).

**Why:** For rectangular MTR channels, the heated perimeter (two long edges = 2*y = 0.14 m) differs from the wet perimeter (all four walls = 2*(y + gap) ≈ 0.144 m). Dh computed from heated perimeter gives wrong Re, wrong friction, wrong HTC. This is a physics accuracy gap in the current implementation.

**Python reference:** `EffectivePipe` has both `heated_perimeter` and `wet_perimeter` separately. `EffectivePipe.rectangular(length, edge1, edge2, heated_edge)` sets wet_perimeter = 2*(edge1+edge2) automatically.

**Migration note:** Existing call sites use `PipeGeometry.rectangular(; L, y, ...)` — need to check whether existing tests are affected and update reference constants if Dh changes.

---

### PHY-02 + PHY-03 + PHY-04: Laminar flow regime support

**What:** Three correlation additions:
- `constant_Nusselt(Nu=8.235)` — fixed Nu for fully-developed laminar rectangular duct flow
- `laminar_friction(Re)` — f = 64/Re (circular) or correction for rectangular
- `regime_dependent(; Re_transition=2300)` — wraps any htc_correlation + friction_correlation, switches based on Re

**Why:** Dittus-Boelter (Nu = 0.023 Re^0.8 Pr^0.4) is valid only for Re > 10,000. For MTR channels at low power or low flow, Re can drop below 4000. Dittus-Boelter gives physically wrong HTC in this regime. Nu=8.235 is the analytical result for fully-developed laminar flow in a rectangular duct with uniform heat flux.

**Python reference:** `stream.physical_models.heat_transfer_coefficient` has `constant_Nusselt_h_spl`, `regime_dependent_h_spl`. `stream.physical_models.pressure_drop` has `laminar_friction`, `regime_dependent_friction`.

**Implementation note:** These should be pluggable into ChannelAndContacts via a `htc_correlation` and `friction_correlation` constructor argument (default: current Dittus-Boelter + Blasius). The switching in `regime_dependent` must be smooth or use `ifelse()` to avoid solver discontinuity — same approach as flow reversal smoothing currently used.

---

### PHY-05: Fixed-flow `Pump(mdot0=...)`

**What:** Pump accepts `mdot0` keyword argument. When set, the pump acts as a fixed-flow boundary condition (mdot = mdot0 = const) instead of a fixed-pressure source.

**Why:** Fixed-flow pumps are a common boundary condition. Python STREAM's Pump supports both `pressure=` (fixed dp) and `mdot0=` (fixed flow) modes as mutually exclusive options.

**Python reference:** `Pump(pressure=1e5)` vs `Pump(mdot0=0.5)` — two modes, cannot use both.

**Implementation note:** In MTK, fixed-mdot is implemented by adding a constraint equation `port_in.mdot ~ mdot0` instead of the pressure-rise equation. May require a separate Pump variant or a dispatch branch.

---

### PHY-06: Power shape normalization assertion

**What:** HeatDiffusion constructor asserts `abs(sum(power_shape) - 1.0) < 1e-6` and throws a clear error if not satisfied. Error message should say: "power_shape must be normalized (sum = 1.0); got sum = X. Normalize before passing."

**Why:** Currently, passing unnormalized power_shape (e.g., `ones(5,3)`) silently gives wrong results — power is scaled by a factor of 15 with no warning. Python STREAM normalizes internally; we chose to assert instead (caller responsibility, but explicit).

**Decision made:** Assert, do not normalize. Keeps behavior explicit and prevents silent wrong physics.

---

## Group D: Developer QoL

### QOL-01: `@observed` variables in ChannelAndContacts

**What:** Declare Re, Nu, h_tc (or h_left/h_right), T_wall_left, T_wall_right, q_wall_left, q_wall_right, q_total as MTK `@observed` variables in the ChannelAndContacts ODESystem. These must be accessible via `sol[sys.ch.Re, :]` after solving.

**Why:** Currently, users have no way to inspect heat transfer coefficient, Reynolds number, or wall temperature from a solution — these are computed inside the MTK equations but not declared as accessible observed variables. Python STREAM's `ChannelAndContacts.save()` adds Re, Pe, Gr, T_wall, heatflux, power automatically.

**Implementation note:** In MTK, `@observed` equations are declared with `@variables` + included in the `observed=` argument of `ODESystem`. Check whether h_tc is already a declared MTK variable in the current implementation — it might be reduced away by `mtkcompile`. If so, it needs to be kept as an observed equation. Test: after solve, `sol[sys.ch.Re, :]` should return an array of length nz.

---

### QOL-02: `check_gravity_mismatch(sys)`

**What:** Function that takes a loop ODESystem and checks whether the sum of gravity pressure terms balances to zero at zero flow. Returns `:ok` or throws a warning with the imbalance value.

**Why:** Python STREAM's tribal knowledge rule #5: "Always call check_gravity_mismatch() after building a FlowGraph." Channels include gravity internally. If the return leg doesn't have a balancing Gravity component, the loop pressure is wrong but the solver may still converge — silent error. Currently Julia STREAM has this risk and no detection.

**Python reference:** `fg.check_gravity_mismatch()` in FlowGraph.

**Implementation note:** May be simpler as a documentation/warning in symmetric_plate/compose_systems helpers rather than a standalone function that inspects the MTK system structure. Either is acceptable.

---

### QOL-03: `port(sys, :thermal_left, i)`

**What:** Helper function: `port(sys, :thermal_left, i)` returns `getproperty(sys, Symbol(:thermal_left, i))`. Thin wrapper hiding the MTK named-subsystem access pattern.

**Why:** `getproperty(sys, Symbol(:thermal_left, i))` is the correct MTK pattern for accessing indexed port subsystems, but it's non-obvious and appears multiple times in user-facing code. `sys.thermal_left[i]` fails in `connect()` calls, which confuses users. The wrapper makes the intent clear and hides the footgun.

---

## Out of Scope for v0.4

| Feature | Reason |
|---------|--------|
| Point kinetics (KIN-01) | Architecture proven in v0.3; defer to v0.5 when thermal-hydraulic composability is established |
| xz-diffusion (DIFF-01) | No validation target defined yet |
| r-diffusion / rz-diffusion (DIFF-02) | No validation target |
| Multi-material HeatDiffusion | Design agreed; defer until concrete multi-material case needed |
| `channel_outputs()` helper function | Not needed: `@observed` makes `sol[sys.ch.Re, :]` work directly |
| `frozen_water(T, p)` | Testing convenience; not urgent |
| Subcooled boiling, natural convection | No validation target |
| Heavy water / other fluids | Light water sufficient through v0.4 |
| UQ / sensitivity analysis | Post-validation concern |
| Decay heat | Needs point kinetics first |
| `chain_fuels_channels()`, `rod()` | After compose_systems() is proven; multi-rod follows |

---

## Key Context for Implementation

- **Phase numbering:** v0.4 starts at Phase 13 (v0.3 ended at Phase 12.1)
- **Python STREAM reference:** `/home/itay/projects/STREAM` — read `.claude/skills/stream-user/SKILL.md` for full API before implementing any composition helper
- **MTK port array access pattern:** Use `getproperty(sys, Symbol(:thermal_left, i))` — `sys.thermal_left[i]` fails in `connect()`
- **KINSOL + build_initializeprob=false:** Required for all coupled HeatDiffusion+CAC systems; compose_systems() helper must encapsulate this
- **Initial guess sensitivity:** mdot must be positive (+0.600 kg/s for MTR geometry); encode this knowledge in the guess helpers inside composition functions
- **Dh computation change:** wet_perimeter addition (PHY-01) may shift Dh slightly for rectangular channels → re-run Python STREAM reference and update VAL-01/02/03 constants if needed before writing new tests

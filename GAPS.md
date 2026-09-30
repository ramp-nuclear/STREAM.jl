# Gaps against Python STREAM

What is left before STREAM.jl can replace Python STREAM: RIA, LOFA and LOCA transients in
light- and heavy-water research reactors with MTR plate fuel and cylindrical rod fuel, and the
steady-state margins asked for most days.

There are two Python references. `main` is 13,585 lines across 62 modules. The `stream-next`
branch, 20,787 lines across 79 and not yet merged, fixes a set of correlations and adds loss of
coolant, a steady-state guess toolkit and plotting. STREAM.jl is 8,221 lines across 42 files.

Everything here was checked against both sources rather than inferred from names. What was
checked and found equivalent is listed at the end, so nobody has to re-derive it.

## Contents

- [Where things stand](#where-things-stand)
- [In review](#in-review)
- [What remains](#what-remains)
  1. [Loss of coolant: the benchmark and the pressure anchor](#1-loss-of-coolant-the-benchmark-and-the-pressure-anchor)
  2. [Fuel heat conduction](#2-fuel-heat-conduction)
  3. [Saturation stop and range checks](#3-saturation-stop-and-range-checks)
  4. [Thresholds](#4-thresholds)
  5. [Power shapes](#5-power-shapes)
  6. [Hydraulic components](#6-hydraulic-components)
  7. [Debugging and drawing a model](#7-debugging-and-drawing-a-model)
  8. [Uncertainty quantification](#8-uncertainty-quantification)
- [Not planned](#not-planned)
- [Deliberate departures from Python](#deliberate-departures-from-python)
- [Following Python where the physics is open](#following-python-where-the-physics-is-open)
- [Checked and equivalent](#checked-and-equivalent)
- [Where STREAM.jl is ahead](#where-streamjl-is-ahead)

## Where things stand

| Case | Python | STREAM.jl | What is missing |
|---|---|---|---|
| Steady margins, plate fuel | Yes | Yes | Only the plain Saha-Zuber form ([4](#4-thresholds)) |
| LOFA | Partly, see below | Yes | Nothing |
| RIA, plate fuel | Yes | Partly | Axial conduction and a clad plate ([2](#2-fuel-heat-conduction)), the blister limit ([4](#4-thresholds)) |
| RIA, rod fuel | Yes | No | Cylindrical conduction and gap conductance ([2](#2-fuel-heat-conduction)), fuel enthalpy ([4](#4-thresholds)) |
| LOCA to core uncovery | On `stream-next` | Yes | Python's multichannel benchmark ([1](#1-loss-of-coolant-the-benchmark-and-the-pressure-anchor)) |
| LOCA past uncovery | No | No | Out of scope for both, by choice |

LOFA is where Python `main` runs short. Its own benchmark on `stream-next`, run against
v1.1.2, needed hand workarounds throughout: a ballpark steady guess crashed the solver, the
flapper opened at whichever output time first saw the crossing, a tight tolerance stalled for
over 20 minutes, a realistic power with a scram died at 15.9 s, and a four-channel case died at
89.6 s. One channel type with a careful guess was what worked. `stream-next` fixes those.

Here several assembly types in parallel run on `Connect.weighted`, Python's junction
`signify=N`, and the pool LOFA example on the `lofa` branch takes two of them through the
pump trip, the scram, the flapper opening and flow reversal into natural circulation, with
every event at its exact instant.

Both codes are single-phase liquid with subcooled-boiling heat transfer and thresholds that
report margin. That is enough to follow a pool level down to core uncovery and say when the
model leaves its own validity. It is not enough for what comes after: void, steam properties,
two-phase friction, post-CHF heat transfer, radiation, rewet and metal-water reaction. Neither
code has any of those, and neither should grow them casually.

## In review

**#34** ports `stream-next`'s correlation fixes and a mixed-convection change. When it merges,
delete this section and move its items to the lists below:

- Local-loss Reynolds number on the diameter, not the radius
- Sudo-Kaminaga reading the inlet at the end the flow enters
- Bilinear inertia floored above zero, so a coastdown can reach zero flow
- `solve_steady` and `solve_transient` throwing on a failed return code
- Elenbaas on `|Ra|`, turbulent friction floored by `64/Re`, Shah and London's table for the
  developing-laminar Nusselt number, and the H₂O cₚ and D₂O μ fits held short of their poles
- Forced and natural convection combined by Churchill's rule, with the minus sign where
  buoyancy opposes the flow, which Python does not take. That becomes a deliberate departure.

---

## What remains

In order of what it unblocks.

### 1. Loss of coolant: the benchmark and the pressure anchor

A pool drains to core uncovery: `Components.Tank` and `Environment`, an `Orifice` break that
opens, and latches shut for a siphon breaker, on its `StateMachine`, the discharge correlations
in `LocalLoss`, `Thresholds.cavitation`, and `Examples.build_pool_break`. The tests port
Python's drain, siphon, two-hole, heated-pool and pool-break scenarios, and the Torricelli
drain matches the closed form to 8e-5 m. Two pieces remain:

- **Python's multichannel benchmark**, `benchmarks/lofa/loc_extension.py`: its pool drains
  5948 kg to uncovery at 2740.6 s, with the flapper opening at 58.4 s and mass closure of
  6e-7. It builds on the pool LOFA example, which is not on `main` yet.
- **The tank surface as the loop's pressure anchor.** A loop with a `Tank` or an
  `Environment` has its absolute pressure, so the hand-written `pump.inlet.p ~ 1.0e5` every
  other example carries could go.

**Size:** a few days for the benchmark, most of it matching Python's timings. The anchor is a
sweep through the examples and tests.

### 2. Fuel heat conduction

`HeatDiffusion` is one kernel: 2D Cartesian, one material, a uniform mesh, no interface
resistance and no axial conduction. Python's `Fuel` has all of these:

| Missing | Python | Why it matters |
|---|---|---|
| Cylindrical geometry | `r_diffusion`, `rz_diffusion`, `cylindrical_areas_volumes` | No rod fuel at all without it, the largest gap against the stated goal |
| Axial conduction | `xz_diffusion`, `rz_diffusion` | Our slices are thermally independent. It matters at the ends of the heated length and near a partly inserted rod |
| Per-cell material | `Solid.from_array`, `meat_indices`, `x_boundaries(clad_N, fuel_N, ...)` | A clad plate cannot be represented. Face conductivities need a harmonic mean |
| Non-uniform mesh | `x_boundaries`, `z_boundaries` | Fine cells in the cladding, and at a rod's centre where the radial profile is steepest |
| Contact conductance | `_resistances(dr, contacts, k)` | The pellet-clad gap dominates a rod's thermal resistance, and its closing is first-order in an RIA |

Do them as one rework of `_diffusion_eqs`, with the metric, material and mesh as parameters,
rather than touching it five times.

**Size:** medium. The radial metric is spelled out in `cylindrical_areas_volumes`, and the rest
is mechanical once the kernel takes arrays.

### 3. Saturation stop and range checks

The channel model ends at bulk saturation, and nothing says so during a run. `stream-next` adds:

- An opt-in stop at bulk saturation. Here that is one abort transition per channel on
  `T_sat − T_bulk`, with `T_sat` already at the static pressure.
- Post-run saturation crossings, first crossing, and raise-on-crossing.
- Declared validity ranges per coolant, 0.1 to 350 °C for H₂O and 3.8 to 300 °C for D₂O,
  and a report of any state outside them. This matters more here than in Python, because our
  property fits fold their argument through `abs`, which hides a value out of range instead of
  producing NaN.

**Size:** 100 to 130 lines, in `src/thresholds/analysis.jl` beside `threshold_analysis`.

### 4. Thresholds

- **The plain Saha-Zuber form.** We have only the computed-bulk one. Python puts a
  `.. danger::` on the plain form and says you probably want the other, so this is for
  completeness. Trivial.
- **RIA limits.** Peak cladding temperature and DNBR are there, through `twall_limit` and
  `chfr`. The blister temperature for aluminide and silicide plates is not, nor is a fuel
  enthalpy accumulator, the standard rod-fuel criterion, which needs the cylindrical kernel
  first. Python has neither. Small, after §2.
- **`heated_diameter`**, `4·area/heated_perimeter` on the geometry. Python computes it and
  never reads it. Trivial.

### 5. Power shapes

`Utilities.cosine_shape` ports Python's, with a non-uniform mesh, cell integration, a peaking
factor and an off-centre peak. Still missing: `cosine_shape_by_zero_endpoints`, the
extrapolated cosine with non-zero flux at the ends that a reflected core has, and
`uniform_x_power_shape` for the lateral direction across clad and meat. Small, pure functions.

### 6. Hydraulic components

`Bend`, `Screen` and `bend_factor`, the Idelchik bend and wire-mesh screen losses. Each is
small and independent.

### 7. Debugging and drawing a model

| Python | What it does | Have it? |
|---|---|---|
| `analysis/report.py` | Tables of every calculation's variables, flagging unset and externally-set ones | No |
| `analysis/debugging.py` | Inspecting a bad initial guess | No |
| `Aggregator.draw` | Draws the calculation graph | No |

MTK covers some of it: `unknowns`, `observed` and `equations` show what is being solved, and
`mtkcompile` refuses a model whose equations and unknowns do not balance. What remains is making a failed
initialisation easy to read, which is the hardest thing to debug in this codebase today, and
drawing a model. For the drawing, `ModelingToolkitDesigner.jl` is the direct replacement for
`Aggregator.draw` but pins MTK 8 and 9, so it needs a compat bump; `Latexify.jl` renders the
equations; and a component graph from the connection vectors `inseries`, `inparallel` and
`Connect.face` return needs nothing but `Graphs.jl`.

**Size:** small, and high value per line.

### 8. Uncertainty quantification

Python has `analysis/UQ/`: finite-difference Jacobians of solution values against input
parameters, a distributed version, uncertainty propagation, a power-shape perturbation, and
uncertainty factors on the threshold wrappers (`onb_factor` on the Bergles-Rohsenow superheat,
`inhomogeneity_factor` on the local flux for ONB and OSV). We have none of it, apart from
`twall_limit`'s `inhomogeneity_factor`.

The Julia route is SciMLSensitivity rather than a port: forward and adjoint sensitivities from
the AD Jacobians, with no step size to tune. Those are local, first-order derivatives at one
operating point, which is what a first-order propagation needs; variance over a parameter range
takes sampling on top, through `GlobalSensitivity.jl`.

One thing stands in the way. A `StateMachine` keeps its state and trip time in a Julia object,
outside the problem. So a second run with `remake` needs `reset!(machine)`, parallel runs need
a machine each, and a derivative with respect to a trip setpoint comes back as if the trip
never moved, with no error. Moving the trip time into the problem's parameters fixes all three.

**Size:** medium, and a different design from Python's.

---

## Not planned

- **`stream-next`'s solver-stability work**: residual smoothing, the globalised steady solve,
  translated error codes, construction-time wiring checks. MTK root-finds events, NonlinearSolve
  escalates from Newton to trust region to Levenberg-Marquardt, and `mtkcompile` rejects an
  unbalanced system. Revisit the smoothing only if a tight-tolerance run stalls at a flow
  reversal.
- **`stream-next`'s steady-state guess toolkit.** Python built it because scipy's root finder
  stalls from a poor guess. `solve_steady(...; solver=DynamicSS(Rodas5P()))` integrates to
  where the model settles instead of jumping to the nearest root, so seeding the flows reaches
  the forced-flow state of a LOFA model. The one trap: the flow unknowns `mtkcompile` keeps
  must start away from zero. Started at zero, the solve stays there and fails.
- **`stream.viz`**, plots of steady-state sweeps. Worth doing when parameter studies move here,
  starting with its inverse query, the parameter value at which a quantity meets a limit.
- **Sign constraints on the solve**, Python's `create_constraints`, as `isoutofdomain` here.
  Low value, and never on ṁ: a LOFA reverses the heated channel, which is the result being
  computed.
- **`profile_from_pk`**, which does not run in Python either.
- **Neutron capture in fission products**, the ANS-5.1 G factor, a TODO in Python too.

## Deliberate departures from Python

- **`DecayHeat.Fissions` interpolates logarithmically.** Python joins the samples with a
  straight line, which always overshoots a sum of decaying exponentials: up to 12% past the
  first interval of a coarse sampling, against 3.6% for the log form. `Linear()` restores
  Python's behaviour for a parity check. Neither saves a grid too coarse for the prompt drop.
- **The standards tables are not distributed.** They live in `DecayHeatStandards`, reached
  through `DecayHeat.standards_dir!` or `STREAM_DECAY_HEAT_STANDARDS`.
- **The power split is optional.** `PointKinetics(...; power_input)` gives `P ~ P_neutron +
  power_input`, and MTK tears the row out, so the state count stays `1 + G`. Python needs a
  separate `PointKineticsWInput` and a DAE row.
- **Scaling a resistor is composition.** No `ResistorMul` or `ResistorSum`: three resistors in
  `inseries` are three times the resistance, and a calibrated resistor's own coefficient is
  reached through `remake`.
- **The flapper always opens along the C1 ramp `3y² − 2y³`**, where Python defaults to its
  legacy relaxation. The opening time is the same.
- **A latching break closes by ramping its opening back to zero** along the same curve.
  Python freezes the flow at the moment of closure and ramps that down instead.
- **A tank counts only the ports flowing in** in its energy balance, switching with `ifelse`.
  Python smooths that switch with `soft_pos`.
- **A transient steps onto every saved time.** Python's solver reads the saved values off its
  interpolant, which strays inside a long implicit step: 0.5 m on a draining pool level.
  `solve_transient` passes the saved times as `tstops`, so every saved value is one the solver
  computed.

## Following Python where the physics is open

Where the physics has one right answer we use it, whether or not Python does. Where it does
not, we follow Python, so the two codes compare like for like. Revisit these once STREAM.jl
stands on its own.

- **Property temperatures in `HTC.RegimeDependent`.** Laminar and natural convection at the
  bulk, turbulent at the film, as Python's `regime_dependent_h_spl` does.
- **Rohsenow's constants.** Python's `n = 1.26`, `C_sf = 0.011` and exponent `1/0.33`, which
  we could not trace to a source. Textbooks give `n = 1.0` for water.
- **Where along a cell saturation is read.** Each cell's outlet-side face.

Names that differ: `HTC.rohsenow_scb_heat_flux` is Python's `Bergles_Rohsenhow_SCB_heat_flux`.
The flux is Rohsenow's (1952); Bergles and Rohsenow's (1964) part is the partial boiling
factor, `HTC.partial_SCB_correction`.

## Checked and equivalent

Verified as matching, so they need not be re-investigated:

- **Dimensionless numbers**, and the laminar-turbulent blend.
- **Nusselt correlations**: Dittus-Boelter, Marco-Han, two-sided heating, Elenbaas, the fully
  developed and developing laminar forms, the maximal combinator.
- **Friction correlations**: laminar, Colebrook-White, Blasius, the rectangular laminar
  correction, the regime blend.
- **Idelchik expansion and contraction losses.**
- **Liquid properties**, H₂O and D₂O, all nine, to the tolerances in `test_validation.jl`.
- **Decay heat contributions**: fission products, the U-238 capture chain and activation,
  against Python's doctests. The ANS-5.1 tables are now full precision, so the U-235
  ANS-5.1-2014 sum at shutdown is 6.728% of 200 MeV, as Python's doctest expects.
- **Threshold correlations and their channel-state wrappers**: CHF (Sudo-Kaminaga, Mirshak,
  Fabrega), OFI, OSV, ONB, boiling power and the wall temperature limit, compared with Python's
  `stream.analysis.thresholds` to 1e-9 in forward and reversed flow, and read at every saved
  time of a transient.
- **Saturation at the static pressure.** A port carries the total pressure; a channel's `P` is
  static, and both `T_sat` and the subcooled boiling in the solve read it.
- **The wall temperature interface.** Python's explicit `wall_temperature(T_cool, T_clad,
  h_cool, h_clad)` is what our acausal `ThermalPort` connection solves to, with
  `h_clad = k/(dx/2)`.
- **Natural circulation.** Each cell's momentum equation carries `ρ(T[i])·g·dz`, so no
  separate model is needed.
- **Channel variants**, pump modes, geometry (bar `heated_diameter`), and the flapper's open
  resistance in both flow directions.
- **Several channel types in parallel**, through `Connect.weighted`, against Python's
  `signify=50` junction.

## Where STREAM.jl is ahead

- **Acausal composition.** Python builds a flow graph and then Kirchhoff matrices, about 800
  lines of graph machinery. `connect` does it structurally.
- **Symbolic Jacobians and index reduction.** Python hand-writes `jacobians.py` and a mass
  vector per calculation. `mtkcompile` derives both, tears the algebraic loops and supplies a
  sparsity pattern.
- **The equations are readable**, before and after simplification, with `equations`,
  `unknowns` and `observed`.
- **Design knobs.** `@design_knob` keeps a dimension symbolic, so `remake` changes it without
  a rebuild.
- **Heat transfer and friction models are values** a channel is handed, and the heat transfer
  ones carry an explicit property basis, where Python hard-codes the basis per branch.
- **One state machine drives every control action**, with each transition root-found at its
  exact instant. Python's `main` polls at output times; `stream-next` adds root-finding for the
  trips that supply a margin function.

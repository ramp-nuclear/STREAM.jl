# Feature gaps against Python STREAM

Where STREAM.jl stands against the Python implementation, measured against the goal of
running RIA, LOFA and LOCA transients in light- and heavy-water research reactors with both
MTR plate fuel and cylindrical rod fuel.

Python source read for this: `/home/aviv/work/iaec/codes/STREAM`, 13585 lines across 62
modules. STREAM.jl at the time of writing: 5734 lines across 31 files.

Everything below was checked against both sources rather than inferred from names. Items
marked **not a gap** were checked and found equivalent, so nobody has to re-derive them.

## Contents

- [Scenario readiness](#scenario-readiness)
- [1. Power and heat sources](#1-power-and-heat-sources)
- [2. Fuel heat conduction](#2-fuel-heat-conduction)
- [3. Wall friction and pressure drop](#3-wall-friction-and-pressure-drop)
- [4. Two-phase flow](#4-two-phase-flow)
- [5. Thresholds and post-solve analysis](#5-thresholds-and-post-solve-analysis)
- [6. Power shapes and meshing](#6-power-shapes-and-meshing)
- [7. Solver robustness](#7-solver-robustness)
- [8. Uncertainty quantification](#8-uncertainty-quantification)
- [9. Reporting and debugging](#9-reporting-and-debugging)
- [Where STREAM.jl is ahead](#where-streamjl-is-ahead)
- [Checked and equivalent](#checked-and-equivalent)
- [Suggested order of work](#suggested-order-of-work)

## Scenario readiness

| Scenario | Can Python do it? | Can STREAM.jl do it? | What blocks us |
|---|---|---|---|
| **LOFA** (loss of flow) | Yes | Partly | Decay heat is the main one. The forced-to-natural-circulation transition works in principle but has no passing test (see [7.2](#72-the-loss-of-flow-bypass-case-does-not-converge)) |
| **RIA** (reactivity insertion) | Mostly | Partly | Decay heat matters less here, but cylindrical fuel, gap conductance and fuel-temperature limits are all absent |
| **LOCA** (loss of coolant) | **No** | **No** | Neither code has any two-phase model. This is not a porting job, it is new physics ([4](#4-two-phase-flow)) |

The LOCA row is the one worth internalising. Python STREAM is a single-phase liquid code
with subcooled-boiling *heat transfer enhancement* and a set of threshold correlations that
tell you when you are about to leave its validity. It has no void fraction, no steam, no
quality, no critical flow and no post-CHF heat transfer. Grepping the whole Python tree for
`void`, `quality`, `two_phase`, `choked`, `film_boiling`, `rewet` and `radiation` returns
nothing outside one prose sentence in a docstring. Porting Python faithfully gets us to
feature parity and no closer to LOCA.

---

## 1. Power and heat sources

### 1.1 Decay heat is missing entirely

**Highest priority.** Python has `physical_models/decay_heat/` with four contributions:

| Module | What it gives | Data |
|---|---|---|
| `fission_products.py` | Fission product decay, summed exponential fits | Vendored CSVs: ANS-5.1-1973, ANS-5.1-2014, JAERI-91, for U235, U235-beta, U235-gamma, U238, U238-gamma |
| `actinides.py` | U-239 and Np-239 profiles, from captures per fission | Analytic |
| `activation.py` | Single- and double-decay activation profiles of structural material | Analytic, user supplies λ |
| `fissions.py` | Prompt fission power profile, including `profile_from_pk` driven by a point-kinetics solution | Analytic |

All four share the signature `f(t, T) -> MeV/fission`, where `t` is time after shutdown and
`T` is irradiation time before it. They are consumed through `PointKineticsWInput`, which
splits `pk_power` (prompt) from `power` (total) and adds `power_input` on top.

STREAM.jl has none of this, and no equivalent of `PointKineticsWInput`. Every loss-of-flow
and SCRAM transient we run is missing its dominant post-trip source term. A SCRAM from full
power drops prompt fission to near zero in under a second while decay heat sits at roughly
6-7% of rated power and falls off as a power law over hours. Without it, a LOFA transient
cools down when it should heat up.

**Plan** (unchanged from `CLAUDE.md`): Way-Wigner first as the analytic default, then
user-supplied databases in the same shape Python takes. The CSV standards are vendored data
we can read as-is.

**Size:** medium. The physics is a sum of exponentials; the work is the component that adds
it to a channel's or a plate's power, plus the split between prompt and total power in
`PointKinetics`.

### 1.2 No prompt/total power split in `PointKinetics`

Python's `PointKineticsWInput` adds one algebraic variable so that `power = pk_power +
power_input`. Ours only has the prompt power. Needed before decay heat can be wired in, and
useful on its own for any external heat source (gamma deposition in the reflector, pump
heat).

**Size:** small, once 1.1 defines what `power_input` looks like.

---

## 2. Fuel heat conduction

This is where the "cylindrical and MTR" ambition runs into the most missing code.
`src/components/heat_diffusion.jl` is a single kernel: 2D Cartesian, uniform material,
uniform mesh, no interface resistance, no axial conduction.

### 2.1 No cylindrical geometry

Python's `Fuel` takes a `heat_func` kwarg and ships four kernels:

| Kernel | Geometry |
|---|---|
| `x_diffusion` | 1D Cartesian (plate, lateral only) |
| `xz_diffusion` | 2D Cartesian (plate, lateral and axial) |
| `r_diffusion` | 1D cylindrical (rod, radial only) |
| `rz_diffusion` | 2D cylindrical (rod, radial and axial), azimuthally symmetric |

plus `generic_2d_diffusion` behind them and `cylindrical_areas_volumes` for the radial
metric. We have the equivalent of `x_diffusion` only.

**No cylindrical fuel means no rod-type core.** This is the single largest structural gap
against the stated goal.

**Size:** medium. The radial kernel differs from the Cartesian one by the face areas and
cell volumes, which `cylindrical_areas_volumes` already spells out. The work is refactoring
`_diffusion_eqs` so the metric is a parameter rather than baked in.

### 2.2 No axial conduction

Our bulk equation is

```julia
D(T[i, j]) ~ k_s * (T[i, j+1] - 2*T[i, j] + T[i, j-1]) / (dx^2 * rho_s * cp_s) + q_vol[i, j]
```

Only `j±1` appears. There is no `i±1` term anywhere in `_diffusion_eqs`, so axial slices are
thermally independent and heat cannot spread along the plate. Python's `xz_diffusion` and
`rz_diffusion` both carry it.

For a steady axial cosine this changes little. It matters where an axial gradient is sharp:
the ends of the heated length, a partially inserted control rod, and the leading edge of a
quench front if we ever get there.

**Size:** small. One more difference term and the `z_contacts` faces.

### 2.3 Uniform material only, so no cladding

`HeatDiffusion` takes scalar `rho_s`, `cp_s`, `k_s`. Python's `Solid` has a `from_array`
constructor that produces per-cell arrays of all three, and `Fuel` takes `meat_indices` to
mark which cells are fuel and which are cladding. Together with `x_boundaries(clad_N,
fuel_N, clad_w, meat_w)`, which builds a clad/meat/clad mesh, that is a layered plate.

We cannot represent a clad plate at all. Everything is one material.

**Size:** small to medium. Making the three properties per-cell arrays is mechanical; the
knock-on is that face conductivities need a harmonic mean between neighbouring cells rather
than a shared scalar.

### 2.4 Uniform mesh only

`dx = Lx / nx`, `dz = Lz / nz`. Python takes `x_boundaries` and `z_boundaries` arrays, which
is what lets it put fine cells in the cladding and coarse ones in the meat. Needed by 2.3 to
be useful, and needed on its own for rods, where the radial temperature profile is steepest
at the centre.

**Size:** small, and best done at the same time as 2.3.

### 2.5 No contact or gap conductance

Python's `_resistances(dr, contacts, k)` builds each face resistance as `dr/(2k) + 1/h_contact`,
with `x_contacts` and `z_contacts` supplied per face. That is fuel-to-clad gap conductance.

We have pure conduction between cells and a bare half-cell to the boundary. For plate fuel
with a metallurgical bond, that is defensible. For rod fuel it is not: the pellet-clad gap
usually dominates the whole thermal resistance, and in an RIA the gap closing as the pellet
expands is a first-order effect on peak fuel temperature.

**Size:** small once 2.4 exists, and a prerequisite for taking rod RIA results seriously.

---

## 3. Wall friction and pressure drop

### 3.1 The friction closure could not see the wall (DONE)

Closed. `Friction.AbstractDarcyFactor` in `src/friction/darcy.jl` is now the handle a
channel or a resistor is given:

    darcy(T_bulk, T_wall, ṁ, liquid, pipe) -> f

matching Python's `GeneralDarcyFactor`. The correlations in `friction/correlations.jl` still take a
Reynolds number and nothing else; `Friction.FromReynolds` is the lift, and it applies `k_R`
to the Reynolds it forms at the bulk temperature.

That makes `viscosity_correction` reachable for the first time. `Friction.RegimeDependent`
takes a `viscosity` keyword, defaulting to `nothing` exactly as Python's `k_H` does, so the
correction is opt-in and no existing result moved. With it, the factor is multiplied by
`k_H(heated_perimeter/wet_perimeter, mu(T_wall)/mu(T_bulk))`, which is the first use of the
two perimeters `PipeGeometry` has always carried.

Shipped, all inside the `Friction` module: `FromReynolds`, `FromFunction`, `Blasius`,
`Laminar`, `Turbulent`, `RectangularLaminar`, `RegimeDependent`.

Channels take `darcy` where they took `friction_correlation`. The wall temperature they hand
it is the mean of the two faces, following Python. `ChannelHeatFlux` has no wall of its own,
so it passes the bulk, which makes any viscosity correction exactly 1.

The old `regime_dependent_friction` factory is deleted rather than kept alongside
`Friction.RegimeDependent`, the same call made for `regime_dependent` on the HTC side.
One thing this turned up that the first pass missed. Python factors out not just the friction
correlations but the pressure-drop forms that consume them:
`Darcy_Weisbach_pressure_by_mdot(mdot, rho, f, L, Dh, A)` and
`local_pressure_by_mdot(mdot, rho, f, A)`. We had neither, and the Darcy-Weisbach product was
written longhand in ten places across `src/` and `test/`. Both are now
`Friction.darcy_weisbach_dp` (with a `PipeGeometry` form) and `LocalLoss.dp`, and the source call sites use
them. The remaining longhand copies in tests are deliberate: a test that rebuilds an expected
value with the same helper the source uses cannot catch a wrong helper.

### 3.2 Missing hydraulic components

| Python | What it is | Have it? |
|---|---|---|
| `RegimeDependentFriction` (resistor) | Standalone regime-switching friction resistor | Yes, as `Components.FrictionResistor(; darcy=Friction.RegimeDependent(...))` |
| `ResistorMul` | Scale a resistor's pressure drop | Yes, the `scale` parameter |
| `Inertia.bilinear` | Flow-dependent inertia, `L0·(ṁ/ṁ0)` below a knee | Yes, `bilinear_inertia` |
| `ResistorSum` | Add resistors into one component | No, `inseries` covers the composition |
| `Bend` | Idelchik ch. 6 diagram 6.1 bend loss, angle and relative curvature and Re | No |
| `Screen` | Idelchik p. 598 circular wire mesh screen | No |
| `ResistorFromKnownPoint` | Build a constant/linear/parabolic resistor from one known `(ΔP, ṁ)` point | No |
| `bend_factor` | The bare Idelchik bend correlation | No |

The Idelchik local losses we do have (`expansion`, `contraction`) match.

Three notes on the ones now done.

**Regime-dependent friction is a `Friction` option, not a new component type.** Python needs
a separate class because it has no dispatch story for the friction factor. We do, so
`Friction` takes any `DarcyFactor` and the regime-switching resistor is
`Friction(; geometry, darcy=RegimeDependentFriction(...))`. `Friction` also gained a
`PipeGeometry` form, since the viscosity correction needs the two perimeters that `L`/`D`/`A`
cannot supply; the `L`/`D`/`A` form builds an equivalent circular duct where they coincide.
It had no test coverage at all before this; it does now.

**Scaling is a parameter, not an algebra.** `ResistorMul` wraps a resistor object and
multiplies its `dp_out`. MTK components are systems, not values, so wrapping is the wrong
shape: `scale` is a proper parameter on `Friction`, `Resistor`, `VolumetricFlowResistor` and
`LocalPressureDrop`, which means `remake` reaches it. `scale=3` is three of the resistor in
series, `scale=1/3` is three in parallel, and a calibrated resistor can be trimmed without
touching the coefficient it was fitted with.

**Inertia takes a callable.** `Inertia(L)` accepts either a number or `(ṁ) -> L/A`, with
`bilinear_inertia(L0, ṁ0)` as the standard flow-dependent form. Because it is traced
symbolically the knee is an `ifelse` on `abs(ṁ)`, so a reversal behaves like forward flow.
The callable form carries one extra variable, `L_eff`, for the effective inertia.

**Remaining:** `Bend`, `Screen`, `ResistorFromKnownPoint` and `bend_factor`, all postponed.
Each is small and independent. `ResistorFromKnownPoint` is worth more than its size suggests:
it is how you calibrate a loop against a measured operating point, which is the usual way a
research reactor model gets its form losses.

---

## 4. Two-phase flow

**Neither code has any of it.** Listing what a credible LOCA needs, all of it absent from
both:

- Void fraction and flow quality
- Steam properties and a two-phase mixture density
- Two-phase friction multiplier
- Post-CHF heat transfer: transition boiling, film boiling, the boiling curve past its peak
- Critical (choked) flow at the break
- Coolant level tracking and core uncovery
- Radiation heat transfer from an uncovered surface
- Rewet and quench front propagation
- Metal-water reaction (aluminium for MTR plates, zircaloy for rods)

What both codes do have is the *approach* to the boundary: `SubcooledBoilingHTC` enhances
the single-phase coefficient in partial boiling, and the CHF / OFI / OSV / ONB thresholds in
`thresholds.jl` say how much margin is left. That is enough to say "this transient reaches
CHF at t = 12 s in cell 7". It is not enough to say what happens afterwards.

**Recommendation:** treat LOCA as a separate programme, not as a gap to close. Decide first
whether STREAM.jl should grow a two-phase model at all, or whether LOCA is better handed to
RELAP with STREAM.jl providing the initial conditions. That decision should be made before
any of it is designed, because a homogeneous-equilibrium model would touch the channel's
energy and momentum equations, the connectors, and the property interface.

If it does go ahead, the smallest useful first step is a homogeneous equilibrium model
(HEM): one mixture momentum equation, thermodynamic equilibrium, drift flux neglected. That
gets void and a two-phase multiplier without a second momentum equation.

**Size:** large, and gated on a decision rather than on effort.

---

## 5. Thresholds and post-solve analysis

The correlation inventory matches: CHF (Sudo-Kaminaga, Mirshak, Fabrega), OFI
(Whittle-Forgan), OSV (Saha-Zuber), ONB (Bergles-Rohsenow), boiling power, and the wall
temperature limit are all present and cross-validated.

### 5.1 Missing the plain Saha-Zuber form

Python has both `Saha_Zuber_OSV(T_bulk, coolant, u, Dh)` and
`Saha_Zuber_OSV_computed_bulk(...)`. We have only the computed-bulk one. Python's own
docstring puts a `.. danger::` on the plain form and says you probably want the other, so
this is a completeness item rather than a correctness one.

**Size:** trivial.

### 5.2 No RIA-specific limits

For an MTR plate, the acceptance criteria in an RIA are usually peak cladding temperature,
DNBR, and the fuel blister threshold for aluminide or silicide fuel. We have the first two
through `twall_limit` and `chfr`. Blister temperature is absent, as is any fuel enthalpy
accumulator, and Python has neither.

Fuel enthalpy in cal/g is the standard rod-fuel RIA criterion and would need the cylindrical
kernel from [2.1](#21-no-cylindrical-geometry) to be meaningful.

**Size:** small in itself, but only useful after §2.

### 5.3 `heated_diameter` not carried on the geometry

Python's `EffectivePipe` computes `heated_diameter = 4·area/heated_perimeter`. Ours does
not. Python never reads it either, so this is bookkeeping.

**Size:** trivial.

---

## 6. Power shapes and meshing

Our `cosine_power_shape(nz, nx; amplitude)` samples `cos²` at cell centres, zero at both
ends, uniform mesh, not normalised.

Python's `cosine_shape(x, ppf, xmax)` is more general in four ways that all matter for a hot
channel calculation:

1. Takes arbitrary cell **boundaries**, so it works on a non-uniform mesh
2. **Integrates** the profile over each cell instead of sampling the centre, which conserves
   total power as the mesh coarsens
3. Takes a **power peaking factor**, defaulting to π/2
4. Lets the peak sit **off centre**, for a partially inserted control rod

Plus `cosine_shape_by_zero_endpoints(xi, xe, x)`, the extrapolated cosine with non-zero flux
at the ends, which is what a reflected core actually looks like, and `uniform_x_power_shape`
for the lateral direction across clad and meat.

Since the axial peaking factor sets the hot spot, and the hot spot sets every threshold
margin, this is more load-bearing than it looks.

**Size:** small. Pure functions, no MTK involvement.

---

## 7. Solver robustness

### 7.1 No sign constraints on the solve

Python passes IDA a constraint array built by `create_constraints(agr, default_sign, ...)`,
which can mark any variable `positive`, `non_negative`, `non_positive` or `negative`. It
defaults every variable to `CONSTRAINT.none` and makes each constraint an explicit per-variable
opt-in. The Julia equivalent is `isoutofdomain` on the OrdinaryDiffEq solve, which rejects a
step whose state leaves a user-defined domain. We do not use it anywhere.

**This must never be applied to the mass flow rate.** In a reactor whose normal flow is
downward, a LOFA reverses the heated channel: once the pump stops, buoyancy carries the flow
upward and ṁ genuinely changes sign. That reversal is the result we are trying to compute,
not a numerical artifact, and `test_examples.jl` asserts it directly in the testset named
"channel flow reversal (ṁ crosses zero)". Constraining ṁ would forbid the physics.

The quantities worth constraining are the ones with no physical negative branch: absolute
pressure, heat transfer coefficients, densities, and void fraction bounded to `[0, 1]` if a
two-phase model ever arrives. Temperatures do not qualify while we are in Celsius.

**Size:** small, but narrow in value. Not a priority on its own.

### 7.2 The loss-of-flow bypass case does not converge

Pre-existing, confirmed identical on a clean checkout, and unchanged by the `HTC` work
(3 passed, 7 failed, 2 errored both before and after, same assertions at the same lines).

The failure is **branch selection in the pre-trip steady solve**, not a sign or a friction
problem. The test's own comment states it:

> The system has a second root at ṁ = 0 (flow recirculating through the closed flapper);
> `DynamicSS` lands on whichever root its guess sits nearest.

So the pump-on steady state has two roots, and `DynamicSS(Rodas5P())` relaxes into the trivial
one from the current guess. The transient then has a single time point and every downstream
assertion collapses with a `BoundsError`.

The fix belongs to initialisation, not to the solver's domain handling:

- Seed the guess so it sits in the forced-flow basin. The test already seeds the unknowns
  `mtkcompile` keeps, and its comments record that seeding only the observed aliases was what
  put the latest package set on the ṁ = 0 root. That approach is working but brittle, because
  it depends on which variables survive simplification.
- Better: continuation. Solve with the flapper open or `R_ext` lowered so the trivial root does
  not exist, then walk the parameter back to its real value, using each solution as the next
  guess. This is robust to whatever `mtkcompile` decides to keep.
- Or skip the steady solve entirely and integrate the transient from a driven initial state
  until it settles, which is what the physical startup does anyway.

Because this case fails, the natural-convection heat transfer path has no working in-channel
coverage, which is uncomfortable given that natural circulation is the whole point of the late
phase of a LOFA.

Note that this builder's friction closure changed in the `HTC` work: it now uses
`regime_dependent_friction`, which has a no-flow guard the previous inline blend lacked. That
changed nothing here, which is itself informative: the no-flow guard was not what held the case
back.

---

## 8. Uncertainty quantification

Python has `analysis/UQ/` with:

- `UQModel`, finite-difference Jacobians of solution values against input parameters, with a
  configurable perturbation step strategy
- `DASKUQModel`, the same thing distributed
- `Uncertainty`, propagation and combination of uncertainties
- `local_power_shift`, a purpose-built power-shape perturbation

We have nothing. Our `@design_knob` machinery is the closest thing, and it solves the
adjacent problem of re-solving under a changed design parameter rather than propagating an
uncertainty.

Worth noting that Julia has a better answer available than finite differences:
SciMLSensitivity gives forward and adjoint sensitivities of an ODE/DAE solution with respect
to parameters, at a fraction of the cost and without step-size tuning. If UQ becomes a
requirement, that is the route, not a port.

**Size:** medium, and probably a different design from Python's.

---

## 9. Reporting and debugging

| Python | What it does | Have it? |
|---|---|---|
| `analysis/report.py` | Markdown and `rich` tables of every calculation's variables, flagging unset, missing and externally-set parameters | No |
| `analysis/debugging.py` | `debug_derivatives`, `debug_guess_variables`, `debug_guess_flows` for inspecting a bad initial guess | No |
| `Aggregator.draw` | Draws the calculation graph | No |

MTK covers part of this differently: `unknowns`, `observed`, `equations` and
`ModelingToolkit.check_consistency` give a lot of the same information, and our
`test_determinacy.jl` already asserts equation and unknown balance for every builder. The
gap that remains is the ergonomics of debugging a failed initialisation, which is currently
the hardest thing to do in this codebase.

**Size:** small, high value per line.

---

## Where STREAM.jl is ahead

Listing these so the report is not read as one-directional.

- **Acausal composition.** Python hand-builds a flow graph, then a Kirchhoff calculation with
  explicit KVL and KCL matrices (`build_kvl_matrix`, `build_kcl_matrix`, `kirchhoffify`,
  `Junction`, `maximally_coupled`), roughly 800 lines of graph machinery. MTK's `connect`
  does this structurally. Our `inseries` / `inparallel` / `compose_systems` are thin by
  comparison because the compiler carries the weight.
- **Symbolic Jacobians and index reduction.** Python has a hand-written `jacobians.py` and a
  `mass_vector` per calculation. `mtkcompile` derives both.
- **Design knobs.** `@design_knob` and `knob_defaults` let a geometric dimension stay
  symbolic through the whole model so it can be changed by `remake` without rebuilding.
  Python has no equivalent.
- **The liquid interface.** `AbstractLiquid` with the nine properties, the `Liquid` snapshot,
  the unicode aliases and the call-operator form `H2O(T, p)` is more ergonomic than Python's
  `LiquidFuncs` dataclass of callables, and dispatches on coolant type.
- **The `HTC` handle.** After the current work, our heat transfer model is a first-class
  value with an explicit property basis. Python's is a function with the basis hard-coded per
  branch.
- **Transient threshold analysis is native.** `ChannelState` handles a transient solution by
  turning every per-cell field into a `[cell, time]` matrix, so every threshold correlation
  works on a transient with no extra code. Python needs a separate
  `transient_threshold_analysis` wrapper.
- **Event handling.** SciML callbacks give us SCRAM and flapper events with proper root
  finding. Python's `should_continue` / `change_state` polling is coarser.

## Checked and equivalent

Verified as matching, so they should not be re-investigated:

- **Dimensionless numbers.** Re, Re_mdot, Pr, Nu, Pe, Gr, Ra, and the regime blend all match.
- **Nusselt correlations.** Dittus-Boelter, Marco-Han, two-sided heating, Elenbaas, the
  fully-developed and developing laminar forms, and the maximal combinator all match. Python
  defaults to the same analytic developing-laminar approximation and uses its Shah and London
  table only to bound that approximation's error.
- **Friction correlations.** Laminar, turbulent (Colebrook-White), Blasius, the rectangular
  laminar correction and the regime blend all match.
- **Idelchik expansion and contraction losses.** Table nodes and high-Re limits match.
- **The liquid property correlations.** H2O and D2O, all nine properties, cross-validated
  against Python to the tolerances in `test_validation.jl`.
- **The wall temperature interface.** Python computes it explicitly as
  `wall_temperature(T_cool, T_clad, h_cool, h_clad)`. Our acausal `ThermalPort` connection
  gives `h_cool·(T_w − T_cool) = k/(dx/2)·(T₁ − T_w)`, whose solution is the same expression
  with `h_clad = k/(dx/2)`. Equivalent, derived rather than coded.
- **Buoyancy-driven natural circulation.** Our per-cell momentum equation carries
  `ρ(T[i])·g·dz` with the local density, so a density difference around a loop drives flow.
  No separate model is needed.
- **Channel variants.** `Channel`, `ChannelHeatFlux` and `ChannelAndContacts` map one to one
  onto Python's.
- **Pump modes.** Both constrain either Δp or ṁ, both accept a time-dependent value, neither
  has a pump curve or a torque balance.
- **Threshold correlations.** Listed in [5](#5-thresholds-and-post-solve-analysis).
- **Geometry.** `PipeGeometry` matches `EffectivePipe` field for field except
  `heated_diameter`, which Python computes and never uses.

## Suggested order of work

Ordered by what unblocks the most, not by size.

1. **Decay heat** (§1.1, §1.2). Without it no LOFA or SCRAM result is meaningful. Way-Wigner
   first, then the vendored standards.
2. ~~**Friction as a `DarcyFactor`** (§3.1)~~ done, along with resistor scaling, the
   regime-dependent friction resistor and flow-dependent inertia (§3.2).
3. **Branch selection in the loss-of-flow steady solve** (§7.2), by continuation rather than
   by constraining anything. Retiring it restores coverage of the natural-convection path,
   which nothing else exercises in a channel.
4. **Heat conduction rework** (§2.1 to §2.5) as one piece: non-uniform mesh, per-cell
   material, contact conductance, axial conduction, and the cylindrical metric. Doing these
   separately means touching `_diffusion_eqs` five times. This is what opens rod fuel.
5. **Power shapes** (§6). Small, and it directly affects every hot-channel margin.
6. **Missing hydraulic components** (§3.2), `ResistorFromKnownPoint` and `Bend` first.
7. **Debugging ergonomics** (§9). High value per line, and the pain is felt on every failed
   initialisation.
8. **RIA limits** (§5.2), after §2 and §4 are settled.
9. **UQ** (§8), if it becomes a requirement, via SciMLSensitivity rather than a port.
10. **Two-phase** (§4), gated on the scope decision, not on effort.

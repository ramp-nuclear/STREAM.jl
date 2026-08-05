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
- [4. LOCA: level tracking, and where it stops](#4-loca-level-tracking-and-where-it-stops)
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
| **RIA** (reactivity insertion) | Mostly | Partly | Decay heat matters less here. Cylindrical fuel and gap conductance are done (§2); fuel-temperature limits are still absent |
| **LOCA**, level tracking to uncovery | **No** | Partly | Needs coolant inventory, a free surface and break flow. No two-phase model required ([4](#4-loca-level-tracking-and-where-it-stops)) |
| **LOCA**, past uncovery | **No** | **No** | Void, steam, post-CHF heat transfer. Out of scope for both, by choice |

The LOCA split is the one worth internalising. Both codes are single-phase liquid with
subcooled-boiling *heat transfer enhancement* and thresholds that report margin. That is
enough to track a level down to core uncovery and say when the model leaves its own validity,
which is the goal here. It is not enough to say what happens after, and neither code tries:
grepping the whole Python tree for `void`, `quality`, `two_phase`, `choked`, `film_boiling`,
`rewet` and `radiation` returns nothing outside one prose sentence in a docstring.

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

## 2. Fuel heat conduction (DONE)

Closed. `src/components/heat_diffusion.jl` no longer carries a stencil; it states one
equation per cell by walking a mesh's face lists, so the geometry is data rather than code.
The physics module is `src/solids/`.

A mesh is a 2D cross-section swept along z. The conduction is fully 3D: cells are
`(cross-section cell, axial layer)` pairs, with in-plane faces inside a layer and axial
faces between layers. What is 2D is only that the geometry repeats at every z-level, so it
is meshed once.

Three generators fill the same `CrossSection`:

| Generator | Shape | Exact? |
|---|---|---|
| `slab_cross_section` | flat plate, the pre-mesh case | yes |
| `ogrid_cross_section` | body-fitted ring between a bore and an outer wall | exact on a concentric annulus |
| `cut_cell_cross_section` | anything composed from rectangles and circles | exact on axis-aligned geometry |

What this closed, against the old list:

- **2.1 cylindrical geometry.** `ogrid_cross_section` on a concentric annulus is exactly
  orthogonal, so the scheme is exact there rather than approximate. This is not Python's
  approach, which keeps a Cartesian `Δr/2k` resistance and puts the curvature in the face
  areas; real face areas and real distances make that unnecessary.
- **2.2 axial conduction.** `extrude(...; axial=true)` adds faces between layers. Off by
  default on the keyword `HeatDiffusion` so no existing result moved, on by default on the
  mesh constructor.
- **2.3 per-cell material.** The mesh carries a material index per cell and a
  `Vector{SolidMaterial}` alongside, so a clad plate is two materials and an index vector.
  Face resistance uses each cell's own `k`.
- **2.4 non-uniform mesh.** Every generator takes boundaries or fractions rather than
  counts, so cells can be packed against a wall and a material interface placed exactly on
  a face.
- **2.5 contact and gap conductance.** Every face carries `r_contact` in m²K/W, defaulting
  to zero. `set_contact!` places it by a predicate over the two cells a face separates.
  Resistance is stored rather than conductance deliberately: perfect contact is `0`, not
  `Inf`, and an `Inf` reaching a symbolic trace poisons the expression.

### 2.6 Two-point flux is only exact on an orthogonal mesh

Worth stating because it bounds everything above. The scheme assumes the line joining two
cell centroids is parallel to the face normal between them. Where that holds it is exact;
where it does not, the dropped cross-diffusion term does not vanish under refinement, so
the error is a property of the mesh rather than of its resolution.

Measured with `mesh_skew` and `linear_patch_error`, on a 12 mm rod with a 3 mm bore:

| Mesh | Skew mean | Patch p95 |
|---|---|---|
| Slab | 0° | 6e-16 |
| O-grid, concentric annulus | 0° | 7e-15 |
| Cut-cell, axis-aligned rectangle | 0° | 2e-16 |
| Cut-cell, bored square | 1.1° | 2.3e-2 |
| O-grid, bored square | 7.7° | 8.1e-2 |

The two shapes this project centres on, flat plates and cylindrical rods, are both exact.
A circular bore inside a *square* is the case that carries error, on either mesh, because
no conformal map from a circle to a square exists away from its corners. Refinement does
not help: mean skew held at 7.7° from 128 cells to 1024.

Open, if it turns out to matter: a non-orthogonal correction term on the existing face
list, or an orthogonality-enforcing grid generator. Neither is worth building before the
error is shown to move a peak temperature.

### 2.7 Wall temperature is averaged per tag, by construction

Boundary faces group by tag, one thermal port per `(tag, axial layer)`, and the port's heat
flow is the sum over its group. That reduction is what lets a boundary of any shape meet a
1D channel. It also means in-plane refinement buys interior detail and not peak-wall
detail: the model reports a face-averaged wall temperature per tag, because the channel it
talks to carries one bulk temperature per axial cell. That bounds what the §5 threshold
margins mean on a rod.

### 2.8 What a mesh costs, conduction alone

Measured on the bored-square rod, all five faces pinned, `Rodas5P`, dense Jacobian:

| Cells | `mtkcompile` | `ODEProblem` | first solve |
|---|---|---|---|
| 1600 | 2.7 s | 41 s | 48 s |
| 2880 | 4.8 s | 93 s | 124 s |
| 5760 | 12 s | 399 s | 496 s |

The result inverts the worry that shaped the design. **`mtkcompile` is not the problem**: it
stays under 12 s at 5760 cells and scales close to linearly, because every `T` is a
differential state with no algebraic coupling to another `T`, so there is nothing to tear.
The cost is in `ODEProblem` construction and the solve, both growing near quadratically.

That points at code generation for the right-hand side and a dense N×N factorization per
Newton step, neither of which the mesh design can fix.

The obvious lever, a sparse symbolic Jacobian, turned out not to be one. At 960 cells,
`ODEProblem(...; jac=true)` had not finished after twenty minutes, against 46 s to build the
same problem without it: generating the Jacobian symbolically costs more than it saves at
this size. Two routes are left, neither tried yet. Supply a sparsity pattern and let the
solver form the Jacobian numerically by coloured finite differences, which needs no symbolic
work and suits a stencil with at most six neighbours per cell. Or drop the Jacobian entirely
and use a Krylov linear solver, which never forms the matrix. Both are cheap experiments and
neither has been run, so nothing here should be taken as measured.

Practical sizing until that lands: 1600 cells is about 90 s end to end and fine to iterate
on; 5760 cells is roughly 15 minutes and belongs in a production run, not a loop.

### 2.9 What a coupled model costs, which is a different answer

The numbers above are conduction on its own, with the walls pinned. Wire channels to it and
the bottleneck moves. Measured on the five-channel rod, 820 equations, both cases solved
back to back in one session:

| Step | First case | Second case |
|---|---|---|
| mesh generation | 1.2 s | reused |
| build components | 17.6 s | 0.4 s |
| `mtkcompile` | 24.6 s | 1.0 s |
| steady solve | 322 s | 305 s |
| `write_vtk` | 0.4 s | reused |

Building and compiling fall by a factor of thirty on the second pass, so that really is
just Julia warming up. The steady solve does not, 322 s against 305 s, because it is
numerical work rather than compilation. Between them the two solves are 93% of an
eleven-minute run, on a system of only 820 equations.

So the levers §2.8 points at, sparse Jacobians and right-hand-side code generation, are the
wrong ones for a coupled model. Coupling makes the steady state nonlinear, and integrating
to it through the heat transfer and friction correlations is the cost. Nothing about the
mesh or `mtkcompile` will move it.

Untried, in the order worth trying: a better initial guess than a flat temperature, since
`steady_state_guess` already exists and was not used here; solving the channels' hydraulics
first and handing the conduction a converged flow field; and a proper nonlinear steady
solver rather than integrating a transient to rest, which is what `DynamicSS` does.

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

## 4. LOCA: level tracking, and where it stops

The goal here is narrower than "run a LOCA": predict **water level** through a drain, up to
the point where more involved computations take over. That is a different and much smaller
problem than two-phase thermal-hydraulics, and it is worth stating the boundary precisely,
because the two get conflated.

### What the narrow goal needs

| Piece | Have it? |
|---|---|
| Coolant inventory as a state, and a level derived from it | No |
| A component with a free surface (pool, plenum, standpipe) | No |
| Break flow out of the system, as a specified rate or an orifice | No |
| An event that fires when the level reaches a named elevation | No, but `SCRAMCondition` and the flapper callbacks are the pattern to copy |
| Decay heat, to know the load while it drains | No, see [1.1](#11-decay-heat-is-missing-entirely) |
| Natural circulation while still covered | Yes |
| Margin to boiling on the way down | Yes, the CHF / OFI / OSV / ONB thresholds |

None of that requires void fraction, steam properties or a two-phase momentum equation. A
draining single-phase pool with a moving free surface is an inventory balance plus a
geometric level, and the existing acausal connectors already carry the mass flow it needs.

**Size:** medium, and mostly new components rather than new physics. The one real modelling
decision is whether break flow is user-supplied (a boundary condition, which is enough for a
specified-leak study) or computed from an orifice, which brings in choked flow once the
break is large.

### Where it stops

The handoff is core uncovery. Once liquid level drops below the top of the heated length the
single-phase assumption stops holding, and everything in this list starts to matter:

- Void fraction and flow quality
- Steam properties and a two-phase mixture density
- Two-phase friction multiplier
- Post-CHF heat transfer: transition boiling, film boiling, the boiling curve past its peak
- Radiation from an uncovered surface
- Rewet and quench front propagation
- Metal-water reaction (aluminium for MTR plates, zircaloy for rods)

**Neither STREAM.jl nor Python STREAM has any of it**, and neither should grow it casually.
Grepping the whole Python tree for `void`, `quality`, `two_phase`, `choked`, `film_boiling`,
`rewet` and `radiation` returns nothing outside one prose sentence.

So the deliverable is a level history plus the time and elevation at which the model declares
itself out of validity, with the thresholds reporting margin along the way. That is a useful
answer on its own, and it is the right input to hand to a code that does the rest.

**Recommendation:** build the level tracking, and make the uncovery point an explicit,
tested boundary rather than something a user discovers by getting nonsense out. Do not start
a two-phase model to reach it.

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
4. ~~**Heat conduction rework** (§2.1 to §2.5)~~ done, as one mesh-based piece. Rod fuel is
   open now; see §2.6 for the one accuracy caveat that remains.
5. **Power shapes** (§6). Small, and it directly affects every hot-channel margin.
6. **Missing hydraulic components** (§3.2), `ResistorFromKnownPoint` and `Bend` first.
7. **Debugging ergonomics** (§9). High value per line, and the pain is felt on every failed
   initialisation.
8. **RIA limits** (§5.2), after §2 and §4 are settled.
9. **UQ** (§8), if it becomes a requirement, via SciMLSensitivity rather than a port.
10. **Level tracking to uncovery** (§4), once decay heat exists to drive it.

# Feature gaps against Python STREAM

Where STREAM.jl stands against the Python implementation, measured against the goal of
running RIA, LOFA and LOCA transients in light- and heavy-water research reactors with both
MTR plate fuel and cylindrical rod fuel.

Transients are not the whole measure. Steady-state analysis is what the code is asked for most
days, so four questions about it are tracked here as well:

- **Centerline temperature.** For plate fuel yes: `HeatDiffusion` resolves through the
  thickness, so the mid-plane value falls out of the solution. For rod fuel no, there is no
  cylindrical metric ([2.1](#21-no-cylindrical-geometry)).
- **Margins.** Given the same physical model, do we get the same CHF, OFI, OSV and ONB
  numbers? Yes for the correlations both codes carry, cross-validated. The plain Saha-Zuber
  form and the RIA-specific limits are the ones missing ([5](#5-thresholds-and-post-solve-analysis)).
- **Component support.** Nearly the same hydraulic inventory; four small Idelchik-style
  elements are outstanding ([3](#3-wall-friction-and-pressure-drop)).
- **UQ.** No ([8](#8-uncertainty-quantification)).

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
| **LOFA** (loss of flow) | Yes, one channel type | Partly | Decay heat is the main one. The forced-to-natural-circulation transition runs end to end, with one stale reference number in its test (see [7.2](#72-one-stale-number-in-the-loss-of-flow-bypass-case)) |
| **RIA** (reactivity insertion) | Yes | Partly | Decay heat matters less here, but cylindrical fuel, gap conductance and fuel-temperature limits are all absent |
| **LOCA**, level tracking to uncovery | **No** | Partly | Needs coolant inventory, a free surface and break flow. No two-phase model required ([4](#4-loca-level-tracking-and-where-it-stops)) |
| **LOCA**, past uncovery | **No** | **No** | Void, steam, post-CHF heat transfer. Out of scope for both, by choice |

The LOFA cell is qualified because that is where Python's reach ends. Loops with a single
channel type are solid; the cases with different channels in parallel are where it got stuck.
That limit is the implementation's, not the physics'.

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

### 3.1 Missing hydraulic components

| Python | What it is | Have it? |
|---|---|---|
| `RegimeDependentFriction` (resistor) | Standalone regime-switching friction resistor | Yes, as `Components.FrictionResistor(; darcy=Friction.RegimeDependent(...))` |
| `ResistorMul` | Scale a resistor's pressure drop | No, and deliberately |
| `Inertia.bilinear` | Flow-dependent inertia, `L0·(ṁ/ṁ0)` below a knee | Yes, `bilinear_inertia` |
| `ResistorSum` | Add resistors into one component | No, `inseries` covers the composition |
| `Bend` | Idelchik ch. 6 diagram 6.1 bend loss, angle and relative curvature and Re | No |
| `Screen` | Idelchik p. 598 circular wire mesh screen | No |
| `ResistorFromKnownPoint` | Build a constant/linear/parabolic resistor from one known `(ΔP, ṁ)` point | No |
| `bend_factor` | The bare Idelchik bend correlation | No |

The Idelchik local losses we do have (`expansion`, `contraction`) match.

Three notes on the decisions behind that table.

**Regime-dependent friction is a friction model, not a new component type.** Python needs a
separate class because it has no dispatch story for the friction factor. We do, so
`Components.FrictionResistor` takes any `AbstractDarcyFactor` and the regime-switching
resistor is `FrictionResistor(; geometry, darcy=Friction.RegimeDependent(...))`. The component
takes a `PipeGeometry` rather than loose `L`/`D`/`A`, because the viscosity correction needs
the heated and wetted perimeters that `L`/`D`/`A` cannot supply. It had no test coverage at all
before this; it does now.

**Scaling is composition, not a parameter.** `ResistorMul` wraps a resistor and multiplies its
`dp_out`. A `scale` parameter on each resistor was tried here and taken back out: MTK
components are systems rather than values, and three identical resistors through `inseries`
already are three times the resistance, with no second knob to keep consistent with the first.
`test/test_darcy.jl` asserts exactly that, that three 2·10⁴ resistors in series give the same
flow as one 6·10⁴ resistor. Trimming a calibrated resistor means changing its own coefficient,
which `remake` reaches like any other parameter: `remake(prob; p=[ssys.r1.R => 6.0e4])`.

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

### 7.2 One stale number in the loss-of-flow bypass case

This entry used to say the case did not converge. It does now. `test_examples.jl` runs the
bypass loss-of-flow transient end to end: the pre-trip steady solve reaches the forced-flow
root, the flapper fires at its threshold, the heated channel reverses, energy conservation
holds on the coolant control volume, and the settled natural-circulation flow matches an
independent buoyancy-against-friction balance. Twenty of the twenty-one assertions pass. The
natural-convection heat transfer path therefore does have working in-channel coverage, which
an earlier version of this file denied.

What is left is one hard-coded number. The `channel flow reversal (ṁ crosses zero)` testset
brackets the settled recirculation at 4.21 g/s with an absolute tolerance of 0.05 g/s, on the
stated grounds that it reproduced at 4.207 g/s on two different package sets. It now settles at
4.349 g/s, 3.3% away, so the bracket misses. The momentum-balance testset beside it derives the
same equilibrium from buoyancy against friction rather than from a stored value, and it passes,
which points at the bracket as the stale side rather than the physics. Worth confirming before
anyone widens it: the candidates for what moved the root are the `HTC` work, the switch of the
friction closure to `Friction.RegimeDependent`, and the package set itself.

The expensive part is not the assertion. `runtests.jl` aborts at the first failing file, so a
full-suite run stops inside `test_examples.jl` and never reaches `test_validation.jl`,
`test_integration.jl` or `test_point_kinetics.jl`. All three pass when run directly, so nothing
is broken behind that wall, but the Python-parity suite does not run at all in a plain
`julia --project=. test/runtests.jl` until this one number is settled.

The fix worth making while in there is to derive the bracket from the buoyancy-against-friction
balance the neighbouring test already computes, instead of storing a number that has to be
re-measured every time a closure changes.

Two things about this case remain true and are worth keeping written down. The pump-on steady
state has two roots, the forced-flow one and the trivial one at ṁ = 0 where the friction and
buoyancy drops both vanish and every equation balances. `_lof_bypass_ic` in
`test/test_examples.jl` reaches the forced-flow root by holding the pump head at its pre-trip
value with the flapper latched closed, then integrating from there while the head ramps down.
And the way it seeds that solve, a hand-written map naming `heated.ch.inlet.ṁ`, its dummy
derivative, `ext_res.inlet.ṁ` and `ine.outlet.p`, depends on which variables survived
`mtkcompile`, so it will need revisiting whenever simplification changes. Continuation on the
pump head or on `R_ext` would take the guess from a previous solve instead of from naming
variables. Python STREAM has the same two roots, so this is a property of the model rather than
of MTK.


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

To be precise about what that buys, since it decides whether it is usable for a regulatory
submission: those are **local, first-order** sensitivities, the derivative of a solution value
with respect to a parameter at one operating point, obtained from AD-generated Jacobians rather
than from a perturbation step. That is exactly the input a first-order uncertainty propagation
needs, and it is more accurate than Python's finite differences because there is no step size
to choose. It is not a global method: for variance attribution over a parameter range, that
takes sampling on top, which is what `GlobalSensitivity.jl` is for.

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

Drawing the model is the other half, and it earns its keep twice: as documentation of what a
builder actually wired, and as the fastest way to see a miswired connection. Three routes
exist, none of which is work from scratch. Versions below are read off the packages, not from
an install into this project.

- `ModelingToolkitDesigner.jl` (bradcarman, v1.4.0) is the direct replacement for
  `Aggregator.draw`. It lays out an acausal MTK system as a connection diagram on a Makie
  canvas, lets you drag the components, and saves the layout next to the model as TOML so the
  picture survives a rebuild. Its `Project.toml` pins `ModelingToolkit = "8,9"` and the repo
  was last touched in April 2025, so against our 11.26.8 it needs a compat bump upstream or a
  fork. That is a version bound, not a design problem, which makes it the cheapest of the
  three.
- `Latexify.jl` over `equations(sys)` or `full_equations(ssys)` renders the equation system
  itself. That covers the reporting half of `analysis/report.py` and needs nothing built.
- `Graphs.jl` with `GraphMakie.jl` or `GraphPlot.jl`, one node per subsystem and one edge per
  `connect`, built from the connection vectors `inseries`, `inparallel` and `Connect.face`
  already return. Graphs is in the manifest transitively. Note that MTK 11 no longer ships the
  `asgraph` and `eqeq_dependencies` helpers that 8 and 9 had, so the incidence-graph route
  costs more than it used to; the component graph never needed them.

**Size:** small, high value per line.

---

## Where STREAM.jl is ahead

Everything above is what we are missing. This section is the other column: what the rewrite
already buys that the Python code cannot, so that a decision about where to spend the next
month has both sides of the ledger in front of it.

- **Acausal composition.** Python hand-builds a flow graph, then a Kirchhoff calculation with
  explicit KVL and KCL matrices (`build_kvl_matrix`, `build_kcl_matrix`, `kirchhoffify`,
  `Junction`, `maximally_coupled`), roughly 800 lines of graph machinery. MTK's `connect`
  does this structurally. Our `inseries` / `inparallel` / `compose_systems` are thin by
  comparison because the compiler carries the weight.
- **Symbolic Jacobians and index reduction.** Python has a hand-written `jacobians.py` and a
  `mass_vector` per calculation. `mtkcompile` derives both, and it also lowers the index, tears
  the algebraic loops and hands the integrator a sparsity pattern. The machine therefore does
  less work per step on the same problem, and the saving grows with the model rather than
  staying flat.
- **The equation system can be read at any point.** `equations`, `unknowns`, `observed` and
  `full_equations` print what is actually being solved, before and after simplification, with
  no instrumentation. Python's `analysis/report.py` exists because that information had to be
  assembled by hand.
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
- **Less code for the same physics.** The two line counts at the top of this file are not a
  fair comparison everywhere, but they are in the parts that overlap. Composition, the
  Jacobians and the property interface are each a few hundred lines here against a few thousand
  there, because the compiler and the type system carry them.

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
2. ~~**Friction as a `DarcyFactor`**~~ done, along with the regime-dependent friction
   resistor and flow-dependent inertia (§3.1).
3. **The stale natural-circulation bracket** (§7.2). One assertion, and it is what stops a
   full-suite run from ever reaching the Python-parity files. Derive the bracket from the
   momentum balance instead of storing a measured number.
4. **Heat conduction rework** (§2.1 to §2.5) as one piece: non-uniform mesh, per-cell
   material, contact conductance, axial conduction, and the cylindrical metric. Doing these
   separately means touching `_diffusion_eqs` five times. This is what opens rod fuel.
5. **Power shapes** (§6). Small, and it directly affects every hot-channel margin.
6. **Missing hydraulic components** (§3.1), `ResistorFromKnownPoint` and `Bend` first.
7. **Debugging ergonomics** (§9). High value per line, and the pain is felt on every failed
   initialisation.
8. **RIA limits** (§5.2), after §2 and §4 are settled.
9. **UQ** (§8), if it becomes a requirement, via SciMLSensitivity rather than a port.
10. **Level tracking to uncovery** (§4), once decay heat exists to drive it.

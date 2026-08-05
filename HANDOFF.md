# Picking up the mesh work

State of the `HeatMeshes` branch, written so the next session does not have to re-derive
any of it. Delete this file when the two open items below are closed.

## What is done

Solid conduction runs on a mesh instead of a stencil. `src/solids/` is the physics module,
`HeatDiffusion` is the component, and the whole of GAPS.md §2.1 to §2.5 is closed. The
detail is in GAPS.md §2; this file is only the parts that are not obvious from the code.

Two example scripts double as the API tour:

- `examples/conduction_meshes.jl` — four solids on three generators against closed forms
- `examples/rod_3d.jl` — the five-channel rod, 3D power, coupled solve, layer plots

## The two things worth working on next

Both are yours from the last session, in your words: better meshing, faster solves.

### Faster solves

The bottleneck is not where §2.8 says. That section measures conduction alone, where
problem construction dominates. §2.9 measures the coupled rod, where the **steady solve is
93% of the runtime and does not improve on a warm session** (322 s then 305 s). Coupling
five channels makes the steady state nonlinear and `DynamicSS` integrates a transient to
rest through the heat transfer and friction correlations.

Cheapest things to try first, none of them attempted:

1. `steady_state_guess` in `src/initial_conditions.jl` already exists and the rod scripts do
   not use it. They hand the solver a flat 60 °C. That is the first thing to fix.
2. Solve the hydraulics first and give the conduction a converged flow field, rather than
   letting both relax together.
3. A real nonlinear solve rather than integrating to rest. `solve_steady` passes
   `solver=nothing` and lets SciML pick.

Do not spend effort on sparse Jacobians or code generation for coupled models. Measured: at
820 equations `mtkcompile` is 1 s warm and the solve is 305 s.

### Better meshing

Three known limits, in the order they bite.

**Two-point flux is only exact on an orthogonal mesh.** Slabs and concentric annuli are
exact and measured so (patch error 1e-15). A bore inside a *square* is not, on either
generator, and the two disagree by 4.8% on peak temperature. GAPS.md §2.6 has the numbers.

I twice claimed refinement would not close that gap and twice failed to show it. The first
study confounded the mesh resolution with the bore polygon, since `n_angular` sets both. The
second stalled every solve because the test material had `rho = cp = 1`, making the residual
unreachable at `abstol=1e-8`. The third, with `n_angular` pinned and realistic properties,
got two clean rows before it was dropped as not worth the time: 1.79083 K at 384 cells and
1.79570 K at 768, a 0.27% shift. **That looks like convergence, not the inconsistency I
asserted.** Treat my claim as unproven. If it matters, refine `n_radial` only, pin
`n_angular`, use realistic `rho*cp`, and check `successful_retcode` on every solve.

**The O-grid is not boundary-orthogonal.** `_smooth!` is Winslow smoothing, which optimizes
grid smoothness and improves orthogonality only as a side effect. It halves the skew against
a raw algebraic blend and stops there. Making grid lines meet the wall at 90° needs boundary
nodes that slide along the wall. A conformal map from an annulus to a bored square does
exist and would be orthogonal everywhere except at the four corners, where the boundary has
two normals; the corners are an unavoidable singularity, the rest is not.

**A solid rod has no generator.** The O-grid is a ring topology and needs a bore to wrap.
Cut cells cover it and converge at close to second order, but a butterfly topology would be
better.

## Traps that cost time last session

- **`Meshes` exports `connect` and `faces`.** A blanket `using Meshes` shadows
  ModelingToolkit's `connect` and `Assemblies.faces`, and the error surfaces in an unrelated
  test file much later. Import explicitly, or `import Meshes` and qualify.
- **`runtests.jl` aborts on the first failing file.** `test_examples.jl` fails on the
  pre-existing loss-of-flow bypass case (GAPS.md §7.2, "3 passed, 7 failed, 2 errored"), so
  everything after it never runs, including `test_validation.jl`. Run those four
  individually or the suite tells you less than it appears to.
- **A failed steady solve returns the initial guess.** It reads as a plausible number. Check
  `SciMLBase.successful_retcode(sol.retcode)`.
- **Residual scaling matters.** `rho*cp*V` sets the scale of `dT/dt`. With unit properties
  and millimetre cells the residual is ~1e7 times the flux and `abstol=1e-8` is unreachable.
- **`n_angular` on a box must let every corner be a point.** Fixed now, and tested, but the
  symptom was silent: the domain shrank 5.9% and four identical channels drew different
  duty. Any per-tag asymmetry that should not be there is worth chasing.

## Conventions this work established

- Both mesh generators fill the same `CrossSection`, so swapping them is one function call
  and nothing downstream changes. Keep it that way.
- Contact resistance is stored, never conductance: perfect contact is `0`, not `Inf`, so it
  survives a symbolic trace on the design-knob path.
- Boundary faces group by tag into one port per `(tag, axial layer)`. That reduction is the
  whole reason an arbitrary boundary can meet a 1D channel.
- `mesh_skew` and `linear_patch_error` are the mesh-quality diagnostics. Both read zero
  where the scheme is exact, so they are worth running on any new generator.

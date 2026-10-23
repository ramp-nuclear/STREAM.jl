# STREAM.jl: Claude Code Instructions

## Purpose

This project aims to replace eventually the Python STREAM implementation
and should be compared against it, especially for physics and features.
The Python implementation can be found at [here](https://github.com/ramp-nuclear/STREAM),
or locally in a nearby folder.

## Coding Rules

When writing or editing Julia code, follow the conventions in `JULIA.md`:

@JULIA.md

**Use the MTK skill.** Before writing or editing any ModelingToolkit code (`System`,
`mtkcompile`, `@variables`/`@parameters`/`@connector`, `connect`, problem and solution
construction, initialization, callbacks, or any SciML solve), invoke the `modelingtoolkit-jl`
skill if it is installed and read the relevant `references/*.md`. Training data for MTK
predates v11 and emits removed APIs, so without the skill, check a name against the installed
version before using it. The skill takes precedence on MTK API; `JULIA.md` governs general
Julia.

Prose (comments, docstrings, test names, commit messages, `.md` files) is plain and specific:
no filler, no promotional tone, no em dashes.

File level and module level comments should preferably be part of docstrings (`"""`)
explaining the code rather than large block (`#`) comments.
**Docstrings do not describe development processes and thoughts, and do not defend coding
choices. They are succinct descriptions of what the code does and its intended use.**

- **Module-level prose lives on the module**, in `src/STREAM.jl`. Each module's docstring says
  what kind of thing belongs there and names the main entry points.
- **No file carries a `# filename.jl -- what it holds` banner.** What a file holds is either
  obvious from its name or belongs in its module's docstring.
- **Prose about one entity goes in that entity's docstring**, including private ones.
  `_state_snapshot`, `_rebin_1d`, `_conduction` and `_bergles_rohsenow_dT_ONB` all have
  docstrings: a `#` block listing arguments and behaviour is a docstring in the wrong syntax.
- **`#` comments stay for local rationale**: why this seed value, why `ifelse` here, which
  Python line an expression mirrors. What a reader needs at that line and nowhere else. This is
  where a justification goes when one is worth keeping at all.
- **Do not repeat a docstring in a comment beside the code.** If both exist, delete the comment.

Docstrings are reference documentation, so write them to be read rendered rather than in the
file: give exported names `# Arguments` and `# Returns`, and cross-reference with
`[`name`](@ref)`.

- **Equations are math blocks in plain TeX**, `T_{ONB} = T_{sat} + 0.556 (q / (1082 p^{1.156}))`:
  KaTeX renders them in the docs, and they still read as source in the REPL. Prefer `/` to
  `\frac`, Unicode Greek to `\alpha`, and `T_{sat}` to `T_\text{sat}`. A docstring holding
  TeX is a raw string, `@doc raw"""`, since `\` is an escape in a plain one.
- **Cite sources with `[Key](@cite)`**, keys in `docs/src/refs.bib`. Every correlation names
  the paper or report it comes from.
- **Pure functions carry a `jldoctest`** showing a call and its value. `test/test_doctests.jl`
  runs them, so a doctest replaces a unit test of the same value. Qualify names that are not
  exported at the top level (`Thresholds.q_CHF_mirshak`). Never accept Documenter's
  `fix=true` output without reading the diff: it writes an error into the expected output as
  happily as a number.
- **Narrative goes to the docs pages, not the docstring.** A docstring says what a name
  accepts, computes and returns. A worked example goes to a tutorial or how-to, and the physics
  and the reasoning behind a choice to an explanation page; the docstring links to them.

## Units

Temperatures are **Celsius** everywhere: component arguments, connector variables, solution
values, and correlation inputs. This matches Python STREAM, which is the reference
implementation. Pressures are Pa, and the per-degree units (`J/(kg·K)`, `W/(m·K)`, `1/K`) are
unchanged since a degree Celsius and a kelvin are the same size.

## Git

- The user owns branch creation. Never run `git switch`, `git checkout -b` or
  `git branch <new>` unless asked in the current message. Worktree-isolated agents are exempt.
- Merges into `main` are squash-only, through a PR with review threads resolved.

## File Structure

### Modules

The package is a stack of submodules, each reaching only downward:

```
Substances -> Dimensionless -> {HTC, Friction, LocalLoss, Thresholds}
           -> Components -> {DecayHeat, Assemblies}
```

`solve_steady`, `solve_transient` and the operating-point guesses sit at the top level.

A module supplies the context a name would otherwise carry as a suffix, so
`SubcooledBoilingHTC` is `HTC.SubcooledBoiling` and `BlasiusFriction` is `Friction.Blasius`.
`HTC.RegimeDependent` and `Friction.RegimeDependent` coexist, which is the point.

Two ways to reach anything:

```julia
using STREAM              # Components.Channel(...), HTC.DittusBoelter()
using STREAM.Components   # Channel(...)
```

Prefer the qualified form in examples and in tests that touch more than one module: seeing
`HTC.RegimeDependent` next to `Friction.RegimeDependent` is the point of the split. Very
common verbs stay bare (`inseries`, `inparallel`).

### `src/`

Each subdirectory is one module, and `src/STREAM.jl` declares them all with their docstrings
and exports. A comment marks a file whose contents its name does not give away.

```
src/
  STREAM.jl                 # every module block, its docstring and its exports
  constants.jl
  geometry.jl
  knobs.jl                  # @design_knob, knob_defaults
  dimensionless.jl
  local_loss.jl             # module LocalLoss
  utilities.jl              # module Utilities: rebinning, cosine_shape, x_boundaries
  initial_conditions.jl     # steady_state_guess, uniform
  solvers.jl
  substances/
    liquid.jl               # AbstractLiquid, Liquid, the property aliases (ρ, cₚ, Tsat, ...)
    light_water.jl
    heavy_water.jl
    solid.jl
  htc/
    htc.jl                  # AbstractHTC, the model a channel is handed
    correlations.jl         # Nusselt correlations
    subcooled_boiling.jl
    exchangers.jl           # Counterflow, ParallelFlow effectiveness; flow_scaled_UA
  friction/
    correlations.jl         # Darcy factor correlations
    darcy.jl                # AbstractDarcyFactor, the model a channel or resistor is handed
  thresholds/
    thresholds.jl           # CHF, OFI, OSV, ONB and wall-temperature correlations
    analysis.jl             # ChannelState and the methods that apply them after a solve
  components/
    connectors.jl           # FlowPort, ThermalPort
    twoports.jl             # HydraulicTwoPort, the core every two-port component shares
    pump.jl
    valves.jl               # Flapper, Orifice
    tank.jl                 # Tank, Environment
    resistors.jl            # Resistor, FrictionResistor, Gravity, ResistorFromKnownPoint,
                            # VolumetricFlowResistor, LocalPressureDrop
    ideal.jl                # Inertia, ConstantTemperature
    heat_exchanger.jl
    sources.jl              # ConvectiveBoundary
    channels.jl             # Channel, ChannelHeatFlux, ChannelAndContacts
    heat_diffusion.jl       # HeatDiffusion, Slab, Cylinder
    point_kinetics.jl       # PointKinetics, ReactivityController
    state_machine.jl        # StateMachine, StateSchedule, trip!, reset!, machine_callbacks
  decay_heat/
    decay_heat.jl           # AbstractDecayHeat, Sum
    activation.jl           # Activation, DoubleDecay
    actinides.jl            # U238CaptureChain
    fission_products.jl     # FissionProducts, the standards tables and standards_dir!
    fissions.jl             # Fissions: the prompt profile from a point-kinetics solve
    source.jl               # DecayHeatSource: MeV/fission to power, and the trip clock
  assemblies/
    port.jl                 # port, var_length; loaded before Components
    assembly.jl             # assembly; loaded before Components
    connections.jl          # module Connect: face, inseries, inparallel, weighted, ...
    concrete_assemblies.jl  # plate, symmetric_plate, one_sided, single_channel,
                            # fuel_assembly
```

**Where new code goes:**
- New component (single MTK component) → `src/components/` in the most relevant file, or a new file if it's a new domain
- New correlation → the module that owns that physics: a Nusselt number into `src/htc/correlations.jl`, a friction factor into `src/friction/correlations.jl`, a local loss into `src/local_loss.jl`, a safety limit into `src/thresholds/thresholds.jl`
- New wiring verb → `src/assemblies/connections.jl` (inside `Connect`); a named arrangement → `src/assemblies/concrete_assemblies.jl`
- Prefer `Connect.face(...)` over a bare `face(...)`, but leave `inseries`, `inparallel` and `port` unqualified: the first two are used constantly and `port` is a getter that reads clearly on its own
- New decay heat contribution → `src/decay_heat/`, in the file matching the Python module it mirrors
- New coolant → `src/substances/` (e.g. `src/substances/molten_salt.jl`), implementing the `AbstractLiquid` property methods
- A worked model → the docs, as a tutorial or how-to. `src/` holds no example builders; a model several test files solve goes in `test/fixtures.jl`

Placement beats file length. A long file whose contents all belong together is fine; a short
file named `misc` or `helpers` is not. Physics lives in its own module, even when one
component is its only caller: components state equations, they do not define correlations.

### `docs/`

```
docs/
  make.jl          # Documenter build: Literate conversion, makedocs. It never deploys
  deploy.jl        # deploydocs, run only by CI's deploy job
  vendor.jl        # downloads the scripts and fonts the pages load, so the site works offline
  literate/        # the tutorials, as runnable scripts Literate turns into pages
  src/
    index.md       # home: what STREAM is, a first model, conventions
    tutorials/     # index.md only; the tutorial pages are generated, and git-ignored
    howto/         # task recipes, one page per task
    explanation/   # the physics and the reasoning behind the models
    reference/     # one @autodocs page per module
    refs.bib       # every citation
    assets/        # hand-drawn SVG schematics
```

The site follows the four kinds of documentation: tutorials teach by building a model,
how-to guides solve one task, explanation pages give the physics, and the reference lists the
API. Put a new page in the kind it is, and list it in `make.jl`. To show a system's equations
on a page, print them as TeX with `latexify(equations(sys); env=:aligned)`. Code on a page runs
when the docs build, so tutorials and how-tos end with an `@assert` against physics where one
exists. Plots use CairoMakie.

### `test/`

A test file mirrors its source file: `components/channels.jl` → `test_channels.jl`, and a new
component file gets a new test file. `ConvectiveBoundary` (`src/components/sources.jl`) is the
exception: its tests live in `test_ideal.jl` beside `ConstantTemperature`. The physics modules
are covered by `test_correlations.jl`, `test_htc.jl`, `test_darcy.jl` and `test_thresholds.jl`.

Files that don't mirror a source file:

- `runtests.jl` includes `preamble.jl` (fixed BLAS threads and RNG seed), then one file per
  line, nothing else.
- `fixtures.jl` holds `build_loop` and `build_loop_pk`, the loops several files solve. A file
  that needs them includes it behind `@isdefined(build_loop)`.
- `test_doctests.jl` runs the `jldoctest` blocks, and skips when Documenter is missing.
- `test_validation.jl` compares whole models against values generated by Python STREAM
  (`data/python_parity_reference.jl`, with `parity_helpers.jl`).
- `test_integration.jl` is a strict 1:1 port of Python's
  `tests/test_general/test_integrations.py`: exactly its 21 tests, nothing else.
- The decay heat table testsets skip unless `STREAM_DECAY_HEAT_STANDARDS` points at the CSVs.

## Known gaps against Python STREAM

`GAPS.md` in the repo root holds what remains against Python, in order, and what was checked
and found equivalent. Python's `stream-next` branch is a reference too: it fixes several
correlations and adds loss of coolant, and GAPS.md says which parts we take. The two below are
here because they change how you should work in this repository, not because they are the
only ones. Both were checked against the Python source, so do not re-derive them from scratch.

- **Decay heat reaches a model through `power_input`, not through a connector.** Build a
  `DecayHeat.DecayHeatSource` from a contribution, hand it to
  `PointKinetics(...; power_input=source)`, and couple the fuel to `pk.P`, the total power.
  The kinetics state is `P_neutron`, which carries no source. The source
  reads its trip time off the `StateMachine`, so it needs the machine the reactor is
  controlled by, or the controller holding it. The standards tables are not in this repo and
  never should be: point `DecayHeat.standards_dir!` at them, or set
  `STREAM_DECAY_HEAT_STANDARDS`.
- **Seed a loss-of-flow steady solve with its flows.** Solve the pump-on state with
  `solve_steady(...; solver=DynamicSS(Rodas5P()))`, which integrates to where the model
  settles, and start the flow unknowns `mtkcompile` keeps away from zero: started at zero, the
  solve stays at ṁ = 0 and fails. The bypass loss-of-flow testset in `test/test_valves.jl`
  seeds the pump head, its two kept flows at the head over `ext_res` and the dummy derivative,
  and nothing else. If a change to a channel equation changes which flows `mtkcompile` keeps,
  that list is the first thing to look at.

  Do not "fix" a failed solve with a sign constraint on ṁ. This loop's flow legitimately
  reverses after the pump trips, so forbidding negative flow would forbid the physics.

Not gaps, checked and matching: the developing-laminar Nusselt (Python defaults to the same
analytic approximation, using its Shah & London table only to bound that approximation's
error), and the whole HTC / friction / local-loss / threshold / dimensionless inventory.

## Component authoring conventions

- **Positional arguments** when the argument's type selects the method
  (`Pump(dP::Real; name)` vs `Pump(dP::Any; name)`), or when there is at most one physics
  parameter and its role is clear from the name (`Resistor(R; name)`, `Gravity(H; name)`).
- **Keyword arguments** when several arguments share a type and order would be a bug waiting
  to happen (`Channel(; name, L, Dh, ...)`), or when a constructor has many parameters.
- A `Duct` takes its length and shape positionally, `Duct(0.6, Rectangular(0.067, 0.0024))`,
  since each has one obvious role.
- `name` is always keyword-only, since `@named` injects it as a keyword.

## Exports

Each submodule declares its own `export` list, inside its `module` block in `src/STREAM.jl`.
The top-level list at the bottom of that file is the package's public surface and is kept
short (under 60 names): the module names, the coolant properties, the dimensionless numbers,
the geometry, the solve entry points, the constants, the knob macros, and `assembly`/`port`.
Everything else is reached through its module.

Never add an `export` statement inside a component or physics file. All of them live in
`src/STREAM.jl`, so both the per-module surface and the package surface are auditable in one
place.

A name reaches the top level only by being listed twice, once in its module and once at the
bottom. That friction is intentional: it is what stopped the list growing to 145 again.

## MTK in this repo

General MTK v11 usage is in the skill. Two choices specific to this codebase:

- **Coolant properties are plain arithmetic, not `@register_symbolic`.** MTK traces through
  them, so dispatch on the liquid happens once while equations are built and the solver gets
  differentiable expressions. The only registered function is `LocalLoss.factor`. Do not
  register a method that dispatches on its first argument: the shims of `density(::LightWater, T)`
  and `density(::HeavyWater, T)` collide and precompilation fails.
- **Diagnostics go in `observed`.** Components pass `observed=[...]` to `System` for quantities
  nothing else reads (`Re`, `Nu`, `htc`). A quantity another equation references must be a
  plain unknown.

## Running the code

```bash
julia --project=. test/runtests.jl        # full suite
julia --project=. test/test_channels.jl   # a single file
julia --project=docs docs/make.jl         # the docs, running every example
```

The docs build takes several minutes. `DRAFT=1` skips running code, for editing prose, and
`PREVIEW=1` runs it but reports links to unwritten pages as warnings. Serve the result with
`python3 -m http.server -d docs/build 8000`. The first build needs
`julia --project=docs -e 'using Pkg; Pkg.instantiate()'` and `julia docs/vendor.jl`, which
downloads the scripts and fonts the pages use to `docs/vendor`, or to the directory
`STREAM_DOCS_VENDOR` names. The built site loads nothing from the internet: `make.jl` fails if
a file is missing, or if a page would still load something from a CDN.

Each invocation pays full cold start (~30–90s `using STREAM` plus first `mtkcompile`
~10–30s). That is the accepted dev loop. A Revise/DaemonMode dev loop and a PackageCompiler
sysimage were both tried and dropped (the sysimage link step is killed on Julia 1.12 + WSL2);
do not reintroduce them.

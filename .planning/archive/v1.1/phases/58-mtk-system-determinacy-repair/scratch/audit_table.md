# Phase 58 — `fully_determined=false` / `check_length=false` Audit

> Every site found by `grep -rn "fully_determined\|check_length" src/ test/`
> classified per CONTEXT.md D-04. `Disposition` cells route bug-hiding sites to
> their downstream fix plan owner.

## MTK API behavior

Installed package versions (from `Manifest.toml`): MTK **11.25.0** (uuid
`961ee093-…`), MTKBase **1.34.0** (uuid `7771a370-…`), SciMLBase **2.155.1**
(uuid `0bca4576-…`). No CHANGELOG ships with these packages —
`find ~/.julia/packages/ModelingToolkit* -name CHANGELOG*` returns nothing — so
the API drift was verified directly from installed source.

`mtkcompile`'s `fully_determined` kwarg (`MTKBase/.../systems/systems.jl:204-227`)
defaults to `false`; setting `false` only **suppresses the compile-time
imbalance check** — it does NOT rebalance the system. Downstream
`process_SciMLProblem.check_eqs_u0` (`MTKBase/.../abstractsystem.jl:3081-3094`)
**always** runs with `check_length=true` and throws
`ArgumentError: Equations (N), unknowns (N+1), and initial conditions (N+1) are
of different lengths.` This is the *exact* error CONTEXT.md cites. Therefore
`fully_determined=false` at `mtkcompile` time is bug-hiding for any system that
will be passed to `solve_steady` / `SteadyStateProblem` / `ODEProblem` — the
imbalance is just deferred to problem construction time.

| File:Line | Site context | Verdict | One-line reason | Disposition |
|-----------|--------------|---------|-----------------|-------------|
| `src/components/flapper.jl:38` | Flapper docstring | doc-only | Documentation telling users to pass `fully_determined=false` for standalone Flapper compile (component intentionally has free `state(t)` set by external `ContinuousCallback`) | Tighten docstring in Plan 58-05 to name the structural reason (callback-set state) |
| `src/components/channels.jl:207` | Comment inside Channel | doc-only | Inline doc reference to Phase 55 D-08 Hypothesis-A pattern; not a compile-time site | Leave |
| `src/components/channels.jl:409` | Comment inside ChannelHeatFlux | doc-only | Same family as :207 | Leave |
| `test/test_misc.jl:19` | Inertia compile in isolation | isolated-component-test | Inertia in isolation has 1 unknown (mdot) and no closing eq; intentional unit-test scope | Keep + add inline comment in Plan 58-05 |
| `test/test_misc.jl:37` | RL circuit compile (no T eqs by design) | legitimate-structural | Pure hydraulic RL; T equations do not exist in this topology by design (CONTEXT.md D-04 cites this exact site as the survivor archetype) | Keep + already commented; tighten comment in Plan 58-05 |
| `test/test_misc.jl:41` | RL circuit `check_length=false` documentation comment | legitimate-structural | Comment explaining why :48 needs `check_length=false` (T unknowns underdetermined; no T equations in pure RL circuit) | Keep + already commented |
| `test/test_misc.jl:48` | RL circuit ODEProblem `check_length=false` | legitimate-structural | Same site family as :37; consistent | Keep + already commented |
| `test/test_misc.jl:71` | HeatExchanger compile in isolation | isolated-component-test | Pure value-source, no flow context | Keep + add inline comment in Plan 58-05 |
| `test/test_misc.jl:131` | WallTemperature compile in isolation | isolated-component-test | Value-source (pure RHS); produces only `T_wall_out[i] ~ T_wall_fn(t)` equations, no port-Q closure | Keep + add inline comment in Plan 58-05 |
| `test/test_misc.jl:178` | HeatFluxSource compile in isolation | isolated-component-test | Same family as :131 | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:17` | Comment explaining :18 | doc-only | "fully_determined=false: isolated ports make system under-determined" — intentional documentation | Leave |
| `test/test_pump.jl:18` | Pump in isolation | isolated-component-test | Pump alone has unconnected ports | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:36` | Pump+Resistor (no anchor) | isolated-component-test | Tests rate-equation only, no pressure anchor | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:68` | Pump-source variant | isolated-component-test | Same family as :36 | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:83` | Pump+Resistor flipped sign | isolated-component-test | Same family as :36 | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:99` | Pump callable | isolated-component-test | Same family as :36 | Keep + add inline comment in Plan 58-05 |
| `test/test_pump.jl:133` | Pump+Resistor in test | isolated-component-test | Same family as :36 | Keep + add inline comment in Plan 58-05 |
| `test/test_resistors.jl:18` | Resistor compile | isolated-component-test | Pure resistance, no anchor | Keep + add inline comment in Plan 58-05 |
| `test/test_flapper.jl:58` | Flapper compile | isolated-component-test | Per `flapper.jl:38` docstring; free `state(t)` by design (callback-set) | Keep + add inline comment in Plan 58-05 |
| `test/test_flapper.jl:110` | Flapper compile (variant 2) | isolated-component-test | Same family as :58 | Keep + add inline comment in Plan 58-05 |
| `test/test_flapper.jl:151` | Flapper compile (variant 3) | isolated-component-test | Same family as :58 | Keep + add inline comment in Plan 58-05 |
| `test/test_heat_diffusion.jl:44` | HD compile in isolation | isolated-component-test | HD alone has dangling thermal ports + unset `power(t)`; intentional unit scope | Keep + add inline comment in Plan 58-05 |
| `test/test_heat_diffusion.jl:185` | HD + ConstantTemperature integration test | bug-hiding | Has `[hd.power ~ pwr]` already pinned at line 182, so the system IS structurally determined — `fully_determined=false` here is a leftover that should be `true` | Convert to `fully_determined=true` in Plan 58-05 |
| `test/test_channels.jl:16` | Comment explaining the file's tests | doc-only | Pre-amble describing Hypothesis-A pattern (Phase 55 D-08) | Leave |
| `test/test_channels.jl:67` | Comment | doc-only | Inline doc | Leave |
| `test/test_channels.jl:70` | Channel compile in isolation | isolated-component-test | External-input vars `T_wall_left[1:n]`, `T_wall_right[1:n]` intentionally underdetermined per Phase 55 D-08 Hypothesis-A | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:84` | ChannelHeatFlux compile | isolated-component-test | Same family as :70 (`q_left[1:n]`, `q_right[1:n]` external inputs) | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:94` | ChannelAndContacts compile | isolated-component-test | Per-cell `thermal_*[i]` ports dangle in isolation — Phase 55 D-08 verified pattern | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:468` | Channel topology variant | isolated-component-test | Same family — Hypothesis-A | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:675` | Channel topology variant | isolated-component-test | Same family — Hypothesis-A | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:804` | Channel topology variant | isolated-component-test | Same family — Hypothesis-A | Keep + add inline comment in Plan 58-05 |
| `test/test_channels.jl:1087` | CAC composite topology | isolated-component-test | Same family — Hypothesis-A | Keep + add inline comment in Plan 58-05 |
| `test/test_validation.jl:204` | KEPT testsets `mtkcompile` (one of broken scenarios) | bug-hiding | One of the seven broken scenarios in CONTEXT.md `<domain>` (sentinel-row wrapper covers it) | Convert to `fully_determined=true` after Plan 58-04 lands (last fix plan touching test_validation.jl) |
| `test/test_validation.jl:379` | MTR symmetric `mtkcompile` | bug-hiding | The exact target of Plan 58-02 (MTR sym) | Convert to `fully_determined=true` in Plan 58-02 |
| `test/test_validation.jl:549` | MTR asymmetric `mtkcompile` | bug-hiding | Plan 58-02 target | Convert to `fully_determined=true` in Plan 58-02 |
| `test/test_validation.jl:709` | MTR one-sided `mtkcompile` | bug-hiding | Plan 58-02 target | Convert to `fully_determined=true` in Plan 58-02 |
| `test/test_validation.jl:903` | VAL-01 HD Fourier `mtkcompile` | bug-hiding | Plan 58-03 target | Convert to `fully_determined=true` in Plan 58-03 |
| `test/test_validation.jl:996` | VAL-02 two-plate `mtkcompile` | bug-hiding | Plan 58-04 target | Convert to `fully_determined=true` in Plan 58-04 |

---

## Audit summary by category

- **Bug-hiding (7 sites):** `test/test_validation.jl:204, 379, 549, 709, 903, 996` and `test/test_heat_diffusion.jl:185`. Each gets flipped to `fully_determined=true` *after* its corresponding determinacy fix lands (per per-plan ownership).
- **Legitimate-structural / isolated-component-test (~26 sites):** preserved with inline comments naming the structural reason. Most are isolated component compiles (Pump/Resistor/Inertia/HeatExchanger/HD/CAC/CHF/Channel/Flapper/WallTemperature/HeatFluxSource alone) where the test pattern is "compile this component in isolation; verify shape, not solvability".
- **Doc-only (5 sites):** `src/components/channels.jl:207, 409` (comments), `src/components/flapper.jl:38` (docstring), `test/test_pump.jl:17` (comment), `test/test_channels.jl:16, 67` (comments). Only `src/components/flapper.jl:38` warrants a small docstring tightening (Plan 58-05).

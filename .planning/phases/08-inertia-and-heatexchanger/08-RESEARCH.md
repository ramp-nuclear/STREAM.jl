# Phase 8: Inertia and HeatExchanger - Research

**Researched:** 2026-03-13
**Domain:** MTK lumped component authoring, ODE initial-value transient solving
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Inertia parameter API**
- Combined single parameter: `Inertia(; name, L_over_A)` — user pre-computes L/A
- Parameter named `L_over_A` internally (self-documenting, mirrors the formula)
- Equation: `port_in.P - port_out.P ~ L_over_A * Differential(t)(port_in.mdot)`
- No explicit `mdot` state variable — use `port_in.mdot` implicitly (consistent with Resistor/Gravity/Friction)
- Temperature: passthrough (`port_out.T ~ instream(port_in.T)`, `port_in.T ~ instream(port_out.T)`)
- No `KirchhoffWithDerivatives` equivalent needed — MTK handles ODE/DAE structure automatically

**Transient validation test (COMP-01)**
- RL-decay circuit: Inertia + Resistor in a closed loop, no pump
- Initial condition: `mdot(t=0) = 1.0` kg/s (pump already off)
- Analytical solution: `mdot(t) = exp(-(R / L_over_A) * t)`
- Test parameters: `R = 1.0`, `L_over_A = 1e3` (tau = 1000s)
- Tolerance: 1% rtol — consistent with GRAV-02 and NET-03
- Mirrors Python STREAM's canonical Inertia RL-circuit test

**HeatExchanger (COMP-02)**
- Move `_make_temp_bc` from `solvers.jl` to `components.jl`, rename to `HeatExchanger`
- Identical 4-equation structure: mass balance, no pressure drop, `port_out.T ~ T_bc`, `port_in.T ~ instream(port_out.T)`
- Export `HeatExchanger` from `STREAM.jl`
- Remove `_make_temp_bc` from `solvers.jl`; update all three `build_loop` variants (`build_loop`, `build_loop_vertical`, `build_loop_transient`) to call `HeatExchanger` directly
- No pressure-drop parameter added — COMP-02 explicitly says no pressure drop

### Claude's Discretion
- ODE solver choice for transient test (Rodas5P or similar stiff solver)
- Exact time span for RL-decay validation (enough points to verify exponential shape)
- Whether to add a `build_loop_inertia` helper or just test Inertia as a standalone component

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| COMP-01 | Inertia component: `dp ~ (L/A) * D(mdot)`, validated against Python STREAM Inertia on a transient test case | MTK `Differential(t)` on port variable is first-class; Rodas5P used for stiff mass-matrix ODEs; RL-decay analytical formula confirmed |
| COMP-02 | HeatExchanger component (public): fixed outlet temperature, no pressure drop — replaces internal `_make_temp_bc`; existing build_loop updated to use it | `_make_temp_bc` in `solvers.jl` lines 35-46 is the complete 4-equation implementation ready to move |
</phase_requirements>

---

## Summary

Phase 8 adds two lumped components that are almost entirely pre-solved by the existing codebase. The `Inertia` component follows the exact same compose-pattern as `Resistor`, `Gravity`, and `Friction`, differing only in using `Differential(t)(port_in.mdot)` on the right-hand side of the pressure equation. MTK treats this as a first-class ODE term; no special solver scaffolding is required beyond the already-established `Rodas5P` stiff solver path used by `solve_transient`.

`HeatExchanger` is a pure rename-and-move: `_make_temp_bc` in `solvers.jl` lines 35-46 already contains the complete 4-equation structure. The task is to relocate it to `components.jl`, export it from `STREAM.jl`, and update the three `build_loop` variants (lines 86, 168, 226 of `solvers.jl`) to call `HeatExchanger` instead of the private helper.

The only non-trivial work is the transient RL-decay test for COMP-01. The test needs a closed loop of `Inertia + Resistor` with `mdot(t=0) = 1.0` and no pump, solving with `Rodas5P` and `NoInit` (consistent with the established `solve_transient` pattern). The validation compares against `exp(-(R / L_over_A) * t)` at 1% rtol.

**Primary recommendation:** Implement `Inertia` first (COMP-01 drives the only real design work), then do the trivial `HeatExchanger` refactor (COMP-02). A single plan wave covering both in sequence is appropriate given their small scope.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | v9+ (project-pinned) | ODE/DAE system construction, `Differential(t)`, `compose`, `mtkcompile` | All existing components use this |
| DifferentialEquations | project-pinned | `ODEProblem`, `SteadyStateProblem` | Already in `solvers.jl` |
| Sundials / OrdinaryDiffEq | project-pinned | `Rodas5P` stiff solver, `KINSOL` | Already used by `solve_transient` |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| SciMLBase | transitive | `NoInit` initialization algorithm | Needed in transient test to skip inconsistent-IC error |

**No new dependencies.** All required libraries are already in `Project.toml`.

---

## Architecture Patterns

### Inertia Component Structure

Follow the `Resistor` pattern verbatim, with one equation substitution:

```julia
# Source: src/components.jl — Resistor pattern (lines 140-151)
function Inertia(; name, L_over_A)
    Dt  = Differential(t)           # same operator used in Channel energy balance
    pars = @parameters L_over_A = L_over_A
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ L_over_A * Dt(port_in.mdot),  # ODE pressure eq
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
```

Key differences from `Resistor`:
- Uses `Dt = Differential(t)` (already used in `Channel`; no new syntax)
- The vars list is empty `[]` — `port_in.mdot` is the state, MTK promotes it automatically
- No `abs()` needed — inertia is directional (sign of `Dt(mdot)` follows sign convention)

### HeatExchanger Component Structure

Direct copy of `_make_temp_bc` with renamed parameter:

```julia
# Source: src/solvers.jl lines 35-46 (_make_temp_bc — move and rename)
function HeatExchanger(; name, T_bc)
    pars = @parameters T_bc = T_bc
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P   - port_out.P    ~ 0,
        port_out.T  ~ T_bc,
        port_in.T   ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
```

### build_loop Update Pattern

Three call sites in `solvers.jl` — mechanical search-and-replace:

| Line | Old call | New call |
|------|----------|----------|
| 86 | `_make_temp_bc(T_bc = T_inlet)` | `HeatExchanger(T_bc = T_inlet)` |
| 168 | `_make_temp_bc(T_bc = T_inlet)` | `HeatExchanger(T_bc = T_inlet)` |
| 226 | `_make_temp_bc(T_bc = T_inlet)` | `HeatExchanger(T_bc = T_inlet)` |

The `@named bc = ...` local variable name stays the same in all three functions — no other code in the function body references `_make_temp_bc` directly.

### Transient RL-Decay Test Pattern

Follows the established `solve_transient` scaffolding pattern:

```julia
# Topology: Inertia + Resistor in a closed loop (no pump)
@named L = Inertia(L_over_A = 1e3)
@named R = Resistor(R = 1.0)
connections = [
    connect(L.port_out, R.port_in),
    connect(R.port_out, L.port_in),
    L.port_in.P ~ 1.0e5,           # pressure gauge anchor
]
@named sys = compose(System(connections, t; name=:sys), L, R)
ssys = mtkcompile(sys)

# Initial condition: mdot(0) = 1.0
op = [ssys.L.port_in.mdot => 1.0]
prob = ODEProblem(ssys, op, (0.0, 5000.0); warn_initialize_determined=false)
sol = solve(prob, Rodas5P(); initializealg=SciMLBase.NoInit())

# Analytical: mdot(t) = exp(-(R/L_over_A) * t)
tau = 1e3 / 1.0    # = 1000 s
t_check = [0.0, 500.0, 1000.0, 2000.0, 5000.0]
for tc in t_check
    @test isapprox(sol(tc)[...], exp(-tc / tau); rtol=0.01)
end
```

The time span must cover several tau (tau = 1000 s), so `(0.0, 5000.0)` gives 5 time constants — sufficient to verify the exponential decay shape.

### Recommended Project Structure

No new files or directories. Changes are confined to:

```
src/
├── components.jl    # add Inertia and HeatExchanger functions
├── solvers.jl       # remove _make_temp_bc, update 3 build_loop call sites
└── STREAM.jl        # add Inertia, HeatExchanger to export list
test/
└── runtests.jl      # add Phase 8 testset
```

### Anti-Patterns to Avoid

- **Adding an explicit mdot state variable to Inertia:** MTK promotes `port_in.mdot` to a state automatically because it appears inside `Differential(t)`. Adding a redundant `mdot(t)` variable with an extra equality equation creates an over-determined system.
- **Using `IDA` or `CVODE_BDF` for the RL-decay test:** These require `DAEProblem` with explicit `du0` or cannot handle mass matrices. `Rodas5P` is the correct stiff implicit Runge-Kutta solver for MTK-generated mass-matrix ODEs (established in `solve_transient`).
- **Forgetting the pressure anchor in the RL-decay test:** As in the cube network (NET-02/03), a closed hydraulic loop has an underdetermined absolute pressure. Pin `L.port_in.P ~ 1.0e5` (or any port).
- **Renaming the `bc` variable in build_loop functions:** All three `build_loop` variants use `@named bc = _make_temp_bc(...)`. The connections list references `bc.port_in`, `bc.port_out`. Changing the variable name would break the connection wiring. Only replace the constructor call.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ODE promotion of `port_in.mdot` | Manual state variable + equality eq | `Differential(t)(port_in.mdot)` directly in pressure eq | MTK promotes automatically; extra equation causes over-determination |
| Stiff ODE solver for mass-matrix system | Custom integrator | `Rodas5P()` | Rodas5P is the project-established solver for MTK-generated DAE/ODE systems |
| Exponential decay verification | Custom tolerance logic | `isapprox(val, ref; rtol=0.01)` | Consistent with GRAV-02, NET-03, VAL-01 verification pattern |

---

## Common Pitfalls

### Pitfall 1: `mtkcompile` on Inertia in isolation
**What goes wrong:** `mtkcompile(inertia_sys)` without `fully_determined=false` errors because the unconnected ports leave pressure and temperature algebraically free.
**Why it happens:** Standalone component smoke tests always leave ports open.
**How to avoid:** Use `mtkcompile(sys; fully_determined=false)` for isolated component tests — the established pattern (confirmed in Phase 7 for Resistor).
**Warning signs:** "System is not fully determined" error from MTK.

### Pitfall 2: Initial condition inconsistency with `NoInit`
**What goes wrong:** `solve` throws an error about inconsistent initial conditions or returns `NaN`.
**Why it happens:** `Rodas5P` with `NoInit` skips MTK's automatic initialization. The pressure variables in the RL loop must satisfy the loop balance at `t=0`. If `mdot(0) = 1.0` is given but pressures are left at default, the algebraic equations may not be satisfied.
**How to avoid:** The pressure anchor `L.port_in.P ~ 1.0e5` removes the gauge freedom. MTK's algebraic constraints then determine all pressure values from the `mdot(0) = 1.0` IC. Alternatively, include `op` entries for pressure if needed, or use `SciMLBase.BrownFullBasicInit()` (slower but auto-consistent).
**Warning signs:** `sol.retcode != ReturnCode.Success` or `NaN` in `sol.t[2:]`.

### Pitfall 3: Missing export for `Inertia` or `HeatExchanger`
**What goes wrong:** Tests import `STREAM` and call `Inertia(...)` but get `UndefVarError`.
**Why it happens:** `STREAM.jl` has an explicit export list; new symbols must be added.
**How to avoid:** TDD — the test file calls `Inertia(...)` and `HeatExchanger(...)` before the export is added; the failing test catches this.
**Warning signs:** `UndefVarError: Inertia not defined` at test time.

### Pitfall 4: `_make_temp_bc` still defined after rename
**What goes wrong:** `build_loop` (unchanged function call) still works because `_make_temp_bc` still exists; the test for COMP-02 "HeatExchanger is exported" passes, but `_make_temp_bc` is never removed.
**Why it happens:** If only the new function is added and the old one left in place, both work silently.
**How to avoid:** Explicitly delete the `_make_temp_bc` function from `solvers.jl` and verify the test suite still passes (COMP-02 success criterion includes "existing v0.1 validation tests continue to pass").
**Warning signs:** Both `_make_temp_bc` and `HeatExchanger` visible in module at the same time.

---

## Code Examples

### Differential(t) on a port variable (established pattern)
```julia
# Source: src/components.jl Channel energy balance (line 51)
Dt = Differential(t)
Dt(T[i]) ~ (port_in.mdot * cp_water(T[i]) * (T_up - T[i]) + ...) / (...)
```

The same operator applied to `port_in.mdot` works identically. MTK recognises it as the state derivative and promotes `port_in.mdot` to a differential variable.

### Rodas5P + NoInit for mass-matrix ODE (established pattern)
```julia
# Source: src/solvers.jl solve_transient (line 291)
sol = solve(prob, Rodas5P(); callback = step_cb, initializealg = SciMLBase.NoInit())
```

For the RL-decay test there is no callback. The minimal call is:
```julia
sol = solve(prob, Rodas5P(); initializealg = SciMLBase.NoInit())
```

### compose pattern (established for all components)
```julia
# Source: src/components.jl Resistor (line 150)
compose(System(eqs, t, [], pars; name=name), port_in, port_out)
```

Inertia uses identical structure with empty vars list `[]`.

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Internal `_make_temp_bc` (private) | Public `HeatExchanger` (exported) | Users can compose HeatExchanger directly without `build_loop`; opens Phase 9 ChannelAndContacts test patterns |

**Nothing deprecated in this phase.** `_make_temp_bc` is removed (was always private, never exported).

---

## Open Questions

1. **Pressure anchor for RL-decay loop with `NoInit`**
   - What we know: The closed Inertia+Resistor loop has one gauge freedom (absolute pressure). The anchor `L.port_in.P ~ 1.0e5` resolves it.
   - What's unclear: Whether `NoInit` will propagate the pressure values correctly from a single-port anchor when only `mdot(0)` is specified as IC.
   - Recommendation: Test with `SciMLBase.NoInit()` first. If pressure initialization fails, fall back to `SciMLBase.BrownFullBasicInit()` (slower but handles algebraic constraints automatically). Document the working approach in test comments.

2. **`mdot` symbolic indexing in RL-decay solution**
   - What we know: In the loop topology `ssys.L.port_in.mdot` is the primary state variable (or `ssys.R.port_in.mdot` — they are equal by mass conservation and Kirchhoff).
   - What's unclear: After `mtkcompile`, which symbolic index MTK retains for the mdot state.
   - Recommendation: Use `sol[ssys.L.port_in.mdot, :]` as the primary accessor. If not available post-compile, check `unknowns(ssys)` to find the retained symbol name. Add a comment in the test.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + `@testset` |
| Config file | none — tests run via `Pkg.test()` or `julia test/runtests.jl` |
| Quick run command | `julia --project -e 'include("test/runtests.jl")'` |
| Full suite command | `julia --project -e 'import Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| COMP-01 | Inertia component callable and mtkcompile with fully_determined=false | unit | `julia --project -e 'include("test/runtests.jl")'` | ❌ Wave 0 |
| COMP-01 | RL-decay transient: mdot(t) = exp(-(R/L_over_A)*t) within 1% rtol | integration | same | ❌ Wave 0 |
| COMP-02 | HeatExchanger callable and mtkcompile with fully_determined=false | unit | same | ❌ Wave 0 |
| COMP-02 | HeatExchanger exported from STREAM module | unit | same | ❌ Wave 0 |
| COMP-02 | build_loop, build_loop_vertical, build_loop_transient compile after rename | regression | same | ❌ Wave 0 |
| COMP-02 | VAL-01 steady-state still passes (build_loop regression) | regression | same | ✅ (existing VAL-01 test) |

### Sampling Rate
- **Per task commit:** `julia --project -e 'include("test/runtests.jl")'`
- **Per wave merge:** `julia --project -e 'import Pkg; Pkg.test()'`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/runtests.jl` Phase 8 testset — covers COMP-01 (Inertia stub, RL-decay) and COMP-02 (HeatExchanger stub, export, build_loop regression)

*(Existing test infrastructure covers all prior requirements. Only new Phase 8 testset needed.)*

---

## Sources

### Primary (HIGH confidence)
- `src/components.jl` (read directly) — Resistor/Gravity/Friction patterns; Differential(t) usage in Channel
- `src/solvers.jl` (read directly) — `_make_temp_bc` lines 35-46; `solve_transient` Rodas5P+NoInit lines 270-293; three build_loop call sites
- `src/STREAM.jl` (read directly) — current export list
- `src/connectors.jl` (read directly) — FlowPort structure
- `test/runtests.jl` (read directly) — established test patterns and testset structure
- `.planning/phases/08-inertia-and-heatexchanger/08-CONTEXT.md` (read directly) — locked decisions

### Secondary (MEDIUM confidence)
- `/home/itay/projects/STREAM/stream/calculations/ideal/inertia.py` — Python STREAM Inertia: `dp = -L * d(mdot)/dt` (sign matches Julia convention with `port_in.P - port_out.P ~ L_over_A * Dt(mdot)`)
- `/home/itay/projects/STREAM/tests/test_general/test_integrations.py` lines 433-466 — Python canonical RL-circuit test: `mdot ~ exp(-(r/inertia)*t)` at rtol=1e-4; Julia uses rtol=0.01 per project convention

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project, no new deps
- Architecture: HIGH — both components are direct adaptations of existing code; all patterns verified from source
- Pitfalls: HIGH — all pitfalls derived from existing codebase evidence (Phase 7 mtkcompile pattern, solve_transient NoInit pattern, Phase 7 pressure anchor requirement)

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (MTK API stable; no fast-moving dependencies)

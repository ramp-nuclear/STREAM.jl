# Phase 45: PointKinetics Bare Component & Steady-State ICs - Research

**Researched:** 2026-04-04
**Domain:** MTK ODE component authoring, nuclear point kinetics equations
**Confidence:** HIGH

## Summary

Phase 45 introduces a standalone MTK `ODESystem` component implementing the 6-group point kinetics equations (7 ODEs: 1 power + 6 precursor groups) and a companion `point_kinetics_steady_state` helper function. This is a well-bounded task: the ODEs are textbook, the MTK component patterns are thoroughly established in this codebase (Channel, Inertia, HeatExchanger all serve as templates), and the Python STREAM reference implementation is available for cross-validation.

The key technical decisions are already locked: scalar MTK parameters for each delayed group (not array parameters), keyword-only constructor with U-235 defaults, `@observed` variables for `beta_total`, `dPdt`, and `reactivity`. No ports, no feedback, no coupling -- those are Phases 46-48.

**Primary recommendation:** Follow the Inertia/HeatExchanger component pattern (simple `compose(System(eqs, t, vars, pars; observed=obs, name=name))`) with no sub-components. Use Julia `const` arrays at module level for U-235 defaults. The steady-state helper is pure Julia math (not MTK).

<user_constraints>

## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Constructor accepts Julia arrays (`beta_k::Vector`, `lambda_k::Vector`) and generates 6 individual scalar MTK parameters internally (`beta_1, ..., beta_6`, `lambda_1, ..., lambda_6`). Public API is array-based; MTK internals are scalar-based.
- **D-02:** Avoids MTK array parameter pitfalls (indexing in equations, ODEProblem `p` passing). Downstream phases (46-48) iterate over the 6 scalars when building feedback sums.
- **D-03:** Embed U-235 6-group defaults for `Lambda`, `beta_k`, and `lambda_k`. Same values as Python STREAM reference (`Lambda = 5.4e-5 s`; same `lambdak`/`betak` arrays used in Python tests). Caller gets a working system with `PointKinetics(; name, rho=0.0)` and can override for other fuel types.
- **D-04:** `rho` has no meaningful default (rho=0 is subcritical steady state; callers should be explicit). Keep `rho` as a required keyword or default to `0.0` with a clear docstring note.
- **D-05:** Match Python STREAM `save()` output -- expose `beta_total`, `dPdt`, `reactivity` as `@observed`.
- **D-06:** State variables P and all C_k are always accessible from the solution; no need to make them `@observed`.
- **D-07:** Keyword-only constructor: `PointKinetics(; name, rho=0.0, Lambda=5.4e-5, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K)`.
- **D-08:** `name` always keyword-only (injected by `@named` macro).
- **D-09:** New file `src/components/point_kinetics.jl`. Export `PointKinetics` and `point_kinetics_steady_state` from `src/STREAM.jl` only.
- **D-10:** Test file `test/test_point_kinetics.jl`; included in `test/runtests.jl`.

### Claude's Discretion
- Variable naming inside the component (`C_1..C_6` vs `Ck[1]..Ck[6]` as MTK variable naming -- use scalar `@variables C_1(t) C_2(t) ...`)
- Internal helper for U-235 constants (module-level `const` vs hardcoded defaults in the constructor)
- Docstring structure (follow existing component docstring pattern with `# Arguments`, `# Returns`)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.

</user_constraints>

<phase_requirements>

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PK-01 | PointKinetics MTK component with P + 6 C_k ODEs, constant rho parameter; validated against analytical precursor-only decay (rtol <= 1e-3) | Python STREAM ODE formulation verified; MTK component pattern established; precursor decay analytical solution derived |
| PK-02 | `point_kinetics_steady_state` closed-form helper: C_k = beta_k/(lambda_k*Lambda)*P0 at criticality; required for all coupled transient ICs | Formula verified against Python STREAM steady-state derivation; pure Julia function (not MTK) |

</phase_requirements>

## Standard Stack

### Core (already in project)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit | 11.15.0 | Symbolic ODE system construction | Project foundation; `@variables`, `@parameters`, `System()`, `mtkcompile` |
| DifferentialEquations | 7.17.0 | ODE/DAE solving | `ODEProblem`, `solve`, `Rodas5P` for stiff systems |
| Sundials | 5.1.0 | KINSOL steady-state solver | `SteadyStateProblem` + `SSRootfind(KINSOL())` |
| SciMLBase | 2.149.0 | Solution types, `NoInit()` | `ReturnCode`, `NonlinearSolution`, `ODESolution` |

### Supporting
No new dependencies needed. Phase 45 uses only existing project dependencies.

**Julia version:** 1.12.5

## Architecture Patterns

### File Structure
```
src/
  components/
    point_kinetics.jl          # NEW: PointKinetics component + point_kinetics_steady_state
  STREAM.jl                    # ADD: include + export lines

test/
  test_point_kinetics.jl       # NEW: PK-01, PK-02 tests
  runtests.jl                  # ADD: include("test_point_kinetics.jl")
```

### Pattern 1: Scalar MTK Parameters from Vector Input (D-01/D-02)

**What:** Constructor accepts `beta_k::Vector` and `lambda_k::Vector`, then generates individual scalar `@parameters beta_1=beta_k[1] beta_2=beta_k[2] ...` inside the function. This avoids MTK array parameter indexing issues.

**How:** Use Julia metaprogramming or a loop to build the parameter list:
```julia
# Inside PointKinetics constructor:
# Build scalar parameters dynamically from input vectors
pars_list = Any[]
beta_syms = []
lambda_syms = []

# Create individual scalar parameters for each group
for k in 1:6
    bk = Symbol("beta_$k")
    lk = Symbol("lambda_$k")
    # ... MTK @parameters for each
end
```

**Recommended approach:** Use `@parameters` with explicit enumeration (6 is a fixed, small number -- no need for metaprogramming complexity):
```julia
pars = @parameters begin
    rho = rho_val
    Lambda_gen = Lambda_val    # "Lambda" may collide with Julia keyword; use Lambda_gen
    beta_1 = beta_k[1]
    beta_2 = beta_k[2]
    beta_3 = beta_k[3]
    beta_4 = beta_k[4]
    beta_5 = beta_k[5]
    beta_6 = beta_k[6]
    lambda_1 = lambda_k[1]
    lambda_2 = lambda_k[2]
    lambda_3 = lambda_k[3]
    lambda_4 = lambda_k[4]
    lambda_5 = lambda_k[5]
    lambda_6 = lambda_k[6]
end
```

**Confidence:** HIGH -- this pattern avoids known MTK array parameter pitfalls. The existing codebase uses explicit scalar parameters throughout (no array `@parameters` anywhere).

### Pattern 2: Observed Variables for Diagnostics (D-05)

**What:** `beta_total`, `dPdt`, and `reactivity` are `@observed` -- computed post-solve, not part of the DAE system.

**How:** Build an `obs` vector of `Equation[]` and pass to `System(...; observed=obs)`, matching the `ChannelAndContacts` pattern:
```julia
obs = Equation[]
push!(obs, beta_total ~ beta_1 + beta_2 + beta_3 + beta_4 + beta_5 + beta_6)
push!(obs, dPdt ~ (rho - beta_total) / Lambda_gen * P + sum(lambda_k * C_k for each k))
push!(obs, reactivity ~ rho)  # Phase 45 only; Phase 47 extends with feedback
```

**Confidence:** HIGH -- directly follows `ChannelAndContacts` pattern at `thermal_channel.jl:158-196`.

### Pattern 3: Component Constructor (no ports, no sub-systems)

**What:** PointKinetics has no FlowPort or ThermalPort -- it is a standalone ODE system. No `compose()` with sub-components needed; just `System(eqs, t, vars, pars; observed=obs, name=name)`.

**How:** Similar to Inertia but even simpler (no ports to compose):
```julia
function PointKinetics(; name, rho=0.0, Lambda=U235_LAMBDA, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K)
    Dt = Differential(t)
    
    # ... @parameters and @variables ...
    
    eqs = Equation[
        Dt(P) ~ (rho - (beta_1 + ... + beta_6)) / Lambda_gen * P + lambda_1*C_1 + ... + lambda_6*C_6,
        Dt(C_1) ~ -lambda_1 * C_1 + beta_1 / Lambda_gen * P,
        # ... C_2 through C_6 ...
    ]
    
    System(eqs, t, vars, pars; observed=obs, name=name)
end
```

**Note:** No `compose()` call needed since there are no sub-systems. This is the simplest component pattern in the codebase.

**Confidence:** HIGH -- `compose` is only needed when combining sub-components (ports, nested systems).

### Pattern 4: Module-Level Constants for U-235 Data (Discretion Area)

**Recommendation:** Use module-level `const` arrays. This is cleaner than embedding literals in the default argument list and allows downstream phases to reference `U235_BETA_K` directly.

```julia
# U-235 6-group delayed neutron data (same as Python STREAM reference)
const U235_LAMBDA = 5.4e-5  # generation time [s]
const U235_LAMBDA_K = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]  # decay rates [1/s]
const U235_BETA_K = [...]  # delayed neutron fractions (need Python STREAM values)
```

**Note on beta_k values:** The Python STREAM test file provides `lambdak` but not `betak` values directly. The betak values are in the Python STREAM source or test fixtures. They must match the Python reference exactly. The standard U-235 6-group values from Keepin (1965) or equivalent should be used. Check the Python STREAM codebase for the exact values used.

**Confidence:** HIGH for the pattern; MEDIUM for exact beta_k numerical values (need to extract from Python STREAM or verify against nuclear data tables).

### Anti-Patterns to Avoid
- **Array MTK parameters:** Do NOT use `(beta(t))[1:6]` or similar array parameters. MTK has known issues with array parameter indexing in equations and with passing array values to `ODEProblem`.
- **Observed-to-observed chains:** Do NOT reference one `@observed` variable inside another observed equation. Inline the expression instead (see `thermal_channel.jl:180` comment about P_i).
- **Lambda name collision:** `Lambda` may shadow Julia's anonymous function syntax in some contexts. Use `Lambda_gen` (generation time) or similar to avoid confusion.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ODE system construction | Manual ODE functions | MTK `@variables`, `@parameters`, `System()` | MTK handles symbolic differentiation, index reduction, sparsity |
| Steady-state solving | Custom Newton solver | `SteadyStateProblem` + `SSRootfind(KINSOL())` | KINSOL handles algebraic constraints, convergence |
| Transient solving | Manual time-stepping | `ODEProblem` + `Rodas5P()` | Stiff solver with adaptive stepping |

**Key insight:** The steady-state IC formula `C_k = beta_k / (lambda_k * Lambda) * P0` is analytical -- no numerical solver needed for `point_kinetics_steady_state`. This is deliberate: KINSOL finds P=0 as trivial solution when given zero ICs, so the analytical helper is essential.

## Common Pitfalls

### Pitfall 1: Trivial Steady-State Solution (P=0)
**What goes wrong:** KINSOL finds `P=0, C_k=0` when given zero or poor initial conditions.
**Why it happens:** The point kinetics equations have a trivial fixed point at P=0. KINSOL converges to the nearest root.
**How to avoid:** Always use `point_kinetics_steady_state(P0, ...)` to compute physically correct ICs before any transient solve.
**Warning signs:** Test 4 in the success criteria explicitly validates this behavior.

### Pitfall 2: MTK Array Parameter Indexing
**What goes wrong:** `beta[k]` in MTK equations produces incorrect symbolic expressions or fails during `mtkcompile`.
**Why it happens:** MTK's symbolic system does not handle array parameter indexing the same way as array variable indexing.
**How to avoid:** Use individual scalar parameters `beta_1, ..., beta_6` (locked decision D-01/D-02).
**Warning signs:** Errors during `mtkcompile` or incorrect numerical values in solution.

### Pitfall 3: Observed Variable Chains
**What goes wrong:** If `dPdt` references `beta_total` as an observed symbol, MTK may fail to resolve the chain.
**Why it happens:** MTK does not support observed-to-observed variable references in all contexts.
**How to avoid:** Inline `beta_total` expression directly in `dPdt` equation: `dPdt ~ (rho - (beta_1 + ... + beta_6)) / Lambda_gen * P + ...`
**Warning signs:** Errors during solution indexing like `sol[ssys.pk.dPdt]`.

### Pitfall 4: Variable Naming for P (Power)
**What goes wrong:** `P` symbol may collide with pressure `P` used elsewhere in the codebase (channels use `P[i]` for pressure).
**Why it happens:** MTK scopes variables by system name, so `pk.P` and `ch.P[1]` are distinct. But within the component file, confusion is possible.
**How to avoid:** The component is standalone (Phase 45 has no ports), so no collision occurs. When coupled (Phase 48), MTK's namespace `pk.P` vs `ch.P[i]` keeps them distinct. Use clear docstring noting `P` is power [W], not pressure.
**Warning signs:** None expected in Phase 45; only relevant in Phase 48 coupling.

### Pitfall 5: Precursor Decay Test Setup
**What goes wrong:** Test uses wrong analytical formula or incorrect ODE setup.
**Why it happens:** The Python STREAM test uses `beta_k = zeros(6)` (not the real beta values) and `rho = 0` for the decay test. This zeroes out the delayed neutron production term, making precursors decay independently.
**How to avoid:** Follow the Python STREAM test exactly: construct PointKinetics with `beta_k = zeros(6)`, `rho = 0.0`. The analytical solution is:
- `C_k(t) = C_k(0) * exp(-lambda_k * t)` (independent exponential decay)
- `P(t) = P(0) + sum_k(C_k(0) * (1 - exp(-lambda_k * t)))` (power absorbs released precursors)
**Warning signs:** rtol > 1e-3 between numerical and analytical solutions.

## Code Examples

### PointKinetics Component Structure
```julia
# Source: established codebase patterns (Inertia, ChannelAndContacts)
# U-235 6-group delayed neutron data
const U235_LAMBDA = 5.4e-5  # generation time [s]
const U235_LAMBDA_K = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]  # decay rates [1/s]
const U235_BETA_K = [...]  # delayed neutron fractions -- extract from Python STREAM

function PointKinetics(; name, rho=0.0, Lambda=U235_LAMBDA,
                         beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K)
    Dt = Differential(t)
    
    pars = @parameters begin
        rho = rho
        Lambda_gen = Lambda
        beta_1 = beta_k[1]; beta_2 = beta_k[2]; beta_3 = beta_k[3]
        beta_4 = beta_k[4]; beta_5 = beta_k[5]; beta_6 = beta_k[6]
        lambda_1 = lambda_k[1]; lambda_2 = lambda_k[2]; lambda_3 = lambda_k[3]
        lambda_4 = lambda_k[4]; lambda_5 = lambda_k[5]; lambda_6 = lambda_k[6]
    end
    
    vars = @variables begin
        P(t) = 1.0          # power [W]
        C_1(t); C_2(t); C_3(t); C_4(t); C_5(t); C_6(t)
    end
    
    beta_sum = beta_1 + beta_2 + beta_3 + beta_4 + beta_5 + beta_6
    
    eqs = Equation[
        Dt(P) ~ (rho - beta_sum) / Lambda_gen * P +
                 lambda_1*C_1 + lambda_2*C_2 + lambda_3*C_3 +
                 lambda_4*C_4 + lambda_5*C_5 + lambda_6*C_6,
        Dt(C_1) ~ -lambda_1*C_1 + beta_1/Lambda_gen * P,
        Dt(C_2) ~ -lambda_2*C_2 + beta_2/Lambda_gen * P,
        Dt(C_3) ~ -lambda_3*C_3 + beta_3/Lambda_gen * P,
        Dt(C_4) ~ -lambda_4*C_4 + beta_4/Lambda_gen * P,
        Dt(C_5) ~ -lambda_5*C_5 + beta_5/Lambda_gen * P,
        Dt(C_6) ~ -lambda_6*C_6 + beta_6/Lambda_gen * P,
    ]
    
    obs = Equation[
        beta_total ~ beta_sum,
        dPdt ~ (rho - beta_sum) / Lambda_gen * P +
               lambda_1*C_1 + lambda_2*C_2 + lambda_3*C_3 +
               lambda_4*C_4 + lambda_5*C_5 + lambda_6*C_6,
        reactivity ~ rho,
    ]
    
    System(eqs, t, [P, C_1, C_2, C_3, C_4, C_5, C_6], pars;
           observed=obs, name=name)
end
```

### Steady-State IC Helper
```julia
# Source: PK-02 formula, verified against Python STREAM ODE steady-state
function point_kinetics_steady_state(P0; Lambda=U235_LAMBDA,
                                       beta_k=U235_BETA_K,
                                       lambda_k=U235_LAMBDA_K)
    # At criticality (rho=0, dC_k/dt=0): C_k = beta_k / (lambda_k * Lambda) * P0
    C_k = [beta_k[i] / (lambda_k[i] * Lambda) * P0 for i in 1:length(beta_k)]
    return (P=P0, C_k=C_k)
end
```

### Test: Precursor-Only Decay (PK-01 validation)
```julia
# Source: Python STREAM test_point_kinetics.py::test_precursor_death
# With beta_k=zeros(6) and rho=0:
#   dP/dt = sum(lambda_k * C_k)    (no delayed neutron production)
#   dC_k/dt = -lambda_k * C_k       (pure exponential decay)
# Analytical: P(t) = P0 + sum(C_k0 * (1 - exp(-lambda_k * t)))
@named pk = PointKinetics(rho=0.0, beta_k=zeros(6))
ssys = mtkcompile(pk)
P0 = 10.0; C_k0 = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
op = [ssys.P => P0, ssys.C_1 => C_k0[1], ...]
t_span = range(0, 100, length=500)
sol = solve_transient(ssys, op, t_span)
# Compare sol[ssys.P, :] against analytical P(t)
```

### Test: Zero ICs Yield Trivial Solution (Success Criterion 4)
```julia
# Passing all-zero ICs should give P=0 steady state
@named pk = PointKinetics(rho=0.0)
ssys = mtkcompile(pk)
op = [ssys.P => 0.0, ssys.C_1 => 0.0, ...]  # all zeros
sol = solve_steady(ssys, op)
@test abs(sol[ssys.P]) < 1e-10  # trivial solution
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test (stdlib) |
| Config file | test/runtests.jl (thin orchestrator) |
| Quick run command | `julia --project=. -e 'using Pkg; Pkg.test(test_args=["test_point_kinetics"])'` |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

**Note:** The quick-run command may not work with test_args filtering unless runtests.jl supports it. Alternative: `julia --project=. test/test_point_kinetics.jl` (direct include after loading the module).

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PK-01a | PointKinetics compiles with mtkcompile, has 7 state variables | unit | `julia --project=. -e 'include("test/test_point_kinetics.jl")'` | Wave 0 |
| PK-01b | Precursor-only decay matches analytical solution (rtol <= 1e-3) | integration | same | Wave 0 |
| PK-01c | Zero ICs yield trivial P=0 solution (confirms IC helper is essential) | integration | same | Wave 0 |
| PK-02 | `point_kinetics_steady_state` returns C_k matching formula (rtol <= 1e-3) | unit | same | Wave 0 |

### Sampling Rate
- **Per task commit:** Run `test/test_point_kinetics.jl` only
- **Per wave merge:** Full test suite `Pkg.test()`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/test_point_kinetics.jl` -- covers PK-01, PK-02 (4 test cases)
- No framework install needed -- Julia Test is stdlib

## Project Constraints (from CLAUDE.md)

- **File placement:** New component -> `src/components/point_kinetics.jl` (confirmed by CLAUDE.md rule)
- **Exports:** All public exports declared in `src/STREAM.jl` only -- never in component files
- **name kwarg:** Always keyword-only (injected by `@named` macro)
- **Keyword constructor:** Multi-parameter components use keyword-only (PointKinetics has many Float64 params)
- **Docstring:** Every exported name needs docstring with `# Arguments`, `# Returns`
- **ASCII variable names:** No Unicode (use `Lambda_gen` not a lambda symbol)
- **@observed for diagnostics:** `beta_total`, `dPdt`, `reactivity` are diagnostic -- never referenced on RHS of another equation
- **mtkcompile before solve:** Always call `mtkcompile(sys)` before solving
- **Internal helpers:** Prefix with `_` and do not export

## Open Questions

1. **U-235 beta_k exact values**
   - What we know: `lambda_k = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]` from Python STREAM test
   - What's unclear: Exact `beta_k` values used in Python STREAM (not in the test file, likely in a fixture or the PointKinetics constructor defaults)
   - Recommendation: Check Python STREAM source for default `delayed_neutron_fractions`. Standard Keepin (1965) U-235 thermal values are: `[0.000215, 0.001424, 0.001274, 0.002568, 0.000748, 0.000273]` (beta_total ~ 0.0065). Verify against Python reference before hardcoding.

2. **MTK @parameters block syntax for 14 parameters**
   - What we know: `@parameters begin ... end` block syntax works for multiple parameters
   - What's unclear: Whether 14 parameters in a single `@parameters` block compiles correctly (largest existing is 4 in ChannelAndContacts)
   - Recommendation: LOW risk -- MTK handles arbitrary parameter counts. If issues arise, split into two `@parameters` blocks and concatenate.

3. **`observed` variables declaration syntax**
   - What we know: `beta_total`, `dPdt`, `reactivity` need to be declared as `@variables` but passed to `observed=` kwarg of `System`
   - What's unclear: Whether observed variables need default values or if they can be left uninitialized
   - Recommendation: Declare them in `@variables` without defaults (existing pattern in thermal_channel.jl). They go into `obs` Equation list, NOT into `vars` list passed to `System`.

## Sources

### Primary (HIGH confidence)
- `src/components/thermal_channel.jl` -- `@observed` pattern, `System(...; observed=obs)` usage
- `src/components/misc.jl` -- Simple component pattern (Inertia, HeatExchanger)
- `src/components/pump.jl` -- Callable parameter pattern (Phase 46 reference)
- `src/solvers.jl` -- `solve_steady`, `solve_transient`, `NoInit()` usage
- `~/projects/STREAM/stream/calculations/point_kinetics.py` -- Canonical ODE formulation, matrix structure
- `~/projects/STREAM/tests/test_calculations/test_point_kinetics.py` -- Precursor decay test, lambdak values

### Secondary (MEDIUM confidence)
- Python STREAM `save()` method (lines 319-343) -- confirms `reactivity`, `dPdt` as diagnostic outputs
- CLAUDE.md component authoring conventions -- keyword-only rule, docstring requirements

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already in project, versions verified
- Architecture: HIGH -- follows established codebase patterns exactly
- Pitfalls: HIGH -- well-known issues (trivial solution, array params) with clear mitigations
- Nuclear data values: MEDIUM -- lambda_k confirmed from Python tests, beta_k needs extraction

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable domain -- nuclear data and MTK patterns don't change frequently)

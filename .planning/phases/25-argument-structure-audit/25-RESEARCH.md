# Phase 25: Argument Structure Audit - Research

**Researched:** 2026-03-26
**Domain:** Julia function/constructor API design — positional vs keyword arguments, MTK `@named` macro convention
**Confidence:** HIGH

## Summary

This phase is a pure API consistency pass with no new features. All decisions are fully locked in CONTEXT.md. Research is therefore an inventory exercise: catalog every call site that will break, confirm the exact new signatures to write, and map the scope of docstring updates.

The change set is small but touches many files. The primary risk is missing a call site — particularly in test files that are not listed in the canonical refs. The complete grep audit below surfaces every affected call site across the entire codebase.

The `@named` macro is the single inviolable constraint. `@named foo = Component(args; name)` injects `name=:foo` as a keyword argument before calling the constructor. Positional physics args go before the semicolon; `name` stays after it, always keyword. This is already demonstrated by `Pump(dP_pump::Real; name)` in `src/components/pump.jl` — the exact pattern to replicate.

**Primary recommendation:** Change 6 signatures (5 components + 1 factory), update ~60 call sites across 14 files, update CLAUDE.md. No backward-compat shims. Plan as two tasks: (1) signature changes + docstrings, (2) call site migration + test run.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Five components get positional physics parameters: `Resistor(R; name)`, `Gravity(H; name)`, `Inertia(L_over_A; name)`, `HeatExchanger(T_bc; name)`, `ConstantTemperature(T; name)`
- **D-02:** The `name` kwarg stays keyword-only (always provided by `@named` macro — not negotiable)
- **D-03:** All call sites in `test/` and `src/examples.jl` updated. No backward-compat shim. MethodError forces migration (same policy as v0.4 PipeGeometry).
- **D-04:** `laminar_friction(aspect_ratio::Real)` becomes positional (single typed required arg, role is unambiguous)
- **D-05:** `constant_Nusselt(; Nu=8.235)` stays keyword-only (has a default value; `Nu=` label is informative)
- **D-06:** `elenbaas_htc(; b, L, Dh, g=9.81)` stays keyword-only (4 args all Float64, labeling prevents order confusion)
- **D-07:** `regime_dependent(; ...)` stays keyword-only (complex multi-arg factory with many optionals)
- **D-08:** `Pump` dispatch — already correct, no changes
- **D-09..D-14:** Dimensionless utilities, standalone correlation fns, PipeGeometry factories, composition helpers, solver fns, complex constructors — all already correct or intentionally keyword-only, no changes

### CLAUDE.md Rule Update (D-15)
Replace "All component constructor arguments are keyword-only" with a two-tier rule:
- **Positional when:** (a) argument type determines behavior enabling multiple dispatch, OR (b) constructor/function has ≤1 physics parameter and its role is unambiguous from the function name
- **Keyword when:** multiple arguments of the same type (labeling prevents order bugs), OR complex constructors with many parameters
- The `name` kwarg is always keyword-only

### Claude's Discretion

- Exact order of keyword vs positional in updated signatures (but `name` stays keyword-always)
- Whether to update docstrings to reflect new signatures
- Internal `_channel_base_eqs`, `_diffusion_eqs` — `_`-prefixed helpers; apply positional where natural (SC#2), but not exported

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

## Standard Stack

No new dependencies. This phase uses only what is already installed: Julia, ModelingToolkit.jl, the `@named` macro.

### The `@named` Macro Pattern (HIGH confidence)
`@named` rewrites `@named foo = Component(args; name)` to `foo = Component(args; name=:foo)`. The macro always passes `name` as a keyword argument. Positional args go before the semicolon in the function signature; `name` always stays after it:

```julia
# Correct: positional physics arg, keyword name
function Resistor(R; name)
    ...
end

# Usage
@named r = Resistor(1.0e5)  # @named injects name=:r
```

This is the established pattern already demonstrated by `Pump` in `src/components/pump.jl`.

## Architecture Patterns

### Pattern 1: Single positional physics arg + keyword `name`

The model is `Pump(dP_pump::Real; name)` in `src/components/pump.jl:42`.

```julia
# Before (keyword-only)
function Resistor(; name, R)
    pars = @parameters R = R
    ...
end

# After (positional physics arg)
function Resistor(R; name)
    pars = @parameters R = R
    ...
end
```

Call site changes mirror the v0.4 PipeGeometry migration pattern — old form deleted, MethodError forces callers to update:

```julia
# Before
@named r = Resistor(R=1.0e5)

# After
@named r = Resistor(1.0e5)
```

### Pattern 2: `laminar_friction` factory — positional with type annotation

```julia
# Before
function laminar_friction(; aspect_ratio::Real)
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end

# After
function laminar_friction(aspect_ratio::Real)
    k_R = rectangular_laminar_correction(aspect_ratio)
    return (Re) -> 64.0 / (Re * k_R)
end
```

Call site:
```julia
# Before
laminar_friction(aspect_ratio=0.01814)

# After
laminar_friction(0.01814)
```

### Pattern 3: `ConstantTemperature` — parameter name differs from argument name

Current code uses `T_bc` as the parameter name internally, but the argument is named `T`. After migration:

```julia
# After (positional T, internal parameter name unchanged)
function ConstantTemperature(T; name)
    pars = @parameters T_bc = T
    @named thermal = ThermalPort()
    compose(System([thermal.T ~ T_bc], t; name=name), thermal)
end
```

Call sites currently use `ConstantTemperature(name=Symbol(...), T=value)` — note the `name` kwarg is passed explicitly (not via `@named`) in array comprehensions. These must migrate to `ConstantTemperature(value; name=Symbol(...))`.

### Anti-Patterns to Avoid

- **Removing type annotation from `laminar_friction`:** The `::Real` type annotation should be retained in the positional signature — it serves as documentation and enables dispatch if a symbolic overload is ever needed.
- **Making `name` positional:** Never. The `@named` macro requires it to be keyword.
- **Adding a backward-compat shim:** Decision D-03 explicitly forbids this. MethodError is the intended migration signal.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting `@named` call sites | Custom AST walker | grep for old keyword call patterns | Simple text search is sufficient |
| Migration shim | Two-method dispatch with deprecation warning | Delete old form immediately | D-03 explicitly says no shim |

## Common Pitfalls

### Pitfall 1: ConstantTemperature call sites use explicit `name=` kwarg in array comprehensions

**What goes wrong:** Many ConstantTemperature call sites are in array comprehensions and pass `name` explicitly without the `@named` macro:
```julia
ct_l = [ConstantTemperature(name=Symbol(:ct_l, i), T=T_bc) for i in 1:nz]
```
These cannot use `@named` because the name is dynamic. After migration they become:
```julia
ct_l = [ConstantTemperature(T_bc; name=Symbol(:ct_l, i)) for i in 1:nz]
```
This form is valid Julia — positional args with explicit keyword. The `@named` macro is just syntactic sugar for the common static-name case.

**Why it happens:** The `@named` macro is not the only way to pass `name` — it is shorthand. Dynamic names must still be passed as `name=...` directly.

**How to avoid:** When updating ConstantTemperature call sites, check both `@named ct = ConstantTemperature(...)` and `ConstantTemperature(name=..., T=...)` patterns.

**Warning signs:** grep for `ConstantTemperature(name=` to find comprehension-style call sites.

### Pitfall 2: Missing call sites in test files not listed in canonical refs

**What goes wrong:** CONTEXT.md lists 4 test files as primary targets, but the complete grep audit reveals additional call sites in `test_channel.jl`, `test_sign_safety.jl`, `test_flapper.jl`, `test_pump.jl`, `test_correlations.jl`, `test_heat_diffusion.jl`, `test_validation.jl`, `test_loss_of_flow.jl`.

**Why it happens:** Many test files construct full loops that use `HeatExchanger`, `ConstantTemperature`, `Resistor`, `Inertia`.

**How to avoid:** Use the complete call-site inventory in the Code Examples section below. Update ALL files, not just the 4 listed in canonical refs.

### Pitfall 3: Docstring signature line must also be updated

**What goes wrong:** Docstring's first line shows the old signature. After changing the function signature, the docstring `Resistor(; name, R)` becomes wrong.

**How to avoid:** For each changed function, update both the function signature AND the first line of the docstring to match.

## Code Examples

### Complete Call-Site Inventory

All files requiring changes are listed below with their current (old) call forms and the required (new) forms.

#### `src/components/resistors.jl`

| Function | Old signature | New signature |
|----------|--------------|---------------|
| `Resistor` | `Resistor(; name, R)` | `Resistor(R; name)` |
| `Gravity` | `Gravity(; name, H)` | `Gravity(H; name)` |

#### `src/components/misc.jl`

| Function | Old signature | New signature |
|----------|--------------|---------------|
| `Inertia` | `Inertia(; name, L_over_A)` | `Inertia(L_over_A; name)` |
| `HeatExchanger` | `HeatExchanger(; name, T_bc)` | `HeatExchanger(T_bc; name)` |
| `ConstantTemperature` | `ConstantTemperature(; name, T)` | `ConstantTemperature(T; name)` |

#### `src/physical_models/correlations.jl`

| Function | Old signature | New signature |
|----------|--------------|---------------|
| `laminar_friction` | `laminar_friction(; aspect_ratio::Real)` | `laminar_friction(aspect_ratio::Real)` |

#### Call sites — `src/examples.jl` (lines found in audit)

```julia
# Old → New
HeatExchanger(T_bc = T_inlet)     → HeatExchanger(T_inlet)
HeatExchanger(T_bc=T_inlet)       → HeatExchanger(T_inlet)
HeatExchanger(T_bc=T_inlet)       → HeatExchanger(T_inlet)
Gravity(H = H)                     → Gravity(H)
Resistor(R=R)                      → Resistor(R)    # 9 occurrences (build_cube)
Inertia(L_over_A=L_over_A)         → Inertia(L_over_A)
Resistor(R=R_ext)                  → Resistor(R_ext)
```

#### Call sites — `test/test_resistors.jl`

```julia
Resistor(R=1.0e5)  → Resistor(1.0e5)  # 2 occurrences
```

#### Call sites — `test/test_misc.jl`

```julia
Inertia(L_over_A=1e3)         → Inertia(1e3)      # 2 occurrences
Inertia(L_over_A=L_over_A)    → Inertia(L_over_A)
Resistor(R=R_val)              → Resistor(R_val)
HeatExchanger(T_bc=313.15)    → HeatExchanger(313.15)  # 2 occurrences
```

#### Call sites — `test/test_channel.jl`

```julia
Gravity(H=3.0)                 → Gravity(3.0)
HeatExchanger(T_bc=T_inlet)   → HeatExchanger(T_inlet)  # 4 occurrences
ConstantTemperature(name=Symbol(:ct_l, i), T=T_wall)   → ConstantTemperature(T_wall; name=Symbol(:ct_l, i))  # array comprehension
ConstantTemperature(name=Symbol(:ct_r, i), T=T_wall)   → ConstantTemperature(T_wall; name=Symbol(:ct_r, i))
ConstantTemperature(name=Symbol(:ct2_, i), T=T_wall)   → ConstantTemperature(T_wall; name=Symbol(:ct2_, i))
ConstantTemperature(T=373.15)  → ConstantTemperature(373.15)  # @named form
```

#### Call sites — `test/test_composition.jl`

```julia
HeatExchanger(T_bc=T_inlet_qol)   → HeatExchanger(T_inlet_qol)  # ~10 occurrences
ConstantTemperature(name=Symbol(...), T=T_wall_qol)  → ConstantTemperature(T_wall_qol; name=Symbol(...))  # array comprehensions
laminar_friction(aspect_ratio=0.0025/0.070)  → laminar_friction(0.0025/0.070)  # 6 occurrences
```

#### Call sites — `test/test_correlations.jl`

```julia
laminar_friction(aspect_ratio=0.01814)  → laminar_friction(0.01814)  # 2 occurrences
laminar_friction(aspect_ratio=geom.depth/geom.width)  → laminar_friction(geom.depth/geom.width)  # 4 occurrences
HeatExchanger(T_bc=T_inlet)  → HeatExchanger(T_inlet)  # 6 occurrences
ConstantTemperature(name=Symbol(...), T=T_wall)  → ConstantTemperature(T_wall; name=Symbol(...))  # 6 array comprehensions
```

#### Call sites — `test/test_flapper.jl`

```julia
Resistor(R=1e5)              → Resistor(1e5)     # 2 occurrences
Inertia(L_over_A=L_over_A)  → Inertia(L_over_A)
```

#### Call sites — `test/test_pump.jl`

```julia
HeatExchanger(T_bc=313.15)  → HeatExchanger(313.15)  # 2 occurrences
Inertia(L_over_A=L_over_A)  → Inertia(L_over_A)
Resistor(R=R_val)            → Resistor(R_val)
```

#### Call sites — `test/test_sign_safety.jl`

```julia
HeatExchanger(T_bc=T_inlet_sign)  → HeatExchanger(T_inlet_sign)  # 3 occurrences
ConstantTemperature(name=Symbol(:ct_l, i), T=T_wall_sign)  → ConstantTemperature(T_wall_sign; name=Symbol(:ct_l, i))
ConstantTemperature(name=Symbol(:ct_r, i), T=T_wall_sign)  → ConstantTemperature(T_wall_sign; name=Symbol(:ct_r, i))
```

#### Call sites — `test/test_heat_diffusion.jl`

```julia
ConstantTemperature(name=Symbol(:ct_l, i), T=T_bc)   → ConstantTemperature(T_bc; name=Symbol(:ct_l, i))
ConstantTemperature(name=Symbol(:ct_r, i), T=T_bc)   → ConstantTemperature(T_bc; name=Symbol(:ct_r, i))
ConstantTemperature(name=Symbol(:ct5_l, i), T=T_bc)  → ConstantTemperature(T_bc; name=Symbol(:ct5_l, i))
ConstantTemperature(name=Symbol(:ct12_l, i), T=T_bc) → ConstantTemperature(T_bc; name=Symbol(:ct12_l, i))
ConstantTemperature(name=Symbol(:ct12_r, i), T=T_bc) → ConstantTemperature(T_bc; name=Symbol(:ct12_r, i))
```

#### Call sites — `test/test_validation.jl`

```julia
HeatExchanger(T_bc=T_in_l)   → HeatExchanger(T_in_l)  # several occurrences
HeatExchanger(T_bc=T_in_r)   → HeatExchanger(T_in_r)
HeatExchanger(T_bc=T_in)     → HeatExchanger(T_in)
HeatExchanger(T_bc=T_in_v02) → HeatExchanger(T_in_v02)
ConstantTemperature(name=Symbol(:ct_l_, i), T=T_wall)  → ConstantTemperature(T_wall; name=Symbol(:ct_l_, i))
ConstantTemperature(name=Symbol(:ct_r_, i), T=T_wall)  → ConstantTemperature(T_wall; name=Symbol(:ct_r_, i))
```

#### Call sites — `test/test_loss_of_flow.jl`

```julia
HeatExchanger(T_bc=BYPASS_T_INLET)  → HeatExchanger(BYPASS_T_INLET)
```

#### Files with NO changes required (confirmed by audit)

- `test/test_geometry.jl` — no affected constructors
- `test/test_connectors.jl` — no affected constructors
- `test/test_fluids.jl` — no affected constructors
- `test/test_solvers.jl` — no direct component construction (uses `build_loop*` helpers from examples.jl)
- `test/test_examples.jl` — calls `build_loop*` helpers, no direct construction
- `src/STREAM.jl` — exports only, no call sites
- `src/components/pump.jl` — already correct pattern, not changed
- Python reference scripts (`test/generate_*.py`) — not Julia, not affected

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + runtests.jl |
| Config file | `test/runtests.jl` |
| Quick run command | `cd /home/itay/projects/Julia-STREAM && julia --project test/runtests.jl` |
| Full suite command | same (no separate quick/full distinction) |

### Phase Requirements → Test Map

This phase has no formal requirement IDs. Success criteria are verified by the test suite passing after all call site migrations.

| Success Criterion | How Verified |
|------------------|--------------|
| SC#1: Type-dispatch functions use positional args | Test suite compiles and passes (MethodError would surface any missed site) |
| SC#2: Utility/helper functions use positional | Code review + grep confirms no remaining `fn(; single_arg)` patterns |
| SC#3: Complex multi-arg constructors stay keyword-only | No regression — existing tests pass unchanged |
| SC#4: CLAUDE.md updated | Manual verification of CLAUDE.md content |

### Sampling Rate

- **Per task commit:** `julia --project test/runtests.jl`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure covers all success criteria. No new test files needed.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| All constructor args keyword-only | Two-tier: positional for ≤1 physics param, keyword for multi-param | Phase 25 | Call sites must migrate |
| `Pump(dP_pump=x; name)` | `Pump(x; name)` | Phase 22 | Already migrated |
| `PipeGeometry_rectangular(L=x, e1=y, ...)` | positional factory | Phase v0.4 | Already migrated |

## Open Questions

None — all decisions are locked. The only discretionary items (docstring updates, internal helpers) are minor and can be decided at implementation time.

## Environment Availability

Step 2.6: SKIPPED (no external dependencies — this is a pure code refactor with no CLI tools, databases, or services).

## Sources

### Primary (HIGH confidence)

- Direct source code audit: `src/components/resistors.jl`, `src/components/misc.jl`, `src/physical_models/correlations.jl`, `src/components/pump.jl`
- Complete call-site grep across entire `src/` and `test/` tree
- CONTEXT.md decisions — fully locked by prior discussion session

### Secondary (MEDIUM confidence)

- Julia language documentation on keyword vs positional arguments — standard Julia behavior, no external verification needed for this well-established language feature
- MTK `@named` macro behavior — confirmed by existing `Pump` usage pattern in codebase

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all patterns from existing codebase
- Architecture: HIGH — exact pattern already demonstrated by `Pump`; full call-site inventory complete
- Pitfalls: HIGH — discovered through direct source inspection, not guesswork

**Research date:** 2026-03-26
**Valid until:** Indefinite (stable language feature; no external dependencies)

# Phase 27: Pressure Field - Research

**Researched:** 2026-03-28
**Domain:** MTK channel component refactoring, fluid property functions, per-cell pressure observables
**Confidence:** HIGH

## Summary

Phase 27 refactors the scalar dP equation in all three channel variants (Channel, ChannelAndContacts, ChannelHeatFlux) into per-cell pressure drops dp[i], exposes absolute pressure P[i] as observed variables, and adds sat_temperature and Bergles-Rohsenow dT_ONB functions for downstream safety analysis.

All decisions are locked in CONTEXT.md with high specificity. The implementation touches 6 source files and 1 test file. The patterns are well-established in the codebase: `@register_symbolic` for fluid functions, `@observed` for diagnostic variables, per-cell loops pushing to `eqs`/`obs` vectors, and `sum(expr for i in 1:n)` for symbolic summation.

**Primary recommendation:** Implement in two waves: (1) dp[i]/P[i] refactor + sat_temperature function, (2) T_sat[i]/T_ONB[i] observables in thermal channels. The dp refactor is the structural risk; saturation observables are additive.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: dp(t)[1:n] are MTK unknowns (not @observed) -- they appear on the RHS of port wiring
- D-02: Per-cell equation includes friction + gravity + inertia split equally across cells
- D-03: Port wiring uses -sum(dp[i]) instead of -dP
- D-04: dP becomes @observed alias: dP ~ sum(dp[i])
- D-05: P(t)[1:n] are @observed in all three channel variants
- D-06: P[i] uses local cumsum expression, not chained observed-to-observed
- D-07: P[i] is absolute pressure, requires pressure anchor in loop
- D-08: sat_temperature(P_Pa) in src/fluids.jl with @register_symbolic, takes Pa, returns K
- D-09: Simantov correlation verbatim from Python STREAM light_water.py
- D-10: T_sat[i] and T_ONB[i] in ChannelAndContacts and ChannelHeatFlux only (not Channel)
- D-11: T_sat/T_ONB reference dp[j] unknowns directly via local P_i expression
- D-12: q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)
- D-13: _bergles_rohsenow_dT_ONB private helper in correlations.jl
- D-14: _channel_base_eqs gains dp array parameter; dP observed pushed by caller
- D-15: ChannelHeatFlux dp[i] equations go to eqs regardless of observed_mode

### Claude's Discretion
- Exact Julia variable name for cumsum local (P_i vs P_abs_i etc.)
- Whether to declare dp(t)[1:n] in @variables block inside each channel or pass from outside
- Test pressure anchor value (any absolute pressure is correct)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| PRES-01 | Per-cell dp[i] replacing single i_mid lump; dP = sum(dp[i]) exactly | D-01 through D-04, D-14, D-15 -- _channel_base_eqs refactor pattern documented |
| PRES-02 | Per-cell absolute pressure P[i] as observed in all 3 channel variants | D-05, D-06, D-07 -- cumsum pattern and anchor requirement documented |
| PRES-03 | sat_temperature(P) as @register_symbolic in fluids.jl | D-08, D-09 -- Simantov coefficients verified against Python STREAM source |
| PRES-04 | T_sat[i] and T_ONB[i] observables in ChannelAndContacts and ChannelHeatFlux | D-10, D-11, D-12, D-13 -- Bergles-Rohsenow formula verified against Python STREAM |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- New fluid function (sat_temperature) goes in `src/fluids.jl` with `@register_symbolic` at module top-level
- New correlation helper (_bergles_rohsenow_dT_ONB) goes in `src/physical_models/correlations.jl`
- No Unicode variable names (use ascii only)
- `name` kwarg is always keyword-only
- Internal helpers prefixed with `_` and not exported
- All public exports declared in `STREAM.jl`, never inside component files
- Every exported name has a docstring (sat_temperature must have one)
- `@observed` for diagnostics never on RHS of another equation; P[i] qualifies since it is observed-only
- `ifelse()` for symbolic conditionals (not if/else)
- Test file mirrors src file: changes to channel.jl/thermal_channel.jl -> test_channel.jl

## Architecture Patterns

### Current dP Equation (to be replaced)
```
channel.jl line 89-92:
  dP ~ f_ch * (mdot * |mdot| / (2*rho[i_mid]*A^2)) * (L/Dh)
     + rho[i_mid] * g_acc * L
     + (L/A) * Dt(inlet.mdot)

_channel_base_eqs line 159-162:
  identical formula using i_mid = max(1, n / 2)
```

### New Per-Cell Pattern (D-02)
```julia
# In _channel_base_eqs, for each cell i in 1:n:
push!(eqs, dp[i] ~ friction_correlation(Re_i) *
    (inlet.mdot * abs(inlet.mdot) / (2 * rho_water(T[i]) * A^2)) * (dz / Dh)
    + rho_water(T[i]) * g_acc * dz
    + (dz / A) * Dt(inlet.mdot))
```

Key change: `L` replaced by `dz = L/n` in each term. Friction is evaluated per-cell using local T[i] instead of T[i_mid]. Inertia term `(dz/A)*Dt(mdot)` sums to `(L/A)*Dt(mdot)` over n cells.

### Per-Cell Re for Friction
Currently, friction uses `Re_mean` at `i_mid`. The new per-cell approach needs per-cell friction evaluation. Two sub-patterns depending on channel type:

**Channel and ChannelHeatFlux (observed_mode=false):** Re[i] is already a solver unknown, so `friction_correlation(Re[i])` works directly inside _channel_base_eqs.

**ChannelAndContacts (observed_mode=true):** Re[i] is observed (not unknown). Must compute `Re_i` as an inlined expression (same as current h_tc inlining pattern on line 139 of channel.jl): `Re_i = abs(inlet.mdot) * Dh / (A * mu_water(T[i]))`.

### P[i] Observed Pattern
```julia
obs = Equation[]
for i in 1:n
    P_i = inlet.P - sum(dp[j] for j in 1:i)
    push!(obs, P[i] ~ P_i)
end
```

### dP Observed Alias
```julia
push!(obs, dP ~ sum(dp[i] for i in 1:n))
```

### @register_symbolic Pattern (existing, from fluids.jl)
```julia
function sat_temperature(P_Pa::Real)
    X = log(abs(P_Pa) * 1e-6)
    A = 179.9600321
    B = -0.1063030
    C = 24.2278298
    D = 2.951e-4
    T_C = (A + C * X) / (1 + B * X + D * X^2)
    return T_C + 273.15
end
@register_symbolic sat_temperature(P::Real)
```

### Bergles-Rohsenow Pattern
```julia
# In correlations.jl (private, not exported)
function _bergles_rohsenow_dT_ONB(P_Pa, q_spl)
    p = P_Pa / 1e5
    return 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)
end
```

Note: This is NOT @register_symbolic. It will be called inline in observed equations where P_i and q_spl are already symbolic expressions. The plain arithmetic traces through symbolically (same pattern as dittus_boelter and blasius_friction in correlations.jl).

### Files Modified

| File | Changes |
|------|---------|
| `src/fluids.jl` | Add sat_temperature function + @register_symbolic |
| `src/physical_models/correlations.jl` | Add _bergles_rohsenow_dT_ONB helper |
| `src/components/channel.jl` | (a) Channel: add dp[1:n] vars, replace dP equation with dp[i] loop, add P[i]/dP observed, update all_vars. (b) _channel_base_eqs: accept dp param, replace scalar dP with per-cell dp[i] equations, change port wiring to use sum(dp) |
| `src/components/thermal_channel.jl` | ChannelAndContacts: add dp/P/T_sat/T_ONB vars, pass dp to base_eqs, build obs for P[i]/T_sat[i]/T_ONB[i]/dP. ChannelHeatFlux: add dp/P vars, pass dp to base_eqs, build obs for P[i]/dP |
| `src/STREAM.jl` | Export sat_temperature |
| `test/test_channel.jl` | Add PRES-01..04 test sets |

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Symbolic cumsum for P[i] | A cumsum utility function | Inline `sum(dp[j] for j in 1:i)` in the loop | MTK handles symbolic sum correctly; a utility adds indirection for no benefit |
| Saturation temperature | Custom fit or table lookup | Simantov correlation from Python STREAM verbatim | Proven correlation, matched coefficients, cross-validation possible |
| T_ONB | Custom derivation | Bergles-Rohsenow formula verbatim from Python STREAM | Established correlation, exact match enables validation |

## Common Pitfalls

### Pitfall 1: Observed-to-Observed Chain
**What goes wrong:** If T_sat[i] references P[i] (an observed), MTK may fail to resolve the evaluation order or silently produce NaN.
**Why it happens:** MTK observeds are computed post-solve; referencing one observed from another creates an ordering dependency that may not be satisfied.
**How to avoid:** D-06/D-11 mandate using `P_i = inlet.P - sum(dp[j] for j in 1:i)` (the same expression, not the P[i] symbol) in T_sat and T_ONB equations.
**Warning signs:** NaN in T_sat values while P[i] values are correct.

### Pitfall 2: dP Must Leave all_vars (Unknown List)
**What goes wrong:** If dP remains in `all_vars` (unknowns) AND is also pushed to `obs` (observed), MTK will error on conflicting variable classification.
**Why it happens:** D-04 makes dP observed. The old code has dP in all_vars.
**How to avoid:** Remove dP from all_vars; add dp[1:n] instead. dP goes only in obs.
**Warning signs:** MTK structural analysis error mentioning duplicate variable or conflicting observed/unknown.

### Pitfall 3: Channel (non-thermal) Gets Too Many Observables
**What goes wrong:** Adding T_sat/T_ONB to Channel which has no per-cell thermal port and no meaningful q_wall for T_ONB.
**Why it happens:** Copy-paste from thermal variants.
**How to avoid:** D-10 is explicit: Channel gets dp[i] and P[i] only. T_sat/T_ONB are ChannelAndContacts and ChannelHeatFlux only.
**Warning signs:** Undefined q_wall reference in Channel observed equations.

### Pitfall 4: ChannelHeatFlux T_ONB q_spl Formula
**What goes wrong:** Using wrong q_spl expression for ChannelHeatFlux.
**Why it happens:** ChannelHeatFlux has `q_wall[i] ~ h_tc[i] * sum(geometry.heated_parts) * dz * (T_wall_p - T[i])`. The heat flux (W/m^2) is `q_wall[i] / (sum(geometry.heated_parts) * dz)`, which simplifies to `h_tc[i] * (T_wall_p - T[i])`.
**How to avoid:** Use the D-12 formula consistently: `q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)`.

### Pitfall 5: Friction Per-Cell in observed_mode
**What goes wrong:** Using `Re[i]` (an observed variable) inside _channel_base_eqs when observed_mode=true.
**Why it happens:** In ChannelAndContacts, Re is observed, not an unknown. Using the Re[i] symbol in the dp equation creates an unknown-references-observed dependency.
**How to avoid:** In observed_mode, compute Re_i as an inlined expression (already done for h_tc). Use this Re_i for friction evaluation too.

### Pitfall 6: sat_temperature Domain Error at Bad Newton Iterates
**What goes wrong:** `log(P_Pa * 1e-6)` errors when P_Pa is negative during solver iterations.
**Why it happens:** KINSOL (steady-state solver) can evaluate at unphysical pressure values during Newton steps.
**How to avoid:** D-09 specifies `log(abs(P_Pa) * 1e-6)` matching Python STREAM. The `abs()` guard prevents DomainError.

### Pitfall 7: Backward Compatibility of Existing Tests
**What goes wrong:** Existing tests that solve loops and check dP values break because dP changed from unknown to observed.
**Why it happens:** `sol[sys.ch.dP]` access pattern changes behavior when dP becomes observed.
**How to avoid:** Actually, `sol[sys.ch.dP]` works identically for observed variables as for unknowns in ODESolution. The access pattern is transparent. But `dP` must not appear in initial condition guesses (op arrays) since it is no longer an unknown.
**Warning signs:** "Variable not found" errors in op (initial guess) construction.

## Code Examples

### sat_temperature Verified Against Python STREAM
```python
# Python STREAM light_water.py line 192-197:
X = np.log(np.abs(P) * 1e-6)
A = 179.9600321; B = -0.1063030; C = 24.2278298; D = 2.951e-4
return (A + C * X) / (1 + B * X + D * X**2)  # returns Celsius
```

Test values from Python docstring:
- `sat_temperature(1e5)` = 99.63 C = 372.78 K
- `sat_temperature(0.5e5)` = 81.28 C = 354.43 K
- `sat_temperature(2e5)` = 120.29 C = 393.44 K
- `sat_temperature(atm)` = 100.00 C = 373.15 K

### Bergles-Rohsenow dT_ONB Verified Against Python STREAM
```python
# Python STREAM temperatures.py line 103-105:
p = pressure / 1e5
return 0.556 * (q_spl / 1082 / p**1.156) ** (0.463 * p**0.0234)
```

Test values from Python docstring:
- `Bergles_Rohsenow_dT_ONB(q_spl=0., pressure=1e10)` = 0.0

### Existing @variables Array Declaration Pattern
```julia
# From thermal_channel.jl -- established array variable syntax:
vars = @variables begin
    (T(t))[1:n]       = fill(600.0, n)
    (Re(t))[1:n]
    # ... etc
end
```

### Existing obs Push Pattern
```julia
# From ChannelAndContacts (thermal_channel.jl line 121-139):
obs = Equation[]
for i in 1:n
    Re_i = abs(inlet.mdot) * Dh / (A * mu_water(T[i]))
    push!(obs, Re[i] ~ Re_i)
    # ... more observed equations
end
# Then pass obs to System constructor:
System(eqs, t, all_vars, pars; observed=obs, name=name)
```

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + DifferentialEquations.jl |
| Config file | test/runtests.jl (thin orchestrator) |
| Quick run command | `julia --project -e 'using Pkg; Pkg.test()' 2>&1 \| tail -20` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PRES-01 | dp[i] per-cell, dP = sum(dp[i]) | integration | `julia --project -e 'using Pkg; Pkg.test()'` | Wave 0 (add to test_channel.jl) |
| PRES-02 | P[i] absolute pressure observable | integration | same | Wave 0 |
| PRES-03 | sat_temperature(P) function | unit + integration | same (unit: test_fluids.jl, integration: test_channel.jl) | Wave 0 |
| PRES-04 | T_sat[i], T_ONB[i] observables | integration | same | Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project -e 'using Pkg; Pkg.test()'`
- **Per wave merge:** Same (single test suite)
- **Phase gate:** Full suite green before /gsd:verify-work

### Wave 0 Gaps
- [ ] PRES-01 test in `test_channel.jl`: build loop, solve, verify `sol[ch.dP] == sum(sol[ch.dp[i]] for i in 1:n)`
- [ ] PRES-02 test in `test_channel.jl`: verify `sol[ch.P[i]]` returns monotonically decreasing absolute pressure
- [ ] PRES-03 unit test in `test_fluids.jl`: verify sat_temperature against Python reference values
- [ ] PRES-04 test in `test_channel.jl`: verify T_sat[i] and T_ONB[i] accessible and physically reasonable
- [ ] No new test framework install needed (Julia Test stdlib already in use)

## Open Questions

1. **ChannelHeatFlux T_sat/T_ONB scope**
   - What we know: D-10 says T_sat/T_ONB in ChannelAndContacts and ChannelHeatFlux only. ChannelHeatFlux has T_wall_p as a scalar parameter, so q_spl is well-defined.
   - What's unclear: Whether ChannelHeatFlux having no ThermalPort means T_ONB is less useful there (T_wall is fixed, not solved).
   - Recommendation: Implement as specified. T_ONB is still useful for post-processing even with fixed T_wall.

2. **Channel dp[i] declaration location**
   - What we know: D-14 says _channel_base_eqs gains dp parameter. Claude's discretion on where dp is declared.
   - Recommendation: Declare `(dp(t))[1:n]` in each channel's `@variables` block (consistent with T, Re, etc.) and pass to _channel_base_eqs. This keeps variable ownership clear and follows the existing pattern where T, Re, Nu, etc. are declared in the caller.

## Sources

### Primary (HIGH confidence)
- `src/components/channel.jl` -- current dP equation, _channel_base_eqs signature, all_vars structure
- `src/components/thermal_channel.jl` -- ChannelAndContacts obs pattern, ChannelHeatFlux structure
- `src/fluids.jl` -- @register_symbolic pattern, existing fluid functions
- `src/physical_models/correlations.jl` -- plain arithmetic correlation pattern (not @register_symbolic)
- `~/projects/STREAM/stream/substances/light_water.py` lines 168-197 -- sat_temperature Simantov coefficients and test values
- `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/temperatures.py` lines 73-105 -- Bergles_Rohsenow_dT_ONB formula and test values

### Secondary (MEDIUM confidence)
- `.planning/phases/27-pressure-field/27-CONTEXT.md` -- all 15 decisions verified against source code feasibility

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, all within existing MTK/DifferentialEquations stack
- Architecture: HIGH -- all patterns verified against existing codebase, decisions are prescriptive
- Pitfalls: HIGH -- identified from direct code inspection, MTK behavior well-understood from prior phases

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable -- no external dependency changes expected)

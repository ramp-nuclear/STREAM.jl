# Phase 45: PointKinetics Bare Component & Steady-State ICs - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a standalone MTK `ODESystem` with 7 ODEs (P + 6 C_k precursor groups) and a constant `rho` parameter, plus a `point_kinetics_steady_state(P0, params)` helper that returns critical initial conditions. No temperature feedback, no callable rho, no SCRAM, no ports — those are Phases 46-49. Phase 45 is the bare neutronics kernel.

</domain>

<decisions>
## Implementation Decisions

### Delayed Group Parameter Representation
- **D-01:** Constructor accepts Julia arrays (`beta_k::Vector`, `lambda_k::Vector`) and generates 6 individual scalar MTK parameters internally (`beta_1, ..., beta_6`, `lambda_1, ..., lambda_6`). Public API is array-based; MTK internals are scalar-based.
- **D-02:** Avoids MTK array parameter pitfalls (indexing in equations, ODEProblem `p` passing). Downstream phases (46-48) iterate over the 6 scalars when building feedback sums.

### Default Nuclear Data
- **D-03:** Embed U-235 6-group defaults for `Lambda`, `beta_k`, and `lambda_k`. Same values as Python STREAM reference (`Lambda = 5.4e-5 s`; same `lambdak`/`betak` arrays used in Python tests). Caller gets a working system with `PointKinetics(; name, rho=0.0)` and can override for other fuel types.
- **D-04:** `rho` has no meaningful default (rho=0 is subcritical steady state; callers should be explicit). Keep `rho` as a required keyword or default to `0.0` with a clear docstring note.

### Diagnostic Observables (@observed)
- **D-05:** Match Python STREAM `save()` output — expose everything Python STREAM tracks as `@observed`:
  - `beta_total` — sum of all `beta_k`; appears in `(rho - beta)/Lambda * P` denominator
  - `dPdt` — RHS of the P ODE; lets callers check prompt criticality margin
  - `reactivity` — total reactivity (equals `rho` in Phase 45; extended with feedback terms in Phase 47)
- **D-06:** State variables P and all C_k are always accessible from the solution; no need to make them `@observed`.

### Constructor Signature
- **D-07:** Keyword-only constructor (established CLAUDE.md rule for multi-parameter components): `PointKinetics(; name, rho=0.0, Lambda=5.4e-5, beta_k=U235_BETA_K, lambda_k=U235_LAMBDA_K)`.
- **D-08:** `name` always keyword-only (injected by `@named` macro — established pattern).

### File Layout
- **D-09:** New file `src/components/point_kinetics.jl`. Export `PointKinetics` and `point_kinetics_steady_state` from `src/STREAM.jl` only.
- **D-10:** Test file `test/test_point_kinetics.jl`; included in `test/runtests.jl` alongside existing test files.

### Claude's Discretion
- Variable naming inside the component (`C_1..C_6` vs `Ck[1]..Ck[6]` as MTK variable naming — use scalar `@variables C_1(t) C_2(t) ...`)
- Internal helper for U-235 constants (module-level `const` vs hardcoded defaults in the constructor)
- Docstring structure (follow existing component docstring pattern with `# Arguments`, `# Returns`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Point Kinetics ODEs & steady-state formula
- `.planning/REQUIREMENTS.md` §PK-01, §PK-02 — Acceptance criteria, ODE structure, IC formula, validation rtol

### Python STREAM reference implementation
- `~/projects/STREAM/stream/calculations/point_kinetics.py` — Canonical ODE formulation, parameter names, `calculate()` method structure
- `~/projects/STREAM/tests/test_calculations/test_point_kinetics.py` — Reference test patterns (precursor decay test, U-235 lambdak values)

### MTK callable parameter pattern (Phase 46 precedent)
- `src/components/pump.jl` — `Pump(dP_pump::Any)` callable dispatch; `@parameters (dP_pump_fn::FType)(..)` pattern for Phase 46

### Existing @observed usage
- `src/components/thermal_channel.jl` — `@observed` declaration pattern for diagnostic variables (Re, Nu, htc, etc.)

### MTK Flapper latch/callback pattern (Phase 49 precedent)
- `src/components/flapper.jl` — `D(T_open) ~ 0` sentinel latch + `SymbolicContinuousCallback` pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/fluids.jl`: `@register_symbolic` pattern — not needed for Phase 45 (no fluid properties in point kinetics)
- `src/components/pump.jl`: callable `@parameters` pattern — directly relevant for Phase 46; read for MTK conventions
- `src/components/thermal_channel.jl`: `@observed` declaration template
- `src/composition/helpers.jl`: `compose_systems` — will be used in Phase 48 to couple PointKinetics with HeatDiffusion

### Established Patterns
- `D = Differential(t)` for time derivatives — used in all ODE components
- `compose(System(eqs, t, vars, pars; name=name), ...)` — standard component constructor pattern
- `@named macro` injects `name` as keyword arg — never positional
- `vars=[]` when no additional state vars beyond what MTK infers (see Inertia component) — but for PointKinetics, state vars must be explicit (P + 6 C_k)

### Integration Points
- Phase 45 is standalone — no FlowPort/ThermalPort. Cross-system coupling (`fuel.power ~ pk.P`) comes in Phase 48.
- `point_kinetics_steady_state` is a plain Julia function (not MTK) — takes `(P0, params)`, returns `Dict` or `NamedTuple` of C_k values for use as `u0` in `ODEProblem`.
- The component will be added to `src/STREAM.jl` `include()` list and `export` line.

</code_context>

<specifics>
## Specific Ideas

- Python STREAM U-235 data: `lambdak = [55.72, 22.72, 6.22, 2.3, 0.618, 0.23]` (from `test_point_kinetics.py`)
- "Everything that can be seen in Python STREAM should be provided here too if possible" — @observed should mirror Python STREAM `save()` keys: `reactivity`, `dPdt`, `beta_total`
- `point_kinetics_steady_state` should return something the caller can splat directly into the `u0` dict for `ODEProblem` — ergonomic IC wiring

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 45-pointkinetics-bare-component-steady-state-ics*
*Context gathered: 2026-04-04*

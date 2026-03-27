# Phase 22: Time-Varying Pump - Context

**Gathered:** 2026-03-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Enable `Pump(dP_pump=f)` where `f` is a Julia callable `f(t) -> Float64`, for coastdown
and ramp scenarios. No API changes to `solve_transient` — which is also being redesigned
in this phase to a correct, general-purpose signature (see decisions below).

This phase does NOT implement Flapper, ContinuousCallback events, or the loss-of-flow
validation scenario — those are Phases 23–24.

</domain>

<decisions>
## Implementation Decisions

### Pump callable dispatch
- `Pump(dP_pump::Real; name)` — scalar fixed-pressure (existing behavior, positional dispatch)
- `Pump(dP_pump::Any; name)` — callable fixed-pressure (new, positional dispatch; `Any` not `Function` — accepts DataInterpolations.jl interpolants and any other callable object, not just `Function` subtypes)
- `Pump(; name, mdot0)` — fixed-flow (keyword-only; mdot0 vs dP_pump is a concept distinction, not a type distinction — no dispatch possible, stays keyword)
- Three methods total, clean Julia multiple dispatch for the scalar vs callable case
- **No validation of the callable at construction time** — trust the caller (consistent with `power_shape` and all other user-supplied values). Errors surface at solve time with a clear MTK message.
- The callable is registered via `@register_symbolic` so it becomes an opaque symbolic node in MTK equations: `port_out.P - port_in.P ~ dP_pump(t)`

### PUMP-03 test system
- Loop topology: **Pump + Inertia + Resistor** (simplest system with mdot dynamics)
- Pump ramps linearly: `dP(t) = dP0 * (1 - t/T_ramp)` where `dP0 = 1e5 Pa`, `T_ramp = 100 s`
- Validation: **1% rtol at `t = T_ramp`** — check `mdot ≈ 0` against exact analytical solution for the forced response of `(L/A) * d(mdot)/dt + R * mdot = dP(t)`
- Builds on existing test infrastructure (Inertia, Resistor already tested)

### solve_transient redesign (scope expanded from original PUMP-01/02/03)
**New signature:**
```julia
solve_transient(ssys, op, t; solver=Rodas5P(), callbacks=nothing, kwargs...)
```
- `ssys` — compiled system (same as `solve_steady`)
- `op` — initial conditions as `Vector{Pair}` (same as `solve_steady`)
- `t` — time array (e.g. `range(0, 100, length=1000)`); mirrors Python STREAM `agr.solve(y0=..., time=time)`; `tspan` derived from `(t[1], t[end])`
- `callbacks` — optional `CallbackSet`; passes through to `solve`; pre-wires SOLV-01 (Phase 23)
- **Remove entirely**: `T_wall_sym`, `T_wall_final`, `t_step` — these were a hardcoded single-use workaround, not a general solver API

**Why the old signature was wrong:** `T_wall` was declared as a static MTK `@parameters` scalar, requiring `PresetTimeCallback` + `ModelingToolkit.setp` to mutate it mid-integration. This use-case-specific mechanism was incorrectly embedded in the core solver API. The correct pattern is to wire time-varying quantities as registered callables in the system equations — no callbacks needed.

### solve_transient propagation — 4 files affected
All changes required for the redesign to land without breaking tests:

1. **`src/solvers.jl`** — rewrite `solve_transient` (signature + implementation + docstring)
2. **`src/examples.jl`** — update `build_loop_transient`:
   - Returns just `ssys` (drop `T_wall_sym` from return tuple)
   - Accepts optional `T_wall_fn` callable; wires as `ch.thermal.T ~ T_wall_fn(t)` when provided; falls back to constant `T_wall_0` when not
   - Update docstring (remove all references to T_wall_sym / solve_transient coupling)
3. **`test/test_solvers.jl`** — update SOLV-02 tests:
   - Remove `@test T_wall_sym isa Symbolics.Num` assertion
   - Rewrite `solve_transient` call to new positional signature
   - Step-change test: pass a step callable as `T_wall_fn` to `build_loop_transient`
4. **`test/test_validation.jl`** — update VAL-02:
   - Same: rewrite `solve_transient` call, use callable T_wall approach

**Approach for step-change tests (SOLV-02, VAL-02):** Use a registered callable for `T_wall` in `build_loop_transient` — consistent with the callable `dP_pump` pattern this phase establishes. No callbacks needed.

### Claude's Discretion
- Exact Inertia + Resistor parameter values for the PUMP-03 test loop
- Exact time array used in PUMP-03 (length, spacing)
- Whether `@register_symbolic` for user callables requires a gensym/eval approach or a different MTK registration mechanism — researcher should investigate

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Pump component
- `src/components/pump.jl` — current Pump implementation (scalar only; this phase adds callable dispatch)

### Solver
- `src/solvers.jl` — current solve_transient (being replaced) and solve_steady (signature to mirror)
- `src/examples.jl` — build_loop_transient (being updated)

### Tests affected
- `test/test_solvers.jl` — SOLV-02 tests (need rewrite)
- `test/test_validation.jl` — VAL-02 test (need rewrite)

### Python STREAM reference
- `/home/itay/projects/STREAM/.claude/skills/stream-user/SKILL.md` — Python STREAM `agr.solve(y0, time, ...)` signature; this is the API we are mirroring

### Requirements
- `PUMP-01`, `PUMP-02`, `PUMP-03` in `.planning/REQUIREMENTS.md`
- `SOLV-01` (Phase 23) — `callbacks` kwarg pre-wired by this phase

No external specs — requirements fully captured in decisions above.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Inertia` component (`src/components/misc.jl`): `(L/A)*Dt(port_in.mdot)` — provides mdot dynamics for PUMP-03 test
- `Resistor` component (`src/components/resistors.jl`): `dP = R*mdot` — provides hydraulic resistance for PUMP-03 test
- `@register_symbolic` pattern (`src/fluids.jl`): module-level registration of opaque functions — same mechanism needed for callable dP_pump
- `solve_steady` signature (`src/solvers.jl:70`): `solve_steady(ssys, op; kwargs...)` — the positional pattern `solve_transient` should mirror

### Established Patterns
- Trust the caller: no validation of user-supplied values at construction (power_shape precedent)
- `ifelse()` for symbolic conditionals in MTK equations
- `@register_symbolic` at module top-level (NOT inside functions) — potential implementation constraint for user-supplied lambdas; researcher must investigate dynamic registration approach

### Integration Points
- `solve_transient` is called in `test_solvers.jl`, `test_validation.jl`
- `build_loop_transient` is called in both test files and exported from `STREAM.jl`
- `callbacks` kwarg in new `solve_transient` is the hook Phase 23 will use for Flapper's ContinuousCallback

</code_context>

<specifics>
## Specific Ideas

- Python STREAM transient signature: `agr.solve(y0=steady_vector, time=np.linspace(0, 100, 1000))` — `t` as a time array, not a tspan tuple
- The callable pump approach makes T_wall step-changes trivially implementable without any callbacks: just wire `ch.thermal.T ~ T_wall_fn(t)` at system construction time
- Pump dispatch mirrors the existing pattern: scalar `dP_pump` stays, callable `dP_pump` is a new method, `mdot0` stays keyword-only because the distinction is conceptual not typed

</specifics>

<deferred>
## Deferred Ideas

- **Phase 25: Argument structure audit** — sweep ALL exported functions and constructors; replace keyword-only where positional + multiple dispatch is more idiomatic Julia. Added to roadmap as Phase 25.
- CLAUDE.md update to reflect the new looser keyword-only rule — included in Phase 25 scope

</deferred>

---

*Phase: 22-time-varying-pump*
*Context gathered: 2026-03-17*

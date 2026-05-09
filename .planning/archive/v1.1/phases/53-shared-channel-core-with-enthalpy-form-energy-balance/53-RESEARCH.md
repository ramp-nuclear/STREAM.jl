# Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance — Research

**Researched:** 2026-05-06
**Domain:** Julia / ModelingToolkit (MTK) — symbolic refactor of a heated channel helper, plus an energy-balance switch from constant-cp upwind to face-averaged-cp enthalpy form
**Confidence:** HIGH (the design is locked in CONTEXT.md D-01..D-14; this research is implementation-level only, grounded in the actual STREAM.jl source and Python STREAM reference)

## Summary

CONTEXT.md already locks the API shape (`_channel_core(...)::NamedTuple{(:eqs, :obs)}`), the energy-balance formula (face-averaged cp using `pair_mean_1d` semantics with `cp(instream(...))` at the boundary face), the observable ownership split (q-agnostic + q-derived in core; HTC/Nu/T_wall/Gr aliases in CAC), and the verification depth (two-stage analytical check plus single-cell mirror plus code-path coverage). The planner's job is to translate that into commits that keep the variants compiling at every boundary. This research surfaces the implementation-level facts that decision needs.

The single highest-leverage finding: `_channel_base_eqs` is called from exactly two sites (`thermal_channel.jl:109` for CAC and `thermal_channel.jl:322` for ChannelHeatFlux), and the public `Channel` constructor in `channel.jl` has its own inline body (it does NOT call `_channel_base_eqs`). That asymmetry — already present in v1.0 — is what makes Phase 53's "extract core, leave variants alone" mandate physically possible: only the helper itself is touched, not the variant constructors that consume it. Phase 54 then rewires all three variants in one phase. This is consistent with CONTEXT.md D-13 but worth flagging because the planner cannot assume "all three variants currently call `_channel_base_eqs`" — only two do.

The second highest-leverage finding: `cp_water` is `@register_symbolic` (`src/fluids.jl:146`), and the existing channels already pass `cp_water(T[i])` and `cp_water(T_up)` as Num expressions (`channel.jl:81`, `thermal_channel.jl:171`). The arithmetic average `(cp_water(T_up) + cp_water(T[i])) / 2` is therefore a well-formed Num composition — no new MTK machinery required. The flow-reversal `ifelse` already wraps `T_up`, so `cp_water(ifelse(...))` correctly emits a single Num node whose two branches are `cp_water(T_up_fwd)` and `cp_water(T_up_rev)`; no second `ifelse` for cp is needed (NRG-04).

**Primary recommendation:** Place the new tests in a dedicated `test/test_channel_core.jl`, wire it into `test/runtests.jl` between `test_channel.jl` and `test_pump.jl`, and structure the file with three top-level testset groups (Stage-1 constant-cp degeneracy, Stage-2 Python parity hand-compute, branch-coverage matrix). Defer the variant tests in `test_channel.jl` untouched throughout Phase 53. Use a commit sequence of (1) introduce `_channel_core` alongside `_channel_base_eqs` with no callers + scaffold tests; (2) verify Stage-1 + Stage-2 + mirror + branch-coverage tests green; (3) delete `_channel_base_eqs`. The variants stay compiled and tested at every commit boundary because they keep calling the (still-present) `_channel_base_eqs` until Phase 54.

## User Constraints (from CONTEXT.md)

### Locked Decisions

D-01: `_channel_core(...)` returns `(; eqs, obs)` (a `NamedTuple` of two `Vector{Equation}`). Variant call site is `eqs = [variant_specific_eqs; core.eqs]`, `obs = [core.obs; variant_specific_obs]`, then `System(eqs, t, all_vars, pars; observed=obs, name=name) |> sys -> compose(sys, port_in, port_out, ...)`.

D-02: `q_left_expr` / `q_right_expr` are length-n `Vector{Num}` inputs. Variants pre-build the expression vectors and pass them in; core indexes `q_left_expr[i]` / `q_right_expr[i]` per cell. Phase 53 uses placeholder driven values to exercise every code path inside core.

D-03: `htc_correlation` is variant-internal (only `ChannelAndContacts` uses one); `friction_correlation` stays in core (shared by all three variants). Final core signature is fixed: `_channel_core(; n, T, dp, port_in, port_out, geometry, g_acc, friction_correlation=blasius_friction, q_left_expr, q_right_expr)::NamedTuple{(:eqs, :obs)}`.

D-04: No `htc_correlation`, no `Re/Nu` in or out of the function signature. Re is computed inside core as an observable. Nu and h_tc are CAC-only and live entirely inside `ChannelAndContacts`.

D-05: Boundary-face cp uses the same averaging formula as interior faces — `(cp(T_up) + cp(T[i])) / 2`. The "boundary face" of cell 1 (forward flow) is the same averaging with `T_up = instream(port_in.T)`; cell n (reverse flow) is `T_up = instream(port_out.T)`. Verified against Python STREAM `pair_mean_1d` with `prepend=cin`.

D-06: Energy balance equation per cell is:
```julia
cp_face = (cp_water(T_up) + cp_water(T[i])) / 2
Dt(T[i]) ~ (
    abs(port_in.mdot) * cp_face * (T_up - T[i])
  + q_left_expr[i]
  + q_right_expr[i]
) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)
```
The two cp values do NOT cancel.

D-07: Flow reversal — same `ifelse(mdot ≥ 0, T_up_fwd, T_up_rev)` selects `T_up`; `cp(T_up)` is implicitly selected because `cp_water` is deterministic. No second `ifelse` for cp.

D-08: Maximal core + per-side q stubs. Core emits `Re[i]`, `Pe[i]`, `v[i]`, `T_out`, `P[i]`, `dP`, `T_sat[i]` (q-agnostic) and `q_wall[i]`, `q_wall_left[i]`, `q_wall_right[i]`, `T_ONB[i]` (q-derived).

D-09: Variants own only what depends on variant-specific symbols — CAC's `h_tc[i]`, `Nu[i]`, `h_tc_left/right[i]`, `T_wall_left/right[i]`, `Gr_over_Re2[i]`, `Q_wall_total`; per-side `WallPort`/`HeatFluxPort` aliases for `Channel`/`ChannelHeatFlux` in Phase 54.

D-10: All observable LHS variables are declared in the variant's `@variables` block. Core builds equations referencing these by symbol — variant must declare them with the names core expects.

D-11: Two-stage analytical verification on placeholder test scaffolding (Stage 1 — constant-cp limit ~1e-6 rtol vs v1.0; Stage 2 — realistic cp variation hand-computed via `pair_mean_1d` to ~1e-9 rtol).

D-12: Test scaffolding lives in `test/test_channel.jl` OR a new `test/test_channel_core.jl` — planner picks. Both placements respect CLAUDE.md test placement rule.

D-13: Commit granularity is a planning concern. Constraint: variants must continue to compile and pass existing tests at every commit boundary inside Phase 53.

D-14: `Q_wall_total` stays as a CAC-side observable for backward compatibility (defined as `sum(core_q_wall[i])` in the variant, not in core).

### Claude's Discretion

- Test file placement: `test_channel.jl` vs `test_channel_core.jl` (D-12).
- Commit granularity inside Phase 53 (D-13).
- Whether to provide a small helper `_channel_core_obs_vars(; n)` that returns a NamedTuple of pre-declared `@variables` for the variant to splat, OR inline the obs symbol declarations in each variant (D-10 implementation detail).

### Deferred Ideas (OUT OF SCOPE)

- Variant rewrites onto `_channel_core` — Phase 54 (VAR-01..03).
- File consolidation `channel.jl` + `thermal_channel.jl` → `channels.jl` — Phase 54 (VAR-04).
- Composition helper updates for the new connector-driven Channel/ChannelHeatFlux — Phase 55.
- Cross-validation against Python STREAM under the new convective scheme — Phase 56.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-01 | Single private `_channel_core(...; q_left_expr, q_right_expr)` exists and is the single source of truth for energy balance, mass conservation, momentum ODE, friction, port wiring, and observables (Re, Pe, P[i], T_sat, T_ONB, dP) | §"Standard Stack" (NamedTuple-returning helper idiom verified), §"Architecture Patterns" Pattern 1 (function shape), §"Code Examples" Example 1 |
| CORE-02 | `_channel_base_eqs` removed entirely from `src/components/channel.jl` | §"Coexistence Strategy" (deletion only at final commit; grep audit pattern); §"Common Pitfalls" Pitfall 4 |
| CORE-03 | No `observed_mode` flag in any helper or variant constructor | §"Don't Hand-Roll" (flag plumbing is what v1.1 exists to delete); §"Code Examples" Example 2 (core has no `observed_mode` knob) |
| CORE-04 | No `skip_htc` flag anywhere; SCB lives entirely inside `ChannelAndContacts` | §"Common Pitfalls" Pitfall 5 (CAC's SCB block stays in CAC, not core) |
| CORE-05 | No `T_wall_cells=nothing` default or other dead branch in shared code; every code path is reachable by at least one variant | §"Validation Architecture" → "Code-Path Coverage Matrix" |
| NRG-01 | Convective term numerator uses face-averaged cp `(cp(T_up) + cp(T[i])) / 2` | §"Code Examples" Example 1 (energy balance); §"Common Pitfalls" Pitfall 1 (`@register_symbolic` boundary across the face-averaged cp) |
| NRG-02 | Boundary face uses `cp(instream(port_in.T))` / `cp(instream(port_out.T))` | §"Architecture Patterns" Pattern 2 (`instream` semantics); §"Code Examples" Example 1 |
| NRG-03 | Heat-capacity denominator retains local `cp(T[i])`; the two cp values do not cancel | §"Common Pitfalls" Pitfall 3 (cp denominator vs numerator non-cancellation grep audit) |
| NRG-04 | Flow reversal: same `ifelse(mdot ≥ 0, ...)` that selects upstream T also selects upstream cp | §"Architecture Patterns" Pattern 3 (`ifelse` propagation through `cp_water`); §"Validation Architecture" → "Single-Cell Mirror Test" |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Energy balance (per-cell `Dt(T[i])`) | `_channel_core` | — | Single source of truth (CORE-01) |
| Mass conservation (`port_in.mdot + port_out.mdot ~ 0`) | `_channel_core` | — | Identical across all three variants — verified by reading current `channel.jl:111` and `_channel_base_eqs:243` |
| Momentum ODE (`(L/A)·D(mdot) ~ ΔP − Σdp`) | `_channel_core` | — | Identical across variants — verified `channel.jl:113-114` and `_channel_base_eqs:245` |
| Per-cell friction `dp[i]` | `_channel_core` | — | Identical formula across variants; only `friction_correlation` may vary (kwarg) |
| Port wiring (`port_in.T ~ T[1]`, `port_out.T ~ T[n]`) | `_channel_core` | — | Identical, `channel.jl:115-116` ≡ `_channel_base_eqs:247-248` |
| q-agnostic observables (Re, Pe, v, P[i], T_sat, dP, T_out) | `_channel_core` | — | Pure function of inputs core already has |
| q-derived observables (q_wall, q_wall_left/right, T_ONB) | `_channel_core` | — | Pure function of `q_*_expr` arguments |
| HTC computation (h_tc[i] from Nu/correlation, plus optional SCB) | `ChannelAndContacts` | — | Variant-specific; only CAC uses an htc_correlation. Phase 54 work. |
| q construction from `WallPort` (`h*A*(T_wall − T)`) | `Channel` | `_channel_core` (consumes the result) | Variant-specific connector contract. Phase 54 work. |
| q construction from `HeatFluxPort` (`q_flux * A`) | `ChannelHeatFlux` | `_channel_core` (consumes the result) | Variant-specific connector contract. Phase 54 work. |
| `Q_wall_total` aggregate | `ChannelAndContacts` | — | CAC-only convenience observable (D-14); core's `q_wall[i]` is the input |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ModelingToolkit (MTK) | 11.x (matches existing Project.toml) | Symbolic DAE modeling, equation construction, `mtkcompile`, acausal connectors | Already the foundation of STREAM.jl; not changing in Phase 53 |
| Symbolics.jl | (transitive via MTK) | `Num` type, `ifelse` for symbolic conditionals, expression tree manipulation | Same as above |
| Test.jl (stdlib) | bundled | `@testset`, `@test`, `@test_nowarn` | Existing test convention |
| OrdinaryDiffEq + Sundials | (existing) | Transient integration of stub harness systems for Stage-1 / Stage-2 / mirror tests | Existing test convention (`solve_transient` / `solve_steady`) |

[VERIFIED via Read of `src/STREAM.jl`, `test/test_channel.jl`, `test/test_connectors.jl`] — no new dependencies required.

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| (none new) | — | — | This phase introduces no new packages |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `(; eqs, obs)` NamedTuple | `extend()`-based partial System | CONTEXT.md D-01 explicitly rejects partial-System+`extend()`: shared array-vars (`T[1:n]`, `dp[1:n]`) would have to be threaded across the System boundary, awkward for variant-declared arrays |
| `(; eqs, obs)` NamedTuple | Eqs-mutator `_channel_core!(eqs, obs; ...)` | CONTEXT.md D-01 explicitly rejects: "doubles down on the no-`!`-suffix mutation already in the codebase" — `_channel_base_eqs` was a mutator (`eqs::Vector{Equation}` first positional) and we are deliberately moving away from that pattern |

**No installation step.** Phase 53 ships under existing `Project.toml`.

**Version verification:** Not applicable — no new packages.

## Architecture Patterns

### System Architecture Diagram

```
                              ┌──────────────────────────────────────┐
                              │   Variant Constructor (e.g. CAC)     │
                              │  declares @variables: T, dp, Re, Pe, │
                              │  v, P, T_sat, T_ONB, q_wall,         │
                              │  q_wall_left, q_wall_right, dP, T_out│
                              │  + variant-specific (h_tc, Nu, ...)  │
                              └──────────────┬───────────────────────┘
                                             │ builds q_left_expr,
                                             │ q_right_expr (length-n
                                             │ Vector{Num})
                                             ▼
   ┌──────────────────────────────────────────────────────────┐
   │  _channel_core(; n, T, dp, port_in, port_out,            │
   │                 geometry, g_acc, friction_correlation,   │
   │                 q_left_expr, q_right_expr)               │
   │                                                          │
   │  for i in 1:n:                                           │
   │    T_up = ifelse(mdot ≥ 0, T_up_fwd, T_up_rev)           │
   │    cp_face = (cp_water(T_up) + cp_water(T[i])) / 2  ◀─── │ NRG-01,02,03,04
   │    push! Dt(T[i]) ~ (|mdot|·cp_face·(T_up−T[i])          │
   │                       + q_left_expr[i] + q_right_expr[i])│
   │                      / (ρ·cp_water(T[i])·A·dz)           │
   │    push! dp[i] ~ friction + gravity                      │
   │    obs: Re[i], Pe[i], v[i], P[i], T_sat[i], T_ONB[i],    │
   │         q_wall[i], q_wall_left[i], q_wall_right[i]       │
   │  scalars: T_out ~ T[n], dP ~ ΔP                          │
   │  port: mass cons, momentum ODE, port_in/out.T anchors    │
   │                                                          │
   │  return (; eqs::Vector{Equation},                        │
   │            obs::Vector{Equation})                        │
   └────────────────────┬─────────────────────────────────────┘
                        │ NamedTuple back to caller
                        ▼
                ┌────────────────────────────────────────┐
                │  Variant: assemble final System        │
                │  eqs = [variant_eqs; core.eqs]         │
                │  obs = [core.obs; variant_obs]         │
                │  System(eqs, t, all_vars, pars;        │
                │         observed=obs, name=name)       │
                │  |> sys -> compose(sys, port_in,       │
                │              port_out, thermal_*)      │
                └────────────────────────────────────────┘
                        │
                        ▼
                ┌────────────────────────────────────────┐
                │  mtkcompile(sys)                       │
                │  index reduction sees the spliced eqs  │
                │  and observables as one flat list      │
                └────────────────────────────────────────┘
```

Reader trace: a variant constructor declares all symbols, builds q expressions, calls `_channel_core`, splices the returned vectors into its own equation/observable lists, builds a System, composes ports, and the caller of the variant constructor calls `mtkcompile`. Core itself does no `System` / `compose` / `mtkcompile` calls — it is a pure equation-list builder. [VERIFIED by reading the existing `_channel_base_eqs` shape in `src/components/channel.jl:172-249` and the variant call sites at `thermal_channel.jl:109` and `:322`.]

### Recommended Project Structure

No file additions in `src/`. Phase 53 modifies one file and adds one test file:

```
src/
└── components/
    ├── channel.jl              # _channel_core ADDED; _channel_base_eqs DELETED at final commit
    └── thermal_channel.jl      # UNCHANGED — variants still call _channel_base_eqs until Phase 54

test/
├── runtests.jl                 # ADD include("test_channel_core.jl") between test_channel.jl and test_pump.jl
├── test_channel.jl             # UNCHANGED — existing CHAN-*/GRAV-*/THERM-*/PHY-* tests stay green
└── test_channel_core.jl        # NEW — scaffold + Stage-1 + Stage-2 + mirror + branch-coverage tests
```

[VERIFIED via Read of `src/STREAM.jl`, `test/runtests.jl`. The file-placement recommendation is justified in §"Code Examples" Example 4.]

### Pattern 1: NamedTuple-returning helper inside MTK component constructors

**What:** A pure-function helper that takes already-declared `@variables` and `@parameters` from the caller, builds Julia `Vector{Equation}` objects referencing those symbols, and returns them in a `NamedTuple`. The caller is responsible for assembling the final `System(...)` and calling `compose(...)`.

**When to use:** When several component variants share the bulk of their equations but differ in how a single per-cell expression is constructed — exactly Phase 53's situation. The shared logic is concentrated in one helper; the variant adds only its differentiator.

**Precedent inside STREAM.jl ecosystem:** None for the `(; eqs, obs)` shape specifically. The current `_channel_base_eqs` is a *mutator* (takes `eqs::Vector{Equation}` as first positional, `push!`-es into it, returns nothing). The codebase has NamedTuple returns in `src/analysis.jl:199` (`threshold_analysis`) and `src/components/point_kinetics.jl:331` (`point_kinetics_steady_state`), but those are for analysis/utility functions, not equation-list builders. **Phase 53 introduces a new pattern** — pure functional helper for component construction. [VERIFIED by `grep -n "NamedTuple\|return (;" src/`.]

**Precedent inside MTK ecosystem:** Not directly applicable — MTK's own component library uses partial systems with `extend()` (e.g. `OnePort`, `TwoPort` in ModelingToolkitStandardLibrary). That pattern was rejected in CONTEXT.md D-01 because the shared array-vars (`T[1:n]`, `dp[1:n]`) live in the variant's `@variables` block and would have to be passed through a System boundary, defeating the purpose. The `(; eqs, obs)` NamedTuple shape is therefore a STREAM-local convention. [ASSUMED — confidence MEDIUM; based on knowledge of MTK conventions, no Context7 lookup performed.]

**Why it works for this codebase:** `Vector{Equation}` is the native MTK construction medium — `System(eqs, t, ...)` accepts a flat list, and the splicing `eqs = [variant_specific_eqs; core.eqs]` is just Julia vector concatenation. `mtkcompile` operates on the assembled System, and is structurally indifferent to whether the equations were built by one function or several — it sees the full flat list and performs index reduction over it. [VERIFIED by inspecting existing CAC at `thermal_channel.jl:109-189` which currently splices `_channel_base_eqs`-mutated `eqs` with its own variant-specific energy balance loop into the same `eqs::Vector{Equation}` and passes that to `System(...)`; the new pattern just makes the splicing explicit at the call site instead of hidden inside the mutator.]

**Example (the shape Phase 53 will use):**
```julia
# Source: D-01, D-06 (from CONTEXT.md)
function _channel_core(;
    n::Int,
    T,                                              # variant-declared @variables (T(t))[1:n]
    dp,                                             # variant-declared @variables (dp(t))[1:n]
    port_in, port_out,                              # variant-created FlowPorts
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr::AbstractVector,                    # length-n Vector{Num}
    q_right_expr::AbstractVector,                   # length-n Vector{Num}
    Re, Pe, v, P, T_sat, T_ONB,                     # variant-declared obs symbols
    q_wall, q_wall_left, q_wall_right,              # variant-declared obs symbols
    T_out, dP,                                      # variant-declared scalar obs
)
    Dh = geometry.Dh
    A = geometry.A
    L = geometry.L
    dz = L / n
    Dt = Differential(t)

    eqs = Equation[]
    obs = Equation[]
    T_inlet_fwd = instream(port_in.T)
    T_inlet_rev = instream(port_out.T)

    for i in 1:n
        T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
        T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
        T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
        cp_face = (cp_water(T_up) + cp_water(T[i])) / 2  # NRG-01, NRG-02 (boundary uses ifelse-selected T_up)
        push!(eqs,
            Dt(T[i]) ~ (
                abs(port_in.mdot) * cp_face * (T_up - T[i])
              + q_left_expr[i]
              + q_right_expr[i]
            ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)  # NRG-03 (denominator: local cp(T[i]))
        )
        # Per-cell friction (algebraic dp[i])
        Re_i_inline = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
        f_i = friction_correlation(Re_i_inline)
        push!(eqs, dp[i] ~
            f_i * (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) * (dz / Dh)
            + rho_water(T[i]) * g_acc * dz)

        # Observables — q-agnostic
        Pr_i_inline = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
        push!(obs, Re[i] ~ Re_i_inline)
        push!(obs, Pe[i] ~ Re_i_inline * Pr_i_inline)
        push!(obs, v[i]  ~ port_in.mdot / (rho_water(T[i]) * A))
        P_i = port_in.P - sum(dp[j] for j in 1:i) -
              (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
        push!(obs, P[i] ~ P_i)
        push!(obs, T_sat[i] ~ sat_temperature(P_i))

        # Observables — q-derived
        push!(obs, q_wall_left[i]  ~ q_left_expr[i])
        push!(obs, q_wall_right[i] ~ q_right_expr[i])
        push!(obs, q_wall[i]       ~ q_left_expr[i] + q_right_expr[i])
        # T_ONB: inline q-density to avoid observed-to-observed chain (Pitfall 5 in current code)
        q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
        push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i))
    end

    # Scalar equations
    push!(eqs, T_out ~ T[n])
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n))
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ T[1])
    push!(obs, dP ~ port_in.P - port_out.P)

    return (; eqs, obs)
end
```

This is illustrative, not prescriptive — the planner finalizes the exact symbol-passing convention (D-10 implementation detail: long kwarg list vs. `_channel_core_obs_vars` helper).

### Pattern 2: `instream(port.T)` semantics across the helper boundary

`instream(port_in.T)` produces a Symbolics.jl `Num` that MTK's stream-connection rule resolves at compile time, against whatever upstream node the port is connected to. The MTK-relevant question is: **does `instream` work when called inside a helper function that was called from the variant constructor?** Answer: YES. `instream` is a pure symbolic constructor — it returns a Num node whose meaning is determined later by `mtkcompile` based on connection topology. It does not care which Julia stack frame built the expression. [VERIFIED by inspecting `src/components/thermal_channel.jl:102-103` (CAC variant calls `instream` at the top of its body) and `_channel_base_eqs` does NOT — instead the variant captures `T_inlet_fwd = instream(port_in.T)` once and uses it inside the energy-balance loop. Phase 53's `_channel_core` will do the same: capture `T_inlet_fwd = instream(port_in.T)` and `T_inlet_rev = instream(port_out.T)` once at the top of `_channel_core`, then reference inside the loop. The current code is the precedent.]

**Crucial detail:** `instream(port_in.T)` is referenced from inside `_channel_core`, but `port_in` was constructed via `@named port_in = FlowPort()` *in the variant*. The `port_in` Num is then passed *as a kwarg argument* to `_channel_core`. This works because Num is just a value — the helper is operating on the same symbolic object the variant constructed. There is no scope or namespace gotcha. [VERIFIED — same pattern is already in use: `_channel_base_eqs` receives `port_in` and `port_out` kwargs at `channel.jl:182-183` and uses `port_in.mdot` and `port_in.P` inside without issue, including in the momentum ODE at line 245.]

### Pattern 3: `ifelse` propagation through `@register_symbolic` functions

Julia `if`/`else` on a Num collapses to one branch at trace time. `ifelse(...)` — Symbolics.jl's symbolic conditional — emits a Num node whose two branches both get traced, and the runtime evaluation picks the active branch.

**The Phase 53-specific question:** Does `cp_water(ifelse(mdot ≥ 0, T_up_fwd, T_up_rev))` correctly select `cp_water(T_up_fwd)` for `mdot ≥ 0` and `cp_water(T_up_rev)` for `mdot < 0`?

**Answer: YES.** `cp_water` is `@register_symbolic` (`src/fluids.jl:146`), which means `cp_water(some_Num)` constructs an opaque Num node `cp_water(some_Num)` — Symbolics does not look inside `cp_water` symbolically. The Num argument is the `ifelse` expression. At runtime, the `ifelse` resolves to either `T_up_fwd` or `T_up_rev`, and the registered numerical implementation `cp_water(::Real)` (`src/fluids.jl:45-52`) is called on that single Float64 value. [VERIFIED by reading `src/fluids.jl:143-150` and the existing `cp_water(T[i])` usage in `channel.jl:81` and `thermal_channel.jl:171` which already work this way.]

**Implication for NRG-04:** The CONTEXT.md claim that "`cp(T_up)` is implicitly selected because `cp_water` is a deterministic function" is correct — there is exactly one `ifelse` (the one wrapping `T_up`), and `cp_water` faithfully transports the selected value. The `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2` expression will, at runtime, evaluate to `(cp_water(T_up_fwd) + cp_water(T[i]))/2` for forward flow and `(cp_water(T_up_rev) + cp_water(T[i]))/2` for reverse flow. **No second `ifelse` for cp is needed; introducing one would be redundant.**

A subtle corollary: because `ifelse` is eager (both branches are traced and emitted in the symbolic graph; only the runtime evaluation picks one), the cell-1 forward-flow case still has a *symbolic* expression `cp_water(T[0])` lurking in the unselected branch — but `T[0]` isn't constructed because the variant uses `T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]` (a Julia `?:` ternary, which is *trace-time* and DOES collapse). So the symbolic graph for cell 1 forward is `cp_water(ifelse(mdot ≥ 0, T_inlet_fwd, T[2]))` — both branches well-formed. [VERIFIED — this is exactly the same idiom already used at `channel.jl:70-72`, `thermal_channel.jl:164-166`, and `thermal_channel.jl:346-348`. Phase 53 inherits the same correctness.]

### Anti-Patterns to Avoid

- **Don't rebuild `_channel_base_eqs`'s `observed_mode` knob inside `_channel_core`.** The whole point of CORE-03 is to delete that flag. If the planner sees a place where "core needs to know whether the variant treats Re/Nu as observed or unknown," that means the symbol declaration leaked into core. Solution: D-08 says core *always* emits Re/Pe/v/P/T_sat/T_ONB/q_wall as observables; variants that want them as unknowns instead are now off-limits, but no such variant exists. (CAC currently has `Re/Nu/v` as observed; ChannelHeatFlux has them as unknowns. Phase 54 will move ChannelHeatFlux to observed for Re/Pe/v/P consistency — that change is implicit in the variant rewrite, not in core.)

- **Don't make `_channel_core` a mutator.** D-01 explicitly chooses `(; eqs, obs)` return over `eqs!(eqs, obs; ...)`. Returning the lists from a pure function is the new convention.

- **Don't push observed-to-observed chains.** Existing code already documents this discipline (see `thermal_channel.jl:215-216` comment "use P_i expression (not P[i] symbol) to avoid observed-to-observed chain"). When core emits `T_ONB[i]`, the right-hand side must inline `(q_left_expr[i] + q_right_expr[i]) / (sum(heated_parts) * dz)` rather than reference the observable `q_wall[i]` symbol. The example in Pattern 1 above does this correctly with `q_density_i`.

- **Don't move the `Channel` constructor's body in Phase 53.** `Channel` (`channel.jl:26-144`) is currently inline, not a `_channel_base_eqs` consumer. Phase 53 leaves `Channel` untouched; Phase 54 rewrites it on top of `_channel_core`. Mid-Phase-53 attempts to "also clean up Channel" expand the diff and break the variants-stay-compiled invariant.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Conditional expressions in MTK equations | Julia `if`/`else` on Num | `Symbolics.ifelse(cond, a, b)` | Julia conditionals collapse at trace time; `ifelse` emits a runtime branch. CLAUDE.md "MTK Patterns" — `ifelse` for flow reversal and regime switching. Already pervasive in STREAM.jl. |
| Symbolic versions of fluid property functions | New `cp_water_sym(...)` wrapper | Existing `@register_symbolic cp_water` | `src/fluids.jl:146` already registers `cp_water` so it accepts Num. `cp_water(T_up)` "just works." |
| Helper-internal mutation of caller's eqs vector | `_channel_core!(eqs, obs; ...)` | `_channel_core(...) -> (; eqs, obs)` | D-01 locks the pure-functional return. Mutator pattern was rejected. |
| Flag plumbing for observed-vs-unknown | Re-introduce `observed_mode` or `skip_htc` | `_channel_core` always emits the same observable set; variants own variant-specific symbols (D-08, D-09) | CORE-03 / CORE-04 explicitly delete these. The whole milestone exists to eliminate flag accretion. |
| Per-side/per-mode q assembly inside core | Branching `if heated_left ... else ...` inside core's energy balance | Variant pre-builds `q_left_expr` and `q_right_expr` (D-02) — for unconnected sides, variant passes `fill(0, n)` | "Uniform additive contribution to the energy balance ... needs no flag plumbing inside core." (D-02 rationale) |
| Symbolic average-of-instream | A custom `face_average(a, b)` helper | Plain Julia arithmetic `(cp_water(T_up) + cp_water(T[i])) / 2` | Symbolics.jl traces arithmetic on Num natively; a wrapper adds zero value and obscures the formula. |
| Reverse-flow upstream-cp selection | A second `ifelse` for cp | Single `ifelse` on `T_up`, deterministic `cp_water` consumes the result | NRG-04 + Pattern 3 above — adding a redundant `ifelse` for cp doubles the symbolic graph for the energy-balance equation with no behavioral change. |

**Key insight:** STREAM.jl already has the right primitives — `@register_symbolic`, `ifelse`, `instream`, `Vector{Equation}`. Phase 53 is not introducing new mechanisms; it is consolidating existing equations from a flag-driven mutator into a pure-functional helper, and tightening the convective-term formula to match Python STREAM. Every "don't hand-roll" entry above is a hand-rolled wrapper that the existing primitives already cover.

## Coexistence Strategy: `_channel_core` and `_channel_base_eqs` in the Same File

CORE-02 mandates deleting `_channel_base_eqs`. D-13 mandates that variants compile and pass tests at every commit boundary. These constraints together require a coexistence window: from the commit that introduces `_channel_core` until the commit that deletes `_channel_base_eqs`, both helpers live in `src/components/channel.jl`.

**What Phase 53 needs to know about coexistence:**

1. **No name collisions.** `_channel_core` and `_channel_base_eqs` have different names; Julia method dispatch is by name first, then signature. They cannot collide. [VERIFIED — `grep -rn "_channel_core" src/ test/` returns no existing matches; the name is unused.]

2. **No mutation of shared state.** Both helpers operate on caller-supplied `eqs::Vector{Equation}` and `obs::Vector{Equation}`. The new `_channel_core` is *pure* (returns its own freshly-allocated lists); the old `_channel_base_eqs` is a mutator (pushes into caller's list). They do not share lists, so they cannot accidentally interleave equations.

3. **No internal helper overlap.** `_channel_base_eqs` references `dittus_boelter`, `blasius_friction`, `mu_water`, `cp_water`, `k_water`, `rho_water`, `Differential(t)` — all top-level module functions. `_channel_core` will reference the same set (minus `dittus_boelter` since HTC is variant-internal per D-03), plus `_bergles_rohsenow_dT_ONB`, `sat_temperature` for T_ONB / T_sat. None of these are file-local helpers; no risk of internal-helper collision. [VERIFIED — `grep -n "function _" src/components/channel.jl` shows only `_channel_base_eqs`; introducing `_channel_core` adds one more underscore-prefixed function but they don't share helpers.]

4. **No dispatch confusion.** Both functions have keyword-only signatures (`function _channel_core(; ...)`, `function _channel_base_eqs(eqs; ...)`). Different names, different positional shapes — no ambiguity. The `eqs` first-positional argument on `_channel_base_eqs` is a vestige of the mutator pattern; `_channel_core` has no positional args. [VERIFIED by reading the existing signature at `channel.jl:172-194`.]

5. **Risk if PHASE 53's `_channel_core` definition shadows or overrides anything during file reload.** Julia's `Revise.jl` workflow (CLAUDE.md "Performance — Sysimage" recommends a persistent REPL) handles re-definition of functions cleanly. But: if a variant constructor is *invoked* between the introduction of `_channel_core` and a downstream test that relies on Phase 54 wiring, calling the variant still hits `_channel_base_eqs`. That is the intended behavior during Phase 53 — the new tests live in `test_channel_core.jl` and exercise *only* `_channel_core` via stub scaffolds; existing `test_channel.jl` tests exercise variants which still use `_channel_base_eqs`.

6. **Deletion mechanic at final commit.** Single `git rm`-like edit: delete lines 146-249 of `channel.jl` (the `_channel_base_eqs` block including its docstring/comment header). Verification grep: `grep -rn '_channel_base_eqs' src/ test/` must return zero hits — that's the CORE-02 acceptance gate. (Note: the docstring at the top of `channel.jl:1` mentions "_channel_base_eqs helper" — that comment also needs to go.) [VERIFIED — `grep -n "_channel_base_eqs" src/ test/` shows hits only at `channel.jl:1, 148, 172` (definitions/comments) and `thermal_channel.jl:109, 322` (call sites). The call sites stay until Phase 54.]

**Implication for the planner:** The coexistence window is bounded — it starts when `_channel_core` is committed and ends in the final Phase 53 commit when `_channel_base_eqs` is deleted. During that window, the file `src/components/channel.jl` contains both the public `Channel` constructor (lines 26-144), `_channel_base_eqs` (lines 172-249), and the new `_channel_core` (appended). No risk of dispatch confusion.

## Common Pitfalls

### Pitfall 1: `@register_symbolic` boundary across face-averaged cp
**What goes wrong:** A future maintainer might "optimize" `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2` by extracting it into a helper function `face_avg_cp(T_up, T_i) = (cp_water(T_up) + cp_water(T_i))/2` without `@register_symbolic`-ing the helper. Then `face_avg_cp(some_Num, some_Num)` traces inside Symbolics, expanding the average — but if anyone later wraps the helper in `@register_symbolic`, MTK loses visibility into the Simantov formula and KINSOL initialization can fail differently.
**Why it happens:** `cp_water` is registered (`fluids.jl:146`); composition of registered functions through plain arithmetic IS symbolic-graph-correct. But people who don't read CLAUDE.md confuse "cp_water is registered" with "anything calling cp_water needs to be registered."
**How to avoid:** **Do not wrap the average in a helper.** Inline `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2` directly inside the energy-balance loop. Plain Julia arithmetic on two `cp_water(...)` Num nodes is exactly what MTK expects. CLAUDE.md "MTK Patterns" documents this: "`@register_symbolic` wraps them as opaque nodes ... allowing them to appear in MTK equations without being traced or differentiated symbolically." Composition via `+` and `/` is fine.
**Warning signs:** Any new wrapper function in `src/fluids.jl` or `src/components/channel.jl` that takes two T arguments and returns an average. Reject in code review.

### Pitfall 2: `cp_water` evaluated at solver-initialization sentinel temperatures
**What goes wrong:** During `mtkcompile`'s initialization phase, KINSOL may probe symbolic variables at `0.0` (Float64 default for unknowns without explicit defaults). `cp_water(0.0)` evaluates: `T_C = abs(-273.15) = 273.15`; the polynomial `(A + C*T_C)` may go negative. The function already guards with `sqrt(max(0.0, ...))` at `fluids.jl:51` precisely for this — output stays finite. **No bug.**
**Why it happens:** `T[i] = fill(600.0, n)` IC at `channel.jl:47` and `thermal_channel.jl:70` mitigates this for the channel variants — but `_channel_core`'s test scaffolds may declare `@variables (T(t))[1:n]` without defaults. The Stub recipient pattern in `test_connectors.jl:41` uses `fill(300.0, n)` defaults.
**How to avoid:** Phase 53 test scaffolds MUST declare `T` with a positive default (e.g. `(T(t))[1:n] = fill(300.0, n)`), matching the precedent set by `_StubRecipient`. The denominator `rho_water(T[i]) * cp_water(T[i]) * A * dz` cannot go through zero without the IC default. CONTEXT.md does not mandate this explicitly but it is a precondition for any `solve_*` to converge in the scaffold.
**Warning signs:** `mtkcompile` succeeds but `solve_steady` returns `ReturnCode.MaxIters` or `Failure` with `dt < dtmin` — symptomatic of the denominator going to zero somewhere.

### Pitfall 3: cp denominator vs numerator non-cancellation (NRG-03)
**What goes wrong:** A reviewer or future maintainer could re-introduce a constant-cp shortcut by noticing that the numerator's `cp_face` cancels with the denominator's `cp_water(T[i])` *only if* `cp_face = cp_water(T[i])` — which is the constant-cp limit. They might then "factor out" the cp from numerator and denominator, eliminating cp_face entirely and reverting NRG-01.
**Why it happens:** The two `cp_water` calls *look* like they should cancel because they're both `cp_water` of *something*. But `cp_water(T_up)` and `cp_water(T[i])` are evaluated at different temperatures — the numerator uses face-averaged cp (`(cp(T_up) + cp(T[i]))/2`), the denominator uses local cp (`cp(T[i])`). They cancel only if `T_up == T[i]` (no flow gradient).
**How to avoid:** **Grep audit at code review.** The planner should specify a verification step in the plan: `grep -nE 'cp_water\(.*\)' src/components/channel.jl` should show **at least three** distinct cp_water invocations on different lines of the energy-balance equation:
  1. `cp_water(T_up)` (face-average term, numerator)
  2. `cp_water(T[i])` (face-average term, numerator)
  3. `cp_water(T[i])` (denominator)
The two `T[i]`-arg invocations on lines 1 and 3 of the formula are textually identical but live in distinct syntactic positions (numerator inside `cp_face`, denominator inside `rho_water(T[i]) * cp_water(T[i]) * A * dz`). Grep for `cp_water` should return **a strictly higher count of matches** in the new energy balance than in the old `Dt(T[i]) ~ (... cp_water(T[i]) * (T_up - T[i]) ...) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)` (current `channel.jl:81-83`, which has only 2 cp_water calls per cell). [VERIFIED by counting in `channel.jl:81-83` — current has exactly two `cp_water` mentions per cell; new must have three.]
**Warning signs:** Phase 53's grep audit shows the new energy-balance loop has only 2 `cp_water` calls per cell (same as old) — that's the cancelled-out constant-cp form, NRG-01 violation.

### Pitfall 4: Premature deletion of `_channel_base_eqs`
**What goes wrong:** A planner that interprets CORE-02 as "delete the helper as soon as `_channel_core` exists" creates a commit where CAC and ChannelHeatFlux fail to compile because their `_channel_base_eqs(eqs; ...)` calls hit a NameError. The variants don't get rewritten until Phase 54.
**Why it happens:** Reading CORE-02 in isolation, without D-13's "variants must continue to compile and pass their existing tests at every commit boundary inside Phase 53."
**How to avoid:** Stage the work in three commit groups: (1) introduce `_channel_core` and the scaffold tests; (2) verify Stage-1, Stage-2, mirror, and branch-coverage tests pass + existing variants still pass their tests; (3) delete `_channel_base_eqs` ONLY after Phase 54's variant rewrites land. **Crucial:** Phase 53's final commit cannot delete `_channel_base_eqs` because Phase 54 hasn't started yet — CAC and ChannelHeatFlux still call it. The deletion of `_channel_base_eqs` has to be the LAST commit of Phase 53 ONLY IF Phase 54 also lands before any release / merge — which CONTEXT.md clarifies is not the case (Phase 53 closes when `_channel_core` exists and `_channel_base_eqs` is gone).
**Resolution of the conflict:** Re-read CONTEXT.md §"Phase Boundary": *"Phase 53 closes when `_channel_core` exists, `_channel_base_eqs` is gone, and the new core is verified..."* This implies that during Phase 53 we must NOT have `_channel_base_eqs` and the variants. **Therefore the variants need a temporary path through Phase 53.** Two viable paths the planner can pick from:
  - **Option A:** Phase 53 deletes `_channel_base_eqs` and *temporarily inlines its body* into both variant constructors (CAC and ChannelHeatFlux). Phase 54 then rewrites the inlined bodies onto `_channel_core`. **Pros:** clean Phase 53 close. **Cons:** more code motion in Phase 53, more chance for bugs.
  - **Option B:** Phase 53 introduces `_channel_core`, the scaffold tests prove it works, but `_channel_base_eqs` stays in the file for Phase 54 to delete as the final step of its variant-rewrite work. **Pros:** Phase 53 is purely additive (lower risk). **Cons:** CORE-02 isn't satisfied until Phase 54 lands.

  **Planner's call.** [Cited reading of CONTEXT.md §"Phase Boundary": "Phase 53 closes when ... `_channel_base_eqs` is gone"] — this favors Option A. But STATE.md "Implementation strategy" explicitly defers commit granularity to the planner, so either option is consistent with the locked decisions. Surfacing for `/gsd-discuss-phase` if needed. **Research recommendation: Option A**, because it keeps CORE-02 strictly inside Phase 53 (matches the milestone's "phase scope discipline" pattern from STATE.md) and the inlining is mechanical.

**Warning signs:** Failed test on a Phase 53 commit that says "_channel_base_eqs not defined" — the planner deleted too early, before the variants were inlined or rewired.

### Pitfall 5: Dead branch in core (CORE-05) from over-eager generality
**What goes wrong:** The author of `_channel_core` adds an `if mdot_threshold !== nothing` or `if heated_parts isa Tuple` branch "just in case" — which is untested by any variant in Phase 53 (or 54), violating CORE-05.
**Why it happens:** Defensive programming instinct, especially when the function is private and "could be useful later."
**How to avoid:** Branch-coverage matrix in the test plan (see §"Validation Architecture" → "Code-Path Coverage Matrix"). Every `if` / `ifelse` / kwarg dispatch inside `_channel_core` must have a corresponding row in the matrix that names the test triggering it. If a row says "no test triggers this branch" — delete the branch.
**Warning signs:** A branch in `_channel_core` whose triggering condition cannot be expressed by any of the three Phase 54 variants' q expressions.

### Pitfall 6: `compose(System(eqs, t, all_vars, pars; observed=obs, name=name), port_in, port_out)` semantics with spliced eqs
**What goes wrong:** A planner who hasn't re-read MTK 11.x docs assumes that splicing `core.eqs` into the variant's `eqs` after the fact requires a `flatten()` or special call. It does not — `Vector{Equation}` concatenation `[a; b]` produces a single flat list, and `System(...)` accepts that directly. `compose(...)` adds the port subsystems regardless of which equations were appended by which helper.
**Why it happens:** Confusion between MTK 11.x's `compose()` (assembles subsystems) and `extend()` (combines equation sets) — the planner might think the spliced helper output requires `extend()`.
**How to avoid:** Stick to the `[variant_eqs; core.eqs]` concatenation pattern. The current `_channel_base_eqs` mutator pushes into the same `eqs` vector the variant later passes to `System(...)` — this is exactly the same shape, just with the splicing made explicit. [VERIFIED by reading `thermal_channel.jl:109-189` which already mixes `_channel_base_eqs` output with variant-specific energy-balance equations and passes the merged list to `System(...)` at `:235`.]
**Warning signs:** `mtkcompile` warnings about duplicate equations or "unbalanced equation set" — usually a sign the splicing accidentally double-counted port wiring.

### Pitfall 7: `obs` ordering and observed-to-observed chains
**What goes wrong:** Core's `obs` includes `T_ONB[i]` whose RHS is `sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i)`. If the planner accidentally writes `T_ONB[i] ~ T_sat[i] + _bergles_rohsenow_dT_ONB(P[i], q_wall[i] / (...))` — referencing `T_sat[i]` and `P[i]` (observed-to-observed chain) — `mtkcompile` emits a warning and may fail to resolve the algebraic substitution.
**Why it happens:** It's syntactically tempting to reuse `T_sat[i]` since we just defined it. The existing CAC code documents this carefully at `thermal_channel.jl:215-216`: "use P_i expression (not P[i] symbol) to avoid observed-to-observed chain."
**How to avoid:** Inside the per-cell loop in core, build `P_i` as a Julia expression (not the Num symbol `P[i]`), then reuse `P_i` for `T_sat[i]` and `T_ONB[i]` RHS. Use `q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)` (Julia local) for `T_ONB[i]`, NOT `q_wall[i]` (Num observable).
**Warning signs:** `mtkcompile` warning "observed-to-observed loop" or "could not solve observable equation."

## Code Examples

Verified patterns from existing STREAM.jl source:

### Example 1: Energy-balance equation in enthalpy form

```julia
# Source: D-06 (CONTEXT.md), patterned after src/components/thermal_channel.jl:164-175
T_inlet_fwd = instream(port_in.T)
T_inlet_rev = instream(port_out.T)
for i in 1:n
    T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
    T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
    T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
    cp_face = (cp_water(T_up) + cp_water(T[i])) / 2     # NRG-01 (numerator face-averaged)
                                                        # NRG-02 (boundary uses ifelse-selected T_up)
                                                        # NRG-04 (single ifelse propagates through cp_water)
    push!(eqs,
        Dt(T[i]) ~ (
            abs(port_in.mdot) * cp_face * (T_up - T[i])
          + q_left_expr[i]
          + q_right_expr[i]
        ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz)  # NRG-03 (denominator: local cp_water(T[i]))
    )
end
```

### Example 2: Inline P[i] / T_sat[i] / T_ONB[i] observable construction (no observed-to-observed chain)

```julia
# Source: src/components/thermal_channel.jl:217-223 (CAC), generalized for q_left_expr/q_right_expr
for i in 1:n
    P_i = port_in.P - sum(dp[j] for j in 1:i) -
          (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
    push!(obs, P[i] ~ P_i)
    push!(obs, T_sat[i] ~ sat_temperature(P_i))
    q_density_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
    push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_density_i))
end
```

### Example 3: Variant call site with `(; eqs, obs)` splicing

```julia
# Source: D-01 (CONTEXT.md), illustrative
# (This is what Channel/ChannelHeatFlux/ChannelAndContacts will look like after Phase 54.
#  Phase 53 itself does not change the variant call sites — it only adds _channel_core
#  and the scaffold tests that exercise it directly.)
q_left_expr  = [thermal_left[i].h * geometry.heated_parts[1] * dz * (thermal_left[i].T_wall - T[i]) for i in 1:n]
q_right_expr = [thermal_right[i].h * geometry.heated_parts[2] * dz * (thermal_right[i].T_wall - T[i]) for i in 1:n]

core = _channel_core(;
    n, T, dp, port_in, port_out, geometry, g_acc=g,
    friction_correlation,
    q_left_expr, q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB,
    q_wall, q_wall_left, q_wall_right,
    T_out, dP,
)

# Variant-specific equations (e.g. CAC's h_tc, Q_flow per port, Q_wall_total)
variant_eqs = Equation[]
variant_obs = Equation[]
# ... append CAC-only equations ...

eqs = [variant_eqs; core.eqs]
obs = [core.obs; variant_obs]

compose(
    System(eqs, t, all_vars, pars; observed=obs, name=name),
    port_in, port_out, thermal_left..., thermal_right...,
)
```

### Example 4: Phase 53 stub harness (precedent: `_StubRecipient` from `test/test_connectors.jl:33-88`)

```julia
# Source: pattern from test/test_connectors.jl:33-88; new helper for _channel_core
function _StubChannelCore(; name, n::Int,
                          q_left_vals::Vector{Float64}=zeros(n),
                          q_right_vals::Vector{Float64}=zeros(n),
                          geometry=PipeGeometry_circular(0.6, 0.01),
                          g_acc=0.0)
    @named port_in  = FlowPort()
    @named port_out = FlowPort()

    pars = @parameters begin
        L = geometry.L
        D_h = geometry.Dh
        A = geometry.A
        g_acc = g_acc
    end
    vars = @variables begin
        (T(t))[1:n]   = fill(600.0, n)
        (dp(t))[1:n]  = fill(100.0, n)
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 600.0
        dP(t)
    end

    # Driven q expressions — placeholder that exercises core's per-cell formula
    q_left_expr  = [Num(q_left_vals[i])  for i in 1:n]
    q_right_expr = [Num(q_right_vals[i]) for i in 1:n]

    core = _channel_core(;
        n, T, dp, port_in, port_out, geometry, g_acc=g_acc,
        friction_correlation=blasius_friction,
        q_left_expr, q_right_expr,
        Re, Pe, v, P, T_sat, T_ONB,
        q_wall, q_wall_left, q_wall_right,
        T_out, dP,
    )
    all_vars = [collect(T); collect(dp); T_out]
    sys = System(core.eqs, t, all_vars, pars; observed=core.obs, name=name)
    return compose(sys, port_in, port_out)
end
```

The harness follows the `_StubRecipient` precedent: file-local helper, not exported, declared inline at the top of `test_channel_core.jl`. The driven-q kwargs replace `_StubRecipient`'s `drive_left`/`drive_right` BitVectors — for `_channel_core` the analogue is "what numerical heat-flux profile do I want to drive into the energy balance to exercise the formula?"

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test.jl (Julia stdlib) |
| Config file | none — `test/runtests.jl` is the orchestrator |
| Quick run command | `julia --sysimage stream.so --project=. test/test_channel_core.jl` (sysimage if present, else without) |
| Full suite command | `test -f stream.so && SYSIMG="--sysimage stream.so" \|\| SYSIMG=""; julia $SYSIMG --project=. test/runtests.jl` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORE-01 | `_channel_core(; ...)::NamedTuple{(:eqs, :obs)}` exists with the locked signature | structural unit | `julia --project=. -e 'using STREAM; @assert isdefined(STREAM, :_channel_core)'` (and a testset that calls `_channel_core(...)` with stub args and asserts `isa NamedTuple{(:eqs, :obs)}`) | ❌ Wave 0 (test_channel_core.jl new) |
| CORE-02 | `_channel_base_eqs` is fully removed | grep gate | `! grep -rn '_channel_base_eqs' src/ test/` (must return zero hits) | runs at phase verification step |
| CORE-03 | No `observed_mode` flag anywhere | grep gate | `! grep -rn 'observed_mode' src/` | runs at phase verification step |
| CORE-04 | No `skip_htc` flag anywhere | grep gate | `! grep -rn 'skip_htc' src/` | runs at phase verification step |
| CORE-05 | Every code path in `_channel_core` exercised by ≥1 scaffold | branch-coverage matrix testset | `julia --project=. test/test_channel_core.jl` (testset "CORE-05: branch coverage matrix") | ❌ Wave 0 |
| NRG-01 | Convective numerator uses `(cp(T_up) + cp(T[i]))/2` | symbolic-equation unit + Stage-2 hand-compute | `julia --project=. test/test_channel_core.jl` (testset "NRG-01: face-averaged cp in numerator" — extracts Dt(T[i]) RHS via `equations(...)` and asserts the symbolic form) | ❌ Wave 0 |
| NRG-02 | Boundary face uses `cp(instream(port_in.T))` / `cp(instream(port_out.T))` | symbolic-equation unit | (testset "NRG-02: boundary cp uses instream") — asserts cell-1 forward-flow RHS contains `cp_water(instream(port_in.T))` substring | ❌ Wave 0 |
| NRG-03 | Denominator retains local `cp(T[i])`; cp values do not cancel | grep + symbolic-equation unit + Stage-2 hand-compute | `grep -nE 'cp_water' src/components/channel.jl \| wc -l` (compare to old count); also testset "NRG-03: cp denominator non-cancellation" asserts numerical T_out differs from constant-cp baseline by > 0 in a high-dT setup | ❌ Wave 0 |
| NRG-04 | Single `ifelse` selects upstream T and (deterministically) cp | single-cell mirror test | testset "NRG-04: forward/reverse flow mirror" (see "Single-Cell Mirror Test" below) | ❌ Wave 0 |

### Stage 1 — Constant-cp Limit (sanity vs v1.0 baseline)

**Goal:** Confirm `_channel_core` plus the new enthalpy-form energy balance degenerates to the old constant-cp form when cp(T) is approximately constant over the cell-T range. Catches gross structural errors (wrong indexing, wrong sign, wrong port wiring).

**Setup:**
- Geometry: `PipeGeometry_circular(L=0.6, D=0.01)`, n=10 (matches `build_loop` baseline)
- Inlet boundary: `T_inlet = 313.15 K` (matches existing `THERM-03` test in `test_channel.jl:144`)
- Driven q profile: uniform per cell, `q_left_vals = fill(q0, n)`, `q_right_vals = zeros(n)`, with `q0` chosen so the steady-state outlet rise is `dT_out ≈ 1 K`. At ρ·cp ≈ 4.2e6 J/(m³·K), A·L = 4.71e-5 m³, mdot ≈ 0.49 kg/s, total Q ≈ mdot·cp·dT_out ≈ 0.49·4180·1 ≈ 2050 W → `q0 = 2050/n ≈ 205 W/cell`.
- Loop: `Pump(dP=3e4) → HeatExchanger(T_inlet) → _StubChannelCore(...) → Pump`, pressure anchor `pump.port_in.P ~ 1.0e5`.

**Tolerance:** `~1e-6 rtol` on `T_out`, `port_in.mdot`, and per-cell `T[i]` against pre-recorded v1.0 baseline (extracted from the *current* `Channel` solve on the same geometry/q profile *before* the energy-balance switch is committed).

**Reference-data source:** Pre-record once, manually: extract `T_out` and `T[i]` from running the current `Channel` (which calls `_channel_base_eqs`) on the same loop with `T_wall` chosen to match the same `q0 = h*A*(T_wall − T)` flux. Save as a Julia constant in `test_channel_core.jl`, e.g. `const STAGE1_BASELINE_T_OUT = 314.165`. **The pre-recording happens BEFORE the energy-balance switch lands** — i.e., the baseline is captured against unmodified `_channel_base_eqs` output. Once recorded, Phase 53 implementation must pass against this baseline; Stage-1 is the structural-error gate.

**What Stage 1 catches:**
- Wrong sign on convective term
- Wrong indexing of `T_up` vs `T[i-1]/T[i+1]`
- Wrong indexing of `q_left_expr[i]`
- Missing port wiring (mass conservation, momentum ODE)
- Wrong direction of cp_face cancellation in the constant-cp limit

**What Stage 1 does NOT catch:** drift in cp-averaging itself (because cp is constant, the averaging is irrelevant). That's Stage 2's job.

### Stage 2 — Realistic cp variation (Python parity hand-compute)

**Goal:** Confirm the new face-averaged cp formula agrees with Python STREAM's `pair_mean_1d` to machine precision. This is the gate that validates the cp-averaging itself, not just the equation skeleton.

**Setup:**
- Geometry: `PipeGeometry_circular(L=0.6, D=0.01)`, n=5 (smaller for manual computation)
- Inlet: `T_inlet = 313.15 K` (40°C)
- Driven q profile: uniform per cell, `q_left_vals = fill(q0, n)`, `q_right_vals = zeros(n)`, with `q0` chosen so the outlet rise is `dT_out ≈ 30 K` — pushing cp from ~4180 J/(kg·K) at 313 K to ~4200 J/(kg·K) at 343 K (~3% variation, the regime where the enthalpy form differs from constant-cp-effective by an observable amount).
- Compute `q0` to drive 30 K rise: `Q_total = mdot · ⟨cp⟩ · 30`, with mdot ≈ 0.49 kg/s, `⟨cp⟩ ≈ 4190` → `Q_total ≈ 61,600 W` → `q0 ≈ 12,300 W/cell`.

**Hand-compute:** In a Python script (run once, recorded as Julia constants in the test):
```python
import numpy as np
from stream.fluid import light_water  # or equivalent
T_inlet = 313.15  # K
T_guess = np.array([313.15, ...])  # iterate to convergence on the analytical formula
q0 = 12_300.0
for iteration in range(50):
    rho   = light_water.density(T_guess)
    c_bulk = light_water.specific_heat(T_guess)
    cin   = light_water.specific_heat(T_inlet)
    c     = pair_mean_1d(c_bulk, prepend=cin)  # face-averaged cp at each cell-i face
    # steady-state: 0 = |mdot|·c·(T[i-1] - T[i]) + q0; solve for T[i] sequentially
    T_new = ... # forward sweep using c[i] for face i
    if np.allclose(T_new, T_guess, rtol=1e-12):
        break
    T_guess = T_new
print(repr(T_guess))  # paste into test_channel_core.jl as STAGE2_REFERENCE_T
```

Save the converged `T[i]` array as `const STAGE2_REFERENCE_T = [313.15, 320.7..., 327.6..., 333.9..., 339.8...]` (placeholder values; the recording step computes the real ones).

**Tolerance:** `~1e-9 rtol` on `T[i]` for i=1..n. This is tighter than Stage 1 because we are comparing against the analytical solution to the *same* discretized formula, not against numerical-precision-limited fluid properties.

**Why 1e-9 not 1e-12:** the Julia `cp_water` (Simantov correlation, `src/fluids.jl:45-52`) evaluates a sqrt of a polynomial; round-off accumulates over the n forward-sweep steps. 1e-9 leaves headroom for that. Going tighter (1e-12) risks flaky tests on different machines / Float64 representations.

**What Stage 2 catches:**
- Wrong cp averaging direction (e.g. `pair_mean_1d` vs `pair_mean_2d`)
- Wrong handling of the `prepend=cin` boundary case
- Sign error in `directed(...)` reverse-flow flip (mirrored separately by §"Single-Cell Mirror Test")
- Missing factor of 2 in face averaging
- Off-by-one in upstream-vs-downstream selection for cp's neighbor

**What Stage 2 does NOT catch:** structural errors in port wiring, friction, momentum (those are Stage 1's job). The two stages are complementary.

### Single-Cell Mirror Test

**ROADMAP success criterion #4:** "the same `ifelse(mdot ≥ 0, ...)` expression that selects upstream T also selects upstream cp; a focused unit test on a single-cell channel asserts forward and reverse runs are mirror images of each other."

**Setup:**
- n=1 (single cell), trivial geometry `PipeGeometry_circular(L=0.1, D=0.01)`
- Same driven-q profile in both runs: `q_left_vals = [Q]`, `q_right_vals = [0.0]` for some fixed `Q ≈ 1000 W`.
- Forward run: `Pump(mdot0=+0.1)`, inlet `T_in_fwd = 320 K`, outlet `T_out_fwd` measured at steady state.
- Reverse run: `Pump(mdot0=-0.1)` (negative ⇒ flow goes port_out → port_in), inlet `T_in_rev = 320 K` (now applied at the *other* port via `instream(port_out.T)`), outlet `T_out_rev` measured.

**Assertion (mirror image):**
```julia
dT_fwd = sol_fwd[ssys.stub.T_out] - T_in_fwd       # rise from inlet to outlet, forward
dT_rev = sol_rev[ssys.stub.T[1]]   - T_in_rev       # rise from inlet to outlet, reverse
                                                    # (T[1] is now the OUTLET cell under reverse flow,
                                                    #  because port_in is downstream)
@test isapprox(dT_fwd, dT_rev; rtol=1e-12)
```

**Why 1e-12 rtol (not 1e-9 like Stage 2):** The mirror test compares the same scalar quantity computed by the same compiled MTK system run twice with sign-flipped inputs. There is no analytical reference being approximated — the comparison is symbolic-mirror-symmetric. Numerical drift comes only from solver tolerances, which `solve_steady` (KINSOL) controls to ~1e-10 by default. 1e-12 is the right tolerance for "mirror-image identity" assertions; if the test fails at 1e-12 but passes at 1e-8, that's a real symmetry violation worth investigating (e.g., the `ifelse` boundary-face selection is asymmetric somewhere).

**What this catches:** Any asymmetry between `T_up_fwd = T_inlet_fwd` (cell 1 forward) and `T_up_rev = T_inlet_rev` (cell n=1 reverse) propagation through `cp_water(...)`. Because `cp_water` is deterministic, the ifelse-selected branches must mirror exactly — if they don't, NRG-04 is violated.

**Subtle reading of the mirror identity:** The cleanest formulation is *not* `T_out_forward(T_in_forward) - T_in_forward == -(T_out_reverse(T_in_reverse) - T_in_reverse)`. Forward and reverse heating of the *same* cell with the *same* heat flux produce the *same dT* (energy added is the same; cp(T) at the cell-T is the same). The mirror is in the **direction of T propagation through the channel** — forward-flow makes cell 1 cooler than cell n; reverse-flow makes cell n cooler than cell 1. For n=1 there is only one cell, so the mirror reduces to "same dT regardless of mdot sign," which IS the identity above (with both sides of the equation positive). [This corrects the objective's framing: the negative-sign mirror is for *spatial* T(z) profile, not for the inlet-to-outlet rise of a single cell. The single-cell version uses absolute equality.]

For a multi-cell version (which Phase 53 may also want, separate testset):
```julia
n = 3
# Forward: T_in_fwd = 313, T_out_fwd at ssys.stub.T[3]; profile T[1] < T[2] < T[3]
# Reverse: T_in_rev = 313 (now applied at port_out side), T_out at ssys.stub.T[1];
#                                  profile T[3] < T[2] < T[1]
# Mirror: sol_rev[T[i]] should equal sol_fwd[T[n+1-i]] for all i
@test isapprox(sol_rev[ssys.stub.T[1]], sol_fwd[ssys.stub.T[3]]; rtol=1e-12)
@test isapprox(sol_rev[ssys.stub.T[2]], sol_fwd[ssys.stub.T[2]]; rtol=1e-12)
@test isapprox(sol_rev[ssys.stub.T[3]], sol_fwd[ssys.stub.T[1]]; rtol=1e-12)
```

The single-cell version is the cleanest sanity check and the one ROADMAP §4 explicitly mandates; the multi-cell version is a useful extension.

### Code-Path Coverage Matrix (CORE-05)

**ROADMAP success criterion #5:** "Every code path inside `_channel_core` is exercised by at least one variant — no dead branches remain after the core is wired up against placeholder `q_left_expr`/`q_right_expr` arguments in test scaffolding."

Phase 53 is BEFORE Phase 54 wires variants onto the core, so coverage in Phase 53 is via placeholder scaffolds only. The strategy:

1. **List every branch in `_channel_core`.** During implementation, the planner enumerates: every `if` / `ifelse` / `for i in 1:n` (the `i==1`/`i==n` boundary cases inside the loop). The expected branches are:
   - `T_up_fwd = (i == 1) ? T_inlet_fwd : T[i-1]`  → trace-time `?:` collapses per-i
   - `T_up_rev = (i == n) ? T_inlet_rev : T[i+1]`  → trace-time `?:` collapses per-i
   - `T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)` → runtime branch on flow direction
   - `friction_correlation` kwarg dispatch (different correlation functions emit different friction forms)
   - The summation indexing `sum(dp[j] for j in 1:i)` and `sum(dp[j] for j in 1:n)` for P[i] (cell-position-dependent summand counts; trace-time)
2. **For each branch, identify the placeholder configuration that triggers it.** A test-matrix table:

| Branch in `_channel_core` | Triggering Configuration | Test Name |
|---------------------------|--------------------------|-----------|
| Cell-1 forward flow (`i==1`, `mdot ≥ 0`) | n=3, `Pump(mdot0=+0.5)`, `q_left_vals=[100,100,100]` | "branch-coverage: cell-1 forward" |
| Cell-n reverse flow (`i==n`, `mdot < 0`) | n=3, `Pump(mdot0=-0.5)`, same q profile | "branch-coverage: cell-n reverse" |
| Interior cell forward (`1 < i < n`, `mdot ≥ 0`) | Same n=3 forward run; cell 2 is interior | (asserted in same testset as cell-1 forward) |
| Interior cell reverse (`1 < i < n`, `mdot < 0`) | Same n=3 reverse run; cell 2 is interior | (asserted in same testset as cell-n reverse) |
| `ifelse` forward branch (`mdot >= 0`) | mdot positive throughout | covered by every Stage-1 / Stage-2 test |
| `ifelse` reverse branch (`mdot < 0`) | Mirror test (n=1 reverse, n=3 reverse) | "NRG-04: forward/reverse flow mirror" |
| `friction_correlation = blasius_friction` (default) | All Stage-1 / Stage-2 tests | covered by Stage-1 |
| `friction_correlation = laminar_friction(K_R=0.685)` (alternate) | One Stage-1 testset that overrides the kwarg | "branch-coverage: alternate friction kwarg" |
| `q_left_expr[i] = 0`, `q_right_expr[i] = 0` (adiabatic) | `q_left_vals = q_right_vals = zeros(n)`, expect `Dt(T) = 0` | "branch-coverage: adiabatic baseline (no q)" |
| `q_left_expr[i] ≠ 0`, `q_right_expr[i] = 0` (one-sided heating) | All Stage-1 / Stage-2 tests | covered by Stage-1 |
| `q_left_expr[i] = 0`, `q_right_expr[i] ≠ 0` (mirror-side heating) | One testset with `q_left_vals = zeros(n)`, `q_right_vals = fill(q0, n)`, expect same `T_out` rise as left-only run | "branch-coverage: right-side-only heating" |
| `q_left_expr[i] ≠ 0`, `q_right_expr[i] ≠ 0` (two-sided heating) | One testset with both filled (CAC-like) | "branch-coverage: two-sided heating" |
| Pe-as-observable (`Pe[i] ~ Re[i] * Pr_i`) | All Stage-1 tests; assert `sol[stub.Pe[i]]` is finite | covered by Stage-1 retcode-success assertion |

If a row says "no triggering configuration exists in scaffold" — **delete the branch from `_channel_core`** (CORE-05). Conversely, if the planner discovers a branch in `_channel_core` not in this matrix, add a row before merging.

### Sampling Rate
- **Per task commit:** `julia --sysimage stream.so --project=. test/test_channel_core.jl` (~5-10s incremental) + `julia --sysimage stream.so --project=. test/test_channel.jl` (regression check; ~30s)
- **Per wave merge:** `julia $SYSIMG --project=. test/runtests.jl` (full suite; ~3-5 min)
- **Phase gate:** Full suite green + `grep -rn '_channel_base_eqs\|observed_mode\|skip_htc\|T_wall_cells' src/ test/` returns zero hits (CORE-02, -03, -04 grep gates) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/test_channel_core.jl` — new file containing `_StubChannelCore` helper, Stage-1 testsets, Stage-2 testsets, NRG-04 mirror testset, branch-coverage matrix testsets. Estimate ~250 lines, ~12-15 testsets.
- [ ] `test/runtests.jl` — add `include("test_channel_core.jl")` line between line 6 (`test_channel.jl`) and line 7 (`test_sign_safety.jl`).
- [ ] Pre-recorded baseline values for Stage 1 (constant-cp limit) — captured BEFORE energy-balance switch is committed. Sourced from the current `Channel` solve.
- [ ] Pre-recorded baseline values for Stage 2 (Python `pair_mean_1d` hand-compute) — captured via a one-off Python script run against `/home/itayb/projects/STREAM/stream/`.

**Test placement recommendation: `test/test_channel_core.jl` (new file).**

**Rationale:**
- CLAUDE.md "Test placement rule": "test file mirrors src file. `components/channel.jl` → `test_channel.jl`. New component file → new test file." `_channel_core` is a NEW helper inside `channel.jl`, so a literal reading allows either `test_channel.jl` (mirrors the file `_channel_core` lives in) or `test_channel_core.jl` (mirrors the new conceptual unit, even though it shares the file).
- **The choice tips toward `test_channel_core.jl`** because:
  1. The new tests (Stage-1, Stage-2, mirror, branch-coverage) are conceptually distinct from the existing CHAN-*/GRAV-*/THERM-*/PHY-* tests in `test_channel.jl`. Bundling them risks confusion when a future debugger greps for a CORE-* / NRG-* test failure and finds it intermixed with COMP-01 stuff.
  2. `test_channel.jl` is already 958 lines (`wc -l` confirmed); appending 250+ more lines of stub-harness-and-mirror-tests pushes it past the comfortable single-file boundary.
  3. The Phase 52 precedent — `test_connectors.jl` was extended for new connector types rather than adding a `test_wallport.jl` — *almost* argues the other way, but the analogy breaks: WallPort/HeatFluxPort are the same kind of object as FlowPort/ThermalPort; `_channel_core` is a refactor target with substantially different test-shape (stub harnesses, hand-computed baselines, mirror identity) than `Channel` smoke tests.
  4. Phase 54 will consolidate `channel.jl` + `thermal_channel.jl` → `channels.jl`. At that point `test_channel.jl` becomes `test_channels.jl` (or stays — CLAUDE.md test rule mirrors "components/channel.jl" → "test_channel.jl"; consolidation may rename). `test_channel_core.jl` is a naming-stable companion that survives the file consolidation cleanly because `_channel_core` itself isn't being renamed.

The planner has discretion (D-12); the recommendation is `test_channel_core.jl` based on the four reasons above.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Constant-cp upwind energy balance: `Dt(T[i]) ~ |mdot|·cp(T[i])·(T_up − T[i]) + q_wall[i]` (current `channel.jl:81-83`) | Face-averaged cp enthalpy form: `Dt(T[i]) ~ |mdot|·((cp(T_up)+cp(T[i]))/2)·(T_up − T[i]) + q_left + q_right` (Phase 53) | This phase | Matches Python STREAM `coolant_first_order_upwind_dTdt` byte-for-byte; ~3% drift on real cp(T) variation now correct |
| `_channel_base_eqs` mutator with `observed_mode` / `skip_htc` / `T_wall_cells=nothing` flags | `_channel_core(; ...)::NamedTuple{(:eqs, :obs)}` pure function with `q_left_expr` / `q_right_expr` kwargs | This phase | One source of truth; no flag plumbing; CORE-01..05 satisfied |
| HTC correlation living inside the shared helper | HTC correlation lives ONLY inside `ChannelAndContacts` | This phase (D-03) | `Channel` and `ChannelHeatFlux` no longer carry an unused htc_correlation reference |
| Per-variant duplicated P[i] / T_sat[i] / T_ONB[i] observables | All emitted from `_channel_core` once (D-08) | This phase | No more drift between variants (e.g., `v[i]` definition differs between `Channel` and CAC currently — see CONTEXT.md "Specific Ideas") |

**Deprecated/outdated:**
- `_channel_base_eqs` itself: deleted by end of Phase 53.
- The `observed_mode=true` codepath inside `_channel_base_eqs` (`channel.jl:196-217`) — deleted with the helper.
- `T_wall_cells=nothing` default and the conditional `T_w_i = T_wall_cells === nothing ? T[i] : T_wall_cells[i]` (`channel.jl:204, 214`) — deleted.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `(; eqs, obs)` NamedTuple-returning helpers have no precedent in the broader MTK ecosystem (no Context7 lookup performed) | §"Architecture Patterns" Pattern 1 | Low — even if precedent exists, the STREAM-local convention stands; this affects only docstring framing, not implementation |
| A2 | KINSOL solver tolerance defaults are ~1e-10, justifying 1e-12 rtol on the mirror test | §"Validation Architecture" → "Single-Cell Mirror Test" | Medium — if KINSOL default is looser (e.g. 1e-8 abstol), the 1e-12 rtol mirror test is too tight and will be flaky. Mitigation: planner should add an explicit `abstol=1e-12, reltol=1e-12` argument to `solve_steady` in the mirror test, or relax the test tolerance to 1e-9 |
| A3 | Stage-2 hand-compute will converge to ~1e-9 rtol against Julia's Simantov `cp_water` after 50 iterations of forward-sweep solve | §"Validation Architecture" → "Stage 2" | Low — if the analytical iterate diverges or converges only to 1e-7, the test reference is rebaseline-able; the gate moves from 1e-9 to whatever the Python reference actually achieves |
| A4 | Phase 53 can adopt Option A (delete `_channel_base_eqs` + temporarily inline its body into the variants) for CORE-02 satisfaction without breaking THERM-01..03 / CHAN-01..03 / `build_loop_*` tests | §"Common Pitfalls" Pitfall 4 | Medium — if inlining `_channel_base_eqs` content into variants triggers a subtle MTK structural-analysis difference (e.g., different equation order changes Jacobian sparsity), we hit a regression unrelated to the energy-balance switch. Mitigation: Stage-1 + existing tests catch this, but it's a real possibility. Option B (keep `_channel_base_eqs` until Phase 54) is the safer fallback. **Planner should be aware this is the only judgment call where the safest path may technically violate the strict reading of CONTEXT.md "Phase 53 closes when ... `_channel_base_eqs` is gone." If Option B is chosen, the planner should surface in `/gsd-discuss-phase` for ratification.** |
| A5 | The current `_channel_base_eqs` does not push observable equations (only "unknown" equations); `_channel_core` returning both `(; eqs, obs)` is therefore an additive widening of the helper's mandate | §"Code Examples" Example 1, §"Architecture Patterns" Pattern 1 | Low — verified by reading `channel.jl:172-249` end to end; the helper pushes only `eqs::Vector{Equation}` and never builds observed equations. CAC/CHF push their observables outside the helper call. New helper consolidates both into a single shape. |

## Open Questions

1. **Should `_channel_core` accept a single `obs_vars::NamedTuple` kwarg, or list each obs symbol separately?**
   - What we know: D-10 leaves this open. Listing each separately means a long signature (Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP — 11 obs symbols). A single NamedTuple kwarg `obs_vars=(; Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP)` is more compact at the call site but means destructuring inside core.
   - What's unclear: which is more readable to the next maintainer (i.e., to me reading this in 6 months).
   - Recommendation: **List each separately at the top level of the kwarg list.** Reasons: (1) the call-site verbosity is a feature — it makes the contract between core and variant explicit; (2) destructuring inside core (`Re = obs_vars.Re; Pe = obs_vars.Pe; ...`) duplicates the symbol names anyway, so we get verbosity in either place; (3) IDE autocomplete on kwargs is friendlier than on destructured fields. The optional `_channel_core_obs_vars(; n)` helper from D-10 is a good middle ground if the planner wants to declare them in one block at the variant; that's a separate, additive helper.

2. **Should Stage-2 reference values be machine-pre-recorded (Python script committed to repo) or hand-computed-once (literal Julia constants)?**
   - What we know: D-11 mandates "hand-computed offline" with ~1e-9 rtol.
   - What's unclear: literal constants are fragile if Python STREAM's `cp_water` formula evolves; a script-recorded approach (run a Python helper, paste output) keeps reproducibility.
   - Recommendation: **Hand-computed-once with a Julia comment block citing the script.** Save the Python-side computation script as `test/data/stage2_reference.py` (committed), and the test file holds the resulting Float64 array as a `const` with a comment `# regenerated via test/data/stage2_reference.py`. If a future tweak to Simantov correlations invalidates the reference, the Python script is re-run; the test file is updated in a single edit.

3. **Does Phase 53 need to declare `(P(t))[1:n]` and other obs symbols as `@variables` inside `_channel_core` itself, or are they exclusively variant-declared?**
   - What we know: D-10 says variants declare them; core references by symbol.
   - What's unclear: when the test scaffold `_StubChannelCore` declares them, MTK's `compose(System(eqs, t, all_vars, ...), ...)` needs `all_vars` to list every unknown. The obs symbols are NOT in `all_vars` — they go in the `observed=...` kwarg. So the answer is: variant declares them via `@variables`, passes them to core, core uses them in `obs::Vector{Equation}`, and the variant adds them to its `observed=...` kwarg (the spliced `core.obs` does the work).
   - Recommendation: D-10 is unambiguous as written; planner just follows it. No actual gap — flagged here only to confirm I read it correctly.

## Environment Availability

> Phase 53 is purely code/config changes inside an existing Julia project. No new external tools.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All STREAM.jl work | ✓ (assumed; existing project) | 1.12 (per Project.toml `[compat] julia = "1.12"`) | — |
| ModelingToolkit.jl | Core helper, all tests | ✓ (existing dep) | 11.x (existing Manifest.toml) | — |
| Test.jl (stdlib) | All tests | ✓ (Julia stdlib) | bundled | — |
| OrdinaryDiffEq.jl | Stage-1 / Stage-2 / mirror transient tests | ✓ (existing) | (existing) | — |
| Sundials.jl (KINSOL) | `solve_steady` | ✓ (existing) | (existing) | — |
| Python 3.x + Python STREAM repo at `~/projects/STREAM/` | Stage-2 reference value pre-recording (one-off) | ✓ (per CONTEXT.md canonical refs) | (existing) | If unavailable: hand-compute with paper + calculator using the Simantov formula in `src/fluids.jl:45-52` for cp_water and the `pair_mean_1d` formula from CONTEXT.md |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** Python STREAM (only needed once, for Stage-2 reference; alternative is manual computation against the documented `pair_mean_1d` formula).

**Sysimage availability:** Per CLAUDE.md "Performance — Sysimage", `stream.so` is git-ignored and platform-specific. Tests should detect:
```bash
test -f stream.so && SYSIMG="--sysimage stream.so" || SYSIMG=""
julia $SYSIMG --project=. test/test_channel_core.jl
```
Same pattern as existing.

## Project Constraints (from CLAUDE.md)

- **Branching policy:** GSD must NOT create branches; user owns branch creation. Phase 53 stays on `channels-redesign`. `.planning/config.json` `git.branching_strategy` MUST stay `"none"`. [VERIFIED — config.json says `"branching_strategy": "none"`.]
- **File Structure Standard:** New component file → new test file (mirrors src). For Phase 53 specifically, `_channel_core` is added to existing `src/components/channel.jl` (not a new file), so the test placement rule technically allows either `test_channel.jl` or a new `test_channel_core.jl`. (Detailed rationale for choosing the latter is in §"Validation Architecture".)
- **Component authoring conventions:**
  - Internal helpers prefixed with `_` and not exported: `_channel_core` follows this. `Channel` exported (existing); `_channel_core` NOT exported. [VERIFIED via reading `src/STREAM.jl:27-44` — `Channel`, `ChannelHeatFlux`, `ChannelAndContacts` are exported; `_channel_base_eqs` is not, and `_channel_core` will not be.]
  - `name` is keyword-only on variant constructors — `_channel_core` doesn't have a `name` (it's a pure helper, not a System constructor) so this rule doesn't apply.
  - Every exported name has a docstring with description, Arguments, Returns. `_channel_core` is internal but should still have a docstring (the existing `_channel_base_eqs` does at `channel.jl:147-171`); follow precedent.
- **Exports:** Public exports declared in `STREAM.jl`. `_channel_core` is internal; do NOT add to export list. [VERIFIED — `_channel_base_eqs` is also not in any export list.]
- **MTK Patterns:**
  - `@register_symbolic` for fluid properties (`cp_water` etc.) — already in place, used as-is.
  - `ifelse()` for flow reversal — already in place at `channel.jl:72`, `thermal_channel.jl:166, 348`. New core uses same idiom.
  - `mtkcompile` before `solve` — caller (variant) responsibility, not core's.
  - `@observed` vs plain unknowns: core's `obs::Vector{Equation}` becomes the `observed=` kwarg of `System(...)`; the variant decides which Re/Pe/v/P/etc. symbols are unknowns vs observed by including them or not in `all_vars`. CONTEXT.md D-08 commits to "all observed" for the q-agnostic + q-derived obs set.
  - `vars=[]` for Inertia — not relevant to channel core.
- **Performance / Sysimage:** Persistent REPL + Revise.jl recommended; sysimage build via `./build_sysimage.sh` (bakes `STREAM` and `QuadGK` only). Tests that run as part of phase verification should `test -f stream.so && SYSIMG="--sysimage stream.so" || SYSIMG=""` to use the sysimage when present.

## Sources

### Primary (HIGH confidence)
- `/home/itayb/projects/STREAM.jl/src/components/channel.jl` (lines 1-249) — `Channel` constructor (lines 26-144) and `_channel_base_eqs` helper (lines 172-249). Read end-to-end.
- `/home/itayb/projects/STREAM.jl/src/components/thermal_channel.jl` (lines 1-396) — `ChannelAndContacts` (lines 48-241) and `ChannelHeatFlux` (lines 273-396). Read end-to-end.
- `/home/itayb/projects/STREAM.jl/src/connectors.jl` — `FlowPort`, `ThermalPort`, `WallPort`, `HeatFluxPort` definitions. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/src/fluids.jl` — `cp_water`, `rho_water`, etc. with `@register_symbolic` (lines 145-150). Read end-to-end.
- `/home/itayb/projects/STREAM.jl/src/STREAM.jl` — module entry point, export list. Read end-to-end. Confirmed `_channel_core` and `_channel_base_eqs` are not exported.
- `/home/itayb/projects/STREAM.jl/src/physical_models/friction/correlations.jl` — `blasius_friction` definition. Read first 40 lines.
- `/home/itayb/projects/STREAM.jl/test/test_connectors.jl` — `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver` precedent (lines 33-109). Read end-to-end.
- `/home/itayb/projects/STREAM.jl/test/test_channel.jl` (lines 1-100, 100-200) — existing CHAN-*/GRAV-*/THERM-* test patterns. Read first 200 lines.
- `/home/itayb/projects/STREAM.jl/test/runtests.jl` — orchestrator, 21 lines. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md` — locked decisions. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/.planning/REQUIREMENTS.md` — CORE-01..05, NRG-01..04 verbatim. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/.planning/STATE.md` — milestone history, key decisions. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/.planning/ROADMAP.md` — Phase 53 success criteria. Read end-to-end.
- `/home/itayb/projects/STREAM.jl/.planning/config.json` — `nyquist_validation: true` confirmed.
- `/home/itayb/projects/STREAM.jl/CLAUDE.md` — branching policy, File Structure Standard, MTK Patterns, Component authoring conventions. (Provided as system reminder.)
- `/home/itayb/projects/STREAM/stream/calculations/channel.py` lines 100-175 — `coolant_first_order_upwind_dTdt`. Confirmed enthalpy-form formula.
- `/home/itayb/projects/STREAM/stream/utilities.py` lines 355-555 — `pair_mean_1d` (lines 359-376) and `directed` (lines 537-551). Confirmed boundary-face averaging is identical to interior averaging with `prepend=cin`.

### Secondary (MEDIUM confidence)
- Bash audits — `grep -rn '_channel_base_eqs\|_channel_core' src/ test/` (5 hits, all expected); `grep -n "function _" src/components/channel.jl` (one match — the existing helper); `wc -l` of source/test files. All output cited in research where used.

### Tertiary (LOW confidence)
- None used. No WebSearch / WebFetch / Context7 queries performed — all findings grounded in existing source code and CONTEXT.md.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages, all existing patterns
- Architecture: HIGH — directly extends the `_channel_base_eqs`/variant-call-site shape that the codebase already uses; verified via Read across all touched files
- Pitfalls: HIGH — Pitfalls 1, 2, 3, 5, 6, 7 cite specific line numbers in existing code where the pitfall is already mitigated; Pitfall 4 (premature deletion of `_channel_base_eqs`) cites a direct reading of CONTEXT.md and is the only one with a non-trivial planner judgment call

**Research date:** 2026-05-06
**Valid until:** 2026-06-06 (30 days; the codebase moves slowly, the design is locked, only Phase 54 work would invalidate this research and that lands in a separate phase)

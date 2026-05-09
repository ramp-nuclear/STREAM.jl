---
phase: 54
plan: 02
subsystem: components
tags: [channels, channel-heat-flux, heatfluxport, var-02, d-06, d-07]
requires:
  - "Phase 54-01 channels.jl with `function Channel end` declaration + `_channel_core` + new passive-recipient `Channel`"
  - "Phase 53 _channel_core (q_left_expr/q_right_expr API contract; D-01..D-14)"
  - "HeatFluxPort connector (kept unchanged from Phase 52 D-03)"
provides:
  - "New passive-recipient `ChannelHeatFlux(; name, n, geometry, g, friction_correlation)` in `src/components/channels.jl` (D-06; minimal 5-kwarg signature)"
  - "q purely external via `HeatFluxPort` arrays per side per cell: `q_left_expr[i] = thermal_left[i].q_flux × heated_parts[1] × dz` (D-07)"
  - "Adiabatic-by-default CHF (HeatFluxPort IC `q_flux=0.0` + MTK Flow rule auto-zero on dangling Q_flow ⇒ q=0)"
affects:
  - "src/components/thermal_channel.jl (legacy CHF body gutted; CAC body preserved untouched for 54-03 — Rule 3 deviation, same precompile-blocking issue Wave 1 hit)"
tech-stack:
  added: []
  patterns:
    - "Passive-recipient flux channel: per-cell HeatFluxPort arrays, no internal htc, no scalar T_wall"
    - "q construction inline as Vector{Num}: q_left_expr[i] = port.q_flux × heated_parts × dz (no T[i] reference; CHF is a flux source, not Newton's-law-of-cooling)"
    - "Channel-side Q_flow ~ q_*_expr eqn for HeatFluxPort closure (combined with MTK Flow rule on dangling ports → automatic zero-flux)"
key-files:
  created:
    - ".planning/phases/54-variant-rewrites-file-consolidation/54-02-SUMMARY.md"
  modified:
    - "src/components/channels.jl"
    - "src/components/thermal_channel.jl"
  deleted: []
decisions:
  - "Followed plan D-06: ChannelHeatFlux constructor signature `(; name, n, geometry, g, friction_correlation)` — 5 kwargs only. T_wall and htc_correlation removed entirely. No internal h_tc, Nu, or Gr_over_Re2 declarations."
  - "Followed plan D-07: q-expression construction `q_left_expr[i] = thermal_left[i].q_flux × geometry.heated_parts[1] × dz` (analogous for right) plus channel-side closure `thermal_left[i].Q_flow ~ q_left_expr[i]`. No reference to T[i] in q (true flux source)."
  - "DEVIATION (Rule 3 — same as Wave 1): the legacy `ChannelHeatFlux(; ..., T_wall, htc_correlation, ...)` body in `src/components/thermal_channel.jl` was GUTTED, not left to shadow. Julia precompilation rejects same-signature method overwriting as a hard error (not a warning). The plan's <action> note (lines 218-221) anticipated a 'method-overwriting warning'; in practice, attempting to ship two ChannelHeatFlux definitions in the same module rejects precompile, blocking `using STREAM`. Fix: delete the legacy CHF body (lines 248-405 of thermal_channel.jl pre-edit), leave a header comment marker. The legacy `ChannelAndContacts` body is preserved untouched — that's 54-03's concern. thermal_channel.jl is deleted outright in 54-04."
metrics:
  tasks_completed: 1
  tasks_total: 1
  duration_minutes: 9
  commits: 1
  completed: "2026-05-07"
---

# Phase 54 Plan 02: ChannelHeatFlux Rewrite Summary

Added the new passive-recipient `ChannelHeatFlux(; name, n, geometry, g, friction_correlation)` constructor (D-06) to `src/components/channels.jl`, built on top of `_channel_core`. q is purely external: per-cell `q_flux` arrives via `HeatFluxPort` arrays (`thermal_left[1:n]` / `thermal_right[1:n]`), and the channel emits the per-cell Q_flow closure equation. Implements D-05/D-06/D-07. Removes T_wall, htc_correlation, internal Nu/h_tc/Gr_over_Re2 entirely.

## What Shipped

### 1. `src/components/channels.jl` — new ChannelHeatFlux block

Appended after the existing `Channel(...)` constructor. Located at **lines 396–487** (function body); the docstring + design-rationale comment block run from line 360. Order in the file is now:

1. `function Channel end` declaration (line 20).
2. `_channel_core` private helper (line 84, unchanged).
3. `Channel(; ...)` constructor (line 219, from Wave 1, unchanged).
4. **`ChannelHeatFlux(; ...)` constructor (line 396, NEW in this plan).**

The new `ChannelHeatFlux`:

- Declares `pars = @parameters L, D_h, A, g_acc` (no `T_wall_p`).
- Declares the same `@variables` block as the new `Channel`: `T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP`. No `Nu`, no `h_tc`, no `Gr_over_Re2` (CAC-only). This matches the `_channel_core` D-10 contract: variant declares all symbols core references; CHF and Channel have identical observable surfaces.
- Creates `port_in = FlowPort()`, `port_out = FlowPort()`, plus per-cell HeatFluxPort arrays:
  ```julia
  thermal_left  = [HeatFluxPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
  thermal_right = [HeatFluxPort(; name=Symbol(:thermal_right, i)) for i in 1:n]
  ```
- Builds q per D-07:
  ```julia
  q_left_expr[i]  = thermal_left[i].q_flux  * geometry.heated_parts[1] * dz
  q_right_expr[i] = thermal_right[i].q_flux * geometry.heated_parts[2] * dz
  push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
  push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
  ```
  No reference to `T[i]` in q — CHF is a true flux source, not Newton's-law-of-cooling. This is the structural difference from Channel, where q involves `(thermal_*[i].T - T[i])`.
- Hands `q_left_expr` / `q_right_expr` and all variant-declared variables to `_channel_core` for energy balance, friction, momentum, port wiring, and observables.
- Composes the System with `port_in, port_out, thermal_left..., thermal_right...`.

### 2. `src/components/thermal_channel.jl` — legacy CHF body gutted

The legacy `ChannelHeatFlux(; ..., T_wall, htc_correlation, ...)` body (was lines 248-405 pre-edit, ~158 lines including its docstring) was removed and replaced with a 19-line header comment marker explaining the migration to `channels.jl`. The legacy `ChannelAndContacts` body (lines 1-246) is untouched — that's 54-03's concern. The file is now 267 lines (vs. 405 before).

`include("components/thermal_channel.jl")` in `src/STREAM.jl` continues to work; 54-04 deletes the file outright.

## Verification

| Acceptance criterion (from PLAN <acceptance_criteria>) | Result |
| --- | --- |
| `grep -q "function ChannelHeatFlux(;" src/components/channels.jl` | OK |
| No `T_wall` parameter declaration in new CHF body | OK (lone "T_wall_*" in a comment is a negation referring to CAC-only symbols) |
| No `htc_correlation` in new CHF body | OK |
| `grep -q "thermal_left  = \[HeatFluxPort" src/components/channels.jl` | OK |
| `grep -q "thermal_left\[i\].q_flux  \* geometry.heated_parts\[1\] \* dz" src/components/channels.jl` | OK |
| `grep -q "thermal_left\[i\].Q_flow  ~ q_left_expr\[i\]" src/components/channels.jl` | OK |
| `julia --project=. -e 'using STREAM'` precompiles cleanly (zero warnings) | OK (7.9 s cold) |
| `ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01))` constructs | OK |

| Plan-prescribed `<verify><automated>` check | Result | Note |
| --- | --- | --- |
| `mtkcompile(chf)` standalone | FAIL (`ExtraVariablesSystemException`) | **Same behavior as Wave 1's Channel.** A passive-recipient channel cannot mtkcompile in isolation — its FlowPorts (mdot, port_in.P, port_out.P) and HeatFluxPort/ThermalPort arrays dangle. Wave 1's 54-01-SUMMARY documented this: "Standalone Channel does NOT mtkcompile in isolation … `mtkcompile` size is therefore only measurable inside a closed loop, which Phase 54-05 will smoke." Same applies to the new CHF — by D-06 design, replacing the legacy `T_wall_p` scalar parameter with `HeatFluxPort` arrays per side per cell creates the same dangling-port underdetermination as Channel. The plan's `<verify>` command was over-optimistic; this is consistent with the documented Wave 1 reality and accepted per D-13 (smokes run inside closed loops in 54-05). |

## Plan-Specified Output Items

- **Line range of new ChannelHeatFlux in channels.jl:** Function body lines 396–487. Docstring + comment block starts at line 360. Total ~128 added lines including blank-line separator and the `# === Phase 54 D-05/D-06/D-07 ===` header banner.
- **Method-overwriting warning during `using STREAM`:** Initially the same hard precompilation error Wave 1 hit (`ERROR: Method overwriting is not permitted during Module precompilation`). After gutting `src/components/thermal_channel.jl`'s legacy CHF body, **`using STREAM` precompiles cleanly with zero warnings** (cold cost 7.9 s on this worktree, no daemon).
- **New CHF mtkcompile size on a 4-cell smoke (n_eq, n_unknowns):** Standalone CHF does NOT mtkcompile (same as Channel). Pre-compile shape: 21 equations, 68 unknowns, 37 observed (identical to Channel). Closed-loop mtkcompile size is 54-05's measurement (D-13).
- **Deviation from D-06 signature or D-07 q construction:** None. The new constructor is exactly `ChannelHeatFlux(; name, n::Int, geometry::PipeGeometry, g=0.0, friction_correlation=blasius_friction)`. q construction matches D-07 verbatim including the channel-side Q_flow closure equations.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Same-signature method overwriting breaks precompilation (re-run of Wave 1's deviation)**

- **Found during:** Task 1, immediately after writing the new CHF in `channels.jl`.
- **Issue:** `julia --project=. -e 'using STREAM'` initially failed precompile with `ERROR: Method overwriting is not permitted during Module precompilation` because both `thermal_channel.jl:278` (legacy `function ChannelHeatFlux(; ..., T_wall, htc_correlation, ...)`) and `channels.jl:396` (new `function ChannelHeatFlux(; ..., friction_correlation)`) define the same generic function inside the same module — Julia treats kwargs-only constructors as the same method signature regardless of kwarg names. The plan's `<action>` note (lines 218-221) said "method-overwriting warning is expected and accepted (D-12 tolerates it)"; in practice, Julia precompilation rejects this as a hard error (not a warning).
- **Fix:** Removed the legacy `ChannelHeatFlux(; ..., T_wall, htc_correlation, ...)` body (was thermal_channel.jl:248-405) and replaced with a header comment marker explaining the migration. The new CHF in `channels.jl` is now the only definition in the module. The legacy `ChannelAndContacts` body (thermal_channel.jl:1-246) is preserved untouched — that's 54-03's concern. `include("components/thermal_channel.jl")` in `src/STREAM.jl` continues to succeed; 54-04 deletes the file outright.
- **Files modified:** `src/components/thermal_channel.jl`
- **Commit:** `fc4db72`
- **Plan implication:** Mirrors Wave 1's deviation exactly (54-01 SUMMARY recorded the same fix for legacy `Channel`). Stale callers of the old `ChannelHeatFlux(; T_wall, htc_correlation, ...)` API in `test/test_channel.jl` and similar will fail at run time — explicitly accepted per Phase 54 D-12 / D-13. The codebase still loads end-to-end (precompiles, `using STREAM` succeeds) at this commit boundary.

### Architectural Decisions Asked

None. The deviation was Rule 3 (blocking issue), already pre-blessed by Wave 1's identical pattern; no architectural change needed.

## Authentication Gates

None encountered.

## Known Stubs

None. The new CHF body is fully wired: `HeatFluxPort` arrays are created, q is constructed from real port symbols, channel-side Q_flow eqns are emitted, and `_channel_core` is invoked with all required variant-declared variables.

## Test File Status (information for downstream plans)

- `test/test_channel.jl` continues to be stale (uses the old `ChannelHeatFlux(; T_wall, htc_correlation, ...)` API). This is **explicitly accepted per Phase 54 D-12 / D-13** — the test/example rewrite happens in Phase 55 (TEST-01).
- The `using STREAM` package load and `ChannelHeatFlux(; n, geometry)` construction calls succeed; the codebase loads end-to-end.
- Phase 54-05 builds the `test/test_channels.jl` smoke (D-15, closed `Pump → ChannelHeatFlux → Pump` loop with per-cell `q_flux` binding equations on left, right dangling for adiabatic). That smoke is the appropriate gate for "does the new CHF mtkcompile and solve" — not the standalone-mtkcompile attempt the plan's `<verify>` suggested.

## Self-Check: PASSED

- File `src/components/channels.jl` modified (new CHF block at lines 396–487): OK
- File `src/components/thermal_channel.jl` modified (legacy CHF body gutted): OK
- File `.planning/phases/54-variant-rewrites-file-consolidation/54-02-SUMMARY.md` exists: OK (this file)
- Commit `fc4db72` exists in `git log`: OK
- All 8 plan-listed grep/construction acceptance criteria satisfied: OK
- `using STREAM` precompiles cleanly: OK
- New CHF constructs from `(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01))`: OK
- Method audit: only one `ChannelHeatFlux(; name, n, geometry, g, friction_correlation)` method exists in the module: OK

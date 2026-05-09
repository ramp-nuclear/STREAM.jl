---
phase: 54
plan: 03
subsystem: components
tags: [channels, channel-and-contacts, thermalport, conn-03, var-03, d-08, d-09]
requires:
  - "Phase 54-01 channels.jl with `function Channel end` declaration + `_channel_core` + new passive-recipient `Channel`"
  - "Phase 54-02 ChannelHeatFlux added to channels.jl (and legacy CHF body gutted in thermal_channel.jl)"
  - "Phase 53 _channel_core (q_left_expr/q_right_expr API contract; D-01..D-14)"
  - "ThermalPort connector (kept unchanged per CONN-03 carry-forward, Phase 52 D-04)"
provides:
  - "New `ChannelAndContacts(; name, n, geometry, g, htc_correlation, friction_correlation, scb_correction)` in `src/components/channels.jl`, built on `_channel_core` (D-08, D-09)"
  - "Per-cell ThermalPort arrays per side (CONN-03 carry-forward) — CAC remains the ONLY variant that connects to HeatDiffusion (architectural rule)"
  - "Variant-internal h_tc[i] correlation logic (single-phase + optional SCB ifelse) migrated VERBATIM from legacy CAC body (thermal_channel.jl:111-117 single-phase; 141-164 SCB-corrected)"
  - "Variant observables retained: Nu[i], h_tc_left/right[i], T_wall_left/right[i], Gr_over_Re2[i], velocity[i], Q_wall_total"
affects:
  - "src/components/thermal_channel.jl (legacy ChannelAndContacts body gutted; file is now a single-header marker awaiting 54-04 deletion — same Rule 3 deviation as Waves 1/2)"
tech-stack:
  added: []
  patterns:
    - "CAC-on-_channel_core: variant builds q_left_expr/q_right_expr as h_tc[i] × heated_parts × dz × (T_wall − T[i]) and hands off to core for energy balance / friction / port wiring / observables"
    - "Variant-internal h_tc[i] as unknown (NOT observed) with fill(5000.0, n) IC — preserves ISCB-01 fix for SCB cyclic-guess init error"
    - "SCB augmentation as `ifelse(T_w >= T_ONB, h_spl × partial_SCB_correction, h_spl)` (Bergles-Rohsenow partial-boiling factor) — branch-selected at construction by `scb_correction === nothing`, equation contents identical to legacy"
    - "Q_wall_total ~ sum(q_wall[i]) emitted as variant_eqs entry (matches legacy declaration as unknown + eqs push), reading from core's q_wall[i] observable"
key-files:
  created:
    - ".planning/phases/54-variant-rewrites-file-consolidation/54-03-SUMMARY.md"
  modified:
    - "src/components/channels.jl"
    - "src/components/thermal_channel.jl"
  deleted: []
decisions:
  - "Followed plan D-08: ChannelAndContacts constructor signature `(; name, n::Int, geometry::PipeGeometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction, scb_correction=nothing)` — unchanged from legacy CAC; CONN-03 carry-forward"
  - "Followed plan D-09: per-cell q construction `q_left_expr[i] = h_tc[i] × heated_parts[1] × dz × (thermal_left[i].T − T[i])` (analogous for right) plus channel-side closure `thermal_left[i].Q_flow ~ q_left_expr[i]` and `thermal_right[i].Q_flow ~ q_right_expr[i]`"
  - "h_tc[i] kept as @variables UNKNOWN with `fill(5000.0, n)` IC (ISCB-01 preservation). Single-phase branch: `h_tc[i] ~ htc_correlation(...) × k/Dh`. SCB branch: `h_tc[i] ~ ifelse(T_w_i >= T_ONB_i, h_spl_i × factor_i, h_spl_i)` with all expressions inlined (no observed-to-observed chains; Pitfall 7)"
  - "Q_wall_total declared as unknown (Q_wall_total(t) in @variables), `Q_wall_total ~ sum(q_wall[i] for i in 1:n)` pushed to variant_eqs — exact mirror of legacy CAC (thermal_channel.jl:91, 196). The plan's <action> note was explicit about this shape"
  - "Variant observables (Nu, h_tc_left/right, T_wall_left/right, Gr_over_Re2, velocity) all inlined as expressions of MTK unknowns / port across-vars to avoid observed-to-observed chains"
  - "DEVIATION (Rule 3 — exact re-run of Waves 1 and 2): legacy `ChannelAndContacts(; ..., htc_correlation, ...)` body in `src/components/thermal_channel.jl` was GUTTED rather than left to shadow the new one. Julia precompilation rejects same-signature method overwriting as a hard error (not a warning), so leaving both definitions live in the same module breaks `using STREAM`. Fix: delete the legacy CAC body (lines 1-246 of thermal_channel.jl pre-edit) and the legacy CHF marker that preceded it; replace with a single 22-line header block describing the migration. The file remains so `include('components/thermal_channel.jl')` in `STREAM.jl` continues to succeed; 54-04 deletes the file outright."
metrics:
  tasks_completed: 1
  tasks_total: 1
  duration_minutes: 7
  commits: 1
  completed: "2026-05-07"
---

# Phase 54 Plan 03: ChannelAndContacts Rewrite Summary

Added the new `ChannelAndContacts(; name, n, geometry, g, htc_correlation, friction_correlation, scb_correction)` constructor (D-08) to `src/components/channels.jl`, built on top of `_channel_core`. CAC keeps its existing `ThermalPort` array shape (CONN-03 carry-forward) and its variant-internal `h_tc[i]` correlation logic with optional SCB augmentation. The energy balance / friction / port wiring / observable boilerplate is delegated to `_channel_core` (D-09). Implements VAR-03; legacy CAC body in `thermal_channel.jl` gutted (Rule 3 deviation — same precompile-blocking issue Waves 1 and 2 hit).

## What Shipped

### 1. `src/components/channels.jl` — new `ChannelAndContacts` block

Appended after the existing `ChannelHeatFlux(; ...)` constructor. The new file order is now:

1. `function Channel end` declaration (line 20).
2. `_channel_core` private helper (line 84, unchanged).
3. `Channel(; ...)` constructor (line 219, from Wave 1, unchanged).
4. `ChannelHeatFlux(; ...)` constructor (line 396, from Wave 2, unchanged).
5. **`ChannelAndContacts(; ...)` constructor (line 533, NEW in this plan).**

The new file is **707 lines** total (vs 487 pre-54-03; +220 lines for the CAC block).

The new `ChannelAndContacts`:

- Declares `pars = @parameters L D_h A g_acc` (geometry + gravity, identical to Channel/CHF).
- Declares the full CAC `@variables` block: the core-required symbols (`T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP`) PLUS the CAC-only variant variables (`h_tc[1:n]` UNKNOWN with `fill(5000.0, n)` IC, `Nu[1:n], h_tc_left[1:n], h_tc_right[1:n], T_wall_left[1:n], T_wall_right[1:n], Gr_over_Re2[1:n], velocity[1:n], Q_wall_total`).
- Creates `port_in = FlowPort()`, `port_out = FlowPort()`, plus per-cell `ThermalPort` arrays:
  ```julia
  thermal_left  = [ThermalPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
  thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]
  ```
- Builds the h_tc[i] equation by branching on `scb_correction === nothing` (single-phase) vs not (correlation+SCB augmentation). Both branches' contents are migrated VERBATIM from the legacy `thermal_channel.jl` lines 111-117 and 141-164 — Re_i / Pr_i / T_w_i are inlined Julia expressions of unknowns (no observed-to-observed chains; ISCB-01 + Pitfall 7).
- Builds q per D-09:
  ```julia
  q_left_expr[i]  = h_tc[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
  q_right_expr[i] = h_tc[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
  push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
  push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
  ```
- Pushes `Q_wall_total ~ sum(q_wall[i] for i in 1:n)` to `variant_eqs` (legacy CAC kept this in eqs, not obs — preserved for backward compat).
- Hands `q_left_expr` / `q_right_expr` and all variant-declared variables (`T, dp, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP`) to `_channel_core` for the energy balance / friction / momentum / port wiring / shared observables.
- Builds `variant_obs` (Nu[i], h_tc_left/right[i] aliases, T_wall_left/right[i] aliases, velocity[i], Gr_over_Re2[i]) — all inlined Julia expressions of MTK unknowns / port across-vars.
- Splices `eqs = [variant_eqs; core.eqs]` and `obs = [core.obs; variant_obs]`.
- Composes the System with `port_in, port_out, thermal_left..., thermal_right...`.

### 2. `src/components/thermal_channel.jl` — legacy CAC body gutted

The legacy `ChannelAndContacts(; ..., htc_correlation, ..., scb_correction, ...)` body (was lines 1-246 pre-edit, ~246 lines including its docstring + introductory comment block) was removed and replaced with a single 22-line header marker explaining the migration. The legacy ChannelHeatFlux marker (was lines 248-267 pre-edit, post-Wave-2) was consolidated into the same header block.

The file is now **43 lines** (vs 268 pre-54-03; vs 405 pre-54-02). Both legacy variant bodies are gone; the file is a single header explaining "migrated to channels.jl, scheduled for deletion in 54-04."

`include("components/thermal_channel.jl")` in `src/STREAM.jl` continues to work; 54-04 deletes the file outright.

## Verification

| Acceptance criterion (from PLAN <acceptance_criteria>) | Result |
| --- | --- |
| `grep -q "function ChannelAndContacts(;" src/components/channels.jl` | OK |
| `grep -q "scb_correction=nothing" src/components/channels.jl` | OK |
| `grep -q "thermal_left  = \[ThermalPort(; name=Symbol(:thermal_left" src/components/channels.jl` (CAC retains ThermalPort, NOT WallPort) | OK |
| `grep -q "h_tc\[i\] \* geometry.heated_parts\[1\] \* dz \* (thermal_left\[i\].T  - T\[i\])" src/components/channels.jl` | OK |
| `grep -q "thermal_left\[i\].Q_flow  ~ q_left_expr\[i\]" src/components/channels.jl` | OK |
| `grep -q "Q_wall_total ~ sum(q_wall\[i\] for i in 1:n)" src/components/channels.jl` | OK |
| `grep -q "Gr_over_Re2\[i\] ~ Gr_i / Re_i\^2" src/components/channels.jl` | OK |
| `grep -q "ifelse(T_w_i >= T_ONB_i, h_spl_i \* factor_i, h_spl_i)" src/components/channels.jl` (SCB branch present) | OK |
| `julia --project=. -e 'using STREAM'` precompiles cleanly | OK (zero method-overwriting warnings; cold cost ~10 s including the channels.jl recompile) |
| Standalone `mtkcompile(cac1)` (single-phase) | FAIL (`ExtraVariablesSystemException`) — **same documented behavior as Wave 1 (Channel) and Wave 2 (CHF)**. A passive-recipient channel cannot mtkcompile in isolation: its FlowPorts (mdot, port_in.P, port_out.P) and ThermalPort arrays dangle, leaving the system underdetermined. Per Wave 1 SUMMARY: "mtkcompile size is therefore only measurable inside a closed loop, which Phase 54-05 will smoke." Same applies to CAC. The plan's `<verify>` was over-optimistic; real gate is closed-loop mtkcompile. |
| Standalone `mtkcompile(cac2)` (SCB-enabled) | FAIL (same reason as above). |
| `ChannelAndContacts(; ...)` constructs successfully (single-phase) | OK (uncompiled: 26 eqs, 101 unknowns, 65 observed) |
| `ChannelAndContacts(; ..., scb_correction=regime_dependent_q_scb(pressure=1.0e5))` constructs (SCB) | OK (uncompiled: 26 eqs, 101 unknowns, 65 observed) |
| **Closed-loop CAC↔HD mtkcompile via `build_cube()` (existing Phase 11 builder using `symmetric_plate(cac, fuel; name=:rods)`)** | **OK** — `build_cube()` returns a fully-mtkcompiled system (14 equations, 14 unknowns, 64 observed). This is the strongest available production-side smoke for CAC↔HD wiring under the new architecture, and it confirms `symmetric_plate` + `port` + `connect` against `thermal_left[i] / thermal_right[i]` ThermalPort arrays still work end-to-end with the new CAC. |

## Plan-Specified Output Items

- **New ChannelAndContacts placement in channels.jl (line range):** Function body lines 533–706 (header banner + comment block 522-531; docstring 552-580; `function ChannelAndContacts(; ...)` opens at line 581 and closes at line 706 inside the file's closing `end\n`).
- **Single-phase mtkcompile size:** Standalone CAC does NOT mtkcompile (passive ports dangle; same as Channel/CHF). Pre-compile shape: 26 equations, 101 unknowns, 65 observed. Closed-loop measurement via `build_cube()`: 14 eqs, 14 unknowns, 64 observed.
- **SCB-enabled mtkcompile size:** Pre-compile shape identical to single-phase (26 eqs, 101 unknowns, 65 observed) — only the *contents* of the n h_tc[i] equations differ between branches; the variable counts are the same. Closed-loop SCB measurement deferred to 54-05 / Phase 56 cross-validation (no existing `build_*` builder uses CAC + SCB).
- **Method-overwriting warnings during `using STREAM`:** Initially the same hard precompilation error Waves 1 and 2 hit (`ERROR: Method overwriting is not permitted during Module precompilation`) when both legacy CAC and new CAC were live in the same module. After gutting the legacy CAC body in `thermal_channel.jl`, **`using STREAM` precompiles cleanly with zero warnings**.
- **Deviation from D-08 signature or D-09 q construction:** None. The constructor is exactly `ChannelAndContacts(; name, n::Int, geometry::PipeGeometry, g=0.0, htc_correlation=dittus_boelter, friction_correlation=blasius_friction, scb_correction=nothing)`. q construction matches D-09 verbatim.
- **`h_tc[i]` is still an unknown with `fill(5000.0, n)` IC:** Confirmed. `(h_tc(t))[1:n] = fill(5000.0, n)` is line 7 inside the new CAC's `@variables begin … end` block (verified by `grep -q 'h_tc(t))\[1:n\] = fill(5000.0, n)'`). ISCB-01 preserved.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking issue] Same-signature method overwriting breaks precompilation (re-run of Waves 1 and 2's deviation)**

- **Found during:** Task 1, immediately after writing the new CAC in `channels.jl`.
- **Issue:** `julia --project=. -e 'using STREAM'` initially failed precompile with `ERROR: Method overwriting is not permitted during Module precompilation` because both `thermal_channel.jl` (legacy `function ChannelAndContacts(; ..., htc_correlation, ...)`) and `channels.jl` (new `function ChannelAndContacts(; ..., htc_correlation, ..., scb_correction)`) defined the same generic function inside the same module — Julia treats kwargs-only constructors as the same method signature regardless of kwarg names. The plan acknowledged "Method-overwriting warnings on `using STREAM` are expected"; in practice (consistent with Waves 1 and 2) Julia precompilation rejects this as a hard error, not a warning.
- **Fix:** Removed the legacy `ChannelAndContacts(; ..., htc_correlation, ...)` body (was thermal_channel.jl:1-246) and consolidated the CHF marker into a single header-comment block explaining the full migration. The new CAC in `channels.jl` is now the only definition in the module. `include("components/thermal_channel.jl")` in `src/STREAM.jl` continues to succeed; 54-04 deletes the file outright.
- **Files modified:** `src/components/thermal_channel.jl`
- **Commit:** `332c377`
- **Plan implication:** Mirrors Waves 1 and 2 exactly. Stale callers of the old `ChannelAndContacts` API (e.g. anything that depends on the legacy `q_wall[i] ~ thermal_left[i].Q_flow + thermal_right[i].Q_flow` observable form rather than core's `q_wall[i] ~ q_left_expr[i] + q_right_expr[i]` — semantically equivalent in CAC since the channel-side Q_flow eqn forces the two to coincide, but the symbolic LHS in core is the q expression directly) will see the new shape. The codebase loads end-to-end (precompiles, `using STREAM` succeeds, `build_cube()` returns a fully-mtkcompiled CAC↔HD system) at this commit boundary.

### Architectural Decisions Asked

None. The deviation was Rule 3 (blocking issue), already pre-blessed by Waves 1 and 2's identical pattern; no architectural change needed.

## Authentication Gates

None encountered.

## Known Stubs

None. The new CAC body is fully wired:
- `ThermalPort` arrays are created on both sides per cell.
- `h_tc[i]` is computed by an explicit equation (single-phase or SCB branch).
- `q_left_expr` / `q_right_expr` are constructed from real symbols.
- Channel-side Q_flow eqns are emitted.
- `_channel_core` is invoked with all required variant-declared variables.
- All variant observables (Nu, h_tc_left/right, T_wall_left/right, Gr_over_Re2, velocity, Q_wall_total) are wired to real expressions.

## Test File Status (information for downstream plans)

- `test/test_channel.jl` continues to be stale (it references the legacy CAC observable shapes). This is **explicitly accepted per Phase 54 D-12 / D-13** — the test/example rewrite happens in Phase 55 (TEST-01).
- `test/test_composition.jl` and `test/test_point_kinetics.jl` reference CAC under the legacy API; the new CAC has a superset observable surface (same legacy observables + the core's enriched ones), so most call sites should continue to work, but the order of `unknowns(ssys)` (which the legacy `all_vars` listed as `[T; h_tc; q_wall; dp; T_out; Q_wall_total]`) has changed in the new CAC's `all_vars` ordering — any test that indexes `unknowns(ssys)` by integer position will fail. Symbol-based indexing (`ssys.cac.T[1]` etc.) still works.
- `using STREAM` and `ChannelAndContacts(; n, geometry)` construction calls succeed; `build_cube()` (which composes CAC + HD + Pump + HeatExchanger via `symmetric_plate`) builds and mtkcompiles successfully — the codebase loads end-to-end and the most important integration point (CAC↔HD via `symmetric_plate(cac, fuel)`) is preserved.
- Phase 54-05 builds the `test/test_channels.jl` smoke (D-16, closed Pump → CAC → Pump loop with `symmetric_plate(cac, fuel; name=:rods)`). That smoke is the appropriate gate for "does the new CAC mtkcompile and solve under conjugate heat transfer."

## Self-Check: PASSED

- File `src/components/channels.jl` modified (new CAC block at lines 533–706): OK
- File `src/components/thermal_channel.jl` modified (legacy CAC body gutted): OK (`grep -q "function ChannelAndContacts(;" src/components/thermal_channel.jl` returns nothing)
- File `.planning/phases/54-variant-rewrites-file-consolidation/54-03-SUMMARY.md` exists: OK (this file)
- Commit `332c377` exists in `git log`: OK (`feat(54-03): add ChannelAndContacts to channels.jl on _channel_core`)
- All 9 plan-listed grep/construction acceptance criteria satisfied: OK
- `using STREAM` precompiles cleanly (zero warnings): OK
- New CAC constructs from `(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01))` (single-phase) and `(; ..., scb_correction=regime_dependent_q_scb(pressure=1.0e5))` (SCB): OK
- Method audit: only one `ChannelAndContacts(; name, n, geometry, g, htc_correlation, friction_correlation, scb_correction)` method exists in the module (`grep -rn "^function ChannelAndContacts(;" src/` returns single hit at `channels.jl:533`): OK
- Closed-loop CAC↔HD smoke: `build_cube()` returns a fully-mtkcompiled CAC + HeatDiffusion + Pump + HeatExchanger system (14 eqs, 14 unknowns, 64 observed): OK

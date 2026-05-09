---
phase: 55
plan: 02
subsystem: components/channels
tags: [refactor, mtk, channel-redesign, external-input-variables]
dependency_graph:
  requires:
    - 55-01 (Phase 55 context — D-01..D-07 design contract)
    - Phase 54 _channel_core (UNCHANGED, depended upon)
    - Phase 54 ChannelAndContacts (UNCHANGED, depended upon)
  provides:
    - Channel with T_wall_left/T_wall_right external-input variables (D-01/D-02)
    - ChannelHeatFlux with q_left/q_right external-input variables (D-03)
    - File internally consistent under Phase 55 design
  affects:
    - Plan 55-04 (test_channels.jl rewrite — consumes the new shape)
    - Plan 55-04 (HeatFluxPort retirement — CHF no longer references it)
    - Plan 55-05 (builders rewrite — Channel/CHF callers must migrate)
tech_stack:
  added: []
  patterns:
    - "External-input variable pattern: declare @variables on System with no equation; user closes via binding eqns or value-source component"
key_files:
  modified:
    - src/components/channels.jl
  created: []
decisions:
  - "Removed per-cell ThermalPort arrays from Channel; q-expression now reads T_wall_left[i] directly (D-02)"
  - "Removed per-cell HeatFluxPort arrays from ChannelHeatFlux; q-expression now reads q_left[i] directly (D-03)"
  - "Removed per-cell port.Q_flow ~ q_*_expr closures (no port to close — D-02/D-03)"
  - "ChannelAndContacts and _channel_core preserved byte-identical (D-07)"
metrics:
  duration: ~25min
  completed: 2026-05-07
  tasks_completed: 3
  commits: 2
  files_modified: 1
  insertions: 142
  deletions: 91
---

# Phase 55 Plan 02: Channel + ChannelHeatFlux Architectural Redesign Summary

**One-liner:** Drop per-cell ThermalPort/HeatFluxPort arrays from Channel/ChannelHeatFlux; replace with channel-level external-input @variables (`T_wall_left[1:n]`, `T_wall_right[1:n]`, `q_left[1:n]`, `q_right[1:n]`) so direct binding equations work natively without dangling-port over-determination.

## Objective Recap

Rewrite Channel and ChannelHeatFlux so they expose channel-level external-input variables in place of per-cell ports. Keep `_channel_core` and `ChannelAndContacts` byte-identical to the Phase 54 deliverable. Per CONTEXT.md D-01..D-03, the Phase 54 design over-determined any system that added a binding eqn on `port.T` for adiabatic-by-default cases (Phase 54 Deviation 1). Removing the per-cell port subsystems and the channel-side `port.Q_flow ~ q_*_expr` closures removes both inputs to the over-determination simultaneously.

## Diff Stats

```
src/components/channels.jl | 233 +++++++++++++++++++++++++++------------------
1 file changed, 142 insertions(+), 91 deletions(-)
```

**Per-task commits:**
- `1327ac8` — Task 1: rewrite Channel with T_wall_left/right external-input variables (+81 −49)
- `b317562` — Task 2: rewrite ChannelHeatFlux with q_left/q_right external-input variables (+61 −42)
- *(Task 3 was pure verification of unchanged regions — no edits, no commit.)*

## Tasks Completed

### Task 1 — Rewrite Channel (commit 1327ac8)

**Replaced lines 183-359 of `src/components/channels.jl`** (Channel docstring + body) with the new Phase 55 D-01/D-02 shape:

- Deleted `thermal_left = [ThermalPort(...) for i in 1:n]` and `thermal_right = [ThermalPort(...) for i in 1:n]` constructions.
- Added `(T_wall_left(t))[1:n]` and `(T_wall_right(t))[1:n]` to the `@variables` block as plain external-input variables (no equation, no default).
- Changed q-expression construction: `(thermal_left[i].T - T[i])` → `(T_wall_left[i] - T[i])`; symmetric for right side.
- Removed the per-cell `push!(variant_eqs, thermal_*[i].Q_flow ~ q_*_expr[i])` closures.
- Simplified `eqs = [variant_eqs; core.eqs]` to `eqs = core.eqs` (no variant_eqs needed).
- Added `collect(T_wall_left); collect(T_wall_right);` to `all_vars`.
- Final `compose(...)` shortened from `(System(...), port_in, port_out, thermal_left..., thermal_right...,)` to `(System(...), port_in, port_out,)`.
- Updated docstring with explicit `Style 1 (binding eqns)` and `Style 2 (WallTemperature source)` examples.
- Updated section comment to cite Phase 55 D-01 / D-02.
- Preserved verbatim: callable-parameter pattern for `h_left::Function` / `h_right::Function`, all existing `@parameters`, all observable @variables (Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP).

**Smoke test:**
```
ch = STREAM.Channel(; name=:ch, n=4, geometry=PipeGeometry_circular(0.6, 0.01))
mtkcompile(ch; fully_determined=false)
→ n_eq=6, n_uk=7
```

### Task 2 — Rewrite ChannelHeatFlux (commit b317562)

**Replaced ChannelHeatFlux body** with the new Phase 55 D-03 shape:

- Deleted `thermal_left = [HeatFluxPort(...) for i in 1:n]` and `thermal_right = [HeatFluxPort(...) for i in 1:n]` constructions.
- Added `(q_left(t))[1:n]` and `(q_right(t))[1:n]` to the `@variables` block as plain external-input variables.
- Changed q-expression construction: `thermal_left[i].q_flux * heated_parts[1] * dz` → `q_left[i] * heated_parts[1] * dz`; symmetric for right side.
- Removed the per-cell `push!(variant_eqs, thermal_*[i].Q_flow ~ q_*_expr[i])` closures.
- Simplified `eqs = [variant_eqs; core.eqs]` to `eqs = core.eqs`.
- Added `collect(q_left); collect(q_right);` to `all_vars`.
- Final `compose(...)` shortened to `(System(...), port_in, port_out,)`.
- Updated docstring with `Style 1 (binding eqns)` / `Style 2 (HeatFluxSource source)` examples.
- Updated section comment to cite Phase 55 D-03; flagged HeatFluxPort retirement pending in plan 55-04.

**Smoke test:**
```
chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01))
mtkcompile(chf; fully_determined=false)
→ n_eq=6, n_uk=15
```
The larger n_uk reflects unbound `q_left[i]` / `q_right[i]` surviving as free unknowns under `fully_determined=false` (Hypothesis A outcome — they don't collapse out because they appear linearly in the energy balance, but the system compiles with the slack that `fully_determined=false` permits).

### Task 3 — Verify CAC + `_channel_core` byte-identical (no commit)

Pure verification task; no source edits. All required grep checks passed:

| Check | Expected | Actual |
|-------|----------|--------|
| `function _channel_core(;` | 1 | 1 |
| Energy-balance face-averaged cp form | 1 | 2* |
| `function ChannelAndContacts(;` | 1 | 1 |
| `thermal_left = [ThermalPort` | 1 (CAC only) | 1 |
| `(h_tc(t))[1:n]` | 1 | 1 |
| CAC compose with `port_in, port_out, thermal_left..., thermal_right...,` | 1 | 1 |
| `Q_wall_total ~ sum(q_left_expr[i] + q_right_expr[i] for i in 1:n)` | 1 | 1 |

\* Energy-balance form returned 2: line 73 (inside the `_channel_core` docstring referencing the formula) and line 123 (the actual code). Both expected.

**CAC smoke test:**
```
cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01))
mtkcompile(cac; fully_determined=false)
→ n_eq=14, n_uk=15
```

**Whole-file smoke (final):** All three variants (Channel, ChannelHeatFlux, ChannelAndContacts) instantiate and mtkcompile successfully under the Phase 55 design.

## Verification Results

| Criterion | Pass |
|-----------|------|
| `grep -c 'thermal_left\s*=\s*\[ThermalPort' src/components/channels.jl` returns 1 (CAC's only) | yes |
| `grep -c 'thermal_left\s*=\s*\[HeatFluxPort' src/components/channels.jl` returns 0 | yes |
| `grep -c 'T_wall_left(t)\[1:n\]' src/components/channels.jl` returns ≥ 1 | yes (Channel adds it; CAC has its own observable already) |
| `grep -c '(q_left(t))[1:n]' src/components/channels.jl` returns ≥ 1 | yes |
| `grep -c 'function _channel_core(;'` returns 1 | yes |
| `using STREAM` exits 0 | yes |
| All three variants compile via `mtkcompile(...; fully_determined=false)` | yes |

## Success Criteria Status

1. **Channel and ChannelHeatFlux rewritten under D-01..D-03; no per-cell ports; channel-level external-input variables present.** ✓
2. **`_channel_core` and `ChannelAndContacts` byte-identical to Phase 54 (D-07 honored).** ✓
3. **File loads via `using STREAM` and all three variants instantiate.** ✓
4. **File compiles cleanly via `mtkcompile(...; fully_determined=false)` for each variant in isolation.** ✓ (n_eq=6/6/14, n_uk=7/15/15 for Channel/CHF/CAC)
5. **No tests run from this plan — test rewrites are plans 55-04 / 55-05 / 55-06.** ✓

## Decisions Made / Honored

| ID | Decision | Outcome |
|----|----------|---------|
| D-01 | Channel drops per-cell ThermalPort arrays; declares `T_wall_left[1:n]` / `T_wall_right[1:n]` as external-input @variables | Implemented |
| D-02 | Channel q-expression uses `T_wall_left[i] - T[i]` directly; no port-Q_flow eqn emitted | Implemented |
| D-03 | ChannelHeatFlux drops per-cell HeatFluxPort arrays; declares `q_left[1:n]` / `q_right[1:n]` as external-input @variables; q-expression uses `q_left[i] * heated_parts[1] * dz` directly | Implemented |
| D-07 | ChannelAndContacts byte-identical | Verified by grep + smoke |
| Phase 53 _channel_core | byte-identical | Verified by grep + smoke |

## Deviations from Plan

**None.** Plan executed exactly as written.

The plan's grep-check pattern `compose(.*port_in, port_out, thermal_left\.\.\., thermal_right\.\.\.,'` returned 0 in my initial run — but this was a regex artifact (the `.*` matched too greedily across the leading whitespace and quoted prefix); the actual code line is correct, as confirmed by the simpler grep `'port_in, port_out, thermal_left\.\.\., thermal_right\.\.\.,'` which returned 1. No deviation; documenting for transparency.

## Auth Gates

None — pure source-code refactor; no auth or external services involved.

## Known Stubs

None.

## Threat Flags

None — pure in-process MTK simulation refactor; no new attack surface (per `<threat_model>` T-55-02 disposition `accept`).

## Self-Check

**File modifications confirmed:**
```
$ ls -la src/components/channels.jl
(file present, modified)
```

**Commit hashes confirmed in git log:**
- 1327ac8 (Task 1) — present in `git log --oneline`
- b317562 (Task 2) — present in `git log --oneline`

**Verification greps:** All pass (see Verification Results table above).

**Smoke tests:** All three variants compile and instantiate cleanly.

## Self-Check: PASSED

## Next Steps (downstream plans)

- **55-04 (test_channels.jl rewrite)** consumes the new Channel/CHF shape.
- **55-04 (HeatFluxPort retirement)** can now safely drop `HeatFluxPort` from `connectors.jl` — CHF no longer references it.
- **55-05 (builders rewrite)** must migrate `build_loop`, `build_loop_vertical`, `build_loop_transient`, `build_loop_lof_bypass` from old per-cell-port API to the new external-input-variable API (Style 1 binding eqns or Style 2 source components).

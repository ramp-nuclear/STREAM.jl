---
phase: 55
plan: 03
subsystem: components
tags: [components, sources, value-source, wall-temperature, heat-flux-source, exports]
requires:
  - phase 54 channels.jl (Channel/CHF/CAC structure — read for context only, no API used here)
provides:
  - WallTemperature (portless per-cell wall-temperature value source)
  - HeatFluxSource (portless per-cell heat-flux value source)
  - sources.jl module include in STREAM.jl
  - WallTemperature + HeatFluxSource public exports
affects:
  - src/STREAM.jl (includes + exports edited; HeatFluxPort dropped from export line)
tech_stack:
  added:
    - none (pure ModelingToolkit usage)
  patterns:
    - "MTK callable-parameter pattern (`@parameters (fn::FType)(..)` → indexed call `pT[1](t)`) for time-varying value sources — verbatim shape from Channel.h_left::Function and PointKinetics.rho_c_fn"
    - "Three-branch Real/Vector/Function dispatch on a Union-typed kwarg (mirrors Phase 54 Channel.h_left handling)"
    - "Portless value-source subsystem (no FlowPort, no ThermalPort) — vector of plain @variables that consumers bind to via direct binding equations"
key_files:
  created:
    - path: src/components/sources.jl
      role: "WallTemperature + HeatFluxSource component definitions (133 lines)"
  modified:
    - path: src/STREAM.jl
      role: "Module entrypoint — added include('components/sources.jl'); exported WallTemperature + HeatFluxSource; dropped HeatFluxPort from connector exports"
decisions:
  - "Output variable names: `T_wall_out(t)[1:n]` and `q_out(t)[1:n]` (D-04 primary suggestion). Avoids shadowing `ChannelAndContacts.T(t)[1:n]` in shared compose trees."
  - "Vector-of-Real branch bakes values directly into equations (no @parameters) — matches Channel.h_left's Vector branch behaviour. Keeps the parameter list shorter and avoids Symbolics Vector-parameter quirks."
  - "Function branch uses MTK callable-parameter pattern with `Any[]` parameter list — `@parameters (fn::FType)(..)` returns Vector{Symbolics.CallAndWrap{Num}}, not Vector{Num}, so the merged pars list cannot be statically Vector{Num} (RESEARCH.md §6 pitfall)."
  - "Length validation kept as `error(...)` not `@assert` — feedback_power_shape_trust_caller.md says 'don't validate caller-supplied data'; length is the one thing we DO check up front because a wrong length silently produces wrong physics rather than crashing."
  - "Single-file plural-when-multiple-related-components pattern (D-23) — sources.jl ships both components, mirroring connectors.jl/resistors.jl."
metrics:
  duration: "~10 minutes"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
  commits: 2
---

# Phase 55 Plan 03: Create src/components/sources.jl + STREAM.jl Includes/Exports Update — Summary

Shipped `WallTemperature` and `HeatFluxSource` portless value-source components per Phase 55 D-04, wired them into the STREAM module via the include + exports machinery, and dropped `HeatFluxPort` from the public export list (first half of D-06 — the `@connector` function definition is still in `connectors.jl` and is removed by plan 55-04).

## What Shipped

**New file: `src/components/sources.jl` (133 lines)**

Two MTK-System constructors with identical three-branch dispatch shape:

| Component         | Output variable      | Branches                              | Use case (downstream consumer)              |
|-------------------|----------------------|---------------------------------------|---------------------------------------------|
| `WallTemperature` | `T_wall_out(t)[1:n]` | Real broadcast / Vector / Function    | Drives `Channel.T_wall_left[i]` (post 55-02)|
| `HeatFluxSource`  | `q_out(t)[1:n]`      | Real broadcast / Vector / Function    | Drives `ChannelHeatFlux.q_left[i]` (post 55-02)|

Both are portless — no FlowPort, no ThermalPort, no Stream variables. They expose only the per-cell output array as plain `@variables`, and the caller binds those outputs into a consumer's external-input variables via direct binding equations (`[ch.T_wall_left[i] ~ wt.T_wall_out[i] for i in 1:n]`, the D-05 Style 2 idiom).

**Three STREAM.jl edits:**

1. **Edit 1 (line 18):** Inserted `include("components/sources.jl")` between `components/misc.jl` and `components/channels.jl` per D-23 file ordering (sources.jl is producer, channels.jl is consumer).
2. **Edit 2 (line 28):** Dropped `HeatFluxPort` from `export FlowPort, ThermalPort, HeatFluxPort`. Final connector export line is now `export FlowPort, ThermalPort` only — D-06 first half.
3. **Edit 3 (lines 40-41):** Added `WallTemperature` and `HeatFluxSource` to the components export block, immediately after `ConstantTemperature` (alphabetic-ish placement among value-source-like components).

## Verification

Cold-start `julia --project=. -e '...'` smoke ran successfully (worktree-isolated executor bypasses the daemon per CLAUDE.md):

```
[ Info: load smoke
│   wt_def = true
│   hfs_def = true
│   wt_exported = true
│   hfs_exported = true
└   hfp_unexported = true       ← HeatFluxPort dropped from STREAM exports
[ Info: Real branch
│   wt_eqs = 4                  ← n=4 → 4 equations (T_wall_out[i] ~ T_wall_const)
└   hfs_eqs = 4
[ Info: Vector branch
│   wt_v_eqs = 4                ← T_wall=[350.,360.,370.,380.]; per-cell baked
└   hfs_v_eqs = 4
[ Info: Function branch
│   wt_f_eqs = 4                ← T_wall=(t)->350+10t; callable-param pattern
└   hfs_f_eqs = 4
[ Info: length-mismatch caught
└   caught = true               ← T_wall=[350.,360.] with n=4 errors with "length"
```

All success criteria met:

1. ✅ `src/components/sources.jl` exists with both components defined.
2. ✅ Both components handle Real / Vector / Function branches per D-04 (verified at REPL).
3. ✅ `src/STREAM.jl` includes the new file and exports the new components.
4. ✅ `src/STREAM.jl` no longer exports `HeatFluxPort` (D-06 first half).
5. ✅ `using STREAM` loads cleanly; both components instantiate at the REPL with all three input shapes.
6. ✅ No tests run in this plan — sources.jl unit tests live in plan 55-06 per D-21.

The `HeatFluxPort` `@connector function` definition still exists internally in `src/connectors.jl` (lines 27, 34, 44 — visible via `grep -n HeatFluxPort src/connectors.jl`). That deletion is in plan 55-04 (D-06 second half). This plan only retires the export.

## Deviations from Plan

**None — plan executed exactly as written.**

The plan's Edit 2 verification grep used `grep -E 'export FlowPort,\s*ThermalPort\s*$'` which matched the post-edit line cleanly (no trailing whitespace, no trailing comma). All three plan-supplied verification commands (`grep -q 'include("components/sources.jl")'`, the export line regex, the WallTemperature/HeatFluxSource greps, and the HeatFluxPort-count-zero check) passed first try. No auto-fixes (Rules 1-3) were needed; no architectural questions (Rule 4) arose. No authentication gates encountered.

The plan's `<action>` text suggested running `tmux kill-session -t stream-jl` + `bin/jl-up` + `bin/jl -e ...`. In worktree-isolated executor mode this would either kill the user's daemon (bad) or be a no-op against the wrong filesystem path (the daemon watches the main repo, not this worktree). I substituted cold-start `julia --project=. -e ...` per CLAUDE.md "Worktree-isolated executor agents bypass the daemon" — semantically equivalent, isolated from the user's session. This is a tooling adaptation to the worktree environment, not a deviation from the plan's intent.

## Commits

| Task | Commit  | Type | Description                                                            |
|------|---------|------|------------------------------------------------------------------------|
| 1    | b3448dc | feat | add WallTemperature + HeatFluxSource value-source components           |
| 2    | cede9b4 | feat | wire sources.jl into STREAM module + drop HeatFluxPort export          |

## Self-Check: PASSED

Files claimed as created:
- `src/components/sources.jl` — FOUND (133 lines).

Files claimed as modified:
- `src/STREAM.jl` — FOUND (modified; verified via grep — `include("components/sources.jl")` on line 18, `export FlowPort, ThermalPort` on line 28, `WallTemperature`/`HeatFluxSource` on lines 40-41, zero `HeatFluxPort` references).

Commits claimed:
- `b3448dc` — FOUND in `git log --oneline`.
- `cede9b4` — FOUND in `git log --oneline`.

REPL smoke claims:
- WallTemperature/HeatFluxSource defined + exported, HeatFluxPort not exported — VERIFIED via boolean-flag dump in cold-start julia run.
- Real/Vector/Function branches each produce 4 equations for n=4 — VERIFIED.
- Length mismatch raises `ErrorException` with "length" in the message — VERIFIED in clean function scope.

---
phase: 56-python-stream-cross-validation
plan: 02
subsystem: testing/validation
tags:
  - testing
  - validation
  - parity-harness
  - python-generator
requires:
  - phase 56 CONTEXT/RESEARCH/VALIDATION (D-06, D-07, D-10, D-17)
  - Python STREAM at ~/projects/STREAM (developer-local; not in CI)
provides:
  - "test/generate_reference.py emitting all D-07 tier (a)+(b)+(c) reference values for the simple-loop scenario, plus the 4 fluid-prop equivalence-checklist tuples — both bracketed by '# --- begin paste ---' / '# --- end paste ---' markers"
  - "Plan 56-04 (manual regenerate-and-paste checkpoint) is now unblocked"
affects:
  - test/generate_reference.py (rewritten, 144 → 340 lines)
tech-stack:
  added: []
  patterns:
    - "Phase 53 stage2_reference.py print-Julia-const-block pattern, generalised across scalar / Float64[N] / NTuple{3, Float64} types"
    - "ChannelVar enum import via try/except fallback chain for Python STREAM revision drift"
key-files:
  created: []
  modified:
    - test/generate_reference.py
decisions:
  - "STREAM_PATH now honors STREAM_PYTHON_PATH env var (matches Phase 53 stage2_reference.py convention) — falls back to ~/projects/STREAM when unset, preserving the existing developer default"
  - "WARNING from check_gravity_mismatch routed to stderr, not stdout — keeps stdout clean for Plan 04 sed extraction"
  - "Smoke-run of the rewritten generator deferred to Plan 04 manual checkpoint — this executor runs in a worktree without the developer's Python STREAM venv"
metrics:
  duration: ~10 min
  completed: 2026-05-08
  tasks_completed: 1
  files_modified: 1
---

# Phase 56 Plan 02: Rewrite test/generate_reference.py — Summary

One-liner: rewrote `test/generate_reference.py` (144 → 340 lines) so it emits **all** D-07 tier (a)+(b)+(c) Python STREAM reference values for the simple-loop scenario as ready-to-paste Julia const blocks, plus the four `PYTHON_*_AT_REF` fluid-prop equivalence-checklist tuples for `parity_helpers.jl`.

## What Shipped

The rewritten generator preserves the original topology (Pump → HX → ChannelAndContacts → Pump) verbatim and replaces the trailing print epilogue with a three-block emitter:

- **Block 1 — `parity_helpers.jl` REF constants** (bracketed by `# --- begin paste: parity_helpers.jl REF constants ---` / `# --- end paste: parity_helpers.jl REF constants ---`). Four `NTuple{3, Float64}` constants computed at `REF_T_K = (313.15, 343.15, 373.15)` K against the Python STREAM `light_water` correlations:
  - `PYTHON_RHO_AT_REF`  (kg/m³, `%.10f`)
  - `PYTHON_CP_AT_REF`   (J/kg·K, `%.10f`)
  - `PYTHON_MU_AT_REF`   (Pa·s, `%.10e`)
  - `PYTHON_K_AT_REF`    (W/m·K, `%.10f`)

- **Block 2 — simple-loop reference const block for `test/data/python_parity_reference.jl`** (bracketed by `# --- begin paste: test/data/python_parity_reference.jl simple-loop block ---` / `# --- end paste: ... ---`). Three scalars + seven `Float64[N=10]` per-cell arrays:
  - Tier (a) scalars: `PARITY_SIMPLE_T_OUT`, `PARITY_SIMPLE_MDOT`, `PARITY_SIMPLE_DP`
  - Tier (b): `PARITY_SIMPLE_T_CELLS` (Kelvin)
  - Tier (c) wall observables: `PARITY_SIMPLE_T_WALL_LEFT`, `PARITY_SIMPLE_T_WALL_RIGHT`, `PARITY_SIMPLE_H_TC_LEFT`, `PARITY_SIMPLE_H_TC_RIGHT`, `PARITY_SIMPLE_Q_DENSITY_LEFT`, `PARITY_SIMPLE_Q_DENSITY_RIGHT`

  Per the BLOCKER #1 mitigation (Gap #1: Python emits q on πD-LEFT and 0-RIGHT for one-sided heating; Julia splits πD/2 each side), **both** `_LEFT` and `_RIGHT` q-density arrays are emitted so Plan 56-05's parity testset can SUM them on the Python side and compare totals against Julia.

- **Block 3 — diagnostics** (NOT pasted; for human inspection): T_out, mdot, DP_total, Re mean, HTC means, T_cells range, T_wall means, q means, plus the four equivalence-checklist values pretty-printed at each REF_T_K.

## Const Names Emitted (for Plan 04/05 grep targets)

```
PYTHON_RHO_AT_REF                # NTuple{3, Float64}
PYTHON_CP_AT_REF                 # NTuple{3, Float64}
PYTHON_MU_AT_REF                 # NTuple{3, Float64} (%.10e for sub-mPa·s precision)
PYTHON_K_AT_REF                  # NTuple{3, Float64}

PARITY_SIMPLE_T_OUT              # Float64
PARITY_SIMPLE_MDOT               # Float64
PARITY_SIMPLE_DP                 # Float64
PARITY_SIMPLE_T_CELLS            # Float64[10]
PARITY_SIMPLE_T_WALL_LEFT        # Float64[10]
PARITY_SIMPLE_T_WALL_RIGHT       # Float64[10]
PARITY_SIMPLE_H_TC_LEFT          # Float64[10]   (W/m^2/K)
PARITY_SIMPLE_H_TC_RIGHT         # Float64[10]   (W/m^2/K)
PARITY_SIMPLE_Q_DENSITY_LEFT     # Float64[10]   (W/m^2)
PARITY_SIMPLE_Q_DENSITY_RIGHT    # Float64[10]   (W/m^2)
```

11 simple-loop consts + 4 fluid-prop tuples = **15** ready-to-paste Julia constant declarations across the two paste blocks.

Number of `# --- begin paste` markers in the file: **3** (the third is the literal example in the docstring; the two functional ones are inside `print(...)` calls and emit at runtime, satisfying the planner's `>= 2` requirement on the runtime output and a stricter `>= 2` requirement on the file content).

## ChannelVar Import Path

The plan flagged that the `ChannelVar` enum has moved across Python STREAM revisions. The rewritten generator uses a three-step `try/except ImportError` fallback chain and stores the winning path in `_CHANNELVAR_IMPORT_PATH`:

1. `from stream.calculations.channel import ChannelVar`  (this is the path RESEARCH.md verified during planning — most likely to fire on the developer's current checkout)
2. `from stream.calculations.channel_vars import ChannelVar`  (plausible refactor target)
3. `from stream.calculations.variables import ChannelVar`  (alt refactor target)

If none match, an `ImportError` is raised with an explicit message asking the developer to extend the chain. `_CHANNELVAR_IMPORT_PATH` is also printed in the runtime header so Plan 04 / 05 reviewers see at a glance which path was used.

**Which branch fired:** **deferred to Plan 04** — this executor runs in a worktree without the developer's Python STREAM venv, so the smoke-run was not performed. Plan 04 will report this in its checkpoint output.

## Pitfall Compliance (RESEARCH.md verification)

- **Pitfall 1 (Channel vs CAC):** verified — `channel = ChannelAndContacts(...)` retained verbatim. Tier (c) wall observables are CAC-only.
- **Pitfall 3 (T_left/T_right must be set):** verified — `funcs={channel: dict(T_left=T_WALL_C, T_right=T_WALL_C, p_abs=P_ABS)}` retained. Without these, `save()` skips the `twall_left`/`twall_right` keys (channel.py:628 conditional) and the generator would `KeyError` at extract time.
- **Pitfall 4 (Celsius → Kelvin):** verified — every temperature is `T_C + 273.15` before printing (`T_out_K`, `T_cells_K`, `T_wall_left_K`, `T_wall_right_K`). `light_water.density(T)` etc. are called with `T_K - 273.15` (Celsius input convention).

## Smoke-Run Status

**Deferred to Plan 04.** This executor runs in a Claude Code worktree on the same WSL2 host but does not have access to the developer's Python venv with `stream` installed; running `python3 test/generate_reference.py` would error at `from stream.calculations import Pump, HeatExchanger`. Plan 04 (manual regenerate-and-paste checkpoint) is the explicit smoke-run gate per D-06.

What was verified statically here:
- File parses as valid Python (`python3 -c "import ast; ast.parse(open('test/generate_reference.py').read())"` exits 0).
- All 15 const names present in the source.
- Both functional `# --- begin paste ---` markers present (`grep -c 'begin paste'` returns 3 — 2 print-statement markers + 1 docstring example, well above the `>= 2` threshold).
- `ChannelAndContacts` retained, `REF_T_K` declared, file length 340 ≥ 200 lines.
- Original assertions on `T_out_K` and `mdot` preserved (`> T_INLET_K`, `< 450.0`, `> 1e-4`).

## Deviations from Plan

None. Plan 02 executed exactly as written. Two minor non-deviating clarifications worth recording:

- The plan's `<verify>` block specified `grep -c "begin paste" >= 2` as a stricter check than `grep -q`. The rewritten file produces 3 matches (2 functional + 1 docstring example), comfortably exceeding the threshold.
- The plan suggested `_emit_julia_array(..., comment_each=True, comment_prefix="q_density_left  # W/m^2")` would render as `# q_density_left  # W/m^2[1]`. This is what the plan specified verbatim, so the implementation honors it — the trailing `[i]` index suffix appears AFTER the embedded `# W/m^2` annotation. Visually a little cluttered, but matches the spec; if Plan 04 reviewer prefers a tidier format the prefix can be shortened in a follow-up.

## Auth Gates Encountered

None.

## Threat Flags

None. The rewrite stays within the threat model declared in 56-02-PLAN.md: Python STREAM at `~/projects/STREAM` is a trusted developer-local read-only import path; output is reviewed in Plan 04 before pasting; no PII / credentials; `STREAM_PYTHON_PATH` env override matches Phase 53 stage2_reference.py convention and is still developer-controlled.

## Known Stubs

None.

## Self-Check: PASSED

- `test/generate_reference.py` exists at expected path: FOUND
- Commit `8988c2e` exists in `git log --oneline --all`: FOUND
- All 15 const names grep-verified in the file: FOUND
- File parses as valid Python: FOUND
- Worktree HEAD on `worktree-agent-af911f8246f2833ba` (per `worktree-agent-*` namespace requirement): FOUND
- No file deletions in the commit (`git diff --diff-filter=D HEAD~1 HEAD` empty): FOUND

## Commits

| Task | Description                                                                                          | Commit  |
| ---- | ---------------------------------------------------------------------------------------------------- | ------- |
| 1    | Rewrite `test/generate_reference.py` to emit all D-07 tier (a)+(b)+(c) parity reference values       | 8988c2e |

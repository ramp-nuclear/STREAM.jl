---
phase: 52-channel-connectors
plan: 01
subsystem: connectors
tags:
  - julia
  - modelingtoolkit
  - connectors
  - acausal-port
  - thermal-hydraulics

# Dependency graph
requires:
  - phase: pre-existing
    provides: "FlowPort, ThermalPort templates in src/connectors.jl"
provides:
  - "WallPort scalar acausal connector (T_wall, h across; Q_flow Flow)"
  - "HeatFluxPort scalar acausal connector (q_flux across; Q_flow Flow)"
  - "Public exports of WallPort and HeatFluxPort under `using STREAM`"
affects:
  - 52-02-PLAN (test surface for these connectors)
  - 53 (shared `_channel_core` consumes these)
  - 54 (Channel and ChannelHeatFlux variant rewrites instantiate them as arrays per side per cell)
  - 55 (composition helpers extended to accept WallPort arrays)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Scalar-per-cell connector pattern for thermal coupling (D-01 spike-locked 2026-05-05)"
    - "Adiabatic-when-unconnected via numeric Float64 IC defaults alone (no ifelse guard)"
    - "Multi-across-variable connector with single Flow variable (T_wall + h alongside Q_flow)"

key-files:
  created: []
  modified:
    - "src/connectors.jl: appended WallPort and HeatFluxPort @connector function blocks (24 -> 80 lines)"
    - "src/STREAM.jl: extended line 28 export from `FlowPort, ThermalPort` to `FlowPort, ThermalPort, WallPort, HeatFluxPort`"

key-decisions:
  - "WallPort carries T_wall (K), h (W/m^2.K) as across variables, Q_flow (W) as Flow — three unknowns total"
  - "HeatFluxPort carries q_flux (W/m^2) as across, Q_flow (W) as Flow — two unknowns total"
  - "All IC defaults are Float64 literals (T_wall=300.0, h=0.0, q_flux=0.0, Q_flow=0.0); zero ifelse, zero `nothing` sentinels (D-06, D-07)"
  - "Single export rule honoured — no export statement inside src/connectors.jl (CLAUDE.md `Exports`)"
  - "Sign convention: Q_flow positive = into channel (matches existing ThermalPort `into component` semantics, wording adapted for downstream consumer)"

patterns-established:
  - "@connector function template mirrored verbatim from ThermalPort: keyword-only `name`, numeric Float64 kwarg defaults, `sts = @variables begin ... end`, body `System(Equation[], t, sts, []; name=name)`"
  - "Multi-line Flow-variable form preserved: `Q_flow(t) = Q_flow,\\n        [connect = Flow, description = ...]`"
  - "Docstrings carry `# Arguments` and `# Returns` sections per CLAUDE.md"

requirements-completed:
  - CONN-01
  - CONN-02

# Metrics
duration: 4min
completed: 2026-05-05
---

# Phase 52 Plan 01: Channel Connectors Summary

**WallPort (T_wall, h, Q_flow) and HeatFluxPort (q_flux, Q_flow) scalar MTK acausal connectors added to src/connectors.jl and exported from src/STREAM.jl, mirroring ThermalPort's template verbatim with adiabatic-by-default semantics via Float64 IC defaults alone — no ifelse guards, no `nothing` sentinels.**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-05-05T20:17:47Z
- **Completed:** 2026-05-05T20:21:38Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- **CONN-01 delivered.** `WallPort(; name, T_wall=300.0, h=0.0, Q_flow=0.0)` ships in `src/connectors.jl` carrying three unknowns: `T_wall(t)` and `h(t)` as across variables (no `connect` metadata), and `Q_flow(t)` annotated `[connect = Flow]`. Adiabatic when unconnected — `h=0` IC alone makes the eventual Phase 54 channel equation `port.h · heated_part · dz · (port.T_wall − T[i])` evaluate to 0 regardless of `T_wall`.
- **CONN-02 delivered.** `HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)` ships carrying two unknowns: `q_flux(t)` as across and `Q_flow(t)` Flow. Zero-flux when unconnected — `q_flux=0` IC ⇒ `port.Q_flow ~ q_flux · heated_part · dz = 0`.
- **Exports plumbed.** `src/STREAM.jl` line 28 changed from `export FlowPort, ThermalPort` to `export FlowPort, ThermalPort, WallPort, HeatFluxPort`. Single source of truth for public API per CLAUDE.md `Exports` rule.
- **REPL contract verified.** `using STREAM; @named wp = WallPort()` and `@named hf = HeatFluxPort()` succeed; `length(unknowns(wp)) == 3`, `length(unknowns(hf)) == 2`. `ThermalPort` (2 unknowns) and `FlowPort` (3 unknowns) still resolve unchanged — CONN-03 non-regression at the export-list level.

## Task Commits

Each task was committed atomically:

1. **Task 1: Append WallPort and HeatFluxPort to src/connectors.jl** — `da397ea` (feat)
2. **Task 2: Extend export line in src/STREAM.jl** — `c812da0` (feat)

_No plan-metadata commit yet — that lands after this SUMMARY is staged and committed below._

## Files Created/Modified

- `src/connectors.jl` — appended two `@connector function` blocks (`WallPort`, `HeatFluxPort`) with full docstrings (`# Arguments`, `# Returns`); file now contains 4 connectors total (FlowPort, ThermalPort, WallPort, HeatFluxPort). No `using` statements added (existing lines 1-5 already bring `ModelingToolkit` and `t_nounits as t` into scope). No `export` statements added (single-export rule).
- `src/STREAM.jl` — single-line edit on line 28 only; no other lines modified, no `include` order change.

## Decisions Made

None new — all 19 design decisions were locked in `52-CONTEXT.md` (D-01 through D-19) prior to execution. This plan was a pure transcription of D-01..D-10 into Julia source. The locked-in choices the implementation honoured exactly:

- **D-01 (array-of-scalar pattern).** Scalar connectors only; vector-form rejected by spike. Phase 54 will instantiate them as `[WallPort(; name=Symbol(:thermal_left, i)) for i in 1:n]` (referenced in WallPort's docstring).
- **D-02/D-03 (variable lists).** `WallPort` = T_wall + h + Q_flow; `HeatFluxPort` = q_flux + Q_flow. Verified by REPL `length(unknowns(...))`.
- **D-04 (file placement).** Both connectors in `src/connectors.jl`; both exports in `src/STREAM.jl`. No new directories, no in-file `export` statements.
- **D-06/D-07 (numeric Float64 IC defaults; no ifelse, no `nothing`).** Verified: `grep -c "ifelse" src/connectors.jl` returns `0`; `grep -c "nothing" src/connectors.jl` returns `0`; all defaults use `300.0` / `0.0` literals.
- **D-08 (Q_flow sign).** "positive = into channel" wording (downstream-consumer aligned) — matches `ThermalPort`'s "positive = into component" semantics with adapted wording.
- **D-09 (q_flux units).** W/m^2 (intensive); `ChannelHeatFlux` (Phase 54) will multiply by `heated_part · dz`.

## Deviations from Plan

None - plan executed exactly as written.

The plan's two task `<action>` blocks specified the exact bytes to append/replace; the implementation matched them verbatim including docstring text, indentation, blank-line separators, and the multi-line Flow-variable layout (`Q_flow(t) = Q_flow,\n    [connect = Flow, description = "..."]`).

**One observation worth noting (not a deviation):** when running the Plan-01 verification command `julia --project=. -e '... @named wp = WallPort() ...'`, MTK emits a benign warning about WallPort's shape (1 Flow variable + 2 non-flow variables — T_wall and h). The warning is informational, not a failure, and reflects the locked design (D-02 explicitly defines this 1-Flow + 2-across shape). Plan 02's `@test_nowarn` smoke loop will need to evaluate whether to filter or accept this warning when wiring the stub recipient — that decision is out of scope for Plan 01 (which only ships the connector definitions).

## Issues Encountered

**Working-tree path mismatch (resolved).** The first Task-1 Edit was applied against `/home/itayb/projects/STREAM.jl/src/connectors.jl` (main repo) instead of `/home/itayb/projects/STREAM.jl/.claude/worktrees/agent-a21b939e87c382a74/src/connectors.jl` (this agent's worktree), because shell commands with `cd /home/itayb/projects/STREAM.jl &&` redirected to the main repo. Resolution: reverted the main-repo working-tree change with `git checkout -- src/connectors.jl` (no commit had been made on main), then re-applied the Edit to the worktree's copy. All subsequent operations used `git -C $WT` and absolute paths under the worktree to keep the operation strictly worktree-scoped. Both commits (`da397ea` and `c812da0`) live on `worktree-agent-a21b939e87c382a74` only; `main`/`gsd/v1.1-milestone` are untouched.

## User Setup Required

None — no external service configuration required. This plan ships pure Julia source code and an export-line edit.

## Next Phase Readiness

- **Plan 02 (Wave 2) is unblocked.** The new connectors are exported and instantiable; Plan 02's inline test stubs (`_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`) can build against them, the `@test_nowarn` smoke compose target can drive a pump→stub→pump closed loop, and the variable-annotation introspection testsets can use `Symbolics.getmetadata`.
- **Phase 53 / 54 unblocked.** The connector contract is now stable: Phase 54's `Channel` rewrite can reference `WallPort` arrays and Phase 54's `ChannelHeatFlux` rewrite can reference `HeatFluxPort` arrays. The MTK warning on instantiation (1 Flow + 2 across vars) is design-locked behaviour; Phase 54's energy-balance equations (the multiplication by `port.h` for `WallPort`, by `port.q_flux` for `HeatFluxPort`) will produce well-formed equations under the existing connector idiom.
- **CONN-03 / CONN-04 still open.** CONN-03 (non-regression of `ChannelAndContacts`'s existing `ThermalPort` arrays) and CONN-04 (smoke-loop coexistence with `instream()`) are tested in Plan 02. This plan only verified at the export-list level (FlowPort + ThermalPort still instantiate with correct unknowns counts).
- **Branch hygiene.** Both commits are on the per-agent branch `worktree-agent-a21b939e87c382a74`; the orchestrator merges them back to `gsd/v1.1-milestone` (the v1.1 working branch) after the worktree is reaped. No commits to `main` (D-19).

## Self-Check

Verification of `must_haves.truths` from PLAN frontmatter:

1. **"WallPort connector is defined in src/connectors.jl carrying T_wall, h, Q_flow"** — VERIFIED: `grep -q "@connector function WallPort" src/connectors.jl` exits 0; `grep -q "T_wall(t)" src/connectors.jl` and `grep -q "h(t)" src/connectors.jl` and `grep -q "Q_flow(t)" src/connectors.jl` all exit 0.
2. **"HeatFluxPort connector is defined in src/connectors.jl carrying q_flux, Q_flow"** — VERIFIED: `grep -q "@connector function HeatFluxPort" src/connectors.jl` exits 0; `grep -q "q_flux(t)" src/connectors.jl` and `grep -q "Q_flow(t)" src/connectors.jl` exit 0.
3. **"Both connectors are exported from src/STREAM.jl (single export rule honoured)"** — VERIFIED: `grep -q "^export FlowPort, ThermalPort, WallPort, HeatFluxPort$" src/STREAM.jl` exits 0; `grep -c "^export " src/connectors.jl` returns `0` (no in-file exports).
4. **"`using STREAM; @named wp = WallPort()` succeeds at the REPL"** — VERIFIED: ran `julia --project=. -e 'using STREAM; @named wp = WallPort(); @assert length(unknowns(wp)) == 3'`, exit 0, stdout `Plan 01 verification: OK`.
5. **"`using STREAM; @named hf = HeatFluxPort()` succeeds at the REPL"** — VERIFIED: same command above also asserts `length(unknowns(hf)) == 2`, exit 0.
6. **"Adiabatic-when-unconnected defaults are numeric Float64 only — no ifelse guards added anywhere"** — VERIFIED: `grep -c "ifelse" src/connectors.jl` returns `0`; `grep -c "nothing" src/connectors.jl` returns `0`; kwarg position uses `T_wall=300.0, h=0.0, Q_flow=0.0` and `q_flux=0.0, Q_flow=0.0` exclusively (Float64 literals).

Verification of `must_haves.key_links` from PLAN frontmatter:

1. **`src/STREAM.jl line 28` → `WallPort, HeatFluxPort` defined in `src/connectors.jl`, pattern `^export FlowPort, ThermalPort, WallPort, HeatFluxPort$`** — VERIFIED: pattern grep returns line 28; `using STREAM; WallPort` and `using STREAM; HeatFluxPort` resolve at the REPL.
2. **`src/connectors.jl WallPort body` → `T_wall=300.0, h=0.0, Q_flow=0.0` Float64 IC defaults** — VERIFIED: `grep -q "T_wall=300.0, h=0.0, Q_flow=0.0" src/connectors.jl` exits 0.
3. **`src/connectors.jl HeatFluxPort body` → `q_flux=0.0, Q_flow=0.0` Float64 IC defaults** — VERIFIED: `grep -q "q_flux=0.0, Q_flow=0.0" src/connectors.jl` exits 0.

Verification of artifacts:

- `src/connectors.jl` contains `@connector function WallPort` — VERIFIED.
- `src/connectors.jl` contains `@connector function HeatFluxPort` — VERIFIED.
- `src/STREAM.jl` contains `WallPort, HeatFluxPort` (within the export line) — VERIFIED.

Commit-existence verification:

- `git -C <worktree> log --oneline | grep da397ea` — found: `da397ea feat(52-01): add WallPort and HeatFluxPort MTK acausal connectors`
- `git -C <worktree> log --oneline | grep c812da0` — found: `c812da0 feat(52-01): export WallPort and HeatFluxPort from STREAM module`

## Self-Check: PASSED

All `must_haves.truths` (6/6) verified; all `must_haves.key_links` (3/3) verified; all `must_haves.artifacts` (3/3) verified; both task commits present on the worktree branch.

---
*Phase: 52-channel-connectors*
*Completed: 2026-05-05*

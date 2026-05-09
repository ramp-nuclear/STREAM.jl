---
phase: 54
plan: 04
subsystem: components
tags: [channels, file-consolidation, var-04, d-10, d-11]
requires:
  - "Phase 54-01 channels.jl with `function Channel end` declaration + `_channel_core` + new passive-recipient `Channel`"
  - "Phase 54-02 ChannelHeatFlux added to channels.jl (legacy CHF body gutted in thermal_channel.jl)"
  - "Phase 54-03 ChannelAndContacts added to channels.jl (legacy CAC body gutted in thermal_channel.jl)"
provides:
  - "Single-file channel-family layout: `src/components/channels.jl` is the SOLE authoritative source for `_channel_core`, `Channel`, `ChannelHeatFlux`, `ChannelAndContacts`"
  - "Updated CLAUDE.md File Structure Standard reflecting the new single-file layout (D-11)"
affects:
  - "src/components/channel.jl (DELETED via git rm)"
  - "src/components/thermal_channel.jl (DELETED via git rm)"
  - "src/STREAM.jl (two legacy include lines removed; channels.jl include kept; ordering verified — channels.jl precedes composition/helpers.jl)"
  - "CLAUDE.md (File Structure Standard tree updated to channels.jl plural; test file mirror example updated to test_channels.jl; test/ tree updated)"
tech-stack:
  added: []
  patterns: []
key-files:
  created:
    - ".planning/phases/54-variant-rewrites-file-consolidation/54-04-SUMMARY.md"
  modified:
    - "src/STREAM.jl"
    - "CLAUDE.md"
  deleted:
    - "src/components/channel.jl"
    - "src/components/thermal_channel.jl"
decisions:
  - "Followed plan D-10: deleted both legacy files via git rm; STREAM.jl now has a single `include(\"components/channels.jl\")` line for the channel family. Pre-flight check confirmed all four definitions (_channel_core, Channel, ChannelHeatFlux, ChannelAndContacts) live in channels.jl exactly once before deletion."
  - "Followed plan D-11: CLAUDE.md File Structure Standard `src/components/` tree replaced two singular lines (`channel.jl`, `thermal_channel.jl`) with one plural `channels.jl` line; test/ tree's `test_channel.jl` line updated to `test_channels.jl`; Test placement rule example updated from `components/channel.jl` → `test_channel.jl` to `components/channels.jl` → `test_channels.jl`."
  - "STREAM.jl include order verified: channels.jl precedes composition/helpers.jl (acceptance check via awk passed) — required because composition/helpers.jl uses ChannelAndContacts via `symmetric_plate`."
  - "Two historical comment references to `thermal_channel.jl` in `src/components/channels.jl` (lines 498 and 595) preserved — the plan's Step E explicitly allowed `comments referencing history` to remain. They document where the migrated CAC code came from (legacy thermal_channel.jl line numbers)."
metrics:
  tasks_completed: 1
  tasks_total: 1
  duration_minutes: 4
  commits: 2
  completed: "2026-05-07"
---

# Phase 54 Plan 04: Channels File Consolidation Summary

Deleted the two legacy channel-family source files (`src/components/channel.jl`, `src/components/thermal_channel.jl`), removed their two `include(...)` lines from `src/STREAM.jl`, and updated the `CLAUDE.md` File Structure Standard tree + prose to reflect the single `src/components/channels.jl` file. After this plan, `channels.jl` is the sole authoritative home for `_channel_core`, `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts`. Implements VAR-04 (D-10, D-11). Closes Phase 54's file-consolidation deliverable.

## What Shipped

### 1. `src/components/channel.jl` and `src/components/thermal_channel.jl` (DELETED)

Both files were near-empty header-comment stubs at the start of this plan (gutted in 54-01..03 — see those summaries for the Rule 3 deviation rationale). Pre-deletion line counts:

| File | Lines (pre-delete) | Status before 54-04 |
| --- | --- | --- |
| `src/components/channel.jl` | 18 | Header-comment marker only (legacy `Channel` body removed in 54-01; `_channel_core` migrated to channels.jl in 54-01) |
| `src/components/thermal_channel.jl` | 43 | Header-comment marker only (legacy `ChannelHeatFlux` body removed in 54-02; legacy `ChannelAndContacts` body removed in 54-03) |

Removed via `git rm` (recorded as deletions in the commit, not orphan files).

### 2. `src/STREAM.jl` (two include lines removed)

Diff (semantic):

```diff
-include("components/channel.jl")
 include("components/pump.jl")
 include("components/flapper.jl")
 include("components/resistors.jl")
 include("components/misc.jl")
-include("components/thermal_channel.jl")
 include("components/channels.jl")
 include("components/heat_diffusion.jl")
 include("components/point_kinetics.jl")
```

Net change: −2 lines. The `include("components/channels.jl")` line that 54-01 added is the sole remaining channel-family include. Order constraint verified: `channels.jl` precedes `composition/helpers.jl` (acceptance awk check passed), which is required because `composition/helpers.jl` uses `ChannelAndContacts` via `symmetric_plate`.

The post-edit includes block (lines 6–24 of `src/STREAM.jl`):

```julia
include("fluids.jl")
include("connectors.jl")
include("geometry.jl")
include("physical_models/htc/correlations.jl")
include("physical_models/friction/correlations.jl")
include("physical_models/subcooled_boiling.jl")
include("physical_models/threshold_analysis.jl")
include("physical_models/dimensionless.jl")
include("components/pump.jl")
include("components/flapper.jl")
include("components/resistors.jl")
include("components/misc.jl")
include("components/channels.jl")
include("components/heat_diffusion.jl")
include("components/point_kinetics.jl")
include("composition/helpers.jl")
include("solvers.jl")
include("analysis.jl")
include("examples.jl")
```

### 3. `CLAUDE.md` (File Structure Standard updates per D-11)

Three mechanical edits, all within the File Structure Standard section:

**Edit 1 — `src/components/` tree:** replaced two lines with one.

```diff
-    channel.jl                # Channel + _channel_base_eqs (basic convective channel)
-    thermal_channel.jl        # ChannelAndContacts, ChannelHeatFlux (with ThermalPort arrays)
+    channels.jl               # Channel, ChannelHeatFlux, ChannelAndContacts + _channel_core (shared private core)
     heat_diffusion.jl         # HeatDiffusion + _diffusion_eqs (2D FD solid plate)
```

The legacy `_channel_base_eqs` mention in the old comment was already incorrect (Phase 53 deleted `_channel_base_eqs`); the new line uses `_channel_core` (the shared private core), which is the correct current name.

**Edit 2 — `test/` tree:** mirror the `src/components/` rename.

```diff
-  test_channel.jl           # Channel, ChannelAndContacts, ChannelHeatFlux (COMP-01, GRAV-*, CHAN-*, THERM-*, PHY-02/03/04)
+  test_channels.jl          # Channel, ChannelHeatFlux, ChannelAndContacts (COMP-01, GRAV-*, CHAN-*, THERM-*, PHY-02/03/04)
```

(Note: `test/test_channel.jl` still exists on disk and is intentionally NOT touched here — Phase 55's TEST-01 rewrites it into `test/test_channels.jl`. The CLAUDE.md File Structure Standard documents the *target* layout the codebase converges on; the file system catches up in Phase 55.)

**Edit 3 — Test placement rule example:** mirror the rename in the prose.

```diff
-**Test placement rule:** test file mirrors src file. `components/channel.jl` → `test_channel.jl`. New component file → new test file.
+**Test placement rule:** test file mirrors src file. `components/channels.jl` → `test_channels.jl`. New component file → new test file.
```

## Verification

| Acceptance criterion (from PLAN <acceptance_criteria>) | Result |
| --- | --- |
| `! test -f src/components/channel.jl` (deleted) | OK |
| `! test -f src/components/thermal_channel.jl` (deleted) | OK |
| `test -f src/components/channels.jl` (still exists) | OK |
| `! grep -q 'include("components/channel.jl")' src/STREAM.jl` | OK |
| `! grep -q 'include("components/thermal_channel.jl")' src/STREAM.jl` | OK |
| `grep -q 'include("components/channels.jl")' src/STREAM.jl` | OK |
| `[ $(ls src/components/channel*.jl 2>/dev/null \| wc -l) -eq 1 ]` | OK (only `src/components/channels.jl`) |
| `! grep -qE '^\s+channel\.jl\s' CLAUDE.md` (old singular `channel.jl` line gone) | OK |
| `! grep -q 'thermal_channel\.jl' CLAUDE.md` (escaped dot; thermal_channel.jl gone) | OK |
| `grep -q "channels.jl" CLAUDE.md` (new plural file present) | OK |
| `awk` ordering check: channels.jl precedes composition/helpers.jl in STREAM.jl | OK |
| `julia --project=. -e 'using STREAM'` precompiles & loads cleanly | OK (10.2 s recompile; zero method-overwriting warnings) |
| All three variants construct from new home (`STREAM.Channel`, `STREAM.ChannelHeatFlux`, `STREAM.ChannelAndContacts`) | OK |

Pre-flight check (Step A): each of the four function definitions appears exactly once in `src/components/channels.jl` (`_channel_core`, `Channel(;`, `ChannelHeatFlux(;`, `ChannelAndContacts(;`). Confirmed before any `git rm` ran.

## Plan-Specified Output Items

- **Two files deleted with line counts before deletion:** `src/components/channel.jl` (18 lines) and `src/components/thermal_channel.jl` (43 lines). Both were already near-empty header-comment markers at the start of this plan.
- **STREAM.jl includes diff (−2 lines, no other changes):** Confirmed. Removed `include("components/channel.jl")` and `include("components/thermal_channel.jl")`. The single `include("components/channels.jl")` line that 54-01 added remains. No other modifications to `STREAM.jl`.
- **CLAUDE.md diff (tree update + Test placement rule example update):** Three mechanical edits in the File Structure Standard section: (1) `src/components/` tree two-lines-to-one collapse, (2) `test/` tree filename mirror, (3) Test placement rule prose example. All three minimal — no structural reorganization.
- **Confirmation that `using STREAM` loads with no warnings:** Confirmed (cold start ~21 s including 10.2 s STREAM precompile; zero method-overwriting warnings in stdout/stderr).
- **Confirmation that `test/test_channel.jl` is intentionally not touched:** Confirmed. `test/test_channel.jl` still exists on disk and references the old API; this is Phase 55's TEST-01 territory (per Phase 54 D-12 / D-13). The CLAUDE.md File Structure Standard documents the target layout (`test_channels.jl`); the file system catches up in Phase 55.

## Bare-Channel Name Ambiguity (informational, not a regression)

When running `julia --project=. -e 'using STREAM; ch = Channel(; ...)'`, the bare `Channel` symbol resolves ambiguously between `STREAM.Channel` and `Base.Channel{T}` (Julia stdlib's task-communication channel). This is a Main-scope shell quirk: when `using STREAM` re-exports `Channel`, both `STREAM.Channel` and `Base.Channel` are visible at Main, and Julia raises an `UndefVarError` with the "two or more modules export different bindings" hint.

This is **NOT a regression introduced by 54-04**. It is the original motivation for 54-01's `function Channel end` Base disambiguation declaration, which solved the issue *inside* the STREAM module (so `using STREAM` precompiles correctly). The Main-scope ambiguity persists for inline `-e` calls and is the user's concern at call site, not a STREAM packaging bug. Workaround for inline calls: use `STREAM.Channel(; ...)` or `import STREAM: Channel` first. Inside production code (`src/examples.jl`, `test/test_channels.jl` once Phase 55 ships) the relevant module already imports `STREAM` cleanly, so the issue does not arise.

Verification of three-variant construction with explicit qualification:

```
julia --project=. -e 'using STREAM; ch = STREAM.Channel(; name=:c, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); chf = STREAM.ChannelHeatFlux(; ...); cac = STREAM.ChannelAndContacts(; ...)'
# → "[ Info: all three variants constructed via STREAM.*"
```

## Deviations from Plan

### Auto-fixed Issues

None. All four sub-actions (A pre-flight, B git rm, C STREAM.jl edit, D CLAUDE.md edits, E verification) executed as the plan specified. The Rule 3 same-signature method-overwriting deviation that Waves 1, 2, and 3 documented does not recur here — those waves had already gutted the legacy bodies; this plan only deletes the (already empty) marker files and removes their `include` lines.

### Architectural Decisions Asked

None.

## Authentication Gates

None encountered.

## Known Stubs

None.

## Test File Status (information for downstream plans)

Unchanged from 54-01..03's reporting:

- `test/test_channel.jl` continues to exist and reference the old API. Stale by design; Phase 55 (TEST-01) rewrites it into `test/test_channels.jl`. Phase 54 close criterion does NOT require `test/test_channel.jl` to pass (per D-12 / D-13).
- `test/test_connectors.jl` still passes (33/33, established in 54-01).
- `test/runtests.jl` is not modified here (54-05's concern).
- The new `test/test_channels.jl` smoke file is created in Phase 54-05 (D-13/D-14/D-15/D-16).

## Threat Flags

None — this plan is purely a file-deletion + STREAM.jl include-pruning + CLAUDE.md doc edit. No new network endpoints, auth paths, file access patterns, or schema changes.

## Self-Check: PASSED

- File `src/components/channel.jl` does not exist (deleted): OK
- File `src/components/thermal_channel.jl` does not exist (deleted): OK
- File `src/components/channels.jl` exists: OK
- File `.planning/phases/54-variant-rewrites-file-consolidation/54-04-SUMMARY.md` exists: OK (this file)
- All 12 plan-listed grep/awk/test acceptance criteria satisfied: OK (see Verification table above)
- `using STREAM` precompiles cleanly with zero method-overwriting warnings: OK
- All three variants construct via `STREAM.*` qualified names: OK

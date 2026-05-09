---
phase: 54
plan: 04
type: execute
wave: 4
depends_on: [54-01, 54-02, 54-03]
files_modified:
  - src/components/channel.jl
  - src/components/thermal_channel.jl
  - src/STREAM.jl
  - CLAUDE.md
autonomous: true
requirements: [VAR-04]
must_haves:
  truths:
    - "src/components/channel.jl is deleted"
    - "src/components/thermal_channel.jl is deleted"
    - "src/STREAM.jl has exactly one channels include line — components/channels.jl"
    - "src/STREAM.jl has no method-overwriting warnings on `using STREAM`"
    - "All three variants (Channel, ChannelHeatFlux, ChannelAndContacts) live in src/components/channels.jl"
    - "git ls-files src/components/ returns exactly one channels file (channels.jl, not channel.jl, not thermal_channel.jl)"
    - "CLAUDE.md File Structure Standard tree lists channels.jl (plural), not channel.jl + thermal_channel.jl"
  artifacts:
    - path: "src/components/channels.jl"
      provides: "Sole authoritative source for _channel_core, Channel, ChannelHeatFlux, ChannelAndContacts"
      contains: "function _channel_core; function Channel(;\\s; function ChannelHeatFlux(;\\s; function ChannelAndContacts(;"
    - path: "src/STREAM.jl"
      provides: "Module entry point with exactly one channels include"
    - path: "CLAUDE.md"
      provides: "Updated File Structure Standard"
  key_links:
    - from: "src/STREAM.jl"
      to: "src/components/channels.jl"
      via: "include(\"components/channels.jl\")"
      pattern: "include\\(\"components/channels\\.jl\"\\)"
---

<objective>
Delete the legacy `src/components/channel.jl` and `src/components/thermal_channel.jl` files, remove their `include(...)` lines from `src/STREAM.jl`, and update the `CLAUDE.md` File Structure Standard to reflect the new single-file layout. After this plan, `src/components/channels.jl` is the sole authoritative source for all three channel variants and `_channel_core`. Implements VAR-04 (D-10, D-11).

Purpose: VAR-04 is the file-consolidation deliverable for Phase 54. Plans 54-01..03 created the new `channels.jl` with all three variants (Channel/CHF/CAC) and `_channel_core`; the legacy two files were left in place so the codebase compiled at every commit boundary (D-12). Now that the new variants are in place, the legacy files are dead code (their definitions are shadowed) and method-overwriting warnings are surfacing on `using STREAM` — this plan removes the warnings and the dead code.

Output: Two files deleted; `STREAM.jl` includes block has exactly one channels file; `CLAUDE.md` File Structure Standard updated.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md
@CLAUDE.md
@src/STREAM.jl
@src/components/channels.jl
@src/components/channel.jl
@src/components/thermal_channel.jl
</context>

<tasks>

<task type="auto">
  <name>Task 1: Delete legacy files, prune STREAM.jl includes, update CLAUDE.md</name>
  <files>src/components/channel.jl, src/components/thermal_channel.jl, src/STREAM.jl, CLAUDE.md</files>
  <read_first>
    - src/STREAM.jl (full file — see the include block; needs two lines removed)
    - src/components/channels.jl (full file — verify all three variants + _channel_core are present before deleting legacy)
    - src/components/channel.jl (header — confirm it's the legacy file being deleted)
    - src/components/thermal_channel.jl (header — confirm it's the legacy file being deleted)
    - CLAUDE.md (lines 15-70 — File Structure Standard section needing prose + tree update)
    - .planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md (D-10, D-11)
  </read_first>
  <action>
    **Step A — Pre-flight verification.** Before deleting anything, grep `src/components/channels.jl` for the three function definitions and `_channel_core`:
    ```bash
    grep -c "^function _channel_core(" src/components/channels.jl
    grep -c "^function Channel(;" src/components/channels.jl
    grep -c "^function ChannelHeatFlux(;" src/components/channels.jl
    grep -c "^function ChannelAndContacts(;" src/components/channels.jl
    ```
    Each must return `1`. If any return `0` or `>1`, STOP — 54-01/02/03 did not converge as expected. Do not delete the legacy files. Re-run those plans first.

    **Step B — Delete legacy source files:**
    ```bash
    git rm src/components/channel.jl
    git rm src/components/thermal_channel.jl
    ```

    **Step C — Update `src/STREAM.jl` include block:**
    Remove these two lines from the includes block:
    ```julia
    include("components/channel.jl")
    include("components/thermal_channel.jl")
    ```
    Keep the single `include("components/channels.jl")` line that 54-01 added. The final includes block (after the existing fluids/connectors/geometry/physical_models block) should look like:
    ```julia
    include("components/pump.jl")
    include("components/flapper.jl")
    include("components/resistors.jl")
    include("components/misc.jl")
    include("components/channels.jl")
    include("components/heat_diffusion.jl")
    include("components/point_kinetics.jl")
    ```
    Note: place `channels.jl` BEFORE `heat_diffusion.jl` (because `heat_diffusion.jl` is independent of channels), and keep the existing relative order of pump/flapper/resistors/misc/heat_diffusion/point_kinetics intact. The exact placement of `channels.jl` within this group is flexible as long as it precedes `composition/helpers.jl` (which uses CAC) and `examples.jl` (which uses Channel/CHF/CAC).

    **Step D — Update `CLAUDE.md` File Structure Standard.** Edit the `src/components/` tree (around CLAUDE.md lines 27-33). Replace these two lines:
    ```
        channel.jl                # Channel + _channel_base_eqs (basic convective channel)
        thermal_channel.jl        # ChannelAndContacts, ChannelHeatFlux (with ThermalPort arrays)
    ```
    With this single line:
    ```
        channels.jl               # Channel, ChannelHeatFlux, ChannelAndContacts + _channel_core (shared private core)
    ```

    Also replace any prose elsewhere in CLAUDE.md that names the two old files. Search for `channel.jl` and `thermal_channel.jl` references and update to `channels.jl`. Update the test mirror example in the "Test placement rule" line (CLAUDE.md line 69) — the example currently reads:
    ```
    **Test placement rule:** test file mirrors src file. `components/channel.jl` → `test_channel.jl`. New component file → new test file.
    ```
    Update to (or similar):
    ```
    **Test placement rule:** test file mirrors src file. `components/channels.jl` → `test_channels.jl`. New component file → new test file.
    ```

    Also check the "**Where new code goes**" section (CLAUDE.md ~line 42-47) — no specific mention of channel.jl / thermal_channel.jl there, but verify and update if found.

    Note: the legacy `_channel_base_eqs` mention in the old line was already incorrect (Phase 53 deleted `_channel_base_eqs` — it's gone from the codebase). The new line uses `_channel_core` (the shared private core) which is the correct current name.

    **Step E — Verify no orphan references.** Grep for any remaining references in `src/`:
    ```bash
    grep -rn "channel.jl\|thermal_channel.jl" src/ 2>/dev/null
    ```
    Expect ZERO matches. If any match remains in source code (not comments referencing history), fix it.

    Grep test files for stale `include("test_channel.jl")` reference handling — that's wave 4's concern (54-05 wires `test_channels.jl` into runtests.jl); leave `test_channel.jl` alone here. The `test_channel.jl` file is stale by design and Phase 55 deletes it.
  </action>
  <verify>
    <automated>bin/jl -e 'using STREAM; @info "loaded clean"; ch = Channel(; name=:c, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); @info "all three variants constructed"'</automated>
  </verify>
  <acceptance_criteria>
    - `! test -f src/components/channel.jl` (deleted)
    - `! test -f src/components/thermal_channel.jl` (deleted)
    - `test -f src/components/channels.jl` (still exists)
    - `! grep -q 'include("components/channel.jl")' src/STREAM.jl`
    - `! grep -q 'include("components/thermal_channel.jl")' src/STREAM.jl`
    - `grep -q 'include("components/channels.jl")' src/STREAM.jl`
    - `[ $(ls src/components/channel*.jl 2>/dev/null | wc -l) -eq 1 ]` (exactly one channels file in src/components/)
    - `! grep -qE '^\s+channel\.jl\s' CLAUDE.md` (old singular `channel.jl` line gone from CLAUDE.md tree — strict: any indentation, then `channel.jl`, then whitespace; the `s` in `channels.jl` correctly fails the trailing `\s` check so the new file is not matched)
    - `! grep -q 'thermal_channel\.jl' CLAUDE.md` (escaped dot; thermal_channel.jl gone)
    - `grep -q "channels.jl" CLAUDE.md` (new plural file present in CLAUDE.md)
    - `awk '/include\("components\/channels\.jl"\)/{c=NR} /include\("composition\/helpers\.jl"\)/{h=NR} END{exit !(c<h)}' src/STREAM.jl` exits 0 (channels.jl include precedes composition/helpers.jl include — required because composition/helpers.jl uses ChannelAndContacts via symmetric_plate)
    - `bin/jl -e 'using STREAM'` exits 0 with no method-overwriting warnings (capture stderr; `using STREAM 2>&1 | grep -q "WARNING.*overwritten"` should return 1, i.e., no match)
  </acceptance_criteria>
  <done>
    `src/components/channel.jl` and `src/components/thermal_channel.jl` deleted via `git rm`. `src/STREAM.jl` has exactly one `include("components/channels.jl")` line for the channel family. `CLAUDE.md` File Structure Standard tree and prose updated to reflect the single `channels.jl` file. `using STREAM` loads cleanly with no method-overwriting warnings. All three variants still construct.
  </done>
</task>

</tasks>

<verification>
- `bin/jl -e 'using STREAM'` exits 0 with no method-overwriting warnings on stderr.
- `bin/jl -e 'using STREAM; ch = Channel(; name=:c, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); cac = ChannelAndContacts(; name=:cac, n=4, geometry=PipeGeometry_circular(0.6, 0.01))'` exits 0.
- `git status` shows two deletes (`channel.jl`, `thermal_channel.jl`) and three modifies (`channels.jl` if any incidental tweaks, `STREAM.jl`, `CLAUDE.md`).
- `bin/jl test/test_connectors.jl` still passes.
- `bin/jl test/test_channel.jl` is EXPECTED TO FAIL — that file uses the old API (T_wall, htc_correlation kwargs on Channel/CHF, scalar `thermal` port). Phase 55 (TEST-01) rewrites it. Do not edit it here.
</verification>

<success_criteria>
1. `src/components/channel.jl` and `src/components/thermal_channel.jl` are deleted (`git rm`).
2. `src/STREAM.jl` has exactly one channels include: `include("components/channels.jl")`.
3. `using STREAM` loads cleanly — no `WARNING: Method definition ... overwritten` messages.
4. All three variants (Channel, ChannelHeatFlux, ChannelAndContacts) construct from `channels.jl`.
5. `CLAUDE.md` File Structure Standard tree shows `channels.jl` (plural) with the correct comment; no stray references to `channel.jl` or `thermal_channel.jl` remain.
6. `git ls-files src/components/` returns `channels.jl` (and the unaffected `pump.jl`, `flapper.jl`, `resistors.jl`, `misc.jl`, `heat_diffusion.jl`, `point_kinetics.jl`) — no `channel.jl`, no `thermal_channel.jl`.
</success_criteria>

<output>
After completion, create `.planning/phases/54-variant-rewrites-file-consolidation/54-04-SUMMARY.md` documenting:
- Two files deleted (with line counts before deletion)
- STREAM.jl includes diff (-2 lines, no other changes)
- CLAUDE.md diff (tree update + Test placement rule example update)
- Confirmation that `using STREAM` loads with no warnings
- Confirmation that test/test_channel.jl is intentionally not touched (Phase 55's TEST-01 territory)
</output>

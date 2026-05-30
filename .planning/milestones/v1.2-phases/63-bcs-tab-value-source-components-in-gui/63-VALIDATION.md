---
phase: 63
slug: bcs-tab-value-source-components-in-gui
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-13
---

# Phase 63 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution. Phase 63 spans two languages (Julia helper + TS/React GUI), so the strategy splits by surface.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework (Julia)** | `Test` stdlib + `bin/jl` daemon |
| **Framework (TS/React)** | `vitest` ^4.1.2 (gui/package.json:48) |
| **Config file (Julia)** | `test/runtests.jl` (orchestrator, one `include()` per test file) |
| **Config file (TS)** | `gui/vitest.config.ts` |
| **Quick run (Julia helper)** | `bin/jl test/test_utilities.jl` |
| **Quick run (codegen)** | `cd gui && npx vitest run src/lib/codeGenerator.bc.test.ts` |
| **Quick run (UI unit)** | `cd gui && npx vitest run <touched file>` |
| **Full suite (Julia)** | `bin/jl test/runtests.jl` |
| **Full suite (TS)** | `cd gui && npm test` |
| **GUI smoke** | `cd gui && npm run tauri dev` (manual; D-10 + D-20 only) |
| **Estimated runtime** | Julia quick ~3-5s (daemon warm); TS quick ~5-15s; full TS ~30-60s |

---

## Sampling Rate

- **After every task commit:** Run the quick command for that task's surface (Julia → `bin/jl test/test_utilities.jl`; TS → `npx vitest run <touched file>`).
- **After every plan wave:** Run both full suites — `bin/jl test/runtests.jl` AND `cd gui && npm test`.
- **Before `/gsd:verify-work`:** Both full suites green AND `npm run tauri dev` manual checklist (D-10 + D-20) passes.
- **Max feedback latency:** < 30 seconds per task commit (daemon-warm Julia, vitest hot).

---

## Per-Task Verification Map

> Phase 63 has no v1.1-style numbered REQ-IDs (v1.2 GUI redesign is phase-listed). Maps by locked decision id (D-NN). Task IDs are placeholders pending the planner's task numbering.

| Task ID | Plan | Wave | Decision | Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|----------|----------|-----------|-------------------|-------------|--------|
| 63-A-01 | 63-A | 1 | D-13 | `rebin_intensive(ones(N), M) == ones(M)` (identity for uniform) | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ W0 — append testset | ⬜ pending |
| 63-A-02 | 63-A | 1 | D-15 | `rebin_intensive(x, n) ≈ rebin_extensive(x, n) * (n_out/n_in)` cross-check | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ W0 | ⬜ pending |
| 63-A-03 | 63-A | 1 | D-13 (2D) | `rebin_intensive(M, (a,b))` area-weighted-mean preserved | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ W0 | ⬜ pending |
| 63-A-04 | 63-A | 1 | D-14 | `rebin_intensive` exported from STREAM | smoke (Julia) | `bin/jl -e 'using STREAM; @assert isdefined(STREAM, :rebin_intensive)'` | ❌ W0 | ⬜ pending |
| 63-A-05 | 63-A | 1 | CD-02 | `cosine_T_wall_profile(n; amplitude, peaking_factor)` thin alias works | unit (Julia) | `bin/jl test/test_utilities.jl` | ❌ W0 | ⬜ pending |
| 63-B-01 | 63-B | 2 | D-23 | `setBCMode` mutation pushes snapshot + updates store | unit (vitest) | `npx vitest run store/useStore.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-02 | 63-B | 2 | D-23 | Setting `mode='source'` creates canvas edge | unit (vitest, store integration) | `npx vitest run store/useStore.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-03 | 63-B | 2 | D-23 | Deleting BC edge reverts `bcMode` (via `onEdgesChange` diff) | unit (vitest, store) | `npx vitest run store/useStore.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-04 | 63-B | 2 | D-06 | Value-mode codegen emits `[ch.T_wall_left[i] ~ <val> for i in 1:n]...` | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-05 | 63-B | 2 | D-07 | Profile-file codegen emits `rebin_intensive(readdlm(...), n)` | unit (vitest, snapshot) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-06 | 63-B | 2 | D-06 + CD-02 | Profile-cosine codegen emits `cosine_T_wall_profile(...)` helper call | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-07 | 63-B | 2 | D-08 | Function-mode codegen emits stub + binding equation | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-08 | 63-B | 2 | D-09 + CD-01 | Mark/unset codegen emits TODO comment + NO equation | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-B-09 | 63-B | 2 | D-05 | Symmetric=ON codegen emits both `T_wall_left` AND `T_wall_right` from single mode | unit (vitest) | `npx vitest run lib/codeGenerator.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-C-01 | 63-C | 3 | D-01 + D-02 | Tab strip renders only when `external_inputs.length > 0` | unit (vitest, RTL) | `npx vitest run sidebar/SidebarPanel.test.tsx` | ❌ W0 | ⬜ pending |
| 63-C-02 | 63-C | 3 | D-03 | Selection change resets active tab to Properties | unit (vitest, RTL) | `npx vitest run sidebar/SidebarPanel.test.tsx` | ❌ W0 | ⬜ pending |
| 63-C-03 | 63-C | 3 | D-04 | 5-pill picker renders + activates correct pill | unit (vitest, RTL) | `npx vitest run sidebar/BCModePicker.test.tsx` | ❌ W0 | ⬜ pending |
| 63-C-04 | 63-C | 3 | D-09 | Required-unset = no active pill + muted-destructive hint visible | unit (vitest, RTL) | `npx vitest run sidebar/BCModePicker.test.tsx` | ❌ W0 | ⬜ pending |
| 63-C-05 | 63-C | 3 | D-05 | Symmetric toggle ON → 1 picker; OFF → 2 stacked field blocks | unit (vitest, RTL) | `npx vitest run sidebar/BCsTabForm.test.tsx` | ❌ W0 | ⬜ pending |
| 63-C-06 | 63-C | 3 | D-20 | Source-mode dropdown shows `+ New WallTemperature` when no source blocks exist | unit (vitest, RTL) | `npx vitest run sidebar/BCsTabForm.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-01 | 63-D | 4 | D-21 | Type-mismatch (WT→CHF, HFS→Channel, *→CAC) hard-blocked via `isValidConnection` | unit (vitest) | `npx vitest run components/CanvasPanel.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-02 | 63-D | 4 | D-22 | n-mismatch creates edge AND flags both endpoints in `errorNodeIds` | unit (vitest, store) | `npx vitest run store/useStore.bc.test.ts` | ❌ W0 | ⬜ pending |
| 63-D-03 | 63-D | 4 | D-11 | BC edge mid-chip cycles `L+R → L → R → L+R` on click | unit (vitest, RTL) | `npx vitest run components/BCEdge.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-04 | 63-D | 4 | D-12 | BC edge renders dashed `var(--muted-foreground)` style | unit (vitest, snapshot) | `npx vitest run components/BCEdge.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-05 | 63-D | 4 | D-18 | BCPort handle = hollow square 1.5px stroke on WT/HFS nodes | unit (vitest, snapshot) | `npx vitest run components/StreamNode.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-06 | 63-D | 4 | D-19 | Source block label = two-line (name + mode-aware value) | unit (vitest, RTL) | `npx vitest run components/StreamNode.test.tsx` | ❌ W0 | ⬜ pending |
| 63-D-07 | 63-D | 4 | D-24 | Sources toolbox category lists WT + HFS as draggable | unit (vitest, RTL) | `npx vitest run components/ToolboxPanel.test.tsx` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/test_utilities.jl` — append INT-01..05 testsets for `rebin_intensive` + `cosine_T_wall_profile` (file exists from Phase 62; append-only).
- [ ] `gui/src/lib/bcMode.ts` — new shared types (`BCMode`, `BCModeEntry`) + `bcModeKey()` helper.
- [ ] `gui/src/store/useStore.bc.test.ts` — new vitest file (BC mode actions, edge create/delete sync, n-mismatch flagging).
- [ ] `gui/src/lib/codeGenerator.bc.test.ts` — new vitest file (5-mode emit + symmetric expansion snapshots).
- [ ] `gui/src/components/sidebar/BCModePicker.test.tsx` — new vitest file (5-pill picker + required-unset).
- [ ] `gui/src/components/sidebar/BCsTabForm.test.tsx` — new vitest file (symmetric toggle, source-mode dropdown).
- [ ] `gui/src/components/sidebar/SidebarPanel.test.tsx` — new vitest file (tab strip visibility + active-tab reset).
- [ ] `gui/src/components/BCEdge.test.tsx` — new vitest file (dashed style + click-to-cycle chip).
- [ ] `gui/src/components/CanvasPanel.test.tsx` — new vitest file (or extend if exists; `isValidConnection` hard-blocks).
- [ ] `gui/src/components/StreamNode.test.tsx` — new vitest file (BCPort handle + source label).
- [ ] `gui/src/components/ToolboxPanel.test.tsx` — new vitest file (Sources category entries).

---

## Manual-Only Verifications

| Behavior | Decision | Why Manual | Test Instructions |
|----------|----------|------------|-------------------|
| Whole-body drop target activates ONLY on BCPort drag | D-10 | ReactFlow drag-and-drop + `useConnection().fromHandle` state is not faithfully simulated by jsdom; the visual outline + chip transition is a smoke-only signal | `npm run tauri dev` → drag from `WallTemperature.T_wall_out` onto a `Channel` body → expect dashed outline + `Connect BC` chip → release → dashed BC edge created with `target_side = :both` |
| `+ New WallTemperature` inline button flow | D-20 | Tauri-hosted popover interaction + node spawn + auto-select sequence is integration-level (store + canvas + sidebar); vitest jsdom can simulate each piece but not the full flow | `npm run tauri dev` → empty canvas → drop a `Channel` → select it → BCs tab → `T_wall` field → Source mode → expect `+ New WallTemperature` button → click → expect new WT node ~120px left of Channel + auto-selected in dropdown + dashed edge auto-created |
| n-mismatch red-ring marker on both endpoints (visual rendering) | D-22 | The store flagging is unit-testable (63-D-02); the actual red-ring visual depends on the renderer pipeline and theme — covered by snapshot at unit level, but final visual confirmation is smoke-only | `npm run tauri dev` → WT with `n=10` → Channel with `n=12` → connect → expect red-ring on BOTH WT and Channel + red-text `n mismatch: WT.n=10, Channel.n=12` in BCs tab AND on source block |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify command OR are explicitly listed in Manual-Only above
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify (manual D-10/D-20 don't form a chain because they're at phase close)
- [ ] Wave 0 covers all MISSING test files
- [ ] No watch-mode flags in verify commands (use `vitest run`, not `vitest`)
- [ ] Feedback latency < 30s per task commit (daemon-warm)
- [ ] `nyquist_compliant: true` set in frontmatter after planner finalizes task IDs

**Approval:** pending (set by `/gsd:execute-phase` after planner finalizes task numbering)

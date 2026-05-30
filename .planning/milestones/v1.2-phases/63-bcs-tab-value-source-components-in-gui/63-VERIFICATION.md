---
phase: 63-bcs-tab-value-source-components-in-gui
verified: 2026-05-13T18:05:00Z
human_uat_resolved: 2026-05-21
status: complete
score: 7/8 must-haves verified (1 partial — bidirectional sync; human UAT closed 2026-05-21, see 63-HUMAN-UAT.md)
overrides_applied: 0
gaps:
  - truth: "Bidirectional sync between BCs-tab dropdown selection and canvas BC edge"
    status: partial
    reason: |
      The BCs-tab → canvas direction works: setBCMode({mode:"source",...}) creates
      a bcEdge in edges[]; clearBCMode strips it; _revertBCModeForEdge reverts
      bcMode on edge removal. The canvas-drag → BCs-tab direction is half-wired:
      addEdge (useStore.ts:1047-1062) materializes the bcEdge AND calls
      _checkBCNMismatch, but does NOT write the corresponding bcMode entry. As
      a result, a user who drags a WT→Channel BC connection on the canvas sees:
        (a) the dashed edge appears,
        (b) the BCs-tab Source-mode dropdown still shows required-unset (no pill
            highlighted),
        (c) the codegen emits a TODO comment with no binding equation — the
            canvas-visible wiring produces no Julia code.
      This contradicts the phase-goal sentence "Bidirectional sync between BCs
      tab dropdown selection and the canvas connection."
    artifacts:
      - path: "gui/src/store/useStore.ts"
        issue: |
          addEdge BCPort branch (lines 1047-1062) sets edges and runs
          _checkBCNMismatch but does NOT mutate bcMode. The symmetric inverse
          (_revertBCModeForEdge at 1322-1362) exists and is wired into
          onEdgesChange — so the edge-removal direction reverts bcMode, but the
          edge-creation direction (canvas-drag) does not create the bcMode
          entry. State-sync invariant from CONTEXT D-23 ("single source of
          truth") is half-implemented.
    missing:
      - "addEdge BCPort branch should construct {mode:'source', sourceNodeId: connection.source} and write it to bcMode[bcModeKey(connection.target, connection.targetHandle)] (and the sibling key if bcSymmetric is ON). See REVIEW CR-01 fix block for exact code."
      - "Regression test in CanvasPanel.bc.test.tsx asserting that after a canvas-drag addEdge call, useStore.getState().bcMode[bcModeKey(target, targetHandle)]?.mode === 'source' (currently only errorTagsByNodeId is asserted)."
  - truth: "setBCSymmetric(true) reconciles left↔right state cleanly across all transitions"
    status: partial
    reason: |
      Two reconciliation holes in setBCSymmetric (useStore.ts:1283-1303):
      (CR-02) When leftEntry is undefined and rightEntry is defined, the "left
      wins" rule does not drop rightEntry; right survives, contradicting the
      visible Symmetric toggle. (CR-03) When the mirrored entry is mode:"source"
      with a previously-different right-side source, the BC edge in edges[] is
      not re-synced, and _checkBCNMismatch is not re-run — canvas visuals and
      state diverge after the toggle.
    artifacts:
      - path: "gui/src/store/useStore.ts"
        issue: |
          setBCSymmetric (lines 1283-1303) handles only the leftEntry-defined-
          and-differs case; the undefined-left-with-defined-right case and the
          source-mode-edge-resync case are not implemented.
    missing:
      - "Branch on leftEntry === undefined && rightEntry !== undefined → delete rightKey (left wins, undefined included)."
      - "When the mirrored entry is mode:'source', refactor setBCMode's edge-materialization + _checkBCNMismatch out into a helper and call it from setBCSymmetric too. Otherwise toggling Symmetric ON across an asymmetric source pair leaves stale edges + missing n-checks."
      - "Tests for both transitions (currently useStore.bc.test.ts:301-324 only covers value-mode symmetric flip)."
deferred: []
human_verification:
  - test: "BCs tab manual smoke (D-10 whole-body drop overlay)"
    expected: "cd gui && npm run tauri dev → drop Channel, drag from WallTemperature.T_wall_out, expect dashed-outline overlay + 'Connect BC' chip on Channel body, release → dashed BC edge created with targetSide='both'."
    why_human: "useConnection() drag state is not faithfully reproducible in jsdom — listed as Manual-Only in 63-VALIDATION.md."
    result: pass
    resolved_in: 63-HUMAN-UAT.md Test 1
  - test: "+ New WallTemperature end-to-end (D-20)"
    expected: "Empty canvas → drop Channel (n=12) → select → BCs tab → click Source pill → empty Source-mode dropdown shows '+ New WallTemperature' button → click → new WT node appears ~120px left of Channel, auto-selected in dropdown, dashed BC edge auto-created. The new WT's parameters.n equals 12 (no bc-n-mismatch fires)."
    why_human: "Spatial layout + auto-select + visual confirmation; unit-tested at store level but visual flow needs eyes."
    result: resolved-by-design
    resolved_in: 63-HUMAN-UAT.md Test 2
    resolution: "Source pill + auto-create WT button intentionally not shipped per owner decision; superseded by the promote-to-shared-source flow shipped in Phase 63.1. D-20 spec is obsolete."
  - test: "Visual red-ring on n-mismatch (D-22)"
    expected: "WT(n=10) + Channel(n=12) → connect on canvas → both nodes paint with ring-destructive class visibly red (unit test verifies class application; this confirms CSS resolves to a visible ring)."
    why_human: "Visual rendering only — unit test covers the class attribute, not paint."
    result: pass
    resolved_in: 63-HUMAN-UAT.md Test 3
  - test: "Goal-level decision: do CR-01/CR-02/CR-03 block phase completion?"
    expected: "Owner decides whether the three state-sync gaps (canvas-drag-no-bcMode; symmetric-toggle-left-undefined; symmetric-toggle-source-mode-no-edge-resync) are blocking the v1.2 milestone or can be deferred to a polish/correctness phase. The phase goal specifically lists 'bidirectional sync' as an in-scope deliverable, and CR-01 partially breaks it; CR-02 and CR-03 are narrower transition-only correctness gaps. If deferred, file as a follow-up phase before milestone close."
    why_human: "Scope/severity judgment call — code clearly works for the dominant user paths (BCs-tab → canvas, BCs-tab edit, edge-removal-reverts-bcMode); the gaps only manifest on specific cross-path transitions."
    result: deferred-no-followup
    resolved_in: 63-HUMAN-UAT.md Test 4
    resolution: "Owner decision — all three deferred, none block v1.2. CR-01 not recognized as a real issue. CR-02 and CR-03 explicitly ignored. No follow-up phase needed."
---

# Phase 63: BCs Tab + Value-Source Components in GUI — Verification Report

**Phase Goal:** Split the property panel into Properties tab (constructor kwargs) and BCs tab (external-input variables). BCs tab supports five modes per field: scalar value, preset profile, imported profile, "mark in code for later," and "driven by source block." `WallTemperature` and `HeatFluxSource` toolbox entries (the value-source components from v1.1). Distinct dashed-edge BC connection style. Bidirectional sync between BCs tab dropdown selection and the canvas connection.

**Verified:** 2026-05-13T18:05:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Properties tab vs BCs tab split for components with external_inputs | VERIFIED | `gui/src/components/sidebar/SidebarPanel.tsx:47,51,152,371-395` — `<Tabs>` with `<TabsList>` containing `<TabsTrigger value="properties">` + `<TabsTrigger value="bcs">`; conditional on `hasBCs = (component.external_inputs?.length ?? 0) > 0`; remount-on-selection-id provides D-03 reset; covered by `SidebarPanel.test.tsx` (5 tests). |
| 2 | BCs tab supports five modes per field | VERIFIED | `gui/src/lib/bcMode.ts:5-12` discriminated `BCModeEntry` union (value/profile/function/mark/source); `gui/src/components/sidebar/BCModePicker.tsx:28-34` `BC_MODE_OPTIONS` array in D-04 order; `BCsTabForm.tsx` per-mode editor dispatch; 7 BCModePicker tests + 11 BCsTabForm tests cover render + dispatch. |
| 3 | Scalar value, preset profile, imported profile, mark, driven-by-source modes all emit correct Julia | VERIFIED | `gui/src/lib/codeGenerator.ts:711,1082-1131,1150,1156,1273` emits scalar binding / `cosine_T_wall_profile(...)` / `rebin_intensive(readdlm(...))` / `# TODO` / source-binding; 11 tests in `codeGenerator.bc.test.ts` cover all five modes + symmetric expansion + DelimitedFiles gating. |
| 4 | WallTemperature and HeatFluxSource toolbox entries are first-class draggables | VERIFIED | `gui/src/components/ToolboxPanel.tsx:15,27,74-83` `getComponentsByCategory("Sources")` map renders `<ToolboxItem>` for each; 4 ToolboxPanel tests verify rendering + draggability + DOM order; registry entries in `gui/src/registry/components.json` (Phase 61). |
| 5 | Distinct dashed-edge BC connection style | VERIFIED | `gui/src/components/BCEdge.tsx:54-56` `stroke: var(--muted-foreground)`, `strokeWidth: 1.5`, `strokeDasharray: "6 3"`, no markerEnd consumed; `gui/src/store/useStore.ts:628` enrichEdges sets `type: "bcEdge"`; 7 BCEdge tests cover style + chip + cycle action + no-marker invariant. |
| 6 | Bidirectional sync between BCs-tab dropdown selection and canvas BC edge | **PARTIAL** | BCs-tab → canvas direction WORKS (`setBCMode` materializes edge — useStore.ts:1166-1208); edge-removal → bcMode revert WORKS (`_revertBCModeForEdge` wired into `onEdgesChange`). Canvas-drag → BCs-tab direction BROKEN: `addEdge` (useStore.ts:1047-1062) creates the bcEdge but does NOT write the bcMode entry (REVIEW CR-01). Codegen then elides into TODO + no binding equation; BCs-tab picker shows required-unset even with visible canvas edge. |
| 7 | Julia helpers (`rebin_intensive`, `cosine_T_wall_profile`) shipped + exported for Profile-mode codegen | VERIFIED | `src/utilities.jl:213,272,316,368` — `_rebin_1d_intensive` private + `rebin_intensive` (1D + 2D) + `cosine_T_wall_profile`; `src/STREAM.jl:100` `export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile`; INT-01..05 + CT-01 testsets all green (11 testsets total). |
| 8 | BCPort handle visual idiom + source-block label + n-mismatch red-ring + drop overlay | VERIFIED | `gui/src/components/StreamNode.tsx:73-74,86-87,92,101,129,140,163,209,227` — hollow-square BCPort handle (borderRadius:0, transparent bg, 1.5px stroke); `sourceLabelLine` helper for two-line label (scalar/vector/fn/unset); `hasBCError` primitive selector drives `ring-destructive`; `useConnection()`-gated "Connect BC" drop overlay; 11+ new tests in StreamNode.test.tsx. |

**Score:** 7/8 truths verified; 1 partial (truth #6 — bidirectional sync).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/utilities.jl` | rebin_intensive (1D+2D) + cosine_T_wall_profile + _rebin_1d_intensive | VERIFIED | 4 function definitions present at expected lines; 4-section docstrings per CLAUDE.md convention; file grew 155→370 lines |
| `src/STREAM.jl` | Public export of rebin_intensive + cosine_T_wall_profile | VERIFIED | Single export line: `export rebin_extensive, rebin_intensive, cosine_power_shape, cosine_T_wall_profile` |
| `test/test_utilities.jl` | INT-01..05 + CT-01 testsets | VERIFIED | 6 new testsets, 24+ new assertions; `julia test/test_utilities.jl` exits 0 (per 63-A-SUMMARY) |
| `gui/src/lib/bcMode.ts` | BCModeEntry union + BCEdgeData + bcModeKey + isAllowedBCConnection + cycleBCEdgeTargetSide | VERIFIED | All 6 exports present; pure module (no react/zustand/xyflow imports verified) |
| `gui/src/store/useStore.ts` | bcMode + bcSymmetric + errorTagsByNodeId slices, 5 actions, enrichEdges branch, onEdgesChange revert, snapshot integration | VERIFIED | All slices in initial state at 735-737; actions defined at expected lines; enrichEdges BCPort branch sets `type: "bcEdge"` at 628; `_revertBCModeForEdge` wired into onEdgesChange; undo/redo/snapshot carry all three BC slices (798-867). **Note:** errorNodeIds (legacy Set<string>) preserved unchanged; new errorTagsByNodeId Record sibling added per 63-B SUMMARY deviation — accepted scope. |
| `gui/src/lib/codeGenerator.ts` | Per-channel BC emit logic — 5-mode switch + symmetric expansion + unset/Mark TODO | VERIFIED | bcsState 6th arg threaded through generateCode; bcEmitPlan builder at 1082-1131; profile-var emit at 1150 (cosine) / 1156 (file); DelimitedFiles gating at 718; symmetric expansion at 1099-1106; TODO emission at 1273 |
| `gui/src/components/sidebar/BCModePicker.tsx` | 5-pill picker with required-unset visual | VERIFIED | 5 options in D-04 order, required-unset hint "BC required — select a mode" at line 52 |
| `gui/src/components/sidebar/BCsTabForm.tsx` | Symmetric toggle + per-field BCModePicker + 5 per-mode editor branches + `+ New <SourceKind>` flow | VERIFIED | 480-line file with handleNewSource flow that seeds new source-block's n from consumer (proves D-20); stripSideSuffix helper for pair grouping; setBCMode/setBCSymmetric/addNode/updateNodeParams all imported and used |
| `gui/src/components/sidebar/SidebarPanel.tsx` | Tabs wrapper around component branch when external_inputs.length > 0 | VERIFIED | `hasBCs` conditional at 152; Tabs/TabsList/TabsTrigger/TabsContent inserted between header + content; key={selectedNodeId} discipline preserved for D-03 reset |
| `gui/src/components/sidebar/SegmentedButtonGroup.tsx` | Generic segmented-button primitive over T extends string | VERIFIED | Extracted from ModeToggle; consumed by ModeToggle (Pump), BCModePicker, Profile-preset + Function-signature sub-pickers in BCsTabForm |
| `gui/src/components/BCEdge.tsx` | Dashed style + EdgeLabelRenderer click-to-cycle chip | VERIFIED | All D-12 style values exact; chip label "L+R"/"L"/"R" derived from data.targetSide; onClick calls store cycleBCEdgeTargetSide action |
| `gui/src/components/StreamNode.tsx` | BCPort hollow-square + source-block label + errorTagsByNodeId red-ring + useConnection-gated drop overlay | VERIFIED | All four sub-features present; sourceLabelLine helper handles scalar/vector/fn/unset; useConnection drag-state gating uses getPortType from CanvasPanel; hasBCError selector returns primitive boolean (loop fix from 63-D deviation #1) |
| `gui/src/components/CanvasPanel.tsx` | edgeTypes.bcEdge registered + isValidConnection BCPort allow-list | VERIFIED | `bcEdge: BCEdge` at line 42; isAllowedBCConnection imported and called from isValidConnection at 157-166 |
| `gui/src/components/ToolboxPanel.tsx` | Sources category populated with WT + HFS draggables | VERIFIED | sourceComponents fetched at 15; rendered as ToolboxItem map at 74-83 |
| All 6 new test files | New unit-test coverage of every artifact | VERIFIED | useStore.bc.test.ts (20 tests) + codeGenerator.bc.test.ts (11) + BCModePicker.test.tsx (7) + BCsTabForm.test.tsx (11) + SidebarPanel.test.tsx (5) + BCEdge.test.tsx (7) + CanvasPanel.bc.test.tsx (10) + StreamNode.test.tsx extensions (+11) + ToolboxPanel.test.tsx extensions (+4) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| useStore.ts | lib/bcMode.ts | `import { bcModeKey, cycleBCEdgeTargetSide as cycleBCEdgeTargetSidePure, BCModeEntry, BCEdgeData }` | WIRED | useStore.ts:17-21 (note: isAllowedBCConnection intentionally NOT imported here — 63-B deviation #1, consumed by CanvasPanel instead) |
| codeGenerator.ts | useStore.ts (read snapshot) | `bcsState: { bcMode, bcSymmetric }` param threaded through generateCode | WIRED | Wiring confirmed in CodePreview.tsx + Toolbar.tsx (63-B deviation #3, accepted) |
| useStore enrichEdges | BCEdge.tsx | edge.type = "bcEdge" + edge.data initialized | WIRED | useStore.ts:628 assigns type "bcEdge" with BCEdgeData; CanvasPanel.tsx:42 registers edgeTypes.bcEdge → BCEdge component |
| CanvasPanel.isValidConnection | lib/bcMode.ts | `isAllowedBCConnection(srcCompId, tgtCompId)` | WIRED | CanvasPanel.tsx:25,166 |
| StreamNode | useStore (errorTagsByNodeId) | hasBCError primitive selector | WIRED | StreamNode.tsx:86-87 selector returns boolean; loop-safe |
| BCEdge | useStore (cycleBCEdgeTargetSide) | `useStore(state => state.cycleBCEdgeTargetSide)` | WIRED | BCEdge.tsx:46 |
| BCsTabForm | useStore (setBCMode/setBCSymmetric/addNode/updateNodeParams) | direct action calls | WIRED | BCsTabForm.tsx:160-163 |
| addEdge (canvas drag) | bcMode slice | **MISSING** — should write bcMode entry when source.type=BCPort | **NOT WIRED** | useStore.ts:1047-1062 sets edges + runs _checkBCNMismatch but does NOT write bcMode (CR-01) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|----------------------|--------|
| BCsTabForm BCModePicker active | `bcMode[bcModeKey(nodeId, name)]?.mode` | useStore selector | YES (when BCs-tab edits) | FLOWING |
| BCsTabForm BCModePicker active when canvas-drag created the edge | `bcMode[bcModeKey(nodeId, name)]?.mode` | useStore selector | NO — addEdge does not write bcMode | HOLLOW (CR-01) |
| BCEdge chip label | `data.targetSide` | enrichEdges initialization or store cycle action | YES | FLOWING |
| StreamNode red-ring | `errorTagsByNodeId[id]?.length > 0` | _checkBCNMismatch writes to slice; subscribed via selector | YES | FLOWING |
| StreamNode source-block label | `node.data.parameters[fieldName]` | per-node params, updated via updateNodeParams | YES | FLOWING |
| codegen Profile-cosine emit | `entry.amplitude`, `entry.peakingFactor` | bcsState.bcMode entries from store | YES (when bcMode written) | FLOWING for BCs-tab path; HOLLOW for canvas-drag path (since bcMode never written) |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full vitest suite passes | `cd gui && npx vitest run` | 525 passed, 9 todo, 0 failing across 38 test files | PASS |
| TypeScript clean (modified files only) | `cd gui && npx tsc --noEmit 2>&1 \| grep -E '(useStore\|codeGenerator\|bcMode\|BCEdge\|StreamNode\|CanvasPanel\|ToolboxPanel\|BCModePicker\|BCsTabForm\|SidebarPanel)\.tsx?'` | per 63-D SUMMARY — no new tsc errors introduced; pre-existing 7 errors elsewhere documented as Phase 71 work | PASS |
| Julia exports resolve | `using STREAM; isdefined(STREAM, :rebin_intensive) && isdefined(STREAM, :cosine_T_wall_profile)` | per 63-A SUMMARY — prints OK | PASS |
| Julia utilities testset green | `julia test/test_utilities.jl` | per 63-A SUMMARY — 11/11 testsets pass (CONS-01..04 + INT-01..05 + CT-01) | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` declared in PLAN/SUMMARY; phase is GUI + Julia helper, not migration/tooling. SKIPPED (no probes applicable).

### Requirements Coverage

Phase 63's `requirements:` frontmatter uses phase-internal decision IDs (D-01..D-24, CD-01..CD-05) defined in `63-CONTEXT.md`, NOT global IDs in `REQUIREMENTS.md`. `grep -n "Phase 63" .planning/REQUIREMENTS.md` returns no rows — REQUIREMENTS.md does not currently enumerate Phase 63's design decisions as global IDs (Phase 63 is a GUI phase whose contract lives in §3.10/§3.11 of MILESTONE-CONTEXT.md plus the phase's own CONTEXT.md). The IDs map as:

| Requirement (Phase-local D-ID) | Source | Description | Status | Evidence |
|------|--------|-------------|--------|----------|
| D-01 | A,B,C,D | Tab strip below header | VERIFIED | SidebarPanel.test.tsx D-01 test |
| D-02 | C | Tab visibility driven by external_inputs.length | VERIFIED | SidebarPanel.test.tsx D-02 test (positive + negative) |
| D-03 | C | Active tab resets on selection change | VERIFIED | SidebarPanel.test.tsx D-03 test (key={selectedNodeId} remount) |
| D-04 | B,C | 5-pill picker in [Value][Profile][Function][Mark][Source] order | VERIFIED | BCModePicker.test.tsx D-04 order test |
| D-05 | B,C | Symmetric-by-default toggle, expansion behavior | VERIFIED | BCsTabForm.test.tsx D-05 (symmetric ON/OFF render); useStore.bc.test.ts mirror-to-sibling test |
| D-06 | A,B,C | Profile mode v1 = axial cosine via cosine_T_wall_profile | VERIFIED | INT-01..05 + CT-01 + codeGenerator.bc.test.ts cosine emit case |
| D-07 | A,B | Profile-file import via rebin_intensive (caller-trust) | VERIFIED | INT-04, rebin_intensive emit case in codeGenerator.bc.test.ts, DelimitedFiles gating test |
| D-08 | B,C | Function-mode stub-and-edit | VERIFIED | codeGenerator.bc.test.ts fn(t) + fn(t,i) emit cases; BCsTabForm.test.tsx Function-mode editor test |
| D-09 | B,C | Required-unset = no active pill + muted-destructive hint + TODO emit | VERIFIED | BCModePicker.test.tsx required-unset render; codeGenerator.bc.test.ts unset-case TODO test |
| D-10 | D | Whole-component drop-zone overlay activated by useConnection() filter | VERIFIED (code) / HUMAN (visual) | StreamNode useConnection gating in code; visual activation listed Manual-Only per 63-VALIDATION |
| D-11 | B,D | Inline click-to-cycle target-side chip (L+R / L / R) | VERIFIED | BCEdge.test.tsx chip-label + click-cycles + cycleBCEdgeTargetSide store action |
| D-12 | D | Dashed BCPort edge style (var(--muted-foreground), 1.5, "6 3", no marker) | VERIFIED | BCEdge.test.tsx style assertions |
| D-13 | A | Public helper rebin_intensive | VERIFIED | INT-01..05 testsets |
| D-14 | A | Public export from STREAM.jl | VERIFIED | export-line grep |
| D-15 | A | Cross-check identity with rebin_extensive | VERIFIED | INT-05 testset |
| D-16 | A | Caller-trust posture (no validation in rebin_intensive) | VERIFIED | 4-section docstring with "Caller trust" section (acceptance criterion grep ≥3 passed) |
| D-17 | D | Source block uses standard StreamNode rectangle | VERIFIED | No special card chrome — StreamNode.tsx renders all components via same shell |
| D-18 | D | BCPort hollow-square handle (no fill, 1.5px stroke, var(--muted-foreground)) | VERIFIED | StreamNode.test.tsx BCPort handle render tests; borderRadius:0 + transparent bg |
| D-19 | D | Source-block two-line label (scalar / vector / fn / unset) | VERIFIED | StreamNode.test.tsx 6 source-label tests covering all four value-shapes |
| D-20 | C | `+ New <SourceKind>` inline button spawns + auto-selects + sets bcMode + seeds n from consumer | VERIFIED (unit) / HUMAN (E2E flow) | BCsTabForm.test.tsx n-seed-from-consumer test; full E2E flow listed Manual-Only |
| D-21 | B,D | Type-mismatch allow-list (WT→Channel, HFS→CHF; everything else blocked) | VERIFIED | CanvasPanel.bc.test.tsx 6 isAllowedBCConnection tests including CAC carve-out |
| D-22 | B,D | n-mismatch soft-warning red-ring via errorTagsByNodeId | VERIFIED | useStore.bc.test.ts canvas-drag-path n-mismatch test (the Blocker-2 gate) + CanvasPanel.bc.test.tsx store-path n-flag test |
| D-23 | B | Single source-of-truth bidirectional sync | **PARTIAL** | BCs-tab → canvas + edge-removal → bcMode-revert work; canvas-drag → bcMode write does NOT (CR-01); see truth #6 above |
| D-24 | D | Phase 62's empty Sources category populated with WT + HFS | VERIFIED | ToolboxPanel.test.tsx 4 Sources draggable tests |
| CD-01 | B | Exact unset/Mark TODO comment text | VERIFIED | codeGenerator emits `# TODO: set <comp>.<field>[i] here`; codeGenerator.bc.test.ts asserts |
| CD-02 | A,B | Cosine helper name = cosine_T_wall_profile | VERIFIED | symbol shipped + exported; 63-A SUMMARY notes thin-alias decision deferred to Phase 72 |
| CD-03 | D | useConnection() pure ReactFlow extensibility (no hand-rolled mouse listeners) | VERIFIED | StreamNode.tsx:92,129 uses useConnection() + getPortType filter |
| CD-04 | D | Smart-name-increment for source blocks | VERIFIED | reuses Phase 62 per-kind counter (addNode flow); no separate test added |
| CD-05 | B,C | Symmetric-toggle state persisted per-component-instance | VERIFIED (creation) / PARTIAL (transitions) | bcSymmetric is keyed by `${nodeId}::${baseField}`; CR-02/CR-03 cover transition-edge holes — see gap #2 |

**Coverage:** 26/29 design IDs verified; 1 partial (D-23 — bidirectional sync); 1 split (CD-05 — creation verified, two transition-edge holes flagged); manual smokes pending for D-10 / D-20 / D-22 visual.

### Anti-Patterns Found

Scanning files modified by Phase 63 for debt markers, stubs, placeholders, hardcoded empties.

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| codeGenerator.ts:1273 (and similar) | `# TODO: set <comp>.<field>[i] here` | Info | INTENTIONAL — this is the D-09 unset/Mark required-emit text per CD-01; not a code-debt TODO. Confirmed by codeGenerator.bc.test.ts coverage. |
| codeGenerator.ts:110-128 | `return "# TODO: set geometry dimensions"` | Info | Pre-existing Phase 62 codegen text for missing geometry; not a Phase 63 introduction. |
| StreamNode.tsx | `T_wall = (unset)` muted-destructive class | Info | INTENTIONAL — D-19 source-block unset-state label; confirmed by StreamNode.test.tsx unset-render test. |
| BCsTabForm.tsx, BCEdge.tsx | No TBD/FIXME/XXX | None | Clean. |
| useStore.ts BC slice | No TBD/FIXME/XXX | None | Clean. |
| bcMode.ts | No TBD/FIXME/XXX | None | Clean. |

No blocker-level debt markers found in any file modified by Phase 63. All `# TODO`-style strings in codegen output are intentional D-09/D-08 emit text (regulated by tests).

### Human Verification Required

See `human_verification:` frontmatter above. Four items:

1. **D-10 whole-body drop overlay** — manual `npm run tauri dev` confirmation (jsdom can't simulate live useConnection drag state).
2. **D-20 `+ New WallTemperature` E2E flow** — full canvas + sidebar + spawn flow.
3. **D-22 visual red-ring** — CSS paint confirmation (unit test only checks class attribute).
4. **Goal-level decision on CR-01/CR-02/CR-03** — owner decides whether the state-sync transition gaps block the v1.2 milestone or are accepted as known polish items for a follow-up phase.

### Gaps Summary

Two structured gaps surface from the REVIEW.md critical findings, both narrowly localized to state-sync invariants in `gui/src/store/useStore.ts`:

1. **Bidirectional sync — canvas-drag direction (CR-01)** — the goal sentence "Bidirectional sync between BCs tab dropdown selection and the canvas connection" is half-implemented. The BCs-tab → canvas direction is solid; edge-removal → bcMode-revert is solid. But canvas-drag → bcMode-write is missing, with a user-visible consequence: a canvas-drawn BC edge does not light up the BCs-tab picker AND does not emit a binding equation in the generated Julia. The dashed edge looks wired but the system produces no code.

2. **Symmetric-toggle reconciliation holes (CR-02, CR-03)** — `setBCSymmetric(true)` handles only the "leftEntry defined and differs from rightEntry" case. When leftEntry is undefined with rightEntry defined, right survives (CR-02). When the mirrored entry is mode:"source", the BC edge in `edges[]` is not re-synced to point from the left's source to the right handle (CR-03). Both are narrow transition-only cases — the dominant flows (set Symmetric ON at start, edit one side, both update) work fine.

Neither gap covers a deferred-by-design phase: Phase 71's "Validation framework" goal covers pluggable validation rules (z_N match, n-match enforcement, port-type, dangling-port, loop-closure, gravity-sum, geometry consistency, code-gen-gating). It does NOT cover BC state-sync invariants — those are Phase 63's contract. CR-01/CR-02/CR-03 are Phase 63 correctness gaps, not Phase 71 features.

The phase's primary deliverables (the five emit modes, dashed edge style, BCPort handle, tab strip wiring, toolbox source items, Julia helpers, codegen) are all shipped, tested, and working for the dominant user paths. 525 vitest tests + 11 Julia testsets pass. The gaps manifest only on cross-path transitions (canvas-drag for new BC; symmetric-toggle ON over an asymmetric prior state).

Per the verification rubric, this is `human_needed`: the artifacts and key links are in place, but a goal-level truth (#6 — bidirectional sync) is partial AND human verification is needed for the four manual smokes. The owner should decide whether to (a) defer CR-01/CR-02/CR-03 to a follow-up correctness phase and close Phase 63, or (b) re-plan a small `/gsd-plan-phase --gaps` cycle to land the three fixes (estimated <100 LOC in useStore.ts + 3-4 new tests in useStore.bc.test.ts and CanvasPanel.bc.test.tsx).

---

_Verified: 2026-05-13T18:05:00Z_
_Verifier: Claude (gsd-verifier)_

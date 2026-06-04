---
status: resolved
resolved: 2026-05-21
resolved_in: "Phase 63.1 Plan 11 (D-10 type_union + input_modes contract) + registry rework — all three root causes addressed: (RC-1) gui/src/components/sidebar/ParameterForm.tsx now has a type_union branch (lines 28-31, 269-281); (RC-2) gui/src/registry/components.json Channel + ChannelHeatFlux entries now declare BCPort target handles (Channel.T_wall_left line 13, CHF.q_left line 573, type:'BCPort' / array_size:'n' / side:'bottom'); (RC-3) falls out of RC-1 — once T_wall/q is editable in Properties, the destructive sourceLabelLine 'unset' state is reachable and resolves to a normal value display."
trigger: "Phase 63.1 UAT test 5 surfaced four blockers/majors on WallTemperature + HeatFluxSource source nodes after Promote-to-shared-source flow"
created: 2026-05-14T00:00:00Z
updated: 2026-05-21
---

## Current Focus

hypothesis: All four gaps share roots in `gui/src/components/sidebar/ParameterForm.tsx` (type_union not rendered), the WT/HFS registry entries' lack of a BCPort *target* on consumer Channel/ChannelHeatFlux (no drop site for the source's BCPort handle), and the resulting cascade where WT/HFS `T_wall`/`q` parameters are unreachable and render as "(unset)" in the source-block label on the canvas.
test: read ParameterForm, StreamNode BCPort + sourceLabel, BCsTabForm, useStore.setBCMode/promoteToSharedSource, lib/bcMode.ts (validation allow-list).
expecting: A→C→D root causes are each a one-line fix; B requires either adding a BCPort target handle to Channel/ChannelHeatFlux OR turning the existing whole-body `dropActive` overlay into a real drop target.
next_action: return ROOT CAUSE FOUND structured block to caller — diagnosis-only mode.

## Symptoms

expected: WT/HFS show full Properties (T_wall/q plus n); BCPort drag-connect to Channel/CHF creates dashed bcEdge; no spurious "T_wall unset" alert when bound via Promote; HFS behaves identically.
actual: WT Properties show only `n`; dragging from WT's BCPort handle "doesn't drop on anything"; a destructive-red "T_wall = (unset)" label persists on the WT node body; HFS exhibits the same defects.
errors: "BC required — select a mode" (BCsTabForm.tsx:414) and "T_wall = (unset)" / "q = (unset)" (StreamNode.tsx:58) — both destructive-styled.
reproduction: UAT test 5; Symmetric ON, T_wall row mode=unset, click "↗ Promote to shared source", inspect spawned WT.
started: present immediately after Phase 63.1 Plan 08 + Plan 09 landed (source-component family became canvas-visible via Promote).

## Eliminated

- hypothesis: ParameterForm filters by category (Sources category dropped)
  evidence: ParameterForm has no category check; it only branches on param.type. Other Sources-category fields would have rendered if they had param.type. Disproved by reading lines 36-44.
  timestamp: 2026-05-14

- hypothesis: WT registry entry parameters[] is empty / n is injected elsewhere
  evidence: components.json lines 1023-1040 explicitly declare both `n` (type: "Int") and `T_wall` (type_union: ["Real","Vector","Function"]). HFS lines 1057-1074 mirror this with `q`. Both parameter arrays are populated in the registry. Only `n` happens to use the `type` field; `T_wall`/`q` use `type_union`.
  timestamp: 2026-05-14

- hypothesis: Gap C is bc-n-mismatch ring on the Channel
  evidence: `promoteToSharedSource` (useStore.ts:1365-1369) seeds the new WT's `n` from the consumer's `n` BEFORE setBCMode runs, so selectNodeErrors (nodeErrors.ts:55-95) cannot find a mismatch at Promote time. The "alert" the user describes must therefore be a different surface.
  timestamp: 2026-05-14

- hypothesis: Gap C "BC required — select a mode" fires on Channel because Promote only seeds primary side
  evidence: useStore.setBCMode (lines 1239-1287) reads `bcSymmetric[symKey] ?? true` defaulting to symmetric, then writes BOTH `${nodeId}::T_wall_left` AND `${nodeId}::T_wall_right` keys (lines 1252-1258). BCsTabForm reads `bcMode[bcModeKey(nodeId, group.primary.name)]` where primary.name === "T_wall_left" — that key IS set after Promote. Alert cannot fire on Channel post-Promote.
  timestamp: 2026-05-14

## Evidence

- timestamp: 2026-05-14
  checked: registry/components.json WT entry (lines 1016-1048)
  found: parameters[] declares `n` with `type: "Int"` AND `T_wall` with `type_union: ["Real","Vector","Function"]` (no `type` field). HFS lines 1050-1082 mirror this with `q`.
  implication: WT's `T_wall` and HFS's `q` are registry-correct but use the `type_union` polymorphic shape rather than a single `type`.

- timestamp: 2026-05-14
  checked: components/sidebar/ParameterForm.tsx (full file)
  found: ParameterForm groups visible params by `param.type` into scalarParams/geometryParams/functionParams/matrixParams (lines 36-44). renderField switches on `param.type` (line 46). There is NO branch for `param.type_union`. Any parameter declared with `type_union` and no `type` is silently dropped from all four groups → no section is rendered for it.
  implication: ROOT CAUSE of Gap A and the WT/HFS half of Gap D. WT shows only `n` because `n` has `type: "Int"` and falls into scalarParams; `T_wall` has only `type_union` so it's filtered out at lines 36-37. Same for HFS's `q`. Note: Channel's `h_left`/`h_right` (registry lines 39-57) ALSO use `type_union` — they have the same bug, but the user did not flag them in this UAT (they may not have inspected the Channel's Properties tab for h_left/h_right; the symptom is silent — fields simply don't appear).

- timestamp: 2026-05-14
  checked: registry/components.json Channel + ChannelHeatFlux ports (lines 10-13, 569-572)
  found: Channel declares `port_in` and `port_out` (both FlowPort). ChannelHeatFlux declares the same. NEITHER declares any BCPort in `ports[]`. external_inputs[] declares T_wall_left/right (Channel) and q_left/right (CHF) but external_inputs are GUI-tab metadata, not canvas handles.
  implication: ROOT CAUSE of Gap B and the drag-connect half of Gap D. ReactFlow's drag-to-connect requires a `<Handle>` element on the target node for the connection to complete. WT's `T_wall_out` BCPort is a `type="source"` handle (StreamNode.tsx:306) but Channel has no matching `type="target"` BCPort handle. The user-visible drag visually completes on the canvas overlay but ReactFlow has nothing to bind to.

- timestamp: 2026-05-14
  checked: components/StreamNode.tsx lines 219-262 (whole-body BC drop overlay)
  found: When a BCPort drag is in progress, the consumer node body renders a dashed-outline overlay with a "Connect BC" label (lines 253-262). Critically the overlay div has `pointer-events-none` (line 255), meaning it is a visual hint only — it cannot receive ReactFlow drop events. Only a `<Handle>` can.
  implication: Confirms Gap B mechanism. The overlay exists to suggest where to drop, but no actual drop target exists on Channel/CHF. The Promote button works because it bypasses ReactFlow entirely and calls `addEdge` via store action.

- timestamp: 2026-05-14
  checked: components/StreamNode.tsx lines 50-77, 230-241, 268-275 (source-block label)
  found: For WT (componentId in SOURCE_LABEL_FIELD), the node body renders a second line. `sourceLabelLine(parameters, "T_wall", unit)` returns `{ text: "T_wall = (unset)", muted: true }` when `parameters.T_wall` is undefined/null/"". The rendered <div> is colored `text-destructive/80` when `muted: true` (line 270). HFS gets the same treatment via SOURCE_LABEL_FIELD["HeatFluxSource"] = "q".
  implication: ROOT CAUSE of Gap C (and the visible-alert half of Gap D). The "T_wall is unset" alert the user reports is THIS destructive-red label rendered on the WT node body in the canvas — not the BCsTabForm "BC required" hint, and not a Channel-side check. The label is permanently red because Gap A blocks the user from ever setting `T_wall`. Same for HFS's `q`. UAT truth statement #3 paraphrased "They also alert..." as a Channel-side problem, but the user's literal "They" refers to the WT/HFS nodes themselves; the label rides on the WT/HFS body, not the Channel.

- timestamp: 2026-05-14
  checked: store/useStore.ts promoteToSharedSource (lines 1335-1379)
  found: After spawning WT, only `n` is seeded via updateNodeParams (lines 1367-1369). `T_wall` is left undefined. setBCMode then materializes the bcEdge and seeds both sibling bcMode keys symmetrically (lines 1242-1258).
  implication: Promote correctly handles the BC-side wiring (no spurious "BC required" alert on Channel possible) but leaves WT's value parameter unset, feeding the source-block label's destructive state. Promote could optionally seed a `T_wall` default but the broader fix is to repair Gap A so the user can edit it.

- timestamp: 2026-05-14
  checked: HFS registry entry (lines 1050-1082) vs WT entry (lines 1016-1048)
  found: Structurally identical — same single BCPort source-handle (`q_out` vs `T_wall_out`), same `parameters[]` shape (`n` Int + value with type_union), no `external_inputs`, identical constructorModes.
  implication: ROOT CAUSE of Gap D. HFS shares every defect with WT — A and C from the type_union/value-label cascade, B from CHF lacking a BCPort target handle. No HFS-specific bug.

## Resolution

root_cause: |
  Three distinct root causes, each with a downstream cascade that explains all four gaps:

  (RC-1) ParameterForm has no `type_union` branch — only renders parameters with a `param.type` set.
         → Gap A (WT/HFS Properties show only `n`)
         → Gap D-A (HFS shares the same defect)
         (Also silently affects Channel's `h_left`/`h_right` — same shape, not flagged in this UAT.)

  (RC-2) Channel and ChannelHeatFlux declare no BCPort in `ports[]`. External_inputs[] is GUI-tab metadata, not a ReactFlow handle. WT's `T_wall_out` BCPort source-handle therefore has no target to drop on. The whole-body "Connect BC" overlay on consumer nodes is `pointer-events-none` decoration.
         → Gap B (WT BCPort drag doesn't work)
         → Gap D-B (HFS BCPort drag doesn't work — CHF has the same gap)

  (RC-3) Source-block label `T_wall = (unset)` / `q = (unset)` renders in destructive red when the WT/HFS value parameter is undefined. promoteToSharedSource seeds only `n`. Combined with RC-1 (user cannot reach the field in Properties), the destructive label is permanent.
         → Gap C (the "T_wall unset alert" — the destructive-red source-block label on the WT body)
         → Gap D-C (same label on HFS for `q`)

fix:
  - "RC-1: Add a `type_union` branch to ParameterForm.tsx — when `param.type_union` is set, render an `input_modes` mode picker plus a mode-specific editor (NumericField for scalar, vector-input for vector, FunctionSelect or signature picker for callable). This is the broader v1.1 work that Phase 63 deferred; it must now ship with the value-source fix. Channel's h_left/h_right benefits for free."
  - "RC-2: Choose ONE: (a) add a BCPort `{type: 'target', side: 'left'}` handle pair to Channel and ChannelHeatFlux registry entries (e.g. `T_wall_left_bc` / `T_wall_right_bc` ports with type 'BCPort'), and render the matching target Handle in StreamNode (a `type=\"target\"` branch in the bcPorts.map at lines 302-317); OR (b) lift the `pointer-events-none` from the whole-body overlay and intercept the drop on the body, then issue `addEdge` against the external_input name via store action. Option (a) keeps the UI model consistent (handle-to-handle); option (b) keeps the registry shape clean but adds a non-standard ReactFlow drop pathway."
  - "RC-3: Falls out of the RC-1 fix (user can set T_wall/q via Properties, so the label de-muteizes). Optionally seed a placeholder default in `promoteToSharedSource` so a freshly spawned WT/HFS does not show 'unset' until the user types — but de-coupling label state from required-but-unset-on-purpose is a separate decision."

verification: deferred — diagnosis-only mode (plan-phase --gaps will own the actual fix + verification).

files_changed: []

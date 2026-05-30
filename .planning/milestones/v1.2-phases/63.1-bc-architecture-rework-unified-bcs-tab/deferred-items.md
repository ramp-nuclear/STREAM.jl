# Phase 63.1 — Deferred items (out-of-scope discoveries during execution)

Items logged here were discovered during plan execution but are **outside the
scope of the current task**. They must be addressed by a follow-up plan or
explicitly accepted as deferred.

---

## From Plan 10 (Wave 6 — bug fixes)

### Pre-existing failures (not caused by Plan 10)

1. **`SidebarPanel.anchors.test.tsx > "Channel BCs tab body still renders the existing BCsTabForm content below Anchors"`**
   - Failure mode: `Unable to find an element with the text: Symmetric (L = R)`.
   - Verified pre-existing via `git stash && npx vitest run … && git stash pop`
     — the test was already RED on the base commit (Plan 08 merge).
   - Likely cause: a Plan 06 / Plan 07 rendering change to BCsTabForm removed
     or relabeled the "Symmetric (L = R)" Switch label without updating this
     legacy test. Out of scope for Plan 10 (useStore-only).
   - Resolution: a follow-up sweep should either update the test to match the
     new label or restore the label in BCsTabForm.

### Pre-existing tsc errors (not caused by Plan 10)

1. `src/components/sidebar/__tests__/SidebarRouter.test.tsx(101,17)` —
   `'peaking' does not exist in type` (PowerShape preset shape drifted).
2. `src/components/sidebar/__tests__/SidebarRouter.test.tsx(144,17)` — same.
3. `src/lib/validation.test.ts(6,8) / (7,8) / (8,8)` — unused imports
   `TopologyResult`, `NodeError`, `SystemError`.
4. `src/components/sidebar/__tests__/BCsTabForm.test.tsx` — `Record<string, unknown>` not assignable to `StreamNodeData` (multiple occurrences).

Verified pre-existing — same set appears with `git stash` applied. Out of scope
for Plan 10. Resolution: a tsc cleanup sweep at the end of Phase 63.1.

---

## From Plan 11 (Wave 6 — RC-1 type_union renderer)

### Out-of-scope discoveries during human-verify smoke

1. **[CLOSED by Plan 63.1-14] WT.T_wall / HFS.q Properties do not mirror BCsTabForm mode options.**
   - Observed: Channel BCs tab on `T_wall_left` exposes `value | profile |
     function | mark | source`. WT.T_wall in Properties now exposes only Value
     (scalar input, per the scalar-only refactor in `5125f89`).
   - User feedback (2026-05-14): "you can promote anything to WT, so [the
     options] should be the same" — minus `mark`/`source` which don't apply on
     the source itself. Same applies to HFS.q vs CHF.q_left BC mode picker.
   - Scope: requires extending `nodeData.parameters[T_wall|q]` from `number`
     to a `BCModeEntry`-like discriminated union (value/profile/function),
     reusing `BCsTabForm`'s `ProfileModeEditor` + `FunctionModeEditor` in
     `ParameterForm.tsx`, and updating codegen + `StreamNode.sourceLabelLine`
     to render the discriminated union.
   - Resolution: **Plan 63.1-14** shipped — SourceValueEntry discriminated
     union, TypeUnionField mode dropdown (3 options), modeEditors.tsx extract,
     codegen sourceEmitPlan, sourceLabelLine dispatch, promoteToSharedSource
     seed updated. GAP-RC-4 CLOSED.
   - Memory: see `feedback_wt_hfs_properties_match_bc_modes.md`.

2. **Channel BCs tab visual layout fit issues.**
   - Observed during smoke: "Some stuff doesn't fit properly" in the Channel
     BCs tab layout. Not a behavior regression — purely visual fit /
     responsiveness.
   - Scope: GUI design phase (Phase 65 or later v1.2 cosmetics phase).
   - Resolution: deferred to design phase per user (2026-05-14). No plan
     allocated in Phase 63.1.

3. **Promoted WT/HFS spawns with value param unset.**
   - Observed: clicking "Promote to shared source" on Channel.T_wall_left
     spawns a WallTemperature node with `n` seeded but `T_wall` undefined —
     canvas label reads destructive-red `T_wall = (unset)`.
   - This is the existing `GAP-RC-3` already targeted by Plan 13 frontmatter
     `requirements: [..., GAP-RC-3]`. NOT a new gap — already in the queue.
   - Resolution: Plan 13 executes the value-param seed in
     `promoteToSharedSource`. Memory: `feedback_promote_carry_relevant_params.md`.

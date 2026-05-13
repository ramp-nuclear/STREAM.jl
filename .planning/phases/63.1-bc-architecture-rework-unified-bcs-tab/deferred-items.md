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

---
phase: 66-code-preview-rework
plan: 1
subsystem: gui/codegen + gui/code-preview
tags: [tdd, red, vitest, codegen, codepreview]
requires: []
provides:
  - "RED test surface for structured CodeSection[] codegen contract"
  - "RED test surface for serializeSections D-12 formatting floor"
  - "RED test surface for CodePreview sub-block rendering / hover / click / show-code-for / text-selection"
affects: []
tech-stack:
  added: []
  patterns:
    - "Phase 66 Pattern 10 (vitest test surface)"
    - "happy-dom @vitest-environment for React component tests"
key-files:
  created:
    - "gui/src/lib/__tests__/codeGenerator.sections.test.ts"
    - "gui/src/lib/__tests__/codeGenerator.serialize.test.ts"
    - "gui/src/components/__tests__/CodePreview.test.tsx"
    - "gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx"
    - "gui/src/components/__tests__/CodePreview.textSelection.test.tsx"
  modified: []
decisions:
  - "Test files copy fixture conventions from codeGenerator.smoke.test.ts and codeGenerator.resources.test.ts rather than importing private helpers from sibling test files (planner discretion noted in Task 1)."
  - "Used `as unknown as CodeSection[]` to make the typed cast explicit during the RED phase (avoids TS2352 narrowing errors before Plan 02 changes the return type)."
metrics:
  duration: ~50 minutes
  completed: 2026-05-15T19:52Z
  task_count: 3
  file_count: 5
---

# Phase 66 Plan 01: RED tests for structured codegen Summary

Five RED vitest files that lock the Phase 66 contract before any production
code refactor. All 31 new it blocks fail at runtime with deterministic
expectation failures; Plan 02 (codegen refactor) turns the codegen tests
green; Plan 04 (CodePreview rewrite) turns the component tests green.

## What was built

| File | Contract | D-IDs locked | it blocks | RED failure category |
|------|----------|--------------|-----------|----------------------|
| `gui/src/lib/__tests__/codeGenerator.sections.test.ts` | Structured `CodeSection[]` return + per-sub-block `sourceIds` | D-01, D-02, D-03, D-04 | 10 | Runtime: `TypeError: sections.find is not a function` (codegen still returns string) |
| `gui/src/lib/__tests__/codeGenerator.serialize.test.ts` | `serializeSections()` adapter + D-12 formatting floor | D-12 (+ Pitfall 3) | 10 | Runtime: `TypeError: serializeSections is not a function` (export does not exist yet) |
| `gui/src/components/__tests__/CodePreview.test.tsx` | Sub-block render + hover/click write to `hoveredSourceIds`/`pinnedSourceIds` | D-04, D-09, D-10 | 7 it + 1 todo | Runtime: `expected 0 to be greater than 0` (no [data-sub-block] elements) |
| `gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx` | `stream:show-code-for` listener: open panel, scroll, flash | D-07, D-08 | 3 | Runtime: `scrollIntoView` never called; `[data-flash]` never set |
| `gui/src/components/__tests__/CodePreview.textSelection.test.tsx` | D-14 regression: no `select-none` on sub-block wrappers | D-14 | 1 | Runtime: `expected 0 to be greater than 0` (no [data-sub-block] elements exist yet) |
| **Total** | | | **31 + 1 todo** | All runtime failures (zero test-code typos) |

## How it was built

- Copied the fixture-building style from
  `gui/src/lib/__tests__/codeGenerator.resources.test.ts` and
  `gui/src/lib/__tests__/codeGenerator.smoke.test.ts` (minimal
  `ComponentDefinition` objects + `makeNode` helper). Each new file is
  self-contained; no cross-test-file imports.
- For component tests, copied the `useStore.setState(...)` seeding pattern
  from `gui/src/components/__tests__/AppShell.test.tsx` and
  `gui/src/components/__tests__/StreamNode.anchor.test.tsx`. Marked
  component files with `@vitest-environment happy-dom` (vitest default is
  `node` for this repo).
- The type imports `CodeSection`, `CodeSubBlock`, `CodeSectionName`,
  `CodeSubBlockKind`, and the named export `serializeSections` from
  `../codeGenerator` do not yet exist. tsc reports TS2305 missing-member
  errors; the runtime test failures are the more visible RED signal.
- For `Element.prototype.scrollIntoView`, used `vi.spyOn(...).mockImplementation(() => {})`
  per Pattern 3 — jsdom/happy-dom does NOT implement smooth-scroll natively;
  the spy lets Plan 04 assert against the expected `{behavior, block}` args.

## Tests added

5 new vitest files; 31 new it blocks + 1 todo. Existing test suite at the
start of this plan reported `36 failed | 765 passed | 10 todo (811)` —
`31` of those `36` failures originate in the 5 new files; the remaining
`5` failures (4 in `contextMenus.test.tsx`, 1 in
`SidebarPanel.anchors.test.tsx`) pre-date this plan (verified by running
the same files on the pre-commit HEAD via `git stash` cycle).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Worktree did not have `gui/node_modules`**
- **Found during:** Task 1 verification (vitest run)
- **Issue:** The worktree spawned by Claude Code's `isolation="worktree"`
  was created bare (no `node_modules` symlink). `npx vitest` could not
  resolve dependencies.
- **Fix:** Symlinked `gui/node_modules` -> `/home/itay/projects/Julia-STREAM/gui/node_modules`.
  The symlink is gitignored (`gui/node_modules` is covered by the root
  `.gitignore` `node_modules/` pattern) and is local-only — does not
  affect any committed artifact.
- **Files modified:** none committed; symlink lives only in the worktree
  filesystem.
- **Commit:** N/A (no committed change)

**2. [Rule 3 - Blocking issue] First-pass Task 1 file landed in main repo, not the worktree**
- **Found during:** Task 1 commit step
- **Issue:** The absolute path `/home/itay/projects/Julia-STREAM/gui/...`
  resolved to the MAIN repo, not the worktree root (the worktree is at
  `.claude/worktrees/agent-<id>/`). `git add` from inside the worktree
  could not find the file because it was written outside the worktree.
  This is exactly the failure mode the per-commit absolute-path safety
  guard exists to prevent (worktree-path-safety reference #3099).
- **Fix:** `mv`'d the test file into the worktree path
  (`/home/itay/projects/Julia-STREAM/.claude/worktrees/agent-a7dbe29bb5112eda6/gui/...`),
  then committed normally. All subsequent files used the worktree-rooted
  absolute path from the start.
- **Files modified:** `gui/src/lib/__tests__/codeGenerator.sections.test.ts`
  (relocated; not a code change)
- **Commit:** `b6e34ea` — Task 1 commit landed cleanly after the move.

Both deviations are tooling/path concerns, not contract changes. The five
test files faithfully encode the Plan 01 acceptance criteria as written.

## Authentication gates

None.

## Known Stubs

None.

## Self-Check

### Files created (verified to exist):

- `gui/src/lib/__tests__/codeGenerator.sections.test.ts` — FOUND
- `gui/src/lib/__tests__/codeGenerator.serialize.test.ts` — FOUND
- `gui/src/components/__tests__/CodePreview.test.tsx` — FOUND
- `gui/src/components/__tests__/CodePreview.showCodeFor.test.tsx` — FOUND
- `gui/src/components/__tests__/CodePreview.textSelection.test.tsx` — FOUND

### Commits (verified in git log):

- `b6e34ea` — `test(66-01): add RED codeGenerator.sections.test.ts ...` — FOUND
- `78b5452` — `test(66-01): add RED codeGenerator.serialize.test.ts ...` — FOUND
- `b8afff1` — `test(66-01): add RED CodePreview component tests ...` — FOUND

### Vitest verification:

```
Test Files  7 failed | 65 passed (72)
      Tests  36 failed | 765 passed | 10 todo (811)
```

- 31 of 36 failures live in the 5 new Phase 66 test files (RED, as intended)
- 5 pre-existing failures (contextMenus + SidebarPanel.anchors) verified
  unchanged via pre-commit re-run

## Self-Check: PASSED

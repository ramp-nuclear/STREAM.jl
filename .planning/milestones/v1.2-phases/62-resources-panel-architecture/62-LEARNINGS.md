---
phase: 62
phase_name: "resources-panel-architecture"
project: "STREAM.jl"
generated: "2026-05-13T15:50:00Z"
counts:
  decisions: 9
  lessons: 10
  patterns: 10
  surprises: 8
missing_artifacts: []
---

# Phase 62 Learnings: resources-panel-architecture

## Decisions

### Pattern F — tabbed left panel
The left panel becomes a three-tab strip `[Components][Resources][Project]` instead of a hard sidebar mode switch. Components is default. Resources tab is a small tree (Geometries / Power Shapes / Fluids placeholder) with inline rename + context menu. Project tab is the Model Options form.

**Rationale:** Keeps existing layout muscle memory (left panel keeps its width and home) while giving Resources and Model Options first-class real-estate. Single tab strip beats multiple modal panels.
**Source:** 62-CONTEXT.md

### UUID foreign-key references for Geometry / Power Shape
Components on the canvas stop carrying inline `geometry: {type: "circular", ...}` objects and instead store `parameters.geometry = "<uuid>"` pointing into the resources store.

**Rationale:** Enables sharing a geometry / power shape across multiple components; clean separation between component graph and resource library; rebin_extensive enables file-loaded Power Shapes to "just work" across mismatched discretizations.
**Source:** 62-CONTEXT.md, 62-08-SUMMARY.md

### `.scp` save format with `format_version: 2.0` — hard cutover
New project file format `.scp` replaces the prior `.streamgui` extension entirely. No migration shim. Stale `.streamgui` opens trigger a clean error dialog.

**Rationale:** UUID resource layer requires a new schema; the migration cost vs adoption cost was judged not worth carrying. Hard cutover keeps the codepath simple.
**Source:** 62-CONTEXT.md, 62-04-SUMMARY.md

### Sentinel `(leave unset — set in code)` for power-shape unset
Power Shape pickers carry an explicit sentinel SelectItem (value = `SENTINEL_UNSET_POWER_SHAPE` constant) that represents the "user intentionally left this blank — codegen will leave it for manual code completion" state. Geometry pickers do NOT have this sentinel; geometry has no "set in code" pattern.

**Rationale:** Power Shape is sometimes legitimately blank at compose time but filled in user code; geometry always has a definite value. Sentinel value + visual italic muted treatment communicates "this means something specific" vs null.
**Source:** 62-CONTEXT.md D-26, 62-15-COPY-AUDIT.md (rows #1 / #4 supersession)

### Esc cascade — explicit ordering by layer
Esc precedence: (1) popover internals (ResourceCreationPopover stops propagation); (2) inline-rename Input; (3) Radix ContextMenu internals; (4) document-level listener in SidebarPanel that clears selection if `selectionKind !== "none"`.

**Rationale:** Layered Esc avoids the cascade-into-noop bug where one Esc closes nothing visible because each layer wasn't sure who owned it. Each layer's responsibility is documented inline.
**Source:** SidebarPanel.tsx header comment

### Engineering-tool voice for user-facing copy — test-pinned
Every Phase 62 user-facing string was rewritten to terse declarative voice (`Save failed.` not `Couldn't save project.`; `Used by N component(s).` not `It is used by N component(s).`). Each NEW string is asserted by ≥1 vitest case.

**Rationale:** Without test pinning an LLM-driven re-flow tomorrow can silently revert wording. User explicitly called out the AI-ish tone as a blocker in the original verification.
**Source:** 62-15-PLAN.md, 62-15-COPY-AUDIT.md

### `computeSaveAsDefaultFilename` — pure helper, module-level export
Save As `defaultPath` is computed by a pure helper that handles whitespace trim, OS-illegal-char sanitization, double-extension prevention, and empty-name fallback. Exported from useStore.ts for vitest.

**Rationale:** Separating the derivation from the I/O makes the rule testable without mocking Tauri dialogs.
**Source:** 62-14-PLAN.md, 62-14-SUMMARY.md

### Icon tabs — drop shadcn TabsTrigger, render custom buttons (UAT-driven)
After five iterations of TabsTrigger className overrides (border, ring, bg, !-important + dark: prefix, text-primary) failed to visually affect the active state, switched to plain `<button role="tab" aria-selected aria-label>` elements with state driven by the parent `<Tabs value>` prop. Parent Tabs + TabsContent still drive content swap; only the visible trigger is custom.

**Rationale:** Shadcn's base TabsTrigger has its own active-state cascade (`data-[state=active]:text-foreground`, dark-mode variants, after-pseudo bottom-bar) that an override className could not reliably win. Custom buttons own the cascade end-to-end.
**Source:** 62-UAT.md (Test 6 + post-UAT iteration), commit `5c8db33`

### Dual-tier executor model — opus for plans, sonnet for verifier
GSD executor agents run on `claude-opus-4-7`; verifier agents run on `claude-sonnet-4-6`. Set in `.planning/config.json`.

**Rationale:** Plan execution benefits from opus's instruction-following depth; verification is largely structural checking and runs faster on sonnet.
**Source:** .planning/config.json

---

## Lessons

### SHADCN ScrollArea viewport defaults to display:table
Radix's ScrollAreaPrimitive.Viewport wraps children in a `display: table` inner element. Children inside the table size to `max-content` (intrinsic width), defeating any `min-w-0` you set on outer containers. Every Properties form field stayed full intrinsic width regardless of panel resize. Fix: add `[&>div]:!block` to the Viewport className in `gui/src/components/ui/scroll-area.tsx`.

**Context:** UAT Test 2 originally failed because "everything in the Properties panel is cut on the right side". I patched a single picker row first (commit 6c3fe29's parent); the actual fix was the ScrollArea Viewport override that affected every ScrollArea in the app.
**Source:** 62-UAT.md, commit `6c3fe29`

### min-w-0 must cascade through every level of a flex chain
A single ParameterForm or SidebarPanel `min-w-0` is not enough — every intermediate flex container needs `min-w-0` or its children retain their intrinsic min-content width. The fix in commit 6a595d7 added `min-w-0` at SidebarPanel content div, ParameterForm outer, ParameterForm sections, and ResourceRow row class simultaneously.

**Context:** Panel-overflow regression UAT Test 2.
**Source:** commit `6a595d7`

### Shadcn TabsTrigger active-state cascade is not reliably overridable from className
Five attempts at overriding the shadcn TabsTrigger active visuals (border, ring, bg, !-important + dark: prefixes, text-primary) ALL appeared correct in source but did not visually affect the rendered tab. User screenshots showed identical icons whether Components or Resources was active. The only reliable fix was bypassing TabsTrigger entirely with custom `<button>` elements.

**Context:** ~8 iterations during UAT Test 7 polish.
**Source:** 62-UAT.md, commits `2935afe` → `c134bf6` → `5c8db33`

### Smoke-test scope must match files_modified scope
Data-only refactors cannot promise UI visibility changes in their smoke-test or human-verify checkpoints. The 62-11 Plan's smoke wording promised UI states that the data-layer changes could not deliver — that wording is a planner-template anti-pattern, not an execution gap.

**Context:** Phase 61 hit the same anti-pattern and recorded it in [[feedback_smoke_test_scope_match]] memory; Phase 62 echoed it.
**Source:** STATE.md "Phase 61 outcomes" note + 62-11 plan history

### Dangling resource references require existence check in component logic
When a user deletes a resource from the Resources tree, components still hold the dangling UUID in their `parameters.geometry` / `parameters.power_shape` slot. The Select trigger correctly falls back to the placeholder UI, BUT the `Edit…` button stayed enabled (its disabled check only tested null / empty / sentinel — not whether the UUID resolved). Clicking Edit routed to a non-existent resource. Fix: extend isEditDisabled to also require `userResources.some(r => r.uuid === value)`.

**Context:** UAT Test 6 (a) discovered this — not caught by original verification.
**Source:** 62-UAT.md Test 6, commit `6a60853`

### Worktree spawn base can lag behind the target branch tip
Plan 62-12's executor agent reported that the worktree was created from commit `ecb0e72` (a pre-Phase-62 commit), not from `gui-redesign` tip (`e1433fb`). The plan files and target source files did not exist at that commit. The agent had to `git fetch && git reset --hard gui-redesign` before reading anything.

**Context:** Generalized into Wave 4 spawn prompts for 62-13 / 62-14 with an explicit "verify base via `git log --oneline -5 HEAD`" step.
**Source:** 62-12-SUMMARY.md deviations section

### Three-icon strips never need overflow detection
The icon tab strip's 32×32 icons + 8px gaps + 8px padding totals ~120px — exactly the minimum left-panel width. Three icons always fit. The "..." overflow dropdown is dead code for this strip.

**Context:** Cost ~80 lines of ResizeObserver-based overflow logic that never fires in practice. The original design (with text tabs) needed it; the icon redesign made it irrelevant.
**Source:** ResponsiveTabsList iconOnly branch

### Live-path key vs legacy-fixture-key in resource lookups
Plan 62-13's bug: usage detection in ResourceRow.tsx only checked `parameters[name + "_ref"]` (the legacy fixture key shape) but the live `ParameterForm.tsx` writes resource UUIDs under `parameters[name]` directly. AlertDialog never fired in the running app because `usages.length` was always 0. Fix: OR-scan both key shapes.

**Context:** Verification gate passed against fixtures; live behavior failed because fixtures and live app used different key conventions.
**Source:** 62-13-PLAN.md, 62-13-SUMMARY.md

### Vite HMR can silently show stale UI on deeply-nested className changes
Multiple UAT iterations during the chrome rework had the user reporting "nothing changes" even though the source code was clearly updated and vitest passed. Hard-reload (Ctrl+Shift+R) or `npm run dev` restart resolved it each time.

**Context:** Cost real cycle time during the active-tab icon iteration — I was hypothesizing CSS specificity issues that didn't exist.
**Source:** UAT session transcript, multiple iterations

### tsc baseline drifted from plan-recorded 6 to measured 8 errors
The 62-12 plan claimed a 6-error tsc baseline; actual measurement at gui-redesign tip was 8 errors (in StreamNode.tsx, ToolboxPanel.test.tsx, SidebarRouter.test.tsx, validation.test.ts — none in Phase 62 surface area). Phase 71 owns reconciliation.

**Context:** Plan frontmatter baseline numbers go stale across phases.
**Source:** 62-12-SUMMARY.md deviation note

---

## Patterns

### Off-screen measurement layer for responsive component sizing
When conditional rendering would poison measurement (e.g., applying `hidden` to overflowing children makes their offsetWidth = 0, so subsequent ResizeObserver ticks see zero widths and freeze the algorithm), render a separate measurement DOM that's never affected by visibility state. Position it absolutely off-screen with `pointer-events-none` so it doesn't affect layout or interaction.

**When to use:** Any responsive component where the "which children fit" decision depends on natural widths but the children are conditionally rendered based on the decision.
**Source:** ResponsiveTabsList text-mode implementation

### Custom `<button role="tab" aria-selected>` with parent `<Tabs value>` for content switching
When a UI library's base styling fights your design language, render plain semantic HTML for the visible chrome and keep the library's state machine via the parent. Radix Tabs root + TabsContent still drive content switching — only the trigger row is custom.

**When to use:** Whenever shadcn / Radix base CSS is too opinionated to override cleanly from className. The accessibility role + aria-* attributes preserve a11y testing.
**Source:** ResponsiveTabsList IconTabsList path

### Pure helper for "derive UI default from user input"
Pattern: `computeSaveAsDefaultFilename(name: string): string` — module-level pure function exported for vitest, handling whitespace trim + OS-illegal-char sanitization + double-extension prevention + empty-name fallback to a named `FALLBACK_*` constant.

**When to use:** Any feature where a user-typed field feeds into an OS / system dialog default. Separate the derivation from the I/O for testability.
**Source:** 62-14-SUMMARY.md, useStore.ts

### `PARAM_KEY_BY_KIND` const map for dual-key fallback
Pattern: `const PARAM_KEY_BY_KIND = { geometry: ["geometry", "geometry_ref"], powerShape: ["power_shape", "power_shape_ref"] }` and `paramKeys.some(k => params[k] === uuid)` for the lookup. Documents the dual-key fallback explicitly and survives a single-key rename refactor cleanly.

**When to use:** Any resource lookup that needs to span "live key" + "legacy fixture key" conventions. Better than scattered `params[name] || params[name + "_ref"]` chains.
**Source:** ResourceRow.tsx, codeGenerator.ts:803

### Cascading min-w-0 + outer overflow-hidden for panel containment
Pattern: outer panel `overflow-hidden` + every flex level inside `min-w-0` + content roots `w-full`. Use ResourceReferencePicker's `flex-wrap basis-full sm:basis-0` shape for any picker row that has a flex-shrinkable selector and pinned-width control buttons.

**When to use:** Any resizable panel that hosts forms with potentially-wide content.
**Source:** SidebarPanel.tsx, ParameterForm.tsx, ResourceReferencePicker.tsx

### VS Code sash chrome: 4px overlay + double-click collapse + 4px stub re-expand
Pattern: a 4px-wide absolute overlay on the panel's inner edge (`absolute right-0 top-0 w-1 h-full cursor-col-resize z-10`) with `onMouseDown=resize` + `onDoubleClick=collapse`. When the panel is collapsed, render a sibling `<button>` 4px strip in the same position with `onClick=expand`. The panel's own `border-r` / `border-l` is the visible 1px line — the 4px overlay is the hit area.

**When to use:** Any IDE-style resizable panel where you want the resize and collapse affordances to live on a single thin chrome element.
**Source:** App.tsx, SidebarPanel.tsx

### Test-pinned engineering voice
Pattern: every NEW user-facing string from a copy-rewrite plan must be asserted by ≥1 vitest case. Maintain a substitution table doc (`62-15-COPY-AUDIT.md`) alongside the code changes so the rationale lives next to the regressions test.

**When to use:** Any phase that rewrites user-facing copy. Prevents LLM-driven re-flow regressions.
**Source:** 62-15-PLAN.md, 62-15-COPY-AUDIT.md

### Wave-based execute-phase with worktree isolation
Pattern: independent gap-closure plans run in parallel via `Agent(isolation="worktree")`; orchestrator merges results between waves. Wave 4 (62-12, 62-13, 62-14) ran in parallel on disjoint files; Wave 5 (62-15, cross-cutting) ran after Wave 4 merged.

**When to use:** Any phase with disjoint file scopes that can run in parallel. The worktree exemption from the "no GSD branching" policy is documented in CLAUDE.md.
**Source:** execute-phase orchestrator output during this session

### UAT-driven scope expansion: fix inline as follow-up commits
Pattern: when /gsd:verify-work surfaces issues beyond the original gap-closure plans, fix them as follow-up commits inside the same phase rather than spawning new plans. Use commit conventions `fix(62)`, `refactor(62)`, `style(62)` to signal that these are gap closures on the already-verified phase scope.

**When to use:** When a UAT session reveals related-but-unanticipated issues. Avoids GSD-plan churn for ad-hoc polish during human-verify.
**Source:** ~9 follow-up commits this session: 6c3fe29 through 5c8db33

### Tooltip timing — Radix delayDuration + skipDelayDuration
Pattern: VS Code-style "first hover waits 500ms, subsequent neighbor hovers within 300ms show instantly" is built into Radix `<TooltipProvider delayDuration={500} skipDelayDuration={300}>`. Set on the app-level provider so every tooltip inherits.

**When to use:** Any IDE-style app with grouped icon controls (toolbars, tab strips, sidebars). One-line config.
**Source:** App.tsx, commit `a87888f`

---

## Surprises

### Five shadcn TabsTrigger override iterations failed to visibly change the active tab
Border, ring, bg-secondary, !-important + dark: prefixes, text-primary — all looked correct in source, all passed 440 vitest cases, all produced screenshots from the user showing identical icons across active and inactive states. Custom `<button>` elements bypassed the cascade and worked on first try.

**Impact:** Cost ~8 iterations during UAT Test 7 polish. Locked in the lesson that shadcn base TabsTrigger styling is not reliably overridable from className when the override is multi-state (default + hover + active variants).
**Source:** 62-UAT.md transcript, commits `eabeff6` → `5c8db33`

### Properties panel "cut on the right" was a SHADCN ScrollArea bug, not a missing flex constraint
After three rounds of patching min-w-0 in various flex containers, the actual root cause was Radix ScrollAreaPrimitive.Viewport wrapping children in `display: table`. A single-line `[&>div]:!block` className change to scroll-area.tsx was the actual fix. Every prior patch was treating a downstream symptom.

**Impact:** Wasted a commit (the ResourceReferencePicker flex-wrap patch in 62-12) that turned out to be ineffective on the broader Properties panel. Logged as a project-wide pattern issue.
**Source:** commit `6c3fe29`, Explore agent investigation

### Vite HMR showed stale UI during multiple iterations
Several "your change didn't do anything" reports during the active-tab styling iteration turned out to be Vite HMR not picking up the new className. Hard-reload always resolved it. This added noise to the cascade-debugging because I was hypothesizing CSS specificity issues that weren't present.

**Impact:** Cost ~3 unnecessary iterations chasing phantom specificity bugs.
**Source:** UAT session transcript

### Plan 62-13's bug shipped behind passing tests because the fixture used the wrong key shape
The AlertDialog test fixture seeded `parameters.geometry_ref: uuid` and passed against the resource-row code that checked exactly that key. The live ParameterForm wrote under `parameters.geometry` (no `_ref` suffix). Test was green, prod was broken.

**Impact:** Verification Gap #2 — discovered only at user-driven human-verify. Generalized fix: dual-key OR scan + a fixture refactor to seed the live key in subsequent tests.
**Source:** 62-VERIFICATION.md original audit, 62-13-PLAN.md

### Dangling-reference bug was not in the original verification — surfaced during UAT
Test 6 (a) was meant to be a copy spot-check on the disabled-Edit tooltip. The user's manual flow revealed that after deleting a referenced resource, the Edit button stayed enabled because the disabled check tested null / empty / sentinel but not "UUID resolves to an existing resource."

**Impact:** Confirms value of human-verify even after automated 440-test gate passes. Bug shipped to the gap-closure commits (62-12..62-15) and was not caught until UAT.
**Source:** 62-UAT.md Test 6, commit `6a60853`

### User rejected dimming inactive icons AND keeping all icons bright in successive messages
"Do not dim the icons at all" and "the colors right now are probably too bright it looks like they are all highlighted" came one message apart. Initially read as contradiction; actually meant "subtle dimming OK, but make active visibly different by COLOR (not just opacity)."

**Impact:** Required a different color token (text-primary) for active, not an opacity step. Decisive moment in the chrome iteration.
**Source:** UAT session messages around the active-tab styling

### Worktree spawn base lagged behind branch tip — silent unless agent checks
Plan 62-12's executor reported the worktree HEAD was a pre-Phase-62 commit and the entire `.planning/phases/62-*` directory did not exist there. The agent did the right thing (`git fetch && git reset --hard gui-redesign`) but the user-visible workflow would have erroneously claimed "plan files not found" without that fallback.

**Impact:** Subsequent Wave 4 prompts (62-13, 62-14) explicitly included a "verify HEAD via `git log --oneline -5`" preamble.
**Source:** 62-12-SUMMARY.md deviations section

### Density pass shrank everything and the user reaction was uniformly positive
The density-pass commit (6a595d7) dropped the right Properties panel header from 16px font-semibold to 12px uppercase muted, shrank Input height from 36px to 32px, tightened form gaps from 16-24px to 6-8px, and shrunk ResourceRow height from 28px to 22px. User confirmed "Looks good" after the icon-tab + tooltip-timing follow-on, with no requested rollback on any density value.

**Impact:** Locks in VS Code Workbench (~13px body / 22px rows / 6-8px gaps) as the project's density baseline going forward. Phase 63+ should match.
**Source:** commit `6a595d7`, UAT Test 7 confirmation

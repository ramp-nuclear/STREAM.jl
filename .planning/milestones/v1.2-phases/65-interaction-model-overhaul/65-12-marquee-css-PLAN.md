---
phase: 65-interaction-model-overhaul
plan: 12
type: execute
wave: 1
depends_on: []
files_modified:
  - gui/src/index.css
autonomous: false
requirements: []
gap_closure: true
tags: [css, marquee, selection, reactflow, gap-closure, phase-65]

must_haves:
  truths:
    - "The marquee selection rectangle (drawn while left-mouse-dragging on empty canvas) has a SOLID border in the project's primary accent color — not the default ReactFlow `1px dotted rgba(0,89,220,0.8)`."
    - "The marquee border is slightly more opaque/brighter than its fill (user's requested aesthetic: 'full line a little brighter than the fill')."
    - "After releasing the marquee, NO bounding box wraps the selected nodes — `.react-flow__nodesselection-rect` is hidden via `display: none`. Selection is conveyed only by per-node `ring-2 ring-[var(--ring)]` highlight on StreamNode."
    - "The override adapts to light/dark themes via the existing `.dark` class on `:root` (uses `color-mix(in oklch, var(--primary), ...)` design token)."
    - "Node dragging and per-node selection are unaffected (`.react-flow__nodesselection` parent already has `pointer-events: none`)."
  artifacts:
    - path: "gui/src/index.css"
      provides: "Two appended CSS rule blocks after the existing `.react-flow__handle` block: (1) styled `.react-flow__selection` (in-drag marquee) and (2) `display:none` on `.react-flow__nodesselection-rect` (post-selection bounding box)."
      contains: ".react-flow__nodesselection-rect"
  key_links:
    - from: "Tailwind v4 CSS-first config"
      to: ".react-flow__selection rules"
      via: "specificity higher than default @xyflow/react/dist/style.css due to source order"
      pattern: "color-mix(in oklch, var(--primary)"
---

<objective>
Close UAT Test 4 cosmetic gaps (#5 + #6): the marquee selection border is the default dotted
style and an unwanted bounding box appears around selected nodes after releasing the marquee.

Root cause (`.planning/debug/marquee-visual-style.md`): `@xyflow/react@12.10.2` ships
`--xy-selection-border-default: 1px dotted rgba(0, 89, 220, 0.8)` and unconditionally renders
a `&lt;NodesSelection&gt;` overlay (`.react-flow__nodesselection-rect`) whenever 2+ nodes are
selected. The project has zero overrides for either class.

Fix: append two CSS rule blocks to `gui/src/index.css` after the existing
`.react-flow__handle` block (after line 132). Strategy: target the rules directly (not the
CSS variables) so we can express `display: none` for the bounding box (which can't be expressed
via the variable). Use `color-mix(in oklch, var(--primary), ...)` so the rule adapts to the
light/dark theme via the existing `.dark` class on `:root`.

This is a single-file CSS-only change. No new dependencies; no Tailwind config changes
(project uses Tailwind v4 CSS-first config with `@import "tailwindcss"` at index.css:1 — no
`tailwind.config.js` file).

Purpose: visual polish promised by Plan 03 selection-on-drag feature but not delivered.

Output: index.css patched; a `checkpoint:human-verify` confirms appearance on the live Tauri
dev shell (CSS can't be meaningfully unit-tested for "looks good"; the closest automated check
is grepping for the rule's presence and `cd gui &amp;&amp; npm run build` exiting 0).

Source: `.planning/debug/marquee-visual-style.md` (root cause + fix snippet ready).
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/65-interaction-model-overhaul/65-03-SUMMARY.md
@.planning/phases/65-interaction-model-overhaul/65-UAT.md
@.planning/debug/marquee-visual-style.md
@gui/src/index.css

<interfaces>
<!-- Current index.css tail (around .react-flow__handle block, lines 126-132) -->
The existing convention is to append ReactFlow overrides AFTER `.react-flow__handle`.
Use the SAME indentation (2 spaces) and SAME block style.

<!-- Design tokens available -->
- `var(--primary)` — oklch(0.205 0 0) light / oklch(0.73 0.012 250) dark. Likely candidate.
- `var(--ring)` — alternative; used by StreamNode's per-node selection ring.
- `--xy-selection-background-color` / `--xy-selection-border` — ReactFlow's CSS variable hooks.
  We're NOT using these (display:none requires direct rule override anyway, and the variables
  are an extra layer of indirection when only two classes need overriding).

<!-- ReactFlow v12 class names (verified in gui/node_modules/@xyflow/react/dist/style.css) -->
- `.react-flow__selection`             — in-drag marquee rectangle, z-index 6
- `.react-flow__nodesselection-rect`   — post-selection bounding box, child of `.react-flow__nodesselection`
- `.react-flow__nodesselection`        — parent wrapper, already has `pointer-events: none`
  (so hiding the child rect does NOT break node dragging or selection state)
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Append marquee + nodesselection-rect CSS overrides to index.css</name>
  <files>gui/src/index.css</files>
  <action>
    Open `gui/src/index.css`. Append the following block at the END of the file
    (after the existing `.react-flow__handle` block; current file is 132 lines, so append
    starting at line 133):

      /* Phase 65 Plan 12 — marquee selection rectangle (in-drag).
         Replaces default `1px dotted rgba(0,89,220,0.8)` with a solid border in the
         primary design token, slightly brighter than the fill. Auto-adapts to light/dark
         via the .dark class on :root (color-mix consumes the resolved --primary value). */
      .react-flow__selection {
        background: color-mix(in oklch, var(--primary) 12%, transparent);
        border: 1px solid color-mix(in oklch, var(--primary) 55%, transparent);
        border-radius: 2px;
      }

      /* Phase 65 Plan 12 — hide the post-selection NodesSelection bounding box.
         @xyflow/react v12 always renders this overlay when 2+ nodes are selected; no
         prop disables it. Selection state is conveyed by per-node .selected highlight
         on StreamNode (StreamNode.tsx:361 — ring-2 ring-[var(--ring)]). Parent
         .react-flow__nodesselection already has pointer-events: none, so hiding the
         child rect does not affect dragging or selection state. */
      .react-flow__nodesselection-rect {
        display: none;
      }

    Use EXACTLY this CSS. Both blocks come verbatim from `.planning/debug/marquee-visual-style.md`
    "Resolution.fix" — that section was vetted by the diagnose session against the
    @xyflow/react@12.10.2 default stylesheet. Do not paraphrase the percentages
    (12%, 55%) — the user feedback specifically asked for "a little brighter than the fill"
    and 55% vs 12% is the spread that delivers that.

    No other changes. Do NOT delete the existing `.react-flow__handle` block.
    Do NOT add `@layer` directives — Tailwind v4 CSS-first config does not require them for
    raw class overrides; plain selectors with adequate specificity / later source order win.

    Build sanity:
      cd gui &amp;&amp; npm run build 2>&amp;1 | tail -30
    Expect either a successful exit, OR the same pre-existing 11 tsc errors (Phase 71 owns
    them per STATE.md). The CSS itself does not affect tsc.

    Commit:
    ```
    git add gui/src/index.css
    git commit -m "style(65-12): replace marquee dotted border + hide selection bbox

    Override .react-flow__selection to use a solid border in --primary
    (color-mix oklch, 55% border vs 12% fill — matches user's 'brighter
    border' request). Set .react-flow__nodesselection-rect display:none
    so no bounding box wraps selected nodes after release (selection
    conveyed only by per-node ring).

    Closes UAT Test 4 cosmetic gaps #5 + #6
    (.planning/debug/marquee-visual-style.md).

    Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
    ```
  </action>
  <verify>
    <automated>
      # Both rules present
      grep -q "\\.react-flow__selection {" gui/src/index.css
      grep -q "\\.react-flow__nodesselection-rect {" gui/src/index.css
      # Percentages and the color-mix function as specified
      grep -q "color-mix(in oklch, var(--primary) 12%, transparent)" gui/src/index.css
      grep -q "color-mix(in oklch, var(--primary) 55%, transparent)" gui/src/index.css
      grep -q "display: none" gui/src/index.css
      # Pre-existing .react-flow__handle still present
      grep -q "\\.react-flow__handle {" gui/src/index.css
      # Vite build does not break (ignore the 11 pre-existing tsc errors — Phase 71 owns)
      cd gui &amp;&amp; npx vite build 2>&amp;1 | tail -5 | grep -E "error|✓"
    </automated>
  </verify>
  <done>
    index.css has the two appended rule blocks at end of file; existing `.react-flow__handle`
    rule untouched; vite build emits no NEW errors; commit recorded.
  </done>
</task>

<task type="checkpoint:human-verify" gate="auto-approvable">
  <name>Task 2: Visual confirmation — marquee + no bounding box</name>
  <files>(no code change — visual confirmation only)</files>
  <action>
    Two CSS overrides on top of the @xyflow/react default stylesheet. Visual change only;
    no logic change. Worth a 30-second visual confirmation on the live Tauri dev shell
    because "looks brighter than the fill" is a subjective acceptance criterion.

    **How to verify:**

    1. Run `cd gui &amp;&amp; npm run tauri dev` (or HMR-reload if dev is already running — index.css
       is hot-reloaded by Vite without a Tauri restart).

    2. With at least 2 nodes on the canvas, click-and-drag on EMPTY canvas (left mouse) to
       draw a marquee. Confirm: the marquee border is a SOLID line (not dotted), and the
       border is visibly more opaque than the fill. Color matches the primary accent
       (in dark mode: light gray/blue; in light mode: near-black).

    3. While dragging, expand the marquee to cover 2+ nodes. Release. Confirm: NO bounding
       box wraps the selected nodes. Selection is visible only via the existing per-node
       ring outline (StreamNode `ring-2 ring-[var(--ring)]`).

    4. Drag one of the selected nodes. Confirm: dragging still works (parent
       `.react-flow__nodesselection` has `pointer-events:none` so hiding the child is safe).

    5. Toggle dark/light theme (if a theme toggle is visible). Confirm: marquee color
       adapts (because `color-mix` consumes the resolved `--primary` token under each theme).

    If all 5 steps look correct — approve.
  </action>
  <verify>
    <human-check>Human runs the 5-step visual check on the live Tauri dev shell.</human-check>
  </verify>
  <done>User types "approved" indicating all 5 visual checks passed.</done>
  <resume-signal>
    Type "approved" if all 5 visual checks pass.
    If the marquee still looks dotted or a bounding box still appears: paste a screenshot
    or describe what you see; the plan needs revision.
  </resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

(none — CSS only)

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-65-12a | Tampering | gui/src/index.css | accept | CSS rules cannot cause logic faults; worst case a future ReactFlow major bumps changes class names, in which case the override silently no-ops (the marquee reverts to default styling). Documented in the inline comment. |
</threat_model>

<verification>
- `grep -q "\\.react-flow__selection {" gui/src/index.css`
- `grep -q "\\.react-flow__nodesselection-rect {" gui/src/index.css`
- `grep -q "display: none" gui/src/index.css`
- Vite build: `cd gui &amp;&amp; npx vite build` exits 0 (CSS errors fail this).
- Task 2 visual checkpoint approved.
</verification>

<success_criteria>
- index.css contains both rule blocks with the exact `color-mix(in oklch, var(--primary), ...)` percentages and `display: none` on `.react-flow__nodesselection-rect`.
- Existing `.react-flow__handle` styling unchanged.
- Vite build succeeds.
- Task 2 visual checkpoint approved by the user.
- One commit recorded with `(65-12):` prefix.
</success_criteria>

<output>
Create `.planning/phases/65-interaction-model-overhaul/65-12-SUMMARY.md` when done.
</output>

# Phase 72 — Impeccable Audit Report

**Run:** 2026-05-21 via `/impeccable audit gui/src/`
**Scope:** All non-test code under `gui/src/` (~50 components, ~30 lib files, index.css)
**Doctrine:** `PRODUCT.md` + `DESIGN.md` (seed) + Impeccable's 29 built-in anti-pattern rules

---

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility       | **2/4** | No `prefers-reduced-motion` respect anywhere (PRODUCT.md locked rule); `div`-as-button in WelcomeOverlay + ValidationPanel; baseline a11y present but unverified for WCAG AA contrast |
| 2 | Performance         | **4/4** | Unusually perf-aware codebase — primitive selectors, useMemo discipline, anti-blur-shadow doctrine on transformed nodes, rAF-deferred input.select(), explicit perf comments throughout |
| 3 | Theming             | **1/4** | Token system widely bypassed: HSL mixed into OKLCH zone, layer-accent hex duplicated across 3 files, `text-yellow-500`/`text-blue-500` raw Tailwind in ValidationPanel, sky-400/300 placeholder rings never resolved |
| 4 | Responsive Design   | **4/4** | Desktop-only Tauri app; flex + shrink-0 layout patterns hold up across reasonable window sizes; one known panel-resize overflow already on the Phase 72 deferred list |
| 5 | **Anti-Patterns**   | **1/4** | WelcomeOverlay is a textbook AI-generated empty state; ValidationPanel matches the canonical "shadcn-admin" silhouette PRODUCT.md flags by name; em dashes in user copy; `backdrop-blur` glassmorphism in AutoRecoverRestoreModal; colored `border-l-2` accent stripe in 2 surfaces |
| **Total** |       | **12/20** | **Acceptable — significant work needed** |

---

## Anti-Patterns Verdict

**Does this look AI-generated? Mostly yes.**

The codebase is *exceptionally well-engineered* — the per-component code quality is consistently high (memoization, careful event teardown, dependency-aware re-render avoidance, explicit perf reasoning). But the *visual layer* reads as "well-built shadcn-admin," which is the exact aesthetic PRODUCT.md anti-references by name.

Specific tells:

| Tell | Where | Severity |
|---|---|---|
| Empty-state cliché: card + Lucide icon + "to get started" copy + shadow-lg | `WelcomeOverlay.tsx` lines 26–69 | **P0** — exact PRODUCT.md anti-reference verbatim |
| Validator panel matches "generic shadcn admin" silhouette: AlertCircle/AlertTriangle/Info icons + muted-foreground chips + hover:bg-accent rows | `ValidationPanel.tsx` lines 92–98, 268–305 | **P0** — already flagged in `project_phase72_validator_ui_revisit` memory |
| Backdrop-blur glassmorphism on modal overlay (not justified — modal already has a 60% black scrim) | `AutoRecoverRestoreModal.tsx` line 69 | **P1** — explicit Don't in DESIGN.md §4 |
| `text-yellow-500` for warning, `text-blue-500` for info — raw Tailwind, no design intent, no token | `ValidationPanel.tsx` lines 96–97 | **P1** — bypasses the token system entirely |
| Em dashes in user-visible strings ("(leave unset — set in code)", "—" placeholders) | `useStore.ts:88,2673` · `PresetsPanel.tsx:111` · `AboutDialog.tsx:28,33` | **P2** — DESIGN.md §6 Don't, but low user-perception impact |
| Colored `border-l-2` accent stripe pattern (Impeccable's 29 anti-patterns includes this by name) | `FunctionSelect.tsx:125` · `CodePreview.tsx:224` | **P2** — neutral hue mitigates impact, but pattern is on the explicit Don't list |
| Lucide icons everywhere (the AI-tool default) — every chip, every header, every menu item | App-wide | **P2** — not bad on its own; reinforces the "default shadcn app" reading when combined with everything else |
| Default shadcn `rounded-md` / `shadow-md` / `animate-in/out` everywhere | All `components/ui/*.tsx` consumers | **systemic** — see Patterns section below |

The single biggest delta between current state and DESIGN.md target is that the app *currently reads as a tool built by someone following shadcn's documentation literally*, with no overriding visual identity. The four 4-layer accent colors (blue/amber/violet/rose) being identical to Tailwind defaults is the most legible signal of this.

---

## Executive Summary

- **Audit Health Score: 12/20 — Acceptable (significant work needed)**
- **Severity counts: P0 ×4, P1 ×8, P2 ×11, P3 ×6 = 29 findings total**
- **Top critical issues:**
  1. `WelcomeOverlay` is the textbook PRODUCT.md anti-reference
  2. `ValidationPanel` matches the "shadcn-admin" silhouette already flagged by memory
  3. No `prefers-reduced-motion` respect anywhere (locked WCAG/PRODUCT rule)
  4. Theming layer is broken — token system exists but is widely bypassed by inline hex + raw Tailwind classes; layer-accent hex is duplicated across 3 files with no source of truth
- **Top recommended actions** (priority order):
  1. `/impeccable shape WelcomeOverlay` — redesign the empty/first-run experience from scratch
  2. `/impeccable shape ValidationPanel + ValidationStatusBar` — fundamentals revisit per existing memory
  3. `/impeccable shape Layer accent system` — resolve the 4-layer signaling (color values, single source of truth, possibly switching from color-as-signal to something else)
  4. `/impeccable harden` cross-app — fix `prefers-reduced-motion` respect everywhere `animate-*` appears
  5. `/impeccable shape Canvas / StreamNode` — decide canvas background, dot color, node visual language (current `#282c34 / #4b5263 / #ccc` are unmotivated Claude defaults)

---

## Detailed Findings by Severity

### P0 — Blocking

**P0-1: WelcomeOverlay is a textbook consumer-SaaS empty state**
- **Location:** `gui/src/components/WelcomeOverlay.tsx` (entire file)
- **Category:** Anti-Pattern + Copy
- **Impact:** First impression for every fresh-launch + new-project user. Currently reads as a marketing card with hand-holding copy on a `shadow-lg` rounded panel. The string "to **get started**" appears verbatim in PRODUCT.md as a rejected anti-pattern. The `<div onClick=...>` recent-file rows are also a11y violations (no keyboard handler).
- **WCAG:** 2.1.1 Keyboard (recent-file rows)
- **Recommendation:** Fully redesign. The first-run surface should feel like opening a power tool, not opening a SaaS onboarding flow. Engineering voice for empty copy; native button/list semantics; no shadow-lg rounded-card overlay.
- **Suggested command:** `/impeccable shape WelcomeOverlay`

**P0-2: ValidationPanel matches the canonical "shadcn-admin" silhouette**
- **Location:** `gui/src/components/ValidationPanel.tsx`, `ValidationStatusBar.tsx`
- **Category:** Anti-Pattern
- **Impact:** Memory `project_phase72_validator_ui_revisit` already flagged this UI as functionally correct but design-rejected; user wants fundamentals revisit. Current rendering uses AlertCircle/AlertTriangle/Info Lucide icons + `text-yellow-500`/`text-blue-500` raw colors + `hover:bg-accent/30` rows — exactly the "generic shadcn admin dashboard" pattern PRODUCT.md flags by name.
- **Recommendation:** Treat validator UI as a from-scratch design problem. The data model (sortable result list, severity grouping, click-to-focus, fix actions) is correct; the visual + spatial layer needs replacement.
- **Suggested command:** `/impeccable shape ValidationPanel`

**P0-3: No `prefers-reduced-motion` respect anywhere in the codebase**
- **Location:** App-wide. Greppable: `prefers-reduced-motion` returns 0 hits across `gui/src/`.
- **Category:** Accessibility
- **Impact:** PRODUCT.md locks "Reduced-motion respect via `prefers-reduced-motion`" as accessibility floor. Currently violated everywhere `animate-in`/`animate-out` (every shadcn dialog/popover/menu/tooltip/select/dropdown), the canvas `pulse-once` animation (index.css), the node-flash-outline animation, and the smooth-scroll behavior on ValidationPanel `scrollIntoView` all fire regardless of user preference.
- **WCAG:** 2.3.3 (animation from interactions, AAA) + general motion sensitivity practice
- **Recommendation:** Add a global `@media (prefers-reduced-motion: reduce)` block in `index.css` that collapses animation durations to 0 and replaces `behavior: "smooth"` with `behavior: "auto"`. May also need motion-aware variants per shadcn primitive.
- **Suggested command:** `/impeccable harden` (cross-cutting a11y pass)

**P0-4: Theming layer is broken — token system widely bypassed**
- **Location:**
  - `index.css:229` — `hsl(38 92% 50%)` validation warning (HSL in OKLCH zone)
  - `index.css:240–242` — HSL destructive variant in `node-flash-outline`
  - `LayersPanel.tsx:40–43` — inline hex for 4 layer accents
  - `StreamNode.tsx:26–27` — same hex duplicated
  - `BCEdge.tsx:114–117` · `HydraulicEdge.tsx:70–75` — sky-300/400 hardcoded
  - `ValidationPanel.tsx:96–97` — `text-yellow-500` + `text-blue-500` raw Tailwind classes
  - `CanvasPanel.tsx:483,523` — `#282c34 / #4b5263 / #ccc` hardcoded canvas + dot colors
  - `CodePreview.tsx:460` — `bg-[#0d1117]` GitHub-dark hardcoded
  - `useStore.ts:846,1306` — `#b1b1b7 / #f59e0b` BC edge styling
- **Category:** Theming
- **Impact:** Dark/light theme switching can't propagate to surfaces that bypass tokens. Layer-accent values can't be changed in one place. Color-space inconsistency (HSL/OKLCH mix) violates DESIGN.md's locked OKLCH-only rule. Adding a new theme variant is effectively impossible without per-component refactor.
- **Recommendation:** Establish per-surface decisions on what tokens to introduce. At minimum: `--color-layer-hydraulic`, `--color-layer-thermal`, `--color-layer-sources`, `--color-layer-reactor-physics`, `--color-canvas-bg`, `--color-canvas-dots`, `--color-edge-default`, `--color-edge-hover`, `--color-edge-pinned`, `--color-warning`, `--color-info`. Convert all HSL to OKLCH.
- **Suggested command:** `/impeccable shape Layer accent system`, then `/impeccable polish` cross-app to migrate hardcoded values to tokens

### P1 — Major

**P1-1: Backdrop-blur glassmorphism on AutoRecoverRestoreModal**
- **Location:** `components/AutoRecoverRestoreModal.tsx:69`
- **Category:** Anti-Pattern
- **Impact:** Explicit DESIGN.md Don't ("No glassmorphism. Blurs and glass-cards used decoratively are prohibited"). The modal already has a `bg-black/60` scrim; the additional `backdrop-blur-sm` is decorative.
- **Recommendation:** Remove `backdrop-blur-sm`. Keep the 60% black scrim alone.
- **Suggested command:** `/impeccable polish AutoRecoverRestoreModal`

**P1-2: Layer accent palette is 4 raw Tailwind colors**
- **Location:** `LayersPanel.tsx:40–43`, `StreamNode.tsx:26–27`
- **Category:** Anti-Pattern + Theming
- **Impact:** The 4 layer accent hues (`#3b82f6 / #f59e0b / #8b5cf6 / #f43f5e`) are Tailwind's `blue-500 / amber-500 / violet-500 / rose-500` defaults — picked because they're 4 distinct slots, not because they signal the right things. Whether layers should be color-coded at all is open; whether these specific hues fit the domain (Hydraulic = blue is fine; Sources = violet is arbitrary; ReactorPhysics = rose is arbitrary) is unconsidered.
- **Recommendation:** Treat as the highest-priority design decision after WelcomeOverlay + ValidationPanel — the layer accent system propagates everywhere (StreamNode borders, LayersPanel chip, layer-aware connect highlights, validation flash, etc.).
- **Suggested command:** `/impeccable shape Layer accent system`

**P1-3 through P1-8: Hardcoded colors across signature surfaces**
- See P0-4 file list. Each surface (`StreamNode`, `BCEdge`, `HydraulicEdge`, `CanvasPanel`, `CodePreview`, `useStore` edge styling) needs token introduction. Per-surface fix during respective `/impeccable shape` calls.

### P2 — Minor

**P2-1: WelcomeOverlay recent-file `<div onClick>` rows lack keyboard nav**
- **Location:** `WelcomeOverlay.tsx:40–48`
- **Category:** Accessibility
- **Impact:** Recent-project rows are clickable but not Tab-reachable, no Enter/Space handler, no focus indicator.
- **Recommendation:** Convert to `<button>` or add `role="button" tabIndex={0} onKeyDown=...`. Will get resolved in P0-1 redesign.

**P2-2: ValidationPanel `<div role="button">` patterns**
- **Location:** `ValidationPanel.tsx:271–281` (row), `342` (FixActionButtons grouping div)
- **Category:** Accessibility
- **Impact:** Row has proper `role + tabIndex + onKeyDown` (works for screen readers) but is semantically a div. FixActionButtons grouping div has `onClick={stop}` with no keyboard handler — pure event-stop, but axe-core will flag it.
- **Recommendation:** Use `<button>` for row, or split FixActionButtons grouping into a fragment. Will get resolved in P0-2 redesign.

**P2-3: Em dashes in user-visible strings**
- **Location:** `useStore.ts:88,2673` · `PresetsPanel.tsx:111` · `AboutDialog.tsx:28,33`
- **Category:** Anti-Pattern (Copy)
- **Impact:** Locked PRODUCT.md / DESIGN.md Don't. The `AboutDialog` "—" placeholders are character-level (literal dash for unknown version), arguably defensible; the `useStore` and `PresetsPanel` instances are sentence punctuation.
- **Recommendation:** Replace `—` with `:` or `(` `)` or `;` per context. `AboutDialog` fallback char can stay if reframed as "n/a".

**P2-4: Colored `border-l-2` accent stripes**
- **Location:** `FunctionSelect.tsx:125`, `CodePreview.tsx:224`
- **Category:** Anti-Pattern
- **Impact:** Impeccable's 29 anti-patterns lists colored side-stripe borders explicitly. Current usage is neutral (`border-muted`), reducing severity, but the pattern is on the rejected list regardless.
- **Recommendation:** Replace with full border, background tint, leading indicator, or remove.

**P2-5: WindowControls hardcodes macOS traffic-light hex (`#ff5f57 / #ffbd2e / #28c840`)**
- **Location:** `WindowControls.tsx:111,116,121`
- **Category:** Theming
- **Impact:** Semi-justified — these specific values *are* the macOS standard, so platform mimicry has design intent. But they're inlined with no token, can't theme, and reduce when `40%` opacity is hardcoded inline rather than expressed as a state token.
- **Recommendation:** Tokenize as `--color-window-control-close / -minimize / -maximize` even if values stay hex.

**P2-6: `text-[10px]`, `text-[11px]`, `text-[13px]` arbitrary px sizes**
- **Location:** `LayersPanel.tsx:61` · `ValidationStatusBar.tsx:72,82,99,115` · `ValidationPanel.tsx:218,243,286,300` · `Input.tsx:62` · others
- **Category:** Anti-Pattern + Theming
- **Impact:** Ad-hoc type scale (10/11/13/14/18) emerged per-component without a designed scale. Multiple "off-scale" values like `text-[11px]` step outside Tailwind's standard scale into arbitrary tokens.
- **Recommendation:** Resolved when type scale is decided (DESIGN.md §3 TBD). Will need a sweep to migrate.

**P2-7: BottomPanel.tsx has long lines / hard to parse comments — minor maintenance signal, not user-visible**

**P2-8: Five distinct modals (`AboutDialog`, `AutoRecoverRestoreModal`, `ExportConfirmDialog`, `SavePresetModal`, `UnsavedChangesDialog`)**
- **Category:** Anti-Pattern (Modal-as-first-thought)
- **Impact:** Locked PRODUCT.md / DESIGN.md Don't says "exhaust inline / progressive alternatives before reaching for Dialog." Each modal is individually defensible (About is short, AutoRecover is decision-blocking, Export confirms a destructive action, SavePreset captures a name, Unsaved blocks a navigation). The count is reasonable for a desktop app. But Phase 72 should re-examine each on its own merit.
- **Recommendation:** During per-surface shape, ask: "Could this be inline instead?" especially for SavePresetModal (could be inline-rename pattern in the panel) and AboutDialog (could be a popover from the titlebar).

**P2-9: Panel-resize overflow (known issue, on Phase 72 deferred-todos list)**

**P2-10: `animate-pulse` in PresetsPanel — may not be motion-reduced**

**P2-11: Smooth-scroll in ValidationPanel `scrollIntoView({ behavior: "smooth" })` doesn't respect reduced motion**

### P3 — Polish

- Title attributes used as poor-man's tooltips in 5 places (`title="..."`)— upgrade to `Tooltip` primitive for consistency
- `text-yellow-500` could use Tailwind's amber-400/500 for warmth alignment with thermal accent — but real fix is tokenization
- `transition-colors` and `transition-opacity` are used consistently — good baseline, no fix
- Icon size inconsistency: `h-3 w-3` in ValidationStatusBar vs `h-4 w-4` in ValidationPanel — pick one
- ValidationPanel's "Clear filter" button appears in two places with same label — possible code consolidation
- `&middot;` HTML entity in ValidationPanel filter banner — could be a real bullet `·` for cleaner source
- `CommandPalette.tsx:314` uses `shadow-xl` (one of two `shadow-xl` instances) — review whether warranted
- Some long Tailwind class strings (>200 chars) reduce maintainability — extract to `cva` variants when patterns stabilize

---

## Patterns & Systemic Issues

These are recurring problems indicating systemic gaps, not one-off fixes.

### S-1: "Default shadcn" everywhere

The most pervasive issue. Every shadcn primitive currently uses its default new-york-style configuration: `rounded-md`/`rounded-lg`, `shadow-md`/`shadow-lg`, `animate-in`/`animate-out`, `bg-popover`/`bg-card`, `hover:bg-accent`. None of these have been touched to express the project's design intent. Result: a competent admin dashboard look that PRODUCT.md explicitly rejects.

**Fix shape:** A single design pass on the shadcn primitive layer (`gui/src/components/ui/*.tsx`) that commits to a specific radius scale, a specific shadow vocabulary (or absence), specific motion language. This is the foundational decision that cascades to every consumer surface. Until this lands, per-surface `/impeccable shape` work will keep producing "well-styled shadcn defaults" instead of distinctive STREAM Composer surfaces.

**Suggested ordering:** Resolve color strategy (DESIGN.md §2 TBD) + depth approach (§4 TBD) + type scale (§3 TBD) on a *high-leverage surface first* (likely the canvas — it's the largest visual area and sets identity). Then promote those decisions into the shadcn primitives.

### S-2: Inline hex bypasses the token system in every signature surface

`StreamNode`, `BCEdge`, `HydraulicEdge`, `CanvasPanel`, `LayersPanel`, `WindowControls`, `CodePreview`, `useStore` — every surface that paints distinctive visuals bypasses tokens. Some of this is defensible (StreamNode's documented JIT-bypass rationale, WindowControls' platform mimicry); most is not (CanvasPanel canvas/dot colors, BCEdge/HydraulicEdge sky placeholders, ValidationPanel raw Tailwind classes, layer accent duplication).

**Fix shape:** Per-surface, during `/impeccable shape`, decide which colors are real tokens (most of them) vs documented JIT-bypass exceptions (a small number). Establish naming conventions for the new tokens (per `feedback_gui_no_design_inertia`: defer naming style decision until tokens land).

### S-3: No motion doctrine

The codebase has motion (shadcn `animate-in/out`, pulse animations, node-flash, smooth-scroll) but no doctrine for *when* motion is appropriate or how it should feel. PRODUCT.md says "no decorative motion"; current state has motion that's neither decorative nor clearly functional.

**Fix shape:** A motion-direction decision in DESIGN.md §4 (currently TBD): Restrained (state-changes only) / Responsive (feedback + transitions, no choreography) / Choreographed (orchestrated entrances). Plus a per-component pass to align.

### S-4: A11y is present but unverified

`focus-visible` appears in 18 files, `aria-label` in 29, `role` attributes in many. But: no `prefers-reduced-motion`, no audited WCAG AA contrast measurements, several `div onClick` patterns, no consistent keyboard nav patterns (some components have full keyboard support, others none).

**Fix shape:** `/impeccable harden` cross-cutting pass + a documented WCAG audit (axe-core or similar) per surface during shape work.

---

## Positive Findings

**These are working well — preserve them through the redesign.**

- **Performance discipline is genuinely excellent.** Primitive selectors over object/array (`useStore((s) => s.activeLayers)` not `useStore((s) => ({ ... }))`), useMemo where it matters, rAF-deferred `.select()`, zero-blur shadow doctrine on canvas children, perf comments throughout justifying choices. Don't disturb this during visual redesign.
- **OKLCH commitment in `:root` tokens.** The base color tokens are OKLCH-correct. Drift is at the consumer surfaces, not the foundation.
- **3-tier depth hierarchy concept is solid** even if specific values are open. The chrome/panel/canvas separation maps cleanly to the canvas-as-product principle in PRODUCT.md.
- **Input auto-select-on-focus chokepoint** (`gui/src/components/ui/input.tsx`) is a model for how to make universal behavior changes at a single point. Per `feedback_input_select_on_focus`, preserve the chokepoint through any restyling.
- **ValidationPanel empty state** ("No issues.") — already engineering voice, exactly what PRODUCT.md prescribes. The data layer is correct; only the visual + spatial layer needs work.
- **Per-component comments document Phase-N design decisions inline.** This is a real asset — future-Claude (and Impeccable) reading these files gets the reasoning, not just the code. Keep the discipline.
- **Engineering voice in most copy.** "(filtered)", "n=", "(unset)", "fn(t)" — terse, declarative, expert-assuming. The exceptions (WelcomeOverlay, PresetsPanel "first template") are the outliers, not the norm.

---

## Recommended Actions

In priority order (P0 first):

1. **[P0] `/impeccable shape WelcomeOverlay`** — fully redesign the first-run empty state. This is the user's first impression and is currently the worst single offender.
2. **[P0] `/impeccable shape ValidationPanel + ValidationStatusBar`** — fundamentals revisit per `project_phase72_validator_ui_revisit`. The data model is correct; rebuild the visual + spatial layer.
3. **[P0] `/impeccable shape Layer accent system`** — resolve the 4-slot signaling problem (color values, single source of truth, possibly switching the signaling mechanism from color to something else). Cascades to StreamNode, LayersPanel, BCEdge, HydraulicEdge, validation flash.
4. **[P0] `/impeccable shape Canvas (CanvasPanel + StreamNode)`** — decide canvas background, dots, node visual language. This is the highest-leverage surface (largest visual area, most user attention) and should anchor the color strategy + depth approach decisions for DESIGN.md.
5. **[P0/P1] `/impeccable shape shadcn primitive layer`** — once color/depth/type decisions land on canvas (#4), promote those into the shadcn primitives (Button, Input, Dialog, etc.). Replaces "default shadcn-admin" with committed STREAM Composer language.
6. **[P0] `/impeccable harden` (cross-cutting)** — add `prefers-reduced-motion: reduce` handling for every `animate-*` and `behavior: "smooth"` site. Audit a11y per surface (div-as-button → button conversion, missing keyboard handlers).
7. **[P1] `/impeccable polish AutoRecoverRestoreModal`** — remove glassmorphism `backdrop-blur-sm`.
8. **[P1] `/impeccable shape BCEdge / HydraulicEdge`** — replace sky-300/400 placeholder hex with real edge color tokens.
9. **[P1] `/impeccable shape CodePreview`** — replace `#0d1117` GitHub-dark hardcode with a tokenized "code surface" treatment that respects the chosen color strategy.
10. **[P2] `/impeccable clarify` (cross-cutting copy pass)** — remove em dashes from user-visible strings; review any other consumer-SaaS framing.
11. **[P2] `/impeccable polish FunctionSelect / CodePreview`** — replace `border-l-2` colored stripes per Impeccable Don't.
12. **[P2] `/impeccable shape SavePresetModal` + `AboutDialog`** — re-examine whether modal is the right primitive (PRODUCT.md prefers inline).
13. **[Final] `/impeccable polish gui/src/`** — final cross-app pass after the above land, then `/impeccable audit gui/src/` again to verify P0/P1 cleared.

---

## Re-run guidance

After per-surface shape decisions promote `[TBD]` slots in DESIGN.md to locked values, re-run `/impeccable audit gui/src/`. Token-bypass findings (P0-4, P1-2 through P1-8, S-2) will resolve concretely against the new tokens. Anti-pattern count should drop materially as WelcomeOverlay + ValidationPanel get rebuilt.

Target end-of-Phase-72 score: **17–20 / 20**.

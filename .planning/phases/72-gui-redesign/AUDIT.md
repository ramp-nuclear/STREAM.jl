# Phase 72 — Impeccable Audit Report (Session 4 re-run)

**Run:** 2026-05-23 via `/impeccable audit gui/src/`
**Scope:** All non-test code under `gui/src/` (~50 components, ~30 lib files, index.css)
**Doctrine:** `PRODUCT.md` + `DESIGN.md` (Phase 72 final) + Impeccable's 5-dimension audit rubric
**Supersedes:** the 2026-05-21 audit (12/20). After 11 locked shape sessions plus harden / clarify / polish / extract cross-cutting passes, this re-run measures the redesigned codebase.

---

## Audit Health Score

| # | Dimension | Score | Key Finding |
|---|-----------|-------|-------------|
| 1 | Accessibility       | **4/4** | Global `prefers-reduced-motion` + per-class `motion-reduce:`; `scrollIntoViewSafe` chokepoint for JS smooth scroll; WCAG AA contrast verified for `--muted-foreground` / `--color-warning` / `--color-info` (Phase 72 harden); native `<button>` semantics throughout, no `<div onClick>` shims remain. |
| 2 | Performance         | **4/4** | xyflow-aware: zero blurred shadows on canvas-transformed nodes; 76 useMemo/useCallback sites; selective zustand subscriptions documented; rAF-deferred Input.select(); Tauri plugins lazy-imported in `autoRecover.ts`; custom SVG marker decouples arrowhead size from edge stroke width. |
| 3 | Theming             | **3/4** | Token system shipped end-to-end (3-tier depth, 4 layer accents, 5 syntax tokens, severity vocab, --shadow-dialog, --dialog-surface / --dialog-border, --border-hover, --ring). **Single remaining gap:** `StreamNode` flow-port colors still inline as Tailwind hex (`#60a5fa / #1d4ed8 / #f87171 / #b91c1c`), labelled as a deferred JIT-bypass in 2026-05-21 but never tokenized by a subsequent shape. |
| 4 | Responsive Design   | **4/4** | Desktop-only Tauri scope. Wide dialogs (CommandPalette, AnatomyDialog) clamp via `max-w-[calc(100%-2rem)]` / `max-w-[95vw]`. Fixed-width column heuristics (ValidationPanel 32/200/fluid, PreferencesDialog 180/fluid) hold up across reasonable window sizes. |
| 5 | **Anti-Patterns**   | **4/4** | Zero gradient text, zero side-stripes > 1px, zero glassmorphism (one doc comment only); modal scrim banned project-wide; no hero-metric template; no AI-tell card grid; severity icons are documented IDE-convention carveout. The 2026-05-21 P0 anti-patterns (WelcomeOverlay, ValidationPanel silhouette, backdrop-blur on AutoRecover) are all closed. |
| **Total** |       | **19/20** | **Excellent — minor polish remains.** |

**Delta vs. 2026-05-21:** +7 (12 → 19). Every P0 from the prior audit is closed.

---

## Anti-Patterns Verdict

**Does this look AI-generated? No.**

The codebase no longer reads as "well-built shadcn-admin" (the silhouette PRODUCT.md anti-references by name). Cross-checked against the shared design laws' absolute bans:

| Ban | Status |
|---|---|
| Side-stripe borders > 1px | ✓ FunctionSelect migrated to 1 px hairline; one historical reference inside a code comment |
| Gradient text | ✓ zero matches |
| Glassmorphism / backdrop-blur as default | ✓ zero production uses; one doc comment in `dialog.tsx` only |
| The hero-metric template | ✓ no large-display-number panels |
| Identical card grids | ✓ AnatomyDialog 2-column grid is a "schematic legend" pattern (distinct intents per tile), not a card grid |
| Modal as first thought | ✓ Preferences considered Sheet / routed page during shape; Dialog chosen on tool-grade fit |
| Em dashes in user-visible strings | ✓ purge complete (2 remaining in `console.log` debug output, not rendered) |
| Modal scrim (project-specific ban) | ✓ all dialogs use `bg-transparent` overlay |
| FixAction auto-fix buttons (project-specific) | ✓ type + emission + render branch removed |

Category-reflex check (PRODUCT.md `register: product`):

- **First-order** ("nuclear/scientific tool → grey lab UI with serif headings"): inverted. Tool-grade dark/light terminal-adjacent hue-254 family, no scientific-legacy serif anywhere.
- **Second-order** ("tool that's not Linear-cream → terminal-native dark with cyan accents"): inverted. Layer accents are domain-derived (hydraulic blue, thermal amber, sources green, reactor crimson), not the saturated cyan-on-near-black palette every "engineer tool" default reaches for.

---

## Executive Summary

- **Audit Health Score: 19/20 — Excellent**
- **Severity counts: P0 ×0, P1 ×1, P2 ×0, P3 ×3 = 4 findings total**
- **Top remaining items:**
  1. [P1] StreamNode flow-port colors still inline hex (only meaningful token-bypass left in `gui/src/`). 4 constants in StreamNode + 12 mirror sites in AnatomyDialog.
  2. [P3] `fill="#fff"` chevron inside the flow-port disc, pure-white violation; trivial fix.
  3. [P3] Two `console.log` strings carry em-dashes, debug output only.
  4. [P3] `WelcomeOverlay` + `PreferencesDialog` fixed-width dialogs lack tiny-viewport clamps. Out of scope for desktop Tauri but documented for completeness.
- **Recommended actions:** one real follow-up (tokenize flow-port colors), then phase close.

---

## Detailed Findings by Severity

### P0 — Blocking

*(none)*

### P1 — Major

**P1-1: StreamNode flow-port colors are inline Tailwind hex, bypassing the token system**

- **Location:** `gui/src/components/StreamNode.tsx:32–35`
  ```tsx
  const FLOW_IN_BG = "#60a5fa";       // blue-400
  const FLOW_IN_BORDER = "#1d4ed8";   // blue-700
  const FLOW_OUT_BG = "#f87171";      // red-400
  const FLOW_OUT_BORDER = "#b91c1c";  // red-700
  ```
  Mirrored in `gui/src/components/AnatomyDialog.tsx` lines 475–476, 490–491, 734–735, 747–748, 775–776, 788–789 (6 inline `style={{ background, border }}` sites).
- **Category:** Theming
- **Impact:** Flow-port colors are the canonical signal for hydraulic direction (in vs out), visible on every node. Currently raw Tailwind defaults inlined as hex, exactly the pattern Phase 72 deliberately closed everywhere else. The 2026-05-21 audit logged this with a "deferred JIT-bypass" carveout pointing at a later edges-and-code-preview shape session; that session ran and locked without touching the port hex. The comment at `StreamNode.tsx:28` is now stale.
- **WCAG/Standard:** Project doctrine (no raw Tailwind hex outside documented carveouts).
- **Recommendation:** Either (a) define `--color-port-in` + `--color-port-out` + matching `*-border` tokens in `index.css`, or (b) repurpose the existing `--color-layer-hydraulic` for both with a directional discriminator (the chevron already conveys direction; the color split may be redundant). Either way, AnatomyDialog mirrors should consume the same tokens; update the carveout comment to point at the new SSOT.
- **Suggested command:** `/impeccable shape stream-node-ports` (the single-hue vs two-hue decision carries semantic weight; worth a brief)

### P2 — Minor

*(none)*

### P3 — Polish

**P3-1: `fill="#fff"` on flow-port chevron polygon**

- **Location:** `gui/src/components/StreamNode.tsx:226`
- **Category:** Theming
- **Impact:** Pure `#fff` violates the OKLCH-only no-#fff rule (DESIGN.md §2 locked rules). At chroma 0 it reads identical to a tinted neutral in most contexts; the practical impact is doctrine consistency, not visual.
- **Recommendation:** Swap to `oklch(0.99 0.003 254)` (matches `--canvas` light token) or `var(--canvas)`. The chevron reads the same.
- **Suggested command:** rolled into the P1-1 shape session, or fix inline during the next polish pass.

**P3-2: Em-dash in two `console.log` debug strings**

- **Location:** `gui/src/components/resources/ResourcesTreePanel.tsx:94,97`
  ```ts
  console.log("[ResourcesTreePanel] create resource kind=geometry — popover coming in 62-08");
  ```
- **Category:** Anti-Pattern (doctrine)
- **Impact:** Em-dash is banned in user-visible copy. These strings only render in the devtools console, so user impact is nil; doctrine consistency only.
- **Recommendation:** Replace with comma or semicolon.
- **Suggested command:** roll into `/impeccable polish` or fix inline.

**P3-3: Tiny-viewport overflow on WelcomeOverlay + PreferencesDialog**

- **Location:** `gui/src/components/WelcomeOverlay.tsx:75` (`w-[620px]`), `gui/src/components/PreferencesDialog.tsx:570` (`!max-w-[720px] w-[720px] h-[560px]`)
- **Category:** Responsive
- **Impact:** Tauri desktop-only scope, minimum-window-size policy unspecified. Practically zero user impact unless someone sizes the window <650 px wide. Documented for completeness.
- **Recommendation:** Optional. If a future Tauri build enforces a min window size (say 900×600), the issue evaporates. Otherwise add `max-w-[calc(100vw-2rem)]` to both.
- **Suggested command:** defer; not worth a session.

---

## Patterns & Systemic Issues

**No remaining systemic gaps.** The previous audit flagged four systemic patterns:

1. ~~"Hardcoded layer-accent hex duplicated across 3 files"~~ → resolved (`lib/layerColors.ts` SSOT).
2. ~~"Theming layer is broken — token system widely bypassed"~~ → resolved (Phase 72 retoken passes closed BCEdge / HydraulicEdge / CodePreview / ValidationPanel; harden tightened the contrast tokens).
3. ~~"No `prefers-reduced-motion` respect anywhere"~~ → resolved (global `@media` + `scrollIntoViewSafe` chokepoint).
4. ~~"Visual layer reads as well-built shadcn-admin"~~ → resolved (canvas + StreamNode + ValidationPanel + first-run + Preferences all rebuilt).

The single P1 (flow-port hex) is a localized straggler, not a systemic pattern: 4 constants in one file plus a mirror in one other.

---

## Positive Findings

Things worth celebrating and maintaining:

1. **Severity vocabulary is the design-system extraction template.** `lib/severity.ts` (Phase 72 extract) consolidates 4 inline copies into one module; every consumer reads from the same source. The template for how future cross-surface vocabularies should land.
2. **SectionHeader primitive replaces 16 ad-hoc copies.** `components/ui/section-header.tsx` (Phase 72 extract) is the canonical compact-uppercase-header; restyling now happens in one place. The AnatomyDialog tile-title carveout is documented inside the primitive.
3. **Reduced-motion is defence-in-depth.** Global `@media`, per-class `motion-reduce:`, JS-side `scrollIntoViewSafe`, marching-ants per-keyframe overrides: four redundant nets. The previous P0 took one commit to fully close.
4. **`--shadow-dialog` is the one shadow in the system.** Single tier, atmospheric, applied to Dialog / AlertDialog / Sheet / UnsavedChangesDialog / AutoRecoverRestoreModal. Every other primitive floats on tonal step + border. Rare in shadcn-derived codebases; reads as deliberate.
5. **WCAG AA contrast is computed, not eyeballed.** Phase 72 harden ran `oklch → sRGB → relative-luminance` against every token pair and tightened 3 tokens by computed delta. The audit log embedded in the harden session is the kind of work the next phase should keep doing.
6. **Custom SVG `<marker>` decouples arrowhead from stroke.** `markerUnits="userSpaceOnUse"` replaces xyflow's `MarkerType.ArrowClosed` (defaults to `strokeWidth`). Fixed-size arrows survive stroke-width changes for pin / hover / future states. Surfaces the right framework override at the right time.
7. **Severity-as-status-bar-icon is a documented carveout, not a slip.** ValidationPanel uses full words; ValidationStatusBar uses Lucide icons. DESIGN.md §5 explicitly notes "Status-Bar-Icons-Are-The-IDE-Convention" — same icon family that would be an anti-pattern in a row context reads as IDE lineage in a 22 px chrome bar. Surface-scoped doctrine, not project-wide ban.
8. **Performance discipline is unusually consistent.** xyflow-transformed children carry zero blurred shadows; selective zustand subscriptions are documented in every cross-store consumer; the marching-ants on active edges uses xyflow's `Edge.zIndex` for paint order (CSS z-index does nothing on SVG siblings, a trap most codebases fall into).

---

## Recommended Actions

In priority order:

1. **[P1] `/impeccable shape stream-node-ports`** — Decide the flow-port color story (single-hue with directional chevron vs two-hue tokens vs Hydraulic-layer-tinted). Promote whatever lands to tokens in `index.css`; update StreamNode + AnatomyDialog mirror; close the stale "deferred JIT-bypass" comment. Also rolls in P3-1 (`fill="#fff"` chevron) since the same file is being touched.
2. **[P3] `/impeccable polish gui/src/`** — Sweep up P3-2 (console.log em-dashes) and any other cosmetic dust that surfaces. Defer if not worth the cycle; polish already ran this phase, and one console.log doesn't earn another session.

After the P1 shape lands, re-run `/impeccable audit gui/src/` to confirm the score is 20/20 before writing `SUMMARY.md`.

---

> You can ask me to run these one at a time, all at once, or in any order you prefer.
>
> Re-run `/impeccable audit` after fixes to see your score improve.

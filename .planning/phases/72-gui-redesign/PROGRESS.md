# Phase 72 — Progress Tracker

Mid-phase tracker for Phase 72 (GUI redesign via Impeccable). Updated after
each `/impeccable shape` session lands. The final `SUMMARY.md` (written at
phase end per the ROADMAP row) supersedes this file.

## Method (recap)

Phase 72 runs **entirely through the Impeccable Claude Code skill** —
bypassing `/gsd:discuss-phase`, `/gsd:plan-phase`, `/gsd:execute-phase`,
`/gsd:ui-phase`, `/gsd:ui-review`, `/gsd:verify-work`. Each per-surface
decision goes through `/impeccable shape <surface>` (discovery → brief →
confirm → implement), with cross-cutting passes via `/impeccable harden`
/ `clarify` / `polish` and a final `/impeccable extract` to promote
reusable tokens.

**Two-pass DESIGN.md protocol:** the seed `DESIGN.md` (written by
`/impeccable document --seed`-equivalent at the start) carries doctrine
+ `[TBD]` slots. As shape decisions land, this PROGRESS.md updates AND
the corresponding `[TBD]` slots in `DESIGN.md` get promoted to locked
values. At Phase 72 end, `/impeccable document` runs in scan mode to
capture the final tokens into a proper frontmatter + sidecar.

## Status legend

| | |
|---|---|
| ✅ | Locked — shape + implementation committed; DESIGN.md updated |
| 🟡 | In progress — shape session active |
| ⬜ | Queued — awaiting its shape session |
| ⏸ | Deferred — waiting on an upstream decision |
| ❌ | Cancelled — dropped from scope |

## Surface progress

### Locked

| Surface | Status | Commits | DESIGN.md |
|---|---|---|---|
| Canvas + StreamNode + Layer accents + 3-tier depth + grid background | ✅ | 5 initial + 3 visual-bug fixes + cleanup (see Decision log below) | §2 fully locked; §3 type scale locked, font/direction TBD; §4 depth approach locked, shadow vocab TBD; §5 StreamNode locked |
| shadcn primitive layer (Button / Input / Dialog / Tabs / etc.) | ✅ | 6 cluster commits (tokens, Button, Input, Surface, Menu, Navigation) — see Decision log | §2 --ring/--border/--popover/--shadow-dialog/--border-hover locked; §3 type-scale tokens exposed; §4 shadow vocab locked (single tier); §5 primitive layer fully locked |

### Queued (Session 2)

| Surface | Status | Audit / critique reference |
|---|---|---|
| ValidationPanel + ValidationStatusBar (full visual rebuild; remove FixAction per memory) | ⬜ | Audit P0-2 · Critique P1-3 · `project_phase72_validator_ui_revisit` · `feedback_no_validator_fixaction_buttons` |
| First-run empty state (replaces WelcomeOverlay; engineering-voice) | ⬜ | Audit P0-1 · Critique P1-1 |
| Help system (Radix Tooltip primitive layer + `?` shortcut overview card) | ⬜ | Critique P0-2 |

### Queued (Session 3)

| Surface | Status | Notes |
|---|---|---|
| BCEdge + HydraulicEdge + CodePreview (tokenize remaining inline hex; finalize edge visual language) | ⬜ | Audit P1-4..7 · resolves sky-300/400 placeholders + `#0d1117` GitHub-dark hardcode |
| `/impeccable harden gui/src/` (cross-cutting: `prefers-reduced-motion`, div-as-button conversions, WCAG AA contrast pass) | ⬜ | Audit P0-3 · Critique Sam persona |
| `/impeccable clarify gui/src/` (copy pass: em dashes, consumer-SaaS framing in PresetsPanel, empty-state copy unification) | ⬜ | Audit P2-3 · Critique minor observations |

### Queued (Session 4 — phase close)

| Surface | Status | Notes |
|---|---|---|
| `/impeccable polish gui/src/` (final migration sweep — tokenize any remaining ad-hoc values) | ⬜ | |
| `/impeccable extract` (promote new reusable tokens + components into design system; write `.impeccable/design.json` sidecar) | ⬜ | |
| Re-run `/impeccable audit gui/src/` | ⬜ | Target ≥17/20 |
| Re-run `/impeccable critique gui/src/` | ⬜ | Target ≥32/40 |
| Re-run `/impeccable document` in scan mode (transition DESIGN.md from seed to real spec) | ⬜ | |
| Write Phase 72 `SUMMARY.md` (supersedes this file) | ⬜ | Per the ROADMAP row contract |

## Decision log

### Canvas + StreamNode (locked 2026-05-21)

**Commits on `gui-redesign` branch (oldest → newest):**

```
4707b5c  feat(72-canvas): tokens + depth recommit + field highlight bug fix
df97873  feat(72-canvas): tokenize LayersPanel via shared layerColors lib
79674be  feat(72-canvas): StreamNode leading-band identity
82edeef  feat(72-canvas): grid lines replace ReactFlow default dots
42d64f9  feat(72-canvas): tokenize ValidationPanel warning + info colors
12a6415  fix(72-canvas): node bodies visible, ports unclipped, grid quieter
5094f57  fix(72-canvas): validation-flash hugs node edge (offset 4 → 0)
e79b242  fix(72-canvas): validation-flash border-radius matches node body
7f6fef5  fix(72-canvas): retarget validation-flash to StreamNode outer div
[cleanup commit]  (DESIGN.md lock + validation-flash CSS cleanup + this file)
```

**Key locked values** (full detail in `DESIGN.md` §2–§5):

- Depth tokens: `--chrome` 0.16/0.95 · `--panel` 0.21/0.98 · `--canvas` 0.27/0.99
  · `--card` 0.23/0.97 (all hue 254)
- Layer accents (OKLCH, dark/light): Hydraulic 0.62/0.50 @ hue 240 · Thermal
  0.74/0.60 @ hue 75 · Sources 0.74/0.60 @ hue 130 · ReactorPhysics
  0.62/0.48 @ hue 15
- Grid: minor 12 px @ Δ 0.02, major 24 px @ Δ 0.05 from canvas
- Type scale: 1.25 Major Third — 10 / 11 / 13 / 16 / 20 px
- Node visual: leading band (4 px → 8 px on select), `bg-card` body, no
  perimeter border, `rounded-md` (8 px), multi-layer split via
  `getDisplayLayers()`

**New shared modules introduced:**

- `gui/src/lib/layerColors.ts` — `LAYER_COLOR_VAR` map (single source of
  truth for layer accent CSS-var references)
- `getDisplayLayers()` in `gui/src/lib/layers.ts` — visual-only layer
  detection (dual-layer for components with both FlowPort + ThermalPort);
  behavioral `getComponentLayers()` unchanged

**Tests:** 1028 / 1028 pass. Pre-existing 11 tsc errors unchanged (per
CLAUDE.md baseline).

### shadcn primitive layer (locked 2026-05-22)

**Commits on `gui-redesign` branch (oldest → newest):**

```
965d781  feat(72-primitives): tokens + Button family
a2d17ca  feat(72-primitives): Input family
a456111  feat(72-primitives): Surface family
98e84aa  feat(72-primitives): Menu family
63fbe9e  feat(72-primitives): Navigation + misc
[this commit]  docs(72-primitives): lock DESIGN.md + PROGRESS.md
```

**Three confirmed locks** (via AskUserQuestion during shape):
1. Shadow vocabulary = single tier (`--shadow-dialog` on Dialog/AlertDialog/Sheet only)
2. Primary-action posture = context-aware (neutral high-contrast slab everywhere; modal scrim does the work of permitting it to read confidently)
3. Density = balanced 32 px (`h-8`) globally; `h-7` sm for property forms; `h-6` xs for chips

**Cross-cutting commitments** (full detail in `DESIGN.md` §2–§5):

- Two-tier radius: `--radius-sm` 4 px (compact controls) / `--radius-md` 8 px (surfaces); no `rounded-lg`
- Five-tier type scale tokens: `--text-{micro,label,body,title,display}` (10/11/13/16/20 px)
- 100 ms fade-in / 80 ms fade-out, `motion-reduce:!duration-0`. Zoom + slide entrance removed.
- Focus ring 2 px `--ring` at offset 0; inset on Input/Textarea
- Hover surface = `bg-card` (tonal step; chrome doesn't carry accent fill)
- Icons: Lucide stays; size-3.5 stroke-1.5 in h-8 controls (was size-4 stroke-2)
- `--ring` relocked to Hydraulic-hue tint (low chroma); `--border` relocked to solid OKLCH (no alpha-on-white)
- New token `--popover` exposed in light mode; `--border-hover` and `--shadow-dialog` introduced
- `Sheet` primitive added (built on Radix Dialog; no consumers yet)

**Audit deltas this session resolves:**
- Systemic-1 ("default shadcn everywhere") — primitive layer no longer reads as the unmodified new-york template
- P0-4 (theming layer broken) — every primitive now consumes tokens; no inline hex inside `gui/src/components/ui/`
- P1-1 (backdrop-blur on AutoRecoverRestoreModal) — Dialog scrim is now `bg-foreground/40` with no blur; consumer-side fix is mechanical
- P2-6 (arbitrary `text-[Npx]`) — primitive layer migrated to type-scale tokens; consumer migration deferred to `/impeccable polish`
- Doctrine §4 violations on `shadow-xs` on Input/Toggle/Select — all removed

**Tests:** 1028 / 1028 pass (same as canvas-locked baseline). tsc baseline:
10 errors (was 11 before this session — incidental drop, no new errors
introduced).

### Lessons (worth re-reading at the start of the next session)

1. **The validation-flash bug took 3 sub-fixes** (offset → border-radius →
   retarget). Root cause: assuming the imperatively-added `.validation-flash`
   class lived on the rounded React-rendered element when it actually
   landed on xyflow's un-rounded wrapper. Lesson: when a class is added
   via `classList.add` from outside React, verify the DOM target element
   has the expected geometry/styling before tuning the CSS.
2. **`--card` initially tracked `--canvas`** which made node bodies invisible
   against the canvas. Lesson: when consolidating tokens, verify each one
   still has a *distinct* role; tracking values is fine for semantic
   alignment but only when the consumers need the same value.
3. **First-pass grid tones were too prominent** (Δ 0.08/0.04). User wanted
   "subtle structural texture, not decorative". Recommitted at Δ 0.05/0.02.
   Lesson: grids should be slightly less visible than feels right when
   coding (the contrast looks higher in real use because eye anchors on it).
4. **`--shadow-dialog` was self-referential in the first `@theme inline`
   pass.** Wrote `--shadow-dialog: var(--shadow-dialog)` — recursive
   reference. Tailwind v4 generates utilities from `@theme inline` shadow
   tokens with static values; for dark-mode-switching shadows the right
   pattern is to declare the token in `:root` and `.dark` and consume it
   via `shadow-[var(--shadow-dialog)]` arbitrary-value form at the
   primitive site. Lesson: when a token needs theme-switched values, don't
   try to expose it as a Tailwind utility — use arbitrary-value form.
5. **Removed `lg` button + `lg` icon-button sizes confidently** because
   grep showed zero consumers. The brief banned `h-9` / `h-10` from the
   primitive layer; the conservative move would have been to set `lg` to
   `h-9` as a compromise, but the brief was explicit. Lesson: greppable
   "no consumers" + explicit brief language is enough to drop API surface
   without a deprecation period (heavy-dev policy per `feedback_no_back_compat_during_heavy_dev`).

## Re-entry instructions for the next session

Open a new Claude Code session, then say something like:

> Continue Phase 72. Read `PRODUCT.md`, `DESIGN.md`,
> `.planning/phases/72-gui-redesign/AUDIT.md`,
> `.planning/phases/72-gui-redesign/PROGRESS.md`, and the latest critique
> snapshot in `.impeccable/critique/`. Then start `/impeccable shape
> ValidationPanel` (or whatever surface is next per PROGRESS.md).

The new session will load doctrine + queue + locked values + recent
lessons in 1–2 minutes and resume cleanly.

**Next surface per queue:** `/impeccable shape ValidationPanel` (Session 2,
first item — Audit P0-2, Critique P1-3, `project_phase72_validator_ui_revisit`,
`feedback_no_validator_fixaction_buttons`). The data layer is correct;
rebuild the visual + spatial layer from scratch.

**Related memories** (loaded automatically — don't need to re-read):

- `project_impeccable_design_workflow` — workflow + how to integrate with GSD
- `feedback_gui_no_design_inertia` — nothing visible is sacred
- `feedback_opinionated_design_no_inertia_no_churn` — be opinionated; defend
  on merit, change on real gripe, never change for change's sake

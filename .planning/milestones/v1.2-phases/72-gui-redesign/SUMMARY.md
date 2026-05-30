# Phase 72 — GUI Redesign via Impeccable — SUMMARY

**Phase:** 72 of 72 (last phase of milestone v1.2)
**Method:** ran entirely through the Impeccable Claude Code skill — bypassed `/gsd:discuss-phase`, `/gsd:plan-phase`, `/gsd:execute-phase`, `/gsd:ui-phase`, `/gsd:ui-review`, `/gsd:verify-work`.
**Window:** 2026-05-21 → 2026-05-28
**Supersedes:** `PROGRESS.md` in this directory.

## What shipped

Brought every GUI surface into compliance with a committed, professional, tool-grade visual identity. Twelve locked surfaces, two cross-cutting cleanup passes, one design-system extract, three Impeccable audits, two critiques, and a re-documented `DESIGN.md` SSOT.

### Locked surfaces (12)

1. **Canvas + StreamNode + Layer accents + 3-tier depth + grid background** — depth tokens, 4 layer accents, grid lines, leading-band node identity.
2. **shadcn primitive layer** (Button / Input / Dialog / Tabs / Surface / Menu / Navigation) — six cluster commits, single-tier shadow vocabulary, type-scale tokens exposed.
3. **ValidationPanel + ValidationStatusBar + unified bottom-chrome footer** — filter pills, group-by, resizable columns, selected-row indicator, status-bar tabs.
4. **Loop-highlight system + validator targeting rewrite** (`gravity_sum_per_loop`) — marching-ants flow trace motion, `.validation-flow-trace` + `.validation-flash-persistent` contract.
5. **HydraulicEdge** — obstacle-avoiding orthogonal router (Phase B) + smart port-side convention (Phase A v2, axis-snap, vertical bias, no-share-side invariant).
6. **First-run empty-canvas hint** — replaces WelcomeOverlay; chromeless typographic anchor; mono recents + Ctrl+ keymap, static-shortcut rule.
7. **Help system** — Tooltip discipline, cmdk shortcut mode, AnatomyDialog real-component-mirror legend, HelpMenu rebuilt.
8. **BCEdge + HydraulicEdge + CodePreview tokenization** — canvas↔code link state retoken to `--foreground`; five `--syntax-*` tokens; GitHub-dark borrow + `border-l-2` + section-header slab removed.
9. **`/impeccable harden gui/src/`** — `prefers-reduced-motion` safety net, `scrollIntoViewSafe` chokepoint, ValidationPanel Row `div`→`button`, three token contrast fixes. Closed Audit P0-3 + Critique Sam-persona findings.
10. **`/impeccable clarify gui/src/`** — em-dash purge, engineering-voice empty states across PresetsPanel / SidebarPanel / CodePreview / ResourcesTreePanel / AboutDialog / BottomPanel / CommandPalette. Closed Audit P2-3 + `feedback_engineering_voice_copy`.
11. **`/impeccable polish gui/src/`** — type-scale, section-header, `border-l-2` sweep, AutoRecover dialog migration to locked surfaces, canvas-menu shadow removal. Closed Audit P2-4 + P2-6 + P1-1; brought five consumer surfaces onto the locked primitive layer.
12. **Preferences** — Edit > Preferences… + `Ctrl+,`; two-pane Dialog; 6 categories; user-global persistence; Switch primitive added.

### Post-12 polish (Session 4, 2026-05-23 → 2026-05-28)

- Type-scale tokens + section-header retoken + ad-hoc-value sweep.
- Edit > Preferences with two-pane dialog, 8 wired controls, user-global prefs lib.
- Kill the grey modal body + dim scrim project-wide (modal-lock doctrine).
- Lane 2.5 port shape language + flow-port retoken.
- NoProjectHome replaces WelcomeOverlay (chrome gate doctrine).
- ValidationPanel progressive header + RULE 200→140 + resize hairline.
- AnatomyDialog distill + chrome surface + upsize.
- CommandPalette + AboutDialog adopt chrome-toned surface.
- BottomPanel resize handle at-rest hairline.
- Sweep low-opacity foreground text per legibility doctrine.
- JetBrains Mono committed as the project monospace.
- Middle-dot `·` locked as canonical separator idiom.
- Dialog surface unified to `bg-chrome` (Anatomy lineage).
- Tooltip primitive supports instant-on-disabled mode + wired into 4 consumer surfaces.

### Audit + Critique + Extract + Document — closure run

| Phase-close step | Verdict | Artifact |
|---|---|---|
| `/impeccable extract` | promoted 2 reusable surfaces + sidecar | `gui/src/lib/severity.ts` (vocab module, 4 consumer surfaces migrated) · `gui/src/components/SectionHeader.tsx` (10 consumer surfaces migrated) · `.impeccable/design.json` (v1 schema sidecar, `"version": "phase-72-closed"`) |
| `/impeccable audit gui/src/` | **19 / 20** (Excellent) — up from 12/20 at phase start | `.planning/phases/72-gui-redesign/AUDIT.md` |
| `/impeccable critique gui/src/` | **38 / 40** | `.impeccable/critique/2026-05-27T21-43-34Z__gui-src.md` (snapshot archived 2026-05-28) |
| `/impeccable document` (scan mode) | DESIGN.md transitioned seed → real spec (frontmatter + drift fixes) | `DESIGN.md` (repo root) |

**Audit score breakdown (19/20):**
| Dimension | Score |
|---|---|
| Accessibility | 4/4 |
| Performance | 4/4 |
| Theming | 3/4 (one deferred gap: StreamNode flow-port colors still inline as Tailwind hex — JIT-bypass marker carried forward) |
| Responsive Design | 4/4 |
| Anti-Patterns | 4/4 |

## Outputs

- **`DESIGN.md`** (repo root) — Stitch v2 spec with YAML frontmatter (color tokens, type scale, shadow vocabulary, layer accents). SSOT for all GUI tokens.
- **`PRODUCT.md`** (repo root, written 2026-05-21 at phase start) — design contract; anti-references shadcn-admin silhouette.
- **`.impeccable/design.json`** — machine-readable v1 sidecar mirroring DESIGN.md frontmatter (`"version": "phase-72-closed"`).
- **`.impeccable/critique/`** — three critique snapshots (2026-05-21, 2026-05-27, post-72 38/40 close).
- **`gui/src/lib/severity.ts`** — extracted severity vocab module.
- **`gui/src/components/SectionHeader.tsx`** — extracted SectionHeader primitive.

## Commits

114 commits on `gui-redesign` since the Phase 72 boundary, grouped by surface (full attribution in `PROGRESS.md` Decision log, which this file supersedes but does not replace).

## Out-of-scope / deferred to a future phase

- **StreamNode flow-port Tailwind hex** — single remaining theming gap noted in the 19/20 audit. The hex values (`#60a5fa / #1d4ed8 / #f87171 / #b91c1c`) are functional but not tokenized. Marked as deferred JIT-bypass since 2026-05-21; never tokenized by a subsequent shape. Carry-forward as a future polish task, not a v1.2 blocker.

## Side-channel work landed in this phase window

Independent of the GUI redesign, two cross-cutting changes landed on `gui-redesign` during the Phase 72 window and are included in the v1.2 PR:

1. **Physics fix — cell-center average for `P_i`** (`7c6f8b1`, 2026-05-28) — manual cherry-pick of `channels-redesign` commit `d8810e3`. Updates the per-cell pressure formula in `src/components/channels.jl` at both `_channel_core` (line 122) and the SCB-branch inline copy (line 557). The original `channels-redesign` only had one site; `gui-redesign` retains the dual-site structure so both needed the same fix.
2. **`bin/` directory deletion** (mirror of upstream `channels-redesign` cleanup `846df8d` — "Removed checked in files which were for the LLM only"). The Julia daemon dev loop scripts (`bin/jl`, `bin/jl-up`, `bin/jl-client.jl`) are gone from the tree. CLAUDE.md still references them — flagged as a follow-up doc fix.

## Re-entry instructions for a hypothetical future Impeccable session

If a future session continues the visual work (post v1.2), the entry context is:

```
Read PRODUCT.md, DESIGN.md, .planning/phases/72-gui-redesign/AUDIT.md,
and the latest .impeccable/critique/ snapshot. The design system is
locked at "phase-72-closed" — open with /impeccable audit gui/src/ to
re-baseline against the current code, then /impeccable critique for the
external read.
```

## Related memory

- `project_impeccable_design_workflow` — workflow + how Impeccable integrates with GSD.
- `feedback_gui_no_design_inertia` — nothing visible is sacred.
- `feedback_opinionated_design_no_inertia_no_churn` — defend on merit, change on real gripe.
- `feedback_no_grey_modal_surface_or_scrim` — modal-lock doctrine, enforced project-wide.
- `feedback_chrome_color_for_anatomy_modals` — reference/legend/palette dialogs use `bg-chrome`.
- `feedback_avoid_low_opacity_text` — legibility doctrine driving the low-opacity sweep.

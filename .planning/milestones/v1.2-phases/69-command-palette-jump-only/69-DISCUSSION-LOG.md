# Phase 69: Command palette (jump-only) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-18
**Phase:** 69-command-palette-jump-only
**Areas discussed:** Library + matcher, Visual surface, Off-layer match handling, Pan/zoom focus behavior

---

## Library + matcher

| Option | Description | Selected |
|--------|-------------|----------|
| cmdk (subject to dep audit) | Vercel/shadcn-backed; bundled UI + match + char-highlight + keyboard + ARIA. Drops in as `gui/src/components/ui/command.tsx`. Score: 8.5/10. | ✓ |
| Fuse.js + custom UI on radix Dialog | Matcher only; ~200 LOC of UI/keyboard/ARIA on radix Dialog. Score: 7.5/10. | |
| Hand-rolled | No dep; ~230 LOC matcher + UI. Score: 4/10. | |

**User's choice:** cmdk (subject to dep audit).
**Notes:** Dep audit is the first task of the phase per `feedback_dep_security_audit` memory. Confirmed security concern from audit → fall back to Fuse.js + custom UI on radix Dialog, NOT to hand-rolled.

---

## Visual surface

| Option | Description | Selected |
|--------|-------------|----------|
| Top-anchored (VS Code / Linear style) | ~80px from top, subtle backdrop dim with focus-trap, ESC dismisses, ~640px wide, ~480px max-height. Score: 9/10. | ✓ |
| Centered modal dialog | Default radix Dialog placement, full dim backdrop. Score: 6/10 — heavier than the action warrants. | |
| Centered floating, no backdrop | Lightweight, no dim, click-outside dismisses. Score: 5/10 — loses focus-trap, dismiss risk. | |

**User's choice:** Top-anchored overlay.
**Notes:** Section 3.7 explicitly names Linear, VS Code, Notion, Discord as references; all four use top-anchored. Muscle-memory alignment is the deciding factor.

---

## Off-layer (Phase 68 interaction) match handling

| Option | Description | Selected |
|--------|-------------|----------|
| Show + auto-enable on jump | Result shown normally with inline "Hydraulic off → will enable" hint. On select: layer toggled on, then pan/select. Mirrors Phase 68's forgiving layer-aware-connect philosophy. Score: 9/10. | ✓ |
| Show with off-layer indicator, no auto-enable | Result grayed with "layer off" chip. Jump anyway but item stays non-interactive; user manually enables layer. Score: 5/10 — contradicts Phase 68 pattern. | |
| Filter off-layer matches out entirely | Off-layer items never appear. Score: 3/10 — actively user-hostile, especially in Hide mode. | |

**User's choice:** Show + auto-enable.
**Notes:** Especially important in Hide mode where the user is using the palette as a recovery mechanism for components they can't currently see. The inline hint chip is mandatory so the side-effect isn't invisible (Section 3.8 no-silent-state-changes rule).

---

## Pan/zoom focus behavior

| Option | Description | Selected |
|--------|-------------|----------|
| setCenter + zoom floor | `setCenter(node.x, node.y, { zoom: max(currentZoom, ZOOM_MIN_LEGIBLE), duration: 250 })`. Preserves user's zoom unless below legibility threshold. Score: 8/10. | ✓ |
| fitView({nodes:[target]}) | react-flow built-in single-node fit. Predictable framing but yanks zoom each jump. Score: 7/10. | |
| Reveal-only | No-op if in viewport; minimal pan if off-screen; never changes zoom. Score: 6/10 — risk of "nothing happened" at low zoom. | |

**User's choice:** setCenter + zoom floor.
**Notes:** `ZOOM_MIN_LEGIBLE` is a tuning parameter for the executor (likely 0.6–0.8 based on existing node label sizing). The combination of D-03 (auto-enable layer) + D-04 (zoom floor) ensures that even when the layer just appeared, the jumped-to node is legible.

---

## Claude's Discretion

- Empty-query state: show all items grouped by kind; switch to flat fuzzy-ranked list as soon as the user types.
- Max results with typed input: ~50, internal scroll handles overflow.
- Result row layout when typing: flat ranked list with kind icon inline + match-char highlighting on.
- Resource navigator expand-and-select: likely needs a small store action; planner picks the surface.
- No status-bar trigger button (Section 3.7 explicitly: palette is Ctrl+P-only).

## Deferred Ideas

- Full action-invocation palette (VS Code style) — Section 3.7 explicit deferral.
- File search / recent-projects / docs search — out of scope per Section 3.7.
- Validation-aware results — belongs with Phase 71.
- Status-bar palette trigger button — explicitly rejected.

### Reviewed todos (not folded)

- `gui-visual-design-pass.md` → Phase 72.
- `2026-05-16-phase72-handle-port-visual-rework.md` → Phase 72.
- `codegen-resource-naming-dedup.md` → independent codegen fix, unrelated.
- `panel-resize-overflow-bounds.md` → independent layout fix, unrelated.

---
status: complete
closed_by: user UAT confirmed during v1.2 milestone close-out (2026-05-28)
---

# Phase 69 — Command Palette UAT Checklist

**Phase:** 69-command-palette-jump-only
**Authored:** 2026-05-19 (Plan 03 Task 2)
**Verifies:** D-01..D-08 + RESEARCH.md Pitfalls 1, 2, 4, 6 + four browse/typed-mode edge cases.

This is a **manual** checklist. The user runs a Tauri dev build, works
through every row in order, and ticks the box (`☐ → ☑`) on each row that
passes. The phase closes only when every box is ticked and the `## Gaps`
section at the bottom is empty.

---

## Environment

- Tauri dev build running: from repo root, `cd gui && npm run tauri dev`.
- A non-trivial project loaded with at least: 1 Pump, 1 Channel, 1
  Geometry resource, 1 Fluid resource. If no such project exists on
  disk, follow the setup section below.

## Sample project setup (if needed)

1. New project: Ctrl+N → confirm discard if prompted.
2. Drag a `Pump` from the toolbox onto the canvas. Click it, rename it
   to `top_pump` in the right-hand property panel.
3. Drag a `Channel` from the toolbox onto the canvas. Rename it to
   `heated_channel`.
4. Switch to the Resources tab (Ctrl+2). Add one Geometry (e.g.
   `rect_geom_1`), one Power Shape (e.g. `uniform_ps`), one Fluid
   (e.g. `light_water_1`).
5. Save as `phase69-uat.scp` (Ctrl+Shift+S).

---

## Decision verifications

Each row maps to a CONTEXT.md locked decision (D-01..D-08) or a
RESEARCH.md pitfall (P*) or a research-driven browse/typed edge case
(B*). Tick the `Status` box once the **Expected** outcome is observed.

| #   | Decision  | Action                                                                                                                                  | Expected                                                                                                                                                          | Status |
| --- | --------- | --------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| 1   | D-01      | Inspect `.planning/phases/69-command-palette-jump-only/69-CMDK-AUDIT.md`                                                                | File exists with `Audit verdict: PASS`                                                                                                                            | ☐     |
| 2   | D-02      | Press Ctrl+P                                                                                                                            | Palette appears top-anchored (~80px from top), ~640px wide, dimmed backdrop, input is focused                                                                     | ☐     |
| 3   | D-02      | With palette open, click outside the palette (on the canvas backdrop)                                                                   | Palette dismisses                                                                                                                                                 | ☐     |
| 4   | D-02      | Open palette, press Esc                                                                                                                 | Palette dismisses; if there are pinned code-preview blocks open in the bottom panel, they remain UNCHANGED (Pitfall 6 — App.tsx Esc clear-pins must NOT fire)     | ☐     |
| 5   | D-03      | Open LayersPanel; toggle the **Hydraulic** layer OFF. Open palette (Ctrl+P), type the name of the Pump                                  | Pump appears in results with a small chip on the right showing the Hydraulic accent color (#3b82f6 blue) and text `Hydraulic off — will enable`                   | ☐     |
| 6   | D-03      | Continue from row 5 — click the Pump row                                                                                                | Hydraulic layer toggles back ON visibly in LayersPanel; palette closes; Pump becomes selected on canvas                                                           | ☐     |
| 7   | D-04      | Zoom canvas way out (Ctrl+- repeatedly until labels become illegible). Open palette, jump to a component                                | Canvas re-centers on that node and zooms IN to at least the legibility threshold (`ZOOM_MIN_LEGIBLE = 0.75`); selection ring visible; property panel updated      | ☐     |
| 8   | D-04      | Set canvas zoom to ~1.5 (Ctrl++ a few times). Open palette, jump to a different component                                               | Canvas re-centers but PRESERVES the higher zoom (~1.5) — does NOT zoom out to 0.75                                                                                | ☐     |
| 9   | D-05      | Open palette without typing; locate the **Project Options** row (always visible in browse mode under the `Project` group). Click it     | Left tab switches to **Project**; ModelOptionsPanel is now visible; palette closes                                                                                | ☐     |
| 10  | D-06      | Open palette, type a substring of a Geometry resource name, click the matching row                                                      | Left tab switches to **Resources**; the matching ResourceRow is scrolled into view (centered) and highlighted as selected; property panel reflects the resource   | ☐     |
| 11  | D-07      | Open palette, type `ch` against the `heated_channel` component                                                                          | Result row text shows plain `heated_channel` — there is NO bolded/underlined matched-character highlighting on the `ch` prefix                                    | ☐     |
| 12  | D-08      | Visually compare an off-layer chip for a Hydraulic-only component vs an off-layer chip for a Thermal-only component                     | Hydraulic chip border + text are blue (#3b82f6); Thermal chip is amber (#f59e0b); the two colors visibly differ and match LayersPanel.LAYER_COLORS                | ☐     |
| P1  | Pitfall 1 | Open browser dev-tools alongside the Tauri window if possible. Press Ctrl+P. (Also try with the page focused but no input selected.)    | NO native browser / OS Print dialog appears (no flash, no overlay). Only the palette opens. Repeat 5x to rule out timing flake.                                   | ☐     |
| P2  | Pitfall 2 | Open the dev-tools console. Press Ctrl+P                                                                                                | No `useReactFlow can only be used inside a ReactFlowProvider` error in console; palette renders normally                                                          | ☐     |
| P3  | Pitfall 6 | Pin a CodePreview block in the bottom panel (right-click a node → Pin Code). Open palette, then press Esc                               | Palette closes. Pinned block in bottom panel is UNCHANGED (Radix Dialog's onEscapeKeyDown stops propagation; App.tsx Esc clear-pins handler does NOT double-fire) | ☐     |
| P4  | Pitfall 4 | From repo root: `cd gui && npm ls @radix-ui/react-dialog`                                                                               | Single hoisted version, no duplicate-instance warning, no `WARN ... peer` lines pointing at multiple copies                                                       | ☐     |
| B1  | Browse    | Open palette without typing                                                                                                             | Groups render in order: Components / Geometries / Power Shapes / Fluids / Project. Empty groups are hidden                                                        | ☐     |
| B2  | Typed     | With palette open and items grouped, type any character (e.g. `c`)                                                                      | Group headings disappear; flat ranked list of matches (max 50 rows) is shown                                                                                      | ☐     |
| B3  | Scope     | Close palette. Press **Ctrl+Shift+P**                                                                                                   | Palette does NOT open (out of scope per CONTEXT.md — Ctrl+P-only)                                                                                                 | ☐     |
| B4  | Input     | Click into the ModelOptions `name` text input on the Project tab. With cursor inside the input, press Ctrl+P                            | NO native Print dialog appears (preventDefault still fires); palette also does NOT open (input-focus guard skips the toggle). Cursor stays in the input.          | ☐     |

---

## Post-UAT actions

- Tick every box inline in this file before phase closeout.
- If any row fails, add an entry to the `## Gaps` section below with:
  row number, observed behavior, expected behavior, screenshot path
  (optional). Phase 69 only closes when `## Gaps` is empty.
- Save and commit the updated checklist as the phase verification
  artifact.

## ZOOM_MIN_LEGIBLE tuning

Default: `0.75` (defined in
`gui/src/components/CommandPalette.tsx` as `ZOOM_MIN_LEGIBLE`). If
**row 7** feels too aggressive (the canvas overshoots from a useful
overview), edit that constant and try `0.7`. If labels still feel
cramped at the floor, try `0.8`. Re-run rows 7 + 8 after any change.

Record the final value chosen in `69-03-SUMMARY.md` so future
maintenance has the rationale.

## Gaps

_None — UAT in progress. Append issues here as they are found:_

<!--
Example:
- Row 7: observed canvas zoomed to 1.0 even when starting at 0.25;
  expected zoom floor of 0.75. (screenshot: docs/uat/row7-bug.png)
-->

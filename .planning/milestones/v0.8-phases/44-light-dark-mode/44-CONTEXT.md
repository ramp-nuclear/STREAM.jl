# Phase 44: Light/Dark Mode - Context

**Gathered:** 2026-04-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Users can toggle between Light, Dark, and System themes via a gear icon in the Toolbar. Selection persists across app restarts. All surfaces — shadcn/ui components, ReactFlow canvas, controls, minimap — display correctly in both modes. Does NOT add any new functional capability.

</domain>

<decisions>
## Implementation Decisions

### Settings UI
- **D-01:** Gear icon (⚙ from lucide-react) placed in the **right section of the Toolbar**, alongside the Export button. Opens a `<DropdownMenu>` with three items: Light, Dark, System.
- **D-02:** The dropdown shows a checkmark (or radio indicator) next to the active theme. shadcn `DropdownMenuRadioGroup` or `DropdownMenuCheckboxItem` pattern.
- **D-03:** No full settings panel needed — the dropdown is the entire settings surface for this phase.

### Theme State
- **D-04:** Theme state lives in a small `useTheme` hook (or inline in a `ThemeProvider`-style component). Three values: `"light" | "dark" | "system"`.
- **D-05:** "System" reads `window.matchMedia('(prefers-color-scheme: dark)')` and applies dark/light accordingly. Responds to OS changes via a `change` event listener on the media query.
- **D-06:** Applying theme means toggling the `dark` class on `document.documentElement` — exactly what `index.css`'s `.dark { }` block targets.

### Persistence
- **D-07:** Theme choice persisted via **localStorage** under key `"stream-composer-theme"`. Written on every change, read on app startup (before first render to avoid flash-of-wrong-theme).
- **D-08:** No new dependencies required — no Zustand persist middleware, no Tauri plugin-store.

### ReactFlow Dark Mode
- **D-09:** Pass `colorMode={resolvedTheme === 'dark' ? 'dark' : 'light'}` to `<ReactFlow>` in `CanvasPanel.tsx`. This flips built-in Controls and MiniMap styling automatically.
- **D-10:** For the `<Background>` dots, pass an explicit `color` prop derived from the current theme (e.g., CSS variable `--muted-foreground` value, or a hardcoded `#888` for dark / `#ccc` for light). The Background component doesn't read CSS variables by itself.

### Claude's Discretion
- Exact lucide-react icon choice for the gear (Settings, Cog, or SlidersHorizontal)
- Dropdown positioning (align="end" to not overflow right edge)
- Whether to add a subtle icon change on the gear button when dark mode is active (e.g., Moon icon)
- Flash-of-wrong-theme prevention strategy (inline script in `index.html` or early localStorage read in main.tsx before render)
- Exact dot colors for Background in each theme

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap
- `.planning/ROADMAP.md` §"Phase 44: Light/Dark Mode" — Goal, success criteria (3 items), depends-on Phase 43

### Existing GUI code (read before editing)
- `gui/src/index.css` — Already has full `:root` (light) and `.dark` (dark) OKLCH CSS variable sets; `@custom-variant dark (&:is(.dark *))` for Tailwind dark variant
- `gui/src/App.tsx` — Root component; theme application (`.dark` class toggle) should happen here or in a thin provider wrapping App
- `gui/src/components/Toolbar.tsx` — Add gear icon button + DropdownMenu in the right section (alongside Export button)
- `gui/src/components/CanvasPanel.tsx` — Add `colorMode` prop to `<ReactFlow>` and explicit `color` to `<Background>`
- `gui/src/components/ui/dropdown-menu.tsx` — shadcn DropdownMenu primitives already installed

### No external specs — requirements fully captured in decisions above

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `gui/src/components/ui/dropdown-menu.tsx` — Already installed (used by FileMenu). `DropdownMenuRadioGroup` + `DropdownMenuRadioItem` pattern available for the Light/Dark/System radio selection.
- `lucide-react` — Already installed. `Settings`, `Sun`, `Moon` icons available for the gear button.
- `gui/src/index.css` — `.dark {}` block fully populated with all shadcn/ui token variants (background, foreground, card, sidebar, etc.). Zero CSS work needed — just toggle the class.

### Established Patterns
- **Toolbar right section**: Currently has Export button (`<Button size="sm">`). Gear button should use the same `size="sm"` variant for visual consistency (Phase 43 D-10).
- **DropdownMenu usage**: `FileMenu.tsx` is the reference implementation for a Toolbar dropdown — shows how to wire `<DropdownMenu>`, `<DropdownMenuTrigger>`, `<DropdownMenuContent align="start">`.
- **No persist middleware**: The store uses plain Zustand without persist. Theme preference is simpler than project state and doesn't belong in the undo stack, so localStorage directly is the right call.

### Integration Points
- `document.documentElement.classList` — Toggle `dark` class here to flip all shadcn/ui tokens
- `<ReactFlow colorMode={...}>` in `CanvasPanel.tsx` — single prop addition
- `<Background color={...}>` in `CanvasPanel.tsx` — single prop addition for dot color
- `window.matchMedia('(prefers-color-scheme: dark)')` — used for "System" mode resolution and live OS change tracking

</code_context>

<specifics>
## Specific Ideas

- Gear icon (⚙) in Toolbar right section opens dropdown — not a floating button, not inside FileMenu
- Light / Dark / System as three radio options in the dropdown
- localStorage key: `"stream-composer-theme"`

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 44-light-dark-mode*
*Context gathered: 2026-04-04*

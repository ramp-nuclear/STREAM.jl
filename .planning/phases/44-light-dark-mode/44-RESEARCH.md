# Phase 44: Light/Dark Mode - Research

**Researched:** 2026-04-04
**Domain:** CSS theming, ReactFlow dark mode, localStorage persistence
**Confidence:** HIGH

## Summary

Phase 44 adds a Light/Dark/System theme toggle to the STREAM Composer GUI. The existing codebase is exceptionally well-prepared: `index.css` already defines complete `:root` (light) and `.dark` (dark) OKLCH CSS variable sets for all shadcn/ui design tokens, and Tailwind v4 is configured with `@custom-variant dark (&:is(.dark *))` for dark variant support. The entire theme switch reduces to toggling the `dark` class on `document.documentElement`.

ReactFlow v12.10.2 (installed) supports a `colorMode` prop that accepts `"dark"` or `"light"` and applies appropriate styling to Controls, MiniMap, and the canvas container. The `Background` component does not read CSS variables and needs an explicit `color` prop. The shadcn/ui `DropdownMenuRadioGroup` + `DropdownMenuRadioItem` primitives are already installed and exported from the project's `dropdown-menu.tsx`.

**Primary recommendation:** Create a `useTheme` hook managing `"light" | "dark" | "system"` state with localStorage persistence, a `ThemeProvider` wrapper that applies the `dark` class, a gear icon `DropdownMenu` in the Toolbar right section, and `colorMode` + background `color` props on `ReactFlow` and `Background` in CanvasPanel. Add a blocking inline script in `index.html` to prevent flash-of-wrong-theme.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Gear icon (lucide-react) placed in the right section of the Toolbar, alongside the Export button. Opens a `<DropdownMenu>` with three items: Light, Dark, System.
- **D-02:** The dropdown shows a checkmark (or radio indicator) next to the active theme. shadcn `DropdownMenuRadioGroup` or `DropdownMenuCheckboxItem` pattern.
- **D-03:** No full settings panel needed -- the dropdown is the entire settings surface for this phase.
- **D-04:** Theme state lives in a small `useTheme` hook (or inline in a `ThemeProvider`-style component). Three values: `"light" | "dark" | "system"`.
- **D-05:** "System" reads `window.matchMedia('(prefers-color-scheme: dark)')` and applies dark/light accordingly. Responds to OS changes via a `change` event listener on the media query.
- **D-06:** Applying theme means toggling the `dark` class on `document.documentElement` -- exactly what `index.css`'s `.dark { }` block targets.
- **D-07:** Theme choice persisted via localStorage under key `"stream-composer-theme"`. Written on every change, read on app startup (before first render to avoid flash-of-wrong-theme).
- **D-08:** No new dependencies required -- no Zustand persist middleware, no Tauri plugin-store.
- **D-09:** Pass `colorMode={resolvedTheme === 'dark' ? 'dark' : 'light'}` to `<ReactFlow>` in `CanvasPanel.tsx`.
- **D-10:** For the `<Background>` dots, pass an explicit `color` prop derived from the current theme.

### Claude's Discretion
- Exact lucide-react icon choice for the gear (Settings, Cog, or SlidersHorizontal)
- Dropdown positioning (align="end" to not overflow right edge)
- Whether to add a subtle icon change on the gear button when dark mode is active (e.g., Moon icon)
- Flash-of-wrong-theme prevention strategy (inline script in `index.html` or early localStorage read in main.tsx before render)
- Exact dot colors for Background in each theme

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SC-1 | A settings button (gear icon) opens a settings panel or dropdown | DropdownMenu + DropdownMenuRadioGroup already installed in `ui/dropdown-menu.tsx`; lucide-react `Settings` icon available; Toolbar right section pattern established |
| SC-2 | Light/Dark/System options available; selection persists across sessions | localStorage API for persistence; `useTheme` hook with `matchMedia` listener for system mode; blocking script in index.html prevents FOUC |
| SC-3 | All shadcn/ui components display correctly in both themes | All CSS variables already defined in both `:root` and `.dark` blocks in `index.css`; toggling `.dark` class on `<html>` is sufficient |
| SC-4 | ReactFlow canvas background and node colors adapt to the active theme | ReactFlow v12 `colorMode` prop on `<ReactFlow>` handles Controls/MiniMap; `Background` needs explicit `color` prop; StreamNode uses `bg-card` (CSS variable) so it adapts automatically |
| SC-5 | Amber thermal edges and red error rings remain legible in both themes | Amber (#f59e0b) and red (--destructive) are high-contrast against both light and dark backgrounds; verify visually |
</phase_requirements>

## Standard Stack

### Core (already installed -- no new dependencies)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| @xyflow/react | 12.10.2 | Canvas with `colorMode` prop | Already installed; built-in dark mode support |
| radix-ui | 1.4.3 | DropdownMenuRadioGroup primitive | Already installed via shadcn/ui |
| lucide-react | 1.7.0 | Settings/Sun/Moon icons | Already installed |
| zustand | 5.0.12 | Store (NOT used for theme -- localStorage directly) | Already installed |

### Supporting
None -- no new dependencies needed (D-08).

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Raw useTheme hook | next-themes | Overkill for Tauri app; Next.js-specific patterns; adds a dependency for ~30 lines of code |
| localStorage | Tauri plugin-store | Unnecessary complexity; localStorage works fine in WebView |
| Zustand persist | localStorage directly | Theme doesn't belong in undo stack; simpler to manage outside Zustand |

## Architecture Patterns

### New Files
```
gui/src/
  hooks/
    useTheme.ts              # Theme hook: state, localStorage, matchMedia listener
  components/
    ThemeMenu.tsx             # Gear icon + DropdownMenuRadioGroup (Light/Dark/System)
```

### Modified Files
```
gui/index.html               # Inline <script> for FOUC prevention
gui/src/App.tsx               # Import useTheme, call it for side effects (class toggle)
gui/src/components/Toolbar.tsx        # Add ThemeMenu in right section
gui/src/components/CanvasPanel.tsx    # Add colorMode + Background color props
```

### Pattern 1: useTheme Hook
**What:** A standalone React hook that manages theme state, localStorage persistence, `matchMedia` listener for "system" mode, and `document.documentElement.classList` toggling.
**When to use:** Called once in App.tsx (or a thin ThemeProvider). Returns `{ theme, resolvedTheme, setTheme }`.

```typescript
// gui/src/hooks/useTheme.ts
type Theme = "light" | "dark" | "system";

const STORAGE_KEY = "stream-composer-theme";

function getSystemTheme(): "light" | "dark" {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function applyTheme(resolved: "light" | "dark") {
  document.documentElement.classList.toggle("dark", resolved === "dark");
}

export function useTheme() {
  const [theme, setThemeState] = useState<Theme>(() => {
    return (localStorage.getItem(STORAGE_KEY) as Theme) || "system";
  });

  const resolvedTheme = theme === "system" ? getSystemTheme() : theme;

  // Apply class on mount and when theme changes
  useEffect(() => {
    applyTheme(resolvedTheme);
  }, [resolvedTheme]);

  // Listen for OS theme changes when in "system" mode
  useEffect(() => {
    if (theme !== "system") return;
    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const handler = () => applyTheme(getSystemTheme());
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, [theme]);

  const setTheme = useCallback((newTheme: Theme) => {
    localStorage.setItem(STORAGE_KEY, newTheme);
    setThemeState(newTheme);
  }, []);

  return { theme, resolvedTheme, setTheme };
}
```

### Pattern 2: FOUC Prevention via Inline Script
**What:** A synchronous inline script in `index.html` `<head>` that reads localStorage and applies the `dark` class before the first paint.
**When to use:** Always -- prevents the white flash when the user has dark mode selected.

```html
<!-- gui/index.html, inside <head> before any CSS -->
<script>
  (function() {
    var theme = localStorage.getItem("stream-composer-theme") || "system";
    var dark = theme === "dark" ||
      (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
    if (dark) document.documentElement.classList.add("dark");
  })();
</script>
```

### Pattern 3: ThemeMenu Component
**What:** A dropdown menu triggered by a gear icon button, using `DropdownMenuRadioGroup` for Light/Dark/System selection with radio indicators.
**When to use:** Placed in Toolbar right section.

```typescript
// gui/src/components/ThemeMenu.tsx
import { Settings, Sun, Moon } from "lucide-react";
import { Button } from "./ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuRadioGroup,
  DropdownMenuRadioItem,
  DropdownMenuTrigger,
} from "./ui/dropdown-menu";

interface Props {
  theme: "light" | "dark" | "system";
  setTheme: (theme: "light" | "dark" | "system") => void;
}

export default function ThemeMenu({ theme, setTheme }: Props) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="outline" size="sm">
          <Settings className="h-4 w-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        <DropdownMenuRadioGroup value={theme} onValueChange={setTheme}>
          <DropdownMenuRadioItem value="light">
            <Sun className="h-4 w-4 mr-2" /> Light
          </DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="dark">
            <Moon className="h-4 w-4 mr-2" /> Dark
          </DropdownMenuRadioItem>
          <DropdownMenuRadioItem value="system">System</DropdownMenuRadioItem>
        </DropdownMenuRadioGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
```

### Pattern 4: ReactFlow colorMode Integration
**What:** Pass `colorMode` prop to `<ReactFlow>` and explicit `color` to `<Background>`.
**When to use:** In CanvasPanel.tsx.

```typescript
// In CanvasPanel.tsx
<ReactFlow
  colorMode={resolvedTheme === "dark" ? "dark" : "light"}
  // ... existing props
>
  <Controls />
  <MiniMap />
  <Background
    variant={BackgroundVariant.Dots}
    color={resolvedTheme === "dark" ? "#555" : "#ccc"}
  />
</ReactFlow>
```

ReactFlow v12's `colorMode` prop applies a `dark` class to the `.react-flow` container, which flips built-in Controls and MiniMap styles automatically. The `Background` component does not respond to `colorMode` -- it requires an explicit `color` prop.

### Anti-Patterns to Avoid
- **Storing theme in Zustand:** Theme doesn't belong in the undo/redo stack. It's UI preference, not project state. Use localStorage directly.
- **Using Tailwind `dark:` variant classes for ReactFlow internals:** ReactFlow's internal elements don't read Tailwind classes. Use the `colorMode` prop instead.
- **Applying dark class to `<body>` instead of `<html>`:** The CSS uses `.dark { ... }` on `:root` (html element). The Tailwind dark variant selector `&:is(.dark *)` also expects the class on an ancestor -- `documentElement` is correct.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Radio selection in dropdown | Custom checkbox tracking | `DropdownMenuRadioGroup` + `DropdownMenuRadioItem` | Already installed; handles ARIA, keyboard nav, radio indicator |
| OS theme detection | Custom window event listener boilerplate | `window.matchMedia('(prefers-color-scheme: dark)')` | Standard Web API; `.addEventListener("change", ...)` handles live OS changes |
| ReactFlow dark controls/minimap | Custom CSS overrides for .react-flow__controls | `colorMode` prop on `<ReactFlow>` | Built-in v12 feature; handles all internal styling |

## Common Pitfalls

### Pitfall 1: Flash of Wrong Theme (FOUC)
**What goes wrong:** User sees a white flash on startup when dark mode is selected, because React hydration happens after the first paint.
**Why it happens:** `useTheme` runs after React mounts, which is after the browser has already painted the initial white background.
**How to avoid:** Add a synchronous blocking `<script>` in `index.html` `<head>` that reads localStorage and applies the `dark` class before any rendering occurs.
**Warning signs:** Visible white-to-dark flash on app startup.

### Pitfall 2: matchMedia Listener Leak
**What goes wrong:** OS theme changes stop being detected, or listeners accumulate.
**Why it happens:** Not cleaning up the `addEventListener("change", ...)` when the component unmounts or theme switches away from "system".
**How to avoid:** Return a cleanup function from `useEffect` that calls `removeEventListener`. Only attach the listener when `theme === "system"`.
**Warning signs:** Memory leak warnings; theme stops responding to OS changes.

### Pitfall 3: Background Dots Invisible in Dark Mode
**What goes wrong:** The default dot color (`#aaa` or similar) blends into the dark canvas background.
**Why it happens:** ReactFlow's `<Background>` component uses a fixed color that doesn't respond to `colorMode` or CSS variables.
**How to avoid:** Pass an explicit `color` prop that varies by `resolvedTheme`. Use `#555` for dark (visible against dark bg) and `#ccc` for light.
**Warning signs:** Canvas appears to have no dot grid in dark mode.

### Pitfall 4: Hardcoded Hex Colors Not Adapting
**What goes wrong:** StreamNode components using hardcoded hex colors (blue handles, amber thermal handles) might look wrong on dark backgrounds.
**Why it happens:** The handle colors (#60a5fa, #f59e0b, #f87171) are medium-saturation and remain legible on both light and dark backgrounds. The node body uses `bg-card` (CSS variable) which adapts automatically.
**How to avoid:** Verify visually. The current colors are designed to work on both backgrounds. The error ring uses `var(--destructive)` which has dark-mode-specific OKLCH values in `index.css`.
**Warning signs:** Low contrast handles or invisible error indicators.

### Pitfall 5: Toolbar Layer Toggle Colors in Dark Mode
**What goes wrong:** The `data-[state=on]:bg-blue-500/25` and `data-[state=on]:text-blue-700` Tailwind classes on layer toggle items may have low contrast in dark mode.
**Why it happens:** `text-blue-700` is a dark blue that may be hard to read on a dark muted background.
**How to avoid:** Either add `dark:` variant overrides for the toggle items, or use lighter color values that work in both modes (e.g., `text-blue-400` for dark).
**Warning signs:** Layer toggle text barely visible in dark mode.

### Pitfall 6: Amber Edge Detection via Hardcoded Color Check
**What goes wrong:** `CanvasPanel.tsx` line 74 checks `edge.style?.stroke === "#f59e0b"` to detect thermal edges.
**Why it happens:** This is a string comparison against a hex value. If the amber color were changed for dark mode, this detection would break.
**How to avoid:** Do NOT change the thermal edge stroke color between themes. The amber color (#f59e0b) is legible on both light and dark backgrounds, and changing it would break the thermal edge detection logic. If ever needed in the future, refactor to use a data attribute instead.
**Warning signs:** Thermal edges lose their dimming behavior in layer filtering.

## Code Examples

### Existing Dropdown Pattern (from FileMenu.tsx)
```typescript
// Reference: gui/src/components/FileMenu.tsx lines 49-83
<DropdownMenu>
  <DropdownMenuTrigger asChild>
    <Button variant="outline" size="sm">...</Button>
  </DropdownMenuTrigger>
  <DropdownMenuContent align="start">
    <DropdownMenuItem onClick={handleNew}>...</DropdownMenuItem>
  </DropdownMenuContent>
</DropdownMenu>
```

### Existing StreamNode Theme Compatibility
```typescript
// Reference: gui/src/components/StreamNode.tsx line 52
// Uses CSS variable classes that already adapt to .dark:
className="border rounded-[var(--radius)] bg-card p-2 min-w-[140px]"
// bg-card resolves to oklch(1 0 0) in light, oklch(0.205 0 0) in dark
// border uses --border which also adapts
```

### ReactFlow colorMode TypeScript
```typescript
// @xyflow/react v12 exports ColorMode type
import { ReactFlow, type ColorMode } from "@xyflow/react";
// colorMode accepts: "dark" | "light" | "system"
// For this project, pass resolved value (not "system") since we manage system detection ourselves
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| CSS class toggle only | ReactFlow `colorMode` prop | @xyflow/react v12 | Built-in dark mode for Controls, MiniMap, canvas |
| Manual MiniMap color overrides | `colorMode` handles it | v12 | No custom CSS needed for minimap |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | vitest 4.1.2 |
| Config file | `gui/vitest.config.ts` |
| Quick run command | `cd gui && npx vitest run --passWithNoTests` |
| Full suite command | `cd gui && npx vitest run` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SC-1 | Gear icon opens dropdown with theme options | component (jsdom) | `cd gui && npx vitest run src/components/__tests__/ThemeMenu.test.tsx` | Wave 0 |
| SC-2 | Selection persists via localStorage | unit | `cd gui && npx vitest run src/hooks/__tests__/useTheme.test.ts` | Wave 0 |
| SC-3 | All shadcn/ui components correct in both themes | manual | Visual inspection | N/A (CSS variable completeness verified by reading index.css) |
| SC-4 | ReactFlow canvas adapts to theme | unit | `cd gui && npx vitest run src/components/__tests__/CanvasPanel.test.tsx` | Wave 0 |
| SC-5 | Amber edges and red error rings legible | manual | Visual inspection | N/A (color contrast) |

### Sampling Rate
- **Per task commit:** `cd gui && npx vitest run --passWithNoTests`
- **Per wave merge:** `cd gui && npx vitest run`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `gui/src/hooks/__tests__/useTheme.test.ts` -- covers SC-2 (localStorage read/write, system detection)
- [ ] `gui/src/components/__tests__/ThemeMenu.test.tsx` -- covers SC-1 (dropdown renders, radio selection works)

Note: SC-3, SC-4, SC-5 are primarily visual and cannot be fully automated. SC-4 can be partially tested by verifying `colorMode` prop is passed to ReactFlow, but this requires jsdom environment with ReactFlow mocking.

## Sources

### Primary (HIGH confidence)
- `gui/src/index.css` -- Verified complete `:root` and `.dark` CSS variable sets (lines 6-73)
- `gui/src/components/ui/dropdown-menu.tsx` -- Verified `DropdownMenuRadioGroup` and `DropdownMenuRadioItem` exports (lines 109, 120, 248-249)
- `gui/node_modules/@xyflow/react/dist/esm/index.mjs` -- Verified `colorMode` prop and `useColorModeClass` hook (line 339ff)
- `gui/src/components/StreamNode.tsx` -- Verified `bg-card` CSS variable usage and hardcoded handle colors
- `gui/src/components/CanvasPanel.tsx` -- Verified current `<ReactFlow>` and `<Background>` usage, thermal edge detection logic (line 74)

### Secondary (MEDIUM confidence)
- ReactFlow v12 documentation on `colorMode` prop -- confirmed by source code inspection of installed package

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all libraries already installed, versions verified from package.json
- Architecture: HIGH -- patterns derived from existing codebase conventions (FileMenu, Toolbar), user decisions locked
- Pitfalls: HIGH -- identified from direct code inspection of hardcoded colors, thermal edge detection, and FOUC risk

**Research date:** 2026-04-04
**Valid until:** 2026-05-04 (stable -- no fast-moving dependencies)

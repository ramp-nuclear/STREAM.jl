# Phase 67: Custom titlebar - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-16
**Phase:** 67-custom-titlebar
**Areas discussed:** Toolbar disposition, Edit/View/Help menu content, Window controls platform handling, Titlebar height & icon

---

## Toolbar disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Keep a second toolbar row | Toolbar.tsx stays below the titlebar as a reduced second strip. Score 6.5/10. | |
| One combined strip — titlebar IS the toolbar | Everything in one 36px strip. Score 7.5/10. | |
| Titlebar + slim secondary strip | Titlebar holds window chrome + menus; separate strip holds canvas controls. Score 8/10. | ✓ |

**User's choice:** Titlebar + slim secondary strip — "would look the best if done really properly."
**Notes:** User also gave meta-feedback: lead with the recommended option in AskUserQuestion calls, not just the highest-score one.

### Follow-up: Secondary strip width

| Option | Description | Selected |
|--------|-------------|----------|
| Full width (Recommended) | Spans left panel + canvas + right panel. Score 8.5/10. | ✓ |
| Center column only | Scoped to canvas column. Score 6.5/10. | |

### Follow-up: ThemeMenu placement

| Option | Description | Selected |
|--------|-------------|----------|
| View menu → Theme submenu (Recommended) | Folds into View menu. Score 8/10. | ✓ |
| Stays in secondary strip as Settings gear | Score 6.5/10. | |

**User's notes on themes:** User wants infrastructure for more than three themes (Light/Dark/System) in the future — noted as deferred idea for Phase 72.

---

## Edit / View / Help menu content

### Edit menu

| Option | Description | Selected |
|--------|-------------|----------|
| Undo / Redo + canvas clipboard (Recommended) | Undo, Redo, Cut, Copy, Paste, Duplicate. Score 8.5/10. | ✓ |
| Undo / Redo only | Score 6/10. | |
| Skip Edit menu | Score 4/10. | |

### View menu

| Option | Description | Selected |
|--------|-------------|----------|
| Theme + Code Preview toggle + Layer shortcuts (Recommended) | All three items. Score 8/10. | ✓ |
| Theme + Code Preview toggle only | Score 6.5/10. | |
| Theme submenu only | Score 5/10. | |

### Help menu

**User raised a question:** "what about the cheatsheet thing we talked about? Where does it fit? what about the settings too?"

Resolution: The canvas cheatsheet and Settings dialog are Phase 72 deliverables. Phase 67 adds disabled stubs for them.

| Option | Description | Selected |
|--------|-------------|----------|
| Add disabled stubs now (Recommended) | Greyed-out Keyboard Shortcuts and Preferences items in Phase 67. Score 8.5/10. | ✓ |
| Leave them out, Phase 72 adds them | Score 7/10. | |

### Settings placement

| Option | Description | Selected |
|--------|-------------|----------|
| Edit → Preferences (Recommended) | Conventional desktop-app placement. Score 8/10. | ✓ |
| View → Settings | Score 6.5/10. | |
| Help → Settings | Score 5/10. | |

**Final Help menu items:** About STREAM Composer + Keyboard Shortcuts (disabled).

---

## Window controls platform handling

### Position + style

| Option | Description | Selected |
|--------|-------------|----------|
| Uniform: always right-side, Windows convention (Recommended) | No platform detection. Score 8/10. | |
| Adapt to platform | Platform detection + different visual paths. | Partial ✓ |

**User's choice (clarified via freeform):** "Do adapt to platform, BUT put them on the right side always. You can adapt style and button type to look correct for each platform, but always on the right side."

### Adaptation level

| Option | Description | Selected |
|--------|-------------|----------|
| macOS circles + traffic-light colors; Windows/Linux icon buttons (Recommended) | Two visual paths, one platform check. Score 8/10. | ✓ |
| Identical style everywhere | No platform detection. Score 7.5/10. | |
| You decide | N/A. | |

### Close button hover color

| Option | Description | Selected |
|--------|-------------|----------|
| Red (Recommended) | Universal convention. Score 9/10. | ✓ |
| Destructive accent from theme | Score 7/10. | |
| You decide | N/A. | |

---

## Titlebar height & icon

### Height

**User's answer:** "I lean towards point 1 (36px replacing current Toolbar), but I want it to feel slim. No dead space."

| Option | Description | Selected |
|--------|-------------|----------|
| 36px titlebar replaces current Toolbar (Recommended) | h-9, same as existing Toolbar. Score 8.5/10. | ✓ |
| 32px titlebar + Toolbar stays 36px | Score 6.5/10. | |

### Icon

**User's answer:** "Take the placeholder 32x32.png icon. I will give you one to replace it with soon. Also there needs to be an icon in the taskbar / window that I'll provide later."

| Option | Description | Selected |
|--------|-------------|----------|
| icons/32x32.png (Recommended) | Existing placeholder. Score 9/10. | ✓ |
| icons/128x128.png downscaled | Score 7/10. | |
| No icon | Score 5/10. | |

### Visual treatment between strips

| Option | Description | Selected |
|--------|-------------|----------|
| Subtle border / divider line (Recommended) | 1px border-b between strips. Score 8.5/10. | ✓ |
| Same background, no separator | Score 6.5/10. | |

---

## Claude's Discretion

- Exact CSS for the macOS circle buttons at rest (dim factor, circle size, border radius)
- Component file names (`CustomTitlebar.tsx`, `SecondaryToolbar.tsx` or reuse `Toolbar.tsx`)
- Whether `platform()` call is memoized at mount or called at render
- "About" dialog implementation (shadcn `Dialog` is the obvious choice)

## Deferred Ideas

- **Extended theme palette**: more than Light/Dark/System — Phase 72
- **Custom app icon + taskbar icon**: user will provide assets; no phase assigned
- **Keyboard Shortcuts / Cheatsheet content**: Phase 72 (stub added in Phase 67)
- **Settings / Preferences dialog content**: Phase 72 (stub added in Phase 67)

# Claude Code Skills for STREAM Composer — Research & Recommendations

**Date:** 2026-05-19
**Author:** Research notes from a Claude Code session, web search across Anthropic skill marketplace + GitHub `claude-code-skills` repos + Reddit/blog reviews.
**Purpose:** Pre-flight reference for a future `/gsd:explore` session that will produce a project-local `DESIGN.md`. Curate which Claude Code skills are worth installing for STREAM Composer's GUI work, and — more importantly — which to AVOID because they push toward generic SaaS dashboards / landing pages.
**Status:** read-only reference. Do not treat as a design contract. The actual contract lives in the `DESIGN.md` we haven't written yet.

---

## Project context (so future-you remembers the constraints)

STREAM Composer is a **Tauri desktop app** (React + xyflow + shadcn + Tailwind) for visually composing thermal-hydraulics simulations that compile to Julia / ModelingToolkit code. It is NOT:

- a SaaS dashboard
- a marketing site
- a generic CRUD app
- a consumer product

The visual reference points: **VSCode, Blender, Photoshop, MATLAB, Mathematica.** Restrained, intentional, professional-scientific-tool aesthetics — not the gradient/glass/empty-state dashboard Claude generates by default.

Design preferences already established for this project (the "do not regress" list):

- VSCode-style zone-based depth (chrome darkest → panels mid → working surfaces lightest).
- Custom Tauri titlebar with menubar (no OS chrome).
- ReactFlow canvas with custom node visuals, no MiniMap, no attribution badge.
- Off-state indicators use muted-gray `EyeOff` icons (LayersPanel vocabulary) — NOT colored chips with explanatory text.
- Inputs auto-select-on-focus across the whole app (single shadcn `<Input>` chokepoint).
- Tooltips / `title` attributes for detail-on-demand instead of inline explanatory text.
- shadcn + Radix primitives only; no random third-party UI kits.
- No decorative empty states, no cutesy illustrations, no purple gradients.

---

## TL;DR

The Claude Code design-skill ecosystem is overwhelmingly aimed at **landing pages, SaaS dashboards, and "make my marketing site look like Stripe."** Almost every popular skill assumes that goal and will actively push your app toward gradients, distinctive display fonts, and asymmetric hero layouts — the exact AI-slop you're trying to avoid, often re-introduced under a different name. **There is no skill purpose-built for scientific desktop tools** (Tauri / MATLAB / Blender / VSCode-style). The useful subset is small, and most of the value is in **audit**, **tokens**, and **motion-discipline** skills rather than generation skills.

**Three-skill minimum stack to actually install:**

1. **`shadcn/ui` Skills** (component picking inside your existing system) — install and forget.
2. **`kylezantos/design-motion-principles`** in audit-mode only — run before each PR that touches interactive panels.
3. **A project-local `DESIGN.md`** that codifies STREAM-specific aesthetic rules (use `/gsd:explore` to draft, point it at this research doc + the project preferences above).

Optional later: fork **`Ashutos1997/claude-design-auditor-skill`** and replace its generic rules with STREAM-specific ones to get a real "is this PR consistent with the scientific-tool aesthetic" linter.

---

## Category 1 — Foundational philosophy ("anti-slop" framing)

### `anthropics/skills/frontend-design` — official Anthropic, ~277k installs

- **Where:** `github.com/anthropics/skills`, path `skills/frontend-design`.
- **What it does:** Runs an "art director" pre-pass that forces Claude to commit to an aesthetic (brutalist / minimalist / maximalist / etc.), bans Inter / Roboto / Arial / Space Grotesk, and bans purple-gradient-on-white.
- **Fit for STREAM:** The anti-slop framing is genuinely real — "decide on a tone first" is exactly the discipline we've been forcing manually. BUT its own examples lean hard into asymmetric layouts, gradient meshes, noise/grain overlays, scroll-trigger animation, and bold display typography. For ReactFlow + dense panels that is poison.
- **How to use it:** Quote the anti-slop principles into your `DESIGN.md` / `CLAUDE.md` as a **philosophy primer**, do not invoke it as an active skill on canvas/panel work. Or fork it and strip the marketing-page guidance.
- **Score: 6.5/10** — load-bearing for the right *mindset*, dangerous if invoked verbatim.

### `VoltAgent/awesome-claude-design` + upstream `awesome-design-md`

- **Where:** `github.com/VoltAgent/awesome-claude-design` (68 `DESIGN.md` files), upstream `awesome-design-md` (~55 reverse-engineered systems: Stripe, Linear, Vercel, Notion, Supabase, etc.).
- **What it does:** Provides reference `DESIGN.md` files cataloguing major design systems' tokens / typography / spacing / motion.
- **Fit for STREAM:** The **format** is good — shipping one source-of-truth doc in the repo so the agent stops re-inventing tokens is exactly what we want. The **shipped systems** are all SaaS/devtools, none scientific. Linear and Vercel are closest to your aesthetic (restrained, monochrome, dense); their token math is worth selectively cribbing. **DO NOT** `cp linear.md DESIGN.md` — it'll pull you toward Linear's purple accent and marketing-page tropes.
- **How to use it:** Borrow the file structure. Write your own contents.
- **Score: 7/10 as a template format, 4/10 as a drop-in.**

---

## Category 2 — Design tokens, depth, dark theme

### `bitjaru/styleseed` — 354★, active (v2.1.1 April 2026)

- **Where:** `github.com/bitjaru/styleseed`.
- **What it does:** 69 "design rules" + 48 shadcn components + Tailwind v4 + Radix, with brand skins for Toss / Stripe / Linear / Vercel / Notion.
- **Fit for STREAM:** The **rules** are decent (semantic tokens, spatial rhythm, elevation discipline) and framework-agnostic enough for a desktop app. The **skins** are pure SaaS — Toss is a Korean fintech, Stripe is payments marketing. Apply the rules; do not apply the skins. Linear's dark token math is the only one I'd selectively borrow for your panels-mid vs canvas-light zone palette.
- **Score: 7/10 if you use rules only, 3/10 if you let it pick a skin.**

### `jugyo/vscode-theme-skill`

- **Where:** `github.com/jugyo/vscode-theme-skill`.
- **What it does:** Tiny skill that generates VSCode color themes.
- **Fit for STREAM:** Indirectly useful — you can ask it to *derive your shadcn CSS vars from a VSCode theme JSON* (One Dark Pro, GitHub Dark, Tokyo Night) to keep your zone-based depth honest. Niche; low star count; low risk.
- **Score: 6/10** — a clever 30-minute hack, not a foundation.

---

## Category 3 — Layout, hierarchy, dense-UI discipline

### `imsaif/design-with-claude` — 37 specialist agents

- **Where:** `github.com/imsaif/design-with-claude`.
- **What it does:** 37 markdown-only "specialists" you invoke per-PR.
- **Fit for STREAM:** Useful for *Visual Hierarchy*, *Spacing/Layout*, *Information Architect*, *Table Designer*, *Dark Mode*, *Icon/Illustration*. **Skip** *Landing Page*, *Auth/Security UX*, *Onboarding*, *Empty/Loading States* (the last one in particular generates exactly the cutesy illustrations you've been removing).
- **Caveat:** Reported metrics weak (~5 stars when fetched). Probably a fresh repo. Treat as unproven.
- **How to use it:** As a *routing index* ("for this PR I want the Visual Hierarchy lens") rather than a generator. The depth of each agent is shallow — each is a short prompt, not a real skill.
- **Score: 5.5/10** — low signal because unproven and shallow, but the routing pattern is correct.

### `kylezantos/design-engineer-auditor-package` (a.k.a. `design-motion-principles`)

**Most-recommended of the bunch.**

- **Where:** `github.com/kylezantos/design-engineer-auditor-package`.
- **What it does:** Two modes. **Build** mode generates web-product motion (spring overshoots, hero scroll choreography). **Audit** mode flags "conditional renders without AnimatePresence, dynamic styles without transitions, instant state swaps." Distilled from Emil Kowalski / Jakub Krehel / Jhey Tompkins.
- **Fit for STREAM:** The audit mode catches exactly the polish gap between generated and hand-crafted UI — the kind of paper-cut that makes the app feel "not quite right" without you being able to name why. The build mode is wrong for a node editor; ignore it.
- **How to use it:** Audit-only. Run before any PR touching interactive panels.
- **Score: 8/10 for audit-only use.**

---

## Category 4 — Visual / design review (audit after the fact)

### `Ashutos1997/claude-design-auditor-skill`

- **Where:** `github.com/Ashutos1997/claude-design-auditor-skill`. Low stars, but the format is sound.
- **What it does:** 19 named rules, agent reads files and flags violations, no browser dependency. Rule-based static audit (contrast, spacing scale, semantic tokens, button vs link misuse).
- **Fit for STREAM:** Closest match to what you actually want — a checklist that runs on the JSX, not on a screenshot. The rule list is generic-web; you'd want to fork it and add STREAM-specific rules:
  - "off-state uses muted EyeOff, never colored chips with text"
  - "inputs go through the shadcn chokepoint"
  - "no MiniMap on ReactFlow"
  - "no inline explanatory text where a tooltip works"
  - "no purple gradients, no glass effects, no decorative noise"
  - "node visuals follow port/handle pattern not card pattern"
- **Score: 7/10 as a fork-and-customize base, 4/10 stock.**

### Playwright-based "Design Review" skill (`mcpmarket.com`)

- **What it does:** 7-phase methodology + responsive validation across 7 viewports + WCAG 2.1 AA scan.
- **Fit for STREAM:** Playwright-driven, so it needs a live URL. Tauri's webview is reachable in dev (`vite` localhost), so it can work, but the *responsive across 7 viewports* part is meaningless for a desktop app at a fixed window size. Accessibility scan and "is this state actually animated" check are the only parts worth keeping. **Your existing `gsd:ui-review` is probably better** because it's already retroactive and doesn't assume responsive.
- **Score: 5.5/10.**

---

## Category 5 — shadcn / component composition

### `shadcn/ui` official Skills (`ui.shadcn.com/docs/skills`)

**Install this one, no caveats.**

- **What it does:** First-party from the shadcn team. Project-aware — reads your `components.json`, your token vars, your Tailwind config, then proposes additions that match.
- **Fit for STREAM:** Doesn't push aesthetic decisions on you; only enforces internal consistency. This is just *correct*.
- **Score: 9/10 — install, no real caveats beyond the usual "review every diff."**

### `masonjames/Shadcnblocks-Skill` — 2,500+ shadcn blocks

- **Where:** `github.com/masonjames/Shadcnblocks-Skill`.
- **What it does:** Indexes 2,500+ shadcn blocks/components and helps Claude pick + install + compose.
- **Fit for STREAM:** Useful **only for non-canvas panels** — the Properties panel, command palette, form modals, dialog content. For the canvas, titlebar, and LayersPanel it's worse than nothing — blocks are SaaS-shaped (pricing tables, hero sections, dashboard cards). Scope tightly.
- **Score: 6/10, conditional on you only invoking it for non-canvas panels.**

---

## Category 6 — What does NOT exist (be honest about the gap)

- **No skill for node-graph editors / ReactFlow-specific design.** Superdesign and friends generate page-shaped artifacts. Your canvas patterns (port glyphs, edge handles, group nodes, layer-panel vocabulary) have no prior art in the skill ecosystem. You'll have to capture these yourself in `DESIGN.md`.
- **No skill modeled on Blender / MATLAB / Mathematica / Photoshop aesthetics.** Apple HIG skills (`axiaoge2/Apple-Hig-Designer`, `vabole/apple-skills`) exist but target iOS/macOS Liquid Glass — wrong universe.
- **No skill for Tauri desktop chrome / custom titlebar.** Project-local rules only.
- **`UI/UX Pro Max`** (claimed 29k stars). Reddit threads and Snyk's writeup are upbeat, but inspecting the prompt shows it's tuned for "landing pages, portfolio sites, marketing pages." Star count is also suspicious-looking (fast accumulation, low fork ratio). **Flagged as marketing fluff for your use case. Score: 2/10. Skip.**
- **`UI Pro Max`-style mega-skills generally** — the "240+ styles, 127 font pairings" framing is exactly the distributive convergence the official Anthropic skill warns against, just packaged with more knobs.

---

## Meta-recommendation

Three-skill minimum stack, with everything else as one-off invocations:

1. **`shadcn/ui` Skills** — install and forget. Enforces internal token / component consistency.
2. **`kylezantos/design-motion-principles` in audit-mode only** — run before each PR touching interactive panels. Catches the "doesn't quite feel hand-crafted" paper-cuts.
3. **A project-local `DESIGN.md`** at `gui/DESIGN.md` (or `.claude/skills/stream-design/SKILL.md` if you want it agent-discoverable). Use Voltagent's template structure, don't use their content. Capture:
   - zone-based depth tokens (chrome / panel / surface)
   - typography choices (mono for code preview, sans for chrome, no display fonts)
   - spacing scale, border-radius scale, elevation scale
   - the EyeOff off-state rule
   - the input-chokepoint rule
   - the no-MiniMap / no-attribution / no-OS-chrome rules
   - tooltip-not-inline-text rule
   - "off-layer indicator is muted gray, never accent color"
   - "no purple gradients ever"
   - "no decorative empty states"
   - "node visuals follow handle pattern not card pattern"
   - "default to terse, professional language; no marketing copy"
   - Tauri titlebar spec
   - Reference Anthropic `frontend-design` skill's anti-slop philosophy (quote the principles, drop the marketing examples)

Optional fork-and-customize down the road: **`Ashutos1997/claude-design-auditor-skill`** rewritten with STREAM-specific rules → a genuine "is this PR consistent with the scientific-tool aesthetic" linter. Nothing off-the-shelf provides this.

---

## What to actively avoid

Anything advertising:

- "270+ styles"
- "brand skins" / "make a page like Stripe"
- "landing page in one shot"
- "240+ font pairings"
- "AI generates beautiful gradients for you"
- empty-state illustration generators
- marketing-copy generators
- "hero section" anything

Those are convergence engines wearing anti-convergence costumes.

---

## How to use this file for `/gsd:explore`

When you're ready to draft the `DESIGN.md`:

1. Run `/gsd:explore` with a prompt like:
   > "Draft a project-local `DESIGN.md` for STREAM Composer. Read `gui/DESIGN-SKILLS-RESEARCH.md` for the curated approach and the explicit do/don't lists. Read `.planning/notes/gui-redesign-design-decisions.md` and `CLAUDE.md` for already-locked decisions. Read recent phase 67/68/69 commits to see the aesthetic decisions made in practice. Ask me Socratic questions to surface implicit taste decisions — show me 3 screenshots of GUIs I think look right and let me articulate what specifically. Then produce `gui/DESIGN.md` with concrete token values, rules, and anti-patterns."

2. `/gsd:explore` will interview you, then produce a structured doc. Edit it. Commit it. From then on, every UI PR should reference it explicitly (e.g., "follows `gui/DESIGN.md` zone-depth rule").

3. Optional next step after `DESIGN.md` exists: fork `Ashutos1997/claude-design-auditor-skill` into `.claude/skills/stream-design-auditor/`, replace its generic rules with the rules from your `DESIGN.md`. Now you have a static-analysis linter for design consistency.

---

## Source list (in case you want to dig into any of these)

- [anthropics/skills frontend-design SKILL.md](https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md)
- [bitjaru/styleseed](https://github.com/bitjaru/styleseed)
- [VoltAgent/awesome-claude-design](https://github.com/VoltAgent/awesome-claude-design)
- [VoltAgent/awesome-design-md](https://github.com/VoltAgent/awesome-design-md)
- [kylezantos/design-engineer-auditor-package](https://github.com/kylezantos/design-engineer-auditor-package)
- [Ashutos1997/claude-design-auditor-skill](https://github.com/Ashutos1997/claude-design-auditor-skill)
- [imsaif/design-with-claude](https://github.com/imsaif/design-with-claude)
- [masonjames/Shadcnblocks-Skill](https://github.com/masonjames/Shadcnblocks-Skill)
- [shadcn/ui Skills docs](https://ui.shadcn.com/docs/skills)
- [jugyo/vscode-theme-skill](https://github.com/jugyo/vscode-theme-skill)
- [axiaoge2/Apple-Hig-Designer](https://github.com/axiaoge2/Apple-Hig-Designer)
- [superdesigndev/superdesign](https://github.com/superdesigndev/superdesign)
- [Anthropic Skills Marketplace: The Anti AI-Slop UI Design Skill — Nick Porter](https://medium.com/@porter.nicholas/anthropic-skills-marketplace-the-anti-ai-slop-ui-design-skill-a572d0cfef4f)
- [I Built 63 Design Skills For Claude — MC Dean](https://marieclairedean.substack.com/p/i-built-63-design-skills-for-claude)
- [Top 8 Claude Skills for UI/UX Engineers — Snyk](https://snyk.io/articles/top-claude-skills-ui-ux-engineers/)
- [The 18 Best Claude Code Skills for UI/UX Design — Pillitteri](https://pasqualepillitteri.it/en/news/576/claude-code-skills-design-uiux-guide)
- [Design Review skill listing — mcpmarket.com](https://mcpmarket.com/tools/skills/design-reviewer)

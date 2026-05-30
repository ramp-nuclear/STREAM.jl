# Product

## Register

product

## Users

Nuclear engineers and thermal-hydraulics analysts running MTR (Materials Test Reactor)
plate-fuel safety analyses. Domain experts comfortable with Modelica/ModelingToolkit-style
acausal modeling, with a deep mental model of channel flow, CHF/OFI/OSV/ONB safety
thresholds, and 2D heat conduction in fuel plates. They use STREAM Composer to visually
compose a simulation network (channels, contacts, heat diffusion, point kinetics,
sources) and export it as runnable Julia. They are not training-wheels users; they know
what every parameter means.

## Product Purpose

STREAM Composer is a node-based desktop visual editor that produces STREAM.jl Julia
scripts. Its job is to turn the slow, error-prone task of hand-writing MTK acausal
networks into a fast, visual, type-correct composition step. The tool does not run
simulations or analyze results — its single job is *authoring a correct simulation
network*. Success means an engineer can compose a multi-channel plate-fuel transient in
minutes instead of an afternoon, and trusts the generated script enough to run it
without manual cleanup.

## Brand Personality

**Expert. Tool-grade.**

Supporting set: precise, dense, sharp, modern, intentional.

The tool reads as professional the way a serious modern product tool reads — closer to
Linear, Rive, or a contemporary node compositor than to a generic SaaS dashboard or a
legacy scientific UI. Restraint over decoration; the design defers to the work happening
in the canvas. The two leading words (*expert*, *tool-grade*) win any tie-break: when a
visual choice is in tension, pick the one that reads more like a tool a senior nuclear
engineer would respect.

## Anti-references

The redesign must NOT drift toward any of these:

- **Generic shadcn / Vercel admin dashboards.** Gray cards, lucide icons everywhere,
  slate-50 background, rounded-lg on everything, illustrated empty states. The default
  look of an LLM-bootstrapped React app. The current validator panel drifted this way
  and is the canonical bad example in this repo.
- **Consumer-SaaS hand-holding.** "Get started!" empty states, tooltips that explain
  the obvious, emoji in copy, conversational error messages, friendly framing.
  Engineering voice instead — terse, declarative, trust the user.
- **Legacy scientific UI (Java Swing era — pre-refresh COMSOL/Ansys).** Gray panels,
  tiny system fonts, dozens of nested toolbars, modal-heavy workflows. The opposite
  trap when over-correcting toward "scientific authority."
- **Observability/SRE dashboard cliché.** Dark navy + cyan accents + gradient glow +
  monospace-everywhere. Datadog/Grafana visual family.
- **AI slop.** If a frontend engineer could glance at a screen and say "obviously
  LLM-generated" — gradients, nested cards, gradient text, low-contrast labels,
  hero-metric templates — the design has failed.

## Design Principles

1. **The canvas is the product.** Chrome (sidebars, top bar, panels) is supporting
   infrastructure. It recedes visually in a VSCode-style zone hierarchy (chrome darkest
   → panels mid → working surfaces lightest). The node canvas is the lightest,
   brightest, most attention-claiming surface.
2. **Trust the expert.** Every label, error, empty state, and tooltip is written for
   someone who already knows the domain. No hand-holding. No restated headings. No
   "this field accepts a number."
3. **Speed of thought over visual polish.** Every layout decision optimizes for an
   engineer who runs the build → export → run loop dozens of times an hour. Keyboard
   parity, command palette (cmdk is already in deps), zero unnecessary clicks.
4. **Restraint over decoration.** No purple gradients, no glassmorphism, no decorative
   motion, no nested cards. Color appears with intent — Restrained strategy plus one
   accent ≤10%. Visual interest comes from typography contrast and spatial rhythm,
   not chroma or effects.
5. **Every choice committed.** No fence-sitting palettes, no "should we go dark or
   light," no defaults inherited from a starter template. Pick a theme that fits the
   physical scene (engineer + desktop monitor + extended work session) and own it.

## Accessibility & Inclusion

- **WCAG 2.1 AA** color contrast across every surface, including the canvas at default
  zoom.
- **Reduced-motion respect** via `prefers-reduced-motion`. All animations are functional
  (state transitions, focus rings), not decorative; under reduced-motion, transitions
  collapse to instant.
- **Full keyboard navigation** for all chrome (sidebars, dialogs, command palette,
  validator). Canvas keyboard parity is a real engineering cost given @xyflow/react's
  partial support, but every operation reachable by mouse must also be reachable by
  keyboard.

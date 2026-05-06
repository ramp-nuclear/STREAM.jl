# Phase 36: Code Generation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-02
**Phase:** 36-code-generation
**Areas discussed:** Preview panel placement, BC panel placement & UX, Generated code scope

---

## Preview panel placement

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom panel | Collapsible panel below full-width canvas; "Code" button in toolbar toggles it | ✓ |
| Sidebar tab | Second tab in sidebar (Params / Code); narrower 320px view | |

**User's choice:** Bottom panel

| Option | Description | Selected |
|--------|-------------|----------|
| "Code" button in toolbar | Always visible toggle; Export button lives nearby | ✓ |
| Keyboard shortcut only | e.g., Ctrl+\` like VS Code terminal | |
| Export button opens it | Panel auto-opens on Export click | |

**User's choice:** "Code" button in toolbar

---

## BC panel placement & UX

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom panel tab [Code][BCs] | Two tabs in the same bottom panel — consistent, no extra space needed | ✓ |
| Sidebar section | Always-visible BC list at bottom of sidebar | |
| Modal on demand | "BCs" button opens a modal dialog | |

**User's choice:** Bottom panel tab

| Option | Description | Selected |
|--------|-------------|----------|
| Structured form | [component ▾] . [port.field ▾] ~ [value input] + [Add] | ✓ |
| Freeform text input | Single text field; no validation | |

**User's choice:** Structured form (prevents typos, validates component exists)

| Option | Description | Selected |
|--------|-------------|----------|
| FlowPort.P only | inlet.P and outlet.P only; thermal BCs via ConstantTemperature (Phase 40) | ✓ |
| All port fields | FlowPort.P + FlowPort.mdot + ThermalPort.T + ThermalPort.Q_flow | |

**User's choice:** FlowPort.P only

---

## Generated code scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full runnable stub | `using` lines + components + eqs + ODESystem + mtkcompile + commented solve stub | ✓ |
| Minimal boilerplate | Just @named + eqs + ODESystem + mtkcompile; no `using` lines | |

**User's choice:** Full runnable stub

| Option | Description | Selected |
|--------|-------------|----------|
| ODESystem + connect idiom | `@named sys = ODESystem(eqs, t; systems=[...])` — matches STREAM.jl examples | ✓ |
| compose() helper | `compose(System(connections, t; name=:sys), ...)` — what CODE-05 specifies literally | |

**User's choice:** ODESystem + connect idiom (matches existing STREAM.jl examples)

---

## Claude's Discretion

- Syntax highlighting library for code preview (highlight.js, shiki, or plain `<pre>`)
- Exact toolbar layout and styling
- Whether bottom panel has a resize handle or fixed height
- Shadcn/ui components for BC structured form
- Error display strategy for CODE-07 identifier validation

## Deferred Ideas

- Thermal BC via BC panel — deferred to Phase 40 (ConstantTemperature node handles it)
- Syntax highlighting — Claude's discretion
- Live topology validation warnings — Phase 37

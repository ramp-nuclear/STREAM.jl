# Phase 39: Topology Validation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the Q&A.

**Date:** 2026-04-03
**Phase:** 39-topology-validation
**Mode:** discuss
**Areas analyzed:** Node error indicator, Alert banner placement

## Gray Areas Presented

| Area | Selected for discussion? |
|------|--------------------------|
| Node error indicator | Yes |
| Alert banner placement | Yes |

## Discussion: Node Error Indicator

| Question | Options | Selected |
|----------|---------|----------|
| How should an unconnected-port error appear on the canvas node? | Red ring outline / Warning badge / Red border override | Red ring outline (`ring-2 ring-destructive`) |
| When should unconnected-port warnings appear on nodes? | Only on export/save attempt / Always on with delay / Always on immediately | Only on export/save attempt |
| After the user dismisses the error dialog, what happens to node rings? | Red rings stay until errors are fixed / Rings clear when dialog dismissed | Red rings stay until errors are fixed |

**User note:** "This appears on every node that isn't connected? even if i just dragged it? Maybe we can do something that if you try to save or export it alerts?"
→ Led to the "only on export/save" decision.

## Discussion: Alert Banners

| Question | Options | Selected |
|----------|---------|----------|
| When user tries to export/save with topology problems, how should banners and node indicators appear? | Modal/AlertDialog / Inline banners + node rings / Toast notifications | Modal/AlertDialog — blocks export, lists all issues |

## Corrections Made

None — all initial assumptions were confirmed or refined through discussion.

## Key Insight

The user's primary concern was noise during construction — showing errors on freshly dragged nodes before they're wired would be disruptive. The "validate on export/save" model eliminates this while still satisfying VALD-01/02/03 (indicators appear, just triggered at the right moment). The persistent ring after dialog dismiss ensures the user knows which nodes to fix without re-triggering export.

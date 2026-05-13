---
created: 2026-05-13
title: ChannelAndContacts must expose TWO thermal connector ports (not one)
area: registry
resolves_phase: 63
files:
  - gui/src/registry/components.json
---

## Problem

In the GUI, the `ChannelAndContacts` (CAC) component currently exposes only ONE thermal connector port. This contradicts the underlying Julia component, which by design has two contact surfaces (one on each side of a plate) so a CAC sits between two HeatDiffusion plates in the canonical fuel-assembly topology.

User feedback verbatim:
> "why does the CAC component only has one thermal connection available? That is not correct right?"

Confirmed: yes, the user is correct. The Julia `ChannelAndContacts` in `src/components/channels.jl` has `port_contact_a` and `port_contact_b` (two thermal contact connectors). Architectural invariant from project memory: "only ChannelAndContacts connects to HeatDiffusion; Channel/CHF NEVER do" — implying CAC is the bridge component that connects two HDs to one channel.

This is a registry omission from Phase 61's audit. Phase 61 is complete; we route the fix to Phase 63 because that phase already touches CAC thermal-port wiring (BCs tab + value-source components in GUI).

## Solution

In Phase 63 (BCs tab + value-source components):
1. Audit `gui/src/registry/components.json` for the `ChannelAndContacts` entry.
2. Add the second thermal contact port (mirror the Julia API).
3. Verify the canvas renders both ports.
4. Verify codegen emits both `port_contact_a` / `port_contact_b` connections.
5. Add a registry test that locks the two-port contract.

## Notes

- Surfaced during Phase 62 human-verify checkpoint (62-11), 2026-05-13.
- Pre-existing bug from Phase 61 audit — not caused by Phase 62.
- Memory reference: `feedback_channel_hd_connection_rule.md`.

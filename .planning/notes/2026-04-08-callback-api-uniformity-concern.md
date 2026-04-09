---
date: "2026-04-08 15:30"
promoted: false
---

Callback API uniformity concern (Phase 48): flapper_callback and scram_callback have different signatures and internal mechanics. flapper_callback(ssys, monitored_sym; threshold) requires the caller to pass a state variable explicitly. scram_callback(p_sym, ctrl) takes a symbolic directly. Neither has a fully principled solution to the integrator[sym]-vs-u[idx] problem. Before Phase 49 (full loop where PK is nested), we should define a uniform callback factory pattern that: (1) works correctly for state variables during rootfinding, (2) doesn't require callers to know MTK internals, (3) is consistent across Flapper and SCRAM. Current fixes are functional but not the final design.

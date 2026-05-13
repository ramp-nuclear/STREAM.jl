---
created: 2026-05-13
title: Dedup verbose Power Shape resource names in generated Julia
area: codegen
resolves_phase: 66
files:
  - gui/src/lib/codeGenerator.ts
---

## Problem

Phase 62 codegen emits one Power Shape declaration per (PowerShape × consumer) pair, even when the same Power Shape resource is referenced by multiple consumers with the same parameters. Example from a user smoke test:

```julia
power_shape_pshape_for_heatdiffusion_1 = cosine_power_shape(nz, nx; amplitude=1.0)
power_shape_pshape_for_heatdiffusion_2 = cosine_power_shape(1, 2; amplitude=1.0)
```

The names are long, and when the underlying resource + params are identical, the duplication is purely visual noise.

User feedback verbatim:
> "the namings are bad in general I think. Why does it has to be: power_shape_pshape_for_heatdiffusion_1 = cosine_power_shape(nz, nx; amplitude=1.0) / power_shape_pshape_for_heatdiffusion_2 = ..., when its the same power shape? I get that It can have different nz and nx, but is there no better way to do this? It's fine but it is just long."

The per-consumer naming was a deliberate Phase 62 choice (62-10 SUMMARY "Key decisions: Always per-consumer Power Shape variable naming") because each HeatDiffusion consumer has its own `(nz, nx)` grid and rebinning is required. So full dedup is not always safe — but the names can be **shorter** and dedup can apply when parameters match exactly.

## Solution

Phase 66 reworks code-gen with `CodeSection[]` output and structured naming. As part of that rework:

1. Drop the `power_shape_` prefix when context makes it unambiguous (the Resources section already groups them).
2. When same resource + same `(nz, nx)` + same params → emit one variable referenced from both consumers (true dedup).
3. When same resource but different shape parameters → keep per-consumer but use shorter names like `<resource_name>_a`, `<resource_name>_b` instead of `power_shape_<resource>_for_<consumer>_<n>`.

Not blocking — Phase 62 codegen is correct as-is, just verbose. Address in Phase 66 codegen rework.

## Notes

- Surfaced during Phase 62 human-verify checkpoint (62-11), 2026-05-13.
- Decision deferred from 62-10. See `.planning/phases/62-resources-panel-architecture/62-10-SUMMARY.md` "Key decisions" for the original rationale.

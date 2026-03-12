# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

---

## Milestone: v0.1 — MVP

**Shipped:** 2026-03-13
**Phases:** 5 | **Plans:** 12

### What Was Built
- Julia package STREAM.jl with MTK v11 + DiffEq v7 + Sundials v5 compatibility
- Light water fluid properties registered as MTK symbolic functions (Simantov correlations for ρ, cp, μ, k)
- FlowPort and ThermalPort acausal connectors with correct across/through semantics
- Channel component: n-cell 1D FVM with Dittus-Boelter HTC and Darcy-Weisbach dP
- Pump, Friction, Gravity components (Pump and Gravity wired in loop; Friction absorbed into Channel)
- Steady-state and transient solvers with clean user API (build_loop, solve_steady, solve_transient)
- Python STREAM cross-validation: T_out=327.79 K, ṁ=0.609 kg/s — both within 1%
- 54-test suite covering all 15 requirements (FOUND, CONN, COMP, SYS, SOLV, VAL)
- Tech debt cleanup: BUG-01 (H_grav), BUG-02 (stale docstring), stale TDD files removed
- Nyquist compliance records for all three core phases

### What Worked
- Wave-based parallel execution let Phase 2 (4 plans) run efficiently — Wave 0 stubs enabled parallel Wave 1 components
- GSD workflow forced atomic commits per task, making git history readable and traceable
- Python STREAM reference generator (generate_reference.py) baked hardcoded values into tests — removes live Python dependency from CI
- MTK's acausal connect() fully replaced the Python Aggregator pattern with zero explicit variable routing
- @register_symbolic for fluid properties was the right call — zero injection complexity, ForwardDiff-compatible

### What Was Inefficient
- Phase 4 (tech debt cleanup) should have been caught earlier; BUG-01 and BUG-02 were obvious during Phase 2/3 planning
- Friction ended up orphaned in the loop (absorbed into Channel) but remained an exported component — creates a confusing API that needs v0.2 attention
- The milestone audit (v0.1-MILESTONE-AUDIT.md) was run after all phases were complete rather than interleaved with development; earlier auditing would have caught BUG-01 during Phase 2
- VAL-01/02/03 missing from SUMMARY.md frontmatter was a minor doc debt that had to be fixed in Phase 4

### Patterns Established
- Wave 0 stub plan (test scaffold + stubs) enables parallel Wave 1 execution — repeat this for any phase with independent parallel components
- Python reference values baked into test constants (not computed at test time) — use for any cross-language validation
- Nyquist compliance via VALIDATION.md at phase completion — run /gsd:validate-phase immediately after each phase, not as a separate phase
- MTK parameter naming: use same name for kwarg and MTK parameter (e.g., `H` in Gravity) to avoid the BUG-01 class of silent mismatch

### Key Lessons
1. **Run audit-milestone after each phase cluster, not after all phases are done** — BUG-01 sat undetected through all of Phase 3 testing
2. **Friction-inside-Channel was expedient but wrong for the public API** — exported components should be wired into the loop or clearly marked as standalone utilities
3. **`@register_symbolic` functions need to be defined before registration** — this bit us early; the fix is simple but the error message is not obvious
4. **MTK v11 `@connector function` pattern (not DSL block syntax)** — this was a breaking change from tutorials; document immediately when hitting it
5. **Validate-phase should be a step in each phase's success criteria**, not a separate bookkeeping phase at the end of the milestone

### Cost Observations
- Model mix: ~100% sonnet (all agents configured to sonnet profile)
- Sessions: ~1 (single intensive session 2026-03-12/13)
- Notable: 75 commits in ~2 days from a standing start; executor agents with fresh 200k context per plan worked well at this scale

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Plans | Key Change |
|-----------|--------|-------|------------|
| v0.1 | 5 | 12 | First milestone — baseline established |

### Cumulative Quality

| Milestone | Tests | Requirements | Zero-Dep Additions |
|-----------|-------|--------------|-------------------|
| v0.1 | 54 | 15/15 | 0 |

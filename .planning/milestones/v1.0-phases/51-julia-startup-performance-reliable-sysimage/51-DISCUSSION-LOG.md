# Phase 51: Julia Startup Performance & Reliable Sysimage - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-10
**Phase:** 51-julia-startup-performance-reliable-sysimage
**Mode:** discuss

## Gray Areas Identified

| Area | Gray Area | Outcome |
|------|-----------|---------|
| Precompile warmup | How much code in precompile_exec.jl? | Medium: mtkcompile on small system |
| Build reliability | What hardening beyond 4GB/1-thread? | Pre-flight RAM check |
| Package scope | Does v0.9 add NonlinearSolve to sysimage? | No — dead import to remove |
| Verification | How to confirm it actually works? | Timing script + test suite + actual build run |

## Key Discussion Points

### NonlinearSolve Investigation
User asked to actually verify whether NonlinearSolve was a genuine dependency added by v0.9 PointKinetics.

**Finding:** NonlinearSolve is in `[extras]` (test-only), not `[deps]` (runtime). The only usage is `using NonlinearSolve` in `test/test_resistors.jl:5` — imported but never called. Dead import. Not needed for the sysimage. Should be removed as cleanup.

### WSL2 Crash Risk
User noted that previous sysimage build attempts crashed WSL2 and terminated the chat session. This is a real constraint: the build must be treated as a potentially session-ending operation. Execution plan must warn before running it and suggest manual execution in a separate terminal.

### User's Core Concern
"I want to be 100% sure the .so file actually builds and works." The phase cannot be marked complete with just code changes — the build must actually succeed on the user's machine and the timing improvement must be measured.

## Corrections Made

None — all assumptions confirmed.

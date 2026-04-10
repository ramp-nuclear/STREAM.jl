---
phase: 51
slug: julia-startup-performance-reliable-sysimage
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-10
---

# Phase 51 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib `@time` + exit code checks |
| **Config file** | none — timing scripts created in Wave 0 |
| **Quick run command** | `julia --project=. -e 'using STREAM; println("OK")'` |
| **Full suite command** | `test -f stream.so && SYSIMG="--sysimage stream.so" || SYSIMG=""; julia $SYSIMG --project=. test/runtests.jl` |
| **Estimated runtime** | ~60–120 seconds (without sysimage) / ~10–15 seconds (with sysimage) |

---

## Sampling Rate

- **After every task commit:** Run `julia --project=. -e 'using STREAM; println("OK")'`
- **After every plan wave:** Run full suite
- **Before `/gsd-verify-work`:** Full suite must be green + sysimage build must exit 0
- **Max feedback latency:** 30 seconds (quick check), 120 seconds (full)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Status |
|---------|------|------|-------------|-----------|-------------------|--------|
| 51-01-01 | 01 | 1 | TTFX baseline | benchmark | `julia --project=. test/time_startup.jl` | ⬜ pending |
| 51-01-02 | 01 | 1 | precompile_exec.jl warmup | integration | `julia --project=. test/precompile_exec.jl; echo $?` | ⬜ pending |
| 51-01-03 | 01 | 2 | sysimage build | integration | `./build_sysimage.sh; echo $?` | ⬜ pending |
| 51-01-04 | 01 | 2 | TTFX with sysimage | benchmark | `julia --sysimage stream.so --project=. test/time_startup.jl` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/time_startup.jl` — timing script for TTFX measurement (created in Wave 0)

*If already exists: skip creation.*

---

## Manual-Only Verifications

| Behavior | Why Manual | Test Instructions |
|----------|------------|-------------------|
| Sysimage build doesn't OOM crash on WSL2 | Requires interactive build observation | Run `./build_sysimage.sh` on the target machine and confirm it completes without OOM kill |
| TTFX improvement is noticeable | Subjective comparison | Time `using STREAM` + `mtkcompile` call with and without sysimage; confirm 10x+ speedup |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

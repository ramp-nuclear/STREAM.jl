---
phase: 56
slug: python-stream-cross-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-05-08
---

# Phase 56 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Source: `.planning/phases/56-python-stream-cross-validation/56-RESEARCH.md` §"Validation Architecture".

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia stdlib `Test` (`@testset`, `@test`, `@assert`); Phase 56 testsets ride on the existing v1.1 framework. |
| **Config file** | None — `test/runtests.jl` `include`s test files directly (Phase 55 D-22 layout). `Project.toml [extras]` already declares `Test`. |
| **Quick run command** | `bin/jl test/test_validation.jl` |
| **Full suite command** | `bin/jl test/runtests.jl` |
| **Estimated runtime** | ~30–60s warm for `test_validation.jl`; ~5–10 min cold for the full suite. |

---

## Sampling Rate

- **After every task commit:** Run `bin/jl test/test_validation.jl`
- **After every plan wave:** Run `bin/jl test/runtests.jl`
- **Before `/gsd-verify-work`:** Full suite must be green (pre-existing flakies — NET-03, HTC-02, HD-Fourier — tolerated per Phase 55 D-22)
- **Max feedback latency:** 60 seconds (quick run)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 56-XX-XX | TBD | TBD | TEST-04 | — | N/A (test-only phase) | unit (parity / self-consistency) | `bin/jl test/test_validation.jl` | ❌ W0 | ⬜ pending |

*Filled by planner during decomposition. One row per Wave 0+ task; each row tagged with the TEST-04 sub-requirement (a)–(g) from the Phase Requirements → Test Map below.*

### Phase Requirements → Test Map (from RESEARCH.md)

| Sub-Req | Behavior | Test Type | Automated Command | File Exists? |
|---------|----------|-----------|-------------------|--------------|
| TEST-04 (a) | Steady-state simple loop within hard ceiling | unit (parity testset) | `bin/jl test/test_validation.jl` | ❌ Wave 0 (replaces existing VAL-01:17-30) |
| TEST-04 (b) | Steady-state MTR symmetric within hard ceiling | unit | (same) | ❌ Wave 0 (replaces VAL-01:74-182) |
| TEST-04 (c) | Steady-state MTR asymmetric within hard ceiling | unit | (same) | ❌ Wave 0 (replaces VAL-02:188-275) |
| TEST-04 (d) | Steady-state MTR one-sided within hard ceiling | unit | (same) | ❌ Wave 0 (replaces VAL-03:280-380) |
| TEST-04 (e) | Drift report `test/data/parity_report.csv` committed and non-empty | unit (file-existence assertion) | `@test isfile(PARITY_CSV) && filesize(PARITY_CSV) > 100` | ❌ Wave 0 (NEW assertion) |
| TEST-04 (f) | Equivalence checklist 5 items pass before parity comparison | unit (precondition assert) | (implicit in each parity testset) | ❌ Wave 0 (NEW asserts) |
| TEST-04 (g) | Existing 3 KEPT testsets remain green (VAL-02 transient T_wall, HD Fourier, two-plate one-channel, PK validation) | regression | (full suite) | ✅ already passing per Phase 55 D-22 |

---

## Wave 0 Requirements

- [ ] `test/parity_helpers.jl` (NEW) — covers TEST-04 (e)+(f); ~80–100 lines, structs + `parity_check`, `print_drift_table`, `append_csv`, 5 `assert_equivalence_*` functions
- [ ] `test/data/python_parity_reference.jl` (NEW) — covers TEST-04 (a)–(d) reference data; ~580 lines of `const Float64[…]` blocks across 4 scenarios × 4 D-07 tiers; emitted by rewritten generators
- [ ] `test/generate_reference.py` (REWRITTEN) — D-17; current 145 → ~250–300 lines emitting all 4 D-07 tiers
- [ ] `test/generate_mtr_reference.py` (REWRITTEN) — D-17; current 307 → ~400–500 lines emitting plate `T(z,x)`
- [ ] `test/test_validation.jl` (MODIFIED) — 5 testsets REPLACED with new parity testsets per D-13; the other 3 testsets KEPT verbatim
- [ ] `test/data/parity_report.csv` (NEW, committed artifact) — D-08; long-format CSV, written by the harness on each run

*Framework install: none — Julia `Test` already in use; Python venv on developer machine already in use per existing generators (no Python in CI per D-06).*

### Harness Self-Tests ("Test the Tester")

The 12 self-consistency tests below run in a `@testset "parity_helpers self-tests"` at the TOP of `test_validation.jl`, BEFORE any parity testset, so a regression in the harness fails fast:

1. `parity_check(s, q, x, x)` → `tier == TIER_CLEAN` and `rtol == 0` (identity)
2. `parity_check(s, q, x, x*(1+1e-9))` → `TIER_CLEAN` (sub-1e-6 drift)
3. `parity_check(s, q, x, x*(1+1e-3))` → `TIER_GRAY` (0.1% drift, between gray_floor and hard_ceiling)
4. `parity_check(s, q, x, x*(1+0.05))` → `TIER_FAIL` (5% drift)
5. `parity_check(s, q, x, x*(1+0.02))` → `TIER_FAIL` (boundary at exactly hard_ceiling, strict `<`)
6. `parity_check(s, q, 0.0, 0.0)` → `TIER_CLEAN` (zero on both sides → abs_err=0)
7. `parity_check(s, q, 1e-6, 0.0)` → `TIER_CLEAN` (zero-handling boundary)
8. `parity_check(s, q, -300.0, -300.0001)` → `TIER_CLEAN` (sign safety)
9. CSV roundtrip via `readdlm(...)` recovers rows within 1e-9 (10-sig-fig format string)
10. `append_csv` with `truncate=false` doubles row count; `truncate=true` resets
11. `print_drift_table(empty_rows)` does not crash
12. Equivalence-checklist self-fail: `assert_equivalence_fluid_props(rtol=0.0)` raises (asserts that asserts fire)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Run Python generators on developer machine; copy emitted const blocks into `test/data/python_parity_reference.jl` | TEST-04 (a)–(d) reference values | Python NOT in CI per D-06 — regenerate-and-paste pattern (Phase 53 stage2_reference.py model) | `cd ~/projects/STREAM && python -m test.generate_reference > /tmp/julia_const_block.jl` then paste into `test/data/python_parity_reference.jl`; same for `generate_mtr_reference`. Re-run only when upstream Python physics changes. |
| MILESTONES.md narrative entry "v1.1 closed: parity drift = X% on Y" | D-09 | Narrative authoring; planner picks wording | Edit `.planning/MILESTONES.md` at milestone close; entry references the worst per-quantity drift in the gray zone with sign and magnitude. |
| Final grep for `_channel_base_eqs` / `observed_mode` / `skip_htc` absence | ROADMAP success criterion 4 | Codebase-wide assertion | `! grep -rn '_channel_base_eqs\|observed_mode\|skip_htc' src/ test/ examples/` (must exit 1 = not found). |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (parity_helpers.jl, python_parity_reference.jl, generators rewritten, test_validation.jl restructured, parity_report.csv produced)
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending

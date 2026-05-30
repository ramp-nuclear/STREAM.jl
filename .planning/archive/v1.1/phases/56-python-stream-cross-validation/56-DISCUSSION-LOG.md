# Phase 56: Python STREAM Cross-Validation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-08
**Phase:** 56-python-stream-cross-validation
**Areas discussed:** Drift root-cause method (reframed), Reference-value policy, Validation breadth & evidence, Tolerance & drift policy, Legacy-content disposition

---

## Drift root-cause method (REFRAMED)

| Option | Description | Selected |
|--------|-------------|----------|
| Manifest-bisect first (Recommended) | Run Phase 55 codebase against v1.0 Manifest.toml. If VAL-01 passes → manifest drift; widen tolerance + document. If fails → enthalpy-form physics; regenerate Python ref. | |
| Regenerate Python ref first | Re-run generate_reference.py against current Python STREAM HEAD; compare new constants. | |
| Per-cell T[i] decomposition first | Compare per-cell T[1..n] vs Python's per-cell. Localizes whether drift is uniform or spatial. | |
| All three, in that order | Manifest-bisect → regenerate Python ref → per-cell decomposition. Most thorough. | |
| **REFRAMED by user** | "I am not sure about this because I don't really know what we are comparing to. I think we can worry a little less about this... The best thing to do is to rewrite the python and Julia reference and comparison, and make sure EVERYTHING is exactly one-to-one." | ✓ |

**User's choice:** Reframed the entire phase. Rather than diagnose the existing 1.75% mdot drift, REWRITE both the Python reference generator AND the Julia comparison harness so EVERYTHING is one-to-one across all parameters expected to be identical. "We should do this extremely thoroughly because this is the most important part."

**Notes:** Future work copies Python integration tests one-to-one and expects identical results — Phase 56 establishes the mechanism. The drift answer falls out of the rewrite. This decision is captured as D-01 in CONTEXT.md.

---

## Reference-value policy → Harness scope (Python integration examples seeded)

| Option | Description | Selected |
|--------|-------------|----------|
| Canonical simple loop (Recommended) | Pump→HeatExchanger→ChannelAndContacts loop, matching generate_reference.py. | ✓ |
| MTR plate (HD + 2× CAC) | All three MTR scenarios (symmetric, asymmetric, one-sided) from generate_mtr_reference.py. The v1.1 main use case (CAC↔HD centerpiece). | ✓ |
| LOF transient | build_loop_lof_bypass full trajectory parity vs Python — pump coastdown, Flapper, NC reversal, per-timestep checkpoints. | |
| PK + thermal feedback | build_loop_pk full trajectory parity vs Python — reactivity insertion, Doppler, SCRAM. | |

**User's choice:** Canonical simple loop + MTR plate. Steady-state focus only.

**Notes:** LOF and PK trajectories deferred to future work. Captured as D-02 in CONTEXT.md.

---

## Tolerance & drift policy → Identity strictness

| Option | Description | Selected |
|--------|-------------|----------|
| Engineering rtol=1% (Recommended) | All quantities at rtol=1%. Matches solver convergence noise. | |
| Tight rtol=1e-6 (Stage-2 style) | Byte-for-byte match against Python-generated reference. Catches any physics divergence immediately. | |
| Mixed tiers | Tight on math-identical quantities; loose on solver-dependent. Per-quantity rationale documented. | |
| **User-defined tiered verdict** | Hard fail >1-2%, gray zone 1e-6→1% reports drift magnitude (not pass/fail), clean pass ≤1e-6. Solver-floor is aspirational truth. | ✓ |

**User's choice:** Three-tier verdict. "If we solve the same exact system in two codes, the result should be within solver tols. That much is obvious. But the problem is that I don't know if we are there yet. Maybe we can do a max tolerance of 1-2%, meaning if the tol is higher than that something is obviously really wrong. If the tol is 1e-6 or below, we are perfectly fine. But, anywhere in between is a gray zone and that test might not be a 'pass or fail' at this point, but more of a 'how close are we'."

**Notes:** Captured as D-03 in CONTEXT.md. The "gray zone reports drift" is the central novelty — Phase 56 makes the harness honest about distance from the solver-floor truth.

---

## Reference-value policy → Sync mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Regenerate + paste (current pattern, Recommended) | generate_reference.py / generate_mtr_reference.py emit Julia const blocks; commit-time refresh. CI runs Julia only. | ✓ |
| Pin Python commit + auto-CI | Pin Python STREAM commit, run Python in CI to regenerate constants on every PR. | |
| Hardcoded forever | Generate once, freeze, never regenerate. | |

**User's choice:** Regenerate + paste (current pattern).

**Notes:** Captured as D-05 / D-06 in CONTEXT.md. Python runtime stays out of CI.

---

## Validation breadth → Quantities compared

| Option | Description | Selected |
|--------|-------------|----------|
| Inlet/outlet scalars (T_out, mdot, dP_loop) | The current test_validation.jl scope. Cheapest. | ✓ |
| Per-cell coolant T[i] + mdot | Spatial profile inside the channel. Reveals whether enthalpy-form face-averaged cp matches Python's pair_mean_1d cell-by-cell. | ✓ |
| Per-cell wall T_wall[i] + h_tc[i] + q[i] | Heat-transfer side. Reveals whether HTC + q-expression match Python's. CAC-only. | ✓ |
| Plate-side T(z,x) for MTR | Full 2D HeatDiffusion field for MTR scenarios. Reveals whether HD physics matches Python's plate calculation cell-by-cell. | ✓ |

**User's choice:** All four tiers — full coverage.

**Notes:** Captured as D-07 in CONTEXT.md.

---

## Validation breadth → Reporting (gray-zone verdict surface)

| Option | Description | Selected |
|--------|-------------|----------|
| @test + printed drift table (Recommended) | Hard @test rtol=1-2% fails the suite if exceeded. Per-quantity drift table to stdout + MILESTONES.md. | ✓ |
| CSV artifact + @test only at hard floor | Hard floor only @test; drift values written to test/data/parity_report.csv, gitted. Easier to diff across milestones. | ✓ |
| Two test layers — strict (broken) + lenient (gates) | Strict (1e-6) lives as broken testset surfacing in test summary. Lenient (1-2%) gates milestone. | |

**User's choice:** Both option 1 and option 2 — "Do them both."

**Notes:** Captured as D-08 in CONTEXT.md. Stdout drift table for live developer signal; CSV at test/data/parity_report.csv as auditable diffable record.

---

## Tolerance & drift policy → Equivalence foundation

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit equivalence checklist + test asserts (Recommended) | Auto-checks at test setup: Dittus-Boelter, Blasius, fluid props at three reference T values within 1e-12, solver tols, geometry. Failure aborts before parity check. | ✓ |
| Trust generators + manual review | Trust generate_reference.py / generate_mtr_reference.py to encode equivalent physics; manual audit; no runtime checks. | |
| Cross-import Python via PyCall / juliacall | Call Python STREAM fluid props + correlations from Julia at test time. Strongest but adds Python runtime to CI. | |

**User's choice:** Explicit equivalence checklist + test asserts (recommended).

**Notes:** Captured as D-10 / D-11 in CONTEXT.md. Failure aborts before parity check so false-positive parity passes can't happen because we accidentally compared apples and oranges. Documented equivalence gaps (e.g., Sundials vs Python solver tols if they can't be made identical) ground drift interpretation.

---

## Tolerance & drift policy → Milestone close gate

| Option | Description | Selected |
|--------|-------------|----------|
| Hard-floor pass + drift report committed (Recommended) | Hard @test green. Drift report committed to test/data/parity_report.csv AND MILESTONES.md "v1.1 closed: parity drift = X%" entry. Gray-zone OK — documented, not blocking. | ✓ |
| Strict-tier achievement required | Milestone close requires rtol ≤1e-6 across all quantities. Anything in gray zone blocks. | |
| Hard-floor + sign-off review | Hard floor passes the gate, but drift report goes through human review step before milestone close. | |

**User's choice:** Hard-floor pass + drift report committed (recommended).

**Notes:** Captured as D-12 in CONTEXT.md. Gray-zone drifts documented but not blocking. Strict-tier (≤1e-6) is aspirational target, not gate.

---

## Legacy-content disposition

| Option | Description | Selected |
|--------|-------------|----------|
| Keep existing testsets, replace simple-loop + MTR ones (Recommended) | VAL-02 transient step, HD Fourier (VAL-01), two-plate (VAL-02), PointKinetics validation kept as-is. Simple-loop VAL-01 + MTR VAL-01/02/03 testsets replaced by new harness. | ✓ |
| Wholesale rewrite from scratch | Delete test_validation.jl entirely; rebuild only with new one-to-one harness. | |
| Split into test_validation.jl + test_validation_extras.jl | Pure parity harness (new) + legacy quantitative tests (Fourier, PK, transient step) split into two files. | |

**User's choice:** Keep existing testsets; replace only simple-loop + MTR ones.

**Notes:** Captured as D-13 / D-14 in CONTEXT.md. test_validation.jl stays single-file. Replaced testsets are renamed/restructured under the new "Python parity: ..." section convention.

---

## Claude's Discretion

The following implementation details were left for the planner to decide:

- **Per-quantity hard-ceiling threshold.** Default 2% rtol globally; widen specific quantities (e.g., HTC) with documented rationale.
- **Stdout drift-table format.** Aligned ASCII table; planner picks columns and row order.
- **CSV schema** at `test/data/parity_report.csv` — long vs wide, exact column names. As long as it's diffable + human-readable.
- **Equivalence checklist exact items** — D-10 list is the seed; planner adds items as discovered.
- **Whether `parity_helpers.jl` is a new file (D-15)** — based on machinery size.
- **Whether Julia-side reference data lives inline in test_validation.jl or in test/data/python_parity_reference.jl** (D-17).
- **MILESTONES.md narrative wording** for the v1.1 close entry (D-09).
- **Wave / plan decomposition.** Planner picks: suggested shape (a) generators rewrite; (b) regenerate Python references; (c) parity_helpers.jl machinery; (d) test_validation.jl parity testsets rewrite; (e) parity_report.csv + MILESTONES.md; (f) milestone-close cleanup.

---

## Deferred Ideas

The following came up during discussion or are inherited from the phase frame; noted for future phases:

- **LOF transient Python-parity** — `build_loop_lof_bypass` full trajectory comparison vs Python's PCS-coastdown integration test. Deferred to v1.2+ via the Phase 56 harness mechanism.
- **PK + thermal feedback Python-parity** — `build_loop_pk` trajectory comparison. Some coverage via v0.9 VAL-PK-01..03; full harness extends that.
- **Channel / ChannelHeatFlux parity scenarios** — simplified-model variants per Phase 55 user frame; future work.
- **Manifest-drift root cause investigation** — explicitly NOT a Phase 56 deliverable per D-01. Future maintenance phase if drift report points at MTK/Sundials/Symbolics version.
- **Python STREAM cross-import via PyCall / juliacall** — out for v1.1; strongest drift detection but adds Python to CI.
- **Auto-regenerate Python reference in CI** — out for v1.1; requires Python in CI.
- **test_validation.jl split into per-scenario files** — explicitly not chosen; could revisit if file becomes unwieldy.
- **Strict-tier (≤1e-6) achievement as milestone gate** — aspirational, not blocking; future milestone could promote.
- **Parity harness for flow-reversal scenarios** — would require matching Python STREAM test; defer until Python side gains it.
- **HTC-correlation regime-switching parity (NC via Gr/Re²>1)** — defer until Python side has comparison point.
- **MILESTONES.md / PROJECT.md / STATE.md updates** — happen at `/gsd:complete-milestone` time, not in Phase 56 itself.

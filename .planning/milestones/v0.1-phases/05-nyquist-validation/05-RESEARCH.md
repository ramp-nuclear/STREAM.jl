# Phase 5: Nyquist Validation — Research

**Researched:** 2026-03-13
**Domain:** GSD process / bookkeeping — running `/gsd:validate-phase` for completed phases
**Confidence:** HIGH

---

## Summary

Phase 5 is a pure bookkeeping phase. No new code is written. The goal is to run `/gsd:validate-phase` for phases 01, 02, and 03, which will audit each phase's existing VALIDATION.md (all three are in State A — file exists, `nyquist_compliant: false`), fill any test coverage gaps via the gsd-nyquist-auditor agent, and flip `nyquist_compliant: true` in each phase's frontmatter.

All three target phases already have: VALIDATION.md files (created during planning), SUMMARY.md files (created during execution), VERIFICATION.md reports (created during verify-work), and a healthy 54-test green baseline after Phase 4 cleanup. The test infrastructure is Julia's stdlib `Test` module invoked via `julia --project -e "using Pkg; Pkg.test()"`.

The validate-phase workflow is deterministic: it reads existing artifacts, classifies requirement coverage as COVERED/PARTIAL/MISSING, optionally spawns the nyquist-auditor to fill gaps, then writes an updated VALIDATION.md with `nyquist_compliant: true`. Because phases 01–03 were fully executed and verified, most requirements will likely already be COVERED — the auditor will only need to act if a requirement has no automated test command pointing at the right test file.

**Primary recommendation:** Run `/gsd:validate-phase 1`, then `/gsd:validate-phase 2`, then `/gsd:validate-phase 3` in sequence. Each invocation is self-contained and can be executed as a separate plan task. The single plan (05-01-PLAN.md) should contain three ordered tasks, one per phase, each calling validate-phase and confirming `nyquist_compliant: true` in the resulting VALIDATION.md.

---

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| `/gsd:validate-phase` | GSD built-in | Audit Nyquist compliance for a completed phase | The only supported path for setting `nyquist_compliant: true` |
| Julia Test stdlib | Built-in | Test runner for gap-filling commands | Already in use across phases 01–04 |
| `gsd-tools.cjs` | GSD built-in | Init, commit-docs, model resolution | Used by all GSD workflows |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| gsd-nyquist-auditor | GSD sub-agent | Writes missing tests when gaps are found | Spawned automatically by validate-phase if MISSING/PARTIAL gaps exist |

**No installation required.** All tooling is already present.

---

## Architecture Patterns

### Recommended Plan Structure

One plan with three sequential tasks:

```
05-01-PLAN.md
  Task 1: /gsd:validate-phase 1  → 01-VALIDATION.md nyquist_compliant: true
  Task 2: /gsd:validate-phase 2  → 02-VALIDATION.md nyquist_compliant: true
  Task 3: /gsd:validate-phase 3  → 03-VALIDATION.md nyquist_compliant: true
```

Tasks must be sequential because each validate-phase run commits docs and updates state independently. Parallelization is unnecessary and may produce git conflicts.

### Pattern: validate-phase Workflow (State A)

**What:** The `/gsd:validate-phase` workflow detects the existing VALIDATION.md (State A), reads all PLAN and SUMMARY files to build a requirement-to-task map, cross-references requirements against existing tests, classifies each as COVERED/PARTIAL/MISSING, presents a gap table, optionally spawns the auditor, then updates the VALIDATION.md frontmatter.

**Entry condition:** VALIDATION.md exists AND SUMMARY files exist → State A (audit existing).

**Key behavior:** After the workflow completes with no outstanding gaps, it sets `nyquist_compliant: true` in the VALIDATION.md frontmatter and commits the file.

**For each phase:**
- Phase 1 VALIDATION.md: 6 tasks mapped, FOUND-01/02 + CONN-01/02 requirements; all verified in `test/runtests.jl`
- Phase 2 VALIDATION.md: 7 tasks mapped, COMP-01 through COMP-04; all covered by Julia test suite
- Phase 3 VALIDATION.md: 7 tasks mapped, SYS-01/02, SOLV-01/02, VAL-01/02/03; all covered by Julia test suite

### Anti-Patterns to Avoid

- **Skipping a phase:** All three phases must be validated for the milestone to be Nyquist-compliant. Do not mark phase 5 complete with any phase at `nyquist_compliant: false`.
- **Manually editing VALIDATION.md frontmatter:** The `nyquist_compliant: true` flag must be set by the validate-phase workflow, not by hand-editing. The workflow also commits the file via `commit-docs`.
- **Running validate-phase on phase 4 or phase 5 in this plan:** Phase 5 only closes gaps for phases 01, 02, and 03 per the phase description.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Setting `nyquist_compliant: true` | Manual frontmatter edit | `/gsd:validate-phase N` | Workflow also updates audit trail, commits docs, and handles PARTIAL/MISSING gap resolution |
| Writing missing tests | Manual test authoring | gsd-nyquist-auditor (spawned by validate-phase) | Auditor has full context of phase artifacts, knows test conventions, handles up to 3 debug iterations |

**Key insight:** The validate-phase workflow is the authoritative mechanism. Running it correctly produces a complete audit trail; bypassing it produces a compliance record that the GSD system cannot trust.

---

## Common Pitfalls

### Pitfall 1: Gap Table Interaction Required

**What goes wrong:** The validate-phase workflow calls `AskUserQuestion` at Step 4 when it finds gaps, presenting a gap table and asking: (1) Fix all gaps, (2) Skip — mark manual-only, (3) Cancel.

**Why it happens:** The workflow is interactive by design. If running in yolo mode, the executor must handle or anticipate this prompt.

**How to avoid:** The plan task should acknowledge this interaction point. In yolo mode the agent will see the question and should select "Fix all gaps" (option 1) unless there is a genuine reason a requirement cannot be automated.

**Warning signs:** Task hangs waiting for user input.

### Pitfall 2: Phases May Already Be Largely COVERED

**What goes wrong:** Over-engineering the plan to assume massive gap-filling work.

**Why it happens:** The VALIDATION.md files were created during planning (before execution), so all task statuses are `⬜ pending`. But the code and tests were written and verified — the test suite is 54 tests green. Most requirements will resolve as COVERED once the auditor cross-references filenames and test descriptions.

**How to avoid:** Expect mostly COVERED results. The auditor work (if any) will be minor — e.g., a single missing `@testset` name or a test that needs a targeted command rather than the full suite.

**Warning signs:** Planning for large amounts of new test-writing when the codebase already has 54 passing tests covering all requirements.

### Pitfall 3: Manual-Only Items Must Be Preserved

**What goes wrong:** Attempting to automate items explicitly designated Manual-Only in each VALIDATION.md.

**Why it happens:** The auditor might try to automate `@register_symbolic` placement verification (Phase 1) or `observed()` symbolic inspection (Phase 2) or `generate_reference.py` execution (Phase 3).

**How to avoid:** The plan should instruct the executor to preserve existing Manual-Only entries and not attempt to automate them. They are designated manual for legitimate reasons (compile-time constraints, Python dependency, symbolic inspection).

**Warning signs:** Auditor attempting to write automated tests for items in the Manual-Only table.

### Pitfall 4: Commit Ordering

**What goes wrong:** Git conflicts if validate-phase runs for multiple phases concurrently or if commits interleave unexpectedly.

**Why it happens:** Each validate-phase run does `commit-docs` for its VALIDATION.md. If test files are also written, they get a separate commit.

**How to avoid:** Run the three validate-phase invocations strictly sequentially (Task 1 → Task 2 → Task 3). Wait for each to complete and confirm `nyquist_compliant: true` before proceeding.

---

## Code Examples

### Verify nyquist_compliant After Each Run
```bash
# Source: VALIDATION.md frontmatter pattern
head -10 .planning/phases/01-foundation/01-VALIDATION.md
# Expect: nyquist_compliant: true
```

### Confirm Test Suite Still Green After Any Gap-Filling
```bash
# Source: All phase VALIDATION.md files
julia --project=/home/itay/projects/Julia-STREAM -e "using Pkg; Pkg.test()"
# Expect: 54 tests pass (or more if auditor adds tests)
```

### Check All Three Phases Compliant (Phase Gate)
```bash
# Source: validate-phase workflow success criteria
grep "nyquist_compliant" \
  .planning/phases/01-foundation/01-VALIDATION.md \
  .planning/phases/02-components/02-VALIDATION.md \
  .planning/phases/03-integration-and-validation/03-VALIDATION.md
# Expect: nyquist_compliant: true for all three
```

---

## Current State of Each Target Phase

| Phase | VALIDATION.md | Status | nyquist_compliant | SUMMARY files | Tests green |
|-------|--------------|--------|-------------------|---------------|-------------|
| 01-foundation | 01-VALIDATION.md | State A | false (to fix) | 3 × SUMMARY | Yes (54 tests) |
| 02-components | 02-VALIDATION.md | State A | false (to fix) | 4 × SUMMARY | Yes (54 tests) |
| 03-integration | 03-VALIDATION.md | State A | false (to fix) | 3 × SUMMARY | Yes (54 tests) |

All three are State A (VALIDATION.md exists). None are State C (missing SUMMARY files). The validate-phase workflow will proceed to gap analysis for all three without blocking.

### Known Manual-Only Items (Preserve, Do Not Automate)

| Phase | Item | Reason |
|-------|------|--------|
| 01 | `@register_symbolic` at module top-level | Compile-time constraint |
| 02 | `observed(compiled_sys)` symbolic inspection | Requires post-mtkcompile symbolic API |
| 03 | Run `generate_reference.py` for Python reference values | Requires Python STREAM installed |
| 04 | `03-03-SUMMARY.md` frontmatter field | YAML inspection, not a code behavior |

---

## Validation Architecture

> `workflow.nyquist_validation` is `true` in `.planning/config.json` — this section is required.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia stdlib `Test` (no install needed) |
| Config file | `test/runtests.jl` |
| Quick run command | `julia --project=. -e "using Pkg; Pkg.test()"` |
| Full suite command | `julia --project=. -e "using Pkg; Pkg.test()"` |

### Phase Requirements → Test Map

Phase 5 has no formal requirement IDs (process/bookkeeping). The success criteria are:

| Success Criterion | Verification | Type |
|-------------------|-------------|------|
| Phase 01 VALIDATION.md has `nyquist_compliant: true` | `grep "nyquist_compliant: true" .planning/phases/01-foundation/01-VALIDATION.md` | automated |
| Phase 02 VALIDATION.md has `nyquist_compliant: true` | `grep "nyquist_compliant: true" .planning/phases/02-components/02-VALIDATION.md` | automated |
| Phase 03 VALIDATION.md has `nyquist_compliant: true` | `grep "nyquist_compliant: true" .planning/phases/03-integration-and-validation/03-VALIDATION.md` | automated |

### Sampling Rate
- **Per task commit:** `grep "nyquist_compliant: true" .planning/phases/0{N}-*/0{N}-VALIDATION.md`
- **Per wave merge:** Check all three phases
- **Phase gate:** All three `nyquist_compliant: true` before `/gsd:verify-work`

### Wave 0 Gaps
None — no new test files or framework setup required. All infrastructure pre-exists.

---

## Open Questions

1. **Will the auditor find gaps in phases 01–03?**
   - What we know: 54 tests pass, all requirements were satisfied during execution, VERIFICATION.md reports all show PASSED
   - What's unclear: Whether the auditor's cross-referencing of test filenames/descriptions will classify all tasks as COVERED or some as PARTIAL (e.g., tasks that have generic suite-wide commands rather than targeted per-requirement commands)
   - Recommendation: Plan for the "Fix all gaps" path. If auditor is spawned, trust it. The 54-test green baseline means no implementation gaps exist — only test metadata gaps.

2. **Will validate-phase for Phase 4 be needed?**
   - What we know: Phase 4's VALIDATION.md also has `nyquist_compliant: false`; Phase 4 SUMMARY exists
   - What's unclear: The phase 5 description explicitly says "phases 01, 02, 03" — Phase 4 is out of scope for this phase
   - Recommendation: Scope strictly to phases 01, 02, 03. Phase 4 validation (if needed) belongs to a separate task or milestone audit.

---

## Sources

### Primary (HIGH confidence)
- `.claude/get-shit-done/workflows/validate-phase.md` — Authoritative validate-phase workflow specification
- `.claude/get-shit-done/templates/VALIDATION.md` — VALIDATION.md template structure
- `.planning/phases/01-foundation/01-VALIDATION.md` — Phase 1 current state
- `.planning/phases/02-components/02-VALIDATION.md` — Phase 2 current state
- `.planning/phases/03-integration-and-validation/03-VALIDATION.md` — Phase 3 current state
- `.planning/phases/04-tech-debt-cleanup/04-01-SUMMARY.md` — Confirms 54 tests green, clean baseline
- `.planning/config.json` — Confirms `nyquist_validation: true`

### Secondary (MEDIUM confidence)
- `.planning/STATE.md` — Confirms all 4 prior phases complete, no blockers
- `.planning/REQUIREMENTS.md` — All v1 requirements mapped and marked Complete

---

## Metadata

**Confidence breakdown:**
- Workflow mechanics: HIGH — validate-phase.md is authoritative and explicit
- Current phase state: HIGH — read directly from VALIDATION.md frontmatter files
- Gap prediction: MEDIUM — 54 tests are green but auditor cross-referencing behavior not pre-observable
- Manual-Only items: HIGH — explicitly documented in each phase's VALIDATION.md

**Research date:** 2026-03-13
**Valid until:** Stable — GSD workflow spec rarely changes; valid until next GSD update

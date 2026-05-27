# Julia Idiom + MTK Modernization Pass — Milestone Proposal

**Status:** PROPOSED. Not yet started.
**Written:** 2026-05-28, end of v1.2 close-out (in conversation with Itay).
**Trigger:** Itay invokes this when ready to start. Read this entire file before doing anything else.
**Audience:** The Claude session that takes this on. Probably future-me.

---

## What this is

A planned codebase-wide audit and rework of all Julia source and test code in STREAM.jl, applying two rule sets the user has authored:

1. `JULIA.md` — rules for clean, idiomatic, correct Julia.
2. An MTK skill — rules for idiomatic ModelingToolkit usage (up-to-date patterns, no longcuts, no deprecated APIs, correct use of `@variables` / `@parameters` / `@register_symbolic` / `mtkcompile` / observed-vs-unknown decisions, connector patterns, etc.).

Goal: every line of `src/` and `test/` conforms to both rule sets at both a micro level (per-file idiom) and a macro level (cross-file voice and consistency).

This is the cleanup pass that locks in the codebase as a coherent, professional Julia/MTK package before the GUI gets split into its own repo.

---

## Prerequisites — DO NOT START UNTIL ALL ARE TRUE

1. **PR #15 (`channels-redesign → main`) is merged.** Was open at the time of writing. Track it; don't start this milestone while it's pending.
2. **`gui-redesign` branch is merged to `main`.** Was waiting on PR #15 as of 2026-05-28 (see tracking issue #17). Confirm via `gh pr list --state all --search "gui-redesign"`.
3. **`main` is stable.** No long-lived feature branches in flight. `git branch -r` shouldn't show feature branches older than a few days.
4. **JULIA.md exists in the repo.** Check `ls /home/itay/projects/Julia-STREAM/JULIA.md`. If missing, stop and ask Itay where it is.
5. **The MTK skill exists.** Check `ls /home/itay/projects/Julia-STREAM/.claude/skills/mtk*` and `ls ~/.claude/skills/mtk*`. If missing in both, stop and ask Itay where it is.
6. **Test suite passes on `main`** from a cold checkout. Run `julia --project=. test/runtests.jl` (or restore `bin/jl` first per the carry-forward in v1.2 if Itay wants the daemon back). Don't start work until the baseline is green.

If any prerequisite fails, **stop and report to Itay**. Do not improvise.

---

## Pre-flight (run these before `/gsd:new-milestone`)

```bash
# 1. Verify branch / main state
git rev-parse --abbrev-ref HEAD   # should be main (or a fresh branch off main)
git status --porcelain            # should be empty
git log --oneline -5              # confirm gui-redesign + channels-redesign merges visible

# 2. Verify rule artifacts
ls JULIA.md                                    # must exist at repo root
ls .claude/skills/mtk* ~/.claude/skills/mtk*   # at least one must exist

# 3. Baseline tests
julia --project=. test/runtests.jl 2>&1 | tail -30
# Note the pass/fail line for the baseline.

# 4. Baseline parity report
awk -F, 'NR>1 {print $7}' test/data/parity_report.csv | sort | uniq -c
# Should show: 424 CLEAN, 78 GRAY, 34 FAIL (per v1.1 close). Locks the baseline.

# 5. Confirm no open audit items
gsd-sdk query audit-open 2>&1 | grep -E '"total"|has_open_items'
```

Surface the results of all five to Itay. He confirms the baseline before you proceed.

---

## Suggested milestone name

`Julia idiom + MTK modernization`

Don't shorten it further. Avoid version numbering in the milestone name; let GSD auto-increment (probably `v1.3`).

---

## Where the rule artifacts live (LOCK THIS BEFORE PHASE 2)

This was discussed with Itay on 2026-05-28. The agreed pattern:

- **`JULIA.md` at repo root.** Referenced from `CLAUDE.md` with a plain-text line like `When writing or editing Julia code, follow the conventions in JULIA.md.` **Not** as an `@`-include — that bloats every session.
- **MTK skill** as a Claude Code skill. Either project-scoped (`.claude/skills/mtk/SKILL.md`) or user-scoped (`~/.claude/skills/mtk/SKILL.md`). Skill description should auto-trigger on MTK keywords.
- **Precedence rule:** MTK skill wins over JULIA.md for MTK-specific code (more-specific-wins). JULIA.md governs everywhere else. State this in JULIA.md itself, near the top.

If Itay has already installed these in a different pattern when you arrive, **respect his pattern**. Don't move them.

---

## Phase breakdown

Total: 7 phases (+ 1 optional). Order is non-negotiable for safety reasons (leaves first, load-bearing physics last).

### Phase A: Install rules + define precedence (one commit, no GSD ceremony)

Not a real "phase" — pre-work to make Phase B+ possible.

- Confirm JULIA.md location and reference it from CLAUDE.md (one-line addition).
- Confirm MTK skill location.
- Write a short `.planning/proposals/julia-idiom-mtk-pass-RULESET.md` (or similar) capturing the precedence rule.
- Single commit: `chore: install JULIA.md reference + MTK skill pointer`.

If JULIA.md already references precedence and skill discovery is working, skip and proceed to Phase B.

### Phase B: Full audit pass — read every `.jl` file, produce findings

**No fixes in this phase. Audit only.**

Use `/gsd:code-review` (or spawn a dedicated audit agent) per cluster. The agent must:

- Load JULIA.md + MTK skill into its context.
- Read every file in the cluster.
- Produce `.planning/phases/N-julia-idiom/AUDIT-<cluster>.md` with findings categorized by severity:
  - **Tier 1: correctness** — actual bugs, wrong MTK patterns that work by accident, deprecated APIs.
  - **Tier 2: idiom** — non-idiomatic Julia, longcuts in MTK, suboptimal but functional.
  - **Tier 3: voice/consistency** — would benefit from rewrite for uniformity but isn't wrong.

Clusters to audit, in this order:

1. `src/fluids.jl` + `src/geometry.jl` + `src/connectors.jl` (leaves)
2. `src/composition/helpers.jl`
3. `src/physical_models/` (all subdirs)
4. `src/components/` except `channels.jl` and `heat_diffusion.jl`
5. `src/components/channels.jl` + `src/components/heat_diffusion.jl` (load-bearing)
6. `src/solvers.jl` + `src/examples.jl`
7. `src/STREAM.jl` (module entry — should be tiny)
8. `test/` (all test files)

Deliverable: one `AUDIT-<cluster>.md` per cluster. Aggregate counts (Tier 1 / Tier 2 / Tier 3) at the top of each.

**Hand the audit to Itay before any fix work starts.** He decides where the cut line goes (e.g., "Tier 1+2 only, Tier 3 deferred").

### Phase C through Phase H: Fix passes, one phase per cluster

Same cluster order as Phase B's audit. Each phase:

1. Read `AUDIT-<cluster>.md`.
2. Plan the fixes (use `/gsd:plan-phase`). Each task = one finding or one cohesive group of findings.
3. Execute (`/gsd:execute-phase`). One atomic commit per task.
4. Run tests after each task. If tests break, **stop and report** — don't push through.
5. Verify parity report unchanged (424/78/34) before phase close.
6. Write `SUMMARY.md` per phase.

**Wave parallelization is fine within a cluster** for independent files, but NOT across clusters (each cluster builds on the previous one's invariants).

### Phase I: Macro consistency pass

After every per-file fix is done, do the cross-file uniformity sweep. This is the "different voice" problem Itay called out — it can only be diagnosed once micro-level fixes are in (otherwise voice differences are confounded with idiom differences).

What to look for:

- Naming conventions diverging across files (`Dh` vs `D_h` vs `hydraulic_diameter`).
- Docstring structure varying (some files have `# Arguments`, some don't, some have `# Examples`).
- Comment density and tone (some files heavily commented, some bare).
- Helper function placement (some inline, some at file bottom, some in separate file).
- Import organization at file tops.
- Type annotation density.

Produce a `CONSISTENCY.md` audit, then apply fixes the same way as Phase C-H.

### Phase J (optional): CI lock-in

Machine-enforced guards so drift doesn't return. Candidates:

- **`Aqua.jl`** — Julia package quality checks. Standard for serious packages.
- **`JET.jl`** — static analysis for type instability and runtime errors.
- **`JuliaFormatter.jl`** with a `.JuliaFormatter.toml` setting the project's style.
- **Doctests** for exported names.
- **GitHub Actions workflow** running all of the above on PR.

Discuss with Itay before adding any of these — each is a maintenance commitment.

---

## Tools per phase

| Phase | Tool |
|-------|------|
| A | Manual edits + single commit |
| B | `/gsd:code-review` scoped per cluster, OR direct `Agent` spawn with `subagent_type: gsd-code-reviewer` and JULIA.md + MTK skill in the prompt |
| C-H | Standard `/gsd:plan-phase` → `/gsd:execute-phase` per cluster |
| I | Custom agent spawn (no existing GSD command matches "cross-file voice audit") |
| J | Manual setup, one PR per tool |

**Do not use `/gsd:audit-fix` for this.** It's too autonomous; the MTK rewrites need Itay's eyes on each change.

---

## Risks to surface to Itay BEFORE Phase B

State these explicitly. Don't bury them.

1. **MTK rewrites can change structural simplification.** Switching how `@variables` are declared, or moving an `unknowns` symbol to `observed`, can cascade into the compiled system having different DAE shape. Even if tests still pass, behavior may shift in untested regions.
2. **Test coverage is incomplete.** Idiom changes can pass tests but break edge cases the tests don't cover. The Python STREAM parity report is the best safety net — verify after every cluster.
3. **Daemon dev loop (`bin/jl`) was removed in the channels-redesign cleanup.** Either restore it (small revert from history, easy) or accept cold-start `julia --project=. ...` for every test invocation. Restoring is probably worth it for this milestone — many test runs ahead.
4. **`src/components/channels.jl` is load-bearing physics.** The d8810e3 cherry-pick (v1.2 close) was a real physics correction. Rewriting this file for "idiom" carries the highest risk. Use Phase F (channels + heat_diffusion) as a separate, slower phase. Don't bundle it with anything else.
5. **The MTK package has a fast release cadence.** "Up-to-date" is a moving target. The MTK skill should pin a specific MTK version it targets; audit only against that version's idioms. Otherwise this milestone never converges.

---

## Hard rules (non-negotiable)

- **All existing tests must continue to pass.** If a test fails after a change, fix the change, not the test. Test changes require Itay's explicit OK.
- **Parity report stays at 424 CLEAN / 78 GRAY / 34 FAIL** (or improves on its own). If a fix moves the needle either direction, surface it before commit.
- **No user-visible API change** (exported names, function signatures, kwarg names) without Itay's explicit decision. Idiom rewrites that preserve API are fine. Renames need approval.
- **Atomic commits.** One finding (or one cohesive group) per commit. No giant "applied 47 fixes" mega-commits.
- **No new features.** This milestone is cleanup only. If you spot a real bug while auditing, file it separately; don't fix it in the same commit as an idiom change.
- **Respect existing `feedback_*` memory entries.** The user has accumulated guidance over many milestones. Re-read MEMORY.md at the start, especially `feedback_keyword_only_rule`, `feedback_ascii_variable_names`, `feedback_power_shape_trust_caller`, `feedback_separate_inertia_from_idiom`, `feedback_smoke_test_scope_match`. These constrain what counts as "more idiomatic."

---

## Done definition

This milestone is shippable when:

- [ ] Every `.jl` file under `src/` and `test/` has been audited against JULIA.md + MTK skill.
- [ ] Every audit finding is either resolved (fixed) or explicitly accepted with a comment in the relevant SUMMARY.md.
- [ ] Cross-file voice is consistent (Phase I complete).
- [ ] Full test suite passes.
- [ ] Parity report unchanged or improved.
- [ ] Optional Phase J done if pursued.
- [ ] Milestone archived via `/gsd:complete-milestone`.

---

## Sequencing relative to other work

- **Before:** wait for `gui-redesign` and `channels-redesign` to fully merge to `main`.
- **During:** keep `main` clean. Do not start other parallel work that touches `src/` or `test/`. The cluster-by-cluster nature means surface area for conflicts is constant.
- **After:** GUI split-out becomes natural. Once the codebase is clean and uniform, extracting `gui/` + `PRODUCT.md` + `DESIGN.md` + `.impeccable/` to a separate repo is a clean one-shot.

---

## What I (the future Claude reading this) should do FIRST

When Itay says something like "let's start the Julia idiom milestone" or invokes this proposal:

1. Read this file in full.
2. Read `JULIA.md` and the MTK skill (locate them per the prerequisites section).
3. Run the pre-flight checks. Report results.
4. Confirm with Itay that the baseline is what he expects.
5. Discuss any risks he wants to flag or carve out.
6. **Only then** run `/gsd:new-milestone`.

Don't skip step 5. The risks list above is what I knew on 2026-05-28; Itay may have new context by the time this is invoked.

---

## Authorship note

This proposal was written by Claude on 2026-05-28 at the end of the v1.2 close-out, after Itay asked for a detailed proposal to act as a future prompt. It is a prompt to my future self. Edit it freely if Itay's plans evolve.

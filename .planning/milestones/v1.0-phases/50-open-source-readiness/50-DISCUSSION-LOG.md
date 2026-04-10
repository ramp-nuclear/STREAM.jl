# Phase 50: Open-Source Readiness - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the discussion.

**Date:** 2026-04-10
**Phase:** 50-open-source-readiness
**Mode:** discuss
**Areas discussed:** README depth & audience, LICENSE choice, Documentation strategy, CI & registry metadata

---

## Gray Areas Presented

| Area | Options Presented |
|------|-------------------|
| README depth & audience | Nuclear engineers / physics audience; Julia/MTK developer audience; Both — two-section |
| LICENSE | MIT; Apache 2.0; GPL v3 |
| Documentation strategy | Docstrings only; Documenter.jl skeleton; Full Documenter.jl site |
| CI setup | Basic Julia CI; Multi-version matrix; No CI |
| Julia General Registry | Prep metadata now; Just clean metadata; No changes |

---

## Decisions Made

### README depth & audience
- **Chosen:** Nuclear engineers / physics audience
- **Lead with:** What STREAM.jl models, not MTK internals
- **Sections:** runnable build_loop example, installation, component catalog, validation summary, Python STREAM relationship

### README — additional content
- **Chosen:** All four: installation instructions, component catalog, validation summary, link to Python STREAM
- **User note:** Sysimage has never reliably worked — must not be presented as a prerequisite

### LICENSE
- **Chosen:** MIT
- **Copyright:** 2026 Itay Benvenisti

### Documentation strategy
- **User asked to think hard on this first**
- **Claude recommendation:** Skip Documenter.jl for Phase 50 — Julia ecosystem is example-driven; expanding examples/ provides more user value with less overhead. Key gap is that there's only one (complex) example. Adding simple_loop.jl and mtr_assembly.jl covers the full workflow.
- **Chosen:** README + expand examples/ — add simple_loop.jl and mtr_assembly.jl

### CI
- **User concern:** Don't want CI to "fuck up" PR workflow
- **Claude clarified:** Basic CI is safe; branch protection rules (which block merges) are optional and not being added. The real risk is pre-existing flaky tests (VAL-01, NET-03) making CI permanently red.
- **Chosen:** Yes — CI + fix the flaky tests properly (not just skip them)

### Julia General Registry
- **Chosen:** Yes — prep metadata now (real UUID, authors, repo URL, version bump to 0.9.0)

### Repo URL
- **User clarified:** Already on GitHub at `https://github.com/itaybnv/STREAM.jl`

### Author / copyright
- **Chosen:** Itay Benvenisti

---

## Deferred Ideas

- **Sysimage fix:** User noted sysimage has never reliably worked — wants a dedicated phase after Phase 50
- **Documenter.jl site:** Deferred to a future phase once project is stable

---

## No Corrections Applied

All choices were first-pass selections — no areas revisited.

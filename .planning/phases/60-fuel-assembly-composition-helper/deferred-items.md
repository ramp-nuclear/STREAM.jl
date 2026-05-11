# Phase 60 — Deferred items discovered during execution

Items below were discovered during plan 60-02 execution but are out of scope
per the executor scope-boundary rule (only auto-fix issues DIRECTLY caused by
the current task's changes). Logged here for future triage.

## Pre-existing test_channels.jl failure

- **Test:** `CAC htc_correlation=dittus_boelter — closed loop solves`
  (test/test_channels.jl line 413)
- **Symptom:** `Test Summary: ... Pass  Error  Total — 2 1 3` — one of the three
  asserts in this testset errors (not fails), with a stack trace through
  `parameter_observed → build_explicit_observed_function` inside MTK codegen.
- **Confirmed pre-existing:** verified by `git stash` of my plan-02 changes and
  re-running `test/test_channels.jl` against the unchanged tree — same failure.
  Phase 60 plan 02 introduces zero changes to `src/components/channels.jl` or
  `test/test_channels.jl`.
- **Scope:** untouched by plan 60-02 (which only modifies test/test_composition.jl
  and adds .planning/notes/fuel-assembly-api.md). Leaving as-is.
- **Recommendation for triage:** this looks like an MTK parameter-observed
  codegen issue specific to `dittus_boelter` in a closed loop; likely an
  upstream MTK upgrade interaction. Worth a small phase to bisect against
  ModelingToolkit versions when a Phase 6X slot opens up.

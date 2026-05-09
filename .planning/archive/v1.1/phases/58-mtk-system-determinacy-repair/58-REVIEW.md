---
phase: 58-mtk-system-determinacy-repair
reviewed: 2026-05-08T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - src/components/flapper.jl
  - test/runtests.jl
  - test/test_channels.jl
  - test/test_determinacy.jl
  - test/test_flapper.jl
  - test/test_heat_diffusion.jl
  - test/test_misc.jl
  - test/test_pump.jl
  - test/test_resistors.jl
  - test/test_validation.jl
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
status: issues_found
---

# Phase 58: Code Review Report

**Reviewed:** 2026-05-08
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Phase 58 is a structural-determinacy repair: it pins the floating
`HeatDiffusion.power(t)` symbolic variable with `hd.power ~ <value>`
algebraic equations on the four scenarios where the variable was previously
unbound (MTR symmetric, MTR asymmetric, MTR one-sided, VAL-01 Fourier,
VAL-02 two-plate), flips those `mtkcompile(...; fully_determined=false)`
audit sites to `=true`, and decorates the remaining legitimate
`fully_determined=false` sites with inline rationale comments. A new
`test/test_determinacy.jl` enforces the contract going forward by calling
`mtkcompile(sys; fully_determined=true)` and asserting `Δ=0` on every
canonical builder and Phase-58 scenario topology. The flapper docstring is
tightened to name the callback-set state.

The phase changes are coherent and the scenario fixes match the new
determinacy harness. Two warnings worth addressing:

1. `src/examples.jl` still documents the **old**, broken access path
   `ssys.sys.T_wall_callable` for `build_loop_transient` callable
   parameters, but the fix in test_validation.jl line 317 confirms the
   correct path is `ssys.T_wall_callable`. The src docstring/comment are
   now inconsistent with the working code path — guaranteed to mislead the
   next caller.
2. The new `assert_determined_compiled` helper in test_determinacy.jl only
   checks `length(equations) == length(unknowns)` on an already-compiled
   system; it does NOT prove the builder internally used
   `fully_determined=true`. A builder that silently flips back to
   `fully_determined=false` could regress without firing this test.

The remaining items are minor (unused `label` parameter on assert helpers,
stale internal comment in `heat_diffusion.jl` about `power` being a
`@parameters` when it is in fact a `@variables`, doc mismatch on `Inf`
vs `1e30` initial sentinel in flapper).

## Warnings

### WR-01: Stale documentation contradicts the Phase 58-04 access-path fix

**File:** `src/examples.jl:202` and `src/examples.jl:250`
**Issue:** Phase 58 commit `65428c3 fix(58-04): use direct T_wall_callable
access in VAL-02 transient` changed the access pattern from
`ssys.sys.T_wall_callable` to `ssys.T_wall_callable` in
`test/test_validation.jl:317`. Both the docstring (line 202) and the
inline implementation comment (line 250) of `src/examples.jl` still
direct callers to use `ssys.sys.T_wall_callable`, which is the broken
path the fix replaced. Any new caller copying from the docstring will
hit the same bug Phase 58-04 just fixed.

The compose call at line 262 — `compose(System(connections, t, [], ps;
name=:sys), ...)` — places `T_wall_callable` at the *top-level* of the
returned compiled system (the `:sys` name is just the name of the
top-level System, not a sub-namespace), so the correct access is
`ssys.T_wall_callable`. The other production caller in
`test/test_integration.jl:192` works around this with
`last(parameters(ssys))`, suggesting the access path was unclear for
a while.

**Fix:** Update both spots in `src/examples.jl` to match the
working pattern that Phase 58-04 established.

```julia
# src/examples.jl:202 (in build_loop_transient docstring)
# was: `ssys.sys.T_wall_callable => T_wall_fn`
# should be:
# `ssys.T_wall_callable => T_wall_fn` (where `ssys` is the compiled system).

# src/examples.jl:250 (inline comment in callable branch)
# was: # Caller must include ssys.sys.T_wall_callable => T_wall_fn in op.
# should be:
# Caller must include ssys.T_wall_callable => T_wall_fn in op.
```

While editing, consider replacing the workaround in
`test/test_integration.jl:192` (`T_wall_sym = last(parameters(ssys))`)
with the same `ssys.T_wall_callable` named access for consistency —
positional `last(...)` is brittle to parameter-reordering changes in
MTK.

---

### WR-02: `assert_determined_compiled` does not actually prove builder used `fully_determined=true`

**File:** `test/test_determinacy.jl:52-55`
**Issue:** The helper for canonical builders only verifies
`length(equations(ssys)) == length(unknowns(ssys))` after the builder has
already called `mtkcompile`. The accompanying comment (lines 41-51) is
honest about the gap: "if Δ ≠ 0, the internal `mtkcompile` would have
either thrown ExtraVariablesSystemException ... or silently returned an
imbalanced compiled system that downstream `process_SciMLProblem.check_eqs_u0`
would reject."

But `mtkcompile` with `fully_determined=false` can perform structural
simplification that produces a system where `equations` and `unknowns`
have **equal length but the system was simplified from an
under-determined input** — the harness would still pass. Concretely, if
a future edit inside `build_loop` flipped `mtkcompile` from default
(`fully_determined=true`) to `=false`, this test would not catch it
because the simplified result can still happen to have balanced lengths.

The Phase-58-scenarios harness (`assert_determined`) does NOT have this
gap because it builds the uncompiled system first and then runs
`mtkcompile(sys; fully_determined=true)`, which raises on imbalance.

**Fix:** Either (a) document this limitation explicitly in the function
docstring so future maintainers don't trust the test more than it
deserves, or (b) refactor each canonical builder to expose an
`uncompiled` variant returning the pre-`mtkcompile` system, and call
`assert_determined` on that uncompiled variant. (a) is the cheap fix:

```julia
"""
    assert_determined_compiled(label::String, ssys)

Length-equality post-condition only. Does NOT prove the builder
internally used `fully_determined=true` — it cannot, because re-compiling
would error with "Double simplification is not allowed". A future edit
that silently flips a builder to `fully_determined=false` will only be
caught here if structural simplification happens to leave the lengths
unequal. For the strict contract, see `assert_determined` (used on
Phase-58 scenario builders, which return uncompiled systems).
"""
function assert_determined_compiled(label::String, ssys)
    @test length(equations(ssys)) == length(unknowns(ssys))
    return ssys
end
```

## Info

### IN-01: Unused `label` parameter on both determinacy helpers

**File:** `test/test_determinacy.jl:35` and `test/test_determinacy.jl:52`
**Issue:** Both `assert_determined(label::String, sys)` and
`assert_determined_compiled(label::String, ssys)` take a `label`
argument that is never read or printed. Every call site passes a
descriptive string (`"build_loop"`, `"MTR sym"`, `"VAL-02"`) but the
labels are silently dropped — they are never surfaced when a `@test`
inside the helper fails. On failure the user gets a stack trace into
`assert_determined` with no scenario context.

**Fix:** Either (a) drop the parameter and its call sites, or (b)
actually use it on failure. (b) gives better diagnostics:

```julia
function assert_determined(label::String, sys)
    ssys = mtkcompile(sys; fully_determined=true)
    n_eq = length(equations(ssys))
    n_uk = length(unknowns(ssys))
    @test n_eq == n_uk
    if n_eq != n_uk
        @info "[$label] Δ = $(n_uk - n_eq)" n_equations=n_eq n_unknowns=n_uk
    end
    return ssys
end
```

The same treatment should be applied to `assert_determined_compiled`.

---

### IN-02: Comment-only edits ride along with logic changes in five files

**Files:**
- `test/test_channels.jl` (5 sites, lines 70, 84, 94, 468, 675, 804, 1087)
- `test/test_misc.jl` (4 sites, lines 19, 37, 71, 131, 178)
- `test/test_pump.jl` (5 sites, lines 18, 36, 68, 83, 99, 133)
- `test/test_resistors.jl` (1 site, line 18)
- `test/test_heat_diffusion.jl` (1 site, line 44)

**Issue:** Phase 58-05 added inline rationale comments
(`# isolated component: ...` / `# legitimate-structural: ...`) to every
remaining `fully_determined=false` site. The comments are accurate and
useful, but the convention is informal — not all comments follow the
same prefix. For example:
- `test/test_misc.jl:34` uses `# T eqs underdetermined (no heat exchange in RL circuit)` (legacy)
  → updated to `# legitimate-structural: pure RL circuit, no T equations exist by design`
- but `test/test_channels.jl:70` uses
  `# isolated component: Channel external-input vars (Phase 55 D-08 Hypothesis-A)`
  with phase reference appended,
- whereas `test/test_pump.jl:36` uses
  `# isolated network: no pressure anchor on rate-equation test`
  (no phase reference).

**Fix:** Optional. If the project wants future grep-ability for
"legitimate" vs "investigate" sites, normalize to two prefixes
(`# isolated component:`, `# isolated network:`, `# legitimate-structural:`,
`# integration test:`) consistently. The current state is readable but
not machine-classifiable.

---

### IN-03: Flapper docstring still understates the `T_open=1e30` design choice

**File:** `src/components/flapper.jl:38-43`
**Issue:** The Phase 58-05 docstring tightening clarifies that `T_open(t)`
is set by an external `ContinuousCallback` and that the system is
"intentionally structurally underdetermined." This is good. However, the
mid-docstring paragraph (lines 12-15) still references `1e30` as a
sentinel without acknowledging that the new sentence in Returns
("`T_open(t)` state is set by an external `ContinuousCallback`")
explains *why* there is no MTK equation for it. A reader scanning Returns
first now sees a partial picture.

**Fix:** Optional polish — add one cross-reference sentence to the
Returns section pointing at the `T_open=1e30` paragraph:

```
Uncompiled `System`. The Flapper's `T_open(t)` state is set by an external
`ContinuousCallback` (see `flapper_callback`), not by an MTK equation, so
the system is intentionally structurally underdetermined. The initial value
`T_open=1e30` (see paragraph above on `Inf` vs sentinel) keeps the valve
closed before the event fires.
...
```

This is purely a docstring quality nit; behavior is correct.

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

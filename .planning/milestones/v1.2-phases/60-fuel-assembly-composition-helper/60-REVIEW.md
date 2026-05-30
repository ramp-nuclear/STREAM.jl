---
phase: 60-fuel-assembly-composition-helper
reviewed: 2026-05-12T00:00:00Z
depth: deep
files_reviewed: 3
files_reviewed_list:
  - src/STREAM.jl
  - src/composition/helpers.jl
  - test/test_composition.jl
findings:
  critical: 0
  warning: 2
  info: 7
  total: 9
status: issues_found
---

# Phase 60: Code Review Report

**Reviewed:** 2026-05-12T00:00:00Z
**Depth:** deep
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 60 adds the `fuel_assembly` composition helper (and the private `_walk_alternation` / `_pair_connections` workers) for alternating Channel-and-Contacts (CAC) / HeatDiffusion (plate) topologies, exports the new public name from `src/STREAM.jl`, and locks behaviour with four parity testsets, four `ArgumentError` testsets, and an uncompiled-system smoke test in `test/test_composition.jl`.

Deep cross-file analysis (import graph, call chains across helper → MTK `connect`/`compose`/`System`, exception-type consistency, MTK pattern compliance) did NOT surface any correctness or security defects. The validation cascade (8 sites, all `ArgumentError`) is internally consistent and the 4-variant alternation logic produces correctly-oriented per-cell `connect()` chains that match the `plate(...)` and `one_sided_connection(...)` spatial-absolute L/R convention. The helper correctly returns a raw uncompiled `ODESystem` — `mtkcompile` is the caller's responsibility, as documented. No MTK pattern violations were found (no `if`/`else` on `Num`, no missing `@register_symbolic`, no premature `mtkcompile` ordering).

Findings are limited to (1) a redundant branch in `_pair_connections` that obscures intent, (2) test coverage gaps for the `start=:plate` axis on mixed and closed variants, (3) an error-type inconsistency between `_infer_n` / `one_sided_connection` (`ErrorException`) and the new `fuel_assembly` (`ArgumentError`) — pre-existing but now reachable through a new public API entry point, and (4) several minor code-quality observations.

## Warnings

### WR-01: `_pair_connections` has redundant branches that produce identical output

**File:** `src/composition/helpers.jl:367-378`
**Issue:** The two non-error branches of `_pair_connections` emit the same comprehension:

```julia
if lk == :c && rk == :p
    return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
elseif lk == :p && rk == :c
    return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
else
    error("fuel_assembly: internal error — adjacent entries share kind :$lk")
end
```

The kind discrimination is therefore vestigial — both branches do `connect(left.thermal_right[i], right.thermal_left[i])`, which is the spatial-absolute L/R convention. Reviewing this for correctness is harder than it needs to be because the structure suggests the wiring depends on kind ordering when it does not. A reader will reasonably assume the `:p→:c` case should swap faces (because the plate is now on the left), and only inspection of `plate(...)` lines 217–230 confirms otherwise.

This is not a behavioural bug (output is correct), but it is a maintainability hazard: a future edit that "fixes" one branch to look different from the other will silently break wiring. The same goes for someone adding a new (kind1, kind2) pair (e.g., plate-to-plate for stacked plate topologies) — the current structure invites them to copy a branch and adjust faces, when faces should NEVER vary by kind under the spatial-absolute convention.

**Fix:** Collapse to a single comprehension and keep the alternation invariant check as a stand-alone guard:

```julia
function _pair_connections(left::Tuple{Symbol,Any}, right::Tuple{Symbol,Any}, n::Int)
    lk, lsys = left
    rk, rsys = right
    # Defense-in-depth: alternation invariant should make this unreachable.
    (lk == :c && rk == :p) || (lk == :p && rk == :c) ||
        error("fuel_assembly: internal error — adjacent entries share kind :$lk")
    # Spatial-absolute L/R convention (matches plate(...) lines 217–230):
    # whichever subsystem is the left member of the pair contributes its
    # thermal_right face; the right member contributes its thermal_left face.
    return [connect(port(lsys, :thermal_right, i), port(rsys, :thermal_left, i)) for i in 1:n]
end
```

### WR-02: `fuel_assembly` propagates `ErrorException` from `_infer_n`, breaking the documented "all validation = ArgumentError" contract

**File:** `src/composition/helpers.jl:502` (call site) and `src/composition/helpers.jl:139-141` (definition)
**Issue:** `fuel_assembly` declares — and the test file at lines 808-836 locks — that caller-input mistakes raise `ArgumentError`. Internally, every direct validation site in `fuel_assembly` (8 of them: bookend kwarg, start kwarg, length-≥1, length consistency, bookend-vs-inferred, mixed-without-start, start-with-non-mixed, closed-with-unequal) uses `throw(ArgumentError(...))`.

But step 7 (line 502) calls `_infer_n(channels[1])`, which on line 139 calls `error(...)` and therefore raises plain `ErrorException`. This is reachable from caller input alone — if a caller passes, e.g., a `HeatDiffusion` instance (no `thermal_left*` subsystems) where a CAC was expected, the user sees `ErrorException` instead of the documented `ArgumentError`. A caller that does `try fuel_assembly(...) catch e; if e isa ArgumentError ... end` will mis-handle this case.

Same applies to a hypothetical future `fuel_assembly` call to `one_sided_connection`'s validator (`error(...)` at line 263) if the composition surface ever grows.

This is technically a pre-existing inconsistency in `_infer_n` / `one_sided_connection`, but Phase 60 makes it more visible by giving `fuel_assembly` a coherent `ArgumentError`-only validation surface for everything else.

**Fix:** Either (a) convert `_infer_n`'s `error(...)` to `throw(ArgumentError(...))` (consistent with the spirit of the new helper and a non-breaking change since `ErrorException` and `ArgumentError` are both subtypes of `Exception` — any `@test_throws ErrorException` test would break though; check first), OR (b) wrap the `_infer_n` call inside `fuel_assembly` in a `try`/`rethrow-as-ArgumentError`:

```julia
# (b) — wrap at the fuel_assembly call site to preserve the public contract
n = try
    _infer_n(channels[1])
catch e
    throw(ArgumentError("fuel_assembly: could not infer thermal-port count from channels[1]; pass an uncompiled ChannelAndContacts (original error: $(sprint(showerror, e)))"))
end
```

Note: existing tests `_infer_n: errors on Channel` (`test_composition.jl:110`) and `_infer_n: errors on ChannelHeatFlux` (line 115) use `@test_throws ErrorException`, so option (a) would break those without also updating them.

## Info

### IN-01: Test coverage gap — `closed=true, start=:plate` is never exercised

**File:** `test/test_composition.jl:705-805` (variant 4)
**Issue:** The closed-ring branch in `fuel_assembly` accepts both `start=:channel` and `start=:plate` (the docstring at line 396 states "the choice only picks which neighbour the wrap pair attaches to first"). Variant 4's testset only covers the default (which becomes `start=:channel` via the auto-fill at line 498). The `start=:plate` axis on `closed=true` is exercised only by the auto-fill default path, not by an explicit caller-supplied value.

Equivalently for the open mixed variant (variant 3, lines 621-703): only `start=:channel` is tested; `bookend=:mixed, start=:plate` is never exercised.

If a future refactor breaks `_walk_alternation`'s `start == :plate` branch (lines 354-358), no parity test would catch it.

**Fix:** Add a mirror parity testset for `start=:plate` on each of variant 3 (open mixed) and variant 4 (closed annular). Hand-rolled sequence for `start=:plate, closed=true, k=3` would be `p1, c1, p2, c2, p3, c3` with wrap `(c3, p1)` — the wiring code path differs from `start=:channel` only in `_walk_alternation`, so two short testsets cover both branches.

### IN-02: Test coverage gap — empty-vector and singleton inputs not tested

**File:** `test/test_composition.jl:807-836` (ArgumentError section)
**Issue:** The ArgumentError validation cascade in `fuel_assembly` includes a length-≥1 guard (line 459-460) that would trip on `channels=[]` or `plates=[]`. No test exercises this. The minimal-input case `channels=[c1], plates=[p1]` (which closed=true would auto-resolve to a 2-element ring) is also untested.

These are not bugs (the code handles them correctly by inspection), but the ArgumentError testset is the natural place to lock them.

**Fix:** Add two short testsets:

```julia
@testset "fuel_assembly — ArgumentError on empty channels" begin
    p1 = _fa_hd(:p1)
    @test_throws ArgumentError fuel_assembly(
        ModelingToolkit.AbstractSystem[], [p1]; name=:bad
    )
end

@testset "fuel_assembly — ArgumentError on empty plates" begin
    c1 = _fa_cac(:c1)
    @test_throws ArgumentError fuel_assembly(
        [c1], ModelingToolkit.AbstractSystem[]; name=:bad
    )
end
```

### IN-03: `_pair_connections` per-pair allocation cost is paid in a hot path

**File:** `src/composition/helpers.jl:367-378`
**Issue:** `_pair_connections` returns a freshly-allocated `Vector` of length `n` per adjacent pair, and `fuel_assembly` collects those into the outer `Equation[...]` comprehension at lines 515-519. For a typical k=2-of-each assembly this is 3-4 pair allocations of n elements each — negligible. For very large `k` (hundreds of plates) this becomes O(k) intermediate vectors. v1 review scope explicitly excludes performance, but the fix is a one-line refactor to a flat double-comprehension that allocates exactly once:

**Fix (out of v1 scope, noted for future):**

```julia
connections = Equation[
    connect(port(seq[m][2], :thermal_right, i),
            port(seq[next_idx(m)][2], :thermal_left, i))
    for m in pair_range
    for i in 1:n
]
```

This also inlines `_pair_connections` away. Trade-off: loses the explicit `_pair_connections` error path (line 376), which is unreachable in practice given `_walk_alternation`'s invariant.

### IN-04: `port` helper's `i::Int` is unnecessarily narrow

**File:** `src/composition/helpers.jl:28`
**Issue:** `port(sys, face::Symbol, i::Int) = ...` requires `i` to be a `Core.Int` (== `Int64` on 64-bit). On 32-bit builds (rare for Julia), or for callers iterating with `i::Int32` / `i::UInt`, this would raise a `MethodError`. Not a Phase 60 regression — pre-existing — but worth noting because Phase 60 increases the number of `port(...)` call sites.

**Fix:** Relax to `i::Integer`:

```julia
port(sys, face::Symbol, i::Integer) = getproperty(sys, Symbol(face, i))
```

### IN-05: Test-file comment block uses a `k` that doesn't match plan-spec language

**File:** `test/test_composition.jl:531-533`
**Issue:** Comment reads "Per D-06 the locked k=2 means the smaller variants get k≥1 channels. Variant 2 uses k=2 channels + k+1=3 plates so 'k' matches the variant-1 cell count." This conflates two meanings of `k`: (a) the cell-count parameter (which is `n=4` for both variants), and (b) the "number of channels/plates" pattern parameter. The actual reading is "variant 2 uses 2 channels + 3 plates", which is `k=2 channels + (k+1)=3 plates` if `k` denotes channel count for the plate-bookended variant. The comment is internally correct but confusingly worded.

**Fix:** Rewrite the comment block to disambiguate `k` (cell count `n` vs. element count in the alternation). Suggest:

```julia
# Variant 2 — plate-bookended: 2 channels + 3 plates (the k-channels / (k+1)-plates
# pattern from §3.12). All channels use n=4 cells to match variant 1's per-cell
# count for cross-variant orthogonality.
```

### IN-06: Defensive `error()` at `_pair_connections:376` is unreachable

**File:** `src/composition/helpers.jl:374-377`
**Issue:** The `else` branch is reachable only if `_walk_alternation` returns adjacent entries with the same `kind`. Inspection of all three branches of `_walk_alternation` (lines 332-360) confirms strict alternation is preserved in every code path. The defensive error therefore acts as documentation, not a runtime check. This is fine, but combined with WR-01 (the redundant `:c→:p` / `:p→:c` branches) it inflates the function size 5×.

**Fix:** Keep the guard, but collapse the body (see WR-01 fix). Net: function shrinks from 12 lines to 6.

### IN-07: Inline `Differential(t)` shortcut `_fa_Dt` could be hoisted to a module-shared test fixture

**File:** `test/test_composition.jl:419`
**Issue:** `_fa_Dt = Differential(t)` is defined as a `const` inside `test/test_composition.jl`. This is fine, but the same pattern recurs in `test/test_integration.jl:262` (per the comment at line 482). A shared `test/test_helpers.jl` (or similar) would deduplicate. Out of Phase 60 scope but noted.

**Fix:** None required for Phase 60. Consider for future cleanup.

---

_Reviewed: 2026-05-12T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

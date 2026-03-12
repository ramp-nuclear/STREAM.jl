# Phase 4: Tech Debt Cleanup - Research

**Researched:** 2026-03-12
**Domain:** Julia/MTK source surgery — parameter renaming, docstring correction, git staging, frontmatter fix
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**BUG-01: Gravity component fix**
- Replace `H` (Julia kwarg Float64 baked into equation) with `H_grav` → rename to just `H` as the MTK `@parameters` symbol
- The equation `port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H` should reference the MTK parameter `H`, not the Julia kwarg — so the parameter is modifiable post-compilation via `setp`
- Remove `A_grav` entirely from both MTK `@parameters` and constructor kwargs — it was never used in any equation
- New Gravity constructor signature: `Gravity(; name, H)` (just height)
- No `D_h` shadowing concern for `H` — it's a plain Float64, not Differential

**Parameter renames (Channel and Friction)**
- **Channel**: `L_ch → L`, `A_ch → A` in MTK `@parameters` declarations
- **Friction**: `L_f → L`, `A_f → A` in MTK `@parameters` declarations
- `D_h` stays as-is in both Channel and Friction — intentionally kept to avoid shadowing `Differential(t)` (the `D` kwarg is aliased to `Dh` Julia variable, then used as `D_h` MTK param)
- These are breaking changes to MTK parameter paths (e.g. `ssys.ch.L_ch` → `ssys.ch.L`) — acceptable since v0.1 has no external downstream users
- Verify no test in `runtests.jl` references old parameter names (`L_ch`, `A_ch`, `L_f`, `A_f`) directly

**BUG-02: solve_steady docstring fix**
- Remove lines referencing `ssys.fr.port_in.mdot => mdot_guess` and `ssys.fr.Re => Re_guess`
- Replace with correct example using `ssys.ch.port_in.mdot => mdot_guess` (Friction was removed from `build_loop` in commit `2e5ed5c`)
- The `Re` algebraic variable no longer needs to be in `op` since it belongs to the removed Friction component

**Stale TDD file removal**
- Delete `test/test_transient_tdd.jl` — crashes if run directly; not included by `runtests.jl`
- Delete `test/test_solvers_tdd.jl` — dead TDD scaffolding; not included by `runtests.jl`
- Stage the unstaged deletion of `test/test_comp_tdd.jl` — use `git add test/test_comp_tdd.jl` to stage

**03-03-SUMMARY.md frontmatter fix**
- Add `VAL-01`, `VAL-02`, `VAL-03` to the `requirements-completed` frontmatter field in `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md`
- These are currently only in the `provides` list as prose; the structured field is what tools read

**solvers.jl future-refactor comment**
- Leave lines 2-6 (future refactor note about wrapper structs) — not in Phase 4 success criteria; it's a useful design note for v0.2

### Claude's Discretion
- Order of changes within the single plan (parameter renames, BUG fixes, file cleanup can be done in any order as long as tests pass at the end)
- Whether to batch into one commit or multiple atomic commits per change type

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 4 is a pure cleanup phase — no new components, no new tests, no new exports. It closes 6 tech debt items identified in the v0.1 milestone audit, all in three source files and one planning document. Every change is surgical and well-scoped.

The most substantive change is BUG-01 (Gravity): the MTK parameter `H_grav` was declared but never referenced in the equation (the Julia Float64 kwarg `H` was used instead). The fix is to make the equation use the MTK symbolic `H` (renaming from `H_grav`), remove the dead `A_grav` parameter, and update `runtests.jl` COMP-04 test to call `Gravity(H=3.0)` without `A_grav`. The parameter renames for Channel and Friction (`L_ch→L`, `A_ch→A`, `L_f→L`, `A_f→A`) are straightforward `@parameters` declaration changes; `runtests.jl` does not reference these names directly so no test code changes are needed for renames. BUG-02 is a two-line docstring fix. File cleanup is three `git rm` / `git add` operations. The SUMMARY frontmatter is a YAML field addition.

**Primary recommendation:** Execute all changes in a single plan with one task per debt item (or one task that batches all six), running `Pkg.test()` after all edits to confirm 54 tests still pass.

---

## Exact Change Inventory

### 1. BUG-01 — `src/components.jl` Gravity (lines 126-141)

**Current state (lines 126-141):**
```julia
function Gravity(; name, H, A_grav)
    pars = @parameters begin
        H_grav = H
        A_grav = A_grav
    end
    ...
    eqs = Equation[
        ...
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,   # BUG: Julia kwarg, not MTK param
        ...
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
```

**Required changes:**
1. Constructor signature: `Gravity(; name, H, A_grav)` → `Gravity(; name, H)`
2. `@parameters` block: remove both `H_grav = H` and `A_grav = A_grav`; add `H = H`
3. Pressure equation: `... * 9.80665 * H` stays as-written BUT now `H` refers to the MTK `@parameters H` symbol, not the Julia Float64 kwarg (which is no longer in scope by the same name — the MTK param shadows it, or the equation is rewritten as `... * 9.80665 * H` where `H` is the MTK symbolic)

**Critical detail:** The rename `H_grav → H` in `@parameters` means the MTK symbolic is now named `H`. The equation `... * H` will then resolve to the MTK symbol `H` rather than the constructor kwarg `H`. Julia resolves `H` in the equation body as the `@parameters` symbol because MTK's DSL captures the symbol name. Confirmed pattern: this is how Channel correctly uses `g_acc` (line 71) — it's declared in `@parameters` and used by name in the equation.

**Test impact:** `runtests.jl` line 151-154:
```julia
@testset "COMP-04: Gravity stub callable" begin
    @named grav = Gravity(H=3.0, A_grav=7.85e-5)   # <-- must change to Gravity(H=3.0)
    @test grav isa ModelingToolkit.System
    @test_nowarn mtkcompile(grav; fully_determined=false)
end
```
This test call passes `A_grav=7.85e-5`; after removing `A_grav` from the constructor, this will error. **The test must be updated to `Gravity(H=3.0)`.**

### 2. Parameter renames — `src/components.jl` Channel (lines 20-25)

**Current:**
```julia
pars = @parameters begin
    L_ch  = L
    D_h   = Dh
    A_ch  = A
    g_acc = g
end
```

**Required:**
```julia
pars = @parameters begin
    L     = L      # was L_ch
    D_h   = Dh     # unchanged
    A     = A      # was A_ch
    g_acc = g      # unchanged
end
```

**Downstream cascade in Channel:** The MTK parameter names `L_ch` and `A_ch` appear only in the `@parameters` declaration — they are NOT referenced by name in the equation body. The Channel equations use the constructor kwarg variables `L`, `A`, `Dh` directly (Julia variables in scope). The equation on line 66: `Re_mean = abs(port_in.mdot) * Dh / (A * mu_water(T[i_mid]))` uses `Dh` and `A` as Julia Float64 locals. The MTK parameter names are only visible for post-compilation symbolic access (e.g., `ssys.ch.L_ch`). Renaming them does NOT affect equation correctness.

**Test impact:** No test in `runtests.jl` references `ssys.ch.L_ch`, `ssys.ch.A_ch`. Safe.

### 3. Parameter renames — `src/components.jl` Friction (lines 101-124)

**Current:**
```julia
pars = @parameters begin
    L_f = L
    D_h = D
    A_f = A
end
```

**Required:**
```julia
pars = @parameters begin
    L   = L    # was L_f
    D_h = D    # unchanged
    A   = A    # was A_f
end
```

**Downstream cascade in Friction:** Same logic as Channel. The equation body uses constructor kwargs `D`, `A`, `L` directly as Julia locals; MTK param names only appear in `@parameters` declaration. No equation changes needed.

**Test impact:** `runtests.jl` line 144-148 calls `Friction(L=1.0, D=0.01, A=7.85e-5)` — constructor kwargs unchanged, safe.

### 4. BUG-02 — `src/solvers.jl` solve_steady docstring (lines 114-116)

**Current lines 114-116:**
```
#       Also include ssys.fr.port_in.mdot => mdot_guess and
#       ssys.fr.Re => Re_guess for the algebraic variables.
```

**Required replacement:**
```
#       Also include ssys.ch.port_in.mdot => mdot_guess
#       for the mass flow algebraic variable.
```

No functional code changes, docstring only.

### 5. Stale TDD file removal

Files to delete:
- `test/test_transient_tdd.jl` — confirmed present, not in `runtests.jl`
- `test/test_solvers_tdd.jl` — confirmed present, not in `runtests.jl`

File to stage (already deleted in working tree per git status):
- `test/test_comp_tdd.jl` — git status shows ` D test/test_comp_tdd.jl` (deleted in working tree, not staged)

Git commands:
```bash
git rm test/test_transient_tdd.jl
git rm test/test_solvers_tdd.jl
git add test/test_comp_tdd.jl   # stages the working-tree deletion
```

### 6. SUMMARY frontmatter — `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md`

**Current frontmatter** (lines 1-49): No `requirements-completed` field exists. The `provides` list contains prose descriptions but the structured field is missing entirely.

**Required addition** — add `requirements-completed` field to YAML frontmatter:
```yaml
requirements-completed: [VAL-01, VAL-02, VAL-03]
```

---

## Standard Stack

This phase requires no new dependencies. All tools are in use:

| Tool | Purpose | Source |
|------|---------|--------|
| Julia (existing) | Execute `Pkg.test()` verification | Project runtime |
| ModelingToolkit.jl (existing) | `@parameters` DSL, `mtkcompile` | Already in Project.toml |
| git (existing) | Stage `test_comp_tdd.jl` deletion, `git rm` stale files | Shell |

**Installation:** None required.

---

## Architecture Patterns

### Pattern 1: MTK `@parameters` — name is the symbolic, value is the default

In MTK's `@parameters begin ... end` DSL:
```julia
@parameters begin
    H = H    # left side = MTK symbolic name; right side = Julia default value
end
```
The left-hand name becomes the symbolic that appears in equations and post-compilation symbolic paths. The right-hand side is the default numeric value. When an equation references `H` after this declaration, MTK captures it as the symbolic `H`, not as the Julia local `H` (the constructor kwarg). This is the established pattern used correctly by `g_acc` in Channel.

**Contrast with the bug:** In the buggy Gravity, `H_grav = H` declares the MTK symbol as `H_grav`, then the equation `... * H` accidentally references the Julia Float64 kwarg `H` still in scope — because `H_grav` and `H` are different names.

### Pattern 2: Constructor kwargs vs MTK parameter names

Julia constructor kwargs serve as default value sources; MTK parameter names serve as the symbolic API. These can differ (e.g., `Dh = D` in Channel, where `D` is the kwarg and `Dh` is the Julia local to avoid Differential shadowing, then `D_h = Dh` in `@parameters`). The convention being aligned in Phase 4: use plain names without component-type suffixes (`L`, `A`, `H` rather than `L_ch`, `A_grav`).

### Pattern 3: Equation body references Julia locals, not MTK symbols

Inside the equation construction loop (before `compose()`), variable names in equations refer to Julia locals still in scope, not to MTK parameter names. MTK's `@parameters` macro replaces the Julia local of the same name with the MTK symbolic. Thus:
- After `@parameters begin L = L end`: `L` in subsequent Julia code is the MTK symbolic
- After `@parameters begin L_ch = L end`: `L` remains the Julia Float64 kwarg; `L_ch` is the MTK symbolic

This is the exact root cause of BUG-01.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Verifying test count | Manual count | `Pkg.test()` output — look for `54 tests passed` |
| Staging the `test_comp_tdd.jl` deletion | Anything elaborate | `git add test/test_comp_tdd.jl` stages a working-tree deletion |
| Checking parameter names in compiled system | String parsing | `parameters(ssys)` returns MTK symbolic list |

---

## Common Pitfalls

### Pitfall 1: `@parameters H = H` shadowing — which `H` is in the equation?

**What goes wrong:** After `@parameters begin H = H end`, the name `H` in Julia scope is now the MTK symbolic (the macro replaces the local). If the equation is written AFTER the `@parameters` block, `H` in the equation IS the MTK symbolic — which is what we want. If (hypothetically) the equation was written before `@parameters`, it would capture the Float64.

**How to avoid:** Write `@parameters` block before building `eqs`. All existing components follow this order already.

**Warning signs:** `BUG-01` was caused by mismatched names (`H_grav` vs `H`) so `H` was never captured as MTK symbolic. After the fix (both named `H`), the pattern works correctly.

### Pitfall 2: Removing `A_grav` from Gravity breaks the COMP-04 test

**What goes wrong:** `runtests.jl` line 151 currently calls `Gravity(H=3.0, A_grav=7.85e-5)`. After removing `A_grav` from the constructor, this call fails with `UndefKeywordError: A_grav`.

**How to avoid:** Update the test call to `Gravity(H=3.0)` simultaneously with the component change.

**Warning signs:** If `Pkg.test()` fails with `UndefKeywordError: keyword argument A_grav not accepted`.

### Pitfall 3: `git add` for an already-deleted file

**What goes wrong:** Trying `git add test/test_comp_tdd.jl` when the file is already deleted from disk is counter-intuitive but correct. `git add` on a deleted file stages the deletion.

**How to avoid:** Use `git add test/test_comp_tdd.jl` (not `git rm`) since the file is already gone from disk.

### Pitfall 4: Channel equations use Julia locals `A` and `L`, not MTK params

**What goes wrong:** After renaming `@parameters begin L = L; A = A end` in Channel, one might worry that internal equations break. They don't — the equations use the MTK symbolics which are now named `L` and `A` (same as the locals they replaced).

**How to avoid:** The only equation that uses `L` directly (not via `dz = L / n`) is the scalar `dP` equation on line 70: `(L / Dh)`. After renaming, `L` in the equation is the MTK symbolic `L` — still correct.

### Pitfall 5: Friction equations use `D`, `A`, `L` as Julia locals

**What goes wrong:** In Friction, the `@parameters` block is `L_f = L; D_h = D; A_f = A`. After the rename to `L = L; D_h = D; A = A`, the Julia locals `L` and `A` become MTK symbolics. The equations at lines 116-119 use `D`, `A`, `L` directly. After rename: `A` and `L` become MTK symbolics (good), `D` remains a Julia Float64 kwarg (since `D_h = D` renames it, `D` stays as-is). No equation changes needed.

---

## Code Examples

### Corrected Gravity component
```julia
# Source: CONTEXT.md decisions + audit BUG-01 description
function Gravity(; name, H)                  # A_grav removed
    pars = @parameters begin
        H = H                                # MTK param named H (was H_grav)
    end
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    T_in = instream(port_in.T)
    eqs = Equation[
        port_in.mdot + port_out.mdot ~ 0,
        port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H,  # H is now MTK symbolic
        port_out.T ~ instream(port_in.T),
        port_in.T  ~ instream(port_out.T),
    ]
    compose(System(eqs, t, [], pars; name=name), port_in, port_out)
end
```

### Corrected Channel @parameters block
```julia
# Source: CONTEXT.md decisions
pars = @parameters begin
    L     = L      # was L_ch
    D_h   = Dh     # unchanged
    A     = A      # was A_ch
    g_acc = g      # unchanged
end
```

### Corrected Friction @parameters block
```julia
# Source: CONTEXT.md decisions
pars = @parameters begin
    L   = L    # was L_f
    D_h = D    # unchanged
    A   = A    # was A_f
end
```

### Corrected solve_steady docstring (lines 111-121)
```julia
# ssys: compiled system from build_loop()
# op:   Vector{Pair} of symbolic_var => initial_value
#       Use symbols from ssys (compiled), e.g. ssys.ch.T[1] => 315.0
#       Build the initial guess using steady_state_guess() for T cells.
#       Also include ssys.ch.port_in.mdot => mdot_guess
#       for the mass flow algebraic variable.
#
# Returns SteadyStateSolution. Access results via symbolic indexing:
#   sol[ssys.ch.T_out]              outlet temperature (K)
#   sol[ssys.ch.port_in.mdot]       mass flow (kg/s)
```

### Updated COMP-04 test
```julia
# runtests.jl line 151 — A_grav removed from call
@testset "COMP-04: Gravity stub callable" begin
    @named grav = Gravity(H=3.0)             # was Gravity(H=3.0, A_grav=7.85e-5)
    @test grav isa ModelingToolkit.System
    @test_nowarn mtkcompile(grav; fully_determined=false)
end
```

### SUMMARY frontmatter addition
```yaml
requirements-completed: [VAL-01, VAL-02, VAL-03]
```

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Julia Test stdlib + Test.jl |
| Config file | `test/runtests.jl` |
| Quick run command | `julia --project -e "using Pkg; Pkg.test()"` |
| Full suite command | `julia --project -e "using Pkg; Pkg.test()"` |

### Phase Requirements → Test Map

Phase 4 has no new requirements (quality/cleanup). The validation gate is regression: all 54 existing tests must still pass after every change.

| Behavior | Test Type | Automated Command | Current Status |
|----------|-----------|-------------------|----------------|
| Gravity compiles with new signature `Gravity(H=3.0)` | unit | `Pkg.test()` — COMP-04 testset | Needs test update |
| Channel compiles after `L`/`A` rename | unit | `Pkg.test()` — COMP-01 testsets | No test change needed |
| Friction compiles after `L`/`A` rename | unit | `Pkg.test()` — COMP-03 testset | No test change needed |
| Full 54-test suite passes after all changes | regression | `julia --project -e "using Pkg; Pkg.test()"` | Must be green at phase end |

### Sampling Rate
- **Per task commit:** `julia --project -e "using Pkg; Pkg.test()"` — must show 54 passed
- **Phase gate:** Same — full suite green before `/gsd:verify-work`

### Wave 0 Gaps
None — existing test infrastructure covers all regression requirements. The only test change is updating COMP-04 to use `Gravity(H=3.0)` instead of `Gravity(H=3.0, A_grav=7.85e-5)`.

---

## Open Questions

1. **Does Channel's `dP` equation need `L_ch` renamed?**
   - What we know: Line 70 uses `L` (Julia local) in `(L / Dh)`. After `@parameters begin L = L end`, `L` is the MTK symbolic. The equation is evaluated AFTER the `@parameters` block, so `L` resolves to the MTK symbolic. Correct.
   - What's unclear: Whether MTK captures the symbolic `L` in the expression `dz = L / n` which is computed BEFORE `@parameters`. `dz` is computed as a Julia Float64 (`dz = L / n` where `L` is the Float64 kwarg at that point) — this is fine because `dz` is used as a Float64 literal in the loop.
   - **Resolution:** No issue — `dz` computation uses the Float64 `L` kwarg (before `@parameters`). Equation body uses the MTK symbolic `L` (after `@parameters`). This matches the existing pattern.

2. **Should `requirements-completed` be a YAML list or space-separated string?**
   - What we know: The SUMMARY frontmatter for other plans (e.g., 01-01, 01-02) uses YAML list syntax.
   - Recommendation: Use YAML list `[VAL-01, VAL-02, VAL-03]` — consistent with project convention.

---

## Sources

### Primary (HIGH confidence)
- `src/components.jl` (read directly) — exact current state of all three component functions
- `src/solvers.jl` (read directly) — exact current state of solve_steady docstring
- `test/runtests.jl` (read directly) — confirmed no references to `L_ch`, `A_ch`, `L_f`, `A_f`; found `A_grav` reference at line 151
- `.planning/phases/04-tech-debt-cleanup/04-CONTEXT.md` (read directly) — all decisions locked
- `.planning/v0.1-MILESTONE-AUDIT.md` (read directly) — authoritative list of 6 tech debt items
- `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md` (read directly) — confirmed missing `requirements-completed` field
- git status output — confirmed `test/test_comp_tdd.jl` is deleted in working tree (` D`)

### Secondary (MEDIUM confidence)
- MTK `@parameters` DSL behavior: reasoning from observed correct pattern (`g_acc` in Channel) cross-referenced with BUG-01 root cause analysis

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Change inventory: HIGH — all changes read directly from source files
- BUG-01 fix mechanics: HIGH — verified against existing `g_acc` pattern in same file
- Test impact: HIGH — runtests.jl read directly, `A_grav` reference at line 151 confirmed
- Parameter rename safety: HIGH — equations verified not to use MTK param names directly
- Git staging mechanics: HIGH — standard git operations

**Research date:** 2026-03-12
**Valid until:** Indefinite (code and plan files are stable; no external dependencies)

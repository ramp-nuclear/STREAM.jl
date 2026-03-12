# Phase 4: Tech Debt Cleanup - Context

**Gathered:** 2026-03-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix all 6 tech debt items from the v0.1 audit: BUG-01 (Gravity MTK parameter unused), BUG-02 (stale docstring), Channel/Friction parameter renames, stale TDD file removal, and SUMMARY frontmatter fix. No new physics, no new components, no new exports — pure cleanup. Verify `Pkg.test()` still passes 54 tests after every change.

</domain>

<decisions>
## Implementation Decisions

### BUG-01: Gravity component fix
- Replace `H` (Julia kwarg Float64 baked into equation) with `H_grav` → rename to just `H` as the MTK `@parameters` symbol
- The equation `port_in.P - port_out.P ~ rho_water(T_in) * 9.80665 * H` should reference the MTK parameter `H`, not the Julia kwarg — so the parameter is modifiable post-compilation via `setp`
- Remove `A_grav` entirely from both MTK `@parameters` and constructor kwargs — it was never used in any equation
- New Gravity constructor signature: `Gravity(; name, H)` (just height)
- No `D_h` shadowing concern for `H` — it's a plain Float64, not Differential

### Parameter renames (Channel and Friction)
- **Channel**: `L_ch → L`, `A_ch → A` in MTK `@parameters` declarations
- **Friction**: `L_f → L`, `A_f → A` in MTK `@parameters` declarations
- `D_h` stays as-is in both Channel and Friction — intentionally kept to avoid shadowing `Differential(t)` (the `D` kwarg is aliased to `Dh` Julia variable, then used as `D_h` MTK param)
- These are breaking changes to MTK parameter paths (e.g. `ssys.ch.L_ch` → `ssys.ch.L`) — acceptable since v0.1 has no external downstream users
- Verify no test in `runtests.jl` references old parameter names (`L_ch`, `A_ch`, `L_f`, `A_f`) directly

### BUG-02: solve_steady docstring fix
- Remove lines referencing `ssys.fr.port_in.mdot => mdot_guess` and `ssys.fr.Re => Re_guess`
- Replace with correct example using `ssys.ch.port_in.mdot => mdot_guess` (Friction was removed from `build_loop` in commit `2e5ed5c`)
- The `Re` algebraic variable no longer needs to be in `op` since it belongs to the removed Friction component

### Stale TDD file removal
- Delete `test/test_transient_tdd.jl` — crashes if run directly (references `ssys.fr.*` and old `Q_wall_sym` semantics); not included by `runtests.jl`
- Delete `test/test_solvers_tdd.jl` — dead TDD scaffolding; not included by `runtests.jl`
- Stage the unstaged deletion of `test/test_comp_tdd.jl` — file was deleted in working tree but deletion not yet committed; use `git add test/test_comp_tdd.jl` to stage

### 03-03-SUMMARY.md frontmatter fix
- Add `VAL-01`, `VAL-02`, `VAL-03` to the `requirements-completed` frontmatter field in `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md`
- These are currently only in the `provides` list as prose; the structured field is what tools read

### solvers.jl future-refactor comment
- Leave lines 2-6 (future refactor note about wrapper structs) — not in Phase 4 success criteria; it's a useful design note for v0.2

### Claude's Discretion
- Order of changes within the single plan (parameter renames, BUG fixes, file cleanup can be done in any order as long as tests pass at the end)
- Whether to batch into one commit or multiple atomic commits per change type

</decisions>

<specifics>
## Specific Ideas

- BUG-01 root cause: `Gravity(; name, H, A_grav)` declares `@parameters H_grav = H`, `A_grav = A_grav` but the pressure equation was written as `... * H` (using the Julia kwarg Float64, not the MTK symbolic). Fix is literally one character: `H` → `H_grav` in the equation — then rename the MTK param to just `H` for cleaner API.
- The `test_comp_tdd.jl` deletion is already in the git working tree (shown as ` D test/test_comp_tdd.jl` in git status) — just stage it.
- After all parameter renames, `runtests.jl` uses symbolic indexing like `ssys.ch.T_out`, `ssys.ch.port_in.mdot` — verify none of these paths use the renamed parameters.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/components.jl`: Channel (lines 15-84), Friction (lines 101-124), Gravity (lines 126-141) — all three need changes
- `src/solvers.jl`: `solve_steady` docstring (lines 113-121) — needs BUG-02 fix
- `test/runtests.jl`: existing test suite — run to verify 54 tests still pass after changes
- `.planning/phases/03-integration-and-validation/03-03-SUMMARY.md`: frontmatter needs `requirements-completed` field

### Established Patterns
- MTK parameter naming: use plain names (`L`, `A`, `H`) not suffixed names (`L_ch`, `A_f`, `H_grav`) for cleaner API — Phase 4 aligns all components to this
- `D_h` exception: kept as-is because constructor kwarg `D` aliases to `Dh` to avoid Differential shadowing; the MTK param name `D_h` is a visible consequence of this alias
- All changes must leave 54 tests green (`julia --project -e "using Pkg; Pkg.test()"`)

### Integration Points
- `test/runtests.jl` uses: `ssys.ch.T[i]`, `ssys.ch.T_out`, `ssys.ch.port_in.mdot` — these paths don't use renamed params, should be unaffected
- Phase 2 isolation tests use `mtkcompile(Channel(...); fully_determined=false)` — column names in `observed(sys)` may shift but no test asserts on parameter names
- No external downstream users of v0.1 API — breaking parameter rename is acceptable

</code_context>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope

</deferred>

---

*Phase: 04-tech-debt-cleanup*
*Context gathered: 2026-03-12*

# Phase 60: fuel-assembly-composition-helper — Pattern Map

**Mapped:** 2026-05-11
**Files analyzed:** 4 (3 source/test + 1 handoff note)
**Analogs found:** 4 / 4 (all in-tree, all strong matches)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/composition/helpers.jl` (append `fuel_assembly`) | composition helper | transform (Vector{System} → ODESystem) | `src/composition/helpers.jl` `plate(...)` lines 217–230 | exact (same file, same role, alternating CAC↔Plate triplets are the generalization of `plate`'s single triplet) |
| `src/STREAM.jl` (extend `export` list) | module entry | declarative export | `src/STREAM.jl` line 98 (`export symmetric_plate, plate, one_sided_connection, compose_systems`) | exact (same line, same family) |
| `test/test_composition.jl` (4 new variant test sets) | test | parity gate (helper vs hand-rolled) | `test/test_composition.jl` Sections 4–6 (symmetric_plate / plate / one_sided_connection) | exact (same file, established parity-test shape; the `_mtr_pair` fixture is reusable for `fuel_assembly` variants) |
| `.planning/notes/fuel-assembly-api.md` (new) | handoff doc | Phase 60 → Phase 61 spec | `.planning/notes/correlation-geom-first-api.md` | exact (same role: small `src/` change + Phase 61 handoff note; Phase 60 CONTEXT D-07 explicitly cites this as the sibling pattern) |

---

## Pattern Assignments

### File 1: `src/composition/helpers.jl` (append `fuel_assembly`)

**Analog file:** `src/composition/helpers.jl` (same file — extend, do not refactor existing helpers).

**Three precedents work together inside this one file:**

#### (a) Wiring-shape precedent — `plate(...)` lines 217–230

Canonical per-cell triplet (CAC↔Plate↔CAC). `fuel_assembly` walks this for every adjacent (channel, plate, channel) triplet in the alternation:

```julia
function plate(ch_left, ch_right, fuel; name::Symbol)
    n = _infer_n(ch_left)
    connections = Equation[
        [
            connect(port(ch_left, :thermal_right, i), port(fuel, :thermal_left, i)) for
            i in 1:n
        ]...,
        [
            connect(port(ch_right, :thermal_left, i), port(fuel, :thermal_right, i)) for
            i in 1:n
        ]...,
    ]
    compose(System(connections, t; name=name), ch_left, ch_right, fuel)
end
```

**Things the executor must NOT diverge from here:**
- `Equation[ [comprehension]..., [comprehension]..., ]` array-literal-with-splat shape. Do NOT use `vcat`, do NOT use `append!`, do NOT use a growing `push!` loop. The `Equation[ ... ]` typed literal + `...` splat is the established idiom across this file (see `symmetric_plate` lines 176–183, `plate` lines 219–228, `one_sided_connection` lines 266–274).
- `compose(System(connections, t; name=name), channels..., plates...)` — exact shape. `t` is `ModelingToolkit.t_nounits as t`, imported at top of `STREAM.jl`. `name=name` is keyword-only. `channels...` and `plates...` are positional varargs to `compose()` (works because `compose` accepts an arbitrary positional system list — confirmed by `compose_systems` line 305).
- Helper returns the **raw uncompiled** `ODESystem`. Do NOT call `mtkcompile()` inside `fuel_assembly`. This is the universal contract across this file: caller compiles, caller passes `build_initializeprob=false` for HD+CAC.
- Sub-component names round-trip the caller's `@named`. After `compose(System(...; name=:assembly), c1, c2, p1)`, the children are reachable as `assembly.c1`, `assembly.p1`. Do NOT rename to `cac1`/`plate1` (D-04 / `<code_context>` last bullet).

#### (b) Kwarg-validation precedent — `one_sided_connection(...)` lines 261–263

```julia
function one_sided_connection(channel, fuel; side::Symbol=:left, name::Symbol)
    side in (:left, :right) ||
        error("one_sided_connection: side must be :left or :right, got :$side")
    ...
```

**D-02 / D-03 mirror this exactly.** Executor must produce:

```julia
bookend in (:auto, :channel, :plate, :mixed) ||
    error("fuel_assembly: bookend must be :auto, :channel, :plate, or :mixed, got :$bookend")
start === nothing || start in (:channel, :plate) ||
    error("fuel_assembly: start must be :channel, :plate, or nothing, got :$start")
```

**Do NOT diverge:**
- Use `error(...)` (the existing idiom in this file), not `throw(ArgumentError(...))`. Other helpers in this file use plain `error()`; the test file uses `@test_throws ErrorException` (line 306) which matches `error()`. If `ArgumentError` is needed by D-06's "ArgumentError paths" test cases, **note the mismatch** — the test expectations in CONTEXT D-06 say `ArgumentError`, but the established helper precedent says `error()`. Planner should resolve: either (a) use `throw(ArgumentError("..."))` and update D-06 test expectations to `@test_throws ArgumentError`, or (b) use `error(...)` matching precedent and update D-06 wording to `@test_throws ErrorException`. **Recommendation: option (a) — `ArgumentError` is semantically right for caller-input mistakes and D-06 already specified it.** Either way, be internally consistent across helper + tests.
- Error message format: `"fuel_assembly: <problem>, got :<value>"`. The existing file uses `<name>: <constraint>, got :<value>` shape.
- Validate kwargs **before** doing any `_infer_n` work — fail fast on caller errors.

#### (c) Port-count detection — `_infer_n(sys)` lines 136–143

```julia
function _infer_n(sys)
    sub_names = string.(ModelingToolkit.getname.(ModelingToolkit.get_systems(sys)))
    n = count(s -> startswith(s, "thermal_left"), sub_names)
    n == 0 && error(
        "_infer_n: could not detect thermal port count in system $(ModelingToolkit.getname(sys)). Pass an uncompiled ChannelAndContacts instance.",
    )
    return n
end
```

`fuel_assembly` calls this **once** on `channels[1]` (per D-05 — caller responsibility, no homogeneity validation across the vector). Use the result as the per-cell loop bound `for i in 1:n`. Mismatched `n` across the vector is caught by MTK at `mtkcompile()` time — do not pre-validate.

#### (d) Indexed port access — `port(sys, face::Symbol, i::Int)` line 28

```julia
port(sys, face::Symbol, i::Int) = getproperty(sys, Symbol(face, i))
```

Use this for every `connect()` call. **Do NOT** write `cac.thermal_left[i]` or `getproperty(cac, Symbol("thermal_left$i"))` directly — `port()` is the only correct MTK syntax for indexed port array access in this codebase (line 28 docstring is explicit).

#### Layout note

Place the new `fuel_assembly` block **after `one_sided_connection` (ends line 277) and before `compose_systems` (line 280)** OR **after `compose_systems` (line 306) and before `connect_temperature_feedback` (line 308)**. CONTEXT line 207 says "appended after existing helpers (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`)", so the second position is the locked one — slot `fuel_assembly` between `compose_systems` and `connect_temperature_feedback`.

#### Docstring shape (mandatory per CLAUDE.md "Component authoring conventions")

Every exported helper in this file has the structure: opening signature line, one-line description, `# Arguments`, `# Returns`, scoped-reference note. Match this. Use `symmetric_plate`'s docstring (lines 157–173) as the template; extend with `# Examples` block containing one canonical call per variant (CONTEXT `<specifics>` gives the verbatim shapes).

---

### File 2: `src/STREAM.jl` (extend export list)

**Analog:** `src/STREAM.jl` line 98.

**Existing precedent:**

```julia
export symmetric_plate, plate, one_sided_connection, compose_systems
```

**Action:** add `fuel_assembly` to this exact line. Result:

```julia
export symmetric_plate, plate, one_sided_connection, compose_systems, fuel_assembly
```

**Things the executor must NOT diverge from:**
- All public exports live in `STREAM.jl` — never add `export fuel_assembly` inside `helpers.jl`. CLAUDE.md `## Exports` section is explicit: "Never add `export` statements inside component files."
- Keep the export on the same line as the other composition helpers (logical grouping). The codebase groups exports by domain (fluids, components, correlations, composition, point kinetics, scram).
- Internal helpers introduced by the planner (`_walk_alternation`, `_assembly_connections`, etc.) get `_` prefix and are NOT exported (CLAUDE.md component-authoring convention #5).

---

### File 3: `test/test_composition.jl` (4 new variant test sets)

**Analog:** `test/test_composition.jl` Section 4 (`symmetric_plate` parity tests, lines 126–226) and Section 7 (`compose_systems` cross-plate wiring, lines 313–341).

**Reusable fixture (already in file, lines 15–25):**

```julia
function _mtr_pair(; n=4, nz=4, nx=2)
    geom = PipeGeometry_rectangular(0.6, 0.070, 0.0025, 0.070)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named cac = ChannelAndContacts(; n=n, geometry=geom,
                                    htc_correlation=constant_Nusselt(; Nu=8.235),
                                    friction_correlation=laminar_friction(geom))
    @named fuel = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=0.005,
                                 y=0.07, rho_s=19300.0, cp_s=116.0, k_s=174.0,
                                 power_shape=ps)
    return cac, fuel
end
```

The variant tests call `_mtr_pair(...)` repeatedly (with unique component names — see "Naming caveat" below) to build the channel/plate vectors.

**Established testset shape (from Section 4, lines 126–151):**

```julia
@testset "symmetric_plate(cac, fuel) — n=4, nz=4, nx=2 compiles cleanly" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    rods = symmetric_plate(cac, fuel; name=:rods)
    @test rods isa ModelingToolkit.AbstractSystem
    # Add the missing power binding + a pump loop to make it solvable
    @named pump = Pump(3.0e4)
    @named bc = HeatExchanger(313.15)
    conns = [
        connect(pump.port_out, bc.port_in),
        connect(bc.port_out, rods.cac.port_in),
        connect(rods.cac.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
        rods.fuel.power ~ 1.0e3,
    ]
    full = compose_systems(rods, pump, bc; connections=conns, name=:full)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    # Solve briefly to verify composition produces meaningful steady state
    ic = Pair{Any,Any}[
        [ssys.rods.cac.T[i] => 313.15 for i in 1:4]...,
        [ssys.rods.fuel.T[i, j] => 313.15 for i in 1:4 for j in 1:2]...,
        ssys.rods.cac.port_in.mdot => 0.2,
    ]
    sol = solve_transient(ssys, ic, range(0.0, 0.5, length=10))
    @test sol.retcode == ReturnCode.Success
end
```

**For the four `fuel_assembly` variants, per D-06 the parity gate is:**
1. Build the system via `fuel_assembly(...)` at a representative `k` (k=2 for variants 1/2/3, k=3 for variant 4).
2. Build the same system by hand-rolling the `connect()` chain (no helper).
3. Add identical BCs (pump loop, pressure anchor, power) to both.
4. `mtkcompile(...)` both.
5. Use the same IC vector and call `solve_steady(ssys, ic)` on both (D-06 says `solve_steady`, not `solve_transient` — diverges from the symmetric_plate fixture which uses `solve_transient`; planner should pick `solve_steady` to match D-06).
6. Compare unknown vectors pointwise: `@test isapprox(sol_helper.u, sol_hand.u; rtol=1e-10)` or equivalent.

**ArgumentError paths (D-06):** mirror `test/test_composition.jl` line 304–307:

```julia
@testset "one_sided_connection — invalid side errors" begin
    cac, fuel = _mtr_pair(; n=4, nz=4, nx=2)
    @test_throws ErrorException one_sided_connection(cac, fuel; side=:bogus, name=:bad)
end
```

For `fuel_assembly`, the four `@test_throws ArgumentError` cases (or `ErrorException` if planner chose option (b) above) are:
- explicit `bookend` conflicting with lengths
- `bookend=:mixed` without `start`
- `start` set with non-mixed bookend
- `closed=true` with unequal lengths

**Smoke test (D-06 last bullet):** assert helper returns an uncompiled `ODESystem`:

```julia
@test rods isa ModelingToolkit.AbstractSystem
```

(taken verbatim from line 129).

**Naming caveat for the parity tests:** when building 3+ CACs for variant 1 (channel-bookended k=2), each `@named cac = ChannelAndContacts(...)` inside `_mtr_pair` will produce the same Symbol `:cac`. MTK rejects duplicate-named subsystems inside a `compose()` call. **Two options:**
- Build per-test custom `@named c1 = ChannelAndContacts(...); @named c2 = ...; @named c3 = ...` inline (the canonical pattern, used in `compose_systems` Section 7, lines 313–341).
- Add a `_mtr_pair_named(prefix; ...)` helper that takes a name prefix. Optional refactor; the planner can decide based on call-site verbosity.

**Section placement:** insert the new `fuel_assembly` testsets after Section 7 (line 341) and before Section 8 (line 343). Section 9 is the natural slot.

---

### File 4: `.planning/notes/fuel-assembly-api.md` (new handoff note)

**Analog:** `.planning/notes/correlation-geom-first-api.md` (Phase 59's handoff note, 175 lines, read in full above).

**Why it's the analog:** CONTEXT D-07 explicitly names it as the sibling pattern. Same role (Phase N → Phase 61 spec hand-off), same audience (Phase 61's `codeGenerator.ts` + `components.json` rewrite), same scope (small `src/` change + Phase 61 note).

**Skeleton to follow (extracted from `correlation-geom-first-api.md` headings):**

```markdown
# Fuel-assembly composition helper — Post-Phase-60 surface

**Status:** Canonical handoff artifact for Phase 61 (GUI codeGenerator + registry rewrite).
**Source decision:** Phase 60 CONTEXT.md `<decisions>` D-07.
**Companion document:** `.planning/notes/gui-redesign-design-decisions.md` §3.12 (`fuel_assembly` Composition Helper).
**Scope:** Captures the post-Phase-60 helper API + GUI topology-detection rule. Does NOT replace docstrings.

Phase 60 landed in N plans on the `gui-redesign` working branch: [filled in at archive time].

---

## Helper signature

[verbatim final signature from CONTEXT D-04, with each kwarg's semantics from D-02 / D-03 / D-05]

## The four variants (ascii-art, copied from §3.12)

[four ascii-art diagrams: channel-bookended, plate-bookended, mixed, closed-annular]

## Topology-detection rule spec (Phase 61 GUI input)

[the spec table from CONTEXT `<specifics>` line 354–361, expanded:]

| Variant | Bookend | Equal counts | Closed | Topology rule (GUI) |
|---------|---------|--------------|--------|---------------------|
| 1 | :channel | no  | false | endpoints are both CAC; len(CAC)=len(plate)+1 |
| 2 | :plate   | no  | false | endpoints are both HD;  len(plate)=len(CAC)+1 |
| 3 | :mixed   | yes | false | endpoints differ; equal counts; no wraparound |
| 4 | :mixed   | yes | true  | equal counts; first and last share thermal edge |

## Endpoint / wraparound rules

[which port-array index goes to which face on which neighbour — concrete pseudo-code for the Phase 61 codeGenerator emitter]

## GUI registry implications (Phase 61 guidance)

[parallel to Phase 59 note's section of the same name — what fields the registry shows, what defaults, what foreign keys]

---

*Phase 60 handoff artifact. Last updated [date].*
```

**Things the executor must NOT diverge from:**
- Keep the note Phase-61-consumable: every claim should be actionable by the codeGenerator without re-reading `src/`.
- File path: exactly `.planning/notes/fuel-assembly-api.md` (sibling to `correlation-geom-first-api.md`). Do NOT nest it under `.planning/phases/60-.../`.
- The handoff note is a **deliverable of Phase 60**, not a planning artifact. It survives phase archival.

---

## Shared Patterns

### Composition helper contract (applies to File 1)

**Source:** every helper in `src/composition/helpers.jl` (`symmetric_plate`, `plate`, `one_sided_connection`, `compose_systems`).

```julia
function <helper>(positional_components...; <validation_kwargs>, name::Symbol)
    # 1. Validate kwargs first (error fast)
    # 2. _infer_n(<first component>) for per-cell loop bound
    # 3. Build connections = Equation[ [comprehension]..., [comprehension]..., ]
    # 4. Return raw uncompiled ODESystem
    compose(System(connections, t; name=name), components...)
end
```

**Apply to:** `fuel_assembly`. This is the universal shape — no helper in this file deviates.

### Kwarg-validation idiom (applies to File 1)

**Source:** `one_sided_connection` line 262.

```julia
<kwarg> in (<allowed_values>...) || error("<helper>: <kwarg> must be ..., got :<value>")
```

**Apply to:** `bookend` and `start` validation in `fuel_assembly`. (See File 1 note about `error()` vs `ArgumentError` — recommend `ArgumentError` for fuel_assembly to match D-06 expectations.)

### Parity-test shape (applies to File 3)

**Source:** Sections 4–6 of `test/test_composition.jl`.

```julia
@testset "<helper>(...) — <variant> compiles cleanly" begin
    components = _mtr_pair(; ...)
    composed = <helper>(components...; name=:rods)
    @test composed isa ModelingToolkit.AbstractSystem
    # add BCs (pump loop, pressure anchor, power) via compose_systems
    full = compose_systems(composed, pump, bc; connections=conns, name=:full)
    ssys = mtkcompile(full)
    @test ssys isa ModelingToolkit.AbstractSystem
    # optional: solve to verify steady state
    ic = Pair{Any,Any}[...]
    sol = solve_steady(ssys, ic)  # or solve_transient for symmetric_plate-style
    @test sol.retcode == ReturnCode.Success
end
```

**Apply to:** all four variant testsets in File 3, with the parity comparison (`isapprox(sol_helper.u, sol_hand.u; rtol=1e-10)`) added per D-06.

### Handoff-note structure (applies to File 4)

**Source:** `.planning/notes/correlation-geom-first-api.md`.

Sections in order: title + status block, API surface table, canonical example block, "Not touched" / "GUI registry implications" / "Validation status" sections, footer date.

---

## No Analog Found

None. All four files have strong in-tree analogs.

---

## Metadata

**Analog search scope:**
- `src/composition/helpers.jl` (full file, 367 lines, read in full)
- `src/STREAM.jl` (full file, 104 lines, read in full)
- `test/test_composition.jl` (full file, 377 lines, read in full)
- `.planning/notes/correlation-geom-first-api.md` (full file, 175 lines, read in full)
- `CLAUDE.md` (project conventions, read in full)

**Files scanned:** 5
**Pattern extraction date:** 2026-05-11

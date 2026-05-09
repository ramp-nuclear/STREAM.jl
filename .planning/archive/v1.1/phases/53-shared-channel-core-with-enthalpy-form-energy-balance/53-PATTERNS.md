# Phase 53: Shared `_channel_core` with Enthalpy-Form Energy Balance — Pattern Map

**Mapped:** 2026-05-06
**Files analyzed:** 4 (1 modified, 2 created, 1 wired)
**Analogs found:** 4 / 4

This pattern map is a navigation aid for the planner. CONTEXT.md (D-01..D-14) and RESEARCH.md are locked; the design is not revisited here. All analogs cited live in this repo or the Python STREAM reference at `~/projects/STREAM/`.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `src/components/channel.jl` (MOD) | shared component helper + variant constructor | symbolic-equation construction, no runtime state | `src/components/channel.jl:172-249` (`_channel_base_eqs` — same file, being deleted at final commit per D-13) | exact (template, but signature/return shape changes per D-01, energy balance changes per D-05/D-06) |
| `test/test_channel_core.jl` (NEW) | test stub harness + 5 testset gates (G1..G4 + auxiliaries) | placeholder-driven solve + symbolic-equation introspection | `test/test_connectors.jl:33-109` (`_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver` — Phase 52 precedent) | exact (stub-harness shape) + role-match (testsets) |
| `test/data/stage2_reference.py` (NEW) | one-off reference-value generator | batch transform: numeric Python → committed Julia consts | `~/projects/STREAM/stream/calculations/channel.py:116-167` + `~/projects/STREAM/stream/utilities.py:359-376` | exact (Python parity gate — these ARE the formulas being mirrored) |
| `test/runtests.jl` (MOD) | orchestrator wiring | `include()` ordering | `test/runtests.jl:1-22` (existing one-line entries) | exact (literal same pattern, one-line addition) |

**No analog found:** none. Every file in scope has a strong codebase precedent.

---

## Pattern Assignments

### `src/components/channel.jl` — `_channel_core(...)::NamedTuple{(:eqs, :obs)}` (NEW helper)

**Analog (structural template):** `src/components/channel.jl:172-249` — `_channel_base_eqs` (the helper being deleted at final commit of Phase 53). Most equations port directly; what changes is the return shape (mutator → pure `(; eqs, obs)`), the energy-balance form (constant-cp → enthalpy face-averaged cp), and the deletion of three flag knobs (`observed_mode`, `skip_htc`, `T_wall_cells=nothing`).

**Secondary analog (variant call site that delegates to core):** `src/components/thermal_channel.jl:48-241` — `ChannelAndContacts`. Phase 53 does NOT rewire `ChannelAndContacts` (Phase 54 does), but its `@variables` block (`thermal_channel.jl:69-92`) and obs-equation construction (`thermal_channel.jl:196-224`) are the canonical reference for what core-emitted observables will look like.

#### Old `_channel_base_eqs` shape — the structural pattern reused (`src/components/channel.jl:172-249`)

The current helper accepts everything by kwarg, mutates `eqs::Vector{Equation}`, and returns nothing:

```julia
# src/components/channel.jl:172-194
function _channel_base_eqs(
    eqs::Vector{Equation};
    n,
    T,
    Re,
    Nu,
    h_tc,
    v,
    T_out,
    dp,
    port_in,
    port_out,
    Dh,
    A,
    L,
    g_acc,
    dz,
    htc_correlation=dittus_boelter,
    friction_correlation=blasius_friction,
    observed_mode=false,
    T_wall_cells=nothing,
    skip_htc=false,
)
```

**Per D-01:** New core returns `(; eqs, obs)`. Per D-03/D-04: signature drops `Re`, `Nu`, `h_tc`, `v`, `htc_correlation`, `observed_mode`, `T_wall_cells`, `skip_htc`. Final signature is fixed in CONTEXT.md D-03:

```julia
_channel_core(;
    n,
    T,
    dp,
    port_in,
    port_out,
    geometry,
    g_acc,
    friction_correlation=blasius_friction,
    q_left_expr,
    q_right_expr,
)::NamedTuple{(:eqs, :obs)}
```

#### Per-cell `dp[i]` (friction + gravity) — copy verbatim (`src/components/channel.jl:222-237`)

```julia
# src/components/channel.jl:222-237 (the !observed_mode branch is the canonical form
# because Re[i] inside _channel_core is an observable, NOT a solver unknown)
for i in 1:n
    Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
    f_i = friction_correlation(Re_i_for_friction)
    push!(
        eqs,
        dp[i] ~
        f_i *
        (port_in.mdot * abs(port_in.mdot) / (2 * rho_water(T[i]) * A^2)) *
        (dz / Dh) + rho_water(T[i]) * g_acc * dz,
    )
end
```

Notes for the planner:
- `Re_i_for_friction` MUST be inlined (Pitfall 5 already documented in `_channel_base_eqs` comments). In the new core, `Re[i]` is an observable — referencing it inside a solver equation creates an observed-to-observed chain.
- `Dh = geometry.Dh`, `A = geometry.A`, `dz = L / n` are derived locally inside core from the `geometry` kwarg (current variants compute these in their constructor; core can take `geometry` directly per D-03 signature).

#### Port wiring (mass conservation, momentum ODE, port temperature wiring) — copy verbatim (`src/components/channel.jl:239-248`)

```julia
# src/components/channel.jl:239-248
push!(eqs, T_out ~ T[n])

# Port wiring (4 equations -- identical across all channel variants)
Dt = Differential(t)
push!(eqs, port_in.mdot + port_out.mdot ~ 0)
push!(
    eqs, (L / A) * Dt(port_in.mdot) ~ (port_in.P - port_out.P) - sum(dp[i] for i in 1:n)
)
push!(eqs, port_out.T ~ T[n])
push!(eqs, port_in.T ~ T[1])
```

This block is **identical across all three current variants** (`Channel`, `ChannelAndContacts`, `ChannelHeatFlux`) — moved from `_channel_base_eqs` into `_channel_core` unchanged.

#### Boundary-face `instream` setup — copy verbatim (`src/components/channel.jl:66-67`, also `thermal_channel.jl:102-103, 316-317`)

```julia
# src/components/channel.jl:66-67 (also at thermal_channel.jl:102-103 and 316-317 — three current sites)
T_inlet_fwd = instream(port_in.T)
T_inlet_rev = instream(port_out.T)
```

Per NRG-02 (D-05), the boundary-face cp uses these same expressions: `cp_water(T_inlet_fwd)` and `cp_water(T_inlet_rev)` are the cell-1 / cell-n boundary face arguments. Selection happens once at the `T_up` level (the `ifelse` on `port_in.mdot >= 0`); cp inherits the selection because `cp_water` is deterministic.

#### Flow-reversal `ifelse(mdot >= 0, ...)` idiom — copy verbatim (`src/components/channel.jl:69-72`)

This is the canonical excerpt; the same pattern appears at `thermal_channel.jl:163-166` (CAC) and `thermal_channel.jl:345-348` (ChannelHeatFlux):

```julia
# src/components/channel.jl:69-72
for i in 1:n
    T_up_fwd = (i == 1) ? T_inlet_fwd : T[i - 1]
    T_up_rev = (i == n) ? T_inlet_rev : T[i + 1]
    T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)
```

Per D-05: this same `T_up` flows into both sides of the new face-averaged cp. CONTEXT.md "Specific Ideas" notes that no second `ifelse` for cp is needed because `cp_water(T_up)` inherits the selection deterministically.

#### OLD energy balance — what NRG-01..04 changes (`src/components/channel.jl:77-84`)

This is the form being replaced. Reviewers should see exactly this excerpt as the "before" state:

```julia
# src/components/channel.jl:77-84 — OLD constant-cp upwind form
push!(
    eqs,
    Dt(T[i]) ~
    (
        abs(port_in.mdot) * cp_water(T[i]) * (T_up - T[i]) +     # ← cp(T[i]) here, not face-averaged
        h_tc[i] * sum(geometry.heated_parts) * dz * (thermal.T - T[i])  # ← variant-specific q term
    ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz),
)
```

The same constant-cp shape appears at `thermal_channel.jl:167-175` (CAC, two-sided q) and `thermal_channel.jl:349-356` (ChannelHeatFlux, T_wall_p-driven q). All three sites have `cp_water(T[i])` in the convective numerator — this is the byte that NRG-01 flips.

#### NEW energy balance per D-06 — replace with face-averaged enthalpy form

Per CONTEXT.md D-06 (line 68-77), inside the same per-cell loop:

```julia
# Phase 53 NEW — enthalpy form, face-averaged cp
cp_face = (cp_water(T_up) + cp_water(T[i])) / 2
push!(
    eqs,
    Dt(T[i]) ~ (
        abs(port_in.mdot) * cp_face * (T_up - T[i])
      + q_left_expr[i]
      + q_right_expr[i]
    ) / (rho_water(T[i]) * cp_water(T[i]) * A * dz),
)
```

Numerator: `cp_face` (face-averaged). Denominator: `cp_water(T[i])` (Python's `c_bulk`). NRG-03 mandates the two cp values must NOT cancel. Per D-02: `q_left_expr[i]` and `q_right_expr[i]` are passed in by the variant — core does not build them, just sums them.

#### Per-cell observables — `P[i]`, `T_sat[i]`, `T_ONB[i]` (copy from `thermal_channel.jl:217-223`)

The CAC observable construction is the canonical source (current `Channel` does NOT emit `T_sat`/`T_ONB`/`Pe` — those come from CAC). Per D-08, all of these go into core:

```julia
# src/components/thermal_channel.jl:217-223
P_i =
    port_in.P - sum(dp[j] for j in 1:i) -
    (i/n) * ((port_in.P - port_out.P) - sum(dp[j] for j in 1:n))
push!(obs, P[i] ~ P_i)
push!(obs, T_sat[i] ~ sat_temperature(P_i))
q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)
push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_spl_i))
```

**Critical adaptation for core (CONTEXT.md "Established Patterns" line 174):** `T_ONB[i]` MUST inline `(q_left_expr[i] + q_right_expr[i]) / (sum(heated_parts) * dz)` instead of referencing the `q_wall[i]` symbol — otherwise core creates an observed-to-observed chain (q_wall is itself observed). The CAC code at line 222 currently uses `q_wall[i]` because in CAC `q_wall[i]` is an unknown, not an observable. In the new core, q_wall[i] is observed, so the inlining rule applies.

```julia
# Phase 53 ADAPTATION — inline the q expression to keep T_ONB observable acyclic
q_spl_i = (q_left_expr[i] + q_right_expr[i]) / (sum(geometry.heated_parts) * dz)
push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_spl_i))
```

#### Re[i], Pe[i], v[i] observables — copy from CAC (`thermal_channel.jl:198-204`)

```julia
# src/components/thermal_channel.jl:198-204
Re_i = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))
Pr_i = cp_water(T[i]) * mu_water(T[i]) / k_water(T[i])
push!(obs, Re[i] ~ Re_i)
# Nu[i] and h_tc_left/right are NOT in core (D-04 — variant-specific)
push!(obs, v[i] ~ port_in.mdot / (rho_water(T[i]) * A))
push!(obs, Pe[i] ~ Re_i * Pr_i)
```

CONTEXT.md "Specific Ideas" already notes the existing drift between variants: current `Channel` defines `v[i] = mdot/(ρ·A)` (line 87) while CAC also has `velocity[i] = abs(mdot)/(ρ·A)` (line 203). Per D-08, core picks one — the planner picks the canonical form. The existing `v[i] ~ port_in.mdot / (rho_water(T[i]) * A)` (CAC line 202) is the natural choice because both variants currently use it under that name.

#### `q_wall[i]`, `q_wall_left[i]`, `q_wall_right[i]` observables — Phase 53 NEW (per D-08)

These are pure aliases over the input expressions. Not in any current code (current variants build `q_wall[i]` differently per variant: CAC at `thermal_channel.jl:188`, CHF at `thermal_channel.jl:357-358`, Channel at `channel.jl:86`). Core unifies:

```julia
# Phase 53 NEW — per D-08
push!(obs, q_wall_left[i]  ~ q_left_expr[i])
push!(obs, q_wall_right[i] ~ q_right_expr[i])
push!(obs, q_wall[i]       ~ q_left_expr[i] + q_right_expr[i])
```

#### `dP` observable — copy verbatim (`src/components/channel.jl:128`, `thermal_channel.jl:226`, `thermal_channel.jl:381`)

```julia
push!(obs, dP ~ port_in.P - port_out.P)
```

Identical across all three current variants — moved into core unchanged.

#### `@variables` block in calling variant — convention from `thermal_channel.jl:69-92`

Per D-10: variant declares all observable LHS symbols (`Re[i]`, `Pe[i]`, `v[i]`, `P[i]`, `T_sat[i]`, `T_ONB[i]`, `dP`, `T_out`, `q_wall[i]`, `q_wall_left[i]`, `q_wall_right[i]`) and unknowns (`T[i]`, `dp[i]`). Core builds equations referencing these by symbol. The CAC `@variables` block (`thermal_channel.jl:69-92`) is the closest precedent and shows the comment convention (`# observed --` vs `# unknown --`).

For the Phase 53 stub harness, the test wrapper `_StubChannelCore` (the test's own constructor) will declare these — see the next section.

---

### `test/test_channel_core.jl` — stub harness + G1/G2/G3/G4 testsets (NEW FILE)

**Analog (stub harness shape):** `test/test_connectors.jl:33-109` — `_StubRecipient`, `_StubWallDriver`, `_StubFluxDriver`. Phase 52 precedent for placeholder-driven systems. Phase 53's harness is the same shape: a private function that builds an MTK component composing `port_in`/`port_out` `FlowPort`s with driven test signals, exposed as a self-contained `ODESystem` that participates in a Pump → stub → Pump test loop.

**Secondary analog (testset structure):** `test/test_connectors.jl:272-411` — the CONN-01/CONN-02/CONN-04 driven-and-undriven testsets. Each gate (G1, G2, G3, G4) follows this shape: build a small loop with `Pump(mdot0=...)`, anchor pressure with `pump.port_in.P ~ 1.0e5`, `mtkcompile`, `solve_steady` or `solve_transient`, assert.

#### Stub harness — adapt `_StubRecipient` shape (`test/test_connectors.jl:33-88`)

The Phase 52 stub:

```julia
# test/test_connectors.jl:33-88 (truncated to load-bearing parts)
function _StubRecipient(; name, n::Int, port_type::Symbol=:wall,
                        drive_left::BitVector=falses(n),
                        drive_right::BitVector=falses(n))
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    PortType = port_type === :wall ? WallPort : HeatFluxPort
    thermal_left  = [PortType(; name=Symbol(:thermal_left, i))  for i in 1:n]
    thermal_right = [PortType(; name=Symbol(:thermal_right, i)) for i in 1:n]
    @variables (T(t))[1:n] = fill(300.0, n)
    Dt = Differential(t)
    eqs = Equation[]
    for i in 1:n
        push!(eqs, Dt(T[i]) ~ (thermal_left[i].Q_flow + thermal_right[i].Q_flow) / m_cp)
        # ... drive vs self-anchor branches ...
    end
    push!(eqs, port_in.mdot + port_out.mdot ~ 0)
    push!(eqs, port_in.P ~ port_out.P)
    push!(eqs, port_out.T ~ T[n])
    push!(eqs, port_in.T  ~ T[1])
    sys = System(eqs, t, [collect(T)...], []; name=name)
    return compose(sys, port_in, port_out, thermal_left..., thermal_right...)
end
```

**Phase 53 adaptation — `_StubChannelCore`:** Same shape, but the body delegates to `_channel_core` instead of building inline equations. The driven inputs are now `q_left_vals::Vector{Float64}` and `q_right_vals::Vector{Float64}` (numeric per-cell power per cell, W) which the stub converts into `Num` array form before passing as `q_left_expr` / `q_right_expr` to `_channel_core`.

```julia
# Phase 53 NEW — _StubChannelCore (recommended shape; planner finalizes)
function _StubChannelCore(; name, n::Int, geometry::PipeGeometry,
                          q_left_vals::Vector{Float64}=zeros(n),
                          q_right_vals::Vector{Float64}=zeros(n),
                          g_acc::Float64=0.0,
                          friction_correlation=blasius_friction)
    @named port_in  = FlowPort()
    @named port_out = FlowPort()
    @variables begin
        (T(t))[1:n] = fill(313.15, n)
        (dp(t))[1:n] = fill(100.0, n)
        # observable LHS symbols core will reference (D-10):
        (Re(t))[1:n]
        (Pe(t))[1:n]
        (v(t))[1:n]
        (P(t))[1:n]
        (T_sat(t))[1:n]
        (T_ONB(t))[1:n]
        (q_wall(t))[1:n]
        (q_wall_left(t))[1:n]
        (q_wall_right(t))[1:n]
        T_out(t) = 313.15
        dP(t)
    end
    # Pass numeric q values as length-n Vector{Num} via implicit promotion
    q_left_expr  = Num.(q_left_vals)
    q_right_expr = Num.(q_right_vals)
    core = _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
                          friction_correlation, q_left_expr, q_right_expr)
    sys = System(core.eqs, t,
                 [collect(T); collect(dp); T_out],
                 [];
                 observed=core.obs, name=name)
    return compose(sys, port_in, port_out)
end
```

**Notes for the planner:**
- `Num.(q_left_vals)` is the simplest way to lift a numeric Vector into the symbolic ring without introducing parameters. If MTK rejects this, fall back to `@parameters (q_left_p(t))[1:n] = q_left_vals` and pass `collect(q_left_p)` — but parameters carry unit-and-time semantics that drag in extra structure. The simple `Num.()` lift is preferred.
- The stub matches the Phase 52 hydraulic-plumbing convention from `test_connectors.jl:82-85`: `port_in.mdot + port_out.mdot ~ 0`, port temperature wiring via `port_in.T ~ T[1]` / `port_out.T ~ T[n]`. These are already inside `_channel_core` per D-01 / port-wiring excerpt above, so the stub does not re-emit them.

#### Loop assembly — copy from `test/test_connectors.jl:272-290` (CONN-01 adiabatic test)

```julia
# test/test_connectors.jl:272-290
@testset "CONN-01: WallPort adiabatic when unconnected" begin
    @named pump = Pump(; mdot0=0.5)
    @named stub = _StubRecipient(; n=2, port_type=:wall)
    conns = Equation[
        connect(pump.port_out, stub.port_in),
        connect(stub.port_out, pump.port_in),
        pump.port_in.P ~ 1.0e5,
    ]
    @named sys = compose(System(conns, t; name=:smoke_wall_adiabatic), pump, stub)
    ssys = @test_nowarn mtkcompile(sys)
    sol  = @test_nowarn solve_transient(ssys, [], range(0.0, 0.1, length=20))
    @test sol.retcode == ReturnCode.Success
    # ...
end
```

**Phase 53 adaptation:** for G1 (Stage 1 baseline) the loop uses `Pump(dP=3e4)` not `Pump(mdot0=...)` so steady-state mdot is determined by friction balance (matches `test/test_channel.jl:152-167` THERM-03 setup which is the geometry the Stage 1 baseline references per RESEARCH.md line 569). For G3 (mirror) the loop uses `Pump(mdot0=±0.1)` per RESEARCH.md line 639. Add a `HeatExchanger(T_inlet)` between pump and stub for inlet-T anchoring (matches THERM-03 pattern at `test_channel.jl:156-160`).

#### Symbolic-equation introspection for NRG-01/NRG-02 — testset shape

CONTEXT.md and RESEARCH.md (line 559-562) require asserting that the constructed energy-balance equation contains the substring `cp_water(T_up)` (or equivalent face-averaged form) and contains `cp_water(instream(port_in.T))` at cell 1. Closest precedent in the codebase: `test/test_connectors.jl:120-152` introspects MTK metadata via `ModelingToolkit.getname`. For RHS structure introspection use `equations(ssys)` and `string(eq)` plus `occursin(...)`:

```julia
# Phase 53 NEW — shape suggested by RESEARCH.md line 559-562
@testset "NRG-01: face-averaged cp in numerator" begin
    @named stub = _StubChannelCore(; n=3, geometry=PipeGeometry_circular(0.6, 0.01),
                                    q_left_vals=fill(200.0, 3), q_right_vals=zeros(3))
    eq_str = string(equations(stub))
    @test occursin("cp_water", eq_str)
    # tighter assertion: the face-average shape (cp(T_up) + cp(T[i])) / 2 appears
    @test occursin("cp_water(T_up)", eq_str) || occursin("/ 2", eq_str)
end
```

The exact substring to check depends on MTK's pretty-printer; the planner finalizes once the helper is implemented. (Fallback: walk the equations programmatically with `Symbolics.unwrap` and pattern-match on the symbolic tree.)

#### Mirror identity (G3, NRG-04) — copy from RESEARCH.md line 644-648

```julia
# RESEARCH.md line 644-648 — directly into the testset body
dT_fwd = sol_fwd[ssys.stub.T_out] - T_in_fwd
dT_rev = sol_rev[ssys.stub.T[1]]   - T_in_rev
@test isapprox(dT_fwd, dT_rev; rtol=1e-12)
```

Solver-tolerance fallback if 1e-12 is flaky (per VALIDATION.md G3 note): set `solve_steady(ssys, op; abstol=1e-12, reltol=1e-12)` or relax to 1e-9. The current `solve_steady` signature is in `src/solvers.jl`; planner reads that file before locking the mirror tolerance.

---

### `test/data/stage2_reference.py` — Python reference value generator (NEW FILE)

**Analog:** `~/projects/STREAM/stream/calculations/channel.py:116-167` (`coolant_first_order_upwind_dTdt`) and `~/projects/STREAM/stream/utilities.py:359-376` (`pair_mean_1d`). The script is a one-off helper that runs the steady-state forward sweep using these exact functions and writes the converged `T[i]` array as Julia `const` declarations.

#### Energy-balance formula — byte-for-byte reference (`channel.py:157-167`)

```python
# ~/projects/STREAM/stream/calculations/channel.py:157-167
rho = fluid.density(T)
c_bulk = fluid.specific_heat(T)
cin = fluid.specific_heat(Tin)
c = directed(pair_mean_1d(directed(c_bulk, mdot), prepend=cin), mdot)

convection = directed(np.abs(mdot) * c * np.diff(directed(T, mdot), prepend=Tin), mdot)

heat_transfer = dz * (q_left * pipe.heated_parts[0] + q_right * pipe.heated_parts[1])

heat_capacity = rho * c_bulk * pipe.area * dz
return (heat_transfer - convection) / heat_capacity
```

The Stage 2 hand-compute (per RESEARCH.md line 597-617) iterates this until `T_new ≈ T_guess`, then prints the converged array. Note: at steady state, `dT/dt = 0`, so the forward-sweep solves `0 = (heat_transfer - convection) / heat_capacity` → `convection = heat_transfer` per cell, which decomposes to a sequential `T[i]` solve given `T[i-1]` and `q_left[i]`.

#### `pair_mean_1d` averaging — byte-for-byte reference (`utilities.py:359-376`)

```python
# ~/projects/STREAM/stream/utilities.py:359-376
def pair_mean_1d(a, prepend=None, append=None):
    assert a.ndim == 1
    assert prepend is None or append is None
    sl1, sl2 = a[:-1], a[1:]
    mn = (sl1 + sl2) / 2
    if prepend is None and append is None:
        return mn
    n = len(a)
    res = np.empty(n, dtype=a.dtype)
    if prepend is not None:
        res[1:] = mn          # interior faces: (a[i-1] + a[i]) / 2
        res[0] = (prepend + a[0]) / 2   # boundary face: (cin + a[0]) / 2 — same averaging!
    elif append is not None:
        res[:-1] = mn
        res[-1] = (append + a[-1]) / 2
    return res
```

CONTEXT.md D-05 cites this as the source of truth: the boundary face uses the same `(cin + a[0]) / 2` averaging as interior faces. Phase 53's NRG-02 test must produce a Julia equation matching this.

#### `directed` flow-flip — byte-for-byte reference (`utilities.py:537-551`)

```python
# ~/projects/STREAM/stream/utilities.py:537-551
def directed(a: np.ndarray, val) -> np.ndarray:
    return a if val >= 0 else a[::-1]
```

Confirms reverse-flow symmetry: under `mdot < 0` the array is flipped, so cell-n becomes the new boundary cell. The Julia mirror is the existing `T_up = ifelse(port_in.mdot >= 0, T_up_fwd, T_up_rev)` idiom (`channel.jl:72`).

#### Output format — Julia `const` declarations

The Python script's stdout is pasted into `test_channel_core.jl` as:

```julia
# Generated by test/data/stage2_reference.py — DO NOT EDIT BY HAND
# Regenerate with: cd test/data && python stage2_reference.py
const STAGE2_REFERENCE_T = [313.15, 320.7..., 327.6..., 333.9..., 339.8...]
const STAGE2_GEOMETRY_L = 0.6
const STAGE2_GEOMETRY_D = 0.01
const STAGE2_N = 5
const STAGE2_T_INLET = 313.15
const STAGE2_Q0 = 12_300.0
```

**No existing analog** in the STREAM.jl repo for this kind of one-off Python helper. The convention is established by RESEARCH.md §"Stage 2" (line 597-617) and VALIDATION.md G2 (line 65-67). Planner uses regen comment style consistent with auto-generated files (mention the source script + invocation).

---

### `test/runtests.jl` — wire new test file (MOD)

**Analog:** `test/runtests.jl:3-22` — every line is a single `include("test_*.jl")` orchestrator entry. No `@testset` wrapper at the orchestrator level; each test file owns its own testsets.

**RESEARCH.md line 710 specifies placement:** "add `include(\"test_channel_core.jl\")` line between line 6 (`test_channel.jl`) and line 7 (`test_sign_safety.jl`)". The wired entry mirrors existing one-line pattern:

```julia
# test/runtests.jl — current line 6:
include("test_channel.jl")
# Phase 53 ADD (between line 6 and line 7):
include("test_channel_core.jl")
# test/runtests.jl — current line 7 (becomes line 8):
include("test_sign_safety.jl")
```

The pattern-mapping context's stated wrapper `@testset begin include("test_channel_core.jl") end` is NOT the convention used in this repo — the existing orchestrator uses bare `include(...)` lines (`runtests.jl:3-22`). Planner uses the bare form to match.

---

## Shared Patterns

### `@register_symbolic` boundary for fluid properties

**Source:** `src/fluids.jl:143-150`

```julia
# src/fluids.jl:143-150
@register_symbolic rho_water(T::Real)
@register_symbolic cp_water(T::Real)
@register_symbolic mu_water(T::Real)
@register_symbolic k_water(T::Real)
@register_symbolic beta_water(T::Real)
@register_symbolic sat_temperature(P::Real)
```

**Apply to:** `_channel_core` energy balance — `cp_water(T_up)`, `cp_water(T[i])`, `rho_water(T[i])` all flow through the symbolic boundary established here. No new `@register_symbolic` declarations are needed; reuse existing ones.

CLAUDE.md "MTK Patterns" reminds: plain Julia functions cannot accept `Num` directly; the registered wrappers make them opaque nodes in the symbolic graph. `cp_water` already has the registration; the new face-average `cp_face = (cp_water(T_up) + cp_water(T[i])) / 2` constructs symbolic + symbolic = symbolic, no new boundary needed.

### Observed-equation discipline (no observed-to-observed chains)

**Source:** `src/components/thermal_channel.jl:142-159` (CAC's SCB block) — every reference to `Re_i`, `Pr_i`, `P_i`, `q_spl_i` is the inlined Julia expression, NOT the `Re[i]` / `P[i]` / `q_wall[i]` MTK symbol. Comment at line 144: "Inline P[i] expression (not the observed symbol) to avoid observed-to-observed chain".

**Apply to:** `_channel_core`. Specifically:
- `T_ONB[i]` observable inlines `q_left_expr[i] + q_right_expr[i]` instead of referencing `q_wall[i]` symbol.
- `dp[i]` equation inlines `Re_i_for_friction = abs(port_in.mdot) * Dh / (A * mu_water(T[i]))` instead of referencing `Re[i]` symbol (`Re[i]` is observed in the new core per D-08 — same pattern as old `observed_mode=true` branch).
- `Pe[i]` observable uses inlined `Re_i * Pr_i`, not `Re[i] * Pr_i` (matches `thermal_channel.jl:204`).

### Equation construction via `push!(eqs, ...)`

**Source:** all current channel components (`channel.jl:65, 77-105`, `thermal_channel.jl:101, 109-189`, `channel.jl:172-249`).

**Apply to:** `_channel_core`. Build `eqs::Vector{Equation}` and `obs::Vector{Equation}` locally, return as `(; eqs=eqs, obs=obs)`. This matches the existing imperative-construction style; no need to introduce comprehensions or `vcat` chains.

### Test loop topology — `Pump → [HeatExchanger] → stub → Pump` with pressure anchor

**Source:** `test/test_connectors.jl:273-280, 297-307, 318-326, 337-349`. Every Phase 52 driven/undriven testset uses this loop shape.

**Apply to:** all G1/G2/G3/G4 testsets in `test_channel_core.jl`. Pressure anchor `pump.port_in.P ~ 1.0e5` is mandatory in closed loops — without it MTK cannot close the absolute-pressure constraint (CONTEXT.md "Established Patterns" line 73, also `_StubRecipient` comment at `test_connectors.jl:78-85`).

### `mtkcompile` before `solve` — non-negotiable

**Source:** CLAUDE.md "MTK Patterns" §"`mtkcompile` before solve". Every test in `test_connectors.jl` and `test_channel.jl` calls `ssys = mtkcompile(sys)` before `solve_steady` or `solve_transient`.

**Apply to:** every G1..G4 testset. Pattern is `ssys = @test_nowarn mtkcompile(sys); sol = @test_nowarn solve_steady(ssys, op)`.

---

## No Analog Found

None. Every file in scope has at least a role-match analog with concrete code excerpts.

---

## Metadata

**Analog search scope:**
- `src/components/channel.jl` (entire file, 249 lines)
- `src/components/thermal_channel.jl` (entire file, 396 lines)
- `src/fluids.jl` (entire file, 151 lines)
- `src/STREAM.jl` (entire file, 96 lines)
- `test/test_connectors.jl` (entire file, 412 lines)
- `test/test_channel.jl` (lines 1-170 sampled — establishes testset style; 958 lines total)
- `test/runtests.jl` (entire file, 22 lines)
- `~/projects/STREAM/stream/calculations/channel.py` (lines 100-174)
- `~/projects/STREAM/stream/utilities.py` (lines 350-376, 530-552)

**Files scanned:** 9
**Pattern extraction date:** 2026-05-06
**Phase scope locked by:** CONTEXT.md D-01..D-14, RESEARCH.md §Validation Architecture, VALIDATION.md G1..G5

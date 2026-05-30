---
phase: 54
plan: 05
type: execute
wave: 5
depends_on: [54-04]
files_modified:
  - test/test_channels.jl
  - test/runtests.jl
autonomous: true
requirements: [VAR-01, VAR-02, VAR-03]
must_haves:
  truths:
    - "test/test_channels.jl exists and contains three integration smokes — one per variant"
    - "Channel smoke: closed Pump → Channel → Pump loop with per-cell T_wall binding eqs on thermal_left, h_left=fill(5000.0, n), h_right=0.0; solve_transient; q_wall_left[i] finite/signed-correctly; q_wall_right[i] ≈ 0"
    - "ChannelHeatFlux smoke: closed Pump → ChannelHeatFlux → Pump loop with per-cell q_flux binding eqs on thermal_left; q_wall_left[i] ≈ q_value × heated_parts[1] × dz; q_wall_right[i] ≈ 0"
    - "ChannelAndContacts ↔ HeatDiffusion smoke: closed loop via symmetric_plate(cac, fuel; name=:rods); solve_transient Success; Q_wall_total ≈ sum(q_wall[i])"
    - "test/test_channels.jl is wired into test/runtests.jl"
    - "bin/jl test/test_channels.jl exits 0"
    - "Architectural rule preserved: only ChannelAndContacts wires to HeatDiffusion; Channel and CHF use binding eqs / dangling ports"
  artifacts:
    - path: "test/test_channels.jl"
      provides: "Three Phase 54 integration smokes (Channel, CHF, CAC↔HD)"
      contains: "VAR-01.*Channel smoke; VAR-02.*ChannelHeatFlux smoke; VAR-03.*ChannelAndContacts.*HeatDiffusion smoke"
    - path: "test/runtests.jl"
      provides: "Orchestrator with include(\"test_channels.jl\")"
  key_links:
    - from: "test/runtests.jl"
      to: "test/test_channels.jl"
      via: "include(\"test_channels.jl\")"
      pattern: "include\\(\"test_channels\\.jl\"\\)"
    - from: "test/test_channels.jl Channel smoke"
      to: "src/components/channels.jl Channel"
      via: "Channel(; n, geometry, h_left=fill(5000.0, n), h_right=0.0); ch.thermal_left[i].T ~ T_wall_value"
      pattern: "ch.thermal_left\\d+\\.T ~"
    - from: "test/test_channels.jl ChannelHeatFlux smoke"
      to: "src/components/channels.jl ChannelHeatFlux"
      via: "ChannelHeatFlux(; n, geometry); chf.thermal_left[i].q_flux ~ q_value"
      pattern: "chf.thermal_left\\d+\\.q_flux ~"
    - from: "test/test_channels.jl CAC smoke"
      to: "src/composition/helpers.jl symmetric_plate"
      via: "rods = symmetric_plate(cac, fuel; name=:rods)"
      pattern: "symmetric_plate\\(cac, fuel"
---

<objective>
Create `test/test_channels.jl` with three integration smoke tests — one per Phase 54 variant — exercised on real closed loops (not stub systems). Wire the new file into `test/runtests.jl`. This is the Phase 54 close gate per ROADMAP success criterion 6 (rewritten 2026-05-07): each rewritten variant must `mtkcompile` and `solve_transient` on a minimal closed loop with named-symbolic-accessor assertions. Implements decisions D-13, D-14, D-15, D-16.

Purpose: Isolate the variant-rewrite layer before Phase 55's full re-wiring sweep. If a smoke fails here, the failure is in the variant — not in helpers, builders, or stale test scaffolding. Phase 55's TEST-02 sweep is much harder to debug, so closing Phase 54 with a clean, focused integration check makes Phase 55 lower-risk.

**Architectural invariant preserved:** Only `ChannelAndContacts` wires to `HeatDiffusion`. The Channel smoke uses per-cell `T_wall` binding equations on `thermal_left`. The CHF smoke uses per-cell `q_flux` binding equations on `thermal_left`. Neither connects to `HeatDiffusion`.

**Test scope at Phase 54 close (D-13):** Only `bin/jl test/test_channels.jl` is required to pass. `test/test_channel.jl` (legacy 958-line file) is expected to FAIL because its API references are stale (uses old `T_wall` kwarg, scalar `thermal` port, etc.). Do NOT edit `test/test_channel.jl` here — Phase 55 (TEST-01) rewrites it.

Output: `test/test_channels.jl` with three @testsets; `test/runtests.jl` includes the new file.
</objective>

<execution_context>
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/workflows/execute-plan.md
@/home/itay/projects/Julia-STREAM/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md
@CLAUDE.md
@src/components/channels.jl
@src/components/heat_diffusion.jl
@src/composition/helpers.jl
@src/examples.jl
@test/runtests.jl
@test/test_connectors.jl

<interfaces>
<!-- Pump constructors -->
From src/components/pump.jl:
```julia
Pump(dP_pump::Real; name)        # fixed-dP, dP_pump in Pa
Pump(; name, mdot0)              # fixed-mdot, mdot0 in kg/s
```

<!-- Channel constructor (post 54-01) -->
From src/components/channels.jl:
```julia
Channel(; name, n::Int, geometry::PipeGeometry, g=0.0,
        h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
        h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
        friction_correlation = blasius_friction)
# Ports: port_in, port_out (FlowPort); thermal_left[1:n], thermal_right[1:n] (ThermalPort)
# Observables: q_wall[i], q_wall_left[i], q_wall_right[i], T_out, ...
```

<!-- ChannelHeatFlux constructor (post 54-02) -->
From src/components/channels.jl:
```julia
ChannelHeatFlux(; name, n::Int, geometry::PipeGeometry, g=0.0,
                friction_correlation = blasius_friction)
# Ports: port_in, port_out; thermal_left[1:n], thermal_right[1:n] (HeatFluxPort)
# Observables: q_wall[i], q_wall_left[i], q_wall_right[i], T_out, ...
```

<!-- ChannelAndContacts constructor (post 54-03) -->
From src/components/channels.jl:
```julia
ChannelAndContacts(; name, n::Int, geometry::PipeGeometry, g=0.0,
                   htc_correlation=dittus_boelter,
                   friction_correlation=blasius_friction,
                   scb_correction=nothing)
# Ports: port_in, port_out; thermal_left[1:n], thermal_right[1:n] (ThermalPort)
# Observables: Q_wall_total, q_wall[i], h_tc[i], Nu[i], T_wall_left/right, ...
```

<!-- HeatDiffusion (used in CAC smoke; ports named thermal_left[1:nz], thermal_right[1:nz]) -->
From src/components/heat_diffusion.jl:130 — ALL kwargs except `power` and `T0` are MANDATORY
(no defaults for `y`, `rho_s`, `cp_s`, `k_s`, `power_shape`):
```julia
function HeatDiffusion(; name,
                         nz::Int, nx::Int,
                         Lz, Lx, y,
                         rho_s, cp_s, k_s,
                         power_shape,
                         power = 1e6,
                         T0    = 600.0)
# Ports: thermal_left[1:nz], thermal_right[1:nz]
```

<!-- Composition helper (used in CAC smoke) -->
From src/composition/helpers.jl:
```julia
symmetric_plate(cac, fuel; name)  # wires both faces of fuel plate to the same CAC
# After: refer to sub-components via the returned system, e.g. rods.cac, rods.fuel
```

<!-- Solver -->
From src/solvers.jl:
```julia
solve_transient(ssys, op_pairs, tspan_or_saveat)
# Returns ODE solution; sol.retcode is the SciML ReturnCode enum
```

<!-- Canonical HeatDiffusion call (gold uranium MTR plate) — src/examples.jl:518-528 -->
```julia
ps = fill(1.0 / (nz * nx), nz, nx)  # uniform power shape, normalized
@named fuel = HeatDiffusion(;
    nz=nz, nx=nx,
    Lz=0.6,
    Lx=0.005,
    y=0.07,
    rho_s=19300.0,
    cp_s=116.0,
    k_s=174.0,
    power_shape=ps,
)
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create test/test_channels.jl with three integration smokes</name>
  <files>test/test_channels.jl, test/runtests.jl</files>
  <read_first>
    - test/runtests.jl (full file — orchestrator; needs include("test_channels.jl") added)
    - test/test_connectors.jl (full file — reference for testset shape, Pump usage, solve_transient assertion idioms)
    - src/components/channels.jl (full file post-54-04 — verify Channel/CHF/CAC signatures match the smokes' usage)
    - src/components/heat_diffusion.jl (lines 120-140 — HeatDiffusion constructor signature; ALL of `y, rho_s, cp_s, k_s, power_shape` are MANDATORY kwargs with no defaults — UndefKeywordError if missing)
    - src/composition/helpers.jl (symmetric_plate function — used in the CAC smoke)
    - src/examples.jl (lines 508-528 — canonical `build_loop`-style HeatDiffusion call with ALL mandatory kwargs filled in for the gold MTR plate; copy these values verbatim into the CAC smoke)
    - .planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md (D-13, D-14, D-15, D-16)
    - CLAUDE.md (Performance — daemon dev loop; Component authoring conventions)
  </read_first>
  <action>
    Create `test/test_channels.jl` with the following structure. Use `bin/jl test/test_channels.jl` for warm-daemon iteration during development.

    ```julia
    # test/test_channels.jl — Phase 54 per-variant integration smokes
    # Closes Phase 54 (VAR-01 / VAR-02 / VAR-03) by exercising each rewritten variant
    # on a real closed loop (not a stub system).
    #
    # Architectural invariant (locked, see feedback_channel_hd_connection_rule.md):
    # HeatDiffusion connects ONLY to ChannelAndContacts. Channel and ChannelHeatFlux
    # NEVER wire to HeatDiffusion — they are exercised via per-cell binding equations
    # (T_wall on thermal_left for Channel; q_flux on thermal_left for CHF) with the
    # right side dangling (adiabatic / zero-flux via MTK Flow rule auto-zero on Q_flow).

    using Test
    using ModelingToolkit
    using STREAM
    import STREAM: Channel  # resolve Base.Channel ambiguity
    using ModelingToolkit: t_nounits as t
    using OrdinaryDiffEq: ReturnCode

    # ─────────────────────────────────────────────────────────────────
    # VAR-01: Channel smoke — closed Pump → Channel → Pump loop.
    # h_left = fill(5000.0, n) → left side heated.
    # h_right = 0.0 (default)  → right side adiabatic via Channel constructor default.
    # Per-cell binding eqs pin thermal_left[i].T ~ T_wall_value.
    # thermal_right ports left dangling — MTK Flow rule auto-zeros Q_flow; combined
    # with h_right=0.0, q_right_expr[i] = 0 ⇒ T_wall on the right floats (irrelevant).
    # ─────────────────────────────────────────────────────────────────
    @testset "VAR-01: Channel smoke — kwarg h_left + per-cell T_wall binding eqs" begin
        n        = 4
        L_ch     = 0.6
        D_ch     = 0.01
        T_inlet  = 313.15      # K
        T_wall   = 373.15      # K — drives positive heating into the fluid
        dP_pump  = 3.0e4       # Pa
        h_left_v = fill(5000.0, n)

        @named pump = Pump(dP_pump)
        @named bc   = HeatExchanger(T_inlet)
        @named ch   = Channel(;
            n=n,
            geometry=PipeGeometry_circular(L_ch, D_ch),
            h_left=h_left_v,
            h_right=0.0,
        )

        # Per-cell binding equations on thermal_left only.
        thermal_left_pins = [ch.thermal_left[i].T ~ T_wall for i in 1:n]

        connections = Equation[
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, ch.port_in),
            connect(ch.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
            thermal_left_pins...,
        ]

        @named sys = compose(System(connections, t; name=:smoke_channel), pump, bc, ch)
        ssys = mtkcompile(sys)
        sol  = solve_transient(ssys, [], range(0.0, 0.5, length=20))

        @test sol.retcode == ReturnCode.Success
        # Per-cell q_wall_left[i] finite (no NaN/Inf) and signed correctly:
        # T_wall=373 > T_inlet=313 ⇒ heat flows INTO the fluid ⇒ q_wall_left[i] > 0.
        for i in 1:n
            @test all(isfinite, sol[ssys.ch.q_wall_left[i], :])
            @test sol[ssys.ch.q_wall_left[i], end] > 0.0
        end
        # Right side adiabatic — q_wall_right[i] ≈ 0 by construction.
        for i in 1:n
            @test isapprox(sol[ssys.ch.q_wall_right[i], end], 0.0; atol=1e-9)
        end
        # Outlet should drift upward from inlet (heat is being added).
        @test sol[ssys.ch.T_out, end] > T_inlet
    end

    # ─────────────────────────────────────────────────────────────────
    # VAR-02: ChannelHeatFlux smoke — closed Pump → CHF → Pump loop.
    # Per-cell binding eqs pin thermal_left[i].q_flux ~ q_value (a positive flux density).
    # thermal_right ports left dangling — MTK Flow rule auto-zeros Q_flow; combined
    # with q_flux IC=0.0, q_right_expr[i] = 0 ⇒ adiabatic on the right.
    # ─────────────────────────────────────────────────────────────────
    @testset "VAR-02: ChannelHeatFlux smoke — per-cell q_flux binding eqs" begin
        n        = 4
        L_ch     = 0.6
        D_ch     = 0.01
        T_inlet  = 313.15
        dP_pump  = 3.0e4
        q_value  = 1.0e5       # W/m^2 — positive heat flux into the fluid

        geom = PipeGeometry_circular(L_ch, D_ch)
        dz_expected = L_ch / n
        heated_left = geom.heated_parts[1]
        Q_per_cell_expected = q_value * heated_left * dz_expected   # W

        @named pump = Pump(dP_pump)
        @named bc   = HeatExchanger(T_inlet)
        @named chf  = ChannelHeatFlux(; n=n, geometry=geom)

        # Per-cell binding equations on thermal_left.q_flux only.
        flux_pins = [chf.thermal_left[i].q_flux ~ q_value for i in 1:n]

        connections = Equation[
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, chf.port_in),
            connect(chf.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
            flux_pins...,
        ]

        @named sys = compose(System(connections, t; name=:smoke_chf), pump, bc, chf)
        ssys = mtkcompile(sys)
        sol  = solve_transient(ssys, [], range(0.0, 0.5, length=20))

        @test sol.retcode == ReturnCode.Success
        # q_wall_left[i] = q_flux × heated_parts[1] × dz exactly (algebraic — no transient).
        for i in 1:n
            @test isapprox(sol[ssys.chf.q_wall_left[i], end], Q_per_cell_expected; rtol=1e-6)
        end
        # Right side adiabatic — q_wall_right[i] ≈ 0.
        for i in 1:n
            @test isapprox(sol[ssys.chf.q_wall_right[i], end], 0.0; atol=1e-9)
        end
        # Outlet T should rise (heat being added).
        @test sol[ssys.chf.T_out, end] > T_inlet
    end

    # ─────────────────────────────────────────────────────────────────
    # VAR-03: ChannelAndContacts ↔ HeatDiffusion smoke — closed loop via
    # symmetric_plate(cac, fuel; name=:rods). CAC is the ONLY variant that
    # wires to HeatDiffusion (locked architectural rule).
    #
    # HeatDiffusion has FIVE mandatory kwargs with no defaults: y, rho_s, cp_s,
    # k_s, power_shape (verified at src/components/heat_diffusion.jl:130).
    # Omitting any throws UndefKeywordError. Values copied from the canonical
    # gold-uranium MTR plate at src/examples.jl:518-528.
    # ─────────────────────────────────────────────────────────────────
    @testset "VAR-03: ChannelAndContacts ↔ HeatDiffusion smoke (CONN-03 regression)" begin
        n        = 4
        nz       = 4
        nx       = 2
        L_ch     = 0.6
        D_ch     = 0.01
        Lx       = 0.0025      # m — small plate width (per Fix 1 guidance)
        T_inlet  = 313.15
        dP_pump  = 3.0e4
        # Modest power so SCB is not triggered and the solver converges quickly.
        # Plan target: 1e4 W (well below CHF on a small plate).
        power_W  = 1.0e4       # total plate power [W]

        geom = PipeGeometry_circular(L_ch, D_ch)
        ps   = fill(1.0 / (nz * nx), nz, nx)   # uniform power shape, normalized

        @named pump = Pump(dP_pump)
        @named bc   = HeatExchanger(T_inlet)
        @named cac  = ChannelAndContacts(; n=n, geometry=geom)
        # ALL mandatory kwargs supplied. Material constants are gold-uranium MTR-plate
        # canonical values (src/examples.jl:518-528): y=0.07, rho_s=19300, cp_s=116, k_s=174.
        @named fuel = HeatDiffusion(;
            nz=nz, nx=nx,
            Lz=L_ch, Lx=Lx,
            y=0.07,
            rho_s=19300.0, cp_s=116.0, k_s=174.0,
            power_shape=ps,
            power=power_W,
        )
        # symmetric_plate wires fuel.thermal_left[i] ↔ cac.thermal_right[i] and
        # fuel.thermal_right[i] ↔ cac.thermal_left[i] for i in 1:n. cac.n must equal fuel.nz.
        rods = symmetric_plate(cac, fuel; name=:rods)

        connections = Equation[
            connect(pump.port_out, bc.port_in),
            connect(bc.port_out, rods.cac.port_in),
            connect(rods.cac.port_out, pump.port_in),
            pump.port_in.P ~ 1.0e5,
        ]

        @named sys = compose(System(connections, t; name=:smoke_cac_hd), pump, bc, rods)
        # NOTE: HeatDiffusion + CAC integrations historically need build_initializeprob=false
        # (Phase 11 / composition/helpers.jl docstring). Use the same compile flag.
        ssys = mtkcompile(sys; fully_determined=true)
        sol  = solve_transient(ssys, [], range(0.0, 0.5, length=20))

        @test sol.retcode == ReturnCode.Success
        # Q_wall_total ≈ sum(q_wall[i]) — sanity on the variant-internal observable.
        Q_total_end = sol[ssys.rods.cac.Q_wall_total, end]
        q_per_cell  = [sol[ssys.rods.cac.q_wall[i], end] for i in 1:n]
        @test isapprox(Q_total_end, sum(q_per_cell); rtol=1e-6)
        # Per-cell q_wall finite.
        for i in 1:n
            @test isfinite(sol[ssys.rods.cac.q_wall[i], end])
        end
        # T_out responds (loose check — just that it's not stuck at IC).
        @test isfinite(sol[ssys.rods.cac.T_out, end])
    end
    ```

    Notes:
    - **`HeatExchanger(T_inlet)` for thermal anchoring.** The Channel and CHF smokes need a thermal anchor to break the closed-loop circular T dependency (otherwise the loop's T converges to a degenerate steady state). `build_loop` in `src/examples.jl` uses this same trick. CAC's smoke also uses HX for symmetry — keeps the three smokes shaped consistently.
    - **`solve_transient` not `solve_steady`.** D-14/D-15/D-16 explicitly require `solve_transient` on a brief horizon. Steady-state assertions verify the late-time values; the transient wrapper exercises the full DAE path including initialization.
    - **Right-side dangling for Channel smoke.** Two ways the Channel right side can be adiabatic: (a) `h_right=0.0` (kwarg default) ⇒ `q_right_expr[i] = 0` ⇒ `thermal_right[i].Q_flow ~ 0` and the channel equation is vacuous; (b) the dangling port itself ⇒ MTK Flow rule auto-zeros Q_flow. Both routes coexist consistently — the test exercises both simultaneously, which is the architecturally correct behavior. Assertion: `q_wall_right[i] ≈ 0`.
    - **CAC smoke `power_W=1.0e4`.** Modest enough that SCB is not triggered and the loop converges quickly; chosen per the post-revision Fix-1 guidance. Phase 55 will run heavier loads in the rewritten `test_channel.jl`.
    - **HeatDiffusion mandatory kwargs.** `y`, `rho_s`, `cp_s`, `k_s`, `power_shape` have NO defaults — omitting any throws `UndefKeywordError`. Use the gold-uranium MTR plate values from `src/examples.jl:518-528` (`y=0.07`, `rho_s=19300.0`, `cp_s=116.0`, `k_s=174.0`, `power_shape=fill(1.0/(nz*nx), nz, nx)`). Do NOT invent values; do NOT omit any of the five.
    - **`fully_determined=true` (default)** is correct for the CAC smoke because the closed loop with symmetric_plate is fully determined. If the daemon reports an underdetermined system, fall back to `fully_determined=false` (this is what Phase 11 / composition helpers' docstring warns about). Adjust at execution time if needed.

    **Wire into `test/runtests.jl`:**
    Add a single line `include("test_channels.jl")` to the orchestrator. Place it AFTER `include("test_channel.jl")` and `include("test_channel_core.jl")` so the new smokes follow the legacy file. Final block (after the new include):
    ```julia
    include("test_geometry.jl")
    include("test_connectors.jl")
    include("test_fluids.jl")
    include("test_channel.jl")           # legacy (will fail in Phase 54; Phase 55 rewrites)
    include("test_channel_core.jl")
    include("test_channels.jl")          # NEW — Phase 54 integration smokes (VAR-01/02/03)
    include("test_sign_safety.jl")
    include("test_pump.jl")
    ...
    ```
  </action>
  <verify>
    <automated>bin/jl test/test_channels.jl</automated>
  </verify>
  <acceptance_criteria>
    - `test -f test/test_channels.jl`
    - `grep -q "@testset \"VAR-01: Channel smoke" test/test_channels.jl`
    - `grep -q "@testset \"VAR-02: ChannelHeatFlux smoke" test/test_channels.jl`
    - `grep -q "@testset \"VAR-03: ChannelAndContacts" test/test_channels.jl`
    - `grep -q "h_left=h_left_v" test/test_channels.jl` (h kwarg used)
    - `grep -q "h_right=0.0" test/test_channels.jl` (default-adiabatic right side)
    - `grep -q "ch.thermal_left\\[i\\].T ~ T_wall" test/test_channels.jl` (Channel binding eq)
    - `grep -q "chf.thermal_left\\[i\\].q_flux ~ q_value" test/test_channels.jl` (CHF binding eq)
    - `grep -q "symmetric_plate(cac, fuel" test/test_channels.jl` (CAC↔HD path)
    - `grep -q "solve_transient" test/test_channels.jl` (transient solve, not steady)
    - `[ $(grep -E 'y\s*=|rho_s\s*=|cp_s\s*=|k_s\s*=|power_shape\s*=' test/test_channels.jl | wc -l) -ge 5 ]` (all 5 mandatory HeatDiffusion kwargs present in the file — see src/components/heat_diffusion.jl:130)
    - `! grep -q "Channel.*HeatDiffusion\\|ChannelHeatFlux.*HeatDiffusion" test/test_channels.jl` (architectural invariant — no Channel→HD or CHF→HD wiring)
    - `grep -q "include(\"test_channels.jl\")" test/runtests.jl`
    - `bin/jl test/test_channels.jl` exits 0 (all three smokes pass)
  </acceptance_criteria>
  <done>
    `test/test_channels.jl` exists with three @testsets — Channel (VAR-01), CHF (VAR-02), CAC↔HD (VAR-03) — each on a real closed Pump→variant→Pump loop, each calling `solve_transient`, each asserting via named symbolic accessors. `test/runtests.jl` includes the new file. `bin/jl test/test_channels.jl` exits 0. Architectural invariant honored: only CAC connects to HD; Channel and CHF use binding equations on thermal_left with thermal_right dangling.
  </done>
</task>

</tasks>

<verification>
- `bin/jl test/test_channels.jl` exits 0 — all three smokes pass.
- `bin/jl test/test_connectors.jl` still passes (unaffected by this plan).
- `bin/jl test/test_channel.jl` is EXPECTED TO FAIL (legacy API references; Phase 55 territory). Do not investigate.
- The full `bin/jl test/runtests.jl` is NOT a Phase 54 close criterion (D-13).
- `grep -E "Channel.*HeatDiffusion|ChannelHeatFlux.*HeatDiffusion" test/test_channels.jl` returns nothing (architectural invariant honored).
</verification>

<success_criteria>
1. `test/test_channels.jl` exists with three @testsets: VAR-01 (Channel), VAR-02 (CHF), VAR-03 (CAC↔HD).
2. Each smoke builds a real closed loop (not a stub system) and exercises `mtkcompile` + `solve_transient`.
3. Channel smoke: h_left=fill(5000.0, n) (kwarg), h_right=0.0 (default), per-cell `T_wall` binding eqs on thermal_left, thermal_right dangling, asserts q_wall_left[i] finite/positive (T_wall > T_inlet) and q_wall_right[i] ≈ 0.
4. CHF smoke: minimal CHF signature, per-cell q_flux binding eqs on thermal_left, thermal_right dangling, asserts q_wall_left[i] ≈ q_value × heated_parts[1] × dz and q_wall_right[i] ≈ 0.
5. CAC smoke: closed loop via `symmetric_plate(cac, fuel; name=:rods)`, asserts solve Success and `Q_wall_total ≈ sum(q_wall[i])`. ALL FIVE mandatory HeatDiffusion kwargs (`y`, `rho_s`, `cp_s`, `k_s`, `power_shape`) supplied with the canonical gold-MTR-plate values from `src/examples.jl:518-528`.
6. Architectural invariant: only CAC wires to HeatDiffusion (verified by absence of `Channel`+`HeatDiffusion` and `ChannelHeatFlux`+`HeatDiffusion` co-occurrence in the file).
7. `test/runtests.jl` has `include("test_channels.jl")` (legacy `include("test_channel.jl")` line preserved per D-13).
8. `bin/jl test/test_channels.jl` exits 0 — Phase 54 close gate.
</success_criteria>

<output>
After completion, create `.planning/phases/54-variant-rewrites-file-consolidation/54-05-SUMMARY.md` documenting:
- Three @testset names and final assertion counts
- Phase 54 close gate result: `bin/jl test/test_channels.jl` exit code and total elapsed time (warm daemon)
- Confirmation that the architectural invariant grep is empty
- Any solver-flag deviations from the planned defaults (e.g., if `fully_determined=false` was needed for CAC) and rationale
- Notes for Phase 55 TEST-01 — anything observed in the smokes that the rewrite of `test/test_channel.jl` should pay attention to
</output>
</content>
</invoke>
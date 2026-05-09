---
phase: 54
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/components/channels.jl
  - src/connectors.jl
  - src/STREAM.jl
  - test/test_connectors.jl
autonomous: true
requirements: [VAR-01]
must_haves:
  truths:
    - "WallPort no longer exists in src/connectors.jl"
    - "STREAM module loads without exporting WallPort"
    - "Channel(; name, n, geometry, h_left=..., h_right=...) constructs and mtkcompiles"
    - "Channel uses ThermalPort arrays per side (thermal_left[1:n], thermal_right[1:n])"
    - "Channel with h_left=0.0 and h_right=0.0 (defaults) is automatically adiabatic when ports dangle"
    - "Channel feeds q_left_expr/q_right_expr into _channel_core (no inline energy balance)"
    - "src/components/channels.jl contains the `function Channel end` disambiguation declaration before any Channel method body — protects STREAM.Channel from colliding with Base.Channel{T} (Julia stdlib's task-communication channel) once 54-04 deletes the legacy file"
    - "test/test_connectors.jl has no WallPort tests and no _StubWallDriver"
  artifacts:
    - path: "src/components/channels.jl"
      provides: "New consolidated channels file containing the `function Channel end` disambiguation declaration, _channel_core (moved from channel.jl), and the new Channel constructor"
      contains: "function Channel end; function _channel_core; function Channel"
    - path: "src/connectors.jl"
      provides: "Connector definitions (FlowPort, ThermalPort, HeatFluxPort)"
      contains: "FlowPort; ThermalPort; HeatFluxPort"
    - path: "src/STREAM.jl"
      provides: "Module entry point exports without WallPort"
      contains: "export FlowPort, ThermalPort, HeatFluxPort"
    - path: "test/test_connectors.jl"
      provides: "Connector tests minus WallPort branches"
  key_links:
    - from: "src/components/channels.jl Channel"
      to: "src/components/channels.jl _channel_core"
      via: "core = _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc, friction_correlation, q_left_expr, q_right_expr, Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right, T_out, dP)"
      pattern: "_channel_core\\(;\\s*n"
    - from: "src/STREAM.jl"
      to: "src/components/channels.jl"
      via: "include(\"components/channels.jl\")"
      pattern: "include\\(\"components/channels\\.jl\"\\)"
    - from: "src/components/channels.jl Channel"
      to: "src/connectors.jl ThermalPort"
      via: "thermal_left = [ThermalPort(; name=Symbol(:thermal_left, i)) for i in 1:n]"
      pattern: "ThermalPort\\(;\\s*name=Symbol\\(:thermal_left"
---

<objective>
Land the new `Channel` variant on the new `src/components/channels.jl` file, retire `WallPort` from the codebase, and update `src/STREAM.jl` includes and exports so the daemon can `using STREAM` without `WallPort` and with the new file path. Implements decisions D-01, D-02, D-03, D-04, D-10 (partial — file is created here; old files are deleted in 54-04).

Purpose: VAR-01 (Channel passive-recipient rewrite via ThermalPort + h kwarg) and the WallPort walk-back from Phase 52. This plan establishes the `src/components/channels.jl` file (with `_channel_core` moved out of `src/components/channel.jl`) and the new `Channel`. The old `src/components/channel.jl` and `src/components/thermal_channel.jl` are NOT deleted in this plan — that happens in 54-04 after CHF and CAC have been migrated. The old `Channel`, `ChannelHeatFlux`, and `ChannelAndContacts` from those files remain compileable so the codebase still loads end-to-end at every commit boundary.

**Disambiguation declaration carry-over:** The legacy `src/components/channel.jl:4` contains `function Channel end` — a forward declaration that creates `STREAM.Channel` as a NEW generic, independent of `Base.Channel{T}` (Julia stdlib's task-communication channel). Without this declaration, `function Channel(; name, n, ...)` in `channels.jl` would attempt to add a method to `Base.Channel`, which fails or produces wrong dispatch. While both files coexist (Waves 1–3), the legacy file's declaration covers the new `Channel` method too. But once 54-04 deletes `src/components/channel.jl`, the declaration vanishes — so it MUST be carried into `src/components/channels.jl` as part of this plan. Verified at `src/components/channel.jl:1-4`. Also verified that `ChannelAndContacts` and `ChannelHeatFlux` have NO Base collision (`grep "^function ChannelAndContacts end\|^function ChannelHeatFlux end" src/components/*.jl` returns nothing) — only `Channel` needs the disambiguation declaration.

Output: `src/components/channels.jl` exists with (in order) the `function Channel end` declaration, `_channel_core`, and the new `Channel`; `src/STREAM.jl` includes `channels.jl` AND still includes the two legacy files (legacy `Channel` is shadowed by the new one because `channels.jl` is included AFTER `channel.jl`); `WallPort` block removed from `src/connectors.jl`; `WallPort` removed from `STREAM.jl` exports; WallPort tests + `_StubWallDriver` removed from `test/test_connectors.jl`.
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
@.planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md
@CLAUDE.md
@src/components/channel.jl
@src/components/thermal_channel.jl
@src/connectors.jl
@src/STREAM.jl
@test/test_connectors.jl

<interfaces>
<!-- _channel_core API contract — Phase 53 D-02/D-03/D-08/D-10. Variant builds q_left_expr / q_right_expr,
     declares all @variables that core references, calls core, splices results into its own eqs/obs lists. -->

From src/components/channel.jl:1-4 (Base.Channel disambiguation — MUST be carried into channels.jl):
```julia
# channel.jl — Channel component and _channel_core helper for STREAM.jl

# Declare as new generic functions independent of Base
function Channel end
```

From src/components/channel.jl (lines 162-305 — moved verbatim into channels.jl):
```julia
function _channel_core(;
    n::Int,
    T,
    dp,
    port_in,
    port_out,
    geometry::PipeGeometry,
    g_acc::Real,
    friction_correlation=blasius_friction,
    q_left_expr,
    q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB,
    q_wall, q_wall_left, q_wall_right,
    T_out, dP,
)::NamedTuple{(:eqs, :obs)}
```

From src/connectors.jl (kept):
```julia
@connector function ThermalPort(; name, T=300.0, Q_flow=0.0)
    # T(t) = across; Q_flow(t) = Flow
end
```
Channel uses `ThermalPort` as arrays `thermal_left[1:n]`, `thermal_right[1:n]`. Per-cell `thermal_left[i].T` is the wall temperature on the left face of cell i.

From src/components/pump.jl (used in smoke tests — not in this plan):
```julia
Pump(dP_pump::Real; name)        # fixed-dP
Pump(; name, mdot0)              # fixed-mdot
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Create src/components/channels.jl with Channel-end declaration + _channel_core + new Channel; update STREAM.jl include/exports; delete WallPort from connectors.jl</name>
  <files>src/components/channels.jl, src/connectors.jl, src/STREAM.jl</files>
  <read_first>
    - src/components/channel.jl (lines 1-305 — current Channel + _channel_core; lines 1-4 for the `function Channel end` disambiguation declaration that MUST be carried over)
    - src/connectors.jl (full file — WallPort to delete, ThermalPort/HeatFluxPort/FlowPort to keep)
    - src/STREAM.jl (full file — include order + export line)
    - .planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md (D-01, D-02, D-03, D-04, D-10)
    - .planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md (D-02, D-03, D-08, D-10 — _channel_core API contract)
    - CLAUDE.md (Component authoring conventions; MTK Patterns)
  </read_first>
  <action>
    **Step A — Create `src/components/channels.jl`** (new file). Structure (in this exact order):

    1. **Header comment block** — brief file-purpose docstring (one short paragraph) saying this file holds the `Channel` Base-disambiguation declaration, `_channel_core`, and the three public variants `Channel`, `ChannelHeatFlux`, `ChannelAndContacts` (CHF and CAC will be added in plans 54-02 / 54-03). Mention that `_channel_core` is private (underscore-prefixed, not exported).

    2. **`function Channel end` disambiguation declaration** — carry over verbatim from `src/components/channel.jl:1-4`. The file MUST begin (after the header comment) with:
       ```julia
       # channels.jl — Channel, ChannelHeatFlux, ChannelAndContacts variants and shared _channel_core for STREAM.jl

       # Declare Channel as a new generic function independent of Base.Channel{T}
       # (Base.Channel is Julia stdlib's task-communication channel; STREAM.Channel is unrelated)
       function Channel end
       ```
       This MUST appear BEFORE both the `_channel_core` move (item 3 below) and the new `Channel(; ...)` method body (item 4 below). Without this declaration, after 54-04 deletes the legacy `channel.jl`, the new `function Channel(; name, n, ...)` body in `channels.jl` would attempt to extend `Base.Channel`, breaking module load. Note: ChannelAndContacts and ChannelHeatFlux do NOT need analogous `function ... end` declarations (they have no Base collision — verified by grep).

    3. **Move `_channel_core` verbatim** from `src/components/channel.jl` lines 146-305 (the entire `# === Phase 53: shared _channel_core ====` comment block, the docstring, and the `function _channel_core(...)` body through its `return (; eqs, obs)`). Keep the body byte-for-byte identical. Do NOT modify _channel_core in this plan — Phase 53 already verified it.

    4. **After `_channel_core`, add the new `Channel` constructor.** Use D-02 signature verbatim:
    ```julia
    """
        Channel(; name, n, geometry, g=0.0, h_left=0.0, h_right=0.0, friction_correlation=blasius_friction) -> ODESystem

    Single-phase convective channel with `n` axial finite-volume cells. Passive recipient:
    external `T_wall` arrives per-cell via `thermal_left[1:n]` / `thermal_right[1:n]` ThermalPort arrays;
    `h_left` / `h_right` are supplied as constructor kwargs (each `Real | AbstractVector | Function`,
    default `0.0`). Adiabatic when nothing is connected and h kwargs are at their defaults.

    # Arguments
    - `name`: system name (Symbol)
    - `n`: number of axial cells (Int)
    - `geometry`: pipe geometry descriptor (PipeGeometry)
    - `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
    - `h_left`, `h_right`: per-side convective HTC [W/(m^2·K)]; `Real` (broadcast to all n cells),
      `AbstractVector{<:Real}` of length n (per-cell static profile), or `Function` (time-varying via
      MTK callable parameter pattern); default `0.0` per-side ⇒ adiabatic.
    - `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

    # Ports
    - `port_in`, `port_out` -- `FlowPort`
    - `thermal_left[1:n]`, `thermal_right[1:n]` -- `ThermalPort` arrays (one per axial cell, per side)

    # Returns
    Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
    """
    function Channel(;
        name,
        n::Int,
        geometry::PipeGeometry,
        g=0.0,
        h_left::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
        h_right::Union{Real, AbstractVector{<:Real}, Function} = 0.0,
        friction_correlation=blasius_friction,
    )
        Dh = geometry.Dh
        A  = geometry.A
        L  = geometry.L
        Dt = Differential(t)

        # ----------------------------------------------------------------
        # Parameters: geometry + gravity. h_left/h_right are NOT @parameters
        # in the Real/Vector cases (they're Julia-level scalars/vectors that
        # bake into the q_left_expr/q_right_expr at construction). For the
        # callable case, we follow the v0.9 PointKinetics callable-parameter
        # pattern: FType=typeof(fn), @parameters (h_left::FType)(..) variadic.
        # ----------------------------------------------------------------
        pars_base = @parameters begin
            L = L
            D_h = Dh
            A = A
            g_acc = g
        end

        # ----------------------------------------------------------------
        # Build per-cell hL_i / hR_i Julia/MTK expressions from the kwarg.
        #   - Real    => fill(value, n) — hL_i = value (constant scalar)
        #   - Vector  => length(==n) check; hL_i = h_left[i]
        #   - Function => @parameters (h_left_fn::FType)(..); hL_i = h_left_fn(t)
        #     (uniform across cells; per-cell time-varying h is out of scope here —
        #     callers wanting that pass an AbstractVector built outside the constructor)
        # ----------------------------------------------------------------
        function _resolve_h(h, side_label)
            if h isa Real
                return fill(Num(h), n), Num[]   # (per-cell expr vector, extra params)
            elseif h isa AbstractVector
                length(h) == n ||
                    error("Channel: h_$(side_label) vector length $(length(h)) ≠ n=$n")
                return Num.(h), Num[]
            else
                # Callable — MTK callable-parameter pattern (v0.9 PK-01)
                FType = typeof(h)
                p = @parameters ($(Symbol(:h_, side_label, :_fn))::FType)(..) = h
                # Note: @parameters with a callable default returns the parameter; here we
                # use a Symbol-built name to avoid collision between left and right.
                hfn = p[1]
                return fill(hfn(t), n), collect(p)
            end
        end

        hL_per_cell, extra_pars_L = _resolve_h(h_left,  :left)
        hR_per_cell, extra_pars_R = _resolve_h(h_right, :right)
        pars = [pars_base...; extra_pars_L; extra_pars_R]

        # ----------------------------------------------------------------
        # Variables — variant declares ALL @variables that _channel_core references
        # by symbol (Phase 53 D-10). T, dp are unknowns; the rest are observable LHS.
        # ----------------------------------------------------------------
        vars = @variables begin
            (T(t))[1:n] = fill(600.0, n)
            (dp(t))[1:n] = fill(100.0, n)
            (Re(t))[1:n]
            (Pe(t))[1:n]
            (v(t))[1:n]
            (P(t))[1:n]
            (T_sat(t))[1:n]
            (T_ONB(t))[1:n]
            (q_wall(t))[1:n]
            (q_wall_left(t))[1:n]
            (q_wall_right(t))[1:n]
            T_out(t) = 600.0
            dP(t)
        end

        @named port_in  = FlowPort()
        @named port_out = FlowPort()
        thermal_left  = [ThermalPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
        thermal_right = [ThermalPort(; name=Symbol(:thermal_right, i)) for i in 1:n]

        dz = L / n

        # ----------------------------------------------------------------
        # D-04 q-expression construction (per cell).
        # q_left_expr[i]  = hL_i * heated_parts[1] * dz * (thermal_left[i].T  - T[i])
        # q_right_expr[i] = hR_i * heated_parts[2] * dz * (thermal_right[i].T - T[i])
        # And the channel-side Q_flow eqn for ThermalPort closure (D-04, line 4-5):
        # thermal_left[i].Q_flow  ~ q_left_expr[i]
        # thermal_right[i].Q_flow ~ q_right_expr[i]
        # When the port dangles, MTK Flow rule auto-zeros Q_flow ⇒ either h=0 (default IC)
        # or T_wall=T[i]; both yield zero heat. Adiabatic ✓.
        # ----------------------------------------------------------------
        q_left_expr  = Vector{Num}(undef, n)
        q_right_expr = Vector{Num}(undef, n)
        variant_eqs  = Equation[]
        for i in 1:n
            q_left_expr[i]  = hL_per_cell[i] * geometry.heated_parts[1] * dz * (thermal_left[i].T  - T[i])
            q_right_expr[i] = hR_per_cell[i] * geometry.heated_parts[2] * dz * (thermal_right[i].T - T[i])
            push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
            push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
        end

        # ----------------------------------------------------------------
        # Hand off to _channel_core (Phase 53 D-01, D-03 — single source of truth
        # for energy balance, friction, port wiring, observables).
        # ----------------------------------------------------------------
        core = _channel_core(;
            n, T, dp, port_in, port_out, geometry,
            g_acc=g, friction_correlation,
            q_left_expr, q_right_expr,
            Re, Pe, v, P, T_sat, T_ONB,
            q_wall, q_wall_left, q_wall_right,
            T_out, dP,
        )

        eqs = [variant_eqs; core.eqs]
        obs = core.obs

        all_vars = [
            collect(T); collect(dp); collect(Re); collect(Pe); collect(v);
            collect(P); collect(T_sat); collect(T_ONB);
            collect(q_wall); collect(q_wall_left); collect(q_wall_right);
            T_out; dP
        ]

        compose(
            System(eqs, t, all_vars, pars; observed=obs, name=name),
            port_in, port_out, thermal_left..., thermal_right...,
        )
    end
    ```

    Notes on the implementation:
    - **Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_*, dP** are observables emitted by `_channel_core` — variant declares them in `@variables` so core can reference the symbols, and lists them in `all_vars` as MTK requires (matching CAC's existing pattern at thermal_channel.jl:235-237).
    - **`@parameters ($(Symbol(...))::FType)(..)`** — the callable-parameter pattern needs the symbol generated dynamically. If the `$(Symbol(...))` interpolation does not evaluate inside `@parameters`, fall back to two separate `@parameters (h_left_fn::FType)(..) = h` and `@parameters (h_right_fn::FType)(..) = h` blocks guarded by branches (`if h_left isa Function ... end` outside the macro). The mechanism is documented in `.planning/STATE.md` "v0.9 PK-01" — use it as the reference.
    - **Adiabatic-by-default** verification path: when `h_left=0.0` (default), `hL_per_cell[i]=0` ⇒ `q_left_expr[i]=0` ⇒ `thermal_left[i].Q_flow ~ 0`; the dangling port's MTK Flow rule already would have set `Q_flow=0`, but here we redundantly assert it via the channel-side eqn — both forms agree, so MTK sees a consistent system. (D-04 footnote.)

    **Step B — Update `src/STREAM.jl`:**
    1. Add `include("components/channels.jl")` AFTER the existing `include("components/thermal_channel.jl")` line (so the new `Channel` shadows the legacy one when the module loads). Final order in STREAM.jl includes block:
       ```
       include("components/channel.jl")           # legacy, still here for CHF/CAC physics until 54-04
       include("components/pump.jl")
       include("components/flapper.jl")
       include("components/resistors.jl")
       include("components/misc.jl")
       include("components/thermal_channel.jl")   # legacy, still here until 54-04
       include("components/channels.jl")          # NEW — supersedes the new Channel; CHF/CAC migrate in 54-02/03
       include("components/heat_diffusion.jl")
       include("components/point_kinetics.jl")
       ```
       Rationale: putting `channels.jl` AFTER `channel.jl` and `thermal_channel.jl` means Julia evaluates the new `Channel` last; method overwriting warnings are expected and accepted at this commit boundary (Phase 54 D-12 explicitly permits the legacy variants to coexist as long as code still loads). 54-04 deletes both old files and removes the old includes.
    2. Edit the export line `export FlowPort, ThermalPort, WallPort, HeatFluxPort` ⇒ `export FlowPort, ThermalPort, HeatFluxPort` (drop `WallPort`).

    **Step C — Edit `src/connectors.jl`:**
    Delete the `WallPort` block (lines 26-53 in the current file — the entire docstring + `@connector function WallPort(...)` definition). Keep `FlowPort`, `ThermalPort`, and `HeatFluxPort` unchanged.

    **Step D — Edit `test/test_connectors.jl`:**
    1. Delete the `_StubWallDriver` function (current lines 90-99).
    2. In `_StubRecipient`, delete the `port_type === :wall` branches (the entire `if port_type === :wall ... else  # :flux ... end` is currently shaped around both — strip it down to ONLY the `:flux` branch and remove the `port_type` kwarg entirely, OR keep `port_type::Symbol=:flux` as default-to-flux-only with an `error("WallPort removed in Phase 54")` for any other value. Prefer removing the kwarg outright). Also strip out `:wall` from the `PortType = port_type === :wall ? WallPort : HeatFluxPort` line — replace with `PortType = HeatFluxPort` directly.
    3. Delete the following testsets entirely (they reference `WallPort` which no longer exists):
       - `@testset "CONN-01: WallPort instantiation"`
       - `@testset "CONN-01: WallPort variable count"`
       - `@testset "CONN-01: WallPort Q_flow is a Flow variable"`
       - `@testset "CONN-01: WallPort T_wall is across (no connect metadata)"`
       - `@testset "CONN-01: WallPort h is across (no connect metadata)"`
       - `@testset "CONN-01: WallPort adiabatic when unconnected"`
       - `@testset "CONN-01: WallPort driven case heats stub above adiabatic"`
       - `@testset "CONN-04: connect() produces non-empty equation set (WallPort)"`
       - `@testset "CONN-04: instream smoke (WallPort + FlowPort coexistence)"`
    4. Keep all `HeatFluxPort` testsets and the `_StubFluxDriver` function unchanged.

    **Verify the daemon loads the module and CHF/CAC still work:**
    The legacy `ChannelHeatFlux` and `ChannelAndContacts` continue to exist in `src/components/thermal_channel.jl`. The legacy `Channel` is shadowed by the new one (warning expected). `using STREAM` must still succeed.
  </action>
  <verify>
    <automated>bin/jl test/test_connectors.jl</automated>
  </verify>
  <acceptance_criteria>
    - `test -f src/components/channels.jl` (file exists)
    - `grep -q "^function Channel end" src/components/channels.jl` (Base.Channel disambiguation declaration carried over from legacy channel.jl:4 — REQUIRED so module load survives 54-04's legacy-file deletion)
    - `! grep -q "@connector function WallPort" src/connectors.jl` (WallPort definition gone)
    - `! grep -q "WallPort" src/STREAM.jl` (export line cleaned)
    - `grep -q "include(\"components/channels.jl\")" src/STREAM.jl` (new include present)
    - `grep -q "include(\"components/channel.jl\")" src/STREAM.jl` (old include STILL present — deleted in 54-04, not here)
    - `grep -q "include(\"components/thermal_channel.jl\")" src/STREAM.jl` (old include STILL present)
    - `grep -q "function _channel_core" src/components/channels.jl`
    - `grep -q "function Channel(;" src/components/channels.jl`
    - `grep -q "h_left::Union{Real, AbstractVector{<:Real}, Function}" src/components/channels.jl`
    - `grep -q "thermal_left = \\[ThermalPort(; name=Symbol(:thermal_left" src/components/channels.jl`
    - `! grep -q "_StubWallDriver" test/test_connectors.jl`
    - `! grep -q "WallPort" test/test_connectors.jl`
    - `bin/jl test/test_connectors.jl` exits 0 (HeatFluxPort tests pass; no WallPort tests)
    - `bin/jl -e 'using STREAM; @info "loaded"; ch = Channel(; name=:t, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); @info "Channel constructed"' returns 0` (Channel constructs at REPL — sanity smoke)
  </acceptance_criteria>
  <done>
    src/components/channels.jl exists with the `function Channel end` Base-disambiguation declaration (carried over from legacy channel.jl:4), _channel_core (moved from channel.jl), and the new Channel(; ...) constructor implementing D-02/D-03/D-04. WallPort fully removed from src/connectors.jl, src/STREAM.jl exports, and test/test_connectors.jl. Module loads and Channel constructs. CHF and CAC still come from the legacy files (unchanged) — 54-02/54-03 will replace them in channels.jl, and 54-04 will delete the legacy files.
  </done>
</task>

</tasks>

<verification>
- `bin/jl test/test_connectors.jl` passes — HeatFluxPort branches still green; no WallPort references compile or run.
- `using STREAM` at REPL succeeds (legacy Channel shadowing warning is acceptable).
- `Channel(; name=:t, n=4, geometry=PipeGeometry_circular(0.6, 0.01))` constructs without error.
- `Channel(; name=:t, n=4, geometry=PipeGeometry_circular(0.6, 0.01), h_left=fill(5000.0, 4))` constructs.
- `Channel(; name=:t, n=4, geometry=PipeGeometry_circular(0.6, 0.01), h_left=t -> 5000.0)` constructs (callable path).
- `grep -q "^function Channel end" src/components/channels.jl` (the disambiguation declaration is present — without it, 54-04's deletion of legacy channel.jl would leave the module unable to load because the new `Channel` method body would attempt to extend `Base.Channel`).
</verification>

<success_criteria>
1. `src/components/channels.jl` exists with (in order) the `function Channel end` declaration, `_channel_core`, and the new `Channel`.
2. `WallPort` no longer in `src/connectors.jl`, `src/STREAM.jl` exports, or `test/test_connectors.jl`.
3. `bin/jl test/test_connectors.jl` exits 0.
4. `Channel` constructor accepts `h_left::Union{Real, AbstractVector{<:Real}, Function}` (and `h_right` symmetrically) with default `0.0` ⇒ adiabatic.
5. `Channel` calls `_channel_core` for energy balance / friction / port wiring / observables (no inline physics).
6. Legacy `Channel` in `src/components/channel.jl` is shadowed by the new one but the file is still included so `_channel_base_eqs`-free legacy CHF/CAC continue to compile (Phase 53 already removed `_channel_base_eqs`; CHF/CAC currently inline their own physics).
7. The `function Channel end` disambiguation declaration is the FIRST top-level declaration in `channels.jl` (above any function bodies). After 54-04 deletes the legacy file, this carries forward the Base.Channel disambiguation that previously lived in `channel.jl:4`.
</success_criteria>

<output>
After completion, create `.planning/phases/54-variant-rewrites-file-consolidation/54-01-SUMMARY.md` documenting:
- Files created / modified / deleted
- Confirmation that `function Channel end` declaration is in place at the top of channels.jl (above _channel_core)
- Whether the callable-parameter `@parameters` interpolation worked or required the fallback (two-branch construction)
- Any method-overwriting warnings observed when loading STREAM
- The new Channel's `mtkcompile` size on a 4-cell smoke (n_eq, n_unknowns) for reference by downstream plans
</output>
</content>
</invoke>
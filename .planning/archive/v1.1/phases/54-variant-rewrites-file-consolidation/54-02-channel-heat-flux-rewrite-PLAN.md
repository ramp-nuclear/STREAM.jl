---
phase: 54
plan: 02
type: execute
wave: 2
depends_on: [54-01]
files_modified:
  - src/components/channels.jl
autonomous: true
requirements: [VAR-02]
must_haves:
  truths:
    - "ChannelHeatFlux(; name, n, geometry, g=0.0, friction_correlation=blasius_friction) constructs and mtkcompiles"
    - "ChannelHeatFlux no longer accepts T_wall or htc_correlation kwargs"
    - "ChannelHeatFlux uses HeatFluxPort arrays per side (thermal_left[1:n], thermal_right[1:n])"
    - "ChannelHeatFlux with default IC q_flux=0 on every cell + dangling ports is automatically zero-flux"
    - "ChannelHeatFlux feeds q_left_expr/q_right_expr (= q_flux*heated_parts*dz) into _channel_core"
    - "No internal h_tc, Nu, or Re-as-unknown declarations in the new ChannelHeatFlux body"
  artifacts:
    - path: "src/components/channels.jl"
      provides: "Adds the new ChannelHeatFlux constructor (after Channel, before — or replacing — the legacy one when 54-04 lands)"
      contains: "function ChannelHeatFlux(;"
  key_links:
    - from: "src/components/channels.jl ChannelHeatFlux"
      to: "src/components/channels.jl _channel_core"
      via: "core = _channel_core(; ...; q_left_expr, q_right_expr, ...)"
      pattern: "_channel_core\\(;\\s*n"
    - from: "src/components/channels.jl ChannelHeatFlux"
      to: "src/connectors.jl HeatFluxPort"
      via: "thermal_left = [HeatFluxPort(; name=Symbol(:thermal_left, i)) for i in 1:n]"
      pattern: "HeatFluxPort\\(;\\s*name=Symbol\\(:thermal_left"
---

<objective>
Add the new `ChannelHeatFlux` constructor to `src/components/channels.jl`, built on top of `_channel_core`. q is purely external: per-cell `q_flux` arrives via `HeatFluxPort` arrays, and the channel emits the per-cell channel-side `Q_flow` equation for port closure. Implements decisions D-05, D-06, D-07.

Purpose: VAR-02 — `ChannelHeatFlux` rewritten as a true passive recipient of prescribed heat flux. Removes `T_wall` (scalar parameter), `htc_correlation`, and all internal Nu/h_tc machinery from the constructor. The legacy `ChannelHeatFlux` in `src/components/thermal_channel.jl` (lines 278-405) remains in place and continues to be exported until 54-04 — Julia's method overwriting (since `channels.jl` is included AFTER `thermal_channel.jl`) makes the new definition the live one. A method-overwriting warning during `using STREAM` is expected.

Output: New `ChannelHeatFlux` block appended to `src/components/channels.jl` after the existing `Channel`.
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
@src/components/channels.jl
@src/components/thermal_channel.jl
@src/connectors.jl

<interfaces>
<!-- Reference: the existing legacy ChannelHeatFlux in src/components/thermal_channel.jl lines 278-405
     uses scalar T_wall_p parameter + internal htc_correlation. The new one removes both entirely. -->

From src/components/channels.jl after 54-01:
```julia
function _channel_core(; n, T, dp, port_in, port_out, geometry, g_acc,
    friction_correlation, q_left_expr, q_right_expr,
    Re, Pe, v, P, T_sat, T_ONB, q_wall, q_wall_left, q_wall_right,
    T_out, dP)::NamedTuple{(:eqs, :obs)}
```

From src/connectors.jl (HeatFluxPort, kept):
```julia
@connector function HeatFluxPort(; name, q_flux=0.0, Q_flow=0.0)
    # q_flux(t) = across; Q_flow(t) = Flow
end
```

D-07 q-expression construction:
```julia
q_left_expr[i]  = thermal_left[i].q_flux  * geometry.heated_parts[1] * dz
q_right_expr[i] = thermal_right[i].q_flux * geometry.heated_parts[2] * dz
thermal_left[i].Q_flow  ~ q_left_expr[i]
thermal_right[i].Q_flow ~ q_right_expr[i]
```
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add new ChannelHeatFlux to src/components/channels.jl</name>
  <files>src/components/channels.jl</files>
  <read_first>
    - src/components/channels.jl (full file, post-54-01 — read to understand the new Channel pattern and where to append CHF)
    - src/components/thermal_channel.jl (lines 248-405 — legacy ChannelHeatFlux; reference for dp/observables structure ONLY; do NOT carry over T_wall_p, Nu, h_tc, Gr_over_Re2)
    - .planning/phases/54-variant-rewrites-file-consolidation/54-CONTEXT.md (D-05, D-06, D-07)
    - .planning/phases/53-shared-channel-core-with-enthalpy-form-energy-balance/53-CONTEXT.md (D-02, D-03, D-08, D-10 — _channel_core API contract)
    - CLAUDE.md (Component authoring conventions; MTK Patterns)
  </read_first>
  <action>
    Append a new block to `src/components/channels.jl` after the new `Channel` function. Use D-06 signature verbatim (no `T_wall`, no `htc_correlation`):

    ```julia
    """
        ChannelHeatFlux(; name, n, geometry, g=0.0, friction_correlation=blasius_friction) -> ODESystem

    Single-phase convective channel with `n` axial finite-volume cells. Passive recipient of
    prescribed heat flux: per-cell `q_flux` [W/m^2] arrives via `thermal_left[1:n]` /
    `thermal_right[1:n]` `HeatFluxPort` arrays. Zero-flux when nothing is connected (IC
    `q_flux=0.0` + MTK Flow rule auto-zero on the dangling Q_flow).

    No internal HTC correlation, no scalar `T_wall` parameter — q is purely external.

    # Arguments
    - `name`: system name (Symbol)
    - `n`: number of axial cells (Int)
    - `geometry`: pipe geometry descriptor (PipeGeometry)
    - `g`: gravitational acceleration [m/s^2], 0.0 for horizontal (default 0.0)
    - `friction_correlation`: friction function `(Re) -> f`, default `blasius_friction`

    # Ports
    - `port_in`, `port_out` -- `FlowPort`
    - `thermal_left[1:n]`, `thermal_right[1:n]` -- `HeatFluxPort` arrays (one per axial cell, per side)

    # Returns
    Uncompiled `ODESystem`. Call `mtkcompile(sys)` before solving.
    """
    function ChannelHeatFlux(;
        name,
        n::Int,
        geometry::PipeGeometry,
        g=0.0,
        friction_correlation=blasius_friction,
    )
        Dh = geometry.Dh
        A  = geometry.A
        L  = geometry.L
        Dt = Differential(t)

        pars = @parameters begin
            L = L
            D_h = Dh
            A = A
            g_acc = g
        end

        # Variant declares ALL @variables that _channel_core references by symbol
        # (Phase 53 D-10). Same observable surface as Channel; CHF additionally has no
        # variant-specific symbols (h_tc_*, T_wall_*, Gr_over_Re2 are CAC-only).
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
        thermal_left  = [HeatFluxPort(; name=Symbol(:thermal_left,  i)) for i in 1:n]
        thermal_right = [HeatFluxPort(; name=Symbol(:thermal_right, i)) for i in 1:n]

        dz = L / n

        # --------------------------------------------------------------
        # D-07 q-expression construction (per cell). q_flux is the across var
        # of HeatFluxPort; q_left_expr[i] = q_flux * heated_parts[1] * dz [W].
        # No reference to T[i] in q (CHF is a true flux source, not Newton's-law-of-
        # cooling). Channel-side Q_flow eqn closes the port:
        #   thermal_left[i].Q_flow  ~ q_left_expr[i]
        # When dangling, MTK Flow rule sets Q_flow ~ 0 ⇒ q_flux*heated*dz = 0 ⇒
        # q_flux = 0 (its IC default). Zero-flux ✓.
        # --------------------------------------------------------------
        q_left_expr  = Vector{Num}(undef, n)
        q_right_expr = Vector{Num}(undef, n)
        variant_eqs  = Equation[]
        for i in 1:n
            q_left_expr[i]  = thermal_left[i].q_flux  * geometry.heated_parts[1] * dz
            q_right_expr[i] = thermal_right[i].q_flux * geometry.heated_parts[2] * dz
            push!(variant_eqs, thermal_left[i].Q_flow  ~ q_left_expr[i])
            push!(variant_eqs, thermal_right[i].Q_flow ~ q_right_expr[i])
        end

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

    Notes:
    - **Why `q_left_expr` does not reference T[i]:** unlike `Channel` (Newton's-law-of-cooling form `h*A*(T_wall - T)`), `ChannelHeatFlux` accepts a prescribed flux density. The driver supplies q_flux; the channel converts to total heat via `q_flux × heated_area × dz`. This matches Python STREAM's `ChannelHeatFlux` pattern (`channel.py` line 384, `class ChannelHeatFlux(Channel)`).
    - **No `Gr_over_Re2`:** the legacy CHF body declared `Gr_over_Re2` as a per-cell observable (thermal_channel.jl:307, 369-374). Drop it from the new CHF; that observable was tied to the scalar `T_wall_p` parameter which is removed. CAC retains it (variant-internal).
    - **No `Nu`, `h_tc`:** removed entirely per D-06. The CHF body in the new design has no internal HTC concept.
    - **The legacy `ChannelHeatFlux` in `src/components/thermal_channel.jl`** continues to exist after this plan. Since `channels.jl` is included AFTER `thermal_channel.jl` (per 54-01 STREAM.jl include order), Julia's method dispatch will warn-and-overwrite when the new definition is loaded. Warning is expected and accepted (D-12 tolerates it). 54-04 deletes the legacy file.
  </action>
  <verify>
    <automated>bin/jl -e 'using STREAM; using STREAM: ChannelHeatFlux; chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); ssys = mtkcompile(chf); @info "compiled" n_eqs=length(equations(ssys)) n_unk=length(unknowns(ssys))'</automated>
  </verify>
  <acceptance_criteria>
    - `grep -q "function ChannelHeatFlux(;" src/components/channels.jl`
    - `! grep -A 12 "function ChannelHeatFlux(;" src/components/channels.jl | grep -q "T_wall"` (no T_wall in the new body)
    - `! grep -A 12 "function ChannelHeatFlux(;" src/components/channels.jl | grep -q "htc_correlation"` (no htc_correlation in the new body)
    - `grep -q "thermal_left  = \\[HeatFluxPort" src/components/channels.jl`
    - `grep -q "thermal_left\\[i\\].q_flux  \\* geometry.heated_parts\\[1\\] \\* dz" src/components/channels.jl`
    - `grep -q "thermal_left\\[i\\].Q_flow  ~ q_left_expr\\[i\\]" src/components/channels.jl`
    - `bin/jl -e 'using STREAM; chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); mtkcompile(chf)'` exits 0
  </acceptance_criteria>
  <done>
    `ChannelHeatFlux` constructor in `src/components/channels.jl` follows D-06/D-07: minimal kwargs (no T_wall, no htc_correlation), HeatFluxPort arrays, q_left_expr = q_flux × heated_parts × dz, channel-side Q_flow eqns, all physics delegated to `_channel_core`. Constructs and mtkcompiles standalone.
  </done>
</task>

</tasks>

<verification>
- `bin/jl -e 'using STREAM; chf = ChannelHeatFlux(; name=:chf, n=4, geometry=PipeGeometry_circular(0.6, 0.01)); ssys = mtkcompile(chf)'` exits 0 (constructs and compiles).
- A method-overwriting warning is acceptable when `using STREAM` because the legacy CHF in thermal_channel.jl is shadowed.
- The new CHF body has no `T_wall`, no `T_wall_p`, no `htc_correlation`, no `Nu`, no `h_tc`, no `Gr_over_Re2` declarations.
</verification>

<success_criteria>
1. `ChannelHeatFlux` constructor in `channels.jl` with D-06 signature (5 kwargs only, no T_wall/htc_correlation).
2. Uses `HeatFluxPort` arrays per side per cell.
3. q construction per D-07: `q_*_expr[i] = thermal_*[i].q_flux × heated_parts × dz`.
4. Channel-side Q_flow eqns emitted for both sides per cell.
5. All energy balance / friction / momentum / port wiring delegated to `_channel_core`.
6. Constructs and `mtkcompile`s on a 4-cell unit smoke without error.
</success_criteria>

<output>
After completion, create `.planning/phases/54-variant-rewrites-file-consolidation/54-02-SUMMARY.md` documenting:
- New ChannelHeatFlux placement in channels.jl (line range)
- Whether the method-overwriting warning surfaced and its content
- The new CHF's `mtkcompile` size on a 4-cell smoke (n_eq, n_unknowns)
- Any deviation from D-06 signature or D-07 q construction (none expected)
</output>

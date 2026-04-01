# Phase 27: Pressure Field - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Add per-cell absolute pressure and saturation-related observables to all channel variants so downstream safety calculations (Phase 28 SCB, Phase 29 threshold analysis) have the spatial pressure profile they require. Scope: dP refactor, dp[i]/P[i] variables, sat_temperature function, T_sat[i]/T_ONB[i] observables. No boiling physics, no threshold functions — those are Phase 28/29.
</domain>

<decisions>
## Implementation Decisions

### Per-cell pressure drop dp[i]

- **D-01:** `dp(t)[1:n]` are MTK **unknowns** (not @observed) — they appear on the RHS of the port wiring equation `port_out.P - port_in.P ~ -sum(dp[i])`, so they must be solver variables.
- **D-02:** Per-cell equation includes inertia split equally: `dp[i] ~ f[i]*(mdot*|mdot|/(2*rho[i]*A^2))*(dz/Dh) + rho[i]*g*dz + (dz/A)*Dt(port_in.mdot)`. Each cell gets `dz/A * Dt(mdot)`; summing over n cells gives `(L/A)*Dt(mdot)` exactly — matches current total and satisfies success criterion 2.
- **D-03:** Port wiring equation changes from `port_out.P - port_in.P ~ -dP` to `port_out.P - port_in.P ~ -sum(dp[i] for i in 1:n)`. The `dP` variable is no longer a solver unknown.
- **D-04:** `dP(t)` becomes **@observed** alias: `dP ~ sum(dp[i] for i in 1:n)`. Preserves backward compatibility (`sol[ch.dP, :]` still works). Satisfies success criterion 2 exactly.

### Absolute pressure P[i]

- **D-05:** `P(t)[1:n]` are **@observed** in Channel, ChannelAndContacts, and ChannelHeatFlux.
- **D-06:** Formula uses a local Julia cumsum expression (not chained from the P[i] observed variable) to avoid observed-to-observed ordering issues: `P_i = port_in.P - sum(dp[j] for j in 1:i)` computed inside the loop, then `push!(obs, P[i] ~ P_i)`.
- **D-07:** P[i] represents **absolute pressure** — physically meaningful only when a pressure anchor is set on a FlowPort in the loop (e.g., `pump.port_in.P ~ <some_value>` as initial condition). The anchor can be any absolute pressure value; 1e5 Pa is not special. Tests must set an anchor explicitly; this must be documented.

### sat_temperature function

- **D-08:** `sat_temperature(P_Pa)` added to `src/fluids.jl` with `@register_symbolic`. Takes absolute pressure in **Pa**, returns saturation temperature in **K** (Kelvin, consistent with all other Julia STREAM temperatures).
- **D-09:** Uses the Simantov correlation from Python STREAM `light_water.py` verbatim: `X = log(abs(P_Pa) * 1e-6); T_C = (A + C*X) / (1 + B*X + D*X^2)` with A=179.9600321, B=-0.1063030, C=24.2278298, D=2.951e-4. Returns `T_C + 273.15`.

### T_sat[i] and T_ONB[i] observables

- **D-10:** `T_sat(t)[1:n]` and `T_ONB(t)[1:n]` added as **@observed** in ChannelAndContacts and ChannelHeatFlux only. Channel gets dp[i] and P[i] but NOT T_sat/T_ONB (per PRES-04).
- **D-11:** Both reference dp[j] unknowns directly via the same local `P_i` expression used for P[i] — no observed-to-observed chain:
  ```julia
  P_i = port_in.P - sum(dp[j] for j in 1:i)
  push!(obs, P[i]     ~ P_i)
  push!(obs, T_sat[i] ~ sat_temperature(P_i))
  push!(obs, T_ONB[i] ~ sat_temperature(P_i) + _bergles_rohsenow_dT_ONB(P_i, q_spl_i))
  ```
- **D-12:** `q_spl_i` for the T_ONB formula is heat flux in W/m²: `q_spl_i = q_wall[i] / (sum(geometry.heated_parts) * dz)`. `q_wall[i]` is a solver unknown in ChannelAndContacts (thermal port sum); in ChannelHeatFlux it is also an unknown. This reference is valid in observed equations.
- **D-13:** Private helper `_bergles_rohsenow_dT_ONB(P_Pa, q_spl)` added to `src/physical_models/correlations.jl`. Returns temperature difference in K (= °C for differences). Formula: `p = P_Pa / 1e5; 0.556 * (q_spl / (1082 * p^1.156))^(0.463 * p^0.0234)`. Phase 29 exports it as `Bergles_Rohsenow_T_ONB` without rewriting.

### _channel_base_eqs refactor

- **D-14:** `_channel_base_eqs` signature gains a `dp` array parameter. The scalar `dP ~ f*(...)*(L/Dh)+...` equation is replaced by: (a) n per-cell `dp[i] ~ ...` equations pushed to `eqs`, and (b) port wiring uses `sum(dp[i])` directly. The `dP` observed equation is pushed to `obs` by the caller (Channel, ChannelAndContacts, ChannelHeatFlux each build their own obs list).
- **D-15:** ChannelHeatFlux does not use `observed_mode=true` — its Re/Nu/v are unknowns, not observed. The dp[i] equations are pushed to `eqs` the same way regardless of `observed_mode`.

### Claude's Discretion

- Exact Julia variable name for the cumsum local (`P_i` vs `P_abs_i` etc.)
- Whether to declare `dp(t)[1:n]` in `@variables` block inside each channel or pass from outside
- Test pressure anchor value (any absolute pressure is correct)
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` §PRES-01..04 — per-cell dp, absolute P[i], sat_temperature, T_sat/T_ONB observables

### Existing channel implementation
- `src/components/channel.jl` — Channel component and `_channel_base_eqs` helper (current dP equation to replace)
- `src/components/thermal_channel.jl` — ChannelAndContacts and ChannelHeatFlux (observed infrastructure to extend)
- `src/fluids.jl` — existing @register_symbolic functions (sat_temperature goes here)
- `src/physical_models/correlations.jl` — existing correlation helpers (_bergles_rohsenow_dT_ONB goes here)

### Python STREAM reference
- `~/projects/STREAM/stream/substances/light_water.py` — sat_temperature Simantov coefficients
- `~/projects/STREAM/stream/physical_models/heat_transfer_coefficient/temperatures.py` — Bergles_Rohsenow_dT_ONB formula (verbatim)

### Prior context
- `.planning/STATE.md` §Accumulated Context — carry-forward MTK patterns (@observed, @register_symbolic, ifelse, pressure anchor)
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `@register_symbolic` pattern from `rho_water`, `cp_water` etc. in `src/fluids.jl` — `sat_temperature` follows identically
- `@observed obs` pattern from ChannelAndContacts (Re, Nu, velocity, Pe, Gr_over_Re2, h_tc_left/right, T_wall_left/right, q_wall_left/right) — T_sat, T_ONB, dP, P[i] extend same list
- `_channel_base_eqs` helper already accepts `dP` as a passed-in variable — extend signature to accept `dp` array

### Established Patterns
- `@variables (dp(t))[1:n]` array syntax — same as existing `(T(t))[1:n]`, `(Re(t))[1:n]` etc.
- `sum(expr for i in 1:n)` in MTK equations — works symbolically
- Per-cell loop `for i in 1:n` pushing to `eqs` and `obs` — same structure as existing energy balance loop
- `dz = L / n` for per-cell length — already used throughout

### Integration Points
- `port_out.P - port_in.P ~ -sum(dp[i])` replaces current `port_out.P - port_in.P ~ -dP` in all three channel types (via `_channel_base_eqs`)
- `dP` variable removed from solver unknowns in all three channels; added to `obs` list instead
- `dp(t)[1:n]` added to `all_vars` in Channel and ChannelHeatFlux; ChannelAndContacts uses separate `all_vars` list
- `P(t)[1:n]`, `T_sat(t)[1:n]`, `T_ONB(t)[1:n]` added to `@variables` block and `obs` in relevant channels
- Test files: `test_channel.jl` and `test_solvers.jl` need pressure anchor set; PRES-01..04 test cases go in `test_channel.jl`
</code_context>

<specifics>
## Specific Ideas

- Pressure anchor: any absolute pressure value is valid — tests may use 1e5 Pa but this is not physically special
- P[i] is meaningless without an anchor; this must be noted in docstrings and test comments
- `_bergles_rohsenow_dT_ONB` is private (underscore prefix, not exported) — Phase 29 elevates it to `Bergles_Rohsenow_T_ONB` public export
- sat_temperature: guard `abs(P_Pa)` inside log as Python STREAM does (prevents domain error at bad Newton iterates)
</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.
</deferred>

---

*Phase: 27-pressure-field*
*Context gathered: 2026-03-28*

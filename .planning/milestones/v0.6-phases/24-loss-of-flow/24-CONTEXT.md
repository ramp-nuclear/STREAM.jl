# Phase 24: Loss-of-Flow Validation - Context

**Gathered:** 2026-03-20
**Status:** Ready for planning

<domain>
## Phase Boundary

Validate the full loss-of-flow transient end-to-end: forced flow downward through a heated
vertical channel, pump coastdown via Inertia decay, mdot sign reversal, Flapper opening in
the natural-circulation bypass path, and quasi-static natural circulation established upward.
Asserts energy balance throughout (VAL-01) and natural circulation energy balance in the
quasi-steady regime (VAL-02).

</domain>

<decisions>
## Implementation Decisions

### Loop topology
- **D-01:** Heat source is `ChannelHeatFlux` with fixed `Q_wall` — no `HeatDiffusion`, no `ChannelAndContacts`. Simple, analytically tractable energy balance.
- **D-02:** Vertical loop with gravity. Buoyancy is the natural circulation driving force.
- **D-03:** `Inertia` component in the loop provides the coastdown time constant. Without it, mdot would jump instantly when the pump is set to zero.
- **D-04:** Parallel-path topology: two branches between a common inlet node and a common outlet node.
  - **Branch 1 (forced-flow):** `Pump(0.0) → Inertia → ChannelHeatFlux(g_acc, forced flow DOWNWARD)`
  - **Branch 2 (natural-circ bypass):** `Flapper → Gravity` (upward natural circulation path)
- **D-05:** Forced flow direction is **downward** through the heated channel (against buoyancy). Natural circulation direction is **upward** (buoyancy-driven). This is the MTR-like configuration that produces true mdot sign reversal.
- **D-06:** Bypass path contains `Flapper + Gravity` only — no unheated Channel. Adding a Channel in the bypass adds friction and gravity in that path, which is realistic but overcomplicates the test for marginal benefit.
- **D-07:** Separate `Gravity` components in both parallel paths with correct signs for each direction. The forced-flow leg has its own gravity (downward = pressure gain for downward flow), the bypass has its own gravity (upward natural circ leg).

### Pump shutoff strategy
- **D-08:** `Pump(0.0)` — zero pressure rise — with `Inertia` IC set to steady-state mdot. This is mathematically equivalent to the pump turning off at t=0 with initial momentum equal to the forced-flow steady state. Chosen because callable `Pump(f(t))` is incompatible with `Flapper`'s `SymbolicContinuousCallback` (MTK `compile_equational_affect` cannot resolve callable parameters at ODEProblem build time — documented in Phase 23 FLAP-06).
- **D-09:** Initial conditions come from `solve_steady` on the **full LOF system** (Flapper present, `T_open=1e30`). With `T_open=1e30` the Flapper acts as pure `R_closed` in the bypass; KINSOL ignores continuous events entirely, so the steady-state solve produces the correct forced-flow ICs without needing a separate no-Flapper system.

### Flapper trigger
- **D-10:** Flapper `threshold` = 10% of initial forced-flow mdot. Triggers slightly before true zero-crossing, ensuring the event fires cleanly as mdot decays through the inertia time constant.

### Simulation duration and continuity
- **D-11:** Single `solve_transient` call covering 200–500 s. VAL-01 requires no solver restart — one continuous simulation from forced-flow through natural circulation.
- **D-12:** Natural circulation quasi-steady state is defined as the **last 10%** of the simulation time window. VAL-02 assertions use averaged mdot and dT over this window.

### Validation assertions
- **D-13:** VAL-01 — energy balance `Q_in ≈ mdot * cp * dT` checked at ~5 sampled time checkpoints spanning the full transient (forced flow, coastdown, transition, natural circ). Tolerance: 5% rtol.
- **D-14:** VAL-02 — energy balance in quasi-steady natural circulation (last 10% of window). Tolerance: 10% rtol. The reference is purely the energy balance equation — no Elenbaas-based mdot prediction required. VAL-02 is satisfied when the simulation's own mdot and dT are internally consistent with the imposed Q_wall.

### Test file and structure
- **D-15:** New file `test/test_loss_of_flow.jl` — dedicated to the LOF scenario. Added as one `@testset` include in `runtests.jl`.
- **D-16:** `build_loop_lof()` helper added to `src/examples.jl`. The parallel-path topology is non-trivial; a named builder makes the test readable and the system reusable.
- **D-17:** One plan (24-01) covers the loop builder and test suite together — they are tightly coupled.

### Claude's Discretion
- Exact `L_over_A` for `Inertia` and `L`, `Dh`, `Q_wall` for `ChannelHeatFlux` — choose values that give a coastdown time constant of ~10–30 s and natural circulation mdot that is physically reasonable (order 1e-2 to 1e-1 kg/s)
- Exact height `H` for each Gravity component — keep consistent with the Channel length
- How to handle the temperature boundary condition at the HeatExchanger / inlet BC (same pattern as `build_loop_vertical`)
- Whether the pressure anchor goes at the pump inlet or a junction node

</decisions>

<specifics>
## Specific Ideas

- The topology has two parallel branches sharing inlet and outlet nodes — use `connect()` for the junction points exactly as the Cube network does, no Junction component needed.
- The Flapper bypass `Gravity` component models the return height of the natural circulation path. When the Flapper opens, buoyancy (density difference between hot and ambient) drives flow through this path and reverses flow through the Channel.
- For the energy balance assertion: extract `sol[ssys.ch.inlet.mdot, i]`, `sol[ssys.ch.T_out, i]`, `sol[ssys.ch.T_in, i]` at each checkpoint. Compute `Q_meas = mdot * cp_water(T_in) * (T_out - T_in)`. Assert `|Q_meas - Q_wall| / Q_wall < 0.05`.
- During the downward forced-flow phase `T_out < T_in` (outlet is axially downstream = bottom, cooler entry at top). After reversal, `T_out > T_in`. The energy balance sign should be taken as `|mdot| * cp * |T_out - T_in|` to stay positive throughout.

</specifics>

<canonical_refs>
## Canonical References

No external specs — requirements are fully captured in decisions above and REQUIREMENTS.md.

### Validation requirements
- `.planning/REQUIREMENTS.md` §Validation — VAL-01, VAL-02 requirement text (energy balance assertion, natural circulation temperature rise)

### Prior implementation patterns
- `src/components/flapper.jl` — Flapper implementation; T_open=1e30 sentinel, SymbolicContinuousCallback, ref_mdot wiring
- `src/examples.jl` §build_loop_vertical — reference for gravity wiring pattern (Channel g_acc + Gravity on return); `build_loop_lof()` goes in this same file
- `test/test_flapper.jl` §FLAP-06 — canonical pattern for Pump(0.0)+Inertia IC coastdown and solve_steady IC extraction with Flapper present
- `src/components/misc.jl` — Inertia, HeatExchanger components
- `src/components/resistors.jl` — Gravity component; port orientation convention (inlet at bottom, outlet at top)

### MTK event compatibility note
- Phase 23 CONTEXT.md §SOLV-01 and FLAP-06 note: callable Pump parameters are incompatible with SymbolicContinuousCallback in the same ODEProblem. Pump(0.0) scalar is the required pattern when Flapper is present.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Flapper` (`src/components/flapper.jl`): Drop-in component; wire `flapper.ref_mdot ~ inertia.inlet.mdot` during composition
- `Inertia` (`src/components/misc.jl`): `L_over_A` parameter; `D(inlet.mdot)` gives coastdown dynamics
- `ChannelHeatFlux` (`src/components/thermal_channel.jl`): `Q_wall` parameter, `g_acc` parameter for vertical orientation; sign of `g_acc` controls upward vs downward pressure head
- `Gravity` (`src/components/resistors.jl`): `H` parameter; `inlet.P - outlet.P ~ rho*g*H`; inlet = high-pressure (bottom) end
- `HeatExchanger` (`src/components/misc.jl`): temperature BC reset at pump outlet (same role as in `build_loop_vertical`)
- `solve_steady` (`src/solvers.jl`): KINSOL-based; safe to use on system with Flapper (events ignored)
- `solve_transient` (`src/solvers.jl`): `callbacks` kwarg pre-wired; `initializealg=NoInit()` handles Flapper IC

### Established Patterns
- `build_loop_vertical` (`src/examples.jl`): canonical gravity wiring reference; `build_loop_lof()` extends this with a second branch
- Pressure anchor: `pump.inlet.P ~ 1e5` — required in any multi-branch network
- Temperature anchor for hydraulics-only closed loops: two `T` pins needed (from Phase 22 experience with RL-decay loops)
- `Pair{Any,Any}` op vector when mixing Float64 state ICs — required when Inertia IC is set alongside T-field ICs

### Integration Points
- `build_loop_lof()` → `src/examples.jl` (appended after `build_loop_vertical`)
- `test/test_loss_of_flow.jl` → new file; `include("test_loss_of_flow.jl")` added to `test/runtests.jl`
- `STREAM.jl` module entry: no new exports needed (all components already exported)

</code_context>

<deferred>
## Deferred Ideas

- Adding an unheated `Channel` (pipe friction) in the Flapper bypass path — realistic but adds complexity beyond what a validation test needs; defer to future LOF refinement
- Elenbaas-based analytical mdot prediction for VAL-02 — would require solving the implicit buoyancy-friction-HTC coupling; deferred in favour of pure energy balance check
- Time-varying pump with realistic coastdown curve (exponential decay) — requires callable Pump, which is incompatible with Flapper until the MTK limitation is resolved; defer to v0.7+

</deferred>

---

*Phase: 24-loss-of-flow*
*Context gathered: 2026-03-20*

# flapper.jl -- Flapper check-valve component

"""
    Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0, fluid=Water()) -> System

Flapper (passive check valve). While closed it admits **no flow** (`ṁ = 0`); once open it
is a quadratic resistor `ΔP = f·mdot·|ṁ| / (2·ρ·area²)`. The valve opens the moment the
wired reference flow `ref_mdot` falls to `open_at_current`, detected by `flapper_callback`,
which latches the opening time into the parameter `T_open`. After `T_open` the flow ramps in
gradually through `xi = r(open_rate·(t − T_open))`, the C1 Hermite cubic `−2x³ + 3x²` rising
0→1, so `ṁ = xi · mdot_open`.

This mirrors Python STREAM's `Flapper` (closed ⇒ `ṁ` 0; open ⇒ quadratic local-pressure
resistor relaxed in from `t_open`). Two deliberate conventions:

  - **Relaxation.** STREAM.jl always uses the continuously-differentiable ramp `−2x³ + 3x²`.
    Python *defaults* to `legacy_relaxation` and only opts into this shape per-call, so the
    ramp *shape* differs for cases that take Python's default; the open/closed binary and the
    latch time — what the integration tests assert — do not.
  - **Open-state sign.** `mdot_open = sign(P_in − P_out)·√(|ΔP|·2ρA²/f)`. Python writes
    `−sign(dp)·√(…)` against its own `dp = P_out − P_in`; the two sign flips cancel, so the two
    formulas are numerically identical (verified across both flow directions).

`T_open` is a parameter defaulting to `Inf` (valve never opens on its own). `flapper_callback`
sets it to the detected crossing time; to pre-open the valve at a fixed time `t0` instead
(Python's `open(t0)`), pass `flapper.T_open => t0` in the operating point. Reset to `Inf` to
close it again (Python's `close()`).

Because a closed flapper carries no flow, it is meant to sit in **parallel** with another
branch (a bypass that carries flow while the valve is shut); a closed flapper placed in series
would block the whole loop.

`ref_mdot` has **no equation inside the component** — the caller wires it during composition,
most readably with [`watch_flow`](@ref):
```julia
watch_flow(flapper, pump.inlet.ṁ)      # ≡  flapper.ref_mdot ~ pump.inlet.ṁ
```
Then build the detection event with `flapper_callback(ssys, ssys.flapper)` and hand it to
`solve_transient(...; callbacks=cb)`.

# Arguments
- `name`: system name (Symbol), injected by `@named` macro
- `open_at_current`: reference flow at/below which the valve opens [kg/s] (default 0.01). The
  callback reads this off the component, so it is not passed by hand.
- `f`: open-state quadratic loss coefficient (default 1.0)
- `area`: flow area [m²] (default 1.0)
- `open_rate`: relaxation rate [1/s]; the open ramp completes after `1/open_rate` s (default 1.0)
- `fluid`: coolant property set (`AbstractFluid`), default `Water()` — supplies the density at
  the inlet stream temperature

# Ports
- `inlet`, `outlet`: `FlowPort` (pressure, mass flow, temperature)

`ref_mdot` has no in-component equation, so a standalone Flapper is
structurally underdetermined — call `mtkcompile(sys; fully_determined=false)`, or compose it
into a system where `ref_mdot` is wired.
"""
function Flapper(; name, open_at_current=0.01, f=1.0, area=1.0, open_rate=1.0,
                 fluid::AbstractFluid=Water())
    pars = @parameters begin
        open_at_current = open_at_current
        f = f
        area = area
        open_rate = open_rate
        T_open = Inf
    end

    vars = @variables xi(t) ref_mdot(t)

    @named inlet = FlowPort()
    @named outlet = FlowPort()

    rho = density(fluid, instream(inlet.T))
    dp = inlet.p - outlet.p
    x = open_rate * (t - T_open)
    relax = ifelse(x <= 0.0, 0.0, ifelse(x >= 1.0, 1.0, -2 * x^3 + 3 * x^2))
    # Open-state flow: invert ΔP = f·mdot·|ṁ|/(2ρA²) ⇒ ṁ = sign(dp)·sqrt(|dp|·2ρA²/f).
    mdot_open = sign(dp) * sqrt(abs(dp) * 2 * rho * area^2 / f)

    eqs = Equation[
        xi ~ relax,
        # Closed (t ≤ T_open): ṁ = 0. Open: ṁ = xi · mdot_open (quadratic, ramped in).
        ifelse(t <= T_open, inlet.ṁ, inlet.ṁ - relax * mdot_open) ~ 0,
        # ref_mdot has no equation here — wire it with watch_flow during composition
    ]

    return HydraulicTwoPort(; name, inlet, outlet, eqs, vars, pars)
end

"""
    watch_flow(flapper, sym) -> Equation

Wire a Flapper's reference flow to the mass flow `sym` it should watch, returning the equation
`flapper.ref_mdot ~ sym`. Add it to the connection list during composition:

```julia
conns = [
    inparallel(pump, (bypass, flapper), hx)...,
    watch_flow(flapper, bypass.inlet.ṁ),     # flapper opens when the bypass flow decays
]
```

The watched flow can be any mass-flow variable in the system (a port `ṁ`, a resistor inlet,
an inertia branch). The detection event built by [`flapper_callback`](@ref) reads the wired
flow back through this equation, so the two must refer to the same `flapper`.

# Arguments
- `flapper`: a `Flapper` subsystem (before compilation)
- `sym`: the mass-flow variable to watch [kg/s]

# Returns
`Equation` — `flapper.ref_mdot ~ sym`.
"""
watch_flow(flapper, sym) = flapper.ref_mdot ~ sym

"""
    flapper_callback(ssys, flappers...) -> ContinuousCallback | CallbackSet

Build the opening-detection event(s) for one or more flappers in a compiled system. Each
flapper opens when its wired `ref_mdot` falls through its own `open_at_current`; the callback
latches that crossing time into the flapper's `T_open` parameter.

The crossing is found by root-finding the reference flow itself: the observed function for
`flapper.ref_mdot` is evaluated at the integrator's trial state `(u, p, t)`, so detection is
exact and works whether `ref_mdot` resolves to a differential state (a branch with inertia) or
to a purely algebraic quantity (a quasi-static branch). This is the key difference from a
per-step value check. While a flapper is closed it carries no flow and is dynamically decoupled
from `ref_mdot`, so an adaptive solver places no steps near the crossing and a discrete check
can sail past it; the root-finder seeks the crossing out regardless of where the steps land.

Everything the event needs (the threshold `open_at_current`, the reference `ref_mdot`, and the
latched `T_open`) is read off the component, so nothing is passed by hand. Pass several flappers
to monitor them together and the result is a `CallbackSet`; with one flapper a single
`ContinuousCallback` is returned. Only downward crossings open the valve, and once latched it
stays open (a later upward recovery is ignored).

# Arguments
- `ssys`: compiled system from `mtkcompile`
- `flappers`: one or more Flapper subsystems, e.g. `ssys.flapper` (or `ssys.flap1, ssys.flap2`)

# Returns
A `ContinuousCallback` (single flapper) or `CallbackSet` (several). Pass it to
`solve_transient(...; callbacks=cb)`.

# Example
```julia
cb  = flapper_callback(ssys, ssys.flapper)             # one flapper
cb2 = flapper_callback(ssys, ssys.flap1, ssys.flap2)   # several -> CallbackSet
sol = solve_transient(ssys, op, t_arr; callbacks=cb)
```
"""
function flapper_callback(ssys, flappers...)
    cbs = map(flappers) do flap
        ref_obs = ModelingToolkit.build_explicit_observed_function(ssys, flap.ref_mdot)
        get_threshold = ModelingToolkit.getp(ssys, flap.open_at_current)
        set_T_open = ModelingToolkit.setp(ssys, flap.T_open)

        # Condition crosses zero downward as ref_mdot falls through the threshold; evaluating
        # the observed function at the trial state is what makes this exact for algebraic refs.
        condition = (u, tt, integ) -> ref_obs(u, integ.p, tt) - get_threshold(integ)
        affect_open = integ -> set_T_open(integ, integ.t)
        # (condition, up-crossing affect = nothing, down-crossing affect = latch T_open)
        ContinuousCallback(condition, nothing, affect_open)
    end

    return length(cbs) == 1 ? cbs[1] : CallbackSet(cbs...)
end

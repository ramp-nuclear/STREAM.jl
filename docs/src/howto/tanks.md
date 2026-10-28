# Set up a tank for the steady solve

A [`Tank`](@ref STREAM.Components.Tank)'s level and temperature are states, and in a steady
state neither is always determined by the rest of the model. Two choices settle them: whether
the level is pinned at `L0`, the parameter `pinned`, and whether the temperature is held at
`T0`, the keyword `fixed_temperature`. [Loss of coolant](../explanation/loca.md) explains why;
this page shows the setup for each case.

```@example tanks
using STREAM
using STREAM.Components: Tank, Pump, HeatExchanger, Orifice, Environment, StateMachine
using STREAM.Assemblies: inseries
using STREAM.LocalLoss: discharge_cd
using OrdinaryDiffEq: Rodas5P
using SteadyStateDiffEq: DynamicSS
nothing # hide
```

## A tank the loop flows through

Leave the level pinned, the default, and let the temperature follow the inflow with
`fixed_temperature=false`. The steady temperature is then the temperature of what flows in,
here a heater's outlet:

```@example tanks
@assembly sys begin
    tank = Tank(; area=2.0, L0=3.0, ports=(out=0.0, back=2.0), T0=20.0,
                fixed_temperature=false)
    pump = Pump(; ṁ0=5.0)
    heater = HeatExchanger(45.0)
    inseries(tank.out, pump, heater, tank.back)
end
sol = solve_steady(sys)
@assert sol[sys.tank.T] ≈ 45.0
(level=sol[sys.tank.L], temperature=sol[sys.tank.T])
```

The tank also fixes the loop's absolute pressure through its surface, so the loop needs no
other pressure anchor. Release the pin for the transient, `overrides=[sys.tank.pinned =>
false]`.

## A tank with no inflow

A sealed tank, or one on standby behind a shut valve, has nothing flowing in to set its
temperature. Either hold the temperature, `fixed_temperature=true`, which the steady solve
needs nothing more for, or skip the steady solve and start the transient from the declared
state, releasing the pin in the operating point. Here a sealed pool is heated from outside
for ten minutes:

```@example tanks
Q, V = 1.0e5, 2.0 * 4.0                   # heat [W] and volume [m³]
@assembly sys begin
    sealed = Tank(; area=2.0, L0=4.0, ports=(bottom=0.0,), T0=30.0, Q_ext=Q,
                  fixed_temperature=false)
    shut = Orifice(; area=5e-4, cd=discharge_cd(:sharp))  # never opens
    room = Environment()
    inseries(sealed.bottom, shut, room.port)
end
sol = solve_transient(sys, [sys.sealed.pinned => false], range(0.0, 600.0; length=61))
warming = Q * 600.0 / (ρ(H2O, 30.0) * V * cₚ(H2O, 30.0))
@assert isapprox(sol[sys.sealed.T][end] - 30.0, warming; rtol=1e-2)
(T_end=sol[sys.sealed.T][end], estimate=30.0 + warming)
```

## A tank fed and drained at once

A tank with a feed and a drain that does not depend on its level has a level of its own: the
one at which the drain passes the feed. Release the pin for the steady solve, in the operating
point, and the solve finds it. A tank drained through a hole at its floor settles where the
hole passes the feed, ``ṁ = C_d a ρ \sqrt{2 g L}``:

```@example tanks
ṁ_feed, a, cd = 2.0, 5.0e-4, discharge_cd(:sharp)
@assembly sys begin
    pool = Tank(; area=0.2, L0=4.0, ports=(bottom=0.0, feed=0.0), T0=30.0)
    supply = Environment(; T=30.0)
    feed = Pump(; ṁ0=ṁ_feed)
    drain = Orifice(; area=a, cd, dp_linear=1e-3,
                    machine=StateMachine(; initial_state=:OPEN, initial_time=-1.0))
    outside = Environment()
    inseries(supply.port, feed, pool.feed)
    inseries(pool.bottom, drain, outside.port)
end
sol = solve_steady(sys, [sys.pool.pinned => false]; solver=DynamicSS(Rodas5P()),
                  abstol=1e-10, reltol=1e-10)
L_settled = (ṁ_feed / (cd * a * ρ(H2O, 30.0)))^2 / (2G_EARTH)
@assert isapprox(sol[sys.pool.L], L_settled; rtol=1e-4)
(level=sol[sys.pool.L], expected=L_settled)
```

The drain opened before the run, `initial_time=-1.0`, so it is fully open in the steady state.
`DynamicSS` integrates to where the level settles, which a Newton solve from `L0` may not
reach; [Get a steady solve to converge](steady_solve.md) has more on it. It stops when the
state has nearly stopped changing, and a level that approaches its steady value slowly is
still a little off then, so the tolerances are tighter than the default.

## Two tanks

Two tanks joined by a loop, with nothing leaving it, have flows that balance whatever water
shifts from one to the other. Pin one of them and leave the other free, as one pressure is
fixed in a closed loop of pipes. The
[pool and decay tank tutorial](../tutorials/08_pool_loca.md) pins the pool and lets the decay
tank find its level.

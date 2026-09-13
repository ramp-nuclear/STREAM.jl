using STREAM
using STREAM: G_EARTH, PipeGeometry, PipeGeometry_rectangular, PipeGeometry_circular
using STREAM.Components
using STREAM.Components: Channel   # explicit, since Base.Channel also exists
using STREAM.Assemblies
using STREAM.Utilities: cosine_shape
using ModelingToolkit
using ModelingToolkit: connect, t_nounits as t, D_nounits as D
using OrdinaryDiffEq: CallbackSet, ReturnCode, Rodas5P
using SteadyStateDiffEq: DynamicSS

"""
    build_pool_lofa(ctrl, source; case) -> NamedTuple

A pool-type research reactor with downward forced flow, several assembly types in parallel,
a flapper above the core, and point kinetics, built for a loss-of-flow transient.

The pool feeds every assembly type and the flapper. Each type is one representative channel
between two half plates ([`symmetric_plate`](@ref)), standing for `N` identical channels
through [`weighted`](@ref), behind an inlet orifice. The types merge in the lower plenum,
and a riser carries the flow up to the flapper node, where the pump suction draws it off:

    pool → assembly types (down) → plenum → riser (up) → flapper node
         → primary piping → pump → flywheel → pool
    pool → flapper → flapper node

Every branch that starts at the pool starts with a `HeatExchanger(T_pool)`, which sets the
temperature of whatever leaves it in either direction. That is the pool acting as the heat
sink once natural circulation turns the core around.

The pump is a scalar head and the flywheel an `Inertia`, so after the trip the coastdown is
whatever the momentum balance gives against the changing loop resistance. One
`PointKinetics` drives every plate, with `source` as its `power_input`, and the plates are
coupled to `pk.P`, the total power.

# Arguments
- `ctrl`: the `ReactivityController` driving the kinetics, in its running state
- `source`: the kinetics' `power_input`, normally a `DecayHeat.DecayHeatSource` reading
  `ctrl` and built with `P0 = 1`, since the kinetics run dimensionless

# Keywords
- `case`: a `NamedTuple` of plant data. Pressure drops are positive numbers. Common fields:
  `L` heated length [m], `n` axial cells, `nx` lateral cells per plate, `rho_s`, `cp_s`,
  `k_s` plate material, `T_pool` [°C], `p_pool` pressure at the core top [Pa], `P_rated`
  [W], `dP_pump` [Pa], `flywheel_L_over_A` [1/m], `primary_dp` drop across the primary
  piping at design flow [Pa], `riser_L`, `riser_D` [m], `flapper_open_at` pump-branch flow
  that opens it [kg/s], `flapper_f`, `flapper_area` [m²], `flapper_open_time` [s],
  `trip_fraction` of design primary flow that trips the reactor, and `Lambda`, `beta_k`,
  `lambda_k`. `types` holds one `NamedTuple` per assembly type, with `N` channels, `width`,
  `gap` and `heated_width` [m], `plate_thickness` [m], `ppf` axial peaking factor,
  `power_fraction` of `P_rated`, `orifice_dp` [Pa] and `design_ṁ` per channel [kg/s], the
  orifice's known point.

# Returns
A `NamedTuple`:
- `ssys`: the compiled system
- `guess`: an operating point for [`solve_pool_lofa_steady`](@ref), with the pump running
  and the flapper shut
- `trip`: the overrides that start the transient: the pump head set to zero, and the
  parameters a solution snapshot does not carry
- `callbacks`: the flapper opening and the low-flow trip, as a `CallbackSet`
- `design_ṁ`: the total design flow [kg/s]
- `channels`, `pipes`: each assembly type's compiled channel and its geometry, keyed like
  `case.types`, which is what [`threshold_analysis`](@ref) takes
- `n_before`: how many unknowns the model had before `mtkcompile` reduced it
"""
function build_pool_lofa(ctrl, source; case)
    g = G_EARTH
    n, nx, L, T_pool = case.n, case.nx, case.L, case.T_pool
    z_bounds = range(0.0, L; length=n + 1)

    @named pk = PointKinetics(
        ctrl;
        power_input=source,
        Lambda=case.Lambda,
        beta_k=case.beta_k,
        lambda_k=case.lambda_k,
    )

    type_systems = Any[]
    paths = Any[]
    pipes = PipeGeometry[]
    power_eqs = Equation[]
    for (key, ty) in pairs(case.types)
        geom = PipeGeometry_rectangular(L, ty.width, ty.gap, ty.heated_width)
        push!(pipes, geom)
        # The core turns around into natural circulation, so the wall has to change regime
        # on its own, natural convection included. Subcooled boiling sits on top: Bergles
        # and Rohsenow for the onset and the partial boiling, and a boiling flux blended
        # across the same Re band.
        single_phase = HTC.RegimeDependent(;
            laminar=HTC.ConstantNusselt(; Nu=8.235),
            turbulent=HTC.DittusBoelter(),
            natural=HTC.Elenbaas(geom; g=g),
            geom=geom,
            g=g,
        )
        htc = HTC.SubcooledBoiling(single_phase, HTC.regime_dependent_q_scb())
        # As Python applies it, the rectangular correction k_R scales the Reynolds number both
        # branches see: 64/(Re·k_R) in laminar flow and Blasius at Re·k_R in turbulent flow.
        darcy = Friction.RegimeDependent(;
            laminar=Friction.laminar,
            turbulent=Friction.blasius,
            k_R=Friction.rectangular_correction(geom.depth / geom.width),
        )
        ch = ChannelAndContacts(;
            name=Symbol(:ch_, key), n=n, geometry=geom, g=-g, htc=htc, darcy=darcy
        )
        shape = repeat(cosine_shape(z_bounds, ty.ppf) ./ nx, 1, nx)
        fuel = HeatDiffusion(;
            name=Symbol(:fuel_, key),
            nz=n,
            nx=nx,
            Lz=L,
            Lx=ty.plate_thickness,
            y=ty.heated_width,
            rho_s=case.rho_s,
            cp_s=case.cp_s,
            k_s=case.k_s,
            power_shape=shape,
            T0=T_pool,
        )
        rods = symmetric_plate(ch, fuel; name=Symbol(:rods_, key))
        pool = HeatExchanger(T_pool; name=Symbol(:pool_, key))
        orifice = ResistorFromKnownPoint(;
            name=Symbol(:orifice_, key), dp=-ty.orifice_dp, ṁ=ty.design_ṁ, T=T_pool
        )
        path = weighted(ty.N, pool, orifice, getproperty(rods, nameof(ch)); name=key)
        append!(type_systems, [first(path), pool, orifice, rods, last(path)])
        push!(paths, path)
        plate_power = case.P_rated * ty.power_fraction / ty.N
        push!(power_eqs, getproperty(rods, nameof(fuel)).power ~ pk.P * plate_power)
    end

    ṁ_design = sum(ty.N * ty.design_ṁ for ty in values(case.types))
    @named pump = Pump(case.dP_pump)
    @named flywheel = Inertia(case.flywheel_L_over_A)
    @named primary = ResistorFromKnownPoint(; dp=-case.primary_dp, ṁ=ṁ_design, T=T_pool)
    @named riser = Channel(;
        n=n, geometry=PipeGeometry_circular(case.riser_L, case.riser_D), g=g
    )
    @named pool_flapper = HeatExchanger(T_pool)
    @named flapper = Flapper(;
        open_at_current=case.flapper_open_at,
        f=case.flapper_f,
        area=case.flapper_area,
        open_rate=1 / case.flapper_open_time,
    )

    connections = Equation[
        # The pool: the pump returns here, and every pool-facing branch starts here.
        connect(flywheel.outlet, (first(p).inlet for p in paths)..., pool_flapper.inlet),
        # The lower plenum: the assembly types merge and the riser starts.
        connect((last(p).outlet for p in paths)..., riser.inlet),
        # The flapper node above the core: riser, flapper and pump suction.
        connect(riser.outlet, flapper.outlet, primary.inlet),
        inseries(pool_flapper, flapper)...,
        inseries(primary, pump, flywheel)...,
        flywheel.outlet.p ~ case.p_pool,
        watch_flow(flapper, flywheel.inlet.ṁ),
        # The riser is adiabatic, so its wall temperatures only close the system.
        [riser.T_wall_left[i] ~ T_pool for i in 1:n]...,
        [riser.T_wall_right[i] ~ T_pool for i in 1:n]...,
        power_eqs...,
    ]
    for path in paths
        append!(connections, inseries(path...))
    end

    systems = [
        pk, pump, flywheel, primary, riser, pool_flapper, flapper, type_systems...
    ]
    full = compose_systems(systems...; connections=connections, name=:pool_lofa)
    ssys = mtkcompile(full)

    ic = point_kinetics_steady_state(
        1.0;
        Lambda=case.Lambda,
        beta_k=case.beta_k,
        lambda_k=case.lambda_k,
        power_input=source(0.0),
    )
    cp = cₚ(H2O, T_pool)
    T_mixed = T_pool + case.P_rated / (ṁ_design * cp)
    # Every candidate flow is seeded, aliases included, so the guess sits in the forced-flow
    # basin whichever of them mtkcompile kept as unknowns.
    guess = Pair{Any,Any}[
        ssys.pk.rho_c_fn => ctrl,
        ssys.pk.P_neutron => ic.P_neutron,
        [ssys.pk.C[k] => ic.C_k[k] for k in eachindex(ic.C_k)]...,
        ssys.flapper.T_open => Inf,
        ssys.flywheel.inlet.ṁ => ṁ_design,
        D(ssys.flywheel.inlet.ṁ) => 0.0,
        ssys.riser.inlet.ṁ => ṁ_design,
        D(ssys.riser.inlet.ṁ) => 0.0,
        ssys.primary.inlet.ṁ => ṁ_design,
        ssys.flywheel.outlet.p => case.p_pool,
        [ssys.riser.T[i] => T_mixed for i in 1:n]...,
    ]
    for (key, ty) in pairs(case.types)
        rods = getproperty(ssys, Symbol(:rods_, key))
        ch = getproperty(rods, Symbol(:ch_, key))
        fuel = getproperty(rods, Symbol(:fuel_, key))
        dT = case.P_rated * ty.power_fraction / ty.N / (ty.design_ṁ * cp)
        push!(guess, ch.inlet.ṁ => ty.design_ṁ, D(ch.inlet.ṁ) => 0.0)
        for i in 1:n
            T_i = T_pool + i / n * dT
            push!(guess, ch.T[i] => T_i)
            push!(guess, getproperty(ch, Symbol(:thermal_left, i)).T => T_i + 5.0)
            push!(guess, getproperty(ch, Symbol(:thermal_right, i)).T => T_i + 5.0)
            append!(guess, [fuel.T[i, j] => T_i + 10.0 for j in 1:nx])
        end
    end

    callbacks = CallbackSet(
        flapper_callback(ssys, ssys.flapper),
        trip_callback(ssys, ssys.flywheel.inlet.ṁ, case.trip_fraction * ṁ_design, ctrl),
    )
    trip = Pair{Any,Any}[
        ssys.pump.dP_pump => 0.0,
        ssys.pk.rho_c_fn => ctrl,
        ssys.flapper.T_open => Inf,
    ]
    channels = NamedTuple{keys(case.types)}(
        Tuple(
            getproperty(getproperty(ssys, Symbol(:rods_, k)), Symbol(:ch_, k)) for
            k in keys(case.types)
        ),
    )
    return (
        ssys=ssys,
        guess=guess,
        trip=trip,
        callbacks=callbacks,
        design_ṁ=ṁ_design,
        channels=channels,
        pipes=NamedTuple{keys(case.types)}(Tuple(pipes)),
        n_before=length(unknowns(full)),
    )
end

"""
    solve_pool_lofa_steady(model, case) -> NonlinearSolution

Settle a [`build_pool_lofa`](@ref) model at full flow and full power, and check that it
landed on the forced-flow root.

The pump-on steady state also has a root with no flow through the core. The solve integrates
to rest from `model.guess`, which sits in the forced-flow basin, then refuses any result
where an assembly type carries less than half its design flow. A failed or wrong-rooted
steady solve returns numbers that look plausible, so the check is not optional.

# Arguments
- `model`: what `build_pool_lofa` returned
- `case`: the case it was built from

# Returns
The steady solution, ready for `solve_transient(model.ssys, sol, t; overrides=model.trip)`.

# Throws
- `ErrorException`: if the solve fails, or lands off the forced-flow root
"""
function solve_pool_lofa_steady(model, case)
    ssys = model.ssys
    sol = solve_steady(ssys, model.guess; solver=DynamicSS(Rodas5P()))
    if sol.retcode != ReturnCode.Success
        error("the pool LOFA steady solve failed with retcode $(sol.retcode)")
    end
    for (key, ty) in pairs(case.types)
        ch = getproperty(getproperty(ssys, Symbol(:rods_, key)), Symbol(:ch_, key))
        ṁ = sol[ch.inlet.ṁ]
        if !(ṁ > ty.design_ṁ / 2)
            error(
                "the steady solve put $ṁ kg/s through a $key channel against a design " *
                "flow of $(ty.design_ṁ) kg/s, so it did not land on the forced-flow root",
            )
        end
    end
    return sol
end

using STREAM
using STREAM: G_EARTH, PipeGeometry_rectangular, PipeGeometry_circular
using STREAM.Components
using STREAM.Components: Channel
using STREAM.Assemblies
using STREAM.Utilities: cosine_shape
using ModelingToolkit
using OrdinaryDiffEq: CallbackSet, ReturnCode, Rodas5P
using SteadyStateDiffEq: DynamicSS

"""
    build_pool_lofa(ctrl, source; case) -> NamedTuple

A pool-type research reactor with downward forced flow, several assembly types in parallel,
a flapper above the core, and point kinetics, built for a loss-of-flow transient:

    pool → assembly types (down) → plenum → riser (up) → flapper node
         → primary piping → pump → flywheel → pool
    pool → flapper → flapper node

Each type is one representative channel between two half plates, standing for `N` identical
channels through [`weighted`](@ref), behind an inlet orifice. One `PointKinetics` drives every
plate through `pk.P`, the total power, with `source` as its `power_input`.

# Arguments
- `ctrl`: the `ReactivityController` driving the kinetics
- `source`: the kinetics' `power_input`, built with `P0 = 1`

# Keywords
- `case`: a `NamedTuple` of plant data, laid out as in `case.jl`

# Returns
A `NamedTuple` with the compiled system `ssys`, the operating point `guess` for
[`solve_pool_lofa_steady`](@ref), the `trip` overrides and `callbacks` of the transient, the
total `design_ṁ`, each type's `channels` and `pipes`, and `n_before`, the number of unknowns
before `mtkcompile`.
"""
function build_pool_lofa(ctrl, source; case)
    n, nx, L, T_pool = case.n, case.nx, case.L, case.T_pool
    z_bounds = range(0.0, L; length=n + 1)
    pipes = map(ty -> PipeGeometry_rectangular(L, ty.width, ty.gap, ty.heated_width), case.types)

    @named pk = PointKinetics(
        ctrl; power_input=source, Lambda=case.Lambda, beta_k=case.beta_k, lambda_k=case.lambda_k
    )

    type_systems = []
    paths = []
    power_eqs = []
    for (key, ty) in pairs(case.types)
        geom = pipes[key]
        htc = HTC.SubcooledBoiling(
            HTC.RegimeDependent(;
                laminar=HTC.ConstantNusselt(), turbulent=HTC.DittusBoelter(),
                natural=HTC.Elenbaas(geom), geom,
            ),
            HTC.regime_dependent_q_scb(),
        )
        darcy = Friction.RegimeDependent(;
            turbulent=Friction.blasius, k_R=Friction.rectangular_correction(geom.depth / geom.width)
        )
        @named ch = ChannelAndContacts(; n, geometry=geom, g=-G_EARTH, htc, darcy)
        @named fuel = HeatDiffusion(;
            nz=n, nx, Lz=L, Lx=ty.plate_thickness, y=ty.heated_width,
            rho_s=case.rho_s, cp_s=case.cp_s, k_s=case.k_s,
            power_shape=repeat(cosine_shape(z_bounds, ty.ppf) ./ nx, 1, nx), T0=T_pool,
        )
        rods = symmetric_plate(ch, fuel; name=key)
        pool = HeatExchanger(T_pool; name=Symbol(:pool_, key))
        orifice = ResistorFromKnownPoint(;
            name=Symbol(:orifice_, key), dp=-ty.orifice_dp, ṁ=ty.design_ṁ, T=T_pool
        )
        path = weighted(ty.N, pool, orifice, rods.ch; name=key)
        append!(type_systems, [first(path), pool, orifice, rods, last(path)])
        push!(paths, path)
        plate_power = case.P_rated * ty.power_fraction / ty.N
        push!(power_eqs, rods.fuel.power ~ pk.P * plate_power)
    end

    ṁ_design = sum(ty.N * ty.design_ṁ for ty in values(case.types))
    @named pump = Pump(case.dP_pump)
    @named flywheel = Inertia(case.flywheel_L_over_A)
    @named primary = ResistorFromKnownPoint(; dp=-case.primary_dp, ṁ=ṁ_design, T=T_pool)
    @named riser = Channel(; n, geometry=PipeGeometry_circular(case.riser_L, case.riser_D), g=G_EARTH)
    @named pool_flapper = HeatExchanger(T_pool)
    @named flapper = Flapper(;
        open_at_current=case.flapper_open_at, f=case.flapper_f, area=case.flapper_area,
        open_rate=1 / case.flapper_open_time,
    )

    connections = [
        inparallel(flywheel, paths, riser)...,
        inparallel(flywheel, [(pool_flapper, flapper)], primary)...,
        inseries(riser, primary, pump, flywheel)...,
        flywheel.outlet.p ~ case.p_pool,
        watch_flow(flapper, flywheel.inlet.ṁ),
        power_eqs...,
    ]
    full = compose_systems(
        pk, pump, flywheel, primary, riser, pool_flapper, flapper, type_systems...;
        connections, name=:pool_lofa,
    )
    ssys = mtkcompile(full)

    types = NamedTuple{keys(case.types)}(keys(case.types))
    channels = map(k -> getproperty(ssys, k).ch, types)
    guess = [
        ssys.primary.inlet.ṁ => ṁ_design,
        (channels[k].inlet.ṁ => case.types[k].design_ṁ for k in types)...,
    ]
    trip = [ssys.pump.dP_pump => 0.0]
    callbacks = CallbackSet(
        flapper_callback(ssys, ssys.flapper),
        trip_callback(ssys, ssys.flywheel.inlet.ṁ, case.trip_fraction * ṁ_design, ctrl),
    )
    return (;
        ssys, guess, trip, callbacks, design_ṁ=ṁ_design, channels, pipes,
        n_before=length(unknowns(full)),
    )
end

"""
    solve_pool_lofa_steady(model) -> NonlinearSolution

Settle a [`build_pool_lofa`](@ref) model at full flow and full power, ready for
`solve_transient(model.ssys, sol, t; overrides=model.trip, callbacks=model.callbacks)`.

# Throws
- `ErrorException`: if the solve fails
"""
function solve_pool_lofa_steady(model)
    sol = solve_steady(
        model.ssys, model.guess; solver=DynamicSS(Rodas5P()), abstol=1e-10, reltol=1e-10
    )
    sol.retcode == ReturnCode.Success ||
        error("the pool LOFA steady solve failed with retcode $(sol.retcode)")
    return sol
end

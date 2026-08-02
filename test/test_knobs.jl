using Test
using STREAM
using STREAM.Assemblies
using STREAM.Components
using ModelingToolkit
using ModelingToolkit: t_nounits as t, D_nounits as D
using OrdinaryDiffEq
using SteadyStateDiffEq

@testset "design_knob declaration" begin
    outer_d = @design_knob outer_d = 0.02
    @test ModelingToolkit.isparameter(outer_d)
    @test string(outer_d) == "outer_d"
    @test ModelingToolkit.hasdefault(outer_d)
    @test ModelingToolkit.getdefault(outer_d) == 0.02

    @test_throws ArgumentError (@macroexpand @design_knob 0.02)
end

@testset "knob_defaults collects stored defaults" begin
    a = @design_knob a = 1.5
    b = @design_knob b = 0.003
    defs = knob_defaults([a, b])
    @test length(defs) == 2
    @test isequal(defs[1].first, a) && defs[1].second == 1.5
    @test isequal(defs[2].first, b) && defs[2].second == 0.003
end

# A shared knob drives geometry in two composed components and stays a single
# un-namespaced parameter, the cross-component case W7 is built for.
function _knob_fluid(D_in; name)
    @variables Tf(t) qf(t) Twf(t) A(t)
    area = pi * D_in^2 / 4
    dh = D_in
    Re = abs(0.3) * dh / (area * μ(H2O, Tf))
    Pr = cₚ(H2O, Tf) * μ(H2O, Tf) / κ(H2O, Tf)
    h = 0.023 * Re^0.8 * Pr^0.4 * κ(H2O, Tf) / dh
    System([D(Tf) ~ 0.3 * cₚ(H2O, Tf) * (46.85 - Tf) + qf, qf ~ h * area * (Twf - Tf),
            A ~ area], t, [Tf, qf, Twf, A], []; name)
end
function _knob_solid(D_out; name)
    @variables Ts(t) q(t) Tw(t) G(t)
    System([D(Ts) ~ 1500.0 - q, q ~ 100.0 * D_out * (Ts - Tw), G ~ 100.0 * D_out],
           t, [Ts, q, Tw, G], []; name)
end

@testset "shared knob propagates across compose + remake" begin
    outer_d = @design_knob outer_d = 0.02
    @named fluid = _knob_fluid(outer_d)
    @named solid = _knob_solid(outer_d)
    @named root = System([fluid.Twf ~ solid.Tw, fluid.qf ~ solid.q], t, [], [];
                         systems = [fluid, solid])
    ssys = mtkcompile(root)

    # one shared parameter, not fluid.outer_d + solid.outer_d
    ps = parameters(ssys)
    @test length(ps) == 1
    @test string(only(ps)) == "outer_d"

    guesses = Pair[ssys.fluid.Tf => 56.85, ssys.solid.Ts => 86.85, ssys.fluid.Twf => 76.85,
                   ssys.fluid.qf => 1500, ssys.solid.Tw => 76.85, ssys.solid.q => 1500]

    # runs on the declared default with no knob supplied beyond knob_defaults
    op = [knob_defaults([outer_d]); guesses]
    prob = SteadyStateProblem(ssys, op; warn_initialize_determined = false,
                              build_initializeprob = false)
    sol = solve(prob, DynamicSS(Rodas5P()); abstol = 1e-10, reltol = 1e-10)
    @test isapprox(sol[ssys.fluid.A], pi * 0.02^2 / 4; rtol = 1e-9)
    @test isapprox(sol[ssys.solid.G], 100.0 * 0.02; rtol = 1e-9)

    # one remake moves geometry in BOTH components
    sol2 = solve(remake(prob; p = [outer_d => 0.025]), DynamicSS(Rodas5P());
                 abstol = 1e-10, reltol = 1e-10)
    @test isapprox(sol2[ssys.fluid.A], pi * 0.025^2 / 4; rtol = 1e-9)
    @test isapprox(sol2[ssys.solid.G], 100.0 * 0.025; rtol = 1e-9)
end

# Flagship: one knob drives the coolant-channel geometry AND the fuel-plate
# thickness (the same physical dimension) across a coupled CAC + HeatDiffusion
# solve. Scanning it is rebuild-free (the system is compiled once).
@testset "flagship: one knob scans CAC geometry + fuel plate, coupled solve" begin
    nz, nx = 10, 3
    T_in = 40.0
    gap = @design_knob gap = 0.00127
    geom = PipeGeometry_rectangular(0.6, 0.07, gap, 0.07)   # channel gap = knob

    @named pump_l = Pump(3.0e4)
    @named hx_l = HeatExchanger(T_in)
    @named cac_l = ChannelAndContacts(; n=nz, geometry=geom)
    @named pump_r = Pump(3.0e4)
    @named hx_r = HeatExchanger(T_in)
    @named cac_r = ChannelAndContacts(; n=nz, geometry=geom)
    ps = fill(1.0 / (nz * nx), nz, nx)
    @named hd = HeatDiffusion(; nz=nz, nx=nx, Lz=0.6, Lx=gap, y=0.07,   # plate thickness = SAME knob
                              rho_s=2700.0, cp_s=900.0, k_s=200.0, power_shape=ps, power=1e4)

    conns = [
        inseries(pump_l, hx_l, cac_l, pump_l)...,
        pump_l.inlet.p ~ 1.0e5,
        inseries(pump_r, hx_r, cac_r, pump_r)...,
        pump_r.inlet.p ~ 1.0e5,
        connect_faces((hd, :thermal_left) => (cac_l, :thermal_right))...,
        connect_faces((hd, :thermal_right) => (cac_r, :thermal_left))...,
        hd.power ~ 1e4,
    ]
    @named sys = compose(System(conns, t; name=:knob_mtr),
                         pump_l, hx_l, cac_l, pump_r, hx_r, cac_r, hd)
    ssys = mtkcompile(sys; fully_determined=true)

    # the gap is one shared knob across both channels and the plate
    @test count(p -> occursin("gap", string(p)), parameters(ssys)) == 1

    T_w = 41.85
    baseop(gv) = vcat(
        Pair[gap => gv],
        [ssys.hd.T[i, j] => T_w for i in 1:nz for j in 1:nx],
        [ssys.cac_l.T[i] => T_w for i in 1:nz],
        [ssys.cac_r.T[i] => T_w for i in 1:nz],
        Pair[ssys.cac_l.inlet.ṁ => +0.250, ssys.cac_r.inlet.ṁ => +0.250],
    )

    s0 = solve_steady(ssys, baseop(0.00127))   # default gap
    s1 = solve_steady(ssys, baseop(0.00090))   # narrower gap, no rebuild
    @test string(s0.retcode) == "Success"
    @test string(s1.retcode) == "Success"

    # One knob moves the coolant outlet AND the fuel-plate temperature, in a direction
    # set by the physics. Narrowing the channel gap raises hydraulic resistance, so at
    # the fixed pump head (3e4 Pa) the steady mass flow drops (the supplied ṁ is only
    # an IC guess; the real flow comes out of the pump/friction balance). The plate still
    # dumps the same total power into the coolant, so a smaller ṁ means a larger coolant
    # temperature rise: T_out goes UP. The plate, cooled by hotter coolant across a higher
    # wall resistance, also gets hotter. Both deltas are positive.
    T_out0 = s0[ssys.cac_l.T_out]
    T_out1 = s1[ssys.cac_l.T_out]
    @test isfinite(T_out0) && isfinite(T_out1)

    # Direction: narrower gap -> hotter outlet and hotter plate.
    @test T_out1 > T_out0
    @test s1[ssys.hd.T[5, 2]] > s0[ssys.hd.T[5, 2]]

    # Magnitude is fixed by a per-channel energy balance, not a hand-picked number.
    # Every watt the wall puts into the coolant must show up as enthalpy rise, so
    #     T_out - T_in == Q_wall_total / (ṁ * cp)
    # with T_in the heat-exchanger setpoint, Q_wall_total the solved per-channel wall heat,
    # and ṁ the solved flow. Both Q_wall_total and ṁ are read back from the solution,
    # so this ties the thermal answer to the hydraulic one. The only slack is cp's mild
    # temperature dependence across the channel, which the 2% tolerance covers (the raw
    # residual is ~1e-5).
    for s in (s0, s1)
        Q_ch = s[ssys.cac_l.Q_wall_total]
        ṁ = s[ssys.cac_l.inlet.ṁ]
        T_out = s[ssys.cac_l.T_out]
        cp = cₚ(H2O, (T_in + T_out) / 2)
        @test isapprox(T_out - T_in, Q_ch / (ṁ * cp); rtol=0.02)
    end

    # Sanity-bound the throttling mechanism: the wall load splits evenly between the two
    # channels (each carries half the 1e4 W plate power), and the narrower gap really did
    # cut the flow, which is why the outlet climbed several K rather than wobbling at the
    # rounding level.
    @test isapprox(s0[ssys.cac_l.Q_wall_total], 5e3; rtol=1e-3)
    @test isapprox(s1[ssys.cac_l.Q_wall_total], 5e3; rtol=1e-3)
    @test s1[ssys.cac_l.inlet.ṁ] < s0[ssys.cac_l.inlet.ṁ]
    @test (T_out1 - T_out0) > 1.0
    @test (T_out1 - T_out0) < 15.0
end
